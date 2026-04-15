# PrivateBin

[PrivateBin](https://privatebin.info/) is a minimalist, zero-knowledge encrypted pastebin. Data is encrypted in the browser before being sent to the server, so the server never sees the plaintext content.

## Stack Components

| Service | Image | Description |
|---------|-------|-------------|
| privatebin | `privatebin/nginx-fpm-alpine:stable` | Encrypted pastebin with nginx + PHP-FPM |

## Quadlet Files

| File | Purpose |
|------|---------|
| `privatebin.container` | Main container (read-only filesystem) |
| `privatebin-data.volume` | Persistent paste storage |

## Prerequisites

- Podman 4.4+ with Quadlet support

## Setup

### 1. Install Quadlet Files

```bash
podman quadlet install privatebin.container privatebin-data.volume
```

### 2. Start PrivateBin

```bash
systemctl --user start privatebin.service
```

### 3. Verify

```bash
podman ps --filter name=privatebin
curl -s http://localhost:8080/ -o /dev/null -w "HTTP %{http_code}\n"
```

Access the web UI at `http://localhost:8080`.

## Configuration

The default configuration works out of the box. To customize expiration times, paste limits, or syntax highlighting, create a config file:

```bash
sudo mkdir -p /srv/containers/privatebin
sudo cp /path/to/conf.php.sample /srv/containers/privatebin/conf.php
```

Then uncomment the configuration volume line in `privatebin.container`. See the [PrivateBin configuration documentation](https://github.com/PrivateBin/PrivateBin/wiki/Configuration) for available options.

## Security

- The container runs with a read-only root filesystem.
- All paste data is encrypted client-side (zero-knowledge). The server cannot decrypt pastes.
- The encryption key is part of the URL fragment (`#`), which is never sent to the server.

## Port Configuration

| Host Port | Container Port | Protocol |
|-----------|---------------|----------|
| 8080 | 8080 | HTTP |
