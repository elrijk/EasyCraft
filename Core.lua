local ADDON, ns = ...
_G.EasyCraft = ns
ns.version = "1.2.0"
-- значок аддона: список модификаций, портрет окна, кнопка у миникарты
ns.ICON = "Interface\\AddOns\\" .. ADDON .. "\\Media\\Icon"

---------------------------------------------------------------------------
-- Мелкие помощники
---------------------------------------------------------------------------
local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min
local format = string.format

ns.PREFIX = "|cff33ff99Easy|r|cffffd100Craft:|r "
function ns:Print(msg) DEFAULT_CHAT_FRAME:AddMessage(ns.PREFIX .. tostring(msg)) end

local errorsShown = {}
function ns:Safe(fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok and not errorsShown[err] then
    errorsShown[err] = true
    ns:Print(ns.T("|cffff5555ошибка:|r ") .. tostring(err))
  end
  return ok, err
end

function ns.Icon(path)
  if not path then return "Interface\\Icons\\INV_Misc_QuestionMark" end
  if type(path) == "number" then return path end
  if path:find("\\", 1, true) then return path end
  return "Interface\\Icons\\" .. path
end

-- UTF-8 aware lower-case for Russian text (string.lower is byte based)
function ns.Lower(s)
  s = string.lower(s or "")
  s = s:gsub("\208([\144-\159])", function(b) return "\208" .. string.char(b:byte() + 32) end)
  s = s:gsub("\208([\160-\175])", function(b) return "\209" .. string.char(b:byte() - 32) end)
  s = s:gsub("\208\129", "\209\145")
  return s
end

local GetItemInfoFn = C_Item.GetItemInfo
local GetItemIconFn = C_Item.GetItemIconByID
local GetItemCountFn = C_Item.GetItemCount

-- Предметы, сведения о которых аддон сам запросил у сервера (игра их ещё
-- не знала): перерисовываемся только когда пришли они, а не любой предмет
-- любого аддона (поиск на аукционе, сумки).
ns.wantItem = {}
function ns:WantItem(id) if type(id) == "number" then self.wantItem[id] = true end end

function ns:ItemName(id)
  if type(id) ~= "number" then return ns.ItemNames[id] or tostring(id) end
  -- Язык аддона не тот, что у клиента (английский при русском клиенте):
  -- английское название из своей базы. Иначе - из игры.
  if not ns.IsRU and not ns.UseClient and ns.ItemNamesEN and ns.ItemNamesEN[id] then return ns.ItemNamesEN[id] end
  local name = GetItemInfoFn and GetItemInfoFn(id)
  if name then return name end
  self.wantItem[id] = true
  if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
  return ns.ItemNames[id] or (ns.T("Предмет ") .. id)
end

function ns:ItemNameIfCached(id)
  if type(id) ~= "number" then return nil end
  if not ns.IsRU and not ns.UseClient then return ns.ItemNamesEN and ns.ItemNamesEN[id] or nil end
  if not GetItemInfoFn then return nil end
  local name = GetItemInfoFn(id)
  if not name then self.wantItem[id] = true end
  return name
end

function ns:ItemIcon(id)
  if type(id) ~= "number" then return ns.Icon("INV_Enchant_DustStrange") end
  local icon = GetItemIconFn and GetItemIconFn(id)
  return icon or ns.Icon(nil)
end

function ns:ItemCount(id)
  if type(id) ~= "number" or not GetItemCountFn then return 0 end
  local ok, n = pcall(GetItemCountFn, id, true, false, true, true) -- сумки, банк, банк реагентов, общий банк
  return ok and n or 0
end

-- То, из чего можно создавать прямо сейчас: сумки и банк реагентов,
-- без обычного банка.
function ns:BagCount(id)
  if type(id) ~= "number" or not GetItemCountFn then return 0 end
  local ok, n = pcall(GetItemCountFn, id, false, false, true)
  return ok and n or 0
end

-- Только сумки: то, что можно применить прямо сейчас.
function ns:InBags(id)
  if type(id) ~= "number" or not GetItemCountFn then return 0 end
  local ok, n = pcall(GetItemCountFn, id)
  return ok and n or 0
end

function ns:ItemQualityColor(id)
  if type(id) ~= "number" or not GetItemInfoFn then return 1, 1, 1 end
  local name, _, q = GetItemInfoFn(id)
  if not name then self.wantItem[id] = true end
  if q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q] then
    local c = ITEM_QUALITY_COLORS[q]
    return c.r, c.g, c.b
  end
  return 1, 1, 1
end

---------------------------------------------------------------------------
-- Таблицы для быстрого поиска
---------------------------------------------------------------------------
-- переводятся при обращении: язык из настроек известен только на ADDON_LOADED
local RANK_RU = { [75] = "Ученик", [150] = "Подмастерье", [225] = "Умелец", [300] = "Искусник" }
ns.RankNames = setmetatable({}, { __index = function(_, k) return RANK_RU[k] and ns.T(RANK_RU[k]) end })
ns.RankOrder = { 75, 150, 225, 300 }
ns.SkillLineToKey, ns.NameToKey = {}, {}
ns.ItemCategory, ns.NodeByItem, ns.UiToArea = {}, {}, {}

