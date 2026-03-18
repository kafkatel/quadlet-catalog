# Firecrawl

[Firecrawl](https://github.com/mendableai/firecrawl) is an API service that crawls and scrapes websites, converting web content into clean markdown or structured data. It uses Playwright for browser-based rendering to handle JavaScript-heavy pages.

## Stack Components

| Service | Image | Description |
|---------|-------|-------------|
| firecrawl-api | `ghcr.io/firecrawl/playwright-service` | REST API server (port 3002) |
| firecrawl-worker | `ghcr.io/firecrawl/firecrawl` | Background job worker for crawl/scrape tasks |
| firecrawl-playwright | `ghcr.io/firecrawl/playwright-service` | Headless browser microservice for page rendering |
| firecrawl-redis | `docker.io/valkey/valkey` | Job queue and rate limiting (Valkey) |

## Architecture

```
                        ┌─────────────────────────────────────────┐
                        │         firecrawl-backend network       │
                        │                                         │
  Host :3002 ──────►    │  firecrawl-api ──► firecrawl-playwright │
                        │       │                                 │
                        │       ▼                                 │
                        │  firecrawl-worker ──► firecrawl-redis   │
                        └─────────────────────────────────────────┘
```

- **Network** (`firecrawl-network.network`): All four containers run on a shared bridge network (`firecrawl-backend`). Containers resolve each other by name via Podman DNS.
- **Pod** (`firecrawl.pod`): Defined but not referenced by the containers -- the containers use the network directly. The pod publishes port 3080.
- **Port exposure**: The API container publishes port 3002 to the host. The Playwright service (port 3000) is internal to the network.
- **No named volumes**: Data is ephemeral. Redis is used as a transient job queue.

## Quadlet Files

| File | Type | Purpose |
|------|------|---------|
| `firecrawl.pod` | Pod | Pod definition (publishes port 3080) |
| `firecrawl-network.network` | Network | Bridge network for inter-container communication |
| `firecrawl-api.container` | Container | API server |
| `firecrawl-worker.container` | Container | Background job worker |
| `firecrawl-playwright.container` | Container | Playwright rendering microservice |
| `firecrawl-redis.container` | Container | Valkey (Redis) for job queue |
| `firecrawl.env` | Environment | Configuration template |

## Prerequisites

- Podman 4.4+ with Quadlet support
- API keys for any optional integrations (OpenAI, Serper, etc.)

## Setup

### 1. Prepare Configuration

Copy and edit the environment file with your values:

```bash
cp firecrawl.env /etc/firecrawl/firecrawl.env
# Edit with your API keys and configuration
```

The environment file contains configuration for:

- **Redis**: Pre-configured for inter-container networking
- **OpenAI/Ollama**: For AI-powered content extraction
- **Proxy**: For routing requests through a proxy server
- **Search APIs**: Serper, SearchAPI, SearXNG integration
- **Supabase**: For database authentication
- **Analytics**: PostHog integration

Most values can be left empty for a basic deployment. At minimum, you may want to set `TEST_API_KEY` for API authentication.

### 2. Install Quadlet Files

```bash
# User-level
mkdir -p ~/.config/containers/systemd
cp *.container *.network *.pod *.env ~/.config/containers/systemd/
systemctl --user daemon-reload

# Or with podman quadlet install (Podman 5.0+)
podman quadlet install *.container *.network *.pod *.env
```

### 3. Start the Stack

```bash
# Start the network first, then services
systemctl --user start firecrawl-network-network.service
systemctl --user start firecrawl-redis.service
systemctl --user start firecrawl-playwright.service
systemctl --user start firecrawl-api.service
systemctl --user start firecrawl-worker.service
```

Or start everything via dependencies (the API and worker containers declare `Requires=` on their dependencies):

```bash
systemctl --user start firecrawl-worker.service
```

### 4. Verify

```bash
# Check all containers are running
podman ps --filter name=firecrawl

# Test the API
curl http://localhost:3002/v0/scrape \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TEST_API_KEY" \
  -d '{"url": "https://example.com"}'
```

## Health Checks

| Service | Health Check | Interval |
|---------|-------------|----------|
| firecrawl-redis | `redis-cli ping` | 30s |

## Environment Variables

See `firecrawl.env` for the complete list. Key variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `REDIS_URL` | `redis://firecrawl-redis:6379` | Redis connection (pre-configured) |
| `PLAYWRIGHT_MICROSERVICE_URL` | `http://firecrawl-playwright:3000/scrape` | Playwright service URL (pre-configured) |
| `PORT` | `3002` | API listening port |
| `TEST_API_KEY` | (empty) | API authentication key |
| `OPENAI_API_KEY` | (empty) | OpenAI API key for AI extraction |
| `LOGGING_LEVEL` | `info` | Log verbosity |

## Resource Limits

All containers set `Ulimit=nofile=65535:65535` to handle high connection counts.
