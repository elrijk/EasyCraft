# Third-party data

EasyCraft's own code is MIT-licensed (see `LICENSE`). The files in `Data/` were
generated with the author's tools from the sources below.

## pfQuest

Russian names and map coordinates of items, zones, NPCs and gathering nodes.

- Source: https://github.com/shagu/pfQuest
- License: MIT
- Copyright (c) 2017-2021 Eric Mauser (Shagu)

## Other sources

Trainer and vendor positions on WoW Forever were cross-checked by hand against
publicly available game databases.

The "XP: the most per hour" card
(`UI/Xp.lua`) retell facts from public player guides in the addon's own words:

- wowforeverleveling.com, WoW Forever XP Buffs
- wow-professions.com, Camping Guide

The disenchanting table in `Sale.lua` is the well-known classic one (item level
to dust, essence and shard). It matches the WoW Forever disenchanting guide on
wow-professions.com (November 2026); it has not been measured in the game.

Seven recipes outside the stored routes (`Routes.lua`, `EXTRA`) fill stretches
where every recipe of a route is green: Goblin Deviled Clams, Iron Grenade,
Mithril Gyro-Shot, Truesilver Breastplate, Imperial Plate Belt,
Frostsaber Boots and Mantle of the Timbermaw. Their spell, item and
reagent ids were read from the WoW Forever database on wowhead.com; colour
thresholds, vendors and prices from the WoW Forever profession tables on
timesaver.gg; the skill a recipe item asks for from the WoW Forever recipe
lists on warcraft.wiki.gg (November 2026). None of it was measured in the game.

`Data/Skills.lua` lists, for every recipe, the skill it is learned at, the skill
where it turns yellow, green and grey, the kind of its source (trainer,
vendor, drop, quest) and where to get it (vendors and their zones, the pattern
price, the level of the creatures a world drop comes from). The facts were read from the "All recipes" lists of the
WoW Forever profession tables on timesaver.gg (November 2026) with
`tools/fetch-recipe-skills.js`. None of it was measured in the game.

`Data/Vendors.lua` holds the recipe vendors named in those tables: their English
and Russian names and map positions come from pfQuest (see above). The positions
are the classic ones and were not checked on WoW Forever.

No code or data was taken from other profession addons. Recipe lists, reagents
and recipe colours come from the game client at run time.

## MIT License text

The permission notice below applies to pfQuest under its copyright line above.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
