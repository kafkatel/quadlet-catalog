# httpbin

[go-httpbin](https://github.com/mccutchen/go-httpbin) is a Go reimplementation of the classic httpbin HTTP request/response testing service. It echoes back request details, making it useful for testing HTTP clients, proxies, and debugging network issues.

## Stack Components

| Service | Image | Description |
|---------|-------|-------------|
| httpbin | `mccutchen/go-httpbin:2.22.1` | HTTP testing API |

## Quadlet Files

| File | Purpose |
|------|---------|
| `httpbin.container` | Main container |

## Prerequisites

- Podman 4.4+ with Quadlet support

## Setup

### 1. Install Quadlet Files

```bash
podman quadlet install httpbin.container
```

### 2. Start httpbin

```bash
systemctl --user start httpbin.service
```

### 3. Verify

```bash
curl -s http://localhost:8080/get | python3 -m json.tool
```

## Endpoints

| Endpoint | Description |
|----------|-------------|
| `/get` | Returns GET request data |
| `/post` | Returns POST request data |
| `/headers` | Returns request headers |
| `/ip` | Returns origin IP |
| `/status/:code` | Returns given HTTP status code |
| `/delay/:seconds` | Delays response by N seconds |
| `/redirect/:n` | 302 redirects N times |
| `/anything` | Returns anything passed in the request |
| `/forms/post` | HTML form for testing POST |

Full API docs at `http://localhost:8080/`.

## Configuration

Environment variables (set via `Environment=` in the container file):

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `8080` | Listen port |
| `MAX_BODY_SIZE` | `1048576` | Max request body (bytes) |
| `MAX_DURATION` | `10s` | Max duration for `/delay` |

## Port Configuration

| Host Port | Container Port | Protocol |
|-----------|---------------|----------|
| 8080 | 8080 | HTTP |