function ns:BuildLookups()
  for _, key in ipairs(self.ProfOrder) do
    local p = self.Profs[key]
    self.SkillLineToKey[p.skill] = key
    self.NameToKey[p.ru] = key
    self.NameToKey[p.en] = key
    self.NameToKey[self.Lower(p.ru)] = key
  end
  -- другие написания, которые встречались в русском клиенте
  self.NameToKey["Горное дело"] = "mining"
  -- окно плавки в старом виде называется по-своему - это тоже горное дело
  for _, n in ipairs({ "Выплавка металлов", "Выплавка", "Smelting" }) do self.NameToKey[n] = "mining"; self.NameToKey[self.Lower(n)] = "mining" end
  self.NameToKey["Снятие шкур"] = "skinning"
  self.NameToKey["Рыбная ловля"] = "fishing"
  self.NameToKey["Наложение чар"] = "enchanting"

  for _, key in ipairs(self.NodeOrder) do
    local n = self.Nodes[key]
    for _, item in ipairs(n.yields) do
      self.ItemCategory[item] = self.ItemCategory[item] or n.prof
    end
    if not self.NodeByItem[n.item] then self.NodeByItem[n.item] = key end
  end
  for id, src in pairs(self.MatSources) do
    if src.src == "skin" then self.ItemCategory[id] = "skinning" end
  end
  self.ItemCategory[2934] = "skinning"
  for _, id in ipairs({783, 4232, 4235, 8169, 8171, 2318, 2319, 4234, 4304, 8170}) do
    self.ItemCategory[id] = "skinning"
  end
end

-- Зоны из данных (номера AreaTable) -> uiMapID клиента, с проверкой по названию.
function ns:ResolveMaps()
  wipe(self.UiToArea)
  local byName
  local function search(name)
    if not byName then
      byName = {}
      if C_Map and C_Map.GetMapChildrenInfo then
        for _, root in ipairs({ 947, 1414, 1415 }) do
          local ok, kids = pcall(C_Map.GetMapChildrenInfo, root, nil, true)
          if ok and kids then
            for _, info in ipairs(kids) do byName[info.name] = byName[info.name] or info.mapID end
          end
        end
      end
    end
    return byName[name]
  end
  for area, z in pairs(self.Zones) do
    local ui = z.ui
    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(ui)
    if not (info and (info.name == z.ru or info.name == z.en)) then
      ui = search(z.ru) or search(z.en) or ui
    end
    z.uiMap = ui
    self.UiToArea[ui] = area
  end
end

function ns:ZoneName(area)
  local z = self.Zones[area]
  if not z then return "?" end
  if not z.name and C_Map and C_Map.GetMapInfo then
    local info = C_Map.GetMapInfo(z.uiMap or z.ui)
    if info and info.name and info.name ~= "" then z.name = info.name end
  end
  if not ns.IsRU then return (ns.UseClient and ns.lang ~= "enUS" and z.name) or z.en or z.ru end
  return z.name or z.ru
end

function ns:ZoneColor(area)
  local z = self.Zones[area]
  local f = z and z.f or "C"
  if f == "A" then return "|cff4f9cff" elseif f == "H" then return "|cffff5555" end
  return "|cffffd36b"
end

function ns:PlayerFaction()
  local f = UnitFactionGroup and UnitFactionGroup("player")
  return f == "Alliance" and "A" or (f == "Horde" and "H" or nil)
end

-- Ничьи зоны, где лагерь и полёты есть только у одной стороны: другой
-- фракции туда далеко и опасно - такие зоны ниже в списке.
ns.ZONE_SIDE = { [406] = "H", [400] = "H", [8] = "H" }

-- «для Орды» / «для Альянса».
function ns:FactionFor()
  local me = self:PlayerFaction()
  return me == "A" and self.T("для Альянса") or (me == "H" and self.T("для Орды") or nil)
end

-- домашние зоны чужой фракции не показываем
function ns:ZoneAllowed(area)
  local z = self.Zones[area]
  if not z then return false end
  local me = self:PlayerFaction()
  return not me or z.f == "C" or z.f == me
end

---------------------------------------------------------------------------
-- Сохранённые данные
---------------------------------------------------------------------------
local DEFAULTS = {
  hideDone = false, mapMine = true, mapShow = true, mapAreaAlpha = 0.5, minimap = true, miniGuide = true, itemTips = true, trainerStars = true,
  minimapAngle = 205, scale = 1, ahScan = true, askShare = true, useAlts = true, routeMode = "guide",
}

function ns:InitDB()
  EasyCraftDB = EasyCraftDB or {}
  local db = EasyCraftDB
  db.settings = db.settings or {}
  for k, v in pairs(DEFAULTS) do if db.settings[k] == nil then db.settings[k] = v end end
  db.nodes = db.nodes or {}
  db.vprice = db.vprice or {} -- цена у торговца за штуку (id -> медь), запоминаем у торговцев
  self.db, self.settings = db, db.settings
  self:SetLang(db.lang)

  EasyCraftCharDB = EasyCraftCharDB or {}
  local c = EasyCraftCharDB
  c.profs = c.profs or {}
  c.manual = c.manual or {}
  c.gathered = c.gathered or {}
  c.zones = c.zones or {}
  c.fish = c.fish or {}
  c.scan = c.scan or {}
  c.mail = c.mail or {} -- что ждёт на почте (id -> сколько)
  c.hist = c.hist or {}
  c.collapsed = c.collapsed or {}
  self.char = c
end

