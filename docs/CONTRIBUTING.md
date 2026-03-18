# Contributing to the Quadlet Catalog

This guide covers how to add new application definitions to the catalog.

## Overview

The quadlet-catalog is a collection of [Podman Quadlet](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html) definitions that describe containerized application stacks as systemd units. Each definition is a set of declarative files that Podman's systemd generator converts into `.service` units, allowing containers to be managed with `systemctl`.

## Repository Structure

```
quadlet-catalog/
├── definitions/           # All application definitions live here
│   ├── firecrawl/         # Multi-container stack (pod + 4 containers + network)
│   ├── librechat/         # Multi-container stack (pod + 6 containers)
│   ├── mcp-playwright/    # Single-container definition
│   └── perplexity-sonar/  # Container built from local source (uses .build)
├── docs/                  # Documentation and reference material
└── .gitmodules            # Git submodule declarations (for local builds)
```

## Quadlet File Types

Each application definition is composed of one or more of these file types:

| Extension    | Purpose                          | Required? |
|-------------|----------------------------------|-----------|
| `.container` | Defines a single container       | Yes       |
| `.pod`       | Groups containers into a pod     | Multi-container stacks |
| `.network`   | Creates a Podman network         | When containers need private networking |
| `.volume`    | Declares a named volume          | When using named volumes |
| `.build`     | Builds an image from a Dockerfile| When images are built locally |
| `.env`       | Environment variable template    | When configuration is needed |

## Naming Conventions

All files within a definition follow strict naming patterns:

- **Directory**: `definitions/{appname}/`
- **Pod file**: `{appname}.pod`
- **Container files**: `{appname}-{component}.container`
- **Network file**: `{appname}-{network-name}.network`
- **Volume files**: `{appname}-{volume-name}.volume`
- **Build file**: `{appname}.build`
- **Environment file**: `{appname}.env`

The `{appname}` prefix must be consistent across all files in the definition. Component names should be descriptive (e.g., `api`, `worker`, `redis`, `mongodb`).

## Adding a New Definition

### Step 1: Create the Definition Directory

```
mkdir definitions/{appname}
```

### Step 2: Choose Your Architecture

Determine which files your definition needs based on complexity:

**Single container** (e.g., a standalone MCP server):
- `{appname}.container` only

**Multi-container stack** (e.g., an app with a database and cache):
- `{appname}.pod` - publishes ports, attached to the network
- `{appname}-{network}.network` - bridge network for inter-container DNS resolution
- `{appname}-{component}.container` - one per service
- `{appname}.env` - for shared configuration

Containers in a pod share a network namespace (localhost), so two services binding the same port would conflict. Place only the application containers in the pod (via `Pod={appname}.pod`) and run infrastructure services (databases, caches) standalone on the network (via `Network={appname}-{network}.network`). The pod joins the same network, so pod containers resolve standalone containers by name. See `definitions/quay/` for an example of this hybrid pattern.

**Locally-built image** (e.g., building from upstream source):
- `{appname}.build` - image build spec
- `{appname}.container` - references the `.build` file as its image
- Source code via git submodule or vendored files

### Step 3: Write the Quadlet Files

The sections below provide templates and conventions for each file type.

---

## File Templates and Conventions

### Pod File (`{appname}.pod`)

A pod groups related containers. Ports are published at the pod level.

```ini
[Unit]
Description=Pod for the {AppName} Application Stack
After=network-online.target {appname}-network-network.service
Wants=network-online.target
Requires={appname}-network-network.service

[Pod]
# Attach the pod to the backend network so pod containers can resolve
# standalone infrastructure containers by name.
Network={appname}-{network}.network

# Publish the main service port on the pod.
PublishPort={host_port}:{container_port}

[Install]
WantedBy=default.target
```

Key points:
- Publish externally-accessible ports here, not in individual containers.
- Set `Network=` to attach the pod to the bridge network for DNS resolution of standalone containers.
- Use `AddHost=host.docker.internal:host-gateway` if containers need to reach the host.
- The `[Install]` section with `WantedBy=default.target` enables the pod on boot when the user runs `systemctl --user enable {appname}-pod.service`.

