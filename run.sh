#!/bin/bash

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

echo -e "${GREEN}[*] Detecting Docker Compose version...${NC}"
if docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
elif docker-compose version >/dev/null 2>&1; then
    COMPOSE_CMD="docker-compose"
else
    echo -e "${RED}[X] Neither 'docker compose' nor 'docker-compose' was found!${NC}"
    exit 1
fi
echo -e "${GREEN}[✓] Using command: ${YELLOW}$COMPOSE_CMD${NC}"

echo -e "${GREEN}[*] Launching Docker Compose container...${NC}"
if [ ! -f "compose.yml" ] && [ ! -f "docker-compose.yml" ]; then
    echo -e "${RED}[X] Configuration file (compose.yml / docker-compose.yml) not found!${NC}"
    exit 1
fi

$COMPOSE_CMD up -d

echo -e "${GREEN}[*] Waiting 5 seconds for the database to initialize...${NC}"
sleep 5

export RANDOM_PATH=$(openssl rand -hex 8)

echo -e "${GREEN}[*] Automatically injecting SSL paths and secret path into the database...${NC}"
python3 -c "
import sqlite3
import os

db_path = './db/x-ui.db'
if os.path.exists(db_path):
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    c.execute('CREATE TABLE IF NOT EXISTS settings (id INTEGER PRIMARY KEY AUTOINCREMENT, key TEXT UNIQUE, value TEXT)')
    r_path = f'/{os.environ[\"RANDOM_PATH\"]}/'
    c.execute(\"INSERT OR REPLACE INTO settings (key, value) VALUES ('webBasePath', ?)\", (r_path,))
    c.execute(\"INSERT OR REPLACE INTO settings (key, value) VALUES ('webCertFile', '/root/cert/ip/fullchain.pem')\")
    c.execute(\"INSERT OR REPLACE INTO settings (key, value) VALUES ('webCertKey', '/root/cert/ip/privkey.pem')\")
    c.execute(\"INSERT OR REPLACE INTO settings (key, value) VALUES ('webKeyFile', '/root/cert/ip/privkey.pem')\")
    conn.commit()
    conn.close()
    print('Database successfully hardcoded with SSL settings.')
else:
    print('Database file not found yet.')
"

echo -e "${GREEN}[*] Restarting container to apply secure configuration...${NC}"
docker restart 3xui_app

SERVER_IP=$(curl -s ifconfig.me || curl -s api.ipify.org || echo "YOUR_SERVER_IP")

echo -e "${GREEN}=======================================================${NC}"
echo -e "${GREEN}[✓] SUCCESS! Your instance is ready!${NC}"
echo -e "${GREEN}[*] You can log into your new panel immediately at:${NC}"
echo -e "    ${YELLOW}https://$SERVER_IP:2057/$RANDOM_PATH/${NC}"
echo -e "${GREEN}=======================================================${NC}"
