# Changelog

## 1.3.0

The addon advises and you choose. Crafting professions no longer follow route steps: you get a list of recipes that give skill right now, pick one, and the reagents, the bank and the auction house follow your pick.

**Choosing a recipe**

- A list of recipes that give skill right now: learned ones that are orange or yellow, and recipes worth learning. The advice has a star: the recipe that is easiest to do (reagents on hand, cheaper to top up, a recipe that is easy to get).
- Click a recipe to choose it. It opens right under its row, in a dark inset panel: its reagents for the number of crafts until it turns green, and one line with minus, "Create" and plus. The number is how many crafts are planned: it sets how much to take and to buy and how many the button makes (Shift: by 5).
- Reagent counts are green when you have enough for all the planned crafts, yellow when enough for at least one, red when not even for one.
- A reagent you are short of but can make yourself gets its own row, for example "Make: Fire Oil", with how many you can make now. A click makes them.
- What is missing is listed as rows with the price on the right: from a vendor, to buy at the auction house, lying in the bank, waiting in the mail.
- The choice is kept per character and profession and is cleared when the recipe stops giving skill.

**Recipes to learn**

- Every recipe of the profession is known to the addon, not only a fixed route: the skill a recipe is learned at and its colours are built in for alchemy, blacksmithing, cooking, enchanting (partly), engineering, first aid, leatherworking and tailoring.
- Each one says where to get it: the nearest trainer, the vendor or the zone where it is sold and the price, the level of the creatures a world drop comes from, the zones of a drop, or "Quest reward". A click sets the map pin or opens the zone on the map. Recipes sold only to the other faction are not offered.
- 126 more recipe vendors are known by name and position. Vendors that exist only on WoW Forever are shown as a zone.

**Bank, auction house, vendor**

- Bank and auction house work from the chosen recipe: what to take and what to buy, including the reagents of a reagent you make yourself. Nothing chosen: "Choose what to craft" with the list right there.
- Shopping tab, item tooltips and the merchant button count what the chosen recipes need.
- Item tooltips show the auction price of one item, with coin icons, for anything listed at the auction house. Over a stack, the price of the whole stack follows in brackets. A price older than a day says how old it is. A setting turns the line off.

**Main window**

- One page. The side tabs and the separate profession pages are gone: every profession is a card on the first tab. A crafting profession has the list to choose from right in its card. A gathering profession shows what to do now: what to gather and where, or the rank to learn.
- At the skill cap the addon shows what is profitable to craft for sale, and profitable recipes you do not have with where to get them.
- The "Link in chat" button is in the card of each profession.

**Also**

- Trainer window: the star marks recipes that give skill right now and the recipe you chose.
- Minimap: hovering an ore vein or a herb shows the skill it needs in brackets, in the colour it has for your skill.
- Reminders are off by default: the "share recipe data" reminder and the chat line on login about old auction prices. Both are settings now.
- Removed: the "Dungeons / Raids / PvP" filter and the "Best for" marks on the Recipes tab (the list behind them was never checked against WoW Forever), and the setting "Hide completed steps".
- Lighter: the code and the texts of the old route steps for crafting professions are removed.

## 1.2.2

- The route never leads through a green recipe. Where a recipe of the route turns green, the route switches to another recipe that is still orange or yellow.
- One leveling route instead of three modes. The "Leveling route" switch on the home page is gone: the route itself picks the cheaper recipe where there is a choice and prices are known.
- A step always lists a few recipes to level on (three on the page, two in the mini window): learned recipes that are orange or yellow now, each with its cost and how many you can make. You choose; the step counts by skill, whatever you craft.
- Nothing is counted or bought for a green step.
- Seven recipes fill the stretches where a route had only green recipes, so no route has a green stretch now. From the trainer: Goblin Deviled Clams (cooking 160-175), Iron Grenade (engineering 187-194), Mithril Gyro-Shot (engineering 255-260), Truesilver Breastplate (blacksmithing 242-250). From a quest or a vendor, with a note on where to get the recipe: Imperial Plate Belt (blacksmithing 267-270), Frostsaber Boots (leatherworking 265-270), Mantle of the Timbermaw (tailoring 297-300).
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
