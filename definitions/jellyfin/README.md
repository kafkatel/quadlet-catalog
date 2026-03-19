# Jellyfin Media Server

[Jellyfin](https://jellyfin.org/) is a free, open-source media server for organizing and streaming personal video, music, and photo collections. It is a fully community-driven fork with no premium tiers -- all features, including hardware transcoding, are free.

## Stack Components

| Service | Image | Description |
|---------|-------|-------------|
| jellyfin | `docker.io/jellyfin/jellyfin` | Jellyfin Media Server |

## Architecture

This is a standalone container using host networking for DLNA discovery and client auto-detection.

```
  Host network
  ┌──────────────────────────────┐
  │  jellyfin (:8096)            │
  │    └── /media  ← host dirs  │
  └──────────────────────────────┘
```

No pod or bridge network is needed. The container binds directly to the host's network stack, so Jellyfin appears as a native service to other devices on the LAN.

## Quadlet Files

| File | Type | Purpose |
|------|------|---------|
| `jellyfin.container` | Container | Jellyfin Media Server |

## Prerequisites

- Podman 4.4+ with Quadlet support

## Setup

### 1. Create Host Directories

```bash
sudo mkdir -p /srv/containers/jellyfin/{config,cache,media}
```

Using `/srv/containers/` ensures the correct SELinux context (`var_t`) is inherited on Fedora/RHEL systems, so the `:Z` volume mounts work without manual relabeling.

### 2. Set Up Media Libraries

The `media/` directory is a default mount point, but you'll typically want to map your actual media locations directly. Edit the `Volume=` lines in `jellyfin.container` to point to your media directories:

```ini
# Single library
Volume=/home/user/Videos:/media/videos:Z

# Multiple libraries -- one Volume line per directory
Volume=/home/user/Movies:/media/movies:Z
Volume=/home/user/TV:/media/tv:Z
Volume=/home/user/Music:/media/music:Z

# External drive
Volume=/mnt/external/media:/media/external:Z,ro

# NAS mount
Volume=/mnt/nas/videos:/media/nas:Z,ro
```

**How volume mapping works:**

| Host Path (left side) | Container Path (right side) | Jellyfin Library Path |
|-----------------------|----------------------------|----------------------|
| `/home/user/Movies` | `/media/movies` | Select `/media/movies` in Jellyfin UI |
| `/mnt/nas/videos` | `/media/nas` | Select `/media/nas` in Jellyfin UI |

The host path is your actual directory. The container path is an arbitrary name you choose -- it's what you'll see when adding libraries in the Jellyfin setup wizard. Keep the container paths under `/media/` for consistency.

**Volume suffix reference:**

| Suffix | Use When |
|--------|----------|
| `:Z` | Default -- private SELinux label for this container only |
| `:z` | Media shared between multiple containers (e.g., Jellyfin + Plex) |
| `:Z,ro` | Read-only access (prevents Jellyfin from modifying files) |
| `:z,ro` | Shared + read-only |

**External drives:** If a mounted drive contains a `lost+found/` directory or other root-owned directories that your user cannot read, Jellyfin will fail to start. Point to a subdirectory on the drive instead of the drive root:

```ini
# Bad -- lost+found will cause startup failure
Volume=/run/media/user/external:/media/external:Z

# Good -- point to a readable subdirectory
Volume=/run/media/user/external/media:/media/external:Z
```

### 3. Install the Quadlet File

```bash
mkdir -p ~/.config/containers/systemd
cp jellyfin.container ~/.config/containers/systemd/
systemctl --user daemon-reload
```

### 4. Start Jellyfin

```bash
systemctl --user start jellyfin.service
```

The first start pulls the image and may take a few minutes. Once running, access the setup wizard at `http://localhost:8096`.

### 5. Verify

```bash
podman ps --filter name=jellyfin
curl -s http://localhost:8096/health
```

## Adding Libraries After Setup

1. Edit `jellyfin.container` to add new `Volume=` lines
2. Reload and restart:
   ```bash
   systemctl --user daemon-reload
   systemctl --user restart jellyfin.service
   ```
3. In the Jellyfin web UI, go to Dashboard > Libraries > Add Media Library and select the container path you mapped

## Running Plex and Jellyfin Side by Side

Both servers can run simultaneously since they use different ports (Plex: 32400, Jellyfin: 8096). To share the same media directories between both containers, use the lowercase `:z` (shared) SELinux suffix instead of `:Z` (private) in both container files:

```ini
# In plex.container:
Volume=/home/user/Movies:/media/movies:z,ro

# In jellyfin.container:
Volume=/home/user/Movies:/media/movies:z,ro
```

Using `:Z` (private) on the same host path in two containers causes SELinux relabeling conflicts -- the second container to start will fail to access the directory.

## GPU Hardware Transcoding

All Jellyfin features are free -- no subscription required for hardware transcoding. Uncomment the appropriate `AddDevice=` line in `jellyfin.container`:

| GPU | Line to Uncomment | Additional Requirements |
|-----|-------------------|------------------------|
| NVIDIA | `AddDevice=nvidia.com/gpu=all` | `nvidia-container-toolkit` package |
| Intel Quick Sync | `AddDevice=/dev/dri:/dev/dri` | None (built into kernel) |
| AMD VA-API | `AddDevice=/dev/dri:/dev/dri` | `mesa-va-drivers` package |

After enabling the device, configure hardware acceleration in the Jellyfin web UI under Dashboard > Playback > Transcoding.

## Data Persistence

| Host Path | Container Mount | Purpose |
|-----------|----------------|---------|
| `/srv/containers/jellyfin/config` | `/config` | Server settings, database, metadata, plugins |
| `/srv/containers/jellyfin/cache` | `/cache` | Image cache, transcoding cache |
| (your media paths) | `/media/*` | Media libraries |

## Port Reference

When using host networking, Jellyfin binds these ports directly:

| Port | Protocol | Purpose |
|------|----------|---------|
| 8096 | TCP | Web UI and API (HTTP) |
| 8920 | TCP | Web UI and API (HTTPS, if configured) |
| 1900 | UDP | DLNA discovery |
| 7359 | UDP | Client auto-discovery |

If you switch to bridge networking, only publish port 8096 -- the discovery ports require host networking to function.
