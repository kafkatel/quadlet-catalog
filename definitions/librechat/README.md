# LibreChat

[LibreChat](https://github.com/danny-avila/LibreChat) is a self-hosted AI chat platform that supports multiple AI providers (OpenAI, Anthropic, Google, local models) with features like conversation branching, RAG (Retrieval-Augmented Generation), search, and file uploads.

## Stack Components

| Service | Image | Description |
|---------|-------|-------------|
| librechat-api | `ghcr.io/danny-avila/librechat-dev-api` | Main application server (port 3080) |
| librechat-rag-api | `ghcr.io/danny-avila/librechat-rag-api-dev-lite` | RAG API for document retrieval (port 8000) |
| librechat-mongodb | `docker.io/library/mongo` | Conversation and user data storage |
| librechat-meilisearch | `docker.io/getmeili/meilisearch:v1.12.3` | Full-text search engine |
| librechat-valkey | `docker.io/valkey/valkey` | Session cache and rate limiting |
| librechat-vectordb | `docker.io/ankane/pgvector` | Vector database for RAG embeddings |

## Architecture

```
                    ┌──────────────────────────────────────────────┐
                    │              librechat pod                   │
                    │           (shared localhost)                 │
                    │                                              │
  Host :3080 ───►   │  librechat-api                               │
                    │    ├── librechat-rag-api (localhost:8000)    │
                    │    ├── librechat-mongodb (localhost:27017)   │
                    │    ├── librechat-meilisearch (localhost:7700)│
                    │    ├── librechat-valkey (localhost:6379)     │
                    │    └── librechat-vectordb (localhost:5432)   │
                    └──────────────────────────────────────────────┘
```

- **Pod** (`librechat.pod`): All six containers run inside a single pod, sharing a network namespace. Services communicate over `localhost` using their native ports.
- **No separate network**: Since all containers share the pod's network namespace, no bridge network is needed.
- **Port exposure**: Only port 3080 (the API/UI) is published to the host via the pod.
- **Dependency chain**: `librechat-api` depends on all other services via `Requires=`. Starting or enabling `librechat-api` pulls in the entire stack.

## Quadlet Files

| File | Type | Purpose |
|------|------|---------|
| `librechat.pod` | Pod | Groups all containers, publishes port 3080 |
| `librechat-api.container` | Container | Main API and web UI |
| `librechat-rag-api.container` | Container | RAG document retrieval API |
| `librechat-mongodb.container` | Container | MongoDB for conversations and users |
| `librechat-meilisearch.container` | Container | Meilisearch for full-text search |
| `librechat-valkey.container` | Container | Valkey (Redis) for caching |
| `librechat-vectordb.container` | Container | PGVector for RAG embeddings |

## Prerequisites

- Podman 4.4+ with Quadlet support
- API keys for at least one AI provider (OpenAI, Anthropic, etc.)
- LibreChat configuration files

## Setup

### 1. Create Host Directories

The stack stores configuration and persistent data under `/srv/containers/librechat/`. This path inherits the correct SELinux context (`var_t`) on Fedora/RHEL systems, so containers can bind-mount subdirectories without manual relabeling.

```bash
sudo mkdir -p /srv/containers/librechat/{conf,images,uploads,logs}
sudo mkdir -p /srv/containers/librechat/{meilisearch_data,mongodb_data,pgvector_data}
sudo mkdir -p /srv/containers/librechat/valkey/{data,conf}
```

Verify the SELinux context is correct:

```bash
ls -Zd /srv/containers/librechat/
# Expected: system_u:object_r:var_t:s0
```

### 2. Configure LibreChat

Place your configuration files in `/srv/containers/librechat/conf/`:

```bash
# Main LibreChat configuration
sudo cp librechat.yaml /srv/containers/librechat/conf/librechat.yaml

# Environment file with API keys and settings
sudo cp librechat.env /srv/containers/librechat/conf/librechat.env

# PostgreSQL credentials for the vector database
sudo cp postgres.env /srv/containers/librechat/conf/postgres.env
```

The `librechat.env` file should contain your AI provider API keys and application settings. See the [LibreChat documentation](https://www.librechat.ai/docs/configuration) for all available options.

The `postgres.env` file should contain:

```ini
POSTGRES_USER=rag
POSTGRES_PASSWORD=your-secure-password
POSTGRES_DB=rag
```

### 3. Configure Valkey

Create a Valkey configuration file:

```bash
cat > /srv/containers/librechat/valkey/conf/valkey.conf << 'EOF'
bind 0.0.0.0
port 6379
save 60 1000
appendonly yes
EOF
```

### 4. Install Quadlet Files

```bash
# User-level
mkdir -p ~/.config/containers/systemd
cp *.pod *.container ~/.config/containers/systemd/
systemctl --user daemon-reload

# Or with podman quadlet install (Podman 5.0+)
podman quadlet install *.pod *.container
```

### 5. Start the Stack

Starting the API service pulls in all dependencies:

```bash
systemctl --user start librechat-api.service
```

### 6. Verify

```bash
# Check all containers are running
podman ps --filter name=librechat

# Test the web UI
curl -s http://localhost:3080 | head -5
```

Access the web UI at `http://localhost:3080`. Create an account on first access.

## Data Persistence

All persistent data is stored under `/srv/containers/librechat/`:

| Directory | Container Mount | Purpose |
|-----------|----------------|---------|
| `conf/librechat.yaml` | `/app/librechat.yaml` | Application configuration |
| `conf/librechat.env` | (EnvironmentFile) | Environment variables |
| `conf/postgres.env` | (EnvironmentFile) | PostgreSQL credentials |
| `images/` | `/app/client/public/images` | User-uploaded images |
| `uploads/` | `/app/uploads` | File uploads |
| `logs/` | `/app/api/logs` | API logs |
| `mongodb_data/` | `/data/db` | MongoDB data |
| `meilisearch_data/` | `/meili_data` | Search index |
| `pgvector_data/` | `/var/lib/postgresql/data` | Vector embeddings |
| `valkey/data/` | `/data` | Cache persistence |
| `valkey/conf/valkey.conf` | `/etc/valkey.conf` | Valkey configuration |

All volume mounts use the `:Z` suffix for SELinux relabeling.

## Boot Enablement

To start LibreChat automatically on boot:

```bash
systemctl --user enable librechat-api.service
```

This enables the pod (via `WantedBy=default.target` on `librechat.pod`) and all dependent services.
