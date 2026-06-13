#!/bin/bash

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

info()    { echo -e "${GREEN}[*]${NC} $*"; }
success() { echo -e "${GREEN}[✓]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
error()   { echo -e "${RED}[✗]${NC} $*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load .env if present
if [ -f "$SCRIPT_DIR/.env" ]; then
    set -a
    # shellcheck source=.env.example
    source "$SCRIPT_DIR/.env"
    set +a
fi

CONTAINER_NAME="${CONTAINER_NAME:-3xui_app}"
PANEL_PORT="${PANEL_PORT:-2057}"
CERT_DIR="${CERT_DIR:-/root/cert}"
CERT_SUBDOMAIN="${CERT_SUBDOMAIN:-ip}"

# --- Preflight checks --------------------------------------------------------

command -v python3 >/dev/null 2>&1 || error "python3 is required but not installed."
command -v openssl >/dev/null 2>&1 || error "openssl is required but not installed."

info "Detecting Docker Compose version..."
if docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
elif docker-compose version >/dev/null 2>&1; then
    COMPOSE_CMD="docker-compose"
else
    error "Neither 'docker compose' nor 'docker-compose' found. Install Docker with the Compose plugin."
fi
success "Using: ${YELLOW}$COMPOSE_CMD${NC}"

[ -f "$SCRIPT_DIR/compose.yml" ] || [ -f "$SCRIPT_DIR/docker-compose.yml" ] \
    || error "No compose.yml or docker-compose.yml found in $SCRIPT_DIR"

# --- Secret base path --------------------------------------------------------
# Generated once on first run and persisted in .panel_path so re-runs don't
# rotate the URL and break existing clients.

PANEL_PATH_FILE="$SCRIPT_DIR/.panel_path"
if [ -f "$PANEL_PATH_FILE" ]; then
    PANEL_PATH=$(cat "$PANEL_PATH_FILE")
    warn "Reusing existing secret base path. Delete .panel_path to regenerate."
else
    PANEL_PATH=$(openssl rand -hex 8)
    echo "$PANEL_PATH" > "$PANEL_PATH_FILE"
    chmod 600 "$PANEL_PATH_FILE"
    success "Generated new secret base path."
fi

# --- Start containers --------------------------------------------------------

info "Starting containers..."
cd "$SCRIPT_DIR"
$COMPOSE_CMD up -d

# --- Wait for DB -------------------------------------------------------------
# Poll instead of sleeping a fixed amount — fast if the container is healthy,
# fails with a clear message if something is wrong.

info "Waiting for the database to initialize..."
DB_PATH="$SCRIPT_DIR/db/x-ui.db"
WAIT_SECONDS=30
for i in $(seq 1 "$WAIT_SECONDS"); do
    [ -f "$DB_PATH" ] && break
    sleep 1
done

[ -f "$DB_PATH" ] \
    || error "Database not found after ${WAIT_SECONDS}s. Check logs: docker logs $CONTAINER_NAME"

# --- Inject configuration ----------------------------------------------------

info "Writing SSL paths and secret base path to the database..."
python3 - "$DB_PATH" "$CERT_SUBDOMAIN" "/$PANEL_PATH/" <<'PYEOF'
import sqlite3, sys

db_path, cert_subdir, base_path = sys.argv[1], sys.argv[2], sys.argv[3]

conn = sqlite3.connect(db_path)
c = conn.cursor()
c.execute('''
    CREATE TABLE IF NOT EXISTS settings (
        id    INTEGER PRIMARY KEY AUTOINCREMENT,
        key   TEXT UNIQUE,
        value TEXT
    )
''')

settings = {
    'webBasePath': base_path,
    'webCertFile': f'/root/cert/{cert_subdir}/fullchain.pem',
    'webCertKey':  f'/root/cert/{cert_subdir}/privkey.pem',
    'webKeyFile':  f'/root/cert/{cert_subdir}/privkey.pem',
}

for key, value in settings.items():
    c.execute('INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)', (key, value))
    print(f'  {key} = {value}')

conn.commit()
conn.close()
PYEOF

# --- Apply configuration -----------------------------------------------------

info "Restarting container to apply configuration..."
docker restart "$CONTAINER_NAME" >/dev/null

SERVER_IP=$(curl -4 -s --max-time 5 ifconfig.me \
         || curl -4 -s --max-time 5 api.ipify.org \
         || echo "YOUR_SERVER_IP")

echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✓  Panel is ready!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo -e "  URL    : ${YELLOW}https://$SERVER_IP:$PANEL_PORT/$PANEL_PATH/${NC}"
echo -e "  Login  : admin / admin  ${RED}← change immediately!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo ""
