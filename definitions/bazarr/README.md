# Bazarr

[Bazarr](https://www.bazarr.media/) is an automatic subtitle manager that watches Sonarr and Radarr libraries for new content and fetches matching subtitles from providers (OpenSubtitles, Addic7ed, etc.).

## Stack Components

| Service | Image | Description |
|---------|-------|-------------|
| bazarr | `linuxserver/bazarr:latest` | Subtitle automation with web UI |

## Quadlet Files

| File | Purpose |
|------|---------|
| `bazarr.container` | Main container |

## Setup

```bash
sudo mkdir -p /srv/containers/bazarr/config
podman quadlet install bazarr.container
systemctl --user start bazarr.service
```

Access the web UI at `http://localhost:6767`. Connect to Sonarr and Radarr under Settings > Sonarr / Radarr, then configure subtitle providers under Settings > Providers.

## Port Configuration

| Host Port | Container Port | Protocol |
|-----------|---------------|----------|
| 6767 | 6767 | HTTP |
