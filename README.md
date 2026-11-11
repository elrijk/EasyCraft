# EasyCraft

Profession leveling for **WoW Forever**, one step at a time. Open the window,
do the current step, and the addon moves you to the next one when your skill
goes up. No guide in a second window, no counting materials by hand.

## What it does

- **Routes 1-300** for all 12 professions: Alchemy, Blacksmithing, Enchanting, Engineering, Leatherworking, Tailoring, Mining, Herbalism, Skinning, Cooking, First Aid, Fishing.
- **Mini window** beside the profession window: the recipe of the current step, what you have, and a Create button.
- **Route modes**: Standard, Cheaper or Faster, switched above the route.
- **Shopping to the next trainer**: counts your bags, bank, mail and alts, so you never buy twice. Prices are read at the auction house by the addon itself; no other addon needed.
- **Recipes**: every recipe of your professions, learned or not, with cost, profit (auction, vendor or disenchant) and where to get it. A craft queue, cooldowns of all characters, and "what to craft for yourself now".
- **Choosing a profession**: what each one makes, who should take it, the cost of the path to 300 and the whole route before you learn it.
- **One-click helpers**: buy missing reagents at a vendor, take the right stacks from the bank, search everything at the auction house.
- **Trainers and recipes**: the nearest trainer or recipe vendor with a map pin; stars in the trainer window on recipes your route needs.
- **Gathering on the map**: zones for your faction and level, highlighted areas where herbs and ore are dense, node colour in the tooltip.
- **Camp**: the campfire items of your professions and where their blueprints drop; the XP bonuses professions give (Camp Tent, cooked food).
- **Self-check**: if a recipe in the game differs from the route, the addon uses the game's data.

## Commands

`/ec` opens the window. `/ec commands` lists the rest.

## Optional addons

EasyCraft works on its own. These add convenience:

- **Auctionator**: search the whole shopping list at once. Its prices and TradeSkillMaster's are used too.
- **Syndicator (Baganator)** or **BagBrother (Bagnon)**: reagents on characters you have not logged into since installing EasyCraft.
- **TomTom**: arrow to trainers and vendors.

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

## Credits

Map and name data: pfQuest by Shagu (MIT). See `THIRD-PARTY.md`.

---

# EasyCraft (по-русски)

Прокачка профессий в **WoW Forever** по шагам. Открой окно, сделай текущий
шаг, и аддон сам покажет следующий, когда вырастет навык.

- **Маршруты 1-300** для всех 12 профессий.
- **Мини-окно** рядом с окном профессии: рецепт шага, что есть, кнопка «Создать».
- **Режимы маршрута**: «Обычный», «Дешевле» или «Быстрее», переключатель над маршрутом.
- **Покупки до учителя**: сумки, банк, почта и альты уже посчитаны. Цены аддон читает на аукционе сам, другие аддоны не нужны.
- **Рецепты**: все рецепты твоих профессий, выученные и нет, с ценой, выгодой (аукцион, торговец или распыление) и источником. Очередь, откаты всех персонажей, «что создать себе сейчас».
- **Выбор профессии**: что даёт каждая, кому её брать, цена пути до 300 и весь маршрут до изучения.
- **Кнопки-помощники**: докупить у торговца, забрать из банка, найти всё на аукционе.
- **Учителя и рецепты**: ближайший учитель или торговец с меткой на карте.
- **Сбор на карте**: зоны для твоей фракции и уровня, области, где жил и трав больше всего, твои находки.
- **Лагерь**: предметы твоих профессий для костра и где падают чертежи; бонусы к опыту от профессий (палатка, еда).

Команда: `/ec`. Лицензия MIT.
