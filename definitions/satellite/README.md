# Red Hat Satellite Server (Experimental)

⚠️ **EXPERIMENTAL/LAB-ONLY:** This is not an official Red Hat Satellite container deployment method. No official Satellite container images exist as of Satellite 6.18. Red Hat Satellite 6.19 (target: May 2026) will ship containerized Capsules; full Satellite containerization is not yet announced.

This definition creates a UBI-init systemd container where the operator runs `satellite-installer` manually after the container starts. It's suitable for lab environments and testing but is NOT supported for production use. For production deployments, use a full RHEL installation with the [parmstro/rhis-builder-satellite](https://github.com/parmstro/rhis-builder-satellite) Ansible playbooks.

---

[Red Hat Satellite](https://www.redhat.com/en/technologies/management/satellite) is a systems management platform that provides content management, provisioning, configuration management, and subscription management for Red Hat Enterprise Linux deployments.

This quadlet deploys Satellite as a systemd container with its own LAN IP via bridge networking.

## Stack Components

| Service | Image | Description |
|---------|-------|-------------|
| satellite | `localhost/satellite:latest` (locally built) | Red Hat Satellite Server |

## Architecture

Standalone systemd container on an unmanaged bridge network. Satellite runs systemd as PID 1, managing all internal services (PostgreSQL, Apache, Pulp, Candlepin, Foreman) inside the container.

```
┌──────────────────────────────────────────────────┐
│  Host LAN (192.168.1.0/24)                      │
│                                                  │
│  Host ←─► satellite (192.168.1.101)            │
│            └─ systemd (PID 1)                   │
│               ├─ PostgreSQL                     │
│               ├─ Apache (httpd)                 │
│               ├─ Pulp                           │
│               ├─ Candlepin                      │
│               ├─ Foreman                        │
│               └─ Smart Proxy                    │
└──────────────────────────────────────────────────┘
```

## Quadlet Files

| File | Type | Purpose |
|------|------|---------|
| `Containerfile` | Build | UBI-init + satellite-installer |
| `satellite.build` | Build | Image build configuration |
| `satellite.container` | Container | Satellite server |
| `satellite-bridge.network` | Network | Unmanaged bridge network |
| `satellite-*.volume` | Volume | 8 separate volumes for persistence |
| `satellite.env` | Environment | Configuration (secrets empty) |

## Prerequisites

- **OS:** RHEL 9, Fedora 38+, or CentOS Stream 9
- **Podman:** 4.4+ (rootful, not rootless)
- **Resources:**
  - **RAM:** 20 GB minimum, 32 GB recommended
  - **CPU:** 4 cores minimum
  - **Disk:** 200 GB minimum (content storage grows with synced repositories)
- **Bridge networking:** Host must have br0 configured. See [docs/bridge-networking.md](../../docs/bridge-networking.md).
- **Red Hat subscription:** Required for Satellite packages and content CDN access
- **IdM (optional but recommended):** Satellite typically integrates with IdM for DNS and Kerberos

## Setup

### 1. Bridge Networking

Satellite requires bridge networking. See [docs/bridge-networking.md](../../docs/bridge-networking.md) for complete instructions.

Quick check:

```bash
nmcli device status | grep br0
# Should show: br0  bridge  connected
```

### 2. Register the Build Host to Red Hat CDN

The Containerfile needs Red Hat packages. Register your build host (where you run `podman build`):

```bash
# Register to CDN
sudo subscription-manager register --username <your-rh-username>

# Attach a subscription
sudo subscription-manager attach --auto

# Enable Satellite repositories
sudo subscription-manager repos --enable=satellite-6.18-for-rhel-9-x86_64-rpms
sudo subscription-manager repos --enable=satellite-maintenance-6.18-for-rhel-9-x86_64-rpms
```

Alternatively, if you have an existing Satellite, register to it instead.

### 3. Create Host Directories

```bash
sudo mkdir -p /srv/containers/satellite/{pulp,pgsql,foreman,foreman-proxy,candlepin,puppet-ssl,httpd,log}
```

### 4. Configure Network Subnet

Edit `satellite-bridge.network` to match your LAN:

```ini
Subnet=192.168.1.0/24
Gateway=192.168.1.1
IPRange=192.168.1.100/28
```

### 5. Configure Satellite Settings

Edit `satellite.env` with your environment values:

```ini
SATELLITE_HOSTNAME=satellite1.example.com
SATELLITE_ORGANIZATION=My_Org
SATELLITE_ADMIN_PASSWORD=SecurePassword
RH_CDN_ORG_ID=1234567
RH_CDN_ACTIVATION_KEY=my-activation-key
```

If integrating with IdM:

```ini
SATELLITE_USE_IDM=true
IPA_SERVER=idm1.example.com
IPA_REALM=EXAMPLE.COM
```

### 6. Build the Container Image

```bash
cd definitions/satellite/
sudo podman build -t localhost/satellite:latest -f Containerfile .
```

This installs satellite-installer and prerequisites. Build time: 10-15 minutes.

### 7. Install Quadlet Files

```bash
sudo cp *.build *.container *.network *.volume *.env /etc/containers/systemd/
sudo systemctl daemon-reload
```

### 8. Start the Container

```bash
sudo systemctl start satellite.service
```

The container starts systemd and all the volume mounts. Check status:

```bash
sudo systemctl status satellite.service
sudo podman ps --filter name=satellite
```

### 9. Run satellite-installer

Attach to the container and run the installer:

```bash
sudo podman exec -it satellite bash
```

Inside the container, run the installer:

```bash
# Interactive mode
satellite-installer

# Or unattended mode with IdM integration
satellite-installer \
    --foreman-initial-organization "$SATELLITE_ORGANIZATION" \
    --foreman-initial-location "$SATELLITE_LOCATION" \
    --foreman-initial-admin-password "$SATELLITE_ADMIN_PASSWORD" \
    --foreman-ipa-authentication true \
    --foreman-ipa-host "$IPA_SERVER" \
    --enable-foreman-proxy-plugin-discovery \
    --enable-foreman-proxy-plugin-dhcp \
    --enable-foreman-proxy-plugin-dns \
    --enable-foreman-proxy-plugin-tftp \
    --foreman-proxy-dhcp true \
    --foreman-proxy-dns true \
    --foreman-proxy-tftp true
```

Installer runtime: 20-30 minutes. Watch logs in another terminal:

```bash
sudo podman logs -f satellite
```

### 10. Verify

After the installer completes:

```bash
# Check services inside the container
sudo podman exec satellite systemctl status foreman

# Access the web UI
# Open https://<satellite-hostname>/ in a browser
# Log in as 'admin' with SATELLITE_ADMIN_PASSWORD
```

## Day-2 Operations

### Restarting Satellite

```bash
sudo systemctl restart satellite.service
```

All services restart inside the container.

### Running Hammer CLI

```bash
# From the host (after configuring hammer credentials)
sudo podman exec satellite hammer --help

# Or enter the container
sudo podman exec -it satellite bash
hammer organization list
```

### Syncing Content

Content sync is typically configured via the Satellite web UI or Ansible playbooks. For manual sync:

```bash
sudo podman exec satellite hammer repository synchronize --id <repo-id>
```

For comprehensive content configuration, use the [parmstro/rhis-builder-satellite](https://github.com/parmstro/rhis-builder-satellite) Ansible playbooks from inside the container.

### Viewing Logs

```bash
# Systemd journal for the container
sudo journalctl -u satellite.service -f

# Logs inside the container
sudo podman exec satellite journalctl -xe

# Foreman production log
sudo podman exec satellite tail -f /var/log/foreman/production.log

# All persistent logs are in /srv/containers/satellite/log/ on the host
sudo tail -f /srv/containers/satellite/log/foreman/production.log
```

### Backing Up Satellite Data

Stop the container before backing up:

```bash
sudo systemctl stop satellite.service

# Backup all persistent volumes
sudo tar czf satellite-backup-$(date +%Y%m%d).tar.gz -C /srv/containers/satellite .

# Restart
sudo systemctl start satellite.service
```

## Data Persistence

All Satellite state persists across container restarts via host directory bind mounts:

| Host Path | Container Mount | Purpose | Typical Size |
|-----------|----------------|---------|--------------|
| `/srv/containers/satellite/pulp` | `/var/lib/pulp` | Content storage (RPMs, ISOs, container images) | 150-500+ GB |
| `/srv/containers/satellite/pgsql` | `/var/lib/pgsql` | PostgreSQL database | 10-50 GB |
| `/srv/containers/satellite/foreman` | `/etc/foreman` | Foreman configuration | < 100 MB |
| `/srv/containers/satellite/foreman-proxy` | `/etc/foreman-proxy` | Smart Proxy configuration | < 100 MB |
| `/srv/containers/satellite/candlepin` | `/etc/candlepin` | Subscription management config | < 100 MB |
| `/srv/containers/satellite/puppet-ssl` | `/etc/puppetlabs/puppet/ssl` | Puppet SSL certificates | < 100 MB |
| `/srv/containers/satellite/httpd` | `/etc/httpd` | Apache configuration | < 100 MB |
| `/srv/containers/satellite/log` | `/var/log` | All service logs | 1-10 GB |

The bulk of storage (200+ GB) goes to `/var/lib/pulp` for synced content repositories.

## Port Reference

Satellite binds these ports inside the container. Since the container is on the LAN via bridge networking, these ports are directly accessible:

| Port | Protocol | Service | Notes |
|------|----------|---------|-------|
| 80 | TCP | HTTP | Web UI, provisioning templates (redirects to 443) |
| 443 | TCP | HTTPS | Web UI, API, content delivery |
| 5647 | TCP | qpid | Client communication (remote execution) |
| 8140 | TCP | Puppet | Puppet agent check-ins |
| 9090 | TCP | Cockpit | Optional web console |
| 69 | UDP | TFTP | PXE boot files (if TFTP enabled) |
| 53 | TCP/UDP | DNS | If Smart Proxy DNS is enabled |
| 67 | UDP | DHCP | If Smart Proxy DHCP is enabled |

## Limitations vs. Bare-Metal Satellite

This containerized approach has several limitations:

| Feature | Bare-Metal | Container | Notes |
|---------|-----------|-----------|-------|
| Installation | `satellite-installer` on RHEL | Same, but inside container | Experimental — may fail |
| Content sync | ✅ Full support | ⚠️ Untested at scale | Disk I/O performance unknown |
| Capsule deployment | ✅ Full support | ⚠️ Requires separate container | See definitions/capsule/ |
| IdM integration | ✅ Full support | ⚠️ Untested | Kerberos may need additional config |
| Discovery/PXE | ✅ Full support | ⚠️ TFTP/DHCP may not work | Bridge networking required for DHCP relay |
| Performance | Production-grade | Unknown | No benchmarks exist for containerized Satellite |
| Red Hat Support | ✅ Supported | ❌ Unsupported | Use bare-metal for production |

For production deployments, install Satellite on bare-metal or VM RHEL and use the [parmstro/rhis-builder-satellite](https://github.com/parmstro/rhis-builder-satellite) Ansible playbooks.

## Troubleshooting

### Container fails to start

Check disk space — Satellite requires 200+ GB:

```bash
df -h /srv/containers/satellite/
```

Check RAM allocation:

```bash
free -h
```

### satellite-installer fails with "Insufficient memory"

Increase the memory limit in `satellite.container`:

```ini
PodmanArgs=--memory=32g
```

### "Cannot contact Satellite server" from clients

Verify:
1. Container is running: `sudo podman ps --filter name=satellite`
2. Container has expected IP: `sudo podman inspect satellite | grep IPAddress`
3. Firewall allows port 443: `curl -k https://<satellite-ip>/`
4. SELinux is not blocking: `sudo ausearch -m AVC -ts recent`

### Content sync extremely slow

Check disk I/O:

```bash
sudo podman exec satellite iostat -x 5
```

For better performance, consider:
- Using a dedicated disk for `/srv/containers/satellite/pulp`
- Mounting Pulp storage on faster storage (NVMe SSD)
- Increasing CPU allocation in `satellite.container`

## Security Considerations

- **Experimental status** — no security audit, no Red Hat support
- **Secrets in environment file** — protect `satellite.env` (chmod 600, encrypt at rest)
- **Admin password** — change immediately after first login
- **Container privileges** — test without `--privileged` first; only add if installer requires it
- **TLS certificates** — Satellite generates self-signed certs; integrate with IdM CA or external CA for production

## References

- [Red Hat Satellite Documentation](https://docs.redhat.com/en/documentation/red_hat_satellite/)
- [parmstro/rhis-builder-satellite (Ansible)](https://github.com/parmstro/rhis-builder-satellite)
- [Bridge Networking Guide](../../docs/bridge-networking.md)
- [Satellite 6.18 Release Notes](https://docs.redhat.com/en/documentation/red_hat_satellite/6.18/)
