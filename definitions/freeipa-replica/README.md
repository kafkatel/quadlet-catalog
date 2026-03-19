# FreeIPA Replica

A containerized [FreeIPA](https://www.freeipa.org/) Identity Management replica, managed as a systemd quadlet. Supports two networking modes: port publishing to a secondary IP (works anywhere) or direct attachment to a host bridge for full L2 LAN access.

## Architecture

- **Standalone container** (no pod)
- FreeIPA runs its own systemd internally, requiring elevated privileges (`spc_t` SELinux type, `SYS_ADMIN` capability)
- All persistent state lives in a named volume mounted at `/data`
- First start performs `ipa-replica-install`; subsequent starts resume from stored state

## Prerequisites

### 1. FreeIPA Primary Server

A running FreeIPA primary must be reachable and fully configured before deploying the replica.

### 2. Network Identity

The replica needs its own IP address and FQDN. Two approaches:

**Port publishing mode** (default): Add a secondary IP to the host interface.

```bash
nmcli connection modify enp0s25 +ipv4.addresses "192.168.137.10/24"
nmcli connection up enp0s25
```

**Bridge mode**: Attach to a host bridge (`br0`) with a dedicated IP. See `freeipa-replica-bridge.network` and the container file comments.

### 3. DNS Records

Add forward and reverse records in the IdM primary:

```bash
ipa dnsrecord-add example.com idm-replica --a-rec=192.168.137.10
ipa dnsrecord-add 137.168.192.in-addr.arpa 10 --ptr-rec=idm-replica.example.com.
```

### 4. Firewall

```bash
firewall-cmd --permanent --add-service=freeipa-4
firewall-cmd --permanent --add-service=freeipa-ldap
firewall-cmd --permanent --add-service=freeipa-ldaps
firewall-cmd --permanent --add-service=dns
firewall-cmd --reload
```

## Configuration

Copy the environment file and set the admin password:

```bash
cp freeipa-replica.env /etc/containers/systemd/freeipa-replica.env
vi /etc/containers/systemd/freeipa-replica.env
# Set PASSWORD= to the IPA admin password (needed for initial replica install only)
```

Edit `freeipa-replica.container`:
- Set `HostName=` to your replica's FQDN
- **Port publishing mode**: Update the IP in each `PublishPort=` line
- **Bridge mode**: Uncomment `Network=` and `IP=`, comment out all `PublishPort=` lines

Review `IPA_SERVER_INSTALL_OPTS` in the env file and adjust the primary server hostname, domain, realm, and DNS forwarder for your environment.

## Installation

```bash
# System-level (root)
sudo cp freeipa-replica.container freeipa-replica-data.volume freeipa-replica.env \
    /etc/containers/systemd/

# If using bridge mode, also copy the network file:
# sudo cp freeipa-replica-bridge.network /etc/containers/systemd/

sudo systemctl daemon-reload
```

## First Start (Replica Installation)

The first start takes several minutes as it runs `ipa-replica-install`:

```bash
sudo systemctl start freeipa-replica.service

# Monitor the installation
sudo podman logs -f freeipa-replica
```

After successful installation, blank the `PASSWORD=` line in the env file.

## Management

```bash
sudo systemctl status freeipa-replica.service
sudo systemctl stop freeipa-replica.service
sudo systemctl enable freeipa-replica.service
sudo journalctl -u freeipa-replica.service -f
```

## Ports

| Port | Protocol | Service |
|------|----------|---------|
| 53 | TCP/UDP | DNS (BIND) |
| 80 | TCP | HTTP redirect |
| 88 | TCP/UDP | Kerberos KDC |
| 389 | TCP | LDAP |
| 443 | TCP | HTTPS (IdM Web UI) |
| 464 | TCP/UDP | Kerberos kpasswd |
| 636 | TCP | LDAPS |

## Volumes

| Volume | Mount Point | Purpose |
|--------|-------------|---------|
| `freeipa-replica-data` | `/data` | All FreeIPA state (LDAP, certs, keytabs, config) |

## Files

| File | Purpose |
|------|---------|
| `freeipa-replica.container` | Container definition with both networking modes |
| `freeipa-replica-bridge.network` | Optional podman network backed by host bridge `br0` |
| `freeipa-replica-data.volume` | Named volume for persistent `/data` |
| `freeipa-replica.env` | Replica install options and admin password |

## Notes

- The container image (`quay.io/freeipa/freeipa-server:rhel9`) bundles 389-ds, MIT KDC, Dogtag CA, BIND, and httpd.
- `SecurityLabelType=spc_t` is required because FreeIPA runs its own systemd instance inside the container.
- `HealthStartPeriod=300s` allows time for the initial replica installation before health checks begin failing.
- The `/sys/fs/cgroup` read-only mount provides cgroup access for the container's internal systemd.
