# Sonarr

[Sonarr](https://sonarr.tv/) is an automated TV show library manager. It monitors RSS feeds and indexers for new episodes, sends them to a download client, and organizes completed downloads into your media library.

## Stack Components

| Service | Image | Description |
|---------|-------|-------------|
| sonarr | `linuxserver/sonarr:latest` | TV show automation with web UI |

## Quadlet Files

| File | Purpose |
|------|---------|
| `sonarr.container` | Main container |

## Setup

```bash
sudo mkdir -p /srv/containers/sonarr/config
sudo mkdir -p /srv/containers/media/{tv,downloads}
podman quadlet install sonarr.container
systemctl --user start sonarr.service
```

Access the web UI at `http://localhost:8989`.

## Media Directory Layout

Sonarr, Radarr, and Bazarr all mount `/srv/containers/media` as `/data` using the shared `:z` SELinux suffix. This shared filesystem tree enables hardlinks and atomic moves (avoiding slow copy+delete operations):

```
/srv/containers/media/
  downloads/       # Download client output
  tv/              # Sonarr library (set as Root Folder in Sonarr)
  movies/          # Radarr library
```

## Port Configuration

| Host Port | Container Port | Protocol |
|-----------|---------------|----------|
| 8989 | 8989 | HTTP |
