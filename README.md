# Quadlet Catalog

A collection of [Podman Quadlet](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html) definitions for deploying containerized application stacks as systemd units. Each definition is a set of declarative files that Podman's systemd generator converts into `.service` units, allowing containers to be managed entirely with `systemctl`.

## Intention

Podman is available in the base package set for every distro.

If you already have systemd and are using podman you don't need another
orchestrator, scheduler, or governor.

These are application definitions (squint and imagine that they are RPM SPEC
files) targeted at the sysadmin/system operator crowd. More often than not,
the "version" is set to the underlying project's version of "latest" to ensure
that you automatically get your patches and updates. Occasionally, this can
cause things to break, but you should have the previously launched image on
hand.

## Available Definitions

| Definition | Description | Components | Architecture |
|------------|-------------|------------|--------------|
| [firecrawl](definitions/firecrawl/) | Web scraping API with Playwright-based rendering | API, Worker, Playwright, Redis | Pod + Network |
| [jellyfin](definitions/jellyfin/) | Free open-source media server | Jellyfin server | Standalone container |
| [librechat](definitions/librechat/) | Self-hosted AI chat platform with RAG support | API, RAG API, MongoDB, Meilisearch, Valkey, PGVector | Pod |
| [mcp-context7](definitions/mcp-context7/) | Context7 library documentation MCP server | MCP server | Standalone container |
| [mcp-playwright](definitions/mcp-playwright/) | Microsoft Playwright MCP server | Playwright server | Standalone container |
| [perplexity-sonar](definitions/perplexity-sonar/) | Perplexity Sonar API MCP server (local build) | MCP server | Pod + Network + Build |
| [plex](definitions/plex/) | Plex Media Server | Plex server | Standalone container |
| [quay](definitions/quay/) | Container image registry with vulnerability scanning | Registry, Mirror, Clair, PostgreSQL (x2), Redis | Pod + Network |
| [valkey](definitions/valkey/) | Standalone Valkey (Redis-compatible) key-value store | Valkey server | Standalone container |

### Placeholder Definitions

The following directories exist but do not yet contain quadlet files:

| Definition | Status |
|------------|--------|
| `codejail` | Contains upstream source (git submodule) only |
| `qemu` | Empty -- planned |

## Prerequisites

- Podman 4.4+ with Quadlet support (Podman 5.0+ recommended for `podman quadlet install`)
- systemd (Linux)

### Anti-patterns

- `podman-compose` is **not** required -- systemd manages all services

## Host Directory Setup

Most definitions store configuration and persistent data under `/srv/containers/{appname}/`. This path is used because `/srv` carries the correct SELinux context (`system_u:object_r:var_t:s0`) on Fedora, RHEL, and CentOS, which means Podman containers can bind-mount subdirectories without requiring manual relabeling or `semanage fcontext` rules. Files placed under `/srv` inherit this context automatically.

### Creating the Directory Structure

For each application, create the required directories before deploying:

```bash
# Create the base directory (if it doesn't exist)
sudo mkdir -p /srv/containers

# Create per-application directories
# The exact subdirectories vary by definition -- see each definition's README.
# Example for LibreChat:
sudo mkdir -p /srv/containers/librechat/{conf,images,uploads,logs,meilisearch_data,mongodb_data,pgvector_data,valkey/data,valkey/conf}
```

### Why `/srv/containers/`?

On SELinux-enabled systems, bind-mounting host directories into containers requires the files to have an SELinux context that the container's confined process is allowed to read and write. Using `/srv/containers/` provides this out of the box:

1. **Correct context by inheritance** -- `/srv` is labeled `var_t` by default, which is accessible to container processes. New files and directories created under `/srv` inherit this label.
2. **No manual relabeling** -- Alternatives like `/opt` or `/home` have restrictive SELinux types (`usr_t`, `user_home_t`) that require `semanage fcontext` and `restorecon` to make containers work.
3. **The `:Z` volume suffix** -- All volume mounts in these definitions use the `:Z` suffix, which tells Podman to relabel the mount point with a private SELinux label scoped to that specific container. This works correctly when the parent directory already has a permissive base context (like `var_t`), but can fail or cause conflicts if the base context is overly restrictive.

