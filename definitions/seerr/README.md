# Seerr

[Seerr](https://docs.seerr.dev/) is a media request and discovery platform for Plex and Jellyfin. Users can browse, request movies and TV shows, and requests flow automatically into Radarr and Sonarr. Seerr is the successor to Overseerr and Jellyseerr (merged project).

## Stack Components

| Service | Image | Description |
|---------|-------|-------------|
| seerr | `ghcr.io/seerr-team/seerr:latest` | Media request portal with web UI |

## Quadlet Files

| File | Purpose |
|------|---------|
| `seerr.container` | Main container |

## Setup

```bash
sudo mkdir -p /srv/containers/seerr/config
podman quadlet install seerr.container
systemctl --user start seerr.service
```

Access the web UI at `http://localhost:5055`. On first launch, sign in with your Plex or Jellyfin account and configure Radarr/Sonarr connections.

## Migration from Overseerr

If migrating from an existing Overseerr installation, copy your Overseerr config directory to `/srv/containers/seerr/config/`. Seerr automatically migrates the database on first start.

## Notes

- Seerr is **not** a linuxserver.io image. It does not use `PUID`/`PGID` environment variables. It runs as the `node` user (UID 1000) internally.
- The `--init` flag is required because the container does not bundle an init process.

## Port Configuration

| Host Port | Container Port | Protocol |
|-----------|---------------|----------|
| 5055 | 5055 | HTTP |