### Container File (`{appname}-{component}.container`)

Each container in the stack gets its own file.

```ini
# {appname}-{component}.container
# Quadlet container file for {Component} service

[Unit]
Description={Component} container for {AppName}
After=network-online.target {dependencies}
Wants=network-online.target
Requires={hard-dependencies}

[Container]
Image={registry}/{image}:{tag}
ContainerName={appname}-{component}
# Use Pod= for application containers that need port publication via the pod.
# Use Network= for infrastructure containers that run standalone on the network.
# Do not set both -- Pod= ignores Network= since the pod controls networking.
Pod={appname}.pod

# Environment
EnvironmentFile=./{appname}.env
Environment=SPECIFIC_VAR=value

# Data persistence
Volume={appname}-data.volume:/container/path:Z

# Health check (recommended for databases and critical services)
HealthCmd={health-check-command}
HealthInterval=30s
HealthRetries=3
HealthTimeout=5s

[Service]
Restart=always
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
```

Key points:

- **Image sources**: Use fully-qualified image references (`docker.io/library/postgres:16`, `ghcr.io/org/image:tag`). For locally-built images, reference the `.build` file: `Image={appname}.build`.
- **Pod membership**: Set `Pod={appname}.pod` to join the pod. Omit for standalone infrastructure containers.
- **Network**: Set `Network={appname}-{network}.network` for standalone containers that need DNS resolution by name. Do not set `Network=` on containers that use `Pod=` -- the pod controls their networking. Set `Network=` on the `.pod` file instead to attach the pod to the bridge network.
- **Dependencies**: Use `After=` and `Requires=` to control startup order. Reference other Quadlet files, which get translated to systemd service names:
  - `{appname}-{component}.container` becomes `{appname}-{component}.service`
  - `{appname}-{network}.network` becomes `{appname}-{network}-network.service`
- **Volumes**: Prefer named volumes (`{name}.volume:/path:Z`) over bind mounts (`/host/path:/path:Z`). The `:Z` suffix is required on SELinux-enabled systems (Fedora, RHEL, CentOS) to set the correct context.
- **Health checks**: Add health checks for databases and services that other containers depend on.
- **TimeoutStartSec**: Set to `300` (5 minutes) to allow for initial image pulls.
- **Exec**: Override the container entrypoint/command when needed.

### Network File (`{appname}-{network}.network`)

```ini
# {appname}-{network}.network
# Quadlet network file for {description}

[Unit]
Description={AppName} backend network
After=network-online.target
Wants=network-online.target

[Network]
NetworkName={appname}-{network-name}
Driver=bridge
Internal=false

[Install]
WantedBy=multi-user.target
```

Key points:
- Set `Internal=true` if containers should not have outbound internet access.
- The network name in `NetworkName=` is the DNS domain; containers use `ContainerName` values as hostnames within this network.

### Volume File (`{appname}-{volume}.volume`)

```ini
[Unit]
Description={AppName} {description} volume
```

Volume files are minimal. Podman manages the underlying storage location. Reference them from containers as `Volume={appname}-{volume}.volume:/container/path:Z`.

### Build File (`{appname}.build`)

Used when images must be built from source rather than pulled from a registry.

```ini
[Unit]
Description=Build the {AppName} container image from local sources
After=network-online.target
Wants=network-online.target

[Build]
ImageTag=localhost/{appname}:latest
File={path-to-Dockerfile}
SetWorkingDirectory=file
```

Key points:
- `ImageTag` should use the `localhost/` prefix for locally-built images.
- `File` is the path to the Dockerfile, relative to the definition directory.
- `SetWorkingDirectory=file` sets the build context to the Dockerfile's parent directory.
- Source code is typically pulled in via git submodule. Add the submodule to `.gitmodules` at the repo root:
  ```
  [submodule "definitions/{appname}/src"]
      path = definitions/{appname}/src
      url = https://github.com/{org}/{repo}.git
  ```
