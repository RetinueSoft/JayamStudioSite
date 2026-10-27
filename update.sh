#!/bin/sh
# Pulls the latest JayamStudioSite files from GitHub (no git needed)
# and serves them with the Caddy container defined in docker-compose.yml.
#
# Install on the VPS:
#   /root/jayamstudiosite/update.sh    (chmod +x)
#   /root/.github_token                (fine-grained token, Contents: Read-only, chmod 600)
# Cron (every 5 minutes):
#   */5 * * * * /root/jayamstudiosite/update.sh >> /var/log/jayamstudio-deploy.log 2>&1

set -eu

REPO="RetinueSoft/JayamStudioSite"
BRANCH="main"
SITE_DIR="/root/jayamstudiosite"
TOKEN_FILE="/root/.github_token"
LOCK_FILE="/tmp/jayamstudio-update.lock"

log() { echo "$(date '+%F %T') $*"; }

# Skip if a previous run is still going
if command -v flock >/dev/null 2>&1; then
  exec 9>"$LOCK_FILE"
  flock -n 9 || { log "another update is running, skipping"; exit 0; }
fi

if [ ! -s "$TOKEN_FILE" ]; then
  log "ERROR: token file $TOKEN_FILE is missing or empty"
  exit 1
fi
TOKEN=$(tr -d ' \r\n' < "$TOKEN_FILE")

api() {
  curl -fsSL --retry 3 --max-time 120 \
    -H "Authorization: Bearer $TOKEN" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$@"
}

# 1. Latest commit on the branch
LATEST=$(api -H "Accept: application/vnd.github.sha" \
  "https://api.github.com/repos/$REPO/commits/$BRANCH") || {
  log "ERROR: could not reach GitHub or token has no access to $REPO"
  exit 1
}

CURRENT=$(cat "$SITE_DIR/.deployed_sha" 2>/dev/null || echo none)
if [ "$LATEST" = "$CURRENT" ]; then
  exit 0
fi

log "new commit $LATEST (was $CURRENT), downloading"

# 2. Download and extract into a temp folder
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

api -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/$REPO/tarball/$LATEST" -o "$TMP/site.tar.gz"
mkdir "$TMP/src"
tar -xzf "$TMP/site.tar.gz" -C "$TMP/src" --strip-components=1

if [ ! -f "$TMP/src/index.html" ]; then
  log "ERROR: download has no index.html, aborting"
  exit 1
fi

# 3. Copy over the live folder (never overwrite this script while it runs)
rm -f "$TMP/src/update.sh"
mkdir -p "$SITE_DIR"
cp -a "$TMP/src"/. "$SITE_DIR"/
echo "$LATEST" > "$SITE_DIR/.deployed_sha"

# 4. Start the container if needed and reload Caddy config
cd "$SITE_DIR"
docker compose up -d
docker compose exec -T site caddy reload --config /etc/caddy/Caddyfile >/dev/null 2>&1 || true

log "deployed $LATEST"
