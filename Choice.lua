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
  return { head = T("На чём качать"), choose = T("Выбери, что создавать"), make = T("Сделать: %s"), crafts = T("Созданий: %d"),
    pickTip = T("Щелчок выберет этот рецепт: реагенты на него покажутся здесь, в банке и на аукционе."), unpickTip = T("Щелчок снимет выбор."),
    makeTip = T("Этого реагента не хватает, но ты умеешь его делать. Щелчок создаст, сколько хватит реагентов."), countTip = T("Столько нужно, пока рецепт не позеленеет. Кнопки меняют число."),
    enough = T("хватит на %d"), part = T("реагенты: %d из %d"), none = T("нет реагентов"), learn = T("Сначала выучи этот рецепт."), learnHead = T("Можно выучить"), openTip = T("Щелчок выберет рецепт в окне профессии."), inBank = T("в банке %d - забери у банкира"), more = T("и ещё %d"), perCraft = T("~%s за создание"), createTip = T("Создаст столько, сколько выбрано (и сколько хватит реагентов).") }
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
    out[#out + 1] = { key = key, spell = id, name = name or (b and b.n) or self:SpellName(id) or "?", icon = icon or (b and b.i),
      out = b and b.out, d = d, color = ns.COLOR_BY_D[d], known = true, rc = rc, a = a, got = got, total = total, cost = self:RecipeCost(rc) }
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
function ns:Advice(key, rank)
  local list = self:KnownOptions(key, rank)
  for _, e in ipairs(self:LearnableRecipes(key, nil, rank, 8)) do
    local rs = e.s
    list[#list + 1] = { key = key, spell = rs.spell, name = rs.name or self:StepName(rs), icon = rs.tex or self:StepIcon(rs, self.Profs[key]),
      out = rs.id, d = e.d, color = e.color, known = false, rc = rs.rc, a = e.a, got = e.got, total = e.total, cost = e.cost, src = e.src, easy = e.easy == 0 }
  end
  for _, e in ipairs(list) do
    if e.known then e.group = e.a > 0 and 0 or 2
    else e.group = (e.easy and e.a > 0) and 1 or (e.easy and 3 or 4) end
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
  if e.a > 0 then return format(X.enough, e.a) end
  if e.got > 0 then return format(X.part, e.got, e.total) end
  return "|cff9d9d9d" .. X.none .. "|r"
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
-- b.shop = everything to buy at the auction house { id, buy, cost },
-- b.lack = what the bags are short of { id -> count } (the bank may have it).
function ns:PickPlan(key, rank, maxRank, pool, list)
  if not rank then rank, maxRank = self:GetSkill(key) end
  local e = self:Picked(key, rank, maxRank, list)
  if not (e and e.rc) then return nil end
  local b = self:StepBuy({ k = "craft", spell = e.spell, rc = e.rc }, e.n, pool)
  b.shop, b.lack, b.makes = {}, {}, {}
  local function count(it)
    if it.have < it.need then b.lack[it.id] = (b.lack[it.id] or 0) + (it.need - it.have) end
    if it.buy > 0 and not it.vendor and not it.make then b.shop[#b.shop + 1] = { id = it.id, buy = it.buy, cost = it.cost } end
  end
  for _, it in ipairs(b.items) do
    -- what a vendor sells is bought, not made
    local mk = it.buy > 0 and not it.vendor and it.id ~= e.out and self:MakerOf(it.id)
    if mk then
      local crafts = ceil(it.buy / mk.q)
      local sb = self:StepBuy({ k = "craft", spell = mk.spell, rc = mk.rc }, crafts, pool)
      it.make = { key = mk.key, spell = mk.spell, name = mk.name, crafts = crafts, can = min(crafts, self:CanMake({ rc = mk.rc }) or 0), b = sb }
      b.makes[#b.makes + 1] = it
      -- the purchase of the reagent itself is replaced by the purchase of what it is made of
      if it.cost then b.total = b.total - it.cost else b.noPrice = b.noPrice - 1 end
      b.total, b.noPrice, b.vendorCost = b.total + sb.total, b.noPrice + sb.noPrice, b.vendorCost + sb.vendorCost
      for _, name in ipairs(sb.vendor) do tinsert(b.vendor, name) end
      if sb.bank then b.bank = true end
      if sb.mail then b.mail = true end
      for _, sub in ipairs(sb.items) do count(sub) end
    end
    count(it)
  end
  return { e = e, n = e.n, b = b }
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
      tip = X.pickTip .. (where ~= "" and ("\n" .. where) or ""),
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
