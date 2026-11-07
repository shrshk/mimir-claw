#!/usr/bin/env bash
# The morning handoff from the researcher to the judge, with no model in between: asks the ChatGPT agent (its own
# "reviews" session; it sees nothing of the house) for public reviews of new titles and writes its reply into the
# Personal agent's workspace, where the recommendations skill reads it. Run by an OpenClaw command job at 6:00.
#   scripts/gather-reviews.sh [focus]     (default: reviews_focus in ~/.config/mimir-claw/local.json)
set -euo pipefail
export PATH=/opt/homebrew/bin:$PATH
LOCAL=${MIMIR_CLAW_LOCAL:-$HOME/.config/mimir-claw/local.json}
saved=""
[ -f "$LOCAL" ] && saved=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("reviews_focus") or "")' "$LOCAL")
FOCUS=${1:-${saved:-"new releases, then big new movies and shows in any language"}}
OUT_DIR=${REVIEWS_DIR:-$HOME/.openclaw/workspace-home/reviews}
mkdir -p "$OUT_DIR"
tmp=$(mktemp "$OUT_DIR/.today.XXXXXX")
trap 'rm -f "$tmp"' EXIT
{
  echo "# Public reviews, $(date +%F) (from the researcher; one line per title)"
  echo
  openclaw agent --agent mimir-clawgpt --session-key agent:mimir-clawgpt:reviews --timeout 1200000 \
    -m "Gather reviews with the movie-reviews skill. Focus: $FOCUS. Reply with only the list."
} >"$tmp"
grep -q '|' "$tmp" || { echo "the researcher returned no list" >&2; exit 1; }
mv "$tmp" "$OUT_DIR/today.md"
trap - EXIT
