#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────
# Formbricks – Push to Docker Hub
# Image: mbordasch/formbricks_cl:latest
# ─────────────────────────────────────────────

LOCAL_IMAGE="formbricks_cl:latest"
IMAGE="mbordasch/formbricks_cl:latest"

GREEN="\033[0;32m"
RED="\033[0;31m"
NC="\033[0m"

ok()   { echo -e "${GREEN}✔ $*${NC}"; }
fail() { echo -e "${RED}✘ $*${NC}"; exit 1; }

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Push: $IMAGE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

command -v docker >/dev/null 2>&1 || fail "Docker is not installed."
ok "Docker available."

echo "Logging in to Docker Hub..."
docker login || fail "Docker Hub login failed."
ok "Logged in."

echo ""
echo "Tagging $LOCAL_IMAGE → $IMAGE..."
docker tag "$LOCAL_IMAGE" "$IMAGE"
ok "Tagged."

echo ""
echo "Pushing $IMAGE..."
docker push "$IMAGE"
ok "Image pushed: $IMAGE"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}Done!${NC} Pull on the server with:"
echo "  docker compose pull"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
