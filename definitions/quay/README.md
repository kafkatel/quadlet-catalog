# Quay Container Registry

[Project Quay](https://github.com/quay/quay) is an open-source container image registry with vulnerability scanning, repository mirroring, and fine-grained access control.

## Stack Components

| Service | Image | Description |
|---------|-------|-------------|
| quay | `quay.io/projectquay/quay` | Registry application |
| quay-postgres | `postgres:16` | Quay metadata database |
| quay-clair-postgres | `postgres:16` | Clair vulnerability database |
| quay-redis | `valkey/valkey` | Build logs and user events |
| quay-clair | `quay.io/projectquay/clair:4.4.1` | Vulnerability scanner (combo mode) |
| quay-mirror | `quay.io/projectquay/quay` | Repository mirroring worker |

## Architecture

The stack uses a pod for the Quay application containers and a bridge network for infrastructure services:

- **Pod** (`quay.pod`): Contains `quay` and `quay-mirror`. Publishes only HTTP (8080) and HTTPS (8443) to the host. The pod is attached to the backend network.
- **Network** (`quay-network.network`): All infrastructure services (`quay-postgres`, `quay-clair-postgres`, `quay-redis`, `quay-clair`) run standalone on this bridge network. Each has its own network namespace, so all services use their standard ports with no conflicts.

Services resolve each other by container name via Podman's DNS on the bridge network. No database, cache, or scanner ports are exposed to the host.

## Prerequisites

- Podman 4.4+ with Quadlet support
- `podman-compose` is **not** required; systemd manages all services

## Setup

### 1. Generate Secrets

```bash
DB_SECRET=$(python3 -c "import uuid; print(uuid.uuid4())")
SESSION_KEY=$(python3 -c "import uuid; print(uuid.uuid4())")
PSK=$(python3 -c "import secrets; print(secrets.token_hex(32))")
PG_PASSWORD=$(python3 -c "import secrets; print(secrets.token_hex(16))")

echo "DB_SECRET:    $DB_SECRET"
echo "SESSION_KEY:  $SESSION_KEY"
echo "PSK:          $PSK"
echo "PG_PASSWORD:  $PG_PASSWORD"
```

### 2. Create Configuration Files

```bash
sudo mkdir -p /srv/containers/quay/config
sudo mkdir -p /srv/containers/quay/clair-config

sudo cp config.yaml.sample /srv/containers/quay/config/config.yaml
sudo cp clair-config.yaml.sample /srv/containers/quay/clair-config/config.yaml
```

Set the generated secrets in all three files. `PG_PASSWORD` is shared -- it must be the same value in all three places:

- `quay.env` - Set `POSTGRES_PASSWORD` to `PG_PASSWORD`
- `/srv/containers/quay/config/config.yaml` - Replace `CHANGEME` in `DB_URI` with `PG_PASSWORD`, set `DATABASE_SECRET_KEY` to `DB_SECRET`, `SECRET_KEY` to `SESSION_KEY`, `SECURITY_SCANNER_V4_PSK` to `PSK`, and `SERVER_HOSTNAME` to your FQDN
- `/srv/containers/quay/clair-config/config.yaml` - Replace `CHANGEME` in all three `connstring` values with `PG_PASSWORD`, and set `auth.psk.key` to `PSK`

The PSK value must match between Quay's `SECURITY_SCANNER_V4_PSK` and Clair's `auth.psk.key`.

**TLS configuration:** The sample defaults to `PREFERRED_URL_SCHEME: https`, which requires `ssl.cert` and `ssl.key` files in `/srv/containers/quay/config/`. If TLS is handled by a reverse proxy instead, change the bottom of `config.yaml` to:

```yaml
PREFERRED_URL_SCHEME: http
EXTERNAL_TLS_TERMINATION: true
```

### 3. Install Quadlet Files

For system-level deployment:

```bash
sudo cp *.pod *.container *.network *.volume /etc/containers/systemd/
sudo cp quay.env /etc/containers/systemd/
sudo systemctl daemon-reload
```

For user-level deployment:

```bash
mkdir -p ~/.config/containers/systemd
cp *.pod *.container *.network *.volume quay.env ~/.config/containers/systemd/
systemctl --user daemon-reload
```

### 4. Start the Stack

The startup requires two phases because Quay needs the `pg_trgm` PostgreSQL extension before it can run its database migrations.

**Phase 1 -- Start PostgreSQL and install extensions:**

```bash
systemctl --user start quay-postgres.service
# Wait for postgres to finish initializing
sleep 10
podman exec quay-postgres psql -U quay -d quay -c "CREATE EXTENSION IF NOT EXISTS pg_trgm;"
```

**Phase 2 -- Start Quay and remaining services:**

```bash
systemctl --user start quay.service
# Wait for Quay to finish database migrations on first run
sleep 30
systemctl --user start quay-clair-postgres.service
systemctl --user start quay-clair.service quay-mirror.service
```

Replace `systemctl --user` with `sudo systemctl` for system-level deployments.

On subsequent startups (after the initial migration), starting `quay.service` is sufficient -- it pulls in its dependencies via `Requires=`:

```bash
systemctl --user start quay.service
```

### 5. Verify

```bash
# Check all containers are running
podman ps --filter name=quay

# Test health endpoint
curl http://localhost:8080/health/instance
```

All health services should report `true`. Access the web UI at `http://localhost:8080` (or `https://localhost:8443` if TLS certificates are configured). On first access, create an initial user account.

## Port Configuration

Default port mappings (set in `quay.pod`):

| Host Port | Container Port | Protocol |
|-----------|---------------|----------|
| 8080 | 8080 | HTTP |
| 8443 | 8443 | HTTPS |

These are the only ports exposed to the host. All infrastructure services (PostgreSQL, Redis, Clair) are reachable only within the `quay-backend` network.

To use standard ports (80/443), edit `quay.pod` and change the `PublishPort` values. This requires running as root or having `CAP_NET_BIND_SERVICE`.

For reverse proxy deployments, add your proxy container to the `quay-backend` network and proxy to `quay:8080`/`quay:8443`. You can then remove the `PublishPort` lines from `quay.pod` so that Quay is only reachable through the proxy.

## Storage Backends

The sample configuration uses `LocalStorage` backed by the `quay-storage` volume. For production, configure an object storage backend in `config.yaml`:

- Amazon S3
- Google Cloud Storage
- OpenStack Swift
- Ceph/RADOS Gateway
- Azure Blob Storage

See the [storage configuration documentation](https://docs.projectquay.io/config_quay.html) for details.
