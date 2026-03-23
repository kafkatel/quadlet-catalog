# Forgejo

[Forgejo](https://forgejo.org/) is a self-hosted, lightweight Git forge. It provides repository hosting, issue tracking, pull requests, a built-in container/package registry, and CI/CD via Forgejo Actions (GitHub Actions compatible).

## Stack Components

| Service | Image | Description |
|---------|-------|-------------|
| forgejo-server | `codeberg.org/forgejo/forgejo:14-rootless` | Forgejo Git service (HTTP + SSH) |
| forgejo-postgres | `docker.io/library/postgres:16` | PostgreSQL database |
| forgejo-runner | `code.forgejo.org/forgejo/runner:12.6.2` | CI/CD runner daemon (optional) |
| forgejo-runner-podman | `quay.io/podman/stable` | Rootless Podman sidecar for runner job containers |

## Architecture

```
                    ┌────────────────────────────────────────────┐
                    │         forgejo-backend network            │
                    │                                            │
  Host :3000 ──►   │  ┌──────────────────────────────────┐      │
  Host :2222 ──►   │  │       forgejo pod                │      │
                    │  │                                  │      │
                    │  │   forgejo-server (:3000, :2222)  │      │
                    │  └──────────────────────────────────┘      │
                    │              │                              │
                    │              ▼                              │
                    │  forgejo-postgres (:5432)                  │
                    │                                            │
                    │  ┌──────────────────────────────────┐      │
                    │  │    forgejo-runner pod (optional) │      │
                    │  │                                  │      │
                    │  │  forgejo-runner (unprivileged)   │      │
                    │  │  forgejo-runner-podman (rootless)│      │
                    │  │     └─ isolated Podman service   │      │
                    │  └──────────────────────────────────┘      │
                    └────────────────────────────────────────────┘
```

- **Pod** (`forgejo.pod`): Groups the Forgejo server. Publishes port 3000 (HTTP) and 2222 (SSH). Attached to the backend network.
- **Network** (`forgejo.network`): Bridge network for inter-container DNS. PostgreSQL runs standalone on this network so the Forgejo server resolves it by container name.
- **Runner pod** (`forgejo-runner.pod`): Optional. Groups the runner daemon and a rootless Podman sidecar. The runner is unprivileged — job containers execute inside the sidecar's isolated Podman namespace, not on the host.

## Quadlet Files

| File | Type | Purpose |
|------|------|---------|
| `forgejo.pod` | Pod | Pod definition (publishes HTTP + SSH) |
| `forgejo.network` | Network | Bridge network for DNS |
| `forgejo-server.container` | Container | Forgejo Git service |
| `forgejo-postgres.container` | Container | PostgreSQL 16 database |
| `forgejo-runner.pod` | Pod | Runner pod (groups runner + podman sidecar) |
| `forgejo-runner.container` | Container | CI/CD runner daemon (unprivileged) |
| `forgejo-runner-podman.container` | Container | Rootless Podman sidecar for job containers |
| `forgejo-data.volume` | Volume | Repository and package data |
| `forgejo-pgdata.volume` | Volume | PostgreSQL database files |
| `forgejo-runner-socket.volume` | Volume | Shared Podman socket (runner ↔ sidecar) |
| `forgejo-runner-storage.volume` | Volume | Podman container storage for jobs |
| `forgejo-runner-home.volume` | Volume | Podman rootless config directory |
| `forgejo.env` | Environment | Server + database configuration |
| `forgejo-runner.env` | Environment | Runner registration credentials |
| `config/runner-config.yaml` | Config | Runner daemon configuration |

## Prerequisites

- Podman 4.4+ with Quadlet support

## Setup

### 1. Create Host Directories

```bash
sudo mkdir -p /srv/containers/forgejo/{data,config,runner,runner-config}
```

### 2. Configure Runner (Optional)

If deploying CI/CD runners, copy the runner config:

```bash
sudo cp config/runner-config.yaml /srv/containers/forgejo/runner-config/config.yaml
```

### 3. Configure Environment

Edit `forgejo.env` with your values:

```ini
POSTGRES_PASSWORD=your-secure-password
FORGEJO__database__PASSWD=your-secure-password
FORGEJO__server__DOMAIN=git.example.com
FORGEJO__server__ROOT_URL=https://git.example.com/
FORGEJO__server__SSH_DOMAIN=git.example.com
```

If deploying runners, also edit `forgejo-runner.env`:

```ini
FORGEJO_INSTANCE=https://git.example.com
FORGEJO_TOKEN=your-runner-registration-token
```

### 4. Install Quadlet Files

```bash
# Core stack (server + database)
sudo cp forgejo.pod forgejo.network \
   forgejo-server.container forgejo-postgres.container \
   forgejo-data.volume forgejo-pgdata.volume \
   forgejo.env /etc/containers/systemd/

# Optional: CI/CD runner (rootless sidecar pattern)
sudo cp forgejo-runner.pod forgejo-runner.container \
   forgejo-runner-podman.container \
   forgejo-runner-socket.volume forgejo-runner-storage.volume \
   forgejo-runner-home.volume forgejo-runner.env /etc/containers/systemd/

sudo systemctl daemon-reload
```

### 5. Start the Stack

```bash
# Start the pod (pulls in server + database via dependencies)
sudo systemctl start forgejo-pod.service

# Check status
sudo systemctl status forgejo-server.service forgejo-postgres.service
```

### 6. Initial Setup

1. Visit `http://localhost:3000` (or your configured domain)
2. Complete the installation wizard
3. Create your admin account
4. Set `FORGEJO__security__INSTALL_LOCK=true` in `forgejo.env` to prevent re-installation
5. Restart: `sudo systemctl restart forgejo-server.service`

### 7. Verify

```bash
# Check all containers are running
podman ps --filter name=forgejo

# Test the API
curl -s http://localhost:3000/api/healthz
# Expected: {"healthy":true}

# Test SSH (after configuring SSH keys in the web UI)
ssh -p 2222 git@localhost
```

## Deploying CI/CD Runners

### 1. Get a Registration Token

In the Forgejo web UI:
- Go to Site Administration > Actions > Runners
- Click "Create new Runner"
- Copy the registration token

### 2. Register the Runner

Before starting the runner container, register it:

```bash
# Run a one-time registration
sudo podman run --rm -it \
    -v /srv/containers/forgejo/runner:/data:Z \
    code.forgejo.org/forgejo/runner:12.6.2 \
    forgejo-runner register \
        --instance "https://git.example.com" \
        --token "YOUR_REGISTRATION_TOKEN" \
        --name "runner-1" \
        --labels "ubuntu-latest:docker://catthehacker/ubuntu:act-latest,docker:docker://docker:dind" \
        --no-interactive

# Move the registration file into place
sudo mv /srv/containers/forgejo/runner/.runner /srv/containers/forgejo/runner/.runner
```

### 3. Start the Runner Pod

The runner pod starts both the Podman sidecar and the runner daemon:

```bash
sudo systemctl start forgejo-runner-pod.service
```

The Podman sidecar starts first, creates the socket, then the runner connects to it.

### 4. Verify Runner Registration

Check Forgejo web UI: Site Administration > Actions > Runners. The runner should show as "Idle".

```bash
# Check runner logs
sudo journalctl -u forgejo-runner.service -f
```

### Scaling Runners

Each runner needs its own pod (runner + Podman sidecar pair). Copy all three files per additional runner:

```bash
# Create runner-2 data directory
sudo mkdir -p /srv/containers/forgejo/runner-2

# Copy the pod, sidecar, and runner files
for f in forgejo-runner.pod forgejo-runner-podman.container forgejo-runner.container; do
    sudo cp /etc/containers/systemd/$f \
        /etc/containers/systemd/${f/forgejo-runner/forgejo-runner-2}
done

# Edit all three files:
#   forgejo-runner-2.pod        — no changes needed
#   forgejo-runner-2-podman.container — change ContainerName, Pod reference
#   forgejo-runner-2.container  — change ContainerName, Pod reference,
#                                  Volume path to runner-2:/data:Z

# Register runner-2 (same process as above, different --name)
# Then start it
sudo systemctl daemon-reload
sudo systemctl start forgejo-runner-2-pod.service
```

### Cache Server for Multiple Runners

When running multiple runners, deploy a shared cache server so `actions/cache` works across runners:

```bash
# Start a cache server on the host (port 8088)
sudo podman run -d --name forgejo-cache \
    --network forgejo-backend \
    -v /srv/containers/forgejo/cache:/cache:Z \
    -p 8088:8088 \
    code.forgejo.org/forgejo/runner:12.6.2 \
    forgejo-runner cache-server --port 8088 --dir /cache --secret "your-cache-secret"

# Update runner-config.yaml:
#   cache:
#     external_server: http://<host-ip>:8088
#     secret: your-cache-secret
```

## Reverse Proxy (HTTPS)

Forgejo serves HTTP on port 3000. For HTTPS, put it behind a reverse proxy:

### Caddy (Recommended)

```
git.example.com {
    reverse_proxy localhost:3000
}
```

### nginx

```nginx
server {
    listen 443 ssl;
    server_name git.example.com;

    ssl_certificate /etc/letsencrypt/live/git.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/git.example.com/privkey.pem;

    client_max_body_size 1G;

    location / {
        proxy_pass http://localhost:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

## SSH Access

Git over SSH listens on port 2222. Configure your SSH client:

```
# ~/.ssh/config
Host git.example.com
    Port 2222
    User git
```

Then clone:
```bash
git clone git@git.example.com:username/repo.git
```

Open the firewall if needed:
```bash
sudo firewall-cmd --permanent --add-port=2222/tcp
sudo firewall-cmd --reload
```

## Health Checks

| Service | Health Check | Interval |
|---------|-------------|----------|
| forgejo-server | `curl http://localhost:3000/api/healthz` | 30s |
| forgejo-postgres | `pg_isready -U forgejo -d forgejo` | 10s |

## Data Persistence

| Host Path | Container Mount | Purpose |
|-----------|----------------|---------|
| `/srv/containers/forgejo/data` | `/var/lib/gitea` | Git repositories, LFS objects, packages, avatars, attachments |
| `/srv/containers/forgejo/config` | `/etc/gitea` | `app.ini` configuration file (auto-generated on first run) |
| (named volume) `forgejo-pgdata` | `/var/lib/postgresql/data` | PostgreSQL database |
| `/srv/containers/forgejo/runner` | `/data` | Runner registration state |

## Environment Variables

Forgejo uses the `FORGEJO__section__key` format to override `app.ini` settings via environment variables. The double underscore separates the INI section from the key.

| Variable | Default | Description |
|----------|---------|-------------|
| `FORGEJO__server__DOMAIN` | `localhost` | Public domain name |
| `FORGEJO__server__ROOT_URL` | `http://localhost:3000/` | Full public URL |
| `FORGEJO__server__SSH_PORT` | `2222` | SSH port shown in clone URLs |
| `FORGEJO__database__DB_TYPE` | `postgres` | Database type |
| `FORGEJO__database__HOST` | `forgejo-postgres:5432` | Database host (container name) |
| `FORGEJO__security__INSTALL_LOCK` | `false` | Set `true` after first install |
| `FORGEJO__actions__ENABLED` | `true` | Enable Forgejo Actions (CI/CD) |
| `FORGEJO__service__DISABLE_REGISTRATION` | `false` | Disable public user registration |
| `POSTGRES_PASSWORD` | (empty) | PostgreSQL password |

See [Forgejo configuration cheat sheet](https://forgejo.org/docs/latest/admin/config-cheat-sheet/) for all available settings.

## Migrating from the Beardshift K8s Deployment

This quadlet definition is adapted from the [beardshift](https://github.com/bharrington/beardshift) MicroShift/OpenShift deployment. Key differences:

| K8s Resource | Quadlet Equivalent | Notes |
|-------------|-------------------|-------|
| CNPG `Cluster` (PostgreSQL operator) | `forgejo-postgres.container` (plain PostgreSQL 16) | No operator needed — single-instance PostgreSQL |
| K8s `Deployment` | `forgejo-server.container` in `forgejo.pod` | Pod publishes ports; server joins pod |
| K8s `Service` (ClusterIP) | Podman DNS via `forgejo.network` | Containers resolve each other by name |
| K8s `Service` (NodePort 30022) | `PublishPort=2222:2222` on the pod | Direct port publish instead of NodePort |
| K8s `Route` / `Ingress` | External reverse proxy (Caddy/nginx) | Quadlet doesn't manage ingress |
| K8s `StatefulSet` (runners) | Copy runner pod group per instance | Each gets its own pod + sidecar + data directory |
| K8s `ConfigMap` (runner config) | `config/runner-config.yaml` bind mount | Same YAML format |
| K8s `Secret` (runner token) | `forgejo-runner.env` | Operator fills in token |
| Podman sidecar container | `forgejo-runner-podman.container` (rootless sidecar) | Same pattern — isolated Podman service, shared socket |
| PVC (topolvm-provisioner) | Host bind mounts under `/srv/containers/` | No CSI driver needed |
| cert-manager + `inject-cert.sh` | External reverse proxy handles TLS | No in-cluster cert management |

## Backing Up

```bash
# Stop the stack
sudo systemctl stop forgejo-pod.service

# Backup data and database
sudo tar czf forgejo-backup-$(date +%Y%m%d).tar.gz \
    -C /srv/containers/forgejo data/ config/

# For PostgreSQL, also dump the database for a portable backup:
sudo podman exec forgejo-postgres pg_dumpall -U forgejo > forgejo-db-$(date +%Y%m%d).sql

# Restart
sudo systemctl start forgejo-pod.service
```
