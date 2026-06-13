#!/bin/bash
# Issues a Let's Encrypt short-lived IP certificate and installs it
# to CERT_DIR/CERT_SUBDOMAIN/ using acme.sh.
#
# Short-lived certs are valid for 6 days and renewed daily via cron —
# no manual renewal needed. Requires port 80 to be open for the HTTP challenge.

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

info()    { echo -e "${GREEN}[*]${NC} $*"; }
success() { echo -e "${GREEN}[✓]${NC} $*"; }
error()   { echo -e "${RED}[✗]${NC} $*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load .env if present
if [ -f "$SCRIPT_DIR/.env" ]; then
    set -a
    # shellcheck source=.env.example
    source "$SCRIPT_DIR/.env"
    set +a
fi

CERT_DIR="${CERT_DIR:-/root/cert}"
CERT_SUBDOMAIN="${CERT_SUBDOMAIN:-ip}"
CONTAINER_NAME="${CONTAINER_NAME:-3xui_app}"
ACME_EMAIL="${ACME_EMAIL:-}"

# --- Preflight checks --------------------------------------------------------

info "Checking root privileges..."
[ "$EUID" -eq 0 ] || error "Please run as root: sudo $0"

if [ -z "$ACME_EMAIL" ]; then
    error "ACME_EMAIL is not set. Copy .env.example to .env and fill in your email."
fi

info "Detecting public IP address..."
SERVER_IP=$(curl -4 -s --max-time 10 ifconfig.me \
          || curl -4 -s --max-time 10 api.ipify.org \
          || echo "")
[ -n "$SERVER_IP" ] || error "Could not detect public IP. Check your internet connection."
success "IP detected: ${YELLOW}$SERVER_IP${NC}"

if lsof -i :80 >/dev/null 2>&1; then
    error "Port 80 is in use. Stop Nginx/Apache/Caddy before running this script."
fi

# --- Install system dependencies ---------------------------------------------

info "Installing dependencies (socat, curl, lsof)..."
if command -v apt-get &>/dev/null; then
    apt-get update -qq && apt-get install -y -qq socat curl lsof
elif command -v dnf &>/dev/null; then
    dnf install -y -q socat curl lsof
elif command -v yum &>/dev/null; then
    yum install -y -q socat curl lsof
else
    error "Unsupported package manager. Install socat, curl, and lsof manually, then re-run."
fi

# --- Install acme.sh ---------------------------------------------------------

ACME_BIN="$HOME/.acme.sh/acme.sh"
if [ ! -f "$ACME_BIN" ]; then
    info "Installing acme.sh..."
    curl -s https://get.acme.sh | sh -s email="$ACME_EMAIL"
    export LE_WORKING_DIR="$HOME/.acme.sh"
fi

# --- Issue certificate -------------------------------------------------------
# --certificate-profile shortlived  → 6-day cert (Let's Encrypt feature)
# --days 6                          → trigger renewal when ≤6 days remain
#                                     (i.e., renew daily for 6-day certs)
# --force                           → always issue even if a valid cert exists

info "Issuing short-lived IP certificate from Let's Encrypt..."
if ! "$ACME_BIN" --issue \
        -d "$SERVER_IP" \
        --standalone \
        --server letsencrypt \
        --certificate-profile shortlived \
        --days 6 \
        --httpport 80 \
        --force; then
    error "Certificate issuance failed. Ensure port 80 is open in your firewall/security group."
fi

# --- Install certificate files -----------------------------------------------

CERT_INSTALL_DIR="$CERT_DIR/$CERT_SUBDOMAIN"
info "Installing certificates to $CERT_INSTALL_DIR..."
mkdir -p "$CERT_INSTALL_DIR"

"$ACME_BIN" --installcert \
    -d "$SERVER_IP" \
    --key-file       "$CERT_INSTALL_DIR/privkey.pem" \
    --fullchain-file "$CERT_INSTALL_DIR/fullchain.pem" \
    --reloadcmd      "docker restart $CONTAINER_NAME || true"

chmod 600 "$CERT_INSTALL_DIR/privkey.pem"
chmod 644 "$CERT_INSTALL_DIR/fullchain.pem"

echo ""
success "Certificate installed to $CERT_INSTALL_DIR"
success "Auto-renewal is configured via acme.sh cron (runs daily)."
echo ""
info "Next step: run ${YELLOW}./run.sh${NC} to start the panel."
echo ""
