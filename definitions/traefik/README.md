# Traefik

[Traefik](https://traefik.io/traefik/) is a modern reverse proxy and load balancer with automatic TLS certificate management via Let's Encrypt. This definition uses the **file provider** for service discovery, which is the recommended approach for Podman/Quadlet deployments (no Docker socket required).

## Stack Components

| Service | Image | Description |
|---------|-------|-------------|
| traefik | `traefik:v3.6` | Reverse proxy with TLS termination and dashboard |

## Quadlet Files

| File | Purpose |
|------|---------|
| `traefik.container` | Main Traefik container |
| `traefik.yml` | Static configuration (copy to host before deploying) |
| `whoami.yml.sample` | Example dynamic route configuration |

## Prerequisites

- Podman 4.4+ with Quadlet support
- Ports 80 and 443 available (requires root or `net.ipv4.ip_unprivileged_port_start=80` in sysctl)

## Setup

### 1. Create Host Directories

```bash
sudo mkdir -p /srv/containers/traefik/{dynamic,acme}
sudo cp traefik.yml /srv/containers/traefik/traefik.yml
```

### 2. Configure TLS (Optional)

To enable automatic Let's Encrypt certificates, edit `/srv/containers/traefik/traefik.yml`:

1. Uncomment the `certificatesResolvers` section and set your email
2. Uncomment the HTTP-to-HTTPS redirect in the `web` entrypoint
3. Create the ACME storage file:

```bash
touch /srv/containers/traefik/acme/acme.json
chmod 600 /srv/containers/traefik/acme/acme.json
```

### 3. Add Route Configurations

Place YAML files in `/srv/containers/traefik/dynamic/` to define routes. Traefik watches this directory and reloads automatically.

```bash
cp whoami.yml.sample /srv/containers/traefik/dynamic/myapp.yml
# Edit myapp.yml with your service's hostname and backend URL
```

### 4. Install Quadlet Files

```bash
podman quadlet install traefik.container
```

### 5. Start Traefik

```bash
systemctl --user start traefik.service
```

### 6. Verify

```bash
podman ps --filter name=traefik
curl -s http://localhost:8080/api/overview | python3 -m json.tool
```

Access the dashboard at `http://localhost:8080`.

## Service Discovery

This definition uses the **file provider** instead of the Docker/Podman socket provider. This is more secure (no socket access) and aligns with the declarative nature of Quadlet definitions.

To route traffic to other containers on the same host, use `host.containers.internal` as the backend hostname in your dynamic configs, or reference containers by their Podman DNS name if they share a network.

## Port Configuration

| Host Port | Container Port | Protocol | Purpose |
|-----------|---------------|----------|---------|
| 80 | 80 | HTTP | Web entrypoint |
| 443 | 443 | HTTPS | Secure entrypoint |
| 8080 | 8080 | HTTP | Dashboard/API (disable in production) |

## Production Hardening

1. Set `api.insecure: false` in `traefik.yml` and remove the `PublishPort=8080:8080` line
2. Protect the dashboard with authentication middleware in a dynamic config file
3. Enable the HTTP-to-HTTPS redirect
4. Configure Let's Encrypt for automatic TLS
