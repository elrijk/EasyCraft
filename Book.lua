local _, TJ = ...
local floor, max, min = math.floor, math.max, math.min
local format = string.format
local TS = C_TradeSkillUI

-------------------------------------------------------------------------------
--  Книга рецептов, выгода, очередь крафта и откаты.
--  Всё работает на одной записи рецепта (BookEntry):
--  { key, spell, name, icon, out = предмет, q = сколько выходит, rc = реагенты,
--    known, d = цвет (0-3), step = шаг маршрута, best = "drp",
--    cost = реагенты, sale = продажа, profit = выгода за одно создание,
--    can = сколько можно создать из сумок }.
--  Выученные рецепты - из окна профессии (TJ.char.book), невыученные - из
--  маршрута и списка лучшего (Data\Best.lua).
--  Порядок везде один: сверху то, что выгоднее по ценам аукциона.
-------------------------------------------------------------------------------
local function charKey()
  return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "")
end
TJ.CharKey = charKey

-- Что выходит из рецепта: предмет и сколько (из окна профессии).
local outCache = {}
local function readOutput(spell)
  local c = outCache[spell]
  if c then return c[1], c[2] end
  if not (TS and TS.GetRecipeSchematic) then return nil end
  local ok, sch = pcall(TS.GetRecipeSchematic, spell, false)
  if not ok or type(sch) ~= "table" then return nil end
  local id = sch.outputItemID
  if type(id) ~= "number" or id <= 0 then return nil end
  local q = max(1, tonumber(sch.quantityMin) or 1)
  outCache[spell] = { id, q }
  return id, q
end

-------------------------------------------------------------------------------
--  Откаты: запоминаем по персонажам в EasyCraftDB.cds[персонаж][рецепт] =
--  { e = когда будет готов (time()), n = название, i = значок, k = профессия }.
-------------------------------------------------------------------------------
function TJ:NoteCooldown(key, id, b)
  if not (TS and TS.GetRecipeCooldown and self.db) then return end
  local ok, cd = pcall(TS.GetRecipeCooldown, id)
  if not ok then return end
  local cds = self.db.cds
  if not cds then cds = {}; self.db.cds = cds end
  local me = charKey()
  local mine = cds[me]
  if type(cd) == "number" and cd >= 60 then
    if not mine then mine = {}; cds[me] = mine end
    mine[id] = { e = time() + floor(cd), n = b.n, i = b.i, k = key }
  elseif mine and mine[id] and mine[id].e > time() then
    mine[id].e = time() -- откат сняли раньше срока
  end
end

-- Все откаты всех персонажей: готовые сверху, дальше - кому меньше ждать.
function TJ:CooldownList()
  local out, now, me = {}, time(), charKey()
  for who, list in pairs(self.db.cds or {}) do
    for id, c in pairs(list) do
      out[#out + 1] = { who = who, mine = who == me, spell = id, name = c.n, icon = c.i, key = c.k,
        left = max(0, (c.e or 0) - now) }
    end
  end
  table.sort(out, function(a, b)
    if a.left ~= b.left then return a.left < b.left end
    if a.who ~= b.who then return a.who < b.who end
    return (a.name or "") < (b.name or "")
  end)
  return out
end

function TJ:ForgetCooldown(who, spell)
  local list = self.db.cds and self.db.cds[who]
  if not list then return end
  list[spell] = nil
  if not next(list) then self.db.cds[who] = nil end
end

-- «2 д 5 ч», «3 ч 20 мин», «15 мин».
function TJ:TimeLeft(sec)
  local T = TJ.T
  local m = floor(sec / 60 + 0.5)
  if m >= 1440 then return format(T("%d д %d ч"), floor(m / 1440), floor(m % 1440 / 60)) end
  if m >= 60 then return format(T("%d ч %d мин"), floor(m / 60), m % 60) end
  return format(T("%d мин"), max(1, m))
end

-------------------------------------------------------------------------------
--  Скан окна профессии: все выученные рецепты с реагентами и результатом.
--  Зовёт ScanTradeSkill (Tracking.lua) после своего скана.
-------------------------------------------------------------------------------
function TJ:ScanBook(key)
  if not (TS and TS.GetAllRecipeIDs and TS.GetRecipeInfo) then return end
  local ok, ids = pcall(TS.GetAllRecipeIDs)
  if not ok or type(ids) ~= "table" or #ids == 0 then return end
  self.char.book = self.char.book or {}
  local old, new, n = self.char.book[key] or {}, {}, 0
  for _, id in ipairs(ids) do
    local r = TS.GetRecipeInfo(id)
    if r and r.name and r.learned ~= false and r.type ~= "header" and r.type ~= "subheader" then
      local b = old[id] or {}
      b.n, b.i = r.name, r.icon
      if not b.rc then b.rc = self:RecipeReagents(id) end
      if not b.out then
        local out, q = readOutput(id)
        if not out then
          local s = self:SpellStep(key, id)
          out = s and s.id
        end
        b.out, b.q = out, q
      end
      new[id] = b
      n = n + 1
      self:NoteCooldown(key, id, b)
    end
  end
  if n > 0 then self.char.book[key] = new end
