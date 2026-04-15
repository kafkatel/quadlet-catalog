# Uptime Kuma

[Uptime Kuma](https://github.com/louislam/uptime-kuma) is a self-hosted monitoring tool for tracking service availability with HTTP, TCP, DNS, and other check types. It provides configurable alerting (Slack, Discord, email, webhooks) and optional public status pages.

## Stack Components

| Service | Image | Description |
|---------|-------|-------------|
| uptime-kuma | `louislam/uptime-kuma:2` | Monitoring server with web UI |

## Quadlet Files

| File | Purpose |
|------|---------|
| `uptime-kuma.container` | Main container |
| `uptime-kuma-data.volume` | Persistent storage for SQLite database and monitor config |

## Prerequisites

- Podman 4.4+ with Quadlet support

## Setup

### 1. Install Quadlet Files

```bash
podman quadlet install uptime-kuma.container uptime-kuma-data.volume
```

Or manually:

```bash
mkdir -p ~/.config/containers/systemd
cp uptime-kuma.container uptime-kuma-data.volume ~/.config/containers/systemd/
systemctl --user daemon-reload
```

### 2. Start Uptime Kuma

```bash
systemctl --user start uptime-kuma.service
```

### 3. Verify

```bash
podman ps --filter name=uptime-kuma
curl -s http://localhost:3001
```

Access the web UI at `http://localhost:3001`. On first launch, create an admin account.

## Notes

- Data is stored in a SQLite database. NFS-backed volumes are **not supported** (SQLite WAL requires local filesystem locking).
- The `2` tag tracks the latest 2.x release with automatic patch updates.

## Port Configuration

| Host Port | Container Port | Protocol |
|-----------|---------------|----------|
| 3001 | 3001 | HTTP |
