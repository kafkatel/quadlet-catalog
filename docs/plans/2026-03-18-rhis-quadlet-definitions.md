# RHIS Infrastructure Quadlet Definitions

Created: 2026-03-18
Status: VERIFIED
Approved: Yes
Iterations: 0
Worktree: No
Type: Feature

## Summary

**Goal:** Create Podman Quadlet definitions for the three core Red Hat Infrastructure Standard (RHIS) components — IdM Primary, Satellite Server, and Satellite Capsule — as privileged systemd containers with bridge-based networking that gives each container its own LAN IP address. Include a bridge setup script and networking guide.

**Architecture:** Each RHIS service runs as a standalone systemd container (no pod) on an unmanaged bridge network, giving it a real IP on the host's LAN. IdM uses the upstream `freeipa-server` image. Satellite and Capsule use `ubi9/ubi-init` systemd containers where the operator runs the installer post-start. A shared bridge networking guide and setup script serve all three definitions.

**Tech Stack:** Podman Quadlet, FreeIPA container images (`quay.io/freeipa/freeipa-server`), UBI-init images (`registry.access.redhat.com/ubi9/ubi-init`), NetworkManager/nmcli for bridge setup, shell scripting.

## Scope

### In Scope

- `definitions/idm/` — FreeIPA IdM Primary quadlet (container, volume, network, env, README)
- `definitions/satellite/` — Satellite Server quadlet (Containerfile, build, container, volume, network, env, README)
- `definitions/capsule/` — Satellite Capsule quadlet (Containerfile, build, container, volume, network, env, README)
- `docs/bridge-networking.md` — Bridge networking guide for all RHIS quadlets
- `scripts/setup-bridge.sh` — Shell script that replicates the `bridge_setup` Ansible role
- Updates to main `README.md` — add new definitions to the Available table and repository tree

### Out of Scope