---------------------------------------------------------------------------
-- Skills
---------------------------------------------------------------------------
function ns:GetSkill(key)
  local p = self.char and self.char.profs[key]
  if not p then return 0, 0, false end
  return p.rank or 0, p.max or 0, true
end

function ns:RankName(maxRank)
  if not maxRank or maxRank <= 0 then return ns.T("не изучено") end
  for _, cap in ipairs(self.RankOrder) do
    if maxRank <= cap then return self.RankNames[cap] end
  end
  return self.RankNames[300]
end

function ns:LearnedList()
  local primary, secondary = {}, {}
  for _, key in ipairs(self.ProfOrder) do
    if self.char.profs[key] then
      if self.Profs[key].kind == "secondary" then tinsert(secondary, key) else tinsert(primary, key) end
    end
  end
  for _, k in ipairs(secondary) do tinsert(primary, k) end
  return primary
end

local function addFound(found, key, rank, maxRank)
  if key and rank then found[key] = { rank = rank, max = maxRank or 0 } end
end

function ns:ScanSkills()
  local found, enumerated = {}, false
  if GetProfessions and GetProfessionInfo then
    local ok, a, b, c, d, e, f = pcall(GetProfessions)
    if ok then
      enumerated = true
      for _, idx in pairs({ a, b, c, d, e, f }) do
        local name, _, rank, maxRank, _, _, skillLine = GetProfessionInfo(idx)
        addFound(found, self.SkillLineToKey[skillLine] or self.NameToKey[name or ""], rank, maxRank)
      end
    end
  end
  if not enumerated then return end
  local changed = false
  for key, v in pairs(found) do
    local old = self.char.profs[key]
    if not old or old.rank ~= v.rank or old.max ~= v.max then
      changed = true
      self:OnSkillChanged(key, old and old.rank or 0, v.rank, v.max, old == nil)
    end
    v.t = time()
    self.char.profs[key] = v
  end
  -- забытые профессии пропадают из списка навыков
  if next(found) then
    for key in pairs(self.char.profs) do
      if not found[key] then self.char.profs[key] = nil; changed = true end
    end
  end
  if changed then self:RefreshAll() end
end

function ns:SetSkillFromWindow(key, rank, maxRank)
  if not key or not rank or rank <= 0 then return end
  local old = self.char.profs[key]
  -- Из окна обновляем только свою изученную профессию. Новую профессию
  -- берём из списка навыков персонажа, а не из окна (оно может быть чужим).
  if not old then
    self:ScanSkills()
    return
  end
  if not old or old.rank ~= rank or (maxRank and maxRank > 0 and old.max ~= maxRank) then
    -- окно может сказать «предел 0»: тогда прежний предел (0 в Lua - не ложь)
    local mx = (maxRank and maxRank > 0) and maxRank or (old and old.max) or 0
    self:OnSkillChanged(key, old and old.rank or 0, rank, mx, old == nil)
    self.char.profs[key] = { rank = rank, max = mx, t = time() }
    self:RefreshAll()
  end
end

function ns:OnSkillChanged(key, oldRank, newRank, newMax, firstSeen)
  -- навык пришёл после создания: рисуем сразу и вместе с сумками
  if self.craftHold then self.craftHold, self.skillNow = nil, true end
  -- история для журнала
  local h = self.char.hist[key] or {}
  self.char.hist[key] = h
  if not firstSeen and newRank > oldRank then
    tinsert(h, { t = time(), r = newRank })
    while #h > 400 do tremove(h, 1) end
  end
  if firstSeen or not self.ready then return end
  local p = self.Profs[key]
  -- выполненные шаги
  for _, s in ipairs(p.steps) do
    if s.t and oldRank < s.t and newRank >= s.t then
      self:Print(format(ns.T("%s: |cff33dd33шаг выполнен|r - %s"), ns:N(p), self:StepTitle(s)))
      local _, nextStep = self:CurrentStep(key, newRank, newMax)
      if nextStep then self:Print(ns.T("Дальше: ") .. self:StepTitle(nextStep)) end
    end
  end
  for _, s in ipairs(p.steps) do
    if s.learn and s.max and (newMax or 0) < s.max and oldRank < s.learn and newRank >= s.learn and self:CanLearnRank(s, newRank) then
      self:Print(format(ns.T("%s: |cffffd100можно выучить «%s»|r - успей до %d навыка"), ns:N(p), self:RankName(s.max), s.at))
    end
  end
  if newMax and newMax < 300 and newRank >= newMax and oldRank < newMax then
    local msg = format(ns.T("%s %d/%d - пора к учителю: %s"), ns:N(p), newRank, newMax, self:RankName(newMax + 75))
    self:Print("|cffffd100" .. msg .. "|r")
    if UIErrorsFrame then UIErrorsFrame:AddMessage(msg, 1, 0.82, 0) end
  end
end

---------------------------------------------------------------------------
-- Steps
---------------------------------------------------------------------------
function ns:SpellName(id)
  if not id then return end
  if C_Spell and C_Spell.GetSpellName then
    local ok, n = pcall(C_Spell.GetSpellName, id)
    if ok and n then return n end
  end
end

function ns:StepName(s)
  if s.id and s.k ~= "zone" then return self:ItemName(s.id) end
  if s.spell and not s.id then
    -- язык аддона не тот, что у клиента: английское название из базы
    if not ns.IsRU and not ns.UseClient and s.en then return s.en end
    local n = self:SpellName(s.spell)
    if n then return n end
  end
  if s.k == "train" then return ns.T("Выучить: ") .. self:RankName(s.max) end
  return ns:N(s) or "?"
