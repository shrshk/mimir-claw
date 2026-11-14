#!/usr/bin/env bash
# Copies skills from this repo into an OpenClaw agent workspace (replacing older copies of the same skills).
#   scripts/install-skills.sh <agent workspace> [skill …]     (no skills named: all of them)
# On the Air: the Personal agent (~/.openclaw/workspace-home) gets mimir-tv-recommendations, mimir-climate and highchair-chef; the ChatGPT agent
# (~/.openclaw/workspace) gets movie-reviews, the public researcher that sees nothing of the house.
set -euo pipefail
WS=${1:?usage: install-skills.sh <agent workspace> [skill …]}
shift
REPO=$(cd "$(dirname "$0")/.." && pwd)
names=("$@")
[ ${#names[@]} -gt 0 ] || names=($(ls "$REPO/skills"))
mkdir -p "$WS/skills"
for name in "${names[@]}"; do
  [ -f "$REPO/skills/$name/SKILL.md" ] || { echo "no skill $name" >&2; exit 1; }
  rm -rf "${WS:?}/skills/$name"
  cp -R "$REPO/skills/$name" "$WS/skills/$name"
  echo "installed $name in $WS"
done