- IdM Replicas (future work — topology management is complex)
- Automated Satellite configuration (that's what rhis-builder-satellite does)
- Capsule content sync automation
- Ansible integration or rhis-builder-* modifications
- Container images for Satellite 6.19+ (wait for Red Hat to ship official images)

## Context for Implementer

> Write for an implementer who has never seen the codebase.

- **Patterns to follow:** Existing standalone container definitions in `definitions/jellyfin/jellyfin.container` and `definitions/valkey/valkey.container` — both are standalone containers without pods, using host paths under `/srv/containers/`.
- **Conventions:** All files follow `{appname}-{component}.container` naming. Volumes use `:Z` suffix. Environment files use `{appname}.env`. See `docs/CONTRIBUTING.md` for full reference.
- **Key files:**
  - `docs/CONTRIBUTING.md` — template structures for all quadlet file types
  - `definitions/quay/` — the most complex existing definition (pod + network + 6 containers), good reference for multi-volume patterns
  - `rhis-builder-baremetal-init/.worktrees/bridge-setup/roles/bridge_setup/` — source pattern for the bridge setup script
  - `rhis-builder-idm/roles/idm_pre/tasks/ensure_firewall.yml` — IdM firewall ports
  - `rhis-builder-idm/roles/idm_primary/tasks/main.yml` — IdM installer invocation
- **Gotchas:**
  - "Privileged systemd containers" means containers that run systemd as PID 1 — NOT Podman's `--privileged` flag. FreeIPA container runs in a confined namespace with specific capabilities. The hostname MUST be set via `HostName=` or `IPA_SERVER_HOSTNAME`, not via `ipa-server-install --hostname`. For Satellite/Capsule UBI-init containers, `PodmanArgs=--privileged` MAY be needed for the installer to configure system services — document both approaches and test without `--privileged` first.
  - When running FreeIPA DNS, the container needs `DNS=127.0.0.1` so it can reach its own DNS server.
  - The unmanaged bridge approach requires `mode=unmanaged` in the Podman network config. In Quadlet `.network` files, use `Options=mode=unmanaged` plus `Options=bridge_name=br0`. The CLI equivalent is `podman network create --driver bridge --opt mode=unmanaged --interface-name br0`. On Podman < 5.3, the CLI command may reject this due to a netavark bug — a manual JSON network config file in `/etc/containers/networks/` is the fallback (documented in Jamie Montgomerie's blog, Oct 2025).
  - Satellite requires 20+ GB RAM and 200+ GB disk. The UBI-init container approach is experimental/lab-only.
  - The bridge setup script is destructive (migrates all IPs from physical NIC to bridge). It must capture existing config before modifying anything, exactly as the RHIS `bridge_setup` Ansible role does.
- **Domain context:** RHIS (Red Hat Infrastructure Standard) is a reference architecture for deploying Red Hat enterprise infrastructure. The deployment order is: bridge networking → IdM Primary → Satellite → Capsule. Each service depends on the previous one (Satellite registers with IdM for Kerberos/DNS, Capsule registers with both).

## Runtime Environment

These are system-level services deployed via `sudo systemctl` (not `--user`). Quadlet files go to `/etc/containers/systemd/`. Services bind to specific LAN IPs via the unmanaged bridge network. No ports are published — the container IS on the network.

## Assumptions

- Host runs RHEL 9, Fedora, or CentOS Stream with Podman 4.4+ — supported by freeipa-container upstream. Tasks 1-6 depend on this.
- SELinux is enforcing — all volume mounts use `:Z`. Tasks 3-5 depend on this.
- Host has a single physical NIC that can be enslaved to a bridge — the setup-bridge.sh script assumes this. Task 1 depends on this.
- Operator has a Red Hat subscription for Satellite/Capsule content — required for satellite-installer. Tasks 4-5 depend on this.
- The unmanaged bridge Podman network feature works on the target Podman version, or the operator is willing to create the JSON config manually — Task 2 depends on this.

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Bridge setup script drops network connectivity | Medium | High | Script captures all existing config before modifying, validates bridge is up before deactivating old profile, includes rollback instructions |
| Satellite installer fails inside UBI-init container | Medium | High | Document as experimental/lab-only, provide clear troubleshooting steps, note minimum resource requirements |
| Podman version lacks unmanaged bridge support | Medium | Medium | Document manual JSON network config as fallback for Podman < 5.3, test detection in setup-bridge.sh |
| FreeIPA installer fails due to hostname/DNS misconfiguration | Low | High | Validate hostname resolves correctly before starting installer, document DNS prereqs clearly |

## Goal Verification

### Truths

1. A FreeIPA IdM Primary container can be started with `systemctl start idm.service` and responds to `kinit admin` from the host
2. The bridge setup script creates a working bridge from a single physical NIC without dropping existing IP addresses
3. Each container gets its own IP address on the host's LAN, reachable from both the host and remote machines
4. The Satellite container starts systemd as PID 1 and the operator can run `satellite-installer` inside it
5. All quadlet definitions follow the naming and structure conventions in `docs/CONTRIBUTING.md`
6. The bridge networking guide is comprehensive enough to set up networking for any RHIS container without external documentation

### Artifacts

1. `definitions/idm/idm.container` + supporting files — FreeIPA quadlet
2. `definitions/satellite/Containerfile` + `satellite.build` + `satellite.container` + supporting files
3. `definitions/capsule/Containerfile` + `capsule.build` + `capsule.container` + supporting files
4. `docs/bridge-networking.md` — networking guide
5. `scripts/setup-bridge.sh` — bridge setup automation
6. Updated `README.md` with new definitions

## Progress Tracking

- [x] Task 1: Bridge setup script
- [x] Task 2: Bridge networking guide
- [x] Task 3: IdM Primary quadlet definition
- [x] Task 4: Satellite Server quadlet definition
- [x] Task 5: Satellite Capsule quadlet definition
- [x] Task 6: Main README updates

**Total Tasks:** 6 | **Completed:** 6 | **Remaining:** 0

## Implementation Tasks

### Task 1: Bridge Setup Script

**Objective:** Create a shell script that replicates the `bridge_setup` Ansible role from `rhis-builder-baremetal-init`, creating a Linux bridge and migrating all host IPs from the physical NIC to the bridge.

**Dependencies:** None

**Files:**

- Create: `scripts/setup-bridge.sh`

**Key Decisions / Notes:**

- Source pattern: `rhis-builder-baremetal-init/.worktrees/bridge-setup/roles/bridge_setup/tasks/main.yml` and `defaults/main.yml`
- Uses `nmcli` commands (NetworkManager) — same as the Ansible role
- Must capture existing IP config (addresses, gateway, DNS, DNS search) from the active connection profile before modifying anything
- Creates bridge (`br0` by default), creates bridge-slave for the physical NIC, migrates all addresses
- Idempotent — skips if bridge already exists and is active (matches Ansible role behavior)
- Includes `--dry-run` mode that shows what would be done without making changes
- Includes `--rollback` instructions in output
- Accepts parameters: `--interface` (physical NIC, defaults to default route interface), `--bridge-name` (defaults to `br0`)
- Must handle the async bridge activation pattern from the Ansible role (activate bridge, then deactivate old profile) to avoid losing connectivity

**Definition of Done:**

- [ ] Script creates a bridge from a physical NIC
- [ ] All existing IPs, gateway, DNS, and DNS search domains are migrated to the bridge
- [ ] Script is idempotent — running twice has no effect
- [ ] `--dry-run` mode shows planned changes without executing
- [ ] Script validates bridge is active and host IP is on bridge before exiting
- [ ] Rollback instructions are printed and verified to restore original network state (reactivate original profile, delete bridge slave, delete bridge)

**Verify:**

- Manual review of script logic against the Ansible role source

---

### Task 2: Bridge Networking Guide

**Objective:** Create `docs/bridge-networking.md` documenting bridge networking setup for RHIS containers, including the unmanaged bridge Podman network configuration and the Podman network JSON fallback.

**Dependencies:** Task 1

**Files:**

- Create: `docs/bridge-networking.md`

**Key Decisions / Notes:**

- Covers three layers: (1) Linux bridge setup (via the script or manual nmcli), (2) Podman network creation with `--driver bridge --opt mode=unmanaged`, (3) Referencing the network from quadlet `.network` or `.container` files
- Documents the unmanaged bridge JSON fallback for Podman < 5.3 (the netavark bug), with the exact JSON format from the blog post
- Documents the `setup-bridge.sh` script usage
- Explains why macvlan is NOT used (host can't reach container)
- Explains why host networking is NOT used (no separate IP)
- Covers IPv6 considerations (unmanaged bridge supports IPv6 autoconfig; macvlan does not)
- References: [freeipa-container GitHub](https://github.com/freeipa/freeipa-container), [Jamie Montgomerie's blog](https://www.blog.montgomerie.net/posts/2025-10-18-giving-a-rootful-podman-container-its-own-ip/), [Podman networking tutorial](https://github.com/containers/podman/blob/main/docs/tutorials/basic_networking.md), [RHEL 9 container networking docs](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/building_running_and_managing_containers/assembly_setting-container-network-modes_building-running-and-managing-containers)
- Includes a `.network` quadlet file template for the unmanaged bridge pattern
- Documents that rootful Podman is required for bridge/macvlan networking

**Definition of Done:**

- [ ] Guide covers bridge creation (script and manual)
- [ ] Guide covers Podman unmanaged bridge network creation (CLI and JSON fallback)
- [ ] Guide includes quadlet `.network` file template
- [ ] Guide explains why unmanaged bridge was chosen over macvlan and host networking

**Verify:**

- Manual review for completeness and accuracy

---

### Task 3: IdM Primary Quadlet Definition

**Objective:** Create a complete quadlet definition for running FreeIPA IdM Primary as a container with its own LAN IP via the unmanaged bridge network.

**Dependencies:** Task 2

**Files:**

- Create: `definitions/idm/idm.container`
- Create: `definitions/idm/idm-data.volume`
- Create: `definitions/idm/idm-bridge.network`
- Create: `definitions/idm/idm.env`
- Create: `definitions/idm/README.md`

**Key Decisions / Notes:**

- Image: `quay.io/freeipa/freeipa-server:centos-9-stream` (default — closest to RHEL). Also document `fedora-rawhide` tag (latest features, less stable) as an alternative.
- The container runs systemd as PID 1 — upstream freeipa-container does NOT require `--privileged`
- `HostName=` in the container file sets the FQDN (e.g., `idm1.example.ca`)
- `DNS=127.0.0.1` is required when using `--setup-dns` so FreeIPA can reach its own DNS
- `ReadOnly=true` is recommended by upstream
- Volume: `/srv/containers/idm/data:/data:Z` — all FreeIPA state persists here. On subsequent starts, the installer is skipped and services just start.
- Network: Uses the unmanaged bridge network (`.network` file references `br0`). No `PublishPort=` — the container IS on the network.
- First-run installer arguments are passed via `Exec=` or environment variables. Document both `ipa-server-install` interactive and unattended modes.
- Ports reference (for firewall docs, not PublishPort): 53/tcp+udp (DNS), 80 (HTTP), 443 (HTTPS), 389 (LDAP), 636 (LDAPS), 88/tcp+udp (Kerberos), 464/tcp+udp (kpasswd), 123/udp (NTP)
- `TimeoutStartSec=900` — first-run installer takes several minutes
- The `.env` file contains: `IPA_SERVER_HOSTNAME`, realm, domain, admin/DM passwords (empty, operator fills in)
- README documents: host directory setup, bridge network prereqs, first-run installer flow, day-2 operations, IdM client enrollment from other hosts, data persistence/backup

**Definition of Done:**

- [ ] All quadlet files follow naming conventions from CONTRIBUTING.md
- [ ] Container starts with `systemctl start idm.service` (after bridge and network are configured)
- [ ] README documents complete setup flow from bridge creation through first IdM login
- [ ] Environment file has all secrets empty with descriptive comments
- [ ] Volume mount uses `/srv/containers/idm/data` with `:Z` suffix

**Verify:**

- `podman run` equivalent test command documented in README for quick verification

---

### Task 4: Satellite Server Quadlet Definition

**Objective:** Create a quadlet definition for running Red Hat Satellite Server inside a UBI-init systemd container with its own LAN IP.

**Dependencies:** Task 2, Task 3 (Satellite typically depends on IdM for DNS/Kerberos)

**Files:**

- Create: `definitions/satellite/Containerfile`
- Create: `definitions/satellite/satellite.build`
- Create: `definitions/satellite/satellite.container`
- Create: `definitions/satellite/satellite-pulp.volume`
- Create: `definitions/satellite/satellite-pgsql.volume`
- Create: `definitions/satellite/satellite-foreman.volume`
- Create: `definitions/satellite/satellite-foreman-proxy.volume`
- Create: `definitions/satellite/satellite-candlepin.volume`
- Create: `definitions/satellite/satellite-puppet-ssl.volume`
- Create: `definitions/satellite/satellite-httpd.volume`
- Create: `definitions/satellite/satellite-log.volume`
- Create: `definitions/satellite/satellite-bridge.network`
- Create: `definitions/satellite/satellite.env`
- Create: `definitions/satellite/README.md`

**Key Decisions / Notes:**

- **Experimental/Lab-Only** — document prominently. No official Satellite container image exists. Satellite 6.19 (May 2026) will ship containerized Capsules; full Satellite containerization is not yet announced.
- Base image: `registry.access.redhat.com/ubi9/ubi-init` — runs systemd as PID 1
- Containerfile installs satellite-installer prerequisites (subscription-manager, satellite RPMs) at build time. The operator runs `satellite-installer` inside the running container.
- Volumes (each mapped separately for persistence):
  - `/srv/containers/satellite/pulp:/var/lib/pulp:Z` — content storage (bulk of the 200+ GB)
  - `/srv/containers/satellite/pgsql:/var/lib/pgsql:Z` — PostgreSQL database
  - `/srv/containers/satellite/foreman:/etc/foreman:Z` — Foreman configuration
  - `/srv/containers/satellite/foreman-proxy:/etc/foreman-proxy:Z` — Smart Proxy configuration
  - `/srv/containers/satellite/candlepin:/etc/candlepin:Z` — Candlepin (subscription management) config
  - `/srv/containers/satellite/puppet-ssl:/etc/puppetlabs/puppet/ssl:Z` — Puppet SSL certificates
  - `/srv/containers/satellite/httpd-conf:/etc/httpd:Z` — Apache configuration
  - `/srv/containers/satellite/log:/var/log:Z` — log persistence across restarts
- Build: `satellite.build` references the local Containerfile
- Network: Same unmanaged bridge pattern as IdM
- Resource requirements: 20 GB RAM minimum, 4 CPU cores, 200+ GB storage for content
- `TimeoutStartSec=1800` — satellite-installer can take 20+ minutes
- The `.env` file documents: `SATELLITE_HOSTNAME`, `SATELLITE_ORGANIZATION`, `SATELLITE_LOCATION`, `SATELLITE_ADMIN_PASSWORD`, IdM integration settings (`SATELLITE_USE_IDM`, `IPA_SERVER`, `IPA_REALM`), CDN credentials
- README documents: building the image, resource requirements, first-run satellite-installer invocation, IdM integration steps, content sync overview, day-2 operations, limitations vs. bare-metal Satellite

**Definition of Done:**

- [ ] Containerfile builds successfully from UBI-init base
- [ ] Container starts systemd as PID 1 and accepts `podman exec` for satellite-installer
- [ ] README prominently marks this as experimental/lab-only
- [ ] All persistent data directories are mapped to host volumes
- [ ] Resource requirements are clearly documented

**Verify:**

- `podman build` test command documented in README

---

### Task 5: Satellite Capsule Quadlet Definition

**Objective:** Create a quadlet definition for running a Satellite Capsule inside a UBI-init systemd container with its own LAN IP.

**Dependencies:** Task 2, Task 4

**Files:**

- Create: `definitions/capsule/Containerfile`
- Create: `definitions/capsule/capsule.build`
- Create: `definitions/capsule/capsule.container`
- Create: `definitions/capsule/capsule-pulp.volume`
- Create: `definitions/capsule/capsule-foreman-proxy.volume`
- Create: `definitions/capsule/capsule-puppet-ssl.volume`
- Create: `definitions/capsule/capsule-log.volume`
- Create: `definitions/capsule/capsule-bridge.network`
- Create: `definitions/capsule/capsule.env`
- Create: `definitions/capsule/README.md`

**Key Decisions / Notes:**

- Same experimental/lab-only status as Satellite
- Base image: `registry.access.redhat.com/ubi9/ubi-init` — same as Satellite but with capsule-specific packages
- Containerfile installs satellite-capsule RPMs at build time. Operator runs `satellite-installer --scenario capsule` inside the container.
- Lighter weight than Satellite — 8 GB RAM minimum, 2 CPU cores
- Volume: `/srv/containers/capsule/data:/data:Z` — mount points for `/var/lib/pulp`, `/etc/foreman-proxy`, `/var/log`
- Network: Same unmanaged bridge pattern
- Capsule requires certificates generated on the Satellite — document the `capsule-certs-generate` workflow and how to copy the certs tarball into the container
- The `.env` file documents: `CAPSULE_HOSTNAME`, `SATELLITE_HOSTNAME`, `CAPSULE_ORGANIZATION`, `CAPSULE_LOCATION`
- README documents: building the image, generating capsule certs on Satellite, first-run installer invocation, content sync setup

**Definition of Done:**

- [ ] Containerfile builds from UBI-init base with capsule packages
- [ ] Container starts systemd and accepts `podman exec` for capsule installer
- [ ] README documents the cert generation and transfer workflow
- [ ] Lighter resource requirements documented (vs. full Satellite)

**Verify:**

- `podman build` test command documented in README

---

### Task 6: Main README Updates

**Objective:** Update the main `README.md` to include the three new RHIS definitions and the bridge networking documentation in the repository structure.

**Dependencies:** Tasks 1-5

**Files:**

- Modify: `README.md`

**Key Decisions / Notes:**

- Add IdM, Satellite, Capsule to the Available Definitions table
- Add `scripts/` directory to the repository structure tree
- Add `docs/bridge-networking.md` to the docs listing
- IdM: Architecture = "Standalone container (bridge network)"
- Satellite/Capsule: Architecture = "Standalone container (bridge network, local build)", note experimental status in Description

**Definition of Done:**

- [ ] All three definitions appear in the Available Definitions table
- [ ] Repository structure tree includes `scripts/` and the new `docs/` entry
- [ ] No broken internal links

**Verify:**

- Manual review of README rendering

## Open Questions

1. ~~Which FreeIPA image tag to default to?~~ **Resolved:** Default to `centos-9-stream` in the quadlet file. README documents both tags and how to switch to `fedora-rawhide`.
2. Should the Satellite Containerfile subscribe the container to the Red Hat CDN at build time (requires passing subscription credentials into the build context) or leave that to the operator post-start? Plan leaves it to post-start for security.

### Deferred Ideas

- IdM Replica definition (requires topology management, replica agreement setup)
- Automated Satellite configuration integration (run rhis-builder-satellite playbooks inside the container)
- Satellite 6.19 official container images (replace UBI-init approach when available)
- RHIS provisioner container quadlet (already has Quay image at `quay.io/parmstro/rhis-provision-9-*`)
- Keycloak quadlet definition (referenced in rhis-builder-inventory group_vars)
