# Context7 MCP Server

[Context7](https://github.com/upstash/context7) is a Model Context Protocol server that provides AI agents with up-to-date library and framework documentation. Instead of relying on stale training data, agents query Context7 to get current docs and code examples for any library.

This is the canonical system-level definition -- a standalone Context7 instance that can serve any MCP client on the host.

## Stack Components

| Service | Image | Description |
|---------|-------|-------------|
| mcp-context7 | `docker.io/mcp/context7:latest` | Context7 MCP server |

## Architecture

Standalone container. By default it uses stdio transport for direct MCP client integration. It can optionally join a shared `mcp-servers.pod` alongside other MCP servers (like mcp-playwright), or run with SSE transport for network access.

```
  MCP client ──stdio──► mcp-context7

  # Or with SSE transport:
  MCP client ──http──► Host :3000 ──► mcp-context7
```

## Quadlet Files

| File | Type | Purpose |
|------|------|---------|
| `mcp-context7.container` | Container | Context7 MCP server |

## Prerequisites

- Podman 4.4+ with Quadlet support

## MCP Tools

The server exposes two tools:

| Tool | Purpose |
|------|---------|
| `resolve-library-id` | Resolve a library/framework name to a Context7 library ID |
| `query-docs` | Fetch documentation for a resolved library ID |

Always call `resolve-library-id` first to get the exact ID, then pass it to `query-docs`.

## Setup

### 1. Install the Quadlet File

```bash
cd definitions/mcp-context7/
podman quadlet install *.container
```

Or manually:

```bash
mkdir -p ~/.config/containers/systemd
cp mcp-context7.container ~/.config/containers/systemd/
systemctl --user daemon-reload
```

### 2. Start the Service

```bash
systemctl --user start mcp-context7.service
```

### 3. Verify

```bash
podman ps --filter name=mcp-context7
```

## MCP Client Configuration

### Stdio Transport (default)

For Claude Desktop, Cursor, or other MCP clients that manage container lifecycle directly:

```json
{
  "mcpServers": {
    "context7": {
      "command": "podman",
      "args": ["run", "-i", "--rm", "docker.io/mcp/context7:latest"]
    }
  }
}
```

### SSE Transport (network-accessible)

To run Context7 as a persistent network service, uncomment the SSE lines in `mcp-context7.container`:

```ini
Exec=--transport sse --port 3000
PublishPort=3000:3000
```

Then reload and restart:

```bash
systemctl --user daemon-reload
systemctl --user restart mcp-context7.service
```

Connect MCP clients to the SSE endpoint:

```json
{
  "mcpServers": {
    "context7": {
      "url": "http://localhost:3000/sse"
    }
  }
}
```

### Joining a Shared MCP Pod

To run alongside other MCP servers in a shared pod (like `mcp-playwright`), uncomment `Pod=mcp-servers.pod` in the container file. The pod must be defined separately. See `definitions/mcp-playwright/` for the pattern.
