# Changelog

## 1.2.2

- Routes never lead through a green recipe, in any mode. Where a recipe of the route turns green, the route switches to another recipe of the same route that is still orange or yellow. Where the route has nothing else, the step is marked: the window says the recipe is green and offers a learned recipe that gives skill now instead of a craft button.
- Nothing is counted or bought for a green step.
- Three trainer recipes fill stretches where a route had only green recipes: Goblin Deviled Clams (cooking 160-175), Iron Grenade (engineering 187-194) and Mithril Gyro-Shot (engineering 255-260).
- Merchant hint: a panel beside the merchant window, like the ones at the bank and the auction house. A row per item with its own "Buy" button, the total, and "Buy all".
- Trainers and recipe vendors: all of them are listed, the nearest first, instead of only the nearest one.

## 1.2.1

- Fully standalone: EasyCraft no longer reads anything from other addons. Reagents on your other characters come from its own records (a character is counted after it has logged in once with EasyCraft), and trainers get the game's own map pin.
- Buttons widen to fit their label in every language.
- Auction hint: every row has a "Find" button that searches the auction house for the item; the panel is wider.
- Clearer names: the "Leveling route" switch and the "XP bonuses from professions" card.
- The "auction prices read" chat line counts items, not auction rows.
- Fixed the Home tab tooltip and the `/ec help` description, which named things that no longer exist.
- Lighter: about 650 unused translation strings and code for windows this client does not have are removed.

## 1.2.0

**Works on its own**

- Auction prices are read by EasyCraft itself when you open the auction house. No other addon is needed. The addon reminds you to visit the auction house when it has no prices or they are older than 3 days. `/ec scan` reads prices on demand.
- Reagents on your other characters are counted by EasyCraft itself (bags, bank, mail). A setting turns alt counting off.

**Recipes**

- New "Recipes" tab: every recipe of your professions, learned or not, with cost, profit and where to get it. The most profitable on top.
- Profit uses the best way to sell: auction house, vendor, or disenchanting (if the character is an enchanter).
- Craft queue: click a recipe to queue it, see what to buy, craft with one button. A queue block also sits in the mini window.
- Cooldowns of all your characters in one list.
- "What to craft for yourself now": gear better than what you wear and consumables for your level.
- "Dungeons", "Raids" and "PvP" filter: what is considered the best to craft and for which classes. Starter list, not yet checked against WoW Forever.

**Leveling route**

- A "Leveling route" switch on the home page: Standard, Cheaper (least gold per skill point) or Faster (fewest crafts). One choice for all professions.
- EasyCraft records the colours of your recipes at each skill and uses them for the routes. `/ec colors` or a once-per-session hint gives a link to a pre-filled GitHub issue, so thresholds improve for everyone.

**Choosing a profession**

- A separate window: what each profession makes, what it pairs with, who should take it, where the trainer is.
- The cost of the route to 300 and a preview of the whole route before you learn the profession. `/ec choose` opens it.

**Camp**

- "XP: the most per hour": the XP bonuses professions give - the Camp Tent (leatherworking) and cooked food. Numbers come from player guides; check the buff tooltip in game.

**Interface**

- One-screen introduction on first open; "?" in the window title shows it again.
- Settings page regrouped into sections: General, Hints, Map and auction house.
- Step card: one "Create all" button. Hint panels at the bank and auction house scroll when the list is long.
- Removed: the "Map" tab and your own finds on the world map (gathering areas stay), Russian chat command aliases.
- All new strings are translated into the 8 other languages (machine translation).
- Code cleanup: fallbacks for clients other than WoW Forever are removed.

## 1.1.0

- A character with no professions sees a short guide on which profession to pick.
- Shopping tab shows the cost of the whole remaining route to 300 for each profession.
- Camp tab: "Share finds" gives a code with blueprint drop spots you discovered, to send to the author.

## 1.0.0

First public release.

- Step-by-step leveling routes 1-300 for all 12 professions.
- Mini window next to the profession window with the current step and a craft button.
- Shopping list that counts bags, bank, mail and alts, with auction prices.
- Buttons at the vendor, the bank and the auction house to get what is missing.
- Gathering areas on the world map and your own finds as pins; node colour in tooltips.
- Camp tab: campfire items of your professions and where their blueprints drop.
- 10 languages. Translations other than English and Russian are machine-made.
- `/ec reset` asks for confirmation.
- Entry in the addon menu at the minimap.
