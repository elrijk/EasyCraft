local _, ns = ...
local format, min, max, ceil = string.format, math.min, math.max, math.ceil

-------------------------------------------------------------------------------
--  The addon advises, the player chooses. For a crafting profession there is
--  a list of recipes that give skill right now: the learned ones that are
--  orange or yellow, and the ones worth learning. The first is the advice:
--  the easiest to do (reagents on hand, cheaper to top up, a recipe that is
--  easy to get). The player picks one; everything else works from that pick:
--  the reagents in the mini window, what to take at the bank, what to buy at
--  the auction house. A reagent the character can make (and is short of) is
--  planned as its own craft, with its own reagents.
--  The pick is kept per character and profession in EasyCraftCharDB.pick =
--  { [profession] = { spell =, n = crafts set by the player or nil } }.
--  Without n the count is "until the recipe turns green".
-------------------------------------------------------------------------------
local D_BY_COLOR = { orange = 0, yellow = 1, green = 2, gray = 3 }

-- Every text of this feature, translated once per call.
function ns:ChoiceText()
  local T = ns.T
  return { head = T("На чём качать"), choose = T("Выбери, что создавать"), make = T("Сделать: %s"), create = T("Создать %d"), createOf = T("Создать %d из %d"),
    pickTip = T("Щелчок выберет этот рецепт: реагенты на него покажутся здесь, в банке и на аукционе."), unpickTip = T("Щелчок снимет выбор."),
    makeTip = T("Этого реагента не хватает, но ты умеешь его делать. Щелчок создаст, сколько хватит реагентов."), countTip = T("Сколько созданий планировать: столько реагентов считается в банке и на аукционе. Сначала стоит число до позеленения рецепта. С Shift - по 5."),
    enough = T("хватит на %d"), part = T("реагенты: %d из %d"), none = T("нет реагентов"), learn = T("Сначала выучи этот рецепт."), learnHead = T("Можно выучить"), openTip = T("Щелчок выберет рецепт в окне профессии."), inBank = T("в банке %d - забери у банкира"), more = T("и ещё %d"), perCraft = T("~%s за создание"), createTip = T("Создаст столько, сколько запланировано и на сколько хватит реагентов. Серая - реагентов пока нет."), goPin = T("Щелчок поставит метку и откроет карту."), goZone = T("Щелчок откроет карту на этой зоне."), allHave = T("Всё есть"), costSale = T("Реагенты %s, продажа %s"), rankNow = T("Уже можно выучить ранг: "), sellHead = T("Выгодно создавать на продажу"), sellLearn = T("Выгодные рецепты, которых у тебя нет"), sellNone = T("По ценам аукциона сейчас ничего не выгодно."), capNote = T("Навык на пределе: ниже - что выгодно создавать на продажу."), nothing = T("Сейчас нет рецептов, которые дают навык: выучи новый ранг или рецепт."), homePick = T("Создаём: %s"), picked = T("ты выбрал этот рецепт"), givesSkill = T("сейчас даст навык"), vendorAt = T("У торговца: "), buyAt = T("Докупить на аукционе: "), bankLine = T("Часть лежит в банке: забери у банкира"), mailLine = T("Часть ждёт на почте"), noPrice = T("нет цены"),
    toolNeed = T("Нужен инструмент: %s"), noTool = T("нет инструмента"), inBankShort = T("в банке"), toolTip = T("Без этого инструмента в сумке рецепт не создать. Он не тратится."), toolMake = T("Ты умеешь его делать: щелчок создаст."),
    toolLearn = T("Рецепт инструмента ещё не выучен, ниже - где его взять. Его реагенты уже в списке покупок."), goTo = T("Перейти"), goToTip = T("Этот рецепт накладывается на вещь: щелчок откроет его в окне профессии, там выбери цель.") }
end

-- Crafting professions: the ones with recipe thresholds in Data\Skills.lua.
function ns:IsCraftProf(key)
  return self.RecipeSkill ~= nil and self.RecipeSkill[key] ~= nil
