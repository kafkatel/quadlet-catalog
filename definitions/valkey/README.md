# Valkey

[Valkey](https://valkey.io/) is an open-source, Redis-compatible key-value store. It is a community-driven fork of Redis maintained by the Linux Foundation.

This is the canonical system-level definition -- a standalone Valkey instance available to any service on the host. Several application stacks in this catalog (firecrawl, quay, librechat) embed their own vendored copy of Valkey scoped to that stack. Use this definition when you want a single shared instance rather than per-stack copies.

The `redis` directory is a symlink to this one, so either name resolves to the same definition.

## Stack Components

| Service | Image | Description |
|---------|-------|-------------|
| valkey | `docker.io/valkey/valkey:latest` | Valkey key-value store |

## Architecture

Standalone container with port 6379 published to the host. No pod or network is required -- clients connect directly via `localhost:6379` or the host IP.

```
  Host :6379 ───► valkey
                    └── valkey-data volume
```

## Quadlet Files

| File | Type | Purpose |
|------|------|---------|
| `valkey.container` | Container | Valkey server |
| `valkey-data.volume` | Volume | Persistent data |

## Prerequisites

- Podman 4.4+ with Quadlet support

## Setup

### 1. Install Quadlet Files

```bash
cd definitions/valkey/
podman quadlet install *.container *.volume
```

Or manually:

```bash
mkdir -p ~/.config/containers/systemd
cp valkey.container valkey-data.volume ~/.config/containers/systemd/
systemctl --user daemon-reload
```

### 2. Start Valkey

```bash
systemctl --user start valkey.service
```

### 3. Verify

```bash
podman ps --filter name=valkey
valkey-cli ping
# PONG
```

## Optional: Custom Configuration

To use a custom `valkey.conf`, create the config directory and file, then uncomment the Volume and Exec lines in `valkey.container`:

```bash
sudo mkdir -p /srv/containers/valkey/conf
```

Using `/srv/containers/` ensures the correct SELinux context (`var_t`) is inherited on Fedora/RHEL, so the `:Z` volume mount works without manual relabeling.

Starter `valkey.conf`:

```
bind 0.0.0.0
port 6379

# Persistence
save 60 1000
appendonly yes

# Memory limit (adjust to your system)
# maxmemory 256mb
# maxmemory-policy allkeys-lru
```

Then uncomment the relevant lines in `valkey.container`:

```ini
Volume=/srv/containers/valkey/conf/valkey.conf:/etc/valkey/valkey.conf:Z
Exec=valkey-server /etc/valkey/valkey.conf
```

## Vendoring into Application Stacks

This definition is designed as a baseline. To embed Valkey into an application stack:

1. Copy `valkey.container` into your stack's definition directory
2. Rename to `{appname}-valkey.container` (or `{appname}-redis.container`)
3. Set `ContainerName={appname}-valkey`
4. Remove `PublishPort=6379:6379` (stack-internal services shouldn't expose ports)
5. Add `Network={appname}-network.network` or `Pod={appname}.pod`
6. Adjust health check interval to match your stack's needs

See `definitions/quay/quay-redis.container` or `definitions/firecrawl/firecrawl-redis.container` for examples.

## Health Check

| Check | Command | Interval | Retries |
|-------|---------|----------|---------|
| Liveness | `valkey-cli ping` | 10s | 3 |

## Data Persistence

By default, Valkey uses RDB snapshots. Data is stored in the `valkey-data` named volume managed by Podman. To enable AOF (append-only file) persistence, use a custom `valkey.conf` with `appendonly yes`.

To back up:

```bash
podman volume export valkey-data > valkey-backup.tar
```

To restore:

```bash
podman volume import valkey-data valkey-backup.tar
```
