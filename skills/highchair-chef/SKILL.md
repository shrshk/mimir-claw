---
name: highchair-chef
description: Find toddler recipes, adapt them (swaps, allergies, portions) and save custom recipes the family can cook step by step in the Highchair Chef app.
---

# highchair-chef (toddler recipes)

Use this for cooking for the little one: "what can I make for dinner?", "something with lentils", "a dairy-free
mac and cheese", "make that for 6 and save it", "what did we save?". All tools are `highchair-chef__*` (if they
are not loaded, call `tool_search` with "highchair-chef" first). Answer from the tools, never from memory or the web:
the app only shows recipes the tools know.

## The child

The child's age, allergies, foods they refuse and the family's favourite cuisines are directives in USER.md. Pass
them on every search (`ageMonths`, `avoid`, `cuisines`), and follow them over everything below. When the person
states a new lasting fact ("she's off dairy now", "he hates mushrooms"), record it in USER.md, never in this skill.

## The tools

- `highchair-chef__find_recipes` (query, cuisines, meal, maxMinutes, avoid, ageMonths, picky, limit): ranked
  recipes with the reasons they were picked. `avoid` is a hard filter; always pass the child's allergens.
- `highchair-chef__get_recipe` (id): the full recipe, with ingredient ids and steps.
- `highchair-chef__prepare_recipe` (id, remove, swaps, extras, portions): the recipe as it will be cooked with
  those changes, for reading out or sending as a shopping list.
- `highchair-chef__get_recipe_format`: the format and rules for a custom recipe. Read it before saving one.
- `highchair-chef__save_custom_recipe` (recipe), `highchair-chef__list_custom_recipes`,
  `highchair-chef__delete_custom_recipe` (id).

## Making a custom recipe

1. Start from the closest recipe (`find_recipes`, then `get_recipe`) rather than inventing one, and set `basedOn`.
2. Change what the person asked for and nothing else. Keep the toddler rules: little or no salt, no honey under
   12 months, no whole nuts, grapes or popcorn, soft textures, mild heat.
3. Save with a new kebab-case id and a name the person would recognise ("Maya's mac"). If the tool returns
   problems, fix exactly those and save again; don't give up after one try.
4. Tell the person it is saved and that it shows in the app with a "Your recipe" badge, ready to cook step by step.

Delete a custom recipe only when the person asks for that recipe by name. Built-in recipes can't be changed.