end

-- Thresholds of a recipe { learn, yellow, green, grey } or nil.
function ns:RecipeThresholds(key, spell)
  local t = self.RecipeSkill and self.RecipeSkill[key] and self.RecipeSkill[key][spell]
  if t then return t end
  local s = self:SpellStep(key, spell)
  return s and s.sk or nil
end

-- How many crafts until the recipe turns green (not past the rank cap).
-- Thresholds unknown: a short batch.
function ns:CraftsToGreen(key, spell, rank, maxRank)
  local t = self:RecipeThresholds(key, spell)
  if not t then return 5 end
  local cap = (maxRank and maxRank > 0) and maxRank or 300
  return max(1, min(t[3], cap) - rank)
end

-- Reagents in the bags for a recipe: crafts possible, reagents present, reagents in all.
local function onHand(self, rc)
  local got, total = 0, 0
  for i = 1, rc and #rc - 1 or 0, 2 do
    total = total + 1
    if self:BagCount(rc[i]) >= max(1, rc[i + 1] or 1) then got = got + 1 end
  end
  return rc and self:CanMake({ rc = rc }) or 0, got, total
end

-------------------------------------------------------------------------------
--  Tools. Some recipes need a tool in the bags that is not used up (a runed
--  rod for enchanting, a hammer, a spanner). The game names it in the
--  profession window ("Requires: ..."); the addon reads that line for every
--  recipe while the window is open and keeps it in EasyCraftDB.recipes
--  [profession][recipe].tl (the name, or false: no tool). The name is the
--  name of the tool type, which can differ from the item's own name, so the
--  item is found by the words they share.
-------------------------------------------------------------------------------
local TS = C_TradeSkillUI
local GREEN, RED, YELLOW, GREY = "|cff33dd33", "|cffff5555", "|cffffd100", "|cff9d9d9d"
local MAP_ICON = "Interface\\Icons\\INV_Misc_Map_01"
local PHILOSOPHERS_STONE = 9149 -- alchemy transmutes

