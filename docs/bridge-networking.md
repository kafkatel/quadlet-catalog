# Bridge Networking for Infrastructure Containers

This guide covers setting up Linux bridge networking to give Podman containers their own IP addresses on the host's LAN. This is required for infrastructure services (IdM, Satellite, Capsule) that need to be first-class network citizens with dedicated IPs.

## Overview

Standard Podman networking (`bridge` mode with port publishing) gives containers private IPs in a container-only subnet (e.g., `10.88.0.0/16`). The host uses NAT to forward published ports to the container. This works for most applications but doesn't work for services like FreeIPA that:

- Need to be reachable by hostname on the LAN (DNS delegation, Kerberos realm)
- Bind multiple ports that clients discover dynamically (LDAP SRV records, DNS, Kerberos)
- Require bidirectional host ↔ container communication (host joins the IdM domain)

**Bridge networking solves this** by connecting the container directly to the host's physical network. The container gets a real IP on the same subnet as the host, reachable by both the host and remote machines.

## Why Unmanaged Bridge (Not macvlan or host Networking)?

| Approach | Container Gets Own IP? | Host Can Reach Container? | Remote Machines Can Reach? | Notes |
|----------|----------------------|--------------------------|---------------------------|-------|
| **Unmanaged bridge** | ✅ Yes | ✅ Yes | ✅ Yes | **Recommended.** Container is a first-class network client. |
| macvlan | ✅ Yes | ❌ No | ✅ Yes | Linux kernel limitation — host-to-container traffic is blocked. Workaround requires giving the host a second IP on a shim interface. |
| ipvlan | ✅ Yes | ❌ No | ✅ Yes | Same limitation as macvlan. |
| host networking | ❌ No | N/A (shares network stack) | N/A | Container binds ports directly to host. No network isolation. |
| Standard bridge (NAT) | ❌ No (private 10.x IP) | ✅ Yes | ⚠️ Via published ports only | Default Podman behavior — works for most apps but not infrastructure. |

**The unmanaged bridge approach gives containers a real LAN IP while maintaining full host ↔ container ↔ remote connectivity.**