end

function ns:StepTitle(s)
  if s.k == "train" then return format(ns.T("%s (с %d)"), self:StepName(s), s.learn or s.at) end
  if s.k == "book" then return format(ns.T("Книга: %s"), self:StepName(s)) end
  if s.k == "quest" then return ns:N(s) end
  return format("%d-%d  %s", s.f, s.t, self:StepName(s))
end

function ns:StepIcon(s, prof)
  if s.icon then return self.Icon(s.icon) end
  if s.id then return self:ItemIcon(s.id) end
  if s.k == "gather" and s.nodes and s.nodes[1] then return self:ItemIcon(self.Nodes[s.nodes[1]].item) end
  if s.k == "train" then return "Interface\\Icons\\INV_Misc_Book_11" end
  return self.Icon(prof and prof.icon)
end

-- "done", "current", "todo"
function ns:StepState(key, i, rank, maxRank)
  local p = self.Profs[key]
  local s = p.steps[i]
  if not rank then rank, maxRank = self:GetSkill(key) end
  local manual = self.char.manual[key] and self.char.manual[key][i]
  if manual == true then return "done" end
  if s.k == "train" or s.k == "book" or s.k == "quest" then
    local learn = s.learn or s.at
    if manual == false then return rank >= learn and "current" or "todo" end
    if maxRank >= s.max or rank > s.at then return "done" end
    if rank >= learn then return "current" end
    return "todo"
  end
  if manual ~= false and rank >= s.t then return "done" end
  if rank >= s.f and rank < s.t then return "current" end
  return "todo"
end

function ns:CurrentStep(key, rank, maxRank)
  local p = self.Profs[key]
  if not rank then rank, maxRank = self:GetSkill(key) end
  -- возвращает шаг, над которым работать, и ранг, который уже можно выучить (пока не срочно)
  local firstTodo, train
  for i = 1, #p.steps do
    local s = p.steps[i]
    local st = self:StepState(key, i, rank, maxRank)
    local isRank = s.k == "train" or s.k == "book" or s.k == "quest"
    if st == "current" then
      if isRank and rank < s.at then
        train = train or i
      else
        return i, s, train
      end
    end
    if st == "todo" and not firstTodo then firstTodo = i end
  end
  if train then return train, p.steps[train] end
  if firstTodo then return firstTodo, p.steps[firstTodo] end
end

function ns:ToggleManual(key, i)
  local m = self.char.manual[key] or {}
  self.char.manual[key] = m
  local auto = self:StepState(key, i) -- с учётом ручной отметки
  if m[i] == nil then
    m[i] = (auto ~= "done")
  else
    m[i] = nil
  end
  self:RefreshAll()
end

function ns:RemainingCrafts(s, rank)
  if not s.n then return 0 end
  if rank >= s.t then return 0 end
  if rank <= s.f then return s.n end
  return ceil(s.n * (s.t - rank) / (s.t - s.f))
end

-- Сколько реагента нужно на оставшиеся крафты шага.
function ns:StepNeed(s, q, left)
  if s.rc then return q * left end
  return ceil(q * left / s.n)
end

-- Что купить для оставшихся шагов-ремёсел, которые начинаются ниже upTo
-- (обычно предел ранга): { id, need, have, buy, step, crafted } по порядку
-- шагов. crafted - предмет делается своим же шагом маршрута, покупать не надо.
function ns:ShoppingList(key, upTo)
  local p = self.Profs[key]
  local rank, maxRank = self:GetSkill(key)
  local need, order, made = {}, {}, {}
  for i, s in ipairs(p.steps) do
    local mats = s.rc or s.m
    if s.k == "craft" and mats and s.n and (not upTo or s.f < upTo) and self:StepState(key, i, rank, maxRank) ~= "done" then
      local left = self:RemainingCrafts(s, rank)
      if s.id and left > 0 then made[s.id] = true end
      for j = 1, #mats, 2 do
        local id = mats[j]
        local q = self:StepNeed(s, mats[j + 1], left)
        if q > 0 then
          if not need[id] then need[id] = 0; tinsert(order, { id = id, step = i }) end
          need[id] = need[id] + q
        end
      end
    end
  end
  local alts = self:AltCounts()
  for _, e in ipairs(order) do
    e.need = need[e.id]
    e.have = self:ItemCount(e.id)
    e.alts = alts[e.id] or 0
    e.mail = self.MailCount and self:MailCount(e.id) or 0 -- куплено, ждёт в ящике
    e.crafted = made[e.id] or false
    e.buy = e.crafted and 0 or max(0, e.need - e.have - e.alts - e.mail)
  end
  return order
end

-- Все покупки по всем профессиям: id -> { need, have, alts, buy, profs = { {key, need, cap} } }.
-- Кешируется до следующего обновления (сумки, навык, окно профессии).
function ns:AllNeeds()
  if self.needCache then return self.needCache end
  local all = {}
  for _, key in ipairs(self:LearnedList()) do
    local cap = self:ShoppingCap(key)
    for _, e in ipairs(self:ShoppingList(key, cap)) do
      if not e.crafted then
        local a = all[e.id]
        if not a then
          a = { need = 0, have = e.have, alts = e.alts, mail = e.mail, profs = {} }
          all[e.id] = a
        end
        a.need = a.need + e.need
        tinsert(a.profs, { key = key, need = e.need, cap = cap })
      end
    end
  end
  for _, a in pairs(all) do a.buy = max(0, a.need - a.have - a.alts - a.mail) end
  self.needCache = all
  return all