If your system does not use SELinux (e.g., Debian, Ubuntu, Arch), you can use any directory -- the `:Z` suffix is harmless on systems without SELinux.

### Verifying SELinux Context

```bash
# Check the context of your containers directory
ls -Zd /srv/containers/

# Expected output (Fedora/RHEL):
# system_u:object_r:var_t:s0 /srv/containers/

# If the context is wrong, fix it:
sudo restorecon -Rv /srv/containers/
```

## Installation

### Using `podman quadlet install` (Podman 5.0+)

```bash
cd definitions/{appname}/
podman quadlet install *.container *.pod *.network *.volume *.env
```

Not every definition has all file types -- some have only a `.container` file. List the globs that match files in the definition you're installing, or check each definition's README for exact commands. Add `--replace` to update an existing installation.

This copies the files to `~/.config/containers/systemd/` and reloads systemd automatically.

### Manual Installation

Adjust the globs below to match the file types present in the definition you're installing. Not every definition includes all types -- check the definition's README or directory listing.

```bash
# User-level (rootless)
mkdir -p ~/.config/containers/systemd
cp definitions/{appname}/*.container definitions/{appname}/*.pod \
   definitions/{appname}/*.network definitions/{appname}/*.volume \
   definitions/{appname}/*.env ~/.config/containers/systemd/
systemctl --user daemon-reload

# System-level (root)
sudo cp definitions/{appname}/*.container definitions/{appname}/*.pod \
   definitions/{appname}/*.network definitions/{appname}/*.volume \
   definitions/{appname}/*.env /etc/containers/systemd/
sudo systemctl daemon-reload
```

## Usage

After installation, manage stacks with `systemctl`:

```bash
# Start a stack (pulls in dependencies automatically)
systemctl --user start {appname}-pod.service

# Check status
systemctl --user status {appname}-*.service

# View logs
journalctl --user -u {appname}-api.service -f

# Stop a stack
systemctl --user stop {appname}-pod.service

# Enable on boot
systemctl --user enable {appname}-pod.service
```

Replace `systemctl --user` with `sudo systemctl` for system-level deployments.

## Repository Structure

```
quadlet-catalog/
├── README.md                  # This file
├── definitions/               # All application definitions
│   ├── firecrawl/             # Web scraping API stack
│   ├── jellyfin/              # Jellyfin media server
│   ├── librechat/             # AI chat platform stack
│   ├── mcp-context7/          # Context7 library docs MCP server
│   ├── mcp-playwright/        # Playwright MCP server
│   ├── perplexity-sonar/      # Perplexity Sonar MCP server
│   ├── plex/                  # Plex Media Server
│   ├── quay/                  # Container registry stack
│   ├── valkey/                # Valkey key-value store (redis → valkey symlink)
│   ├── codejail/              # (planned) Code sandbox
│   └── qemu/                  # (planned) QEMU VM management
├── docs/
│   └── CONTRIBUTING.md        # How to add new definitions
└── .gitmodules                # Git submodule declarations
```

## Quadlet File Types

| Extension    | Purpose                            | systemd Unit Name Translation |
|-------------|------------------------------------|-----------------------------|
| `.container` | Defines a single container         | `{name}.service`            |
| `.pod`       | Groups containers into a pod       | `{name}-pod.service`        |
| `.network`   | Creates a Podman network           | `{name}-network.service`    |
| `.volume`    | Declares a named volume            | `{name}-volume.service`     |
| `.build`     | Builds an image from a Dockerfile  | `{name}-build.service`      |
| `.env`       | Environment variable template      | (not a unit)                |

## Contributing

See [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) for detailed instructions on adding new definitions, including file templates, naming conventions, and a pre-submission checklist.

## License

See individual definition directories for upstream project licenses.
