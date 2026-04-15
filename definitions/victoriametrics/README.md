# VictoriaMetrics

[VictoriaMetrics](https://victoriametrics.com/) is a high-performance, cost-effective time-series database and monitoring solution. It is Prometheus-compatible and can serve as a drop-in replacement for Prometheus with better resource efficiency.

## Stack Components

| Service | Image | Description |
|---------|-------|-------------|
| victoriametrics | `victoriametrics/victoria-metrics:v1.140.0` | Single-node TSDB with ingestion, storage, and querying |

## Quadlet Files

| File | Purpose |
|------|---------|
| `victoriametrics.container` | Main VictoriaMetrics container |
| `victoriametrics-data.volume` | Persistent TSDB storage |

## Prerequisites

- Podman 4.4+ with Quadlet support

## Setup

### 1. Install Quadlet Files

```bash
podman quadlet install victoriametrics.container victoriametrics-data.volume
```

Or manually:

```bash
mkdir -p ~/.config/containers/systemd
cp victoriametrics.container victoriametrics-data.volume ~/.config/containers/systemd/
systemctl --user daemon-reload
```

### 2. Start VictoriaMetrics

```bash
systemctl --user start victoriametrics.service
```

### 3. Verify

```bash
podman ps --filter name=victoriametrics
curl -s http://localhost:8428/health
```

Access the built-in web UI (vmui) at `http://localhost:8428/vmui`.

## Prometheus Scrape Configuration

To enable Prometheus-compatible metric scraping, create a scrape config and uncomment the volume and Exec override in `victoriametrics.container`:

```bash
sudo mkdir -p /srv/containers/victoriametrics
```

Create `/srv/containers/victoriametrics/prometheus.yml`:

```yaml
scrape_configs:
  - job_name: "victoriametrics"
    static_configs:
      - targets: ["localhost:8428"]

  - job_name: "node"
    static_configs:
      - targets: ["host.containers.internal:9100"]
```

## Data Ingestion

VictoriaMetrics accepts data via multiple protocols:

- **Prometheus remote write** — `POST /api/v1/write`
- **Prometheus scrape** — via `-promscrape.config`
- **InfluxDB line protocol** — `POST /write`
- **OpenTSDB** — `POST /api/put`
- **Graphite plaintext** — port 2003 (requires `-graphiteListenAddr`)
- **DataDog** — `POST /datadog/api/v1/series`

### Quick Test

```bash
# Write a metric
curl -d 'test_metric{job="quicktest"} 42' http://localhost:8428/api/v1/import/prometheus

# Query it
curl 'http://localhost:8428/api/v1/query?query=test_metric'
```

## Key CLI Flags

| Flag | Default | Description |
|------|---------|-------------|
| `-retentionPeriod` | `1` (1 month) | Data retention (e.g., `90d`, `1y`) |
| `-storageDataPath` | `victoria-metrics-data` | TSDB data directory |
| `-httpListenAddr` | `:8428` | HTTP listen address |
| `-promscrape.config` | (none) | Prometheus scrape configuration file |
| `-selfScrapeInterval` | `0s` | Self-metrics collection interval |

Edit the `Exec=` line in `victoriametrics.container` to change these flags.

## Port Configuration

| Host Port | Container Port | Protocol |
|-----------|---------------|----------|
| 8428 | 8428 | HTTP |
