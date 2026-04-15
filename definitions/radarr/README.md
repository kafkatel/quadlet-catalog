# Radarr

[Radarr](https://radarr.video/) is an automated movie library manager. It monitors for new releases, manages quality upgrades, sends to download clients, and organizes completed downloads into your media library.

## Stack Components

| Service | Image | Description |
|---------|-------|-------------|
| radarr | `linuxserver/radarr:latest` | Movie automation with web UI |

## Quadlet Files

| File | Purpose |
|------|---------|
| `radarr.container` | Main container |

## Setup

```bash
sudo mkdir -p /srv/containers/radarr/config
sudo mkdir -p /srv/containers/media/{movies,downloads}
podman quadlet install radarr.container
systemctl --user start radarr.service
```

Access the web UI at `http://localhost:7878`.

## Media Directory Layout

See the [Sonarr README](../sonarr/README.md) for the shared media directory strategy. Radarr uses `/data/movies` as its Root Folder.

## Port Configuration

| Host Port | Container Port | Protocol |
|-----------|---------------|----------|
| 7878 | 7878 | HTTP |
