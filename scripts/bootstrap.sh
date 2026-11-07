#!/usr/bin/env bash
# Brings OpenClaw on this Mac to the home setup kept in this repo. Safe to run again: it only sets what is here.
#   scripts/bootstrap.sh [--chatgpt] [--yes] [--dry-run]
# The Personal agent (`home`, Bedrock) and its skills are always set up. The ChatGPT agent (`mimir-clawgpt`, the
# public reviews researcher) is optional: added with --chatgpt, and kept when this Mac already has it.
# First it checks what the Mac needs (scripts/prereqs.sh): it installs Node, OpenClaw and Tailscale when missing
# (asking first, or --yes), and says what only the person can do: Homebrew's installer, OpenClaw's setup (`openclaw
# onboard`: the gateway, its token, which goes in 1Password), Bedrock (scripts/bedrock-aws.sh: the AWS user and its
# keys as profile openclaw-air, tested with one tiny call). Start mimir-flix, mimir-photos and mimir-climate once (each makes its MCP token file), and for --chatgpt sign in to
# ChatGPT (Codex) during onboarding.
# Then:
#   1. the MCP tokens, read from each app's own file (never printed, never in git);
#   2. config: agents, privacy, phone limits, Bedrock models, the MCP servers (openclaw/config.json);
#   3. the Personal agent's TV instructions in its AGENTS.md (openclaw/agents-home.md) and both agents' skills;
#   4. the automations, if missing: morning reviews and picks, and the Home board refresh.
# Not here, on purpose: USER.md, MEMORY.md, memory/, sessions, paired devices and tokens (personal or per machine).
set -euo pipefail
export PATH=/opt/homebrew/bin:$PATH
REPO=$(cd "$(dirname "$0")/.." && pwd)
DRY=""; CHATGPT=""; YES=""
for arg in "$@"; do
  case $arg in
    --dry-run) DRY=--dry-run ;;
    --chatgpt) CHATGPT=1 ;;
    --yes) YES=--yes ;;
    *) echo "usage: bootstrap.sh [--chatgpt] [--yes] [--dry-run]" >&2; exit 2 ;;
  esac
done
bash "$REPO/scripts/prereqs.sh" ${DRY:+--check} $YES
openclaw config get agents.entries.mimir-clawgpt.name >/dev/null 2>&1 && CHATGPT=1
if [ -n "$CHATGPT" ]; then echo "ChatGPT agent: yes"; else echo "ChatGPT agent: no (add it with --chatgpt)"; fi
# This home's own settings, never in git: ~/.config/mimir-claw/local.json (see openclaw/local.example.json)
LOCAL=${MIMIR_CLAW_LOCAL:-$HOME/.config/mimir-claw/local.json}
local_get() {  # <key>: its value in local.json, or nothing
  [ -f "$LOCAL" ] || return 0
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2]) or "")' "$LOCAL" "$1"
}
PUBLIC_URL=$(local_get public_url)
TZ_NAME=$(local_get timezone)
[ -n "$TZ_NAME" ] || TZ_NAME=$(readlink /etc/localtime | sed 's|.*/zoneinfo/||')
[ -n "$PUBLIC_URL" ] || echo "local: no public_url in $LOCAL; pairing and the Control UI stay on this Mac"
WS=$HOME/.openclaw/workspace
WS_HOME=$HOME/.openclaw/workspace-home

# 1. the MCP tokens, each read from its app's own file
set_token() {  # <env var> <file>
  if [ -f "$2" ]; then
    python3 -c 'import json,sys; print(json.dumps({"env": {"vars": {sys.argv[1]: open(sys.argv[2]).read().strip()}}}))' \
      "$1" "$2" | openclaw config patch --stdin $DRY >/dev/null
    echo "mcp token $1: set from $2"
  else
    echo "mcp token $1: $2 missing; start the app once, then run this again" >&2
  fi
}
set_token MIMIR_FLIX_MCP_TOKEN "$HOME/.config/mimir-flix/mcp-token"
set_token MIMIR_PHOTOS_MCP_TOKEN "$HOME/Library/Application Support/mimir-photos/mcp-token"
set_token MIMIR_CLIMATE_MCP_TOKEN "$HOME/.config/mimir-climate/mcp-token"
# 2. config (it refers to the tokens above)
# one patch (each patch restarts the gateway): the base, plus the ChatGPT agent's part when it is wanted
PUBLIC_URL=$PUBLIC_URL python3 - "$REPO/openclaw/config.json" ${CHATGPT:+"$REPO/openclaw/config-chatgpt.json"} <<'PY' \
  | sed "s|__HOME__|$HOME|g" | openclaw config patch --stdin $DRY >/dev/null
