#!/usr/bin/env bash

deployment_scripts_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DEPLOYMENT_ROOT="$(cd "$deployment_scripts_dir/.." && pwd)"
DEPLOYMENT_OUTPUT_DIR="$DEPLOYMENT_ROOT/outputs"
DEPLOYMENT_BUILD_DIR="$DEPLOYMENT_ROOT/.build-20261013"

DEPLOYMENT_APP_NAME="Local Model Widget"
DEPLOYMENT_EXECUTABLE_NAME="LocalModelWidget"
DEPLOYMENT_SWIFT_PRODUCT="$DEPLOYMENT_EXECUTABLE_NAME"
DEPLOYMENT_BUNDLE_IDENTIFIER="local.codex.LocalModelWidget"
DEPLOYMENT_BUNDLE_VERSION="0.1.0"
DEPLOYMENT_MIN_SYSTEM_VERSION="14.0"

DEPLOYMENT_APP_DIR="$DEPLOYMENT_OUTPUT_DIR/$DEPLOYMENT_APP_NAME.app"
DEPLOYMENT_CONTENTS_DIR="$DEPLOYMENT_APP_DIR/Contents"
DEPLOYMENT_MACOS_DIR="$DEPLOYMENT_CONTENTS_DIR/MacOS"
DEPLOYMENT_RESOURCES_DIR="$DEPLOYMENT_CONTENTS_DIR/Resources"
DEPLOYMENT_EXECUTABLE_PATH="$DEPLOYMENT_MACOS_DIR/$DEPLOYMENT_EXECUTABLE_NAME"
DEPLOYMENT_INFO_PLIST_PATH="$DEPLOYMENT_CONTENTS_DIR/Info.plist"
DEPLOYMENT_RESOURCES_SOURCE_DIR="$DEPLOYMENT_ROOT/Resources"

DEPLOYMENT_LAUNCH_AGENT_LABEL="$DEPLOYMENT_BUNDLE_IDENTIFIER"
DEPLOYMENT_LAUNCH_AGENT_PLIST_NAME="$DEPLOYMENT_LAUNCH_AGENT_LABEL.plist"
DEPLOYMENT_LAUNCH_AGENT_SOURCE="$DEPLOYMENT_OUTPUT_DIR/$DEPLOYMENT_LAUNCH_AGENT_PLIST_NAME"
DEPLOYMENT_LAUNCH_AGENT_DEST="$HOME/Library/LaunchAgents/$DEPLOYMENT_LAUNCH_AGENT_PLIST_NAME"
DEPLOYMENT_LAUNCH_AGENT_DOMAIN="gui/$(id -u)"
DEPLOYMENT_STDOUT_LOG="/tmp/local-model-widget.out.log"
DEPLOYMENT_STDERR_LOG="/tmp/local-model-widget.err.log"

deployment_xml_escape() {
  printf '%s' "$1" | sed \
    -e 's/&/\&amp;/g' \
    -e 's/</\&lt;/g' \
    -e 's/>/\&gt;/g' \
    -e 's/"/\&quot;/g' \
    -e "s/'/\&apos;/g"
}

deployment_render_info_plist() {
  cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$(deployment_xml_escape "$DEPLOYMENT_EXECUTABLE_NAME")</string>
  <key>CFBundleIdentifier</key>
  <string>$(deployment_xml_escape "$DEPLOYMENT_BUNDLE_IDENTIFIER")</string>
  <key>CFBundleName</key>
  <string>$(deployment_xml_escape "$DEPLOYMENT_APP_NAME")</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$(deployment_xml_escape "$DEPLOYMENT_BUNDLE_VERSION")</string>
  <key>LSMinimumSystemVersion</key>
  <string>$(deployment_xml_escape "$DEPLOYMENT_MIN_SYSTEM_VERSION")</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
PLIST
}

