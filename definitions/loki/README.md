# Loki

[Grafana Loki](https://grafana.com/oss/loki/) is a horizontally scalable, highly available log aggregation system inspired by Prometheus. It indexes log metadata (labels) rather than full text, making it cost-effective for high-volume log storage.

## Stack Components

| Service | Image | Description |
|---------|-------|-------------|
| loki | `grafana/loki:3.7.1` | Log aggregation and query engine |

## Quadlet Files

| File | Purpose |
|------|---------|
| `loki.container` | Main Loki container |
| `loki-data.volume` | Persistent storage for chunks, index, and rules |
| `loki-config.yaml` | Sample configuration (copy to host before deploying) |

## Prerequisites

- Podman 4.4+ with Quadlet support

## Setup

### 1. Create Configuration

Loki requires a configuration file at startup. Copy the sample config to the host:

```bash
sudo mkdir -p /srv/containers/loki/config
sudo cp loki-config.yaml /srv/containers/loki/config/loki-config.yaml
```

Review and adjust the config as needed. The sample provides a minimal single-instance setup with filesystem storage and 7-day retention for old samples.

### 2. Install Quadlet Files

```bash
podman quadlet install loki.container loki-data.volume
```

Or manually:

```bash
mkdir -p ~/.config/containers/systemd
cp loki.container loki-data.volume ~/.config/containers/systemd/
systemctl --user daemon-reload
```

### 3. Start Loki

```bash
systemctl --user start loki.service
```

### 4. Verify

```bash
podman ps --filter name=loki
curl -s http://localhost:3100/ready
```

The `/ready` endpoint returns `ready` when Loki is accepting traffic.

## Sending Logs to Loki

Loki accepts log data via several protocols:

- **Promtail** (Grafana's log collector) — recommended for file-based log shipping
- **Grafana Alloy** — unified telemetry collector
- **HTTP push** — `POST /loki/api/v1/push` with JSON or protobuf payloads
- **Docker/Podman logging driver** — configure containers to send logs directly

### Quick Test

```bash
curl -X POST http://localhost:3100/loki/api/v1/push \
  -H "Content-Type: application/json" \
  -d '{"streams":[{"stream":{"job":"test"},"values":[["'$(date +%s)000000000'","hello from loki"]]}]}'

curl -G http://localhost:3100/loki/api/v1/query --data-urlencode 'query={job="test"}'
```

## Port Configuration

| Host Port | Container Port | Protocol |
|-----------|---------------|----------|
| 3100 | 3100 | HTTP |

## Storage

The sample config uses local filesystem storage under the `loki-data` volume. For production at scale, configure an object store backend (S3, GCS, Azure Blob) in the config file. See the [Loki storage documentation](https://grafana.com/docs/loki/latest/configure/storage/).
