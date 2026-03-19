# Plex Media Server

[Plex](https://www.plex.tv/) is a media server that organizes your personal video, music, and photo collections and streams them to any device. It provides automatic metadata fetching, on-the-fly transcoding, and apps for every major platform.

## Stack Components

| Service | Image | Description |
|---------|-------|-------------|
| plex | `docker.io/plexinc/pms-docker` | Plex Media Server |

## Architecture

This is a standalone container using host networking for full local network integration (DLNA, GDM discovery, Plex Companion).

```
  Host network
  ┌──────────────────────────────┐
  │  plex (:32400)               │
  │    └── /media  ← host dirs  │
  └──────────────────────────────┘
```

No pod or bridge network is needed. The container binds directly to the host's network stack, so Plex appears as a native service to other devices on the LAN.

## Quadlet Files

| File | Type | Purpose |
|------|------|---------|
| `plex.container` | Container | Plex Media Server |

## Prerequisites

- Podman 4.4+ with Quadlet support
- A [Plex account](https://www.plex.tv/) (free tier works; Plex Pass required for hardware transcoding)

## Setup

### 1. Create Host Directories

```bash
sudo mkdir -p /srv/containers/plex/{config,transcode,media}
```

Using `/srv/containers/` ensures the correct SELinux context (`var_t`) is inherited on Fedora/RHEL systems, so the `:Z` volume mounts work without manual relabeling.

### 2. Set Up Media Libraries

The `media/` directory is a default mount point, but you'll typically want to map your actual media locations directly. Edit the `Volume=` lines in `plex.container` to point to your media directories:

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

| Host Path (left side) | Container Path (right side) | Plex Library Path |
|-----------------------|----------------------------|-------------------|
| `/home/user/Movies` | `/media/movies` | Select `/media/movies` in Plex UI |
| `/mnt/nas/videos` | `/media/nas` | Select `/media/nas` in Plex UI |

The host path is your actual directory. The container path is an arbitrary name you choose -- it's what you'll see when adding libraries in the Plex web UI. Keep the container paths under `/media/` for consistency.

**Volume suffix reference:**

| Suffix | Use When |
|--------|----------|
| `:Z` | Default -- private SELinux label for this container only |
| `:z` | Media shared between multiple containers (e.g., Plex + Jellyfin) |
| `:Z,ro` | Read-only access (prevents Plex from modifying files) |
| `:z,ro` | Shared + read-only |

**External drives:** If a mounted drive contains a `lost+found/` directory or other root-owned directories that your user cannot read, Plex will fail to start. Point to a subdirectory on the drive instead of the drive root:

```ini
# Bad -- lost+found will cause startup failure
Volume=/run/media/user/external:/media/external:Z

# Good -- point to a readable subdirectory
Volume=/run/media/user/external/media:/media/external:Z
```

### 3. Configure the Claim Token (First Run)

On first run, Plex needs a claim token to link to your account. Generate one at [plex.tv/claim](https://www.plex.tv/claim) (tokens expire after 4 minutes):

```bash
# Uncomment and set in plex.container before first start:
Environment=PLEX_CLAIM=claim-xxxxxxxxxxxxxxxxxxxx
```

After the initial setup, remove or comment out this line -- it's only needed once.

### 4. Install the Quadlet File

```bash
mkdir -p ~/.config/containers/systemd
cp plex.container ~/.config/containers/systemd/
systemctl --user daemon-reload
```

### 5. Start Plex

```bash
systemctl --user start plex.service
```

The first start pulls the image and may take a few minutes. Once running, access the web UI at `http://localhost:32400/web`.

### 6. Verify

```bash
podman ps --filter name=plex
curl -s http://localhost:32400/identity | head -1
```

## Adding Libraries After Setup

1. Edit `plex.container` to add new `Volume=` lines
2. Reload and restart:
   ```bash
   systemctl --user daemon-reload
   systemctl --user restart plex.service
   ```
3. In the Plex web UI, go to Settings > Libraries > Add Library and select the container path you mapped

## GPU Hardware Transcoding

Requires a Plex Pass subscription. Uncomment the appropriate `AddDevice=` line in `plex.container`:

| GPU | Line to Uncomment | Additional Requirements |
|-----|-------------------|------------------------|
| NVIDIA | `AddDevice=nvidia.com/gpu=all` | `nvidia-container-toolkit` package |
| Intel Quick Sync | `AddDevice=/dev/dri:/dev/dri` | None (built into kernel) |
| AMD VA-API | `AddDevice=/dev/dri:/dev/dri` | `mesa-va-drivers` package |

## Data Persistence

| Host Path | Container Mount | Purpose |
|-----------|----------------|---------|
| `/srv/containers/plex/config` | `/config` | Server settings, database, metadata |
| `/srv/containers/plex/transcode` | `/transcode` | Temporary transcoding files |
| (your media paths) | `/media/*` | Media libraries |

## Port Reference

When using host networking, Plex binds these ports directly:

| Port | Protocol | Purpose |
|------|----------|---------|
| 32400 | TCP | Web UI and API (primary) |
| 1900 | UDP | DLNA discovery |
| 5353 | UDP | mDNS/Bonjour |
| 8324 | TCP | Plex Companion |
| 32410-32414 | UDP | GDM network discovery |
| 32469 | TCP | DLNA media streaming |

If you switch to bridge networking, only publish port 32400 -- the discovery ports require host networking to function.