deployment_render_launch_agent_plist() {
  cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$(deployment_xml_escape "$DEPLOYMENT_LAUNCH_AGENT_LABEL")</string>
  <key>ProgramArguments</key>
  <array>
    <string>$(deployment_xml_escape "$DEPLOYMENT_EXECUTABLE_PATH")</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <dict>
    <key>Crashed</key>
    <true/>
  </dict>
  <key>LimitLoadToSessionType</key>
  <string>Aqua</string>
  <key>ProcessType</key>
  <string>Interactive</string>
  <key>WorkingDirectory</key>
  <string>$(deployment_xml_escape "$DEPLOYMENT_ROOT")</string>
  <key>StandardOutPath</key>
  <string>$(deployment_xml_escape "$DEPLOYMENT_STDOUT_LOG")</string>
  <key>StandardErrorPath</key>
  <string>$(deployment_xml_escape "$DEPLOYMENT_STDERR_LOG")</string>
</dict>
</plist>
PLIST
}

deployment_write_info_plist() {
  deployment_render_info_plist > "$DEPLOYMENT_INFO_PLIST_PATH"
}

deployment_write_launch_agent_plist() {
  deployment_render_launch_agent_plist > "$DEPLOYMENT_LAUNCH_AGENT_SOURCE"
}

deployment_app_is_packaged() {
  [[ -x "$DEPLOYMENT_EXECUTABLE_PATH" && -f "$DEPLOYMENT_INFO_PLIST_PATH" ]]
}

deployment_launch_agent_target() {
  printf '%s/%s' "$DEPLOYMENT_LAUNCH_AGENT_DOMAIN" "$DEPLOYMENT_LAUNCH_AGENT_LABEL"
}

deployment_launchctl_bootout() {
  launchctl bootout "$DEPLOYMENT_LAUNCH_AGENT_DOMAIN" "$DEPLOYMENT_LAUNCH_AGENT_DEST"
}

deployment_launchctl_bootstrap() {
  launchctl bootstrap "$DEPLOYMENT_LAUNCH_AGENT_DOMAIN" "$DEPLOYMENT_LAUNCH_AGENT_DEST"
}

deployment_launchctl_enable() {
  launchctl enable "$(deployment_launch_agent_target)"
}

deployment_launchctl_disable() {
  launchctl disable "$(deployment_launch_agent_target)"
}

deployment_launchctl_kickstart() {
  launchctl kickstart -k "$(deployment_launch_agent_target)"
}

deployment_launchctl_print() {
  launchctl print "$(deployment_launch_agent_target)"
}

deployment_check_generated_plists() {
  local tmp_dir
  tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/local-model-widget-plists.XXXXXX")"

  (
    trap 'rm -rf "$tmp_dir"' EXIT
    deployment_render_info_plist > "$tmp_dir/Info.plist"
    deployment_render_launch_agent_plist > "$tmp_dir/$DEPLOYMENT_LAUNCH_AGENT_PLIST_NAME"
    plutil -lint "$tmp_dir/Info.plist" "$tmp_dir/$DEPLOYMENT_LAUNCH_AGENT_PLIST_NAME" >/dev/null
  )
}

deployment_print_paths() {
  cat <<PATHS
root=$DEPLOYMENT_ROOT
app=$DEPLOYMENT_APP_DIR
executable=$DEPLOYMENT_EXECUTABLE_PATH
info_plist=$DEPLOYMENT_INFO_PLIST_PATH
launch_agent_label=$DEPLOYMENT_LAUNCH_AGENT_LABEL
launch_agent_source=$DEPLOYMENT_LAUNCH_AGENT_SOURCE
launch_agent_dest=$DEPLOYMENT_LAUNCH_AGENT_DEST
launch_agent_target=$(deployment_launch_agent_target)
PATHS
}

deployment_usage() {
  cat <<USAGE
Usage: scripts/deployment.sh <command>

Commands:
  info-plist           Print the generated app Info.plist.
  launch-agent-plist   Print the generated LaunchAgent plist.
  check                Generate both plists in a temp dir and lint them.
  paths                Print deployment paths and launchctl target.
USAGE
}

deployment_main() {
  case "${1:-}" in
    info-plist)
      deployment_render_info_plist
      ;;
    launch-agent-plist)
      deployment_render_launch_agent_plist
      ;;
    check)
      deployment_check_generated_plists
      ;;
    paths)
      deployment_print_paths
      ;;
    -h|--help|help)
      deployment_usage
      ;;
    *)
      deployment_usage >&2
      return 64
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
  deployment_main "$@"
fi