Sources: [Jamie Montgomerie's blog](https://www.blog.montgomerie.net/posts/2025-10-18-giving-a-rootful-podman-container-its-own-ip/), [Podman networking tutorial](https://github.com/containers/podman/blob/main/docs/tutorials/basic_networking.md), [RHEL 9 container networking](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/building_running_and_managing_containers/assembly_setting-container-network-modes_building-running-and-managing-containers)

## Three-Layer Setup

Bridge networking for containers requires three layers:

```
┌─────────────────────────────────────────────────────────┐
│ Layer 1: Linux Bridge (br0)                            │
│   - Enslaves physical NIC (e.g., eth0)                 │
│   - Host IP moves from eth0 to br0                     │
│   - Acts like a virtual network switch                 │
└─────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────┐
│ Layer 2: Podman Network (unmanaged)                    │
│   - Podman network config referencing br0              │
│   - mode=unmanaged → Podman uses br0 without managing it│
│   - Assigns IPs from the LAN subnet to containers      │
└─────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────┐
│ Layer 3: Quadlet Network File                          │
│   - .network file references the Podman network        │
│   - Containers reference the .network in their files   │
└─────────────────────────────────────────────────────────┘
```

## Layer 1: Linux Bridge Setup

The bridge enslaves your physical NIC and takes over its IP address. Your NIC becomes a "port" on the virtual switch, and the bridge is both the switch AND the host.

### Automated Setup (Recommended)

Use the provided script:

```bash
# Preview changes
sudo scripts/setup-bridge.sh --dry-run

# Create bridge on default interface
sudo scripts/setup-bridge.sh

# Create bridge on specific interface with custom name
sudo scripts/setup-bridge.sh --interface enp1s0 --bridge-name br-lan
```

The script:
- Auto-detects the default route interface if not specified
- Captures all existing IPs, gateway, DNS, and DNS search domains
- Creates the bridge and enslaves the physical NIC
- Migrates all configuration to the bridge
- Validates the bridge is active before exiting
- Prints rollback instructions

### Manual Setup (NetworkManager)

If you prefer manual control or want to customize the configuration:

```bash
# 1. Get current interface and connection name
DEFAULT_IFACE=$(ip -4 route show default | head -1 | awk '{print $5}')
PARENT_CONN=$(nmcli -g connection.id connection show "$DEFAULT_IFACE")

# 2. Capture existing IP configuration
nmcli -t -f ipv4.addresses,ipv4.gateway,ipv4.dns connection show "$PARENT_CONN"
# Note the values -- you'll replicate them on the bridge

# 3. Create the bridge connection
nmcli connection add type bridge \
    con-name br0 \
    ifname br0 \
    ipv4.addresses "192.168.1.10/24" \
    ipv4.gateway "192.168.1.1" \
    ipv4.dns "192.168.1.1" \
    ipv4.method manual \
    ipv6.method disabled \
    bridge.stp yes \
    bridge.priority 32768 \
    connection.autoconnect yes

# 4. Create bridge slave for the physical NIC
nmcli connection add type bridge-slave \
    con-name br0-port1 \
    ifname "$DEFAULT_IFACE" \
    master br0

# 5. Disable autoconnect on the original profile
nmcli connection modify "$PARENT_CONN" connection.autoconnect no

# 6. Activate the bridge (may cause brief SSH disconnection)
nmcli connection up br0

# 7. Deactivate the old profile
nmcli connection down "$PARENT_CONN"

# 8. Verify
nmcli device status | grep br0
ip -4 addr show br0
```

### Manual Setup (systemd-networkd)

If you use systemd-networkd instead of NetworkManager:

Create `/etc/systemd/network/10-br0.netdev`:

```ini
[NetDev]
Name=br0
Kind=bridge
```

Create `/etc/systemd/network/30-br0.network`:

```ini
[Match]
Name=br0

[Network]
Address=192.168.1.10/24
Gateway=192.168.1.1
DNS=192.168.1.1
```

Update your physical interface config (e.g., `/etc/systemd/network/20-eth0.network`):

```ini
[Match]
Name=eth0

[Network]
Bridge=br0
```

Then restart networkd:

```bash
sudo systemctl restart systemd-networkd
```

### Rollback

If something goes wrong:

```bash
# Reactivate original connection
sudo nmcli connection up "<original-connection-name>"

# Delete bridge components
sudo nmcli connection delete br0-port1
sudo nmcli connection delete br0
```

## Layer 2: Podman Network Configuration

Once the Linux bridge exists, create a Podman network that references it with `mode=unmanaged`.

### Podman 5.3+ (CLI)

```bash
sudo podman network create infra-bridge \
    --driver bridge \
    --interface-name br0 \
    --opt mode=unmanaged \
    --subnet 192.168.1.0/24 \
    --gateway 192.168.1.1 \
    --ip-range 192.168.1.100-192.168.1.150 \
    --ipv6 \
    --disable-dns
```

Key options:
- `--interface-name br0` — attach to the existing bridge
- `--opt mode=unmanaged` — Podman uses the bridge but doesn't manage it (won't create or destroy it)
- `--subnet` / `--gateway` — must match the bridge's network
- `--ip-range` — limits which IPs Podman assigns to containers (prevents DHCP/static IP conflicts)
- `--ipv6` — enables IPv6 autoconfiguration from the LAN's router
- `--disable-dns` — containers use the LAN DNS, not Podman's internal DNS

### Podman < 5.3 (Manual JSON Config)

