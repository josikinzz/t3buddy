#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/deployment.sh"

cd "$DEPLOYMENT_ROOT"
swift build --scratch-path "$DEPLOYMENT_BUILD_DIR" -c release --product "$DEPLOYMENT_SWIFT_PRODUCT"
swift build --scratch-path "$DEPLOYMENT_BUILD_DIR" -c release --product "$DEPLOYMENT_FEED_PRODUCT"

rm -rf "$DEPLOYMENT_APP_DIR"
mkdir -p "$DEPLOYMENT_MACOS_DIR"
cp "$DEPLOYMENT_BUILD_DIR/release/$DEPLOYMENT_EXECUTABLE_NAME" "$DEPLOYMENT_EXECUTABLE_PATH"
mkdir -p "$DEPLOYMENT_HELPERS_DIR"
cp "$DEPLOYMENT_BUILD_DIR/release/$DEPLOYMENT_FEED_PRODUCT" "$DEPLOYMENT_HELPERS_DIR/$DEPLOYMENT_FEED_PRODUCT"
deployment_write_info_plist

if [[ -d "$DEPLOYMENT_RESOURCES_SOURCE_DIR" ]]; then
  mkdir -p "$DEPLOYMENT_RESOURCES_DIR"
  cp -R "$DEPLOYMENT_RESOURCES_SOURCE_DIR"/. "$DEPLOYMENT_RESOURCES_DIR"/
fi

codesign --force --deep --sign - "$DEPLOYMENT_APP_DIR"
codesign --verify --deep --strict "$DEPLOYMENT_APP_DIR"

echo "$DEPLOYMENT_APP_DIR"
