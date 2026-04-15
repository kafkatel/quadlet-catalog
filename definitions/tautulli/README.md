# Tautulli

[Tautulli](https://tautulli.com/) is a monitoring and analytics tool for Plex Media Server. It tracks play history, user activity, and streaming statistics with rich notification support.

## Stack Components

| Service | Image | Description |
|---------|-------|-------------|
| tautulli | `linuxserver/tautulli:latest` | Plex analytics with web UI |

## Quadlet Files

| File | Purpose |
|------|---------|
| `tautulli.container` | Main container |

## Setup

```bash
sudo mkdir -p /srv/containers/tautulli/config
podman quadlet install tautulli.container
systemctl --user start tautulli.service
```

Access the web UI at `http://localhost:8181`. On first launch, connect to your Plex Media Server using your Plex account credentials.

## Port Configuration

| Host Port | Container Port | Protocol |
|-----------|---------------|----------|
| 8181 | 8181 | HTTP |
