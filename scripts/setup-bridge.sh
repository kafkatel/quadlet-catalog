#!/usr/bin/env bash
# setup-bridge.sh
# Creates a Linux bridge and migrates all host IPs from the physical NIC to the bridge.
# This enables containers to get their own IPs on the same L2 network as the host.
#
# Supports both DHCP and static IP configurations:
#   - Static: migrates configured addresses to the bridge
#   - DHCP: creates bridge with DHCP, clones the NIC's MAC so reservations still match
#
# DESTRUCTIVE: This script modifies network configuration. Use --dry-run first.

set -euo pipefail

# Defaults
BRIDGE_NAME="br0"
BRIDGE_CONN_NAME="br0"
BRIDGE_SLAVE_CONN_NAME="br0-port1"
PARENT_IFACE=""
DRY_RUN=false
STP_ENABLED="yes"
STP_PRIORITY="32768"

# Usage
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Creates a Linux bridge and migrates all host IPs from the physical NIC.
Supports both DHCP and statically configured interfaces.

OPTIONS:
    --interface <name>      Physical interface to enslave (default: auto-detect from default route)
    --bridge-name <name>    Bridge device name (default: br0)
    --dry-run               Show what would be done without making changes
    --help                  Show this help message

EXAMPLE:
    # Preview changes
    sudo $0 --dry-run

    # Create bridge on default interface
    sudo $0

    # Create bridge on specific interface
    sudo $0 --interface enp1s0 --bridge-name br-lan

ROLLBACK (if something goes wrong):
    sudo nmcli connection up <original-connection-name>
    sudo nmcli connection delete $BRIDGE_SLAVE_CONN_NAME
    sudo nmcli connection delete $BRIDGE_CONN_NAME

EOF
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --interface)
            PARENT_IFACE="$2"
            shift 2
            ;;
        --bridge-name)
            BRIDGE_NAME="$2"
            BRIDGE_CONN_NAME="$2"
            BRIDGE_SLAVE_CONN_NAME="${2}-port1"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Must run as root for nmcli modifications
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: This script must be run as root (use sudo)"
    exit 1
fi

# Check if nmcli is available
if ! command -v nmcli &>/dev/null; then
    echo "ERROR: nmcli not found. Install NetworkManager first."
    exit 1
fi

# Auto-detect parent interface if not provided
if [[ -z "$PARENT_IFACE" ]]; then
    PARENT_IFACE=$(ip -4 route show default | head -1 | awk '{print $5}')
    if [[ -z "$PARENT_IFACE" ]]; then
        echo "ERROR: Could not auto-detect default network interface"
        echo "Please specify --interface <name>"
        exit 1
    fi
    echo "Auto-detected parent interface: $PARENT_IFACE"
fi

# Verify parent interface exists
if ! ip link show "$PARENT_IFACE" &>/dev/null; then
    echo "ERROR: Interface $PARENT_IFACE does not exist"
    exit 1
fi

# Check if bridge already exists and is active (idempotent check)
if nmcli -t -f NAME connection show --active | grep -q "^${BRIDGE_CONN_NAME}$"; then
    echo "Bridge $BRIDGE_CONN_NAME already exists and is active. Nothing to do."
    exit 0
fi

echo "========================================="
echo "Bridge Setup"
echo "========================================="
echo "Bridge name:      $BRIDGE_NAME"
echo "Parent interface: $PARENT_IFACE"
echo "Dry run:          $DRY_RUN"
echo "========================================="
echo

# Get current connection name for parent interface
PARENT_CONN_NAME=$(nmcli -g connection.id connection show "$PARENT_IFACE" 2>/dev/null | tr -d '\n')
if [[ -z "$PARENT_CONN_NAME" ]]; then
    echo "ERROR: No connection profile found for interface $PARENT_IFACE"
    exit 1
fi

echo "Parent connection: $PARENT_CONN_NAME"

# Detect IP method (auto = DHCP, manual = static)
IP_METHOD=$(nmcli -g ipv4.method connection show "$PARENT_CONN_NAME")
echo "IP method:         $IP_METHOD"
echo

# Capture existing IP configuration
echo "Capturing IP configuration..."

