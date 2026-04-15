# VictoriaLogs

[VictoriaLogs](https://docs.victoriametrics.com/victorialogs/) is a high-performance, cost-effective log management solution from VictoriaMetrics. It provides log collection, storage, and querying with minimal resource requirements.

## Stack Components

| Service | Image | Description |
|---------|-------|-------------|
| victorialogs | `victoriametrics/victoria-logs:v1.50.0` | Log storage and query engine |

## Quadlet Files

| File | Purpose |
|------|---------|
| `victorialogs.container` | Main VictoriaLogs container |
| `victorialogs-data.volume` | Persistent log storage |

## Prerequisites

- Podman 4.4+ with Quadlet support

## Setup

### 1. Install Quadlet Files

```bash
podman quadlet install victorialogs.container victorialogs-data.volume
```

Or manually:

```bash
mkdir -p ~/.config/containers/systemd
cp victorialogs.container victorialogs-data.volume ~/.config/containers/systemd/
systemctl --user daemon-reload
```

### 2. Start VictoriaLogs

```bash
systemctl --user start victorialogs.service
```

### 3. Verify

```bash
podman ps --filter name=victorialogs
curl -s http://localhost:9428/health
```

## Sending Logs to VictoriaLogs

VictoriaLogs accepts log data via several protocols:

- **JSON lines** — `POST /insert/jsonline`
- **Elasticsearch bulk** — `POST /_bulk` (compatible with Filebeat, Logstash, Fluentd)
- **Loki push** — `POST /insert/loki/api/v1/push`
- **Syslog** — via `-syslog.listenAddr` flag
- **OpenTelemetry** — `POST /insert/opentelemetry/v1/logs`

### Quick Test

```bash
# Insert a log entry
curl -X POST http://localhost:9428/insert/jsonline \
  -d '{"_msg":"hello from victorialogs","_time":"'$(date -Iseconds)'","host":"test"}'

# Query logs
curl 'http://localhost:9428/select/logsql/query?query=*&limit=10'
```

## Key CLI Flags

| Flag | Default | Description |
|------|---------|-------------|
| `-retentionPeriod` | `7d` | Log retention (e.g., `30d`, `90d`, `1y`) |
| `-storageDataPath` | `victoria-logs-data` | Data directory |
| `-httpListenAddr` | `:9428` | HTTP listen address |
| `-futureRetention` | `2d` | Accept logs up to this far in the future |

Edit the `Exec=` line in `victorialogs.container` to change these flags.

## Port Configuration

| Host Port | Container Port | Protocol |
|-----------|---------------|----------|
| 9428 | 9428 | HTTP |
