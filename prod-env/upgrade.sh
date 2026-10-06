#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────
# Formbricks – Upgrade einer bestehenden Installation auf v6 (AuthZed/SpiceDB)
# Ablauf laut docs/self-hosting/advanced/authzed-operations.mdx:
#   Backup → App stoppen → SpiceDB + Migrationen → upgrade prepare → upgrade check → Start
# Bei späteren Updates (Migration bereits bestätigt) läuft derselbe Pfad, prepare ist idempotent.
# ─────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DC=(docker compose --project-directory "$SCRIPT_DIR")

GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m"

ok()   { echo -e "${GREEN}✔ $*${NC}"; }
warn() { echo -e "${YELLOW}⚠ $*${NC}"; }
fail() { echo -e "${RED}✘ $*${NC}"; exit 1; }

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Formbricks – Upgrade"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

[[ -f "$SCRIPT_DIR/.env" ]] || fail ".env not found in $SCRIPT_DIR."
for VAR in AUTHZED_TOKEN AUTHZED_DATABASE_PASSWORD HUB_API_KEY CUBEJS_API_SECRET; do
  grep -Eq "^${VAR}=.+" "$SCRIPT_DIR/.env" || fail "$VAR is not set in .env."
done
[[ -f "$SCRIPT_DIR/authzed-postgres-bootstrap.sh" ]] || fail "authzed-postgres-bootstrap.sh not found."
ok "Configuration found."

POSTGRES_USER=$(grep -E '^POSTGRES_USER=' "$SCRIPT_DIR/.env" | cut -d= -f2 | tr -d '"' | tr -d "'")

# ── 1. Pull images ───────────────────────────
echo ""
echo "Pulling Docker images..."
"${DC[@]}" pull
ok "Images pulled."

# ── 2. Stop writers ──────────────────────────
echo ""
echo "Stopping Formbricks (maintenance)..."
"${DC[@]}" stop formbricks traefik || true
ok "Formbricks stopped."

# ── 3. Backup ────────────────────────────────
echo ""
"${DC[@]}" up -d --wait postgres
mkdir -p "$SCRIPT_DIR/backups"
BACKUP_FILE="$SCRIPT_DIR/backups/pg_dumpall-$(date +%F-%H%M%S).sql.gz"
echo "Creating PostgreSQL backup → $BACKUP_FILE"
"${DC[@]}" exec -T postgres pg_dumpall -U "$POSTGRES_USER" | gzip > "$BACKUP_FILE"
[[ -s "$BACKUP_FILE" ]] || fail "Backup is empty – aborting."
chmod 600 "$BACKUP_FILE"
ok "Backup created ($(du -h "$BACKUP_FILE" | cut -f1))."

# ── 4. SpiceDB + database migrations ─────────
echo ""
echo "Starting SpiceDB..."
"${DC[@]}" up -d --wait spicedb
ok "SpiceDB healthy."

echo "Running Formbricks database migrations..."
"${DC[@]}" run --rm --no-deps formbricks-migrate
ok "Database migrated."

# ── 5. AuthZed preparation ───────────────────
echo ""
echo "Preparing AuthZed (schema, relationship backfill, audit)..."
"${DC[@]}" --profile authzed-ops run --rm --no-deps authzed-ops upgrade prepare \
  || fail "upgrade prepare failed – Formbricks stays stopped. Backup: $BACKUP_FILE"

echo "Checking AuthZed..."
"${DC[@]}" --profile authzed-ops run --rm --no-deps authzed-ops upgrade check \
  || fail "upgrade check not clean – Formbricks stays stopped. Backup: $BACKUP_FILE"
ok "AuthZed check clean."

if ! grep -Eq '^FORMBRICKS_AUTHZED_V6_MIGRATION_ACKNOWLEDGED=true$' "$SCRIPT_DIR/.env"; then
  sed -i 's/^FORMBRICKS_AUTHZED_V6_MIGRATION_ACKNOWLEDGED=.*/FORMBRICKS_AUTHZED_V6_MIGRATION_ACKNOWLEDGED=true/' "$SCRIPT_DIR/.env"
  ok "v6 migration acknowledged in .env."
fi

# ── 6. Start everything ──────────────────────
echo ""
echo "Starting services..."
"${DC[@]}" up -d
ok "Services started."

echo ""
"${DC[@]}" ps
echo ""
echo -e "${GREEN}Upgrade complete!${NC} Backup: $BACKUP_FILE"
echo "Logs: docker compose logs -f formbricks"
echo ""