if [[ "$IP_METHOD" == "manual" ]]; then
    # Static: read from connection profile config fields
    PARENT_CONFIG=$(nmcli -t -f ipv4.addresses,ipv4.gateway,ipv4.dns,ipv4.dns-search connection show "$PARENT_CONN_NAME")

    ADDRESSES=$(echo "$PARENT_CONFIG" | grep '^ipv4.addresses:' | sed 's/^ipv4.addresses://g' | tr -d ' ' | grep -v '^$' || true)
    GATEWAY=$(echo "$PARENT_CONFIG" | grep '^ipv4.gateway:' | sed 's/^ipv4.gateway://g' | tr -d ' ' | grep -v '^$\|^--$' || true)
    DNS_SERVERS=$(echo "$PARENT_CONFIG" | grep '^ipv4.dns:' | sed 's/^ipv4.dns://g' | tr -d ' ' | grep -v '^$\|^--$' || true)
    DNS_SEARCH=$(echo "$PARENT_CONFIG" | grep '^ipv4.dns-search:' | sed 's/^ipv4.dns-search://g' | tr -d ' ' | grep -v '^$\|^--$' || true)

    if [[ -z "$ADDRESSES" ]]; then
        echo "ERROR: No IPv4 addresses found in static connection profile"
        echo "Refusing to create an addressless bridge"
        exit 1
    fi

    echo "Mode:     static (migrating configured addresses)"
    echo "Addresses: $ADDRESSES"
    echo "Gateway:   ${GATEWAY:-<none>}"
    echo "DNS:       ${DNS_SERVERS:-<none>}"
    echo "Search:    ${DNS_SEARCH:-<none>}"
else
    # DHCP (auto): read active runtime values for display, but bridge will use DHCP too
    ACTIVE_CONFIG=$(nmcli -t -f IP4.ADDRESS,IP4.GATEWAY,IP4.DNS connection show "$PARENT_CONN_NAME")

    ACTIVE_ADDR=$(echo "$ACTIVE_CONFIG" | grep '^IP4.ADDRESS' | sed 's/^IP4.ADDRESS\[[0-9]*\]://g' | tr -d ' ' | head -1)
    ACTIVE_GW=$(echo "$ACTIVE_CONFIG" | grep '^IP4.GATEWAY' | sed 's/^IP4.GATEWAY://g' | tr -d ' ' | head -1)
    ACTIVE_DNS=$(echo "$ACTIVE_CONFIG" | grep '^IP4.DNS' | sed 's/^IP4.DNS\[[0-9]*\]://g' | tr -d ' ' | paste -sd',' -)

    # Get the MAC address of the physical NIC to clone onto the bridge
    # This preserves DHCP reservations that are bound to the NIC's MAC
    PARENT_MAC=$(nmcli -g GENERAL.HWADDR device show "$PARENT_IFACE" | tr -d '\\')

    if [[ -z "$ACTIVE_ADDR" ]]; then
        echo "ERROR: No active IPv4 address on $PARENT_IFACE"
        echo "Interface may not have a DHCP lease yet"
        exit 1
    fi

    echo "Mode:       DHCP (bridge will also use DHCP)"
    echo "Current IP: $ACTIVE_ADDR (will be reassigned by DHCP)"
    echo "Gateway:    ${ACTIVE_GW:-<none>}"
    echo "DNS:        ${ACTIVE_DNS:-<none>}"
    echo "NIC MAC:    $PARENT_MAC (will be cloned to bridge)"
fi

echo

if [[ "$DRY_RUN" == "true" ]]; then
    echo "DRY RUN: Would execute the following:"
    echo

    if [[ "$IP_METHOD" == "manual" ]]; then
        echo "1. Create bridge connection (static):"
        echo "   nmcli connection add type bridge con-name $BRIDGE_CONN_NAME ifname $BRIDGE_NAME \\"
        echo "     ipv4.addresses \"$ADDRESSES\" \\"
        [[ -n "${GATEWAY:-}" ]] && echo "     ipv4.gateway $GATEWAY \\"
        [[ -n "${DNS_SERVERS:-}" ]] && echo "     ipv4.dns \"$DNS_SERVERS\" \\"
        [[ -n "${DNS_SEARCH:-}" ]] && echo "     ipv4.dns-search \"$DNS_SEARCH\" \\"
        echo "     ipv4.method manual \\"
        echo "     bridge.stp $STP_ENABLED \\"
        echo "     bridge.priority $STP_PRIORITY \\"
        echo "     connection.autoconnect yes"
    else
        echo "1. Create bridge connection (DHCP, MAC cloned from $PARENT_IFACE):"
        echo "   nmcli connection add type bridge con-name $BRIDGE_CONN_NAME ifname $BRIDGE_NAME \\"
        echo "     ipv4.method auto \\"
        echo "     ethernet.cloned-mac-address $PARENT_MAC \\"
        echo "     bridge.stp $STP_ENABLED \\"
        echo "     bridge.priority $STP_PRIORITY \\"
        echo "     connection.autoconnect yes"
    fi

    echo
    echo "2. Create bridge slave for $PARENT_IFACE:"
    echo "   nmcli connection add type bridge-slave con-name $BRIDGE_SLAVE_CONN_NAME ifname $PARENT_IFACE master $BRIDGE_CONN_NAME"
    echo
    echo "3. Disable autoconnect on original profile:"
    echo "   nmcli connection modify \"$PARENT_CONN_NAME\" connection.autoconnect no"
    echo
    echo "4. Activate bridge:"
    echo "   nmcli connection up $BRIDGE_CONN_NAME"
    echo
    echo "5. Deactivate original profile:"
    echo "   nmcli connection down \"$PARENT_CONN_NAME\""
    echo
    echo "6. Verify bridge is active and has IP"
    echo
    echo "Run without --dry-run to apply changes."
    exit 0
