#!/usr/bin/env bash
# Install (or update) mimir-ask on the Mac running OpenClaw, started at login (launchd), on 127.0.0.1:8728.
#   bash ask/install.sh            install or update
#   bash ask/install.sh --remove   stop and remove (its token in ~/.config/mimir-ask stays)
# Needs OpenClaw's OpenAI-style endpoint on (openclaw/config.json has it; scripts/bootstrap.sh applies it).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
LABEL=dev.mimir-ask
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
GUI="gui/$(id -u)"
PY=$(command -v /opt/homebrew/bin/python3 || command -v python3)

launchctl bootout "$GUI/$LABEL" 2>/dev/null || true
if [ "${1:-}" = "--remove" ]; then
  rm -f "$PLIST"
  echo "removed $LABEL"
  exit 0
fi

mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key><array><string>$PY</string><string>-I</string><string>$HERE/mimir_ask.py</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>StandardOutPath</key><string>$HOME/Library/Logs/mimir-ask.log</string>
    <key>StandardErrorPath</key><string>$HOME/Library/Logs/mimir-ask.log</string>
</dict>
</plist>
EOF
launchctl bootstrap "$GUI" "$PLIST"
launchctl kickstart -k "$GUI/$LABEL"
echo "installed $LABEL (log ~/Library/Logs/mimir-ask.log); its token: ~/.config/mimir-ask/token"
