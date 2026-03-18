# Perplexity Sonar

[Perplexity Sonar](https://docs.perplexity.ai/) is an MCP server that integrates the Perplexity Sonar API to provide AI agents with real-time web search capabilities. This definition builds the container image from the upstream [ppl-ai/modelcontextprotocol](https://github.com/ppl-ai/modelcontextprotocol) source.

## Stack Components

| Service | Image | Description |
|---------|-------|-------------|
| perplexity-sonar | `localhost/perplexity-sonar` (locally built) | Perplexity Sonar MCP server |

## Architecture

```
  ┌──────────────────────────────────────────┐
  │       perplexity-sonar network           │
  │                                          │
  │   ┌──────────────────────────────────┐   │
  │   │      perplexity-sonar pod        │   │
  │   │                                  │   │
  │   │   perplexity-sonar (MCP server)  │   │
  │   └──────────────────────────────────┘   │
  └──────────────────────────────────────────┘
```

- **Build** (`perplexity-sonar.build`): Builds the container image from the local `src/perplexity-ask/Dockerfile` (upstream source included as a git submodule).
- **Network** (`perplexity-sonar.network`): Bridge network for the pod.
- **Pod** (`perplexity-sonar.pod`): Attached to the network.
- **Container** (`perplexity-sonar.container`): Runs inside the pod, using the locally-built image.

## Quadlet Files

| File | Type | Purpose |
|------|------|---------|
| `perplexity-sonar.build` | Build | Builds image from `src/perplexity-ask/Dockerfile` |
| `perplexity-sonar.pod` | Pod | Pod attached to the network |
| `perplexity-sonar.network` | Network | Bridge network |
| `perplexity-sonar.container` | Container | MCP server |
| `perplexity-sonar.env` | Environment | API key configuration |

## Prerequisites

- Podman 4.4+ with Quadlet support
- A [Perplexity Sonar API key](https://docs.perplexity.ai/guides/getting-started)
- Git (to initialize the submodule)

## Setup

### 1. Initialize the Git Submodule

The upstream source code is pulled in via a git submodule:

```bash
git submodule update --init definitions/perplexity-sonar/src
```

This clones the [ppl-ai/modelcontextprotocol](https://github.com/ppl-ai/modelcontextprotocol) repository into `src/`.

### 2. Configure the API Key

Edit `perplexity-sonar.env` with your Sonar API key:

```ini
PERPLEXITY_API_KEY=pplx-your-api-key-here
```

Get a key by signing up at the [Perplexity API dashboard](https://docs.perplexity.ai/guides/getting-started).

### 3. Install Quadlet Files

```bash
mkdir -p ~/.config/containers/systemd
cp *.build *.pod *.network *.container *.env ~/.config/containers/systemd/
systemctl --user daemon-reload
```

### 4. Start the Service

The container depends on the build completing first (via `Requires=perplexity-sonar.build`):

```bash
systemctl --user start perplexity-sonar.service
```

On first start, this will build the container image from source, then launch it.

### 5. Verify

```bash
# Check the image was built
podman images localhost/perplexity-sonar

# Check the container is running
podman ps --filter name=perplexity-sonar
```

## Build Details

The image is built using a multi-stage Dockerfile:

1. **Builder stage**: Installs npm dependencies using Node.js 22 Alpine
2. **Release stage**: Copies the compiled `dist/` output and production dependencies
3. **Entrypoint**: `node dist/index.js`

The build tag is `localhost/perplexity-sonar:latest`. The build context is set to the Dockerfile's parent directory (`SetWorkingDirectory=file`).

## MCP Tools

The server exposes one tool:

- **`perplexity_ask`** -- Send conversational queries to the Sonar API for live web search results. Accepts an array of messages with `role` and `content` fields.

## MCP Client Configuration

```json
{
  "mcpServers": {
    "perplexity-ask": {
      "command": "podman",
      "args": [
        "run", "-i", "--rm",
        "-e", "PERPLEXITY_API_KEY",
        "localhost/perplexity-sonar"
      ],
      "env": {
        "PERPLEXITY_API_KEY": "pplx-your-api-key-here"
      }
    }
  }
}
```
