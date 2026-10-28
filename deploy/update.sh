#!/usr/bin/env bash
# Deploys the website files of the release branch into /root/jayamstudiosite/site.
# The server's common Caddy serves that folder (VpsSetup caddy/sites/jayamstudio.caddy); nothing to restart.
# Needs /root/common (RetinueSoft/VpsSetup); /root/common/setup.sh installs it the first time.
#
#   sudo /root/jayamstudiosite/update.sh     deploy the newest release commit now (does nothing if already deployed)
#
# Runs every 5 minutes from /etc/cron.d/retinuesoft, so a merge to release is live within 5 minutes.
# To roll back, revert the change on GitHub (pull request into release); the next run deploys it.
set -euo pipefail

NAME="jayamstudiosite"
REPO="RetinueSoft/JayamStudioSite"

[ -f /root/common/lib.sh ] || { echo "/root/common is missing: run VpsSetup's setup.sh first"; exit 1; }
. /root/common/lib.sh

need_root "$@"
with_lock "$NAME"
load_token
self_update "$REPO" deploy/update.sh "$@"
deploy_static "$NAME" "$REPO"
