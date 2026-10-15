#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/deployment.sh"

if ! deployment_app_is_packaged; then
  "$SCRIPT_DIR/package_app.sh" >/dev/null
fi

mkdir -p "$(dirname "$DEPLOYMENT_LAUNCH_AGENT_DEST")"
deployment_write_launch_agent_plist

cp "$DEPLOYMENT_LAUNCH_AGENT_SOURCE" "$DEPLOYMENT_LAUNCH_AGENT_DEST"
plutil -lint "$DEPLOYMENT_LAUNCH_AGENT_DEST" >/dev/null

deployment_launchctl_bootout 2>/dev/null || true
deployment_launchctl_enable 2>/dev/null || true
deployment_launchctl_bootstrap
deployment_launchctl_enable
deployment_launchctl_kickstart

deployment_launchctl_print
