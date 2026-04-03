#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────
# Formbricks Production Setup Script
# Run this once on the production server.
# ─────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m"

ok()   { echo -e "${GREEN}✔ $*${NC}"; }
warn() { echo -e "${YELLOW}⚠ $*${NC}"; }
fail() { echo -e "${RED}✘ $*${NC}"; exit 1; }

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Formbricks – Production Setup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── 1. Install Docker if missing ─────────────
if ! command -v docker >/dev/null 2>&1; then
  echo "Docker not found — installing..."
  if [[ "$(id -u)" -ne 0 ]]; then
    fail "Docker is not installed. Please run this script as root (sudo) to install it automatically."
  fi
  apt-get update -qq
  apt-get install -y -qq ca-certificates curl gnupg lsb-release
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -qq
  apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
  ok "Docker installed."
else
  ok "Docker already installed."
fi

# ── 2. Check Docker Compose plugin ───────────
if ! docker compose version >/dev/null 2>&1; then
  echo "Docker Compose plugin not found — installing..."
  if [[ "$(id -u)" -ne 0 ]]; then
    fail "Docker Compose plugin is missing. Please run this script as root (sudo) to install it."
  fi
  apt-get install -y -qq docker-compose-plugin
  ok "Docker Compose plugin installed."
else
  ok "Docker Compose already available."
fi

# ── 2. Check .env exists ─────────────────────
if [[ ! -f "$SCRIPT_DIR/.env" ]]; then
  fail ".env file not found in $SCRIPT_DIR. Please create it before running this script."
fi
ok ".env file found."

# ── 3. Load domain from .env ─────────────────
DOMAIN=$(grep -E '^DOMAIN=' "$SCRIPT_DIR/.env" | cut -d= -f2 | tr -d '"' | tr -d "'")
if [[ -z "$DOMAIN" ]]; then
  fail "DOMAIN is not set in .env."
fi
ok "Domain: $DOMAIN"

# ── 4. DNS check ─────────────────────────────
echo "Checking DNS resolution for $DOMAIN..."
SERVER_IP=$(curl -sf https://api.ipify.org || true)
RESOLVED_IP=$(dig +short "$DOMAIN" A | tail -n1 || true)

if [[ -z "$RESOLVED_IP" ]]; then
  warn "Could not resolve $DOMAIN via DNS. Make sure your A record is set before continuing."
elif [[ -n "$SERVER_IP" && "$RESOLVED_IP" != "$SERVER_IP" ]]; then
  warn "DNS mismatch: $DOMAIN resolves to $RESOLVED_IP, but this server's IP is $SERVER_IP."
  warn "Let's Encrypt certificate will fail until DNS points to this server."
else
  ok "DNS resolves to $RESOLVED_IP."
fi

# ── 5. Check ports 80 and 443 ────────────────
echo "Checking port availability..."
for PORT in 80 443; do
  if ss -tlnp | grep -q ":$PORT "; then
    warn "Port $PORT is already in use. Make sure nothing else is binding it."
  else
    ok "Port $PORT is free."
  fi
done

# ── 6. Create acme.json ──────────────────────
ACME_FILE="$SCRIPT_DIR/acme.json"
if [[ -f "$ACME_FILE" && -s "$ACME_FILE" ]]; then
  ok "acme.json already exists and is non-empty — skipping creation."
else
  echo "Creating acme.json..."
  > "$ACME_FILE"
  chmod 600 "$ACME_FILE"
  ok "acme.json created with permissions 600."
fi

# ── 7. Verify required config files ──────────
echo "Checking required config files..."
for FILE in docker-compose.yml traefik.yaml traefik-dynamic.yaml; do
  if [[ ! -f "$SCRIPT_DIR/$FILE" ]]; then
    fail "$FILE not found in $SCRIPT_DIR."
  fi
  ok "$FILE found."
done

# ── 8. Pull images ───────────────────────────
echo ""
echo "Pulling Docker images (this may take a while)..."
docker compose --project-directory "$SCRIPT_DIR" pull
ok "Images pulled."

# ── 9. Start services ────────────────────────
echo ""
echo "Starting services..."
docker compose --project-directory "$SCRIPT_DIR" up -d
ok "Services started."

# ── 10. Health summary ───────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Container status:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
docker compose --project-directory "$SCRIPT_DIR" ps
echo ""
echo -e "${GREEN}Setup complete!${NC}"
echo "Your app should be available at: https://$DOMAIN"
echo ""
echo "Tip: Watch Traefik get the certificate with:"
echo "  docker logs -f traefik"
echo ""
