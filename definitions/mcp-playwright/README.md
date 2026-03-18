# MCP Playwright

[Playwright MCP](https://github.com/microsoft/playwright-mcp) is Microsoft's official Model Context Protocol server for Playwright, enabling AI agents to interact with web pages through browser automation.

## Stack Components

| Service | Image | Description |
|---------|-------|-------------|
| mcp-playwright | `mcr.microsoft.com/playwright/mcp` | Playwright MCP server (port 8931) |

## Architecture

This is a standalone container that joins an external shared pod (`mcp-servers.pod`). It does not define its own pod or network.

```
  ┌─────────────────────────────┐
  │       mcp-servers pod       │
  │                             │
  │  mcp-playwright (:8931)     │
  │  (other MCP servers...)     │
  └─────────────────────────────┘
```

The container references `Pod=mcp-servers.pod`, which must be defined separately. This allows multiple MCP server containers to share a single pod and be managed together.

## Quadlet Files

| File | Type | Purpose |
|------|------|---------|
| `mcp-playwright.container` | Container | Playwright MCP server |

## Prerequisites

- Podman 4.4+ with Quadlet support
- An `mcp-servers.pod` definition (defined elsewhere or created manually)

## Setup

### 1. Create Host Directories

The container uses the `%N` systemd specifier, which expands to the unit name (`mcp-playwright`). Create the directories under `/srv/containers/`:

```bash
sudo mkdir -p /srv/containers/mcp-playwright/{data,conf}
```

Using `/srv/containers/` ensures the correct SELinux context (`var_t`) is inherited, so the `:Z` volume mounts work without manual relabeling.

| Host Path | Container Mount | Purpose |
|-----------|----------------|---------|
| `/srv/containers/mcp-playwright/data` | `/app/output` | Screenshots and output files |
| `/srv/containers/mcp-playwright/conf` | `/home/node/.cache/ms-playwright/` | Playwright browser cache |

### 2. Ensure the Shared Pod Exists

This container expects an `mcp-servers.pod` file to be installed. If you don't have one, create a minimal pod:

```ini
# mcp-servers.pod
[Unit]
Description=Pod for MCP Servers

[Pod]
PublishPort=8931:8931

[Install]
WantedBy=default.target
```

### 3. Install Quadlet Files

```bash
mkdir -p ~/.config/containers/systemd
cp mcp-playwright.container ~/.config/containers/systemd/
# Also install mcp-servers.pod if not already present
systemctl --user daemon-reload
```

### 4. Start the Service

```bash
systemctl --user start mcp-playwright.service
```

### 5. Verify

```bash
podman ps --filter name=mcp-playwright
```

## Configuration

The container starts with the following flags:

| Flag | Value | Description |
|------|-------|-------------|
| `--host` | `0.0.0.0` | Listen on all interfaces |
| `--port` | `8931` | MCP server port |
| `--vision` | (enabled) | Enable vision/screenshot capabilities |
| `--output-dir` | `/app/output` | Directory for screenshots and output |

## MCP Client Configuration

To connect an MCP client (e.g., Claude Desktop) to this server:

```json
{
  "mcpServers": {
    "playwright": {
      "url": "http://localhost:8931/sse"
    }
  }
}
```
