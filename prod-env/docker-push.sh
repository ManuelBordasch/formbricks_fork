#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────
# Formbricks – Push to Docker Hub
# Baut das Image (mit Upstream-Version) und pusht es nach Docker Hub
# ─────────────────────────────────────────────

LOCAL_IMAGE="formbricks_cl:latest"
IMAGE="mbordasch/formbricks_cl:V1.1"

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

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WEB_PKG="$REPO_ROOT/apps/web/package.json"

# Upstream setzt die Version erst in der Release-Pipeline (.github/actions/update-package-version);
# im Repo steht 0.0.0. Ohne das zeigt die App dauerhaft "Neue Version verfügbar".
APP_VERSION="${APP_VERSION:-$(git -C "$REPO_ROOT" describe --tags --abbrev=0 --match '[0-9]*.[0-9]*.[0-9]*')}"
[[ "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Invalid APP_VERSION: $APP_VERSION"

echo "Building $LOCAL_IMAGE with app version $APP_VERSION..."
cp "$WEB_PKG" "$WEB_PKG.orig"
trap 'mv "$WEB_PKG.orig" "$WEB_PKG"' EXIT
sed -i -E "0,/\"version\": \"[^\"]*\"/s//\"version\": \"$APP_VERSION\"/" "$WEB_PKG"
grep -q "\"version\": \"$APP_VERSION\"" "$WEB_PKG" || fail "Could not set version in $WEB_PKG"
docker build -f "$REPO_ROOT/apps/web/Dockerfile" -t "$LOCAL_IMAGE" "$REPO_ROOT"
ok "Built $LOCAL_IMAGE ($APP_VERSION)."

echo ""
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
