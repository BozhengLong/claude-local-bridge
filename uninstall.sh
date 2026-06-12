#!/usr/bin/env bash
set -euo pipefail

LABEL="com.claude-gw-proxy"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

launchctl unload "$PLIST" 2>/dev/null || true
rm -f "$PLIST"
echo "已停止并卸载 $LABEL。"
echo "socat / caddy 若不再需要,可自行: brew uninstall socat  或  brew uninstall caddy"