end

-------------------------------------------------------------------------------
--  Реагенты у других персонажей (альтов) из BagBrother (Bagnon): BrotherBags.
--  Свой персонаж не считается - его сумки и банк даёт сама игра.
-------------------------------------------------------------------------------
local function squash(s) return (tostring(s or ""):gsub("[%s%-]", ""):lower()) end

function ns:AltCounts()
  if self.altCache then return self.altCache end
  local out = {}
  local B = _G.BrotherBags
  local me = UnitName and UnitName("player")
  if type(B) ~= "table" or not me then return out end
  local myKey = squash(me)
  -- свой сервер - тот, где записан текущий персонаж: сначала по имени
  -- сервера, потом поиском себя
  local realm
  local byName = GetRealmName and B[GetRealmName()]
  if type(byName) == "table" then
    for name in pairs(byName) do if squash(name) == myKey then realm = byName break end end
  end
  for _, chars in pairs(realm and {} or B) do
    if type(chars) == "table" then
      for name in pairs(chars) do
        if squash(name) == myKey then realm = chars break end
      end
    end
    if realm then break end
  end
  -- себя не нашли (новый персонаж, BagBrother ещё не записал): альтов не
  -- считаем, чтобы не посчитать себя дважды, и не запоминаем - спросим позже
  if not realm then return out end
  self.altCache = out
  local n = 0
  for name, data in pairs(realm) do
    -- "Имя*" - банк гильдии, его не берём
    if squash(name) ~= myKey and type(data) == "table" and not tostring(name):find("%*$") then
      n = n + 1
      for _, bag in pairs(data) do
        if type(bag) == "table" and type(bag.items) == "table" then
          for _, item in pairs(bag.items) do
            if type(item) == "string" then
              local id = tonumber(item:match("^(%d+)"))
              if id then out[id] = (out[id] or 0) + (tonumber(item:match(";(%d+)$")) or 1) end
            end
          end
        end
      end
    end
  end
  self.altChars = n
  return out
end

-------------------------------------------------------------------------------
--  Отставание профессии от уровня персонажа: обычно навык ~5 за уровень
--  (60 уровень - 300). Возвращает nil или { expected, level, skillLevel }.
-------------------------------------------------------------------------------
ns.SKILL_PER_LEVEL = 5
ns.LAG_WARN = 40 -- предупреждать, если навык ниже обычного на столько (~8 уровней)

function ns:SkillForLevel(level) return min(300, max(1, level or 1) * self.SKILL_PER_LEVEL) end
function ns:LevelForSkill(rank) return max(1, ceil((rank or 1) / self.SKILL_PER_LEVEL)) end

function ns:Lag(key)
  local rank, _, learned = self:GetSkill(key)
  if not learned then return nil end
  local level = UnitLevel and UnitLevel("player") or 1
  local expected = self:SkillForLevel(level)
  if expected - rank < self.LAG_WARN then return nil end
  return { expected = expected, level = level, skillLevel = self:LevelForSkill(rank) }
end

-- До какого навыка считать покупки: до предела ранга, а если навык в него
-- уже упёрся - до предела следующего ранга (после учителя).
function ns:ShoppingCap(key)
  local rank, maxRank = self:GetSkill(key)
  if maxRank <= 0 then return 75 end
  if rank >= maxRank and maxRank < 300 then return maxRank + 75 end
  return maxRank
end

function ns:RouteProgress(key)
  local p = self.Profs[key]
  local rank = self:GetSkill(key)
  return min(1, rank / 300), rank
end

---------------------------------------------------------------------------
-- Gathering difficulty (classic rules: orange <25, yellow <50, green <100)
---------------------------------------------------------------------------
function ns:GatherColor(rank, req)
  if rank < req then return "red" end
  local d = rank - req
  if d < 25 then return "orange" elseif d < 50 then return "yellow" elseif d < 100 then return "green" end
  return "gray"
end

ns.ColorRGB = {
  orange = { 1, 0.5, 0.25 }, yellow = { 1, 1, 0 }, green = { 0.25, 0.75, 0.25 },
  gray = { 0.5, 0.5, 0.5 }, red = { 1, 0.1, 0.1 },
}
local COLOR_RU = { orange = "оранжевый", yellow = "жёлтый", green = "зелёный", gray = "серый", red = "недоступно" }
ns.ColorName = setmetatable({}, { __index = function(_, k) return COLOR_RU[k] and ns.T(COLOR_RU[k]) end })
function ns.ColorRGBText(color, text) return ns:Hex(color) .. text .. "|r" end