- The container file references the build with `Image={appname}.build`, and declares the dependency with `After={appname}.build` and `Requires={appname}.build`.

### Environment File (`{appname}.env`)

```ini
# {appname}.env
# Environment variables for {AppName}
# Copy this file and fill in your values before deploying.

# Service URLs (auto-configured for inter-container networking)
DATABASE_URL=postgres://{appname}-postgres:5432/app

# API Keys (fill in before use)
API_KEY=

# Configuration
LOG_LEVEL=info
```

Key points:
- Pre-fill values that can be derived from the stack topology (inter-container URLs, default ports).
- Leave secret values empty with a descriptive comment.
- Group variables by category with comment headers.
- Reference from containers with `EnvironmentFile=./{appname}.env` (relative path) or `EnvironmentFile=/etc/{appname}/{appname}.env` (absolute deploy path).

---

## Dependency Management

Quadlet files reference each other to establish startup ordering. Understanding the name translation is critical:

| Quadlet File                       | Generated systemd Unit              |
|------------------------------------|-------------------------------------|
| `myapp.pod`                        | `myapp-pod.service`                 |
| `myapp-api.container`              | `myapp-api.service`                 |
| `myapp-backend.network`            | `myapp-backend-network.service`     |
| `myapp-data.volume`                | `myapp-data-volume.service`         |
| `myapp.build`                      | `myapp-build.service`               |

Use these translated names in `After=`, `Requires=`, and `Wants=` directives.

**Ordering rules:**
1. Networks must start before any container that uses them.
2. Builds must complete before containers that use the built image.
3. Database and cache containers should start before application containers.
4. Use `Requires=` for hard dependencies (container cannot function without them).
5. Use `Wants=` for soft dependencies (nice to have, but not fatal if missing).

**Example dependency chain:**

```
network.service  -->  database.service  -->  api.service  -->  worker.service
                                         \-> cache.service -/
```

## Standalone Containers (No Pod)

For simple, single-container services, a pod is not needed. The container file can reference an external pod or stand alone.

```ini
[Unit]
Description={Service} MCP Server
Documentation=https://...

[Container]
ContainerName={appname}
Image={registry}/{image}:{tag}
Volume=/srv/containers/%N/data:/app/data:Z
Exec=--host 0.0.0.0 --port 8931

[Service]
Restart=always
```

Notes:
- `%N` is a systemd specifier that expands to the unit name (without the `.service` suffix), useful for per-service host paths.
- A standalone container can reference an external shared pod with `Pod=shared-pod.pod` if it should join a group managed elsewhere.

## Systemd Specifiers

These systemd specifiers can be used in Quadlet files:

| Specifier | Expansion                              | Common Use                      |
|-----------|----------------------------------------|---------------------------------|
| `%N`      | Unit name (without suffix)             | Per-service volume paths        |
| `%i`      | Instance identifier (template units)   | Placeholder for operator values |
| `%h`      | User home directory                    | User-level paths                |
| `%n`      | Full unit name                         | Logging, identification         |

`%i` is used in this catalog as a placeholder in `Environment=` lines to indicate that the value must be provided by the operator at deploy time (via `EnvironmentFile` or systemd drop-in overrides).

## Deployment Targets

Quadlet definitions can run at two levels:

| Level  | Unit Path                            | `WantedBy=`         | Managed With                        |
|--------|--------------------------------------|---------------------|-------------------------------------|
| System | `/etc/containers/systemd/`           | `multi-user.target` | `sudo systemctl ...`                |
| User   | `~/.config/containers/systemd/`      | `default.target`    | `systemctl --user ...`              |

Pods typically use `WantedBy=default.target` (user-level). Individual containers and networks typically use `WantedBy=multi-user.target` (system-level). Adjust based on your deployment model.

## Commit Conventions

