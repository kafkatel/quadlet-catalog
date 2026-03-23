# FreeIPA Identity Management (IdM) Primary

[FreeIPA](https://www.freeipa.org/) is an integrated identity and authentication solution for Linux/UNIX environments, providing centralized user management, single sign-on (SSO), certificate management, and DNS. It combines 389 Directory Server (LDAP), MIT Kerberos, Dogtag Certificate System, BIND DNS, and SSSD into a unified platform.

This quadlet deploys a FreeIPA IdM Primary server as a container with its own LAN IP via bridge networking.

## Stack Components

| Service | Image | Description |
|---------|-------|-------------|
| idm | `quay.io/freeipa/freeipa-server:centos-9-stream` | FreeIPA IdM Primary |

## Architecture

This is a standalone container on an unmanaged bridge network, giving it a real IP on the host's LAN.

```
┌─────────────────────────────────────────────────┐
│  Host LAN (192.168.1.0/24)                     │
│                                                 │
│  Host (192.168.1.10) ←─► idm (192.168.1.100)  │
│                           │                     │
│                           └─ br0 (unmanaged)   │
└─────────────────────────────────────────────────┘
```

The container appears as a first-class network citizen with its own IP, reachable from both the host and remote machines on the LAN.

## Quadlet Files

| File | Type | Purpose |
|------|------|---------|
| `idm.container` | Container | FreeIPA IdM Primary |
| `idm-data.volume` | Volume | Persistent data volume |
| `idm-bridge.network` | Network | Unmanaged bridge network definition |
| `idm.env` | Environment | Installer configuration (secrets empty) |

## Prerequisites

- **OS:** RHEL 9, Fedora 38+, or CentOS Stream 9
- **Podman:** 4.4+ (rootful, not rootless)
- **Bridge networking:** The host must have a Linux bridge (`br0`) with the physical NIC enslaved. See [Bridge Networking Setup](#bridge-networking-setup) below.
- **DNS:** The IdM server hostname must resolve (either via external DNS or `/etc/hosts`)
- **Firewall:** Ports 53, 80, 443, 389, 636, 88, 464, 123 must be allowed on the bridge interface

## Bridge Networking Setup

**⚠️ REQUIRED:** IdM requires bridge networking to get its own LAN IP. Standard Podman bridge (NAT) mode won't work.

See the full guide at [docs/bridge-networking.md](../../docs/bridge-networking.md) for detailed instructions.

### Quick Setup

```bash
# Option 1: Automated (recommended)
sudo scripts/setup-bridge.sh --dry-run  # Preview
sudo scripts/setup-bridge.sh            # Execute

# Option 2: Manual
sudo nmcli connection add type bridge con-name br0 ifname br0 \
    ipv4.addresses "192.168.1.10/24" \
    ipv4.gateway "192.168.1.1" \
    ipv4.dns "192.168.1.1" \
    ipv4.method manual \
    ipv6.method disabled \
    bridge.stp yes \
    connection.autoconnect yes

sudo nmcli connection add type bridge-slave con-name br0-port1 \
    ifname eth0 master br0

sudo nmcli connection up br0
```

Replace `192.168.1.10/24`, `192.168.1.1`, and `eth0` with your actual host IP, gateway, and interface.

### Verify Bridge

```bash
nmcli device status | grep br0
# Should show: br0  bridge  connected  br0

ip -4 addr show br0
# Should show your host's IP on br0
```

### Configure the Quadlet Network

Edit `idm-bridge.network` to match your LAN subnet:

```ini
Subnet=192.168.1.0/24
Gateway=192.168.1.1
IPRange=192.168.1.100/28
```

The `IPRange` is the subset of IPs that Podman assigns to containers. Use addresses outside your DHCP range.

## Setup

### 1. Create Host Directories

```bash
sudo mkdir -p /srv/containers/idm/data
```

Using `/srv/containers/` ensures the correct SELinux context (`var_t`) is inherited on Fedora/RHEL systems.

### 2. Configure IdM Settings

Edit `idm.env` with your environment values:

```ini
IPA_SERVER_HOSTNAME=idm1.example.com
IPA_REALM=EXAMPLE.COM
IPA_DOMAIN=example.com
IPA_ADMIN_PASSWORD=YourSecureAdminPassword
IPA_DM_PASSWORD=YourSecureDMPassword
```

**Important:**
- `IPA_SERVER_HOSTNAME` must match the `HostName=` in `idm.container`
- `IPA_REALM` is typically the domain in UPPERCASE
- Admin password is for the `admin` user (day-2 management)
- DM (Directory Manager) password is the LDAP superuser password — keep it secret

### 3. Set Hostname in Container File

Edit `idm.container` line 18:

```ini
HostName=idm1.example.com
```

Replace `idm1.example.com` with your actual FQDN.

### 4. Install Quadlet Files

```bash
# System-level deployment (required for bridge networking)
cd definitions/idm/
sudo cp *.container *.volume *.network *.env /etc/containers/systemd/
sudo systemctl daemon-reload
```

### 5. Configure Firewall

IdM requires these ports:

| Port | Protocol | Service |
|------|----------|---------|
| 53 | TCP/UDP | DNS |
| 80 | TCP | HTTP (web UI, cert enrollment) |
| 443 | TCP | HTTPS (web UI) |
| 389 | TCP | LDAP |
| 636 | TCP | LDAPS |
| 88 | TCP/UDP | Kerberos |
| 464 | TCP/UDP | Kerberos kpasswd |
| 123 | UDP | NTP |

```bash
sudo firewall-cmd --zone=public --add-service=freeipa-4 --permanent
sudo firewall-cmd --reload
```

Or manually add each port if the `freeipa-4` service isn't available:

```bash
sudo firewall-cmd --zone=public --permanent \
    --add-port=53/tcp --add-port=53/udp \
    --add-port=80/tcp --add-port=443/tcp \
    --add-port=389/tcp --add-port=636/tcp \
    --add-port=88/tcp --add-port=88/udp \
    --add-port=464/tcp --add-port=464/udp \
    --add-port=123/udp
sudo firewall-cmd --reload
```

### 6. Start IdM Container

```bash
sudo systemctl start idm.service
```

The first start pulls the image and runs the FreeIPA installer. This takes 5-10 minutes. Monitor progress:

```bash
sudo journalctl -u idm.service -f
```

### 7. FreeIPA Installer Flow

#### Interactive Installation (Default)

If `IPA_UNATTENDED=no` (or not set) in `idm.env`, the installer runs interactively on first start. Attach to the container:

```bash
sudo podman exec -it idm bash
```

The installer prompts will appear. Follow the prompts, providing:
- Server hostname (pre-filled from `IPA_SERVER_HOSTNAME`)
- Domain and realm
- Directory Manager password
- Admin password
- DNS forwarders (or `--no-forwarders`)
- NTP servers (or `--no-ntp`)

Once the installer completes, exit the container. The services are running.

#### Unattended Installation

For automated installation, edit `idm.container` and uncomment the `Exec=` lines (or set `IPA_UNATTENDED=yes` in `idm.env` and the container image supports it):

```ini
Exec=ipa-server-install \
  --realm=${IPA_REALM} \
  --domain=${IPA_DOMAIN} \
  --ds-password=${IPA_DM_PASSWORD} \
  --admin-password=${IPA_ADMIN_PASSWORD} \
  --setup-dns \
  --no-forwarders \
  --no-ntp \
  --unattended
```

The installer runs automatically on first start, using values from `idm.env`.

### 8. Verify

```bash
# Check the container is running
sudo podman ps --filter name=idm

# Check services inside the container
sudo podman exec idm ipactl status

# Test Kerberos from the host
kinit admin
# Enter the admin password -- should succeed

# Access the web UI
# Open https://<idm-hostname>/ in a browser
# Accept the self-signed certificate warning (or install the CA cert)
# Log in as 'admin' with the admin password
```

## Day-2 Operations

### Enrolling IdM Clients

On client machines that should join the IdM domain:

```bash
# Install the client
sudo dnf install ipa-client

# Enroll
sudo ipa-client-install --server=idm1.example.com --domain=example.com --realm=EXAMPLE.COM
```

The client will auto-discover SRV records if your DNS is configured correctly.

### Managing Users and Groups

```bash
# From the host (after kinit admin):
ipa user-add jdoe --first=John --last=Doe --email=jdoe@example.com
ipa passwd jdoe

# Add to a group
ipa group-add-member admins --users=jdoe

# List users
ipa user-find
```

Or use the web UI at `https://<idm-hostname>/ipa/ui/`.

### Stopping and Starting

```bash
# Stop
sudo systemctl stop idm.service

# Start
sudo systemctl start idm.service

# Enable on boot
sudo systemctl enable idm.service

# Disable
sudo systemctl disable idm.service
```

### Viewing Logs

```bash
# Systemd journal
sudo journalctl -u idm.service -f

# Logs inside the container
sudo podman exec idm journalctl -xe
```

### Backing Up IdM Data

The entire IdM configuration is in `/srv/containers/idm/data/`. Back it up:

```bash
# Stop the container first
sudo systemctl stop idm.service

# Backup
sudo tar czf idm-backup-$(date +%Y%m%d).tar.gz -C /srv/containers/idm data/

# Restart
sudo systemctl start idm.service
```

### Restoring from Backup

```bash
# Stop the container
sudo systemctl stop idm.service

# Remove current data
sudo rm -rf /srv/containers/idm/data

# Restore
sudo tar xzf idm-backup-YYYYMMDD.tar.gz -C /srv/containers/idm/

# Restart
sudo systemctl start idm.service
```

## Data Persistence

| Host Path | Container Mount | Purpose |
|-----------|----------------|---------|
| `/srv/containers/idm/data` | `/data` | Complete IdM state: LDAP DB, Kerberos KDC, certificates, DNS zones, configuration |

## Port Reference

These ports are bound by FreeIPA inside the container. Since the container is on the LAN via bridge networking, these ports are directly accessible:

| Port | Protocol | Service | Notes |
|------|----------|---------|-------|
| 53 | TCP/UDP | DNS | Primary DNS for the IdM domain |
| 80 | TCP | HTTP | Web UI, certificate enrollment (redirects to 443) |
| 443 | TCP | HTTPS | Web UI (IPA management interface) |
| 389 | TCP | LDAP | Unencrypted LDAP |
| 636 | TCP | LDAPS | LDAP over TLS |
| 88 | TCP/UDP | Kerberos KDC | Key Distribution Center |
| 464 | TCP/UDP | kpasswd | Kerberos password change |
| 123 | UDP | NTP | Network Time Protocol (if NTP enabled) |

## Alternative Image Tags

The quadlet defaults to `centos-9-stream` (stable, closest to RHEL). Alternative tags:

| Tag | Base | Use When |
|-----|------|----------|
| `centos-9-stream` | CentOS Stream 9 | **Default** — production-like, stable |
| `fedora-rawhide` | Fedora Rawhide | Bleeding edge, latest FreeIPA features |
| `fedora-39` | Fedora 39 | Specific Fedora version |
| `almalinux-9` | AlmaLinux 9 | RHEL-like alternative to CentOS Stream |

To change tags, edit line 17 in `idm.container`:

```ini
Image=quay.io/freeipa/freeipa-server:fedora-rawhide
```

See [freeipa-server tags on Quay](https://quay.io/repository/freeipa/freeipa-server?tab=tags) for all available options.

## Running the Container Without Quadlet (Testing)

For quick testing before deploying via systemd:

```bash
sudo podman run --name idm-test \
    --hostname idm1.example.com \
    --network infra-bridge \
    --dns 127.0.0.1 \
    --read-only \
    -v /srv/containers/idm/data:/data:Z \
    -e IPA_SERVER_HOSTNAME=idm1.example.com \
    quay.io/freeipa/freeipa-server:centos-9-stream
```

This is equivalent to the quadlet deployment. Use it to verify the bridge network and FreeIPA installer work before committing to systemd.

## Troubleshooting

### Container fails to start with "hostname not set"

The hostname must be set via `HostName=` in the container file OR the `IPA_SERVER_HOSTNAME` environment variable. Verify:

```bash
sudo podman inspect idm | grep -i hostname
```

### Installer fails with "Unable to resolve host name"

The hostname must resolve via DNS before the installer runs. Either:
1. Add the hostname to your external DNS (recommended)
2. Add it to the host's `/etc/hosts`:
   ```bash
   echo "192.168.1.100 idm1.example.com idm1" | sudo tee -a /etc/hosts
   ```

### "kinit: Cannot contact any KDC" from the host

The host can't reach the IdM Kerberos server. Verify:
1. Container is running: `sudo podman ps --filter name=idm`
2. Container has the expected IP: `sudo podman inspect idm | grep IPAddress`
3. Firewall allows port 88: `sudo firewall-cmd --list-ports | grep 88`
4. `/etc/krb5.conf` on the host points to the right realm and KDC

### Web UI inaccessible

Check:
1. Container is running
2. Port 443 is reachable: `curl -k https://<idm-ip>/`
3. Firewall allows HTTPS traffic
4. Your browser's network can reach the bridge subnet

## Security Considerations

- **Directory Manager password** (`IPA_DM_PASSWORD`) is the LDAP superuser — treat like a root password
- **Read-only root filesystem** — the container's root is read-only; only `/data` is writable
- **SELinux** — the `:Z` volume suffix ensures proper labeling on enforcing systems
- **Certificates** — FreeIPA generates a self-signed CA on first run. For production, integrate with an existing CA or deploy custom certs.

## References

- [FreeIPA Documentation](https://www.freeipa.org/page/Documentation)
- [FreeIPA Container README](https://github.com/freeipa/freeipa-container)
- [FreeIPA Docker Hub](https://hub.docker.com/r/freeipa/freeipa-server/)
- [Bridge Networking Guide](../../docs/bridge-networking.md)
- [Podman Quadlet Documentation](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html)
