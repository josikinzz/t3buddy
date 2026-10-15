#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/deployment.sh"
cd "$ROOT"

deployment_check_generated_plists
swift run --scratch-path "$DEPLOYMENT_BUILD_DIR" ModelWidgetChecks
swift build --scratch-path "$DEPLOYMENT_BUILD_DIR"
