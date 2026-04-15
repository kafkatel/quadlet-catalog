# Grafana

[Grafana](https://grafana.com/) is an open-source observability platform for querying, visualizing, and alerting on metrics, logs, and traces from any data source.

## Stack Components

| Service | Image | Description |
|---------|-------|-------------|
| grafana | `grafana/grafana:13.0.0` | Dashboard and visualization server |

## Quadlet Files

| File | Purpose |
|------|---------|
| `grafana.container` | Main Grafana container |
| `grafana-data.volume` | Persistent storage for dashboards, users, and SQLite database |
| `grafana.env` | Environment variables (admin credentials, plugins, logging) |

## Prerequisites

- Podman 4.4+ with Quadlet support

## Setup

### 1. Configure Environment

```bash
cp grafana.env grafana.env.local
```

Edit `grafana.env` and set `GF_SECURITY_ADMIN_PASSWORD`:

```bash
python3 -c "import secrets; print(secrets.token_hex(16))"
```

If left empty, Grafana defaults to `admin`/`admin` and forces a password change on first login.

### 2. Install Quadlet Files

```bash
podman quadlet install grafana.container grafana-data.volume grafana.env
```

Or manually:

```bash
mkdir -p ~/.config/containers/systemd
cp grafana.container grafana-data.volume grafana.env ~/.config/containers/systemd/
systemctl --user daemon-reload
```

### 3. Start Grafana

```bash
systemctl --user start grafana.service
```

### 4. Verify

```bash
podman ps --filter name=grafana
curl -s http://localhost:3000/api/health | python3 -m json.tool
```

Access the web UI at `http://localhost:3000`.

## Provisioning

Grafana supports declarative configuration of datasources, dashboards, and alerting rules via provisioning files. To enable:

1. Create provisioning directories on the host:

```bash
sudo mkdir -p /srv/containers/grafana/provisioning/{datasources,dashboards,alerting}
```

2. Add YAML configuration files (see [Grafana provisioning docs](https://grafana.com/docs/grafana/latest/administration/provisioning/)).

3. Uncomment the provisioning volume in `grafana.container`.

### Example: Add Loki as a Datasource

Create `/srv/containers/grafana/provisioning/datasources/loki.yaml`:

```yaml
apiVersion: 1
datasources:
  - name: Loki
    type: loki
    access: proxy
    url: http://loki:3100
    isDefault: false
```

## Port Configuration

| Host Port | Container Port | Protocol |
|-----------|---------------|----------|
| 3000 | 3000 | HTTP |
