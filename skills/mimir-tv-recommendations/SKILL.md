---
name: mimir-tv-recommendations
description: Recommend movies and shows by the person's own taste, with the morning's public reviews; keep the titles they choose on their picks list.
---

# mimir-tv recommendations

Use this for "what should I watch?", "recommend something", "anything good and new?", and the morning picks
automation. Recommendations happen here, in this chat. mimir-tv is the library: you read its data, and you write
to it only when the person says so (My list, 👍/👎). All its tools are `mimir-tv__*` (if they are not
loaded, call `tool_search` with "mimir-tv" first).

## The person's taste

Their own recommendation preferences are directives in USER.md (for example "Prefer new movies", "Prefer Korean
movies"). Follow them; they outrank everything below. If there are none, recommend by `taste` and good ratings.
Never write their preferences into this skill. When they state a new lasting preference, record it in USER.md.

`mimir-tv__taste` gives what the house watched (genres and people weighted), liked and disliked titles, and the
house's rules. The rules (genres to avoid, languages to keep) are already applied by every mimir-tv tool.

## Morning picks (the automation, or "what's good this week?")

1. Read `reviews/today.md` in your workspace: public reviews of new titles, written at 6:00 each morning by the
   researcher (another agent that sees nothing of the household). One line per title: title (year) | kind | verdict |
   what people say | sources. If the file is missing or its date is not today, go on without reviews and say so in
   one line. Don't ask any other agent for anything.
2. `mimir-tv__taste`.
3. Build a pool (each call is cached by mimir-tv for a day):
   - `mimir-tv__candidates` with `year_from` last year when they prefer new titles, and kind movie when they
     prefer movies (thinly rated titles are already left out);
   - for preferred languages, `mimir-tv__candidates` again with `language` (two-letter codes such as ko, es, hi, ja).
     Skip a language that returns nothing;
   - every title the reviews say people loved or liked: one `mimir-tv__find_titles` call with all of them (title,
     year, kind). Found ones join the pool with their review, even when thinly rated: the review is the reason.
4. Rank by their directives: their languages and newer titles first; a loved or liked review lifts a title, a mixed
   one lowers it, a disliked one drops it; nothing they disliked, already watched, or already on `picks/list.md`.
5. Post the top 10 here once, numbered, and nothing before it (no notes on how you worked): title (year), language, where it plays, rating
   with votes, and one line why. The why uses only facts from the tools and from reviews/today.md. Say people praise
   a title only when its line in reviews/today.md says so; otherwise describe the story and the rating. Never invent
   rankings, trends, verdicts or claims.
6. End with: "Want to keep any? Say the numbers, or all."

The morning run is scheduled and nobody is watching when it runs: post the picks anyway, every morning, even if
yesterday's are still in the thread. The person reads this thread later and replies here. Never answer NO_REPLY
to a morning picks request.

## In a chat

- When they choose ("2 and 5", "all of them", "add Drishyam"), keep them on their picks list: `picks/list.md` in
  your workspace, one line per title, newest first: date | title (year) | kind | tmdb | where it plays. Keep only
  what they chose; never add without being asked. Say what was added and what was already there.
  mimir-tv's My list is their Jellyfin favourites: a chosen title the home library has (`mimir-tv__search` lists it
  under library) also goes there, with `mimir-tv__add_to_my_list` and its `jellyfin_ids`. Streaming titles stay
  on the picks list only.
- "What's on my list?", "my picks": read `picks/list.md`, newest first, and `mimir-tv__my_list` for the library's.
  When they watched one or say to drop it, take its line out.
- "Play it": `mimir-tv__whats_on_tv` first (if something is playing, ask before changing it), then
  `mimir-tv__play_on_tv` with the app, title and tmdb.
- "Something like X": `mimir-tv__similar_to` (find X's tmdb with `mimir-tv__search`).
- "Tell me more about 3": `mimir-tv__title_details`.
- When they react to a title ("loved it", "not my thing", "never show me that"), record it with
  `mimir-tv__feedback` (up or down). Down leaves it out everywhere from then on.

## Keep it light

One morning run a day. Call candidates once, plus once per preferred
language; don't fetch details for titles you will not show.