end

-------------------------------------------------------------------------------
--  Записи рецептов и выгода
-------------------------------------------------------------------------------
-- Цены записи: реагенты, продажа и выгода за одно создание (без комиссии
-- аукциона); сколько можно создать из сумок.
function TJ:PriceEntry(e)
  e.cost = self:RecipeCost(e.rc)
  local p = e.out and self:AuctionPrice(e.out)
  e.sale = p and p * (e.q or 1) or nil
  e.profit = (e.cost and e.sale) and (e.sale - e.cost) or nil
  e.can = e.rc and (self:CanMake({ rc = e.rc }) or 0) or 0
  local b = e.out and self.Best and self.Best[e.out]
  e.best = b and b.t or nil
  e.classes = b and b.c or nil -- nil при e.best - всем классам
  return e
end

local function fromBook(key, id, b, colors)
  return { key = key, spell = id, name = b.n, icon = b.i, out = b.out, q = b.q or 1, rc = b.rc, known = true,
    d = colors and colors[id] }
end

local function fromStep(self, key, s, known)
  return { key = key, spell = s.spell, name = self:StepName(s), icon = self:StepIcon(s, self.Profs[key]),
    out = s.id, q = 1, rc = s.rc, known = known, step = s }
end

-- Одна запись по рецепту (для очереди): из книги, иначе из маршрута.
function TJ:BookEntry(key, spell)
  local book = self.char.book and self.char.book[key]
  local sc = self.char.scan[key]
  local e
  if book and book[spell] then
    e = fromBook(key, spell, book[spell], sc and sc.colors)
  else
    local s = self:SpellStep(key, spell)
    if not s then return nil end
    e = fromStep(self, key, s, self:RecipeKnown(key, spell) == true)
  end
  return self:PriceEntry(e)
end

-- Лучшее ли это для режима mode ("d", "r", "p"; nil - для любого) и, если
-- mine, для класса игрока.
function TJ:IsBest(e, mode, mine)
  if not e.best then return false end
  if mode and not e.best:find(mode, 1, true) then return false end
  if mine and e.classes then
    local _, class = UnitClass("player")
    for _, c in ipairs(e.classes) do
      if c == class then return true end
    end
    return false
  end
  return true
end

-- Порядок по ценам аукциона: выгоднее - выше; без цены - в конце по названию.
local function byProfit(a, b)
  local pa, pb = a.profit, b.profit
  if pa and pb and pa ~= pb then return pa > pb end
  if (pa ~= nil) ~= (pb ~= nil) then return pa ~= nil end
  if a.order and b.order and a.order ~= b.order then return a.order < b.order end
  return (a.name or "") < (b.name or "")
end
TJ.ByProfit = byProfit

