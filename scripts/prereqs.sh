#!/usr/bin/env bash
# What this Mac needs before bootstrap.sh: each part checked, the missing ones installed when the person says yes
# (or with --yes), the steps only the person can do (Homebrew's installer, OpenClaw's onboarding, signing in) shown
# with what to type. Run by bootstrap.sh first; also on its own:
#   scripts/prereqs.sh [--yes] [--check]
# --check only reports. Exits 1 while a required part is missing.
set -euo pipefail
YES=""; CHECK=""
for arg in "$@"; do
  case $arg in
    --yes) YES=1 ;;
    --check|--dry-run) CHECK=1 ;;
    *) echo "usage: prereqs.sh [--yes] [--check]" >&2; exit 2 ;;
  esac
done
for d in /usr/local/bin /opt/homebrew/bin; do if [ -d "$d" ]; then PATH=$d:$PATH; fi; done
TAILSCALE_APP=/Applications/Tailscale.app/Contents/MacOS/Tailscale  # the Mac app does not put it on PATH
missing=0

ok() { printf '  ok       %-10s %s\n' "$1" "$2"; }
todo() { printf '  missing  %-10s %s\n' "$1" "$2"; }

# install <name> <command...>: asks first (a terminal), or --yes; never with --check or without a terminal
install() {
  local name=$1; shift
  [ -z "$CHECK" ] || return 1
  if [ -z "$YES" ]; then
    [ -t 0 ] || { echo "           to install: $*"; return 1; }
    read -r -p "           install $name now ($*)? [y/N] " answer
    [[ $answer == [yY]* ]] || return 1
  fi
  "$@"
}

echo "Before you start:"

# Homebrew: its installer asks for the Mac's password, so the person runs it
if command -v brew >/dev/null; then ok brew "$(command -v brew)"; else
  todo brew "installs the other parts: paste the line from https://brew.sh into Terminal, then run this again"
  exit 1
fi

# python3: bootstrap.sh uses it to merge the config (macOS's own comes with the Command Line Tools)
if python3 -c '' 2>/dev/null; then ok python3 "$(command -v python3)"; else
  todo python3 "run xcode-select --install, then this again"; missing=1
fi

# Node: OpenClaw runs on it (its package.json: ">=24.22.1 <25 || >=26.12.1")
node_fits() {
  node -e 'const [a, b, c] = process.versions.node.split(".").map(Number), v = a * 1e6 + b * 1e3 + c;
    process.exit((v >= 24022001 && a < 25) || v >= 26012001 ? 0 : 1)' 2>/dev/null
}
if node_fits; then ok node "$(node -v)"; else
  if command -v node >/dev/null; then
    todo node "$(node -v) is too old for OpenClaw (24.22.1+ or 26.12.1+)"
    install Node brew upgrade node || missing=1
  else
    todo node "not installed"
    install Node brew install node || missing=1
  fi
fi

# OpenClaw: in Homebrew's prefix (a user npm prefix like /usr/local needs root)
if command -v openclaw >/dev/null; then ok openclaw "$(openclaw --version 2>/dev/null | head -1)"; else
  todo openclaw "not installed"
  if install OpenClaw npm install -g --prefix "$(brew --prefix)" openclaw@latest --allow-scripts=openclaw; then
    command -v openclaw >/dev/null && ok openclaw "$(openclaw --version 2>/dev/null | head -1)" || missing=1
  else missing=1; fi
fi

# OpenClaw's own setup: the gateway and its token (the person keeps the token in their password manager)
if [ -f "$HOME/.openclaw/openclaw.json" ]; then ok onboarded "$HOME/.openclaw/openclaw.json"; else
  todo onboarded "run: openclaw onboard --install-daemon (local gateway on loopback), then this again"; missing=1
fi

# Bedrock: the Personal agent's model, through the AWS profile openclaw-air. One tiny call proves the keys, the
# user's policy and the account's model access (a profile that only exists would pass here and fail at 6:30).
if ! command -v aws >/dev/null; then
  todo aws "the AWS CLI sets up and tests Bedrock"
  install "the AWS CLI" brew install awscli || missing=1
fi
if ! command -v aws >/dev/null; then :
elif ! aws configure list-profiles 2>/dev/null | grep -qx openclaw-air; then
  todo bedrock "no profile openclaw-air: run scripts/bedrock-aws.sh, signed in to your AWS account as an admin"
  missing=1
elif reason=$(bash "$(dirname "$0")/bedrock-test.sh" openclaw-air 2>&1); then
  ok bedrock "Haiku answers (profile openclaw-air)"
else
  todo bedrock "profile openclaw-air does not reach Claude:"; printf '           %s\n' "$reason"; missing=1
fi

# Tailscale: the phone app reaches the gateway at home and away (optional: without it, home Wi-Fi only)
ts=$(command -v tailscale || { [ -x "$TAILSCALE_APP" ] && echo "$TAILSCALE_APP"; } || true)
if [ -z "$ts" ]; then
  todo tailscale "optional: lets the phone app reach OpenClaw away from home"
  install Tailscale brew install --cask tailscale && echo "           then open Tailscale and sign in" || true
elif [ "$("$ts" status --json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("BackendState",""))' 2>/dev/null)" = Running ]; then
  ok tailscale connected
else
  todo tailscale "optional: installed, not connected: open Tailscale and sign in"
fi

[ "$missing" = 0 ] || { echo "Finish the missing parts above, then run this again." >&2; exit 1; }