-- Every tool item of every profession.
local toolIds
local function allTools(self)
  if toolIds then return toolIds end
  toolIds = { PHILOSOPHERS_STONE }
  local seen = { [PHILOSOPHERS_STONE] = true }
  for _, p in pairs(self.Profs) do
    for _, t in ipairs(p.tools or {}) do
      if not seen[t[1]] then
        seen[t[1]] = true
        toolIds[#toolIds + 1] = t[1]
      end
    end
  end
  table.sort(toolIds)
  return toolIds
end

local function words(s)
  local out = {}
  for w in ns.Lower(s):gmatch("[^%s%p]+") do out[w] = true end
  return out
end

-- The tool item by the name the game gives it, or nil. The same name first
-- (in the client's language, Russian or English); otherwise the item that
-- shares the most words with it, at least two, and only one such item.
local toolByName = {}
function ns:ToolItem(name)
  if type(name) ~= "string" or name == "" then return nil end
  local known = toolByName[name]
  if known ~= nil then return known or nil end
  local want = words(name)
  local best, bestScore, tie, unsure = nil, 0, false, false
  local GetName = C_Item and C_Item.GetItemNameByID
  for _, id in ipairs(allTools(self)) do
    local client = GetName and GetName(id)
    if not client then unsure = true; self:WantItem(id) end
    local score = 0
    for _, n in ipairs({ client or "", self.ItemNames[id] or "", self.ItemNamesEN and self.ItemNamesEN[id] or "" }) do
      if n == name then
        toolByName[name] = id
        return id
      end
      local s = 0
      for w in pairs(words(n)) do if want[w] then s = s + 1 end end
      score = max(score, s)
    end
    if score > bestScore then best, bestScore, tie = id, score, false
    elseif score == bestScore and score > 0 then tie = true end
  end
  local id = (bestScore >= 2 and not tie) and best or nil
  -- a name not loaded yet may still match: ask again later
  if id or not unsure then toolByName[name] = id or false end
  return id
end

-- The tool a recipe needs, as the open profession window says: its name and
-- whether the character has it; false - no tool; nil - the game does not tell.
function ns:ReadRecipeTool(spell)
  if not (TS and TS.GetRecipeRequirements and spell) then return nil end
  local ok, list = pcall(TS.GetRecipeRequirements, spell)
  if not ok or type(list) ~= "table" then return nil end
  local totem = Enum and Enum.RecipeRequirementType and Enum.RecipeRequirementType.Totem or 1
  for _, r in ipairs(list) do
    -- the other kinds are places (an anvil, a forge), not things to carry
    if type(r) == "table" and type(r.name) == "string" and r.name ~= ""
      and (r.type == totem or self:ToolItem(r.name)) then
      return r.name, r.met
    end
  end
  return false
end

local function recipeBase(self, key, spell)
  local t = self.db and self.db.recipes and self.db.recipes[key]
  return t and t[spell]
end

-- The tool of a recipe: { name, id = item or nil, have } or nil when the
-- recipe needs none (or the window has not been opened since). With the
-- window open the game says whether the character has it (a better rod
-- may count too); with it closed - the item in the bags, or what the window
-- said last time unless the item lies in the bank.
function ns:RecipeTool(key, spell)
  local name, met
  if self:IsProfOpen(key) then name, met = self:ReadRecipeTool(spell) end
  local r = recipeBase(self, key, spell)
  if name ~= nil then
    if r then r.tl = name end
  else
    name = r and r.tl
  end
  if not name then return nil end
  local id = self:ToolItem(name)
  local seen = self.char and self.char.toolMet
  if met ~= nil and self.char then
    seen = seen or {}
    self.char.toolMet = seen
    seen[name] = met and true or nil
  end
  local have
  if met ~= nil then have = met and true or false
  elseif id and self:InBags(id) > 0 then have = true
  else have = (seen and seen[name] and not (id and self:ItemCount(id) > 0)) and true or false end
  return { name = name, id = id, have = have }
end

-- A recipe of the character's professions that makes the tool but is not
-- learned yet: { key, spell, name, rc, q, learn = where to get it } or nil.
function ns:ToolMaker(id)
  for _, key in ipairs(self:LearnedList()) do
    local p = self.Profs[key]
    for _, s in ipairs(p and p.steps or {}) do
      if s.k == "craft" and s.id == id and s.spell and s.rc then
        return { key = key, spell = s.spell, name = self:StepName(s), rc = s.rc, q = 1,
          learn = self:RecipeWhere(key, s.spell) or { kind = "other" } }
      end
    end
    for spell, r in pairs(self.db and self.db.recipes and self.db.recipes[key] or {}) do
      if r.out == id and r.rc then
        return { key = key, spell = spell, name = r.n or self:ItemName(id), rc = r.rc, q = max(1, r.q or 1),
          learn = self:RecipeWhere(key, spell) or { kind = "other" } }
      end
    end
  end
  return nil
end

-- A recipe that is put on an item (an enchant): the target is chosen in the
-- profession window, so the addon opens the recipe there instead of crafting.
function ns:RecipeHasTarget(key, spell)
  local st = self:RecipeState(key, spell)
  if st and not st.unknown then return st.enchant and true or false end
  local r = recipeBase(self, key, spell)
  return (r and r.tg) and true or false
end

-- Learned recipes that are orange or yellow now. Colours come from the open
-- profession window; with the window closed, from the stored thresholds.
function ns:KnownOptions(key, rank)
  local out, seen = {}, {}
  local book = self.char and self.char.book and self.char.book[key] or {}
  local function add(id, name, icon, d, rc)
    if seen[id] then return end
    seen[id] = true
    local b = book[id]
    local step = self:SpellStep(key, id)
    rc = (b and b.rc) or rc or (step and step.rc)
    local a, got, total = onHand(self, rc)
    local tool = self:RecipeTool(key, id)
    out[#out + 1] = { key = key, spell = id, name = name or (b and b.n) or self:SpellName(id) or "?", icon = icon or (b and b.i),
      out = b and b.out, d = d, color = ns.COLOR_BY_D[d], known = true, rc = rc, a = a, got = got, total = total, cost = self:RecipeCost(rc),
      tool = (tool and not tool.have) and tool or nil }
  end
  local sc = self:FreshScan(key, rank)
  if sc then
    for _, r in ipairs(sc.list) do
      if r.id and r.d and r.d <= 1 then add(r.id, r.n, r.i, r.d, r.rc) end
    end
  else
    local learned = self.char and self.char.scan[key] and self.char.scan[key].colors
    for id in pairs(learned or {}) do
      local t = self:RecipeThresholds(key, id)
      local d = t and D_BY_COLOR[self:RecipeColor({ sk = t }, rank)]
      if d and d <= 1 then add(id, nil, nil, d) end
    end
  end
  return out
end

-- The whole list, the advice first. Order: a learned recipe the bags are
-- enough for; a trainer or vendor recipe the bags are enough for; other
-- learned recipes; recipes that are easy to get; the rest. Inside a group:
-- the larger share of reagents on hand, orange before yellow, the cheaper craft.
-- A recipe whose tool the bags do not have is not "enough" whatever the reagents.
function ns:Advice(key, rank)
  local list = self:KnownOptions(key, rank)
  for _, e in ipairs(self:LearnableRecipes(key, nil, rank, 8)) do
    local rs = e.s
    local tool = self:RecipeTool(key, rs.spell)
    list[#list + 1] = { key = key, spell = rs.spell, name = rs.name or self:StepName(rs), icon = rs.tex or self:StepIcon(rs, self.Profs[key]),
      out = rs.id, d = e.d, color = e.color, known = false, rc = rs.rc, a = e.a, got = e.got, total = e.total, cost = e.cost, src = e.src, easy = e.easy == 0,
      tool = (tool and not tool.have) and tool or nil }
  end
  for _, e in ipairs(list) do
    local ready = e.a > 0 and not e.tool
    if e.known then e.group = ready and 0 or 2
    else e.group = (e.easy and ready) and 1 or (e.easy and 3 or 4) end
    e.share = e.total > 0 and e.got / e.total or 0
  end
  table.sort(list, function(x, y)
    if x.group ~= y.group then return x.group < y.group end
    if x.share ~= y.share then return x.share > y.share end
    if x.d ~= y.d then return x.d < y.d end
    if x.cost and y.cost and x.cost ~= y.cost then return x.cost < y.cost end
    if (x.cost ~= nil) ~= (y.cost ~= nil) then return x.cost ~= nil end
    return x.spell < y.spell
  end)
  if list[1] then list[1].advice = true end
  return list
end

-- Text on the right of a row: what the bags are enough for.
function ns:AdviceRight(e, X)
  if e.tool then return RED .. X.noTool .. "|r" end
  if e.a > 0 then return format(X.enough, e.a) end
  if e.got > 0 then return format(X.part, e.got, e.total) end
  return GREY .. X.none .. "|r"
end

-- The line about a missing tool for the tooltip of a recipe row, or "".
function ns:ToolLine(e, X)
  return e.tool and ("\n" .. RED .. format(X.toolNeed, e.tool.name) .. "|r") or ""
end

-- Where to get a recipe that is not learned: "Name, zone, price" or the text of the source.
function ns:AdviceWhere(e)
  local src = e.src
  if not src then return "" end
  local where = src.npc and (self:NpcName(src.npc) .. ", " .. self:NpcZone(src.npc)) or (src.info and ns.T(src.info)) or ""
  local price = src.kind == "vendor" and (src.copper and self.W.Money(src.copper) or src.price) or nil
  if price and where ~= "" then where = where .. ", " .. price end
  return where
end

-- Where to go for a recipe that is not learned, as rows { text, right, tip,
-- go }. Trainers or vendors the addon knows: up to three, the nearest first,
-- a click sets the map pin. Only zones known (a vendor without a name, a
-- drop): a row per zone, a click opens the map on it. A world drop or a
-- quest: one line of text, nothing to click.
function ns:AdvicePlaces(e, X)
  local src, out = e.src, {}
  if not src then return out end
  local price = src.kind == "vendor" and (src.copper and self.W.Money(src.copper) or src.price) or nil
  for i, npc in ipairs(src.all or (src.npc and { src.npc }) or {}) do
    if i > 3 then break end
    out[#out + 1] = { text = self:NpcName(npc) .. ", " .. self:NpcZone(npc), right = price, tip = X.goPin,
      go = function() ns:Waypoint(npc, true) end }
  end
  if #out == 0 then
    for i, area in ipairs(src.areas or {}) do
      if i > 3 then break end
      out[#out + 1] = { text = (src.label or "") .. self:ZoneName(area), right = price, tip = X.goZone,
        go = function() ns.Content:ShowOnMap(area) end }
    end
  end
  if #out == 0 and src.info then out[1] = { text = ns.T(src.info) } end
  return out
end

local function picks(self)
  if not self.char then return {} end
  self.char.pick = self.char.pick or {}
  return self.char.pick
end

-- Choose a recipe (nil clears the choice).
function ns:Pick(key, spell)
  local t = picks(self)
  if spell and t[key] and t[key].spell == spell then return end
  t[key] = spell and { spell = spell } or nil
  self.needCache = nil
  self:RefreshAll()
end

-- The chosen recipe as an entry of the list, with n = crafts to plan; nil
-- when nothing is chosen. A choice that gives no skill any more (turned
-- green, or is not in the list for another reason) is cleared.
function ns:Picked(key, rank, maxRank, list)
  local p = picks(self)[key]
  if not p then return nil end
  if not rank then rank, maxRank = self:GetSkill(key) end
  for _, e in ipairs(list or self:Advice(key, rank)) do
    if e.spell == p.spell then
      e.n = p.n or self:CraftsToGreen(key, e.spell, rank, maxRank)
      return e
    end
  end
  picks(self)[key] = nil
  return nil
end

-- Change the number of crafts of the chosen recipe by delta (never below 1).
function ns:PickAdd(key, delta)
  local p = picks(self)[key]
  if not p then return end
  local rank, maxRank = self:GetSkill(key)
  p.n = max(1, (p.n or self:CraftsToGreen(key, p.spell, rank, maxRank)) + delta)
  self.needCache = nil
  self:RefreshAll()
end

-- A learned recipe of this character (any profession) that makes the item:
-- { key, spell, name, rc, q } or nil.
function ns:MakerOf(id)
  for key, book in pairs(self.char and self.char.book or {}) do
    for spell, b in pairs(book) do
      if b.out == id and b.rc and #b.rc >= 2 then
        return { key = key, spell = spell, name = b.n or self:ItemName(id), rc = b.rc, q = max(1, b.q or 1) }
      end
    end
  end
  return nil
end

-- What the chosen recipe takes: { e = entry, n = crafts, b = reagents as
-- ns:StepBuy gives them }. A reagent that has to be bought and that the
-- character can make gets it.make = { key, spell, name, crafts, can, b } and
-- is not counted as a purchase: its own reagents are (one level deep).
-- A tool the bags do not have is b.tool = { name, id, it }: it.make plans
-- its craft the same way (it.make.learn = where to get its recipe when it is
-- not learned yet), or it is bought, or taken from the bank.
-- b.shop = everything to buy at the auction house { id, buy, cost },
-- b.lack = what the bags are short of { id -> count } (the bank may have it).
function ns:PickPlan(key, rank, maxRank, pool, list)
  if not rank then rank, maxRank = self:GetSkill(key) end
  local e = self:Picked(key, rank, maxRank, list)
  if not (e and e.rc) then return nil end
  -- the recipe, what it makes for itself and the tool share the stock
  pool = pool or {}
  local b = self:StepBuy({ k = "craft", spell = e.spell, rc = e.rc }, e.n, pool)
  b.shop, b.lack, b.makes = {}, {}, {}
  local function count(it)
    if it.have < it.need then b.lack[it.id] = (b.lack[it.id] or 0) + (it.need - it.have) end
    if it.buy > 0 and not it.vendor and not it.make then b.shop[#b.shop + 1] = { id = it.id, buy = it.buy, cost = it.cost } end
  end
  local function merge(sb)
    b.total, b.noPrice, b.vendorCost = b.total + sb.total, b.noPrice + sb.noPrice, b.vendorCost + sb.vendorCost
    for _, name in ipairs(sb.vendor) do
      if not tContains(b.vendor, name) then tinsert(b.vendor, name) end
    end
    if sb.vendorApprox then b.vendorApprox = true end
    if sb.bank then b.bank = true end
    if sb.mail then b.mail = true end
  end
  -- the item is made, not bought: its purchase is replaced by the purchase of what it is made of
  local function planCraft(it, mk)
    local crafts = ceil(it.buy / mk.q)
    local sb = self:StepBuy({ k = "craft", spell = mk.spell, rc = mk.rc }, crafts, pool)
    it.make = { key = mk.key, spell = mk.spell, name = mk.name, crafts = crafts, learn = mk.learn,
      can = mk.learn and 0 or min(crafts, self:CanMake({ rc = mk.rc }) or 0), b = sb }
    if it.cost then b.total = b.total - it.cost else b.noPrice = b.noPrice - 1 end
    merge(sb)
    for _, sub in ipairs(sb.items) do count(sub) end
  end
  for _, it in ipairs(b.items) do
    -- what a vendor sells is bought, not made
    local mk = it.buy > 0 and not it.vendor and it.id ~= e.out and self:MakerOf(it.id)
    if mk then
      planCraft(it, mk)
      b.makes[#b.makes + 1] = it
    end
    count(it)
  end
  -- the tool: one, and it stays after crafting
  local tool = self:RecipeTool(key, e.spell)
  if tool and not tool.have then
    b.allHave = false
    if tool.id then
      local tb = self:StepBuy({ k = "craft", rc = { tool.id, 1 } }, 1, pool)
      local it = tb.items[1]
      merge(tb)
      local mk = it.buy > 0 and not it.vendor and (self:MakerOf(it.id) or self:ToolMaker(it.id))
      if mk then planCraft(it, mk) end
      count(it)
      tool.it = it
    end
    b.tool = tool
  end
  return { e = e, n = e.n, b = b }
end

-- Every item a plan counts: the reagents, what a reagent the character makes
-- is made of, the missing tool and what it is made of.
function ns:PlanItems(b)
  local out = {}
  local function add(it)
    out[#out + 1] = it
    for _, sub in ipairs(it.make and it.make.b.items or {}) do out[#out + 1] = sub end
  end
  for _, it in ipairs(b.items) do add(it) end
  if b.tool and b.tool.it then add(b.tool.it) end
  return out
end

-- Rows about the missing tool of a plan, for every window that shows the
-- picked recipe: { id or tex, text, right, tip, hot, go }. The first row is
-- the tool with what to do about it; when its recipe is not learned yet,
-- the places to get that recipe follow.
function ns:ToolRows(plan, X)
  local tool = plan and plan.b.tool
  if not tool then return {} end
  local it = tool.it
  local row = { id = tool.id, tex = (not tool.id) and "Interface\\Icons\\INV_Misc_Wrench_01" or nil,
    text = format(X.toolNeed, tool.id and self:ItemName(tool.id) or tool.name), tip = X.toolTip }
  local out = { row }
  local mk = it and it.make
  if mk and not mk.learn then
    row.right = (mk.can > 0 and GREEN or RED) .. mk.can .. "/" .. mk.crafts .. "|r"
    row.hot = mk.can > 0
    row.tip = X.toolTip .. "\n" .. X.toolMake
    row.go = function()
      if mk.can > 0 then ns:CraftOrOpen(mk.key, mk.spell, mk.crafts) else ns:OpenRecipe(mk.key, mk.spell) end
    end
  elseif mk then
    row.tip = X.toolTip .. "\n" .. X.toolLearn
    for k, pl in ipairs(self:AdvicePlaces({ src = mk.learn }, X)) do
      out[#out + 1] = { tex = MAP_ICON, text = pl.text, right = pl.right, tip = pl.tip, go = pl.go, hot = k == 1 and pl.go ~= nil }
    end
  elseif it and it.have < it.need and it.all > it.have then
    row.right = YELLOW .. X.inBankShort .. "|r"
    row.tip = X.toolTip .. "\n" .. X.bankLine
  elseif it and it.vendor then
    local money = it.cost and ((it.approx and "~" or "") .. self.W.Money(it.cost)) or nil
    row.right = money
    row.tip = X.toolTip .. "\n" .. X.vendorAt .. (money or "")
  elseif it and it.buy > 0 then
    row.right = it.cost and self.W.Money(it.cost) or (GREY .. X.noPrice .. "|r")
    row.tip = X.toolTip .. "\n" .. X.buyAt .. (it.cost and self.W.Money(it.cost) or X.noPrice)
  elseif it and it.mail > 0 then
    row.tip = X.toolTip .. "\n" .. X.mailLine
  end
  return out
end

-- Chosen recipes of every crafting profession the character has:
-- { { key, plan }, ... } and the professions with nothing chosen { key, ... }.
-- One pool of stock for all of them: what one plan took, the next does not get.
function ns:PickPlans()
  local plans, empty, pool = {}, {}, {}
  for _, key in ipairs(self:LearnedList()) do
    if self:IsCraftProf(key) then
      local rank, maxRank = self:GetSkill(key)
      local plan = self:PickPlan(key, rank, maxRank, pool)
      if plan then plans[#plans + 1] = { key = key, plan = plan } else empty[#empty + 1] = key end
    end
  end
  return plans, empty
end

-- Hint panels (bank, auction house). Nothing chosen for the profession: a
-- heading "choose what to craft" and the top of the list; a click chooses.
-- Returns the new y and how many rows were added.
function ns:ChoiceRows(f, key, y, refresh)
  local X = self:ChoiceText()
  local list = self:Advice(key, (self:GetSkill(key)))
  if #list == 0 then return y, 0 end
  y = f:Head(self:N(self.Profs[key]) .. ": " .. X.choose, y)
  local n = 0
  for _, e in ipairs(list) do
    if n >= 4 then break end
    n = n + 1
    local where = e.known and "" or self:AdviceWhere(e)
    y = f:Row({ tex = e.icon, text = self:Hex(e.color) .. e.name .. "|r", right = self:AdviceRight(e, X),
      tip = X.pickTip .. (where ~= "" and ("\n" .. where) or "") .. self:ToolLine(e, X),
      onClick = function() ns:Pick(key, e.spell) refresh() end }, y)
  end
  return y, n
end

-- The chosen recipe as a row of a hint panel: its name and the number of
-- crafts; a click clears the choice.
function ns:PickedRow(f, key, plan, y, refresh)
  local e = plan.e
  return f:Row({ tex = e.icon, text = self:Hex(e.color) .. e.name .. "|r", right = "|cffffffffx" .. plan.n .. "|r",
    tip = self:ChoiceText().unpickTip, onClick = function() ns:Pick(key, nil) refresh() end }, y)
end

-- A hint panel (merchant, auction house): a line that the chosen recipe
-- needs a tool first, in the warning ink. Returns the new y.
function ns:ToolHead(f, plan, y)
  local tool = plan and plan.b.tool
  if not tool then return y end
  local name = tool.id and self:ItemName(tool.id) or tool.name
  return f:Head("|cffa03000" .. format(self:ChoiceText().toolNeed, name) .. "|r", y)
end
