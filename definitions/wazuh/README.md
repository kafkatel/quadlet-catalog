# Wazuh

[Wazuh](https://wazuh.com/) is a free, open-source SIEM and XDR platform for threat detection, integrity monitoring, incident response, and compliance.

## Stack Components

| Service | Image | Description |
|---------|-------|-------------|
| wazuh-manager | `wazuh/wazuh-manager:4.14.4` | SIEM engine: event analysis, rule detection, agent management |
| wazuh-indexer | `wazuh/wazuh-indexer:4.14.4` | Data storage and search (OpenSearch-based) |
| wazuh-dashboard | `wazuh/wazuh-dashboard:4.14.4` | Web UI for visualization and management |

## Architecture

The stack uses a pod for the Wazuh application containers and a bridge network for the indexer:

- **Pod** (`wazuh.pod`): Contains `wazuh-manager` and `wazuh-dashboard`. Publishes agent communication (1514, 1515), REST API (55000), and dashboard UI (443) to the host. The pod is attached to the backend network.
- **Network** (`wazuh-network.network`): The indexer runs standalone on this bridge network. The pod joins the same network so the manager and dashboard can reach the indexer by container name.

```
                    ┌─── wazuh pod ───────────────────────┐
  Agents ──1514──►  │  wazuh-manager ──9200──► wazuh-indexer (network)
  Agents ──1515──►  │                                     │
  API    ──55000──► │                                     │
  Browser ──443──►  │  wazuh-dashboard ──9200──►          │
                    └─────────────────────────────────────┘
```

## Quadlet Files

| File | Purpose |
|------|---------|
| `wazuh.pod` | Pod grouping manager and dashboard; publishes all external ports |
| `wazuh-network.network` | Backend bridge network for indexer communication |
| `wazuh-indexer.container` | OpenSearch-based data store |
| `wazuh-manager.container` | SIEM analysis engine |
| `wazuh-dashboard.container` | Web UI |
| `wazuh.env` | Shared credentials and TLS settings |
| `wazuh-indexer-data.volume` | Indexer data persistence |
| `wazuh-*.volume` (11 files) | Manager and Filebeat state persistence |

## Prerequisites

- Podman 4.4+ with Quadlet support
- `vm.max_map_count` set to at least 262144 (required by the OpenSearch-based indexer):

```bash
sudo sysctl -w vm.max_map_count=262144
# Persist across reboots:
echo "vm.max_map_count=262144" | sudo tee /etc/sysctl.d/99-wazuh.conf
```

## Setup

### 1. Generate TLS Certificates

Wazuh requires TLS between all components. Generate self-signed certificates using openssl:

```bash
mkdir -p /srv/containers/wazuh/certs/{wazuh-indexer,wazuh-manager,wazuh-dashboard}

# Root CA
openssl genrsa -out /srv/containers/wazuh/certs/root-ca-key.pem 2048
openssl req -new -x509 -sha256 -key /srv/containers/wazuh/certs/root-ca-key.pem \
  -out /srv/containers/wazuh/certs/root-ca.pem -days 3650 \
  -subj "/C=US/L=California/O=Wazuh/OU=Wazuh/CN=root-ca"

# Admin cert (for indexer security initialization)
openssl genrsa -out /tmp/admin-key-temp.pem 2048
openssl pkcs8 -inform PEM -outform PEM -in /tmp/admin-key-temp.pem -topk8 -nocrypt \
  -out /srv/containers/wazuh/certs/admin-key.pem
openssl req -new -key /srv/containers/wazuh/certs/admin-key.pem -out /tmp/admin.csr \
  -subj "/C=US/L=California/O=Wazuh/OU=Wazuh/CN=admin"
openssl x509 -req -in /tmp/admin.csr -CA /srv/containers/wazuh/certs/root-ca.pem \
  -CAkey /srv/containers/wazuh/certs/root-ca-key.pem -CAcreateserial \
  -out /srv/containers/wazuh/certs/admin.pem -days 3650 -sha256

# Component certificates (indexer, manager, dashboard)
for COMPONENT in wazuh-indexer wazuh-manager wazuh-dashboard; do
  DIR=/srv/containers/wazuh/certs/$COMPONENT
  openssl genrsa -out /tmp/${COMPONENT}-key-temp.pem 2048
  openssl pkcs8 -inform PEM -outform PEM -in /tmp/${COMPONENT}-key-temp.pem -topk8 -nocrypt \
    -out $DIR/${COMPONENT}-key.pem
  openssl req -new -key $DIR/${COMPONENT}-key.pem -out /tmp/${COMPONENT}.csr \
    -subj "/C=US/L=California/O=Wazuh/OU=Wazuh/CN=$COMPONENT"
  cat > /tmp/${COMPONENT}-san.cnf <<EOF
[v3_req]
subjectAltName = DNS:${COMPONENT},IP:127.0.0.1
EOF
  openssl x509 -req -in /tmp/${COMPONENT}.csr -CA /srv/containers/wazuh/certs/root-ca.pem \
    -CAkey /srv/containers/wazuh/certs/root-ca-key.pem -CAcreateserial \
    -out $DIR/${COMPONENT}.pem -days 3650 -sha256 \
    -extfile /tmp/${COMPONENT}-san.cnf -extensions v3_req
  cp /srv/containers/wazuh/certs/root-ca.pem $DIR/root-ca.pem
done

# Indexer expects filenames: indexer.pem, indexer-key.pem
cp /srv/containers/wazuh/certs/wazuh-indexer/wazuh-indexer.pem /srv/containers/wazuh/certs/wazuh-indexer/indexer.pem
cp /srv/containers/wazuh/certs/wazuh-indexer/wazuh-indexer-key.pem /srv/containers/wazuh/certs/wazuh-indexer/indexer-key.pem
cp /srv/containers/wazuh/certs/admin.pem /srv/containers/wazuh/certs/wazuh-indexer/admin.pem
cp /srv/containers/wazuh/certs/admin-key.pem /srv/containers/wazuh/certs/wazuh-indexer/admin-key.pem

# Manager needs filebeat certs for shipping to indexer
cp /srv/containers/wazuh/certs/wazuh-manager/wazuh-manager.pem /srv/containers/wazuh/certs/wazuh-manager/filebeat.pem
cp /srv/containers/wazuh/certs/wazuh-manager/wazuh-manager-key.pem /srv/containers/wazuh/certs/wazuh-manager/filebeat-key.pem

# Make all certs readable by container processes
chmod -R a+r /srv/containers/wazuh/certs/

# Clean up temp files
rm -f /tmp/admin-key-temp.pem /tmp/admin.csr /tmp/wazuh-*-key-temp.pem /tmp/wazuh-*.csr /tmp/wazuh-*-san.cnf
```

### 2. Create Host Directories

```bash
sudo mkdir -p /srv/containers/wazuh/dashboard-config
sudo mkdir -p /srv/containers/wazuh/dashboard-custom
```

### 3. Configure Environment

Edit `wazuh.env` and set the three empty password fields:

```bash
python3 -c "import secrets; print(secrets.token_hex(16))"
```

The `INDEXER_PASSWORD` and `DASHBOARD_PASSWORD` must match the credentials configured in the indexer's security plugin. For initial deployment, set both to the same value and change them after setup.

### 4. Install Quadlet Files

```bash
podman quadlet install *.pod *.container *.network *.volume wazuh.env opensearch_dashboards.yml
```

Or manually:

```bash
mkdir -p ~/.config/containers/systemd
cp *.pod *.container *.network *.volume wazuh.env opensearch_dashboards.yml ~/.config/containers/systemd/
systemctl --user daemon-reload
```

### 5. Start the Stack

Start the indexer first, initialize its security plugin, then bring up the rest:

```bash
# Phase 1 — Start the indexer
systemctl --user start wazuh-indexer.service

# Wait for the indexer to become available
until podman exec wazuh-indexer curl -ks https://localhost:9200 2>/dev/null | grep -q 'Security not initialized\|wazuh-cluster'; do
  sleep 5
done

# Phase 2 — Initialize security (first time only)
podman exec wazuh-indexer bash -c '
export JAVA_HOME=/usr/share/wazuh-indexer/jdk
/usr/share/wazuh-indexer/plugins/opensearch-security/tools/securityadmin.sh \
  -cd /usr/share/wazuh-indexer/config/opensearch-security/ \
  -cacert /usr/share/wazuh-indexer/config/certs/root-ca.pem \
  -cert /usr/share/wazuh-indexer/config/certs/admin.pem \
  -key /usr/share/wazuh-indexer/config/certs/admin-key.pem \
  -icl -nhnv -h localhost'

# Verify: should return cluster info JSON
podman exec wazuh-indexer curl -ks -u admin:admin https://localhost:9200

# Phase 3 — Start the manager and dashboard
systemctl --user start wazuh-manager.service
systemctl --user start wazuh-dashboard.service
```

**First-run wazuh.yml fix:** On the very first startup, the dashboard init script appends a host entry to `wazuh.yml` that duplicates the default entry, causing a YAML parse error. Fix it by removing the duplicate `hosts:` block:

```bash
podman exec wazuh-dashboard sh -c "
cd /usr/share/wazuh-dashboard/data/wazuh/config/
python3 -c \"
import sys
with open('wazuh.yml') as f: content = f.read()
old = '''hosts:
  - default:
      url: https://localhost
      port: 55000
      username: wazuh-wui
      password: wazuh-wui
      run_as: true

'''
with open('wazuh.yml', 'w') as f: f.write(content.replace(old, ''))
\"
"
systemctl --user restart wazuh-dashboard.service
```

On subsequent startups, starting the manager or dashboard is sufficient — they pull in the indexer via `Requires=`. The security initialization step and wazuh.yml fix are only needed once (state persists in volumes).

### 6. Verify

```bash
# Check all containers are running
podman ps --filter name=wazuh

# Test indexer health
podman exec wazuh-indexer curl -ks -u admin:admin https://localhost:9200

# Test dashboard (should return HTTP 302 redirect to login)
curl -ks https://localhost:5601/ -o /dev/null -w "HTTP %{http_code}\n"
```

Access the dashboard at `https://localhost:5601`. Default login is `admin` with the `INDEXER_PASSWORD` you set.

## Port Configuration

| Host Port | Container Port | Protocol | Purpose |
|-----------|---------------|----------|---------|
| 5601 | 5601 | HTTPS | Dashboard web UI |
| 1514 | 1514 | TCP | Agent event connection |
| 1515 | 1515 | TCP | Agent enrollment |
| 55000 | 55000 | TCP | Wazuh REST API |

To use standard HTTPS port 443, edit `wazuh.pod` and change `PublishPort=5601:5601` to `PublishPort=443:5601`. This requires running as root or setting `net.ipv4.ip_unprivileged_port_start=443` in sysctl.

The indexer port (9200) is not exposed to the host — it is reachable only within the `wazuh-backend` network.

## Agent Enrollment

To register a new Wazuh agent against this deployment:

```bash
# On the agent host
curl -s https://packages.wazuh.com/4.x/apt/pool/main/w/wazuh-agent/wazuh-agent_4.14.4-1_amd64.deb -o wazuh-agent.deb
WAZUH_MANAGER="YOUR_SERVER_IP" dpkg -i wazuh-agent.deb
systemctl start wazuh-agent
```

See the [Wazuh agent deployment documentation](https://documentation.wazuh.com/current/installation-guide/wazuh-agent/index.html) for all supported platforms.