This project uses [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: Add quadlet definitions for {AppName}
feat(submodule): Add {appname} model definition
build: Use local Dockerfile for {appname} image
```

Common types:
- `feat` - New definitions or significant additions
- `build` - Changes to build files or image sources
- `fix` - Corrections to existing definitions
- `docs` - Documentation changes

## Checklist for New Definitions

Before submitting a new definition, verify:

- [ ] All files are in `definitions/{appname}/` with consistent naming
- [ ] Container images use fully-qualified references (include registry domain)
- [ ] Dependencies are declared with `After=`, `Requires=`, or `Wants=`
- [ ] Dependency unit names use the correct systemd translation (see table above)
- [ ] Volumes use the `:Z` suffix for SELinux compatibility
- [ ] Secret values are left empty in `.env` files with descriptive comments
- [ ] `TimeoutStartSec=300` is set for containers that pull large images
- [ ] Health checks are defined for database and cache containers
- [ ] Ports are published at the pod level, not on individual containers
- [ ] Containers do not set both `Pod=` and `Network=` (use one or the other)
- [ ] A `README.md` exists in the definition directory with deployment instructions

## Example: Adding a PostgreSQL + Web App Stack

This walkthrough adds a hypothetical "myapp" with a web frontend and PostgreSQL database.

### Directory layout

```
definitions/myapp/
├── myapp.pod
├── myapp.env
├── myapp-network.network
├── myapp-web.container
├── myapp-postgres.container
├── myapp-pgdata.volume
└── README.md
```

### `myapp.pod`

The pod publishes ports and joins the backend network. Only the web container joins the pod.

```ini
[Unit]
Description=Pod for the MyApp Application Stack
After=network-online.target myapp-network-network.service
Wants=network-online.target
Requires=myapp-network-network.service

[Pod]
Network=myapp-network.network
PublishPort=8080:8080

[Install]
WantedBy=default.target
```

### `myapp-network.network`

```ini
[Unit]
Description=MyApp backend network
After=network-online.target
Wants=network-online.target

[Network]
NetworkName=myapp-backend
Driver=bridge
Internal=false

[Install]
WantedBy=multi-user.target
```

### `myapp-pgdata.volume`

```ini
[Unit]
Description=MyApp PostgreSQL data volume
```

### `myapp-postgres.container`

PostgreSQL runs standalone on the network (not in the pod) so it has its own network namespace.

```ini
[Unit]
Description=PostgreSQL database for MyApp
After=network-online.target myapp-network-network.service
Wants=network-online.target
Requires=myapp-network-network.service

[Container]
Image=docker.io/library/postgres:16
ContainerName=myapp-postgres
Network=myapp-network.network
Volume=myapp-pgdata.volume:/var/lib/postgresql/data:Z
EnvironmentFile=./myapp.env
HealthCmd=pg_isready -U postgres
HealthInterval=30s
HealthRetries=3
HealthTimeout=5s

[Service]
Restart=always
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
```

### `myapp-web.container`

The web container joins the pod for port publication. It reaches PostgreSQL by container name via the shared network.

```ini
[Unit]
Description=MyApp web frontend
After=network-online.target myapp-postgres.service
Wants=network-online.target
Requires=myapp-postgres.service

[Container]
Image=ghcr.io/myorg/myapp:latest
ContainerName=myapp-web
Pod=myapp.pod
EnvironmentFile=./myapp.env
Environment=DATABASE_URL=postgres://myapp:secret@myapp-postgres:5432/myapp

[Service]
Restart=always
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
```

### `myapp.env`

```ini
# myapp.env
# Environment variables for MyApp

# PostgreSQL
POSTGRES_USER=myapp
POSTGRES_PASSWORD=
POSTGRES_DB=myapp

# Application
SECRET_KEY=
LOG_LEVEL=info
```

## Reference

The full Quadlet unit file specification is available in `docs/podman-systemd.unit` in this repository, or online at the [Podman Quadlet documentation](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html).
