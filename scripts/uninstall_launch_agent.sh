#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/deployment.sh"

deployment_launchctl_bootout 2>/dev/null || true
deployment_launchctl_disable 2>/dev/null || true
rm -f "$DEPLOYMENT_LAUNCH_AGENT_DEST"
