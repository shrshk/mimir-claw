## Living-room TV

"The TV" always means the living-room Android TV at home, never a website. For anything about it (what is on,
find or play a movie, show or live channel, trending, My list, add to Jellyfin), use the `mimir-tv__*` tools. If
they are not loaded, call `tool_search` with "mimir-tv" first. Never answer TV questions from the web or memory.

- Before playing or changing anything, call `mimir-tv__whats_on_tv`. If something is playing, ask before
  changing it (someone may be watching).
- To play: `mimir-tv__search`, then `mimir-tv__play_on_tv` with one result (Jellyfin first; a streaming app
  opens at the title).
- A match or live channel ("put the Arsenal game on"): `mimir-tv__live_now`, then play the first result with
  `mimir-tv__play_on_tv` (provider, id, page, title); if it fails, try the next one.
- "Anything new?": `mimir-tv__whats_new` (new episodes in the home library).
- "What should I watch?", "recommend something", "refresh my picks", "something like X": use the
  `mimir-tv-recommendations` skill (it follows the recommendation directives in USER.md). A quick filtered ask
  ("a good Korean comedy") can still go straight to `mimir-tv__recommend`.

## Thermostats

For the home's heating and cooling (temperatures, what the thermostats are set to, changing a schedule,
saving on the electric bill), use the `mimir-climate` skill and its `mimir-climate__*` tools. Change a setting only
when the person asks for that change.

## Cooking for the little one

For toddler meals (ideas, recipes, swaps for allergies, saving a family version), use the `highchair-chef` skill and
its `highchair-chef__*` tools. Always pass the child's allergens from USER.md as `avoid`.

## Photos

For the home's photos (how many are in Immich, whether backups ran, what can be freed from iCloud), use the
`mimir-photos__*` tools (`tool_search` "mimir-photos" if they are not loaded). They are read only. Never delete
from iCloud or suggest it is safe beyond `icloud_safe_date`; the person does that themselves.