function ns:Hex(color)
  local c = self.ColorRGB[color] or { 1, 1, 1 }
  return format("|cff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255)
end

-- Zones ranked for the current gathering skill: {area=, score=, nodes={key=count}}
-- Зоны для шага сбора. Учитываем всё сразу и сортируем по одному счёту:
--  * сколько там мест трав/руды этого шага (оранжевое ценнее зелёного);
--  * рекомендация маршрута для твоей фракции (recH / recA);
--  * где ты сам уже собирал это (свой опыт - сильный довод);
--  * уровень зоны: заметно выше персонажа - опасно, ниже в списке.
-- { area, rec, mine, score, nodes = { key = мест }, order = { key, ... } }.
function ns:StepGatherZones(s, rank, limit)
  local zones, want = {}, {}
  local function zone(area)
    local z = zones[area]
    if not z then z = { area = area, score = 0, data = 0, mine = 0, nodes = {}, order = {} }; zones[area] = z end
    return z
  end
  for _, nk in ipairs(s.nodes or {}) do
    local n = self.Nodes[nk]
    if n then
      want[n.item] = nk
      local color = self:GatherColor(max(rank, 1), n.req)
      local w = (color == "orange" and 3) or (color == "yellow" and 2) or (color == "green" and 1) or 0
      for _, zc in ipairs(n.zones or {}) do
        local area, cnt = zc[1], zc[2]
        if self:ZoneAllowed(area) then
          local z = zone(area)
          z.data = z.data + cnt * w
          if not z.nodes[nk] then tinsert(z.order, nk) end
          z.nodes[nk] = (z.nodes[nk] or 0) + cnt
        end
      end
    end
  end
  -- свой опыт: сколько трав/руды этого шага ты собрал в каждой зоне
  for ui, items in pairs(self.char.zones or {}) do
    local area = self.UiToArea[ui]
    if area and self:ZoneAllowed(area) then
      for id, qty in pairs(items) do
        if want[id] then zone(area).mine = zone(area).mine + qty end
      end
    end
  end
  -- Лучшие зоны своей фракции (маршрут знает их для Орды и Альянса) -
  -- всегда первыми и по порядку маршрута: рядом город, полёты и задания.
  -- Ничьи зоны, где база только у другой стороны, - ниже.
  local me = self:PlayerFaction()
  local rec = {}
  for k, area in ipairs(s[me == "A" and "recA" or "recH"] or {}) do rec[area] = k end
  local my = UnitLevel and UnitLevel("player") or 0
  local list = {}
  for area, z in pairs(zones) do
    z.rec = rec[area] and true or nil
    local zd = self.Zones[area]
    local danger = zd and zd.lo and zd.lo > my + 3
    local away = me and self.ZONE_SIDE[area] and self.ZONE_SIDE[area] ~= me
    z.score = z.data * (danger and 0.4 or 1) * (away and 0.5 or 1) + min(z.mine, 200) * 2
    if rec[area] then z.score = z.score + 100000 - rec[area] * 1000 end
    if z.score > 0 then tinsert(list, z) end
  end
  table.sort(list, function(a, b) return a.score > b.score end)
  while limit and #list > limit do tremove(list) end
  return list
end

-- Почему зона в списке: строки для подсказки.
function ns:ZoneWhy(z)
  local T, out = ns.T, {}
  if z.rec then
    local side = self:FactionFor()
    tinsert(out, side and (T("Рекомендуем ") .. side .. ".") or T("Рекомендуем по маршруту."))
  end
  if (z.mine or 0) > 0 then tinsert(out, format(T("Ты здесь уже собрал: %d."), z.mine)) end
  if (z.data or 0) > 0 then tinsert(out, T("Много того, что нужно для шага.")) end
  local zd = self.Zones[z.area]
  local my = UnitLevel and UnitLevel("player") or 0
  if zd and zd.lo and zd.lo > my + 3 then tinsert(out, "|cffff5555" .. format(T("Зона %d-%d уровня - опасно."), zd.lo, zd.hi) .. "|r") end
  return table.concat(out, "\n")
end

-- Значки трав/руды зоны (пути к картинкам), что там больше - первым.
function ns:ZoneNodeIcons(z, most)
  local order = {}
  for _, nk in ipairs(z.order or {}) do tinsert(order, nk) end
  table.sort(order, function(a, b) return (z.nodes[a] or 0) > (z.nodes[b] or 0) end)
  local out = {}
  for _, nk in ipairs(order) do
    local n = self.Nodes[nk]
    if n and (not most or #out < most) then tinsert(out, self:ItemIcon(n.item)) end
  end
  return out
end

-- Значки трав/руды зоны строкой (для кнопок зон) и подсказка «что там есть».
function ns:ZoneNodesText(z, size, most)
  local icons, lines = {}, {}
  -- значки: сначала то, чего там больше
  local order = {}
  for _, nk in ipairs(z.order or {}) do tinsert(order, nk) end
  table.sort(order, function(a, b) return (z.nodes[a] or 0) > (z.nodes[b] or 0) end)
  for _, nk in ipairs(order) do
    local n = self.Nodes[nk]
    if n then
      if not most or #icons < most then
        tinsert(icons, "|T" .. self:ItemIcon(n.item) .. ":" .. (size or 14) .. ":" .. (size or 14) .. "|t")
      end
      tinsert(lines, format(ns.T("%s: мест %d"), ns:N(n), z.nodes[nk]))
    end
  end
  return table.concat(icons, ""), table.concat(lines, "\n")
end

function ns:BestGatherZones(profKey, rank, limit)
  local zones = {}
  for _, key in ipairs(self.NodeOrder) do
    local n = self.Nodes[key]
    if n.prof == profKey then
      local color = self:GatherColor(max(rank, 1), n.req)
      local w = (color == "orange" and 3) or (color == "yellow" and 2) or (color == "green" and 1) or 0
      if w > 0 then
        for _, zc in ipairs(n.zones) do
          local area, cnt = zc[1], zc[2]
          if self:ZoneAllowed(area) then
            local z = zones[area] or { area = area, score = 0, nodes = {} }
            zones[area] = z
            z.score = z.score + cnt * w
            z.nodes[key] = cnt
          end
        end
      end
    end
  end
  local list = {}
  for _, z in pairs(zones) do tinsert(list, z) end
  table.sort(list, function(a, b) return a.score > b.score end)
  while limit and #list > limit do tremove(list) end
  return list
end

function ns:NodeTopZones(key, limit)
  local out = {}
  for _, zc in ipairs(self.Nodes[key].zones) do
    if self:ZoneAllowed(zc[1]) then tinsert(out, zc) end
    if #out >= (limit or 5) then break end
  end
  return out
end

-- Source areas for a material: list of {area, weight}
function ns:MaterialAreas(id, limit)
  local src = self.MatSources[id]
  if not src then return {} end
  local acc, list = {}, {}
  if src.nodes then
    for _, nk in ipairs(src.nodes) do
      for _, zc in ipairs(self.Nodes[nk].zones) do acc[zc[1]] = (acc[zc[1]] or 0) + zc[2] end
    end
  elseif src.areas then
    for i, a in ipairs(src.areas) do acc[a] = 100 - i end
  end
  for a, w in pairs(acc) do if self:ZoneAllowed(a) then tinsert(list, { a, w }) end end
  table.sort(list, function(x, y) return x[2] > y[2] end)
  while #list > (limit or 4) do tremove(list) end
  return list
end

---------------------------------------------------------------------------
-- Рассылка обновлений (сюда подписываются части окна)
---------------------------------------------------------------------------
ns.refreshers = {}
function ns:RegisterRefresh(fn) tinsert(self.refreshers, fn) end
-- Только что создали предмет: реагенты из сумок уже ушли, а навык игра
-- пришлёт чуть позже. Перерисуй сразу - на долю секунды «7/8» красным.
-- Поэтому после создания ждём навык (не дольше CRAFT_HOLD), а как он
-- пришёл - рисуем сразу.
local CRAFT_HOLD = 0.8
local pending, gen = false, 0
function ns:RefreshAll()
  self.needCache = nil -- покупки пересчитаются при следующем обращении
  local wait = 0.1
  local hold = self.craftHold and (self.craftHold - GetTime()) or 0
  if hold > 0 then wait = hold + 0.05 else self.craftHold = nil end
  -- навык пришёл: отложенную перерисовку заменяем быстрой
  if pending and not self.skillNow then return end
  self.skillNow = nil
  pending = true
  gen = gen + 1
  local my = gen
  local function run()
    if my ~= gen then return end
    pending = false
    for _, fn in ipairs(ns.refreshers) do ns:Safe(fn) end
  end
  C_Timer.After(wait, run)
end

-- Создание предмета прошло: подержать перерисовку до прихода навыка.
function ns:HoldForSkill()
  self.craftHold = GetTime() + CRAFT_HOLD
end

---------------------------------------------------------------------------
-- Цвет рецепта на навыке (пороги Forever: оранжевый, жёлтый, зелёный, серый)
---------------------------------------------------------------------------
function ns:RecipeColor(s, rank)
  local sk = s.sk
  if not sk then return nil end
  if rank >= sk[4] then return "gray" elseif rank >= sk[3] then return "green" elseif rank >= sk[2] then return "yellow" end
  return "orange"
end

function ns:RecipeColorText(s)
  local sk = s.sk
  if not sk then return nil end
  local parts = {}
  if sk[1] and sk[1] > 0 and sk[2] > sk[1] then tinsert(parts, self:Hex("orange") .. ns.T("оранжевый с ") .. sk[1] .. "|r") end
  tinsert(parts, self:Hex("yellow") .. ns.T("жёлтый с ") .. sk[2] .. "|r")
  tinsert(parts, self:Hex("green") .. ns.T("зелёный с ") .. sk[3] .. "|r")
  tinsert(parts, self:Hex("gray") .. ns.T("серый с ") .. sk[4] .. "|r")
  return table.concat(parts, ", ")
end

-- Шанс получить очко навыка за одно создание (0..1), как в классике:
-- оранжевый - всегда, серый - никогда, жёлтый и зелёный - тем реже, чем
-- ближе навык к серому: (серый - навык) / (серый - жёлтый).
-- color - настоящий цвет из окна профессии; если он расходится с данными
-- маршрута, шанс не считаем, чтобы не врать.
function ns:SkillChance(s, rank, color)
  local sk = s and s.sk
  if not (sk and sk[2] and sk[4]) then return nil end
  local dataColor = self:RecipeColor(s, rank)
  color = color or dataColor
  if color == "orange" then return 1 end
  if color == "gray" then return 0 end
  if color ~= dataColor or sk[4] <= sk[2] then return nil end
  return math.max(0, math.min(1, (sk[4] - rank) / (sk[4] - sk[2])))
end

-- «шанс ~60%» для жёлтого и зелёного, nil для остальных.
function ns:ChanceText(s, rank, color)
  local p = self:SkillChance(s, rank, color)
  if not p or p >= 1 or p <= 0 then return nil end
  return format(ns.T("шанс ~%d%%"), math.floor(p * 100 + 0.5))
end

-- Шаг маршрута с этим рецептом (первый невыполненный, иначе любой).
function ns:SpellStep(key, spell)
  local p = self.Profs[key]
  if not (p and spell) then return nil end
  local any
  for i, s in ipairs(p.steps) do
    if s.spell == spell then
      if self:StepState(key, i) ~= "done" then return s, i end
      any = any or i
    end
  end
  if any then return p.steps[any], any end
end

-- Можно ли уже выучить ранг шага s: хватает и навыка, и уровня персонажа.
function ns:CanLearnRank(s, rank)
  if not s or rank < (s.learn or s.at or 0) then return false end
  return not s.lvl or (UnitLevel and UnitLevel("player") or 0) >= s.lvl
end

-- Следующий ранг: с какого навыка его можно учить и какой предел он даст.
function ns:NextRank(key)
  local p = self.Profs[key]
  if not (p and self.char and self.char.profs[key]) then return nil end -- профессия не изучена
  local rank, maxRank = self:GetSkill(key)
  for i, s in ipairs(p.steps) do
    if (s.k == "train" or s.k == "book" or s.k == "quest") and s.max and s.max > (maxRank or 0) then
      if self:StepState(key, i, rank, maxRank) ~= "done" then
        return { learn = s.learn or s.at or 0, max = s.max, step = i, s = s }
      end
    end
  end
end

---------------------------------------------------------------------------
-- НИПы (учителя, торговцы рецептами): отбор по фракции, расстояние, метки
---------------------------------------------------------------------------
function ns:NpcName(id)
  local n = self.NPCs[id]
  return n and (ns.IsRU and (n.ru or n.en) or (n.en or n.ru)) or ("NPC " .. tostring(id))
end

function ns:MapName(ui)
  if not ns.IsRU and not ns.UseClient then
    local area = self.UiToArea[ui]
    local z = area and self.Zones[area]
    if z and z.en then return z.en end
  end
  local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(ui)
  if info and info.name and info.name ~= "" then return info.name end
  local area = self.UiToArea[ui]
  return area and self.Zones[area] and ns:N(self.Zones[area]) or nil
end

function ns:NpcZone(id)
  local n = self.NPCs[id]
  if not n then return "" end
  return self:MapName(n.ui) or n.zone or ""
end

local function worldPos(ui, x, y)
  if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return end
  local ok, cont, pos = pcall(C_Map.GetWorldPosFromMapPos, ui, CreateVector2D(x, y))
  if ok and cont and pos then local a, b = pos:GetXY(); return cont, a, b end
end

local npcWorld = {} -- id -> { континент, x, y } или false

-- НИПы фракции игрока (и нейтральные); ближайшие первыми, если клиент знает расстояние
function ns:NpcsFor(npcs, limit)
  if not npcs then return {} end
  local me = self:PlayerFaction()
  local list = {}
  for _, f in ipairs({ me or "A", "N", me and "" or "H" }) do
    if npcs[f] then
      for _, id in ipairs(npcs[f]) do if self.NPCs[id] then tinsert(list, id) end end
    end
  end
  local pm, px, py = self:PlayerPosition()
  local pc, wa, wb
  if pm and px then pc, wa, wb = worldPos(pm, px, py) end
  if pc then
    local dist = {}
    for _, id in ipairs(list) do
      -- место NPC в мире не меняется: считаем один раз
      local w = npcWorld[id]
      if w == nil then
        local n = self.NPCs[id]
        local c, a, b = worldPos(n.ui, n.x / 100, n.y / 100)
        w = c and { c, a, b } or false
        npcWorld[id] = w
      end
      dist[id] = (w and w[1] == pc and w[2]) and ((w[2] - wa) ^ 2 + (w[3] - wb) ^ 2) or (w and 1e12 or 1e13)
    end
    table.sort(list, function(x, y) return dist[x] < dist[y] end)
  end
  while limit and #list > limit do tremove(list) end
  -- второе значение: расставлены по расстоянию (знаем, где игрок)
  return list, pc ~= nil
end

-- show - сразу открыть карту на метке (кнопка «Метка на карте»).
function ns:Waypoint(id, show)
  local n = self.NPCs[id]
  if not n then return end
  self:MapPoint(n.ui, n.x, n.y, self:NpcName(id), self:NpcZone(id), show)
end

-- Метка на карте в точке (x, y - в процентах) карты ui: TomTom и метка игры,
-- значок на карте мира; show - сразу открыть карту на ней.
function ns:MapPoint(ui, px, py, title, where, show)
  local x, y = px / 100, py / 100
  local arrow = false
  if TomTom and TomTom.AddWaypoint then
    arrow = pcall(TomTom.AddWaypoint, TomTom, ui, x, y, { title = title, persistent = false }) or arrow
  end
  if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
    local ok = pcall(function()
      C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(ui, x, y))
      if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
    end)
    arrow = arrow or ok
  end
  self.mapTarget = { ui = ui, x = x, y = y, title = title }
  self:Print(format("%s - %s (%.1f, %.1f)%s", title, where or "", px, py, arrow and ns.T(", метка поставлена") or ""))
  if (show or not arrow) and self.MapOverlay then self.MapOverlay:OpenMap(ui) end
  self:RefreshAll()
end

---------------------------------------------------------------------------
-- Tools
---------------------------------------------------------------------------
function ns:MissingTools(key, rank)
  local p = self.Profs[key]
  local out = {}
  for _, t in ipairs(p.tools or {}) do
    if t[3] and rank >= t[2] and self:ItemCount(t[1]) == 0 then tinsert(out, t[1]) end
  end
  return out
end