fi

# Execute the bridge setup
if [[ "$IP_METHOD" == "manual" ]]; then
    echo "Creating bridge connection (static)..."
    nmcli connection add type bridge con-name "$BRIDGE_CONN_NAME" ifname "$BRIDGE_NAME" \
        ipv4.addresses "$ADDRESSES" \
        ${GATEWAY:+ipv4.gateway "$GATEWAY"} \
        ${DNS_SERVERS:+ipv4.dns "$DNS_SERVERS"} \
        ${DNS_SEARCH:+ipv4.dns-search "$DNS_SEARCH"} \
        ipv4.method manual \
        ipv6.method disabled \
        bridge.stp "$STP_ENABLED" \
        bridge.priority "$STP_PRIORITY" \
        connection.autoconnect yes
else
    echo "Creating bridge connection (DHCP, MAC cloned from $PARENT_IFACE)..."
    nmcli connection add type bridge con-name "$BRIDGE_CONN_NAME" ifname "$BRIDGE_NAME" \
        ipv4.method auto \
        ethernet.cloned-mac-address "$PARENT_MAC" \
        bridge.stp "$STP_ENABLED" \
        bridge.priority "$STP_PRIORITY" \
        connection.autoconnect yes
fi

echo "Creating bridge slave for $PARENT_IFACE..."
nmcli connection add type bridge-slave con-name "$BRIDGE_SLAVE_CONN_NAME" \
    ifname "$PARENT_IFACE" \
    master "$BRIDGE_CONN_NAME"

echo "Disabling autoconnect on original connection profile..."
nmcli connection modify "$PARENT_CONN_NAME" connection.autoconnect no

echo "Activating bridge..."
echo "WARNING: If you're connected via SSH, this may cause a brief disconnection."
nmcli connection up "$BRIDGE_CONN_NAME"

# Wait for bridge to come up and (if DHCP) obtain a lease
sleep 5

echo "Deactivating original standalone profile..."
if ! nmcli connection down "$PARENT_CONN_NAME" 2>/dev/null; then
    # Profile might already be inactive -- this is OK
    echo "(Profile was already inactive)"
fi

echo
echo "Verifying bridge is active..."
if ! nmcli -t -f DEVICE,STATE device status | grep -q "^${BRIDGE_NAME}:connected$"; then
    echo "ERROR: Bridge $BRIDGE_NAME is not in connected state"
    echo "Check: nmcli device status"
    exit 1
fi

echo "Verifying bridge has an IP address..."
BRIDGE_IPS=$(ip -4 addr show "$BRIDGE_NAME" 2>/dev/null || true)
if ! echo "$BRIDGE_IPS" | grep -q "inet "; then
    echo "ERROR: No IPv4 address on $BRIDGE_NAME"
    if [[ "$IP_METHOD" != "manual" ]]; then
        echo "DHCP lease may not have been obtained yet. Wait and check:"
        echo "  ip -4 addr show $BRIDGE_NAME"
    fi
    exit 1
fi

# For static, verify the specific addresses were migrated
if [[ "$IP_METHOD" == "manual" ]]; then
    echo "Verifying migrated addresses..."
    IFS=',' read -ra ADDR_ARRAY <<< "$ADDRESSES"
    for addr in "${ADDR_ARRAY[@]}"; do
        addr_ip=$(echo "$addr" | cut -d'/' -f1 | tr -d ' ')
        if ! echo "$BRIDGE_IPS" | grep -q "$addr_ip"; then
            echo "ERROR: Expected IP $addr_ip not found on $BRIDGE_NAME"
            echo "Check: ip -4 addr show $BRIDGE_NAME"
            exit 1
        fi
    done
    echo "All ${#ADDR_ARRAY[@]} address(es) verified on bridge"
fi

# Show final state
FINAL_ADDR=$(ip -4 addr show "$BRIDGE_NAME" | grep 'inet ' | awk '{print $2}' | paste -sd', ' -)

echo
echo "========================================="
echo "Bridge setup complete!"
echo "========================================="
echo "Bridge:    $BRIDGE_NAME ($BRIDGE_CONN_NAME)"
echo "Interface: $PARENT_IFACE (enslaved)"
echo "Mode:      $IP_METHOD"
echo "Addresses: $FINAL_ADDR"
echo
echo "ROLLBACK INSTRUCTIONS (if needed):"
echo "  sudo nmcli connection up \"$PARENT_CONN_NAME\""
echo "  sudo nmcli connection delete \"$BRIDGE_SLAVE_CONN_NAME\""
echo "  sudo nmcli connection delete \"$BRIDGE_CONN_NAME\""
echo
