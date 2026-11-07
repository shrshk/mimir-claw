---
name: mimir-climate
description: Read the home's thermostats and change their schedules when the person asks; help keep the electric bill down without making the house uncomfortable.
---

# mimir-climate (the thermostats)

Use this for anything about the home's heating and cooling: "how warm is it upstairs?", "is the AC running?", "make
it warmer at night", "what are the thermostats set to?", "can we save on the electric bill?". All tools are
`mimir-climate__*` (if they are not loaded, call `tool_search` with "mimir-climate" first). Never answer from memory:
the readings change all the time.

## The tools

- `mimir-climate__status`: every thermostat now (temperature, humidity, heating/cooling/idle, mode, heat_to,
  cool_to). Heat starts below heat_to; cooling starts above cool_to. Degrees Fahrenheit.
- `mimir-climate__schedule` (system): the schedule's periods (period_id, start, heat, cool, fan) and the limits.
- `mimir-climate__set_schedule_period` (system, period_id, and start, heat and/or cool; every_day): changes one
  period and checks it by reading the schedule again. A period runs from its start until the next one starts, so
  "night from 9:30 pm to 8 am" is the night period starting 9:30 pm and the morning period starting 8:00 am.
  Start times go in quarter hours. When `schedule` shows days `INDIVIDUAL_DAYS` (period ids 0-27, four per day),
  pass `every_day: true` to change the same period on all seven days, unless the person named a day.

Each call drives the maker's web portal and takes up to a minute or two. Call `status` once per question, not per
system. If a tool says the portal did not answer, wait a few minutes and try once more; then tell the person.

## The person's comfort

Their comfort and saving preferences (the range they like, warmer or cooler at night, rooms that matter) are
directives in USER.md. Follow them; they outrank everything below. When they state a new lasting preference
("we like 72 to 80"), record it in USER.md. Never write it into this skill.

## Changing a setting

1. Change only what the person asked for. Never change a setting on your own initiative, even to save money:
   suggest it and wait for "yes".
2. `schedule` for the system first, to find the period (by its start time) and the current setpoints.
3. Check the request against the limits before calling: each setpoint inside its range, and cool at least the
   deadband (usually 3) above heat. If it does not fit ("cool 72 at night" while heat is 72), say why and offer
   the nearest choice that fits (cool 72 with heat 69 or lower); don't pick one yourself.
4. `set_schedule_period` once per period. Give only what changes; the rest stays.
5. Say what changed, before and after, in one or two lines ("Upstairs, from 11:00 pm: cool 84 → 78; heat stays 72").

A change applies only while the system runs that schedule. If `status` shows a different mode (AWAY, "cool only",
"heat only", "off"), say so: the person ends Away or picks the schedule on the thermostat or in the maker's app. The
portal shows no schedules while a system is in AWAY.

## Saving money (when asked)

- In the cooling season, each degree higher on cool_to saves roughly 3-5% of cooling energy. Night and away
  periods are the cheapest to raise.
- A wide gap between heat and cool (for example 72 to 80) keeps the system idle most of the time.
- If the home heats with gas, the heat setpoint costs gas, not much electricity; say which bill a change affects.
- Suggest at most two changes at a time, each with its rough effect, and ask before making them.
