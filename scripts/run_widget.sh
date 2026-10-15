#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/deployment.sh"

if ! deployment_app_is_packaged; then
  "$SCRIPT_DIR/package_app.sh" >/dev/null
fi

open "$DEPLOYMENT_APP_DIR"
