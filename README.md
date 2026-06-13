# docker-3x-ui

Docker deployment for [3x-ui](https://github.com/MHSanaei/3x-ui) — an Xray panel with a web UI for managing proxy inbounds (VLESS, VMess, Trojan, etc.).

## Features

- **Automatic IP-based SSL** via [acme.sh](https://github.com/acmesh-official/acme.sh) + Let's Encrypt short-lived certificates (6-day validity, renewed daily)
- **Random secret base path** generated on first run — protects the panel from automated scanners
- **Fully configurable via `.env`** — no hardcoded values in any file
- **Idempotent scripts** — safe to re-run; secret path and database are preserved
- Fail2ban and log rotation enabled by default

## Prerequisites

| Requirement | Check |
|---|---|
| Docker + Compose plugin | `docker compose version` |
| Python 3 | `python3 --version` |
| `openssl`, `curl` | usually pre-installed |
| Root access | required for SSL issuance (port 80) |

## Quick Start

### 1. Configure

```bash
cp .env.example .env
nano .env   # set ACME_EMAIL at minimum; review other defaults
```

### 2. Issue SSL Certificate

```bash
sudo ./setup_ssl.sh
```

Issues a [short-lived IP certificate](https://letsencrypt.org/2024/11/06/short-lived-certificates/) from Let's Encrypt. Port 80 must be free and reachable from the internet.

### 3. Launch the Panel

```bash
./run.sh
```

On first run a random secret base path is generated and saved to `.panel_path`. The panel URL is printed at the end.

> **Default credentials: `admin` / `admin` — change them immediately after login.**

## Configuration

| Variable | Default | Description |
|---|---|---|
| `XUI_IMAGE` | `ghcr.io/mhsanaei/3x-ui:latest` | Docker image. Pin a specific tag in production. |
| `CONTAINER_NAME` | `3xui_app` | Docker container name |
| `PANEL_PORT` | `2057` | Host port for the web panel |
| `CERT_DIR` | `/root/cert` | Host directory with SSL certs (mounted as `/root/cert` in container) |
| `CERT_SUBDOMAIN` | `ip` | Subdirectory inside `CERT_DIR` for cert files |
| `ACME_EMAIL` | — | **Required for `setup_ssl.sh`.** Email for acme.sh account |
| `XRAY_VMESS_AEAD_FORCED` | `false` | Force AEAD for VMess (disable for broad client compatibility) |
| `XUI_ENABLE_FAIL2BAN` | `true` | Block IPs after repeated failed logins |
| `LOG_MAX_SIZE` | `10m` | Max size of a single Docker log file |
| `LOG_MAX_FILES` | `3` | Max number of retained log files |

## Proxy Traffic Ports

The web panel is exposed on `PANEL_PORT`. Ports for actual proxy traffic (VLESS, VMess, etc.) depend on which inbounds you create inside the panel. There are two ways to expose them:

**Option A — expose specific ports** (recommended; more secure):

```yaml
# compose.yml → ports:
- "443:443"
- "8443:8443"
```

**Option B — host network mode** (simpler; all ports available immediately):

```yaml
# compose.yml: replace the ports section with:
network_mode: host
```

When using `network_mode: host`, remove the `ports:` key entirely.

## Persistent Data

| Path | Contents |
|---|---|
| `./db/` | SQLite database (all panel config, inbound keys, users) |
| `$CERT_DIR/$CERT_SUBDOMAIN/` | TLS certificate and private key |
| `.panel_path` | Your secret URL base path |

Back up `./db/` regularly. The `.panel_path` file lets you reconstruct the panel URL if you forget it.

## Updating

```bash
docker compose pull          # pull the new image
docker compose up -d         # recreate the container; db is preserved
```

## Troubleshooting

**Container won't start**
```bash
docker logs 3xui_app
```

**SSL issuance fails**
- Ensure port 80 is open in your cloud firewall / security group (not just the OS firewall)
- Let's Encrypt rate-limits failed attempts — wait an hour before retrying

**Panel unreachable after `run.sh`**
- Allow ~10 seconds for Xray to fully start after the container restarts
- Check `docker logs 3xui_app` for startup errors
- Confirm `PANEL_PORT` is open in your firewall

**Regenerate the secret base path**
```bash
rm .panel_path && ./run.sh
```

**View current panel URL**
```bash
cat .panel_path   # base path suffix
```

## Security Notes

- `.env`, `db/`, and `.panel_path` are gitignored — they must never be committed
- The `db/` directory holds all secrets (inbound private keys, user configs) — restrict access with `chmod 700 db/`
- Certificates in `$CERT_DIR` are mounted read-only inside the container
- Fail2ban is enabled by default; review failed-login logs in the panel dashboard
