#!/bin/bash

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

echo -e "${GREEN}[*] Checking root privileges...${NC}"
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[X] Please run as root${NC}"
    exit 1
fi

echo -e "${GREEN}[*] Detecting Public IP address...${NC}"
SERVER_IP=$(curl -s ifconfig.me || curl -s api.ipify.org || echo "")

if [ -z "$SERVER_IP" ]; then
    echo -e "${RED}[X] Could not detect IP. Check your internet connection.${NC}"
    exit 1
fi
echo -e "${GREEN}[✓] IP Detected: ${YELLOW}$SERVER_IP${NC}"

# Check port 80
if lsof -i :80 > /dev/null 2>&1; then
    echo -e "${RED}[X] Port 80 is busy. Stop any web servers (Nginx/Apache) before running this.${NC}"
    exit 1
fi

echo -e "${GREEN}[*] Installing dependencies (socat, curl, lsof)...${NC}"
if command -v apt-get &> /dev/null; then
    apt-get update -qq && apt-get install -y -qq socat curl lsof
elif command -v yum &> /dev/null; then
    yum install -y -q socat curl lsof
fi

ACME_BIN="$HOME/.acme.sh/acme.sh"
if [ ! -f "$ACME_BIN" ]; then
    echo -e "${GREEN}[*] Installing acme.sh...${NC}"
    curl -s https://get.acme.sh | sh -s email=admin@$SERVER_IP
    export LE_WORKING_DIR="$HOME/.acme.sh"
fi

echo -e "${GREEN}[*] Requesting IP SSL Certificate from Let's Encrypt...${NC}"
if ! $ACME_BIN --issue -d "$SERVER_IP" --standalone --server letsencrypt --certificate-profile shortlived --days 6 --httpport 80 --force; then
    echo -e "${RED}[X] SSL issuance failed. Ensure Port 80 is open in your firewall.${NC}"
    exit 1
fi

echo -e "${GREEN}[*] Installing certificates to /root/cert/ip...${NC}"
mkdir -p /root/cert/ip

$ACME_BIN --installcert -d "$SERVER_IP" \
    --key-file /root/cert/ip/privkey.pem \
    --fullchain-file /root/cert/ip/fullchain.pem \
    --reloadcmd "docker restart 3xui_app || true"

chmod 600 /root/cert/ip/privkey.pem
chmod 644 /root/cert/ip/fullchain.pem
