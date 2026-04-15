# Prowlarr

[Prowlarr](https://prowlarr.com/) is an indexer manager for the *arr media automation stack. It manages torrent and Usenet indexer configurations in one place and automatically syncs them to Sonarr, Radarr, and other *arr applications.

## Stack Components

| Service | Image | Description |
|---------|-------|-------------|
| prowlarr | `linuxserver/prowlarr:latest` | Indexer manager with web UI |

## Quadlet Files

| File | Purpose |
|------|---------|
| `prowlarr.container` | Main container |

## Setup

```bash
sudo mkdir -p /srv/containers/prowlarr/config
podman quadlet install prowlarr.container
systemctl --user start prowlarr.service
```

Access the web UI at `http://localhost:9696`. Configure indexers and connect to Sonarr/Radarr under Settings > Apps.

## Port Configuration

| Host Port | Container Port | Protocol |
|-----------|---------------|----------|
| 9696 | 9696 | HTTP |
