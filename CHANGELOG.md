# Changelog

## 1.2.0

**Works without other addons**

- Auction prices are read by EasyCraft itself when you open the auction house. Auctionator and TSM are still used when installed; the fresher price wins. `/ec scan` reads prices on demand.
- Reagents on your other characters are counted by EasyCraft itself (bags, bank, mail). Syndicator and BagBrother are still used when installed. A setting turns alt counting off.

**Recipes**

- New "Recipes" tab: every learned recipe with its profit, the most profitable on top.
- Profit uses the best way to sell: auction house, vendor, or disenchanting (if the character is an enchanter).
- Full recipe list of each profession, read from the game: recipes you have not learned yet show their cost, profit and where to get them.
- Craft queue: click a recipe to queue it, see what to buy, craft with one button. A queue block also sits in the mini window.
- Cooldowns of all your characters in one list.
- "What to craft for yourself now": gear better than what you wear and consumables for your level.
- "Dungeons", "Raids" and "PvP" filters: what is considered the best to craft and for which classes. Starter list, not yet checked against WoW Forever.

**Routes**

- Route modes with a switch above the route: Standard, Cheaper (least gold per skill point) and Faster (fewest crafts).
- EasyCraft records the colours of your recipes at each skill and uses them in the route modes. `/ec colors` and a once-per-session hint give a code to send to the author, so thresholds improve for everyone.

**Choosing a profession**

- A separate window: what each profession makes, what it pairs with, who should take it, where the trainer is.
- The cost of the path to 300 and a preview of the whole route before you learn the profession.

**Camp**

- "XP: the most per hour": rested, Cozy Sleeping Bag, Camp Tent, food, dungeons, and the order to use them.
- The six-quest chain for the Cozy Sleeping Bag, with coordinates. Numbers come from player guides; check the buff tooltip in game.

**Other**

- One-screen introduction on first open; "?" in the window title shows it again.
- All new strings are translated into the 8 other languages (machine translation).
- Code cleanup: fallbacks for clients other than WoW Forever are removed.

## 1.1.0

- Reagents on alts are read from Syndicator (Baganator) when it is installed; BagBrother still works.
- A character with no professions sees a short guide on which profession to pick.
- Shopping tab shows the cost of the whole remaining route to 300 for each profession.
- Camp tab: "Share finds" gives a code with blueprint drop spots you discovered, to send to the author.

## 1.0.0

First public release.

- Step-by-step leveling routes 1-300 for all 12 professions.
- Mini window next to the profession window with the current step and a craft button.
- Shopping list that counts bags, bank, mail and alts, with Auctionator or TSM prices.
- Buttons at the vendor, the bank and the auction house to get what is missing.
- Gathering areas on the world map and your own finds as pins; node colour in tooltips.
- Camp tab: campfire items of your professions and where their blueprints drop.
- 10 languages. Translations other than English and Russian are machine-made.
- `/ec reset` asks for confirmation.
- Entry in the addon menu at the minimap.
