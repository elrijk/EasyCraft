# EasyCraft

Profession leveling for **WoW Forever**, one step at a time. Open the window,
do the current step, and the addon moves you to the next one when your skill
goes up. No guide in a second window, no counting materials by hand.

## What it does

- **All 12 professions**: Alchemy, Blacksmithing, Enchanting, Engineering, Leatherworking, Tailoring, Cooking, First Aid (the addon advises a recipe and you choose), Mining, Herbalism, Skinning, Fishing (what to gather now and where).
- **Mini window** beside the profession window: the recipes that give skill right now, the advice marked with a star. Click one and it opens: its reagents until it turns green, what you can make yourself, and a Create button.
- **Advice, not a rail**: the addon recommends the recipe that is easiest to do now (reagents on hand, cheaper to top up, a recipe that is easy to get), learned or not, with where to learn, buy or loot it. At the skill cap it shows what is profitable to craft for sale.
- **Shopping for the chosen recipe**: counts your bags, bank, mail and alts, so you never buy twice, and plans a reagent you can make yourself as its own craft. Prices are read at the auction house by the addon itself; no other addon needed. Item tooltips show the auction price (a setting turns it off).
- **Recipes**: every recipe of your professions, learned or not, with cost, profit (auction, vendor or disenchant) and where to get it. A craft queue, cooldowns of all characters, and "what to craft for yourself now".
- **Choosing a profession**: what each one makes, who should take it, the cost of the route to 300 and the whole route before you learn it.
- **One-click helpers**: buy missing reagents at a vendor, take the right stacks from the bank, search everything at the auction house.
- **Trainers and recipes**: the nearest trainer or recipe vendor with a map pin; stars in the trainer window on recipes that give skill now and on the one you chose.
- **Gathering on the map**: zones for your faction and level, highlighted areas where herbs and ore are dense, node colour in the tooltip, and the skill a vein or herb needs right on the minimap.
- **Camp**: the campfire items of your professions and where their blueprints drop; the XP bonuses professions give (Camp Tent, cooked food).
- **Self-check**: if a recipe in the game differs from the route, the addon uses the game's data.

## Commands

`/ec` opens the window. `/ec commands` lists the rest.

## Languages

English and Russian are written by hand. German, French, Spanish, Italian,
Portuguese, Korean and Chinese are machine-translated: if a line reads wrong,
please open an issue with the correct text.

## Help improve the routes

The game does not tell addons when a recipe turns yellow or grey. EasyCraft
records the colour of your recipes each time you open a profession window.
`/ec colors` (or the "Send data" button in the settings) gives a code with
these records: paste it into an issue. The code holds recipes and skill
values only, nothing about your character.

## License

MIT, see `LICENSE`. Third-party data and sources: `THIRD-PARTY.md`.
