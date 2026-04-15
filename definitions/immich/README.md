# Immich

[Immich](https://immich.app/) is a self-hosted photo and video management solution with mobile app backup, facial recognition, CLIP-based smart search, albums, and sharing. It is a high-performance alternative to Google Photos.

## Stack Components

| Service | Image | Description |
|---------|-------|-------------|
| immich-server | `ghcr.io/immich-app/immich-server:v2.6` | API server and web UI |
| immich-machine-learning | `ghcr.io/immich-app/immich-machine-learning:v2.6` | Facial recognition and smart search |
| immich-redis | `valkey/valkey:9` | Job queue and session cache |
| immich-postgres | `ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0` | Metadata and vector embeddings |

## Architecture

The stack uses a pod for the Immich server and a bridge network for infrastructure services:

- **Pod** (`immich.pod`): Contains `immich-server`. Publishes port 2283 to the host. Attached to the backend network.
- **Network** (`immich-network.network`): Infrastructure services (`immich-postgres`, `immich-redis`) and the ML sidecar run standalone on this bridge network.

```
                  ┌─── immich pod ──────────────────────┐
  Browser ─2283─► │  immich-server                      │
  Mobile  ─2283─► │    ├──► immich-postgres (network)   │
                  │    ├──► immich-redis (network)       │
                  │    └──► immich-machine-learning (net)│
                  └─────────────────────────────────────┘
```

## Quadlet Files

| File | Purpose |
|------|---------|
| `immich.pod` | Pod for the server; publishes port 2283 |
| `immich-network.network` | Backend bridge network |
| `immich-server.container` | API + web UI |
| `immich-machine-learning.container` | ML sidecar (facial recognition, smart search) |
| `immich-redis.container` | Valkey cache and job queue |
| `immich-postgres.container` | PostgreSQL with pgvecto.rs/VectorChord |
| `immich.env` | Shared credentials |
| `immich-pgdata.volume` | Database persistence |
| `immich-model-cache.volume` | ML model download cache |

## Prerequisites

- Podman 4.4+ with Quadlet support
- Sufficient storage for photo/video library

## Setup

### 1. Create Host Directories

```bash
sudo mkdir -p /srv/containers/immich/library
```

### 2. Configure Environment

Edit `immich.env` and set `POSTGRES_PASSWORD`:

```bash
python3 -c "import secrets; print(secrets.token_hex(16))"
```

Use only alphanumeric characters (A-Za-z0-9) for the password.

### 3. Install Quadlet Files

```bash
podman quadlet install *.pod *.container *.network *.volume immich.env
```

Or manually:

```bash
mkdir -p ~/.config/containers/systemd
cp *.pod *.container *.network *.volume immich.env ~/.config/containers/systemd/
systemctl --user daemon-reload
```

### 4. Start the Stack

```bash
systemctl --user start immich-server.service
```

This pulls in postgres, redis, and the pod via dependency chains. Start the ML service separately:

```bash
systemctl --user start immich-machine-learning.service
```

### 5. Verify

```bash
podman ps --filter name=immich
curl -s http://localhost:2283/api/server/ping
```

Access the web UI at `http://localhost:2283`. Create an admin account on first login.

## GPU Acceleration

### Hardware Transcoding (Server)

Uncomment the GPU device lines in `immich-server.container`. See the [Immich transcoding docs](https://immich.app/docs/features/hardware-transcoding).

### ML Acceleration

Change the image tag in `immich-machine-learning.container`:

| GPU | Image Tag |
|-----|-----------|
| NVIDIA CUDA | `v2.6-cuda` |
| AMD ROCm | `v2.6-rocm` |
| Intel OpenVINO | `v2.6-openvino` |

Then uncomment the corresponding device and group lines. See the [Immich ML acceleration docs](https://immich.app/docs/features/ml-hardware-acceleration).

## Mobile App

Install the Immich app from [Google Play](https://play.google.com/store/apps/details?id=app.alextran.immich) or [App Store](https://apps.apple.com/app/immich/id1613945686). Point it at `http://YOUR_SERVER:2283`.

## Port Configuration

| Host Port | Container Port | Protocol |
|-----------|---------------|----------|
| 2283 | 2283 | HTTP |
