# mimir-claw

The home's assistant setup for OpenClaw: the Personal agent's skills, and later its whole setup (workspace
instructions, MCP servers, models, automations) so a new Mac can be brought up from here.

Private. The person's own data stays out of git: USER.md (their directives), MEMORY.md and memory/, sessions,
credentials and tokens live only on the Mac running OpenClaw (or in 1Password).

## Skills

Two agents, one privacy line. The researcher reads the public web and sees nothing of the house; the judge sees the
house's taste and never searches the web. Neither can message the other: a command job hands the researcher's reply
to the judge as a file. Recommendations happen in the Personal agent's chat; mimir-tv is written to only when the
person says so ("add 2 and 5 to my list").

| Skill | Agent | What it does | Tools |
|---|---|---|---|
| [movie-reviews](skills/movie-reviews/SKILL.md) | ChatGPT agent (web search; every `mimir-tv__*` tool denied) | Asked each morning in its own `reviews` session, finds what people say about new titles (Reddit, X, Instagram, TikTok, critics) and replies with a short list | web search only |
| [mimir-tv-recommendations](skills/mimir-tv-recommendations/SKILL.md) | Personal agent (Bedrock) | Reads the morning's reviews, ranks by the person's USER.md directives and the house's taste, posts the picks in its `mimir-picks` thread, adds the chosen ones to My list | `mimir-tv__*` |
| [mimir-climate](skills/mimir-climate/SKILL.md) | Personal agent (Bedrock) | Reads the thermostats; changes a schedule period only when the person asks; suggests savings by the person's USER.md comfort directives | `mimir-climate__*` |
| [highchair-chef](skills/highchair-chef/SKILL.md) | Personal agent (Bedrock) | Finds toddler recipes by the child's age and allergies in USER.md, adapts them, saves family versions that show in the app | `highchair-chef__*` |

## Bring up OpenClaw on a new Mac

1. Run `bash scripts/prereqs.sh`: it checks what the Mac needs and installs Node, OpenClaw and Tailscale when
   missing (it asks first; `--yes` to skip asking, `--check` to only look). It says what only you can do:
   Homebrew's installer, `openclaw onboard` (local gateway on loopback; keep its token in 1Password), Bedrock,
   signing in to Tailscale. It tests Bedrock with one tiny Haiku call, not only that the profile exists. The
   bootstrap (step 3) runs it too. Sign in to ChatGPT only if you want the optional ChatGPT agent (step 3,
   `--chatgpt`).

   For Bedrock, sign in to your AWS account as an admin in your own terminal and run `bash scripts/bedrock-aws.sh`
   (`--admin-profile NAME` if that profile is not `default`). It makes the AWS user `openclaw-air` (only once),
   lets it call only Claude through the us-east-2 inference profiles, writes its keys to `~/.aws/credentials` as
   profile `openclaw-air` (never printed) and tests them. Safe to run again: working keys are kept; `--rotate`
   replaces them and puts the old ones back if the new ones fail. If the test says so, send Anthropic's one-time
   use-case form in the Bedrock console (Model catalog, a Claude model).
2. Install and start mimir-tv, mimir-photos, [mimir-climate](https://github.com/shrshk/mimir-climate) and
   [Highchair Chef](https://github.com/shrshk/recipes) once: each makes the token OpenClaw uses for its MCP
   (`~/.config/mimir-tv/mcp-token`, `~/Library/Application Support/mimir-photos/mcp-token`,
   `~/.config/mimir-climate/mcp-token`, `~/.config/recipes/mcp-token`).
3. Clone this repo to `~/src/mimir-claw` (the 6:00 job runs from there) and run `bash scripts/bootstrap.sh`
   (`--dry-run` first validates the config only). It always sets up the Personal agent and its skills. Add
   `--chatgpt` for the ChatGPT agent (the public reviews researcher, its web search and the 6:00 reviews job,
   from [openclaw/config-chatgpt.json](openclaw/config-chatgpt.json)); a Mac that already has it keeps it. Without
   it, the morning picks go on without reviews. It is safe to run again: the config is a patch, the TV
   instructions sit between `<!-- mimir-claw:home -->` markers in the Personal agent's AGENTS.md, skills are
   replaced, and automations are added only when missing.
4. Pair the iPhone app (`openclaw qr`, in your own terminal: the code holds a secret), allow its notifications, and
   check the request's role before approving (`openclaw devices list`).

This home's own settings live in `~/.config/mimir-claw/local.json`, never in git (copy
[openclaw/local.example.json](openclaw/local.example.json)): `public_url` (the Control UI and phone pairing address,
for example behind Caddy; leave it out to keep both on the Mac), `timezone` for the automations, and
`reviews_focus` (what the morning researcher looks for first).

What it sets, from [openclaw/config.json](openclaw/config.json) (no secrets; `__HOME__` and `__PUBLIC_URL__` are
filled in):

- agents: `home` ("Personal", Bedrock Haiku; voice `talk.agentId` uses it) and, optional, `mimir-clawgpt` (ChatGPT);
- privacy: `tools.sessions.visibility: "agent"` (the default lets every agent read every other agent's transcripts),
  `agentToAgent.send: []` for both, the ChatGPT agent denies `mimir-tv__*`, `mimir-photos__*`, `mimir-climate__*`, `highchair-chef__*` and `nodes`;
- the phone: `gateway.nodes.commands.deny` blocks photos, contacts, calendar, reminders, location, motion, camera,
  screen recording, SMS and health;
- Bedrock models (Haiku, Sonnet, Opus), the mimir-tv, mimir-photos, mimir-climate and highchair-chef MCP servers (photos: read-only status,
  jobs and the iCloud safe date; no file names), the Caddy address for pairing, telemetry off.

Not in git, on purpose: USER.md (the person's directives), MEMORY.md and memory/, sessions, paired devices, the
gateway token and the ChatGPT sign-in.

Automations (in `timezone` from local.json, else the Mac's time zone), added by the bootstrap:

- 6:00 "Morning reviews": a shell command (no model in between) asks the researcher and writes reviews/today.md;
- 6:30 "Morning picks": the Personal agent on Sonnet (Haiku did not follow the ranking rules) posts in its
  `mimir-picks` thread;
- 7:00 and 18:00 "Home board": the Personal agent (Haiku) refreshes the `home-status` report on the dashboard of
  its `home-board` thread (photos, jobs, the iCloud safe date, the TV, new episodes) from the MCP tools
  ([openclaw/home-board.md](openclaw/home-board.md)). See it in the Control UI at your `public_url`/dashboards; ask
  "refresh the home board" in that thread for a fresh one.