-- Все рецепты профессии. Возвращает: выученные, невыученные (оба списка -
-- по выгоде), прочитано ли окно профессии.
function TJ:BookList(key)
  local p = self.Profs[key]
  if not p then return {}, {}, false end
  local book = self.char.book and self.char.book[key]
  local sc = self.char.scan[key]
  local colors = sc and sc.colors
  local known, unknown, seen, outs = {}, {}, {}, {}
  if book then
    for id, b in pairs(book) do
      seen[id] = true
      local e = self:PriceEntry(fromBook(key, id, b, colors))
      if e.out then outs[e.out] = true end
      known[#known + 1] = e
    end
  end
  for _, s in ipairs(p.steps) do
    if s.k == "craft" and s.spell and not seen[s.spell] then
      seen[s.spell] = true
      -- окно ещё не читали: что выучено, знаем только по игре
      local k = not book and self:RecipeKnown(key, s.spell) == true
      local e = self:PriceEntry(fromStep(self, key, s, k))
      if e.out then outs[e.out] = true end
      if k then known[#known + 1] = e else unknown[#unknown + 1] = e end
    end
  end
  -- лучшее для подземелий, рейдов и PvP, чего ещё нет в списке
  for id, b in pairs(self.Best or {}) do
    if b.p == key and not outs[id] then
      unknown[#unknown + 1] = self:PriceEntry({ key = key, name = self:ItemName(id), icon = self:ItemIcon(id),
        out = id, q = 1, known = false })
    end
  end
  table.sort(known, byProfit)
  table.sort(unknown, byProfit)
  return known, unknown, book ~= nil
end

-------------------------------------------------------------------------------
--  Очередь крафта: TJ.char.queue = { { k = профессия, s = рецепт, n = штук } }
-------------------------------------------------------------------------------
local function queue(self)
  local q = self.char.queue
  if not q then q = {}; self.char.queue = q end
  return q
end

-- Очередь изменилась: обновить подсказку у окна профессии (мини-окно).
local function queueChanged()
  if TJ.Tracker and TJ.Tracker.Update then TJ:Safe(TJ.Tracker.Update, TJ.Tracker) end
end

function TJ:QueueAdd(key, spell, n)
  if not (key and spell) then return end
  local q = queue(self)
  local found
  for _, it in ipairs(q) do
    if it.k == key and it.s == spell then
      it.n = it.n + (n or 1)
      found = true
      break
    end
  end
  if not found then q[#q + 1] = { k = key, s = spell, n = n or 1 } end
  queueChanged()
end

function TJ:QueueRemove(spell)
  local q = queue(self)
  for i = #q, 1, -1 do
    if q[i].s == spell then tremove(q, i) end
  end
  queueChanged()
end

function TJ:QueueClear()
  self.char.queue = {}
  queueChanged()
end

-- Очередь записями рецептов (n - сколько создать), по выгоде.
function TJ:QueueList()
  local out = {}
  for i, it in ipairs(queue(self)) do
    local e = self:BookEntry(it.k, it.s)
    if e and self.char.profs[it.k] then
      e.n, e.order = it.n, i
      out[#out + 1] = e
    end
  end
  table.sort(out, byProfit)
  return out
end

-- Чего не хватает на всю очередь: { items = { { id, need, have, buy, cost } },
-- auction = { { id, buy } }, total (медь), noPrice, buyCount }.
-- Запас - сумки, банк, почта и альты, как в покупках.
function TJ:QueueNeeds(list)
  list = list or self:QueueList()
  local need, order = {}, {}
  for _, e in ipairs(list) do
    local rc = e.rc
    if rc then
      for i = 1, #rc - 1, 2 do
        local id = rc[i]
        if not need[id] then need[id] = 0; order[#order + 1] = id end
        need[id] = need[id] + (rc[i + 1] or 1) * e.n
      end
    end
  end
  local alts = self:AltCounts()
  local out = { items = {}, auction = {}, total = 0, noPrice = 0, buyCount = 0 }
  for _, id in ipairs(order) do
    local have = self:ItemCount(id) + (alts[id] or 0) + self:MailCount(id)
    local buy = max(0, need[id] - have)
    local it = { id = id, need = need[id], have = have, buy = buy }
    if buy > 0 then
      out.buyCount = out.buyCount + 1
      local p = self:UnitPrice(id)
      if p then
        it.cost = p * buy
        out.total = out.total + it.cost
      else
        out.noPrice = out.noPrice + 1
      end
      if not self:IsVendorItem(id) then tinsert(out.auction, { id = id, buy = buy }) end
    end
    tinsert(out.items, it)
  end
  return out
end

-- Создать запись очереди: сколько хватает реагентов, но не больше нужного.
-- Реагентов нет - открыть рецепт в окне профессии.
function TJ:QueueCraft(e)
  if e.can > 0 and e.known then
    return self:CraftOrOpen(e.key, e.spell, min(e.n, e.can))
  end
  self:OpenRecipe(e.key, e.spell)
  self:Print(TJ.T("не хватает реагентов."))
end

-- Первое в очереди (по выгоде), на что есть реагенты.
function TJ:QueueNext(list)
  for _, e in ipairs(list or self:QueueList()) do
    if e.can > 0 and e.known then return e end
  end
end

-- Создал предмет из очереди - в очереди на одну штуку меньше.
local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, _, _, _, spellID)
  local q = TJ.char and TJ.char.queue
  if not (q and spellID) then return end
  for i, it in ipairs(q) do
    if it.s == spellID then
      it.n = it.n - 1
      if it.n <= 0 then tremove(q, i) end
      queueChanged()
      -- сумки изменятся и окно перерисуется само; откат - проверить позже
      local key = it.k
      C_Timer.After(1, function()
        local b = TJ.char.book and TJ.char.book[key] and TJ.char.book[key][spellID]
        if b and TJ:IsProfOpen(key) then TJ:NoteCooldown(key, spellID, b) end
      end)
      return
    end
  end
end)
pcall(ev.RegisterUnitEvent, ev, "UNIT_SPELLCAST_SUCCEEDED", "player")