import json, os, sys
def merge(a, b):  # objects merge, everything else (arrays too) replaces, as `config patch` does
    for k, v in b.items():
        a[k] = merge(a[k], v) if isinstance(v, dict) and isinstance(a.get(k), dict) else v
    return a
out = {}
for f in sys.argv[1:]:
    merge(out, json.load(open(f)))
url = os.environ.get("PUBLIC_URL", "")
if url:  # this home's Control UI address (local.json)
    out["plugins"]["entries"]["device-pair"]["config"]["publicUrl"] = url
    out["gateway"]["controlUi"]["allowedOrigins"] = [url]
else:  # none: pairing and the Control UI stay on this Mac
    del out["plugins"]["entries"]["device-pair"]
    del out["gateway"]["controlUi"]
print(json.dumps(out))
PY
echo "config: patched${DRY:+ (dry run)}"

[ -z "$DRY" ] || exit 0

# 3. workspaces
mkdir -p "$WS_HOME"
python3 - "$WS_HOME/AGENTS.md" "$REPO/openclaw/agents-home.md" <<'PY'
import pathlib, sys
path, part = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]).read_text()
start, end = "<!-- mimir-claw:home -->", "<!-- /mimir-claw:home -->"
block = f"{start}\n{part.rstrip()}\n{end}\n"
text = path.read_text() if path.exists() else ""
if start in text:
    text = text[:text.index(start)] + block + text[text.index(end) + len(end):].lstrip("\n")
elif "## Living-room TV" in text:  # written by hand before this script; it is the last section
    text = text[:text.index("## Living-room TV")] + block
else:
    text = text.rstrip() + "\n\n" + block
path.write_text(text)
PY
echo "AGENTS.md: TV instructions in $WS_HOME"
[ -z "$CHATGPT" ] || bash "$REPO/scripts/install-skills.sh" "$WS" movie-reviews
bash "$REPO/scripts/install-skills.sh" "$WS_HOME" mimir-flix-recommendations mimir-climate

# 4. automations (in TZ_NAME: local.json, else this Mac's time zone)
# A config change restarts the gateway: wait for it, and stop rather than guess when the job list can't be read.
jobs="?"
for _ in $(seq 30); do
  jobs=$(openclaw cron list --json 2>/dev/null | python3 -c 'import json,sys; print(" ".join(j.get("declarationKey") or "" for j in json.load(sys.stdin)["jobs"]))' 2>/dev/null) && break
  jobs="?"; sleep 2
done
[ "$jobs" != "?" ] || { echo "automations: the gateway did not answer; run this again" >&2; exit 1; }
have() { [[ " $jobs " == *" $1 "* ]]; }
if [ -z "$CHATGPT" ]; then echo "automation mimir-reviews: skipped (no ChatGPT agent; picks go on without reviews)"
elif have mimir-reviews; then echo "automation mimir-reviews: there"; else
  openclaw cron add --name mimir-reviews --display-name "Morning reviews" --declaration-key mimir-reviews \
    --cron "0 6 * * *" --tz "$TZ_NAME" --session isolated \
    --command "bash $HOME/src/mimir-claw/scripts/gather-reviews.sh" --timeout-seconds 1500 >/dev/null
  echo "automation mimir-reviews: added"
fi
if have mimir-flix-picks; then echo "automation mimir-flix-picks: there"; else
  openclaw cron add --name mimir-flix-picks --display-name "Morning picks" --declaration-key mimir-flix-picks \
    --agent home --session session:mimir-picks --cron "30 6 * * *" --tz "$TZ_NAME" \
    --model amazon-bedrock/us.anthropic.claude-sonnet-4-6 --timeout-seconds 1200 --tools '*' --no-deliver \
    --description "Daily picks in the mimir-picks thread (mimir-flix-recommendations skill)" \
    --message "Morning picks with the mimir-flix-recommendations skill. Post them in this thread: the person reads it later." >/dev/null
  echo "automation mimir-flix-picks: added"
fi
if have home-board; then echo "automation home-board: there"; else
  openclaw cron add --name home-board --display-name "Home board" --declaration-key home-board \
    --agent home --session session:home-board --cron "0 7,18 * * *" --tz "$TZ_NAME" --timeout-seconds 600 \
    --tools '*' --no-deliver --description "Refreshes the home-status widget on the home-board thread's dashboard" \
    --message "$(cat "$REPO/openclaw/home-board.md")" >/dev/null
  echo "automation home-board: added"
fi
openclaw mcp reload >/dev/null 2>&1 && echo "mcp: reloaded" || echo "mcp: reload failed (is the gateway running?)" >&2