On older Podman versions, the `podman network create` command may reject `mode=unmanaged` due to [a netavark bug](https://github.com/containers/common/issues/2322) (fixed in Podman 5.3). Workaround: create the JSON config file manually.

Create `/etc/containers/networks/infra-bridge.json`:

```json
{
    "name": "infra-bridge",
    "id": "e82ec0a4cab145a1ab06f8e7f6d38d0ee236cc1e1235463fb7ff2503bec6e15e",
    "driver": "bridge",
    "network_interface": "br0",
    "created": "2026-03-19T00:00:00.000000000-00:00",
    "subnets": [
        {
            "subnet": "192.168.1.0/24",
            "gateway": "192.168.1.1",
            "lease_range": {
                "start_ip": "192.168.1.100",
                "end_ip": "192.168.1.150"
            }
        }
    ],
    "ipv6_enabled": true,
    "internal": false,
    "dns_enabled": false,
    "options": {
        "mode": "unmanaged"
    },
    "ipam_options": {
        "driver": "host-local"
    }
}
```

The `id` just needs to be unique — use `uuidgen` or any random hex string.

After creating the file, restart Podman:

```bash
sudo systemctl restart podman
```

Verify:

```bash
sudo podman network ls | grep infra-bridge
```

## Layer 3: Quadlet Network File

Create a `.network` quadlet file that containers can reference.

### Example: `idm-bridge.network`

```ini
# idm-bridge.network
# Quadlet network file for the infrastructure unmanaged bridge network

[Unit]
Description=infrastructure Unmanaged Bridge Network (br0)
Documentation=https://github.com/parmstro/quadlet-catalog/blob/main/docs/bridge-networking.md
After=network-online.target

[Network]
NetworkName=infra-bridge
Driver=bridge
Options=mode=unmanaged
Options=bridge_name=br0
IPv6=true
DisableDNS=true

# Static IP range for container assignment
# Adjust to match your LAN subnet and avoid conflicts with DHCP
Subnet=192.168.1.0/24
Gateway=192.168.1.1
IPRange=192.168.1.100/28

[Install]
WantedBy=multi-user.target
```

**Key settings:**

- `NetworkName=infra-bridge` — this is what containers reference in their `Network=` directives
- `Options=mode=unmanaged` — critical — Podman uses br0 without managing it
- `Options=bridge_name=br0` — the actual Linux bridge device name
- `Subnet` / `Gateway` — must match your LAN
- `IPRange` — subset of the subnet that Podman assigns from (use CIDR notation like `192.168.1.100/28` to limit to .100-.111)
- `DisableDNS=true` — containers use the LAN DNS server, not Podman's internal resolver

### Referencing from Containers

In your `.container` file:

```ini
[Container]
Network=idm-bridge.network
# No PublishPort= -- the container IS on the network
```

Or reference the network directly by name (if you created it via CLI/JSON):

```ini
[Container]
Network=infra-bridge
```

## IPv6 Considerations

The unmanaged bridge approach supports IPv6 autoconfiguration from your LAN's router (via SLAAC). Set `IPv6=true` in the quadlet network file or `--ipv6` in the CLI command.

**macvlan does NOT support IPv6 autoconfig** — it's one of several reasons we chose the unmanaged bridge approach.

## Rootful vs Rootless Podman

**Bridge and macvlan networking require rootful Podman.** Rootless Podman uses `slirp4netns` or `pasta` to provide unprivileged networking, which can't attach to host network interfaces.

infrastructure services should run as system-level services (`/etc/containers/systemd/`, managed with `sudo systemctl`), not user-level.

## Firewall Configuration

When the bridge is active, firewall rules apply to the bridge interface, not the enslaved physical NIC. Update your firewall zones:

```bash
# Move the interface to the appropriate zone
sudo firewall-cmd --zone=public --change-interface=br0 --permanent

# Remove the physical NIC from any zone (it's now enslaved)
sudo firewall-cmd --zone=public --remove-interface=eth0 --permanent

# Reload
sudo firewall-cmd --reload
```

For containers with specific port requirements (like IdM), add firewall rules in the container definition's README.

## Troubleshooting

### Bridge created but container has no IP

Check the Podman network config:

```bash
sudo podman network inspect infra-bridge
```

Verify:
- `"mode": "unmanaged"` is set in `options`
- `"network_interface": "br0"` points to the correct bridge
- The subnet and IP range are correct for your LAN

### Host loses connectivity after bridge activation

The script uses an async activation pattern (activate bridge, then deactivate old profile) to minimize downtime. If connectivity is lost, rollback:

```bash
# From console access (not SSH):
sudo nmcli connection up "<original-connection-name>"
sudo nmcli connection delete br0-port1
sudo nmcli connection delete br0
```

Then investigate the original connection config — the script may have missed a critical setting.

### Container starts but isn't reachable from the LAN

1. Check the container actually got an IP:
   ```bash
   sudo podman exec <container> ip -4 addr show eth0
   ```

2. Verify the IP is in the configured range:
   ```bash
   sudo podman network inspect infra-bridge | grep -A5 lease_range
   ```

3. Check firewall rules on the bridge:
   ```bash
   sudo firewall-cmd --zone=public --list-all
   ```

4. Verify the bridge is forwarding traffic:
   ```bash
   sudo sysctl net.bridge.bridge-nf-call-iptables
   # Should be 0 or 1, not missing
   ```

### SELinux denials

The `:Z` suffix on volume mounts is required on SELinux-enforcing systems. Check for denials:

```bash
sudo ausearch -m AVC -ts recent
```

If denials appear for volume mounts, verify the parent directory has the correct context:

```bash
ls -Zd /srv/containers/
# Expected: system_u:object_r:var_t:s0

# If wrong:
sudo restorecon -Rv /srv/containers/
```

## Quadlet Network File Template

Use this template for infrastructure services. Adjust the subnet, gateway, and IP range to match your LAN.

```ini
# {appname}-bridge.network
# Quadlet network file for infrastructure unmanaged bridge networking

[Unit]
Description={AppName} unmanaged bridge network (br0)
Documentation=https://github.com/parmstro/quadlet-catalog/blob/main/docs/bridge-networking.md
After=network-online.target
Wants=network-online.target

[Network]
# The Podman network name -- containers reference this in Network= directives
NetworkName={appname}-bridge

# Bridge driver with unmanaged mode
Driver=bridge
Options=mode=unmanaged
Options=bridge_name=br0

# Disable Podman's internal DNS -- containers use LAN DNS
DisableDNS=true

# Enable IPv6 autoconfiguration from LAN router
IPv6=true

# Network configuration -- MUST match your LAN subnet
# Adjust these values for your network
Subnet=192.168.1.0/24
Gateway=192.168.1.1

# IP range that Podman assigns to containers
# Use a subset of your LAN subnet that won't conflict with DHCP
# Format: <start-ip>/<cidr-bits> or <start-ip>-<end-ip>
# Example: 192.168.1.100/28 = .100 through .111 (12 IPs)
IPRange=192.168.1.100/28

[Install]
WantedBy=multi-user.target
```

## How It Works

Once the bridge and Podman network are configured:

1. **Physical NIC** (e.g., `eth0`) is enslaved to the bridge — it acts like a cable connecting the bridge to the LAN
2. **Bridge** (`br0`) has your host's IP — it's both a virtual switch and the host's network interface
3. **Podman network** (`infra-bridge`) tells Podman to create virtual ethernet pairs (`veth`) with one end on `br0`
4. **Container** gets a `veth` pair, appears as `eth0` inside the container, with a real LAN IP

The container is now a first-class network citizen, just like a physical machine or VM on your LAN.

## Reference

The `scripts/setup-bridge.sh` script follows the well-established NetworkManager bridge setup pattern:

- Capture existing IP configuration from the active connection profile
- Create bridge and bridge-slave, migrate all addresses
- Validate the bridge is active and carries the expected IPs

This pattern is production-tested across RHEL, Fedora, and CentOS deployments.

## Additional Resources

- [FreeIPA container documentation](https://github.com/freeipa/freeipa-container) — bridge networking requirements
- [Podman networking basics](https://github.com/containers/podman/blob/main/docs/tutorials/basic_networking.md) — macvlan, bridge, slirp4netns comparison
- [Jamie Montgomerie's unmanaged bridge blog](https://www.blog.montgomerie.net/posts/2025-10-18-giving-a-rootful-podman-container-its-own-ip/) — detailed walkthrough
- [RHEL 9 container network modes](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/building_running_and_managing_containers/assembly_setting-container-network-modes_building-running-and-managing-containers) — official Red Hat docs
