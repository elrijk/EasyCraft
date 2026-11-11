local _, TJ = ...
local W, C, T = TJ.W, TJ.Content, TJ.T
local format, floor, min, max = string.format, math.floor, math.min, math.max

-------------------------------------------------------------------------------
--  Выбор профессии: отдельное окно на том же каркасе, что окно знакомства
--  (UI/Intro.lua): та же рамка и фон, заголовок по центру с золотой линией,
--  блоки в золотой рамке, кнопки внизу.
--    заголовок - «Какую профессию выбрать»;
--    панель профессии - её рисунок на всю панель, поверх слева крупный
--    значок, название, основная она или вторичная и одна строка «зачем»;
--    три блока-инфографики: что создаёт (предметы с подсказками), с чем в
--    паре (значки профессий), кому брать (значки классов);
--    внизу - изучена ли, крупная кнопка «Учитель на карте», «Назад» и
--    «Дальше»;
--    справа у окна - вкладки всех профессий: значок и название.
--  Открывается кнопкой «Выбор профессии» на вкладке «Профессии» и при
--  первом открытии аддона.
-------------------------------------------------------------------------------
local S = W.S
local WIDTH, HEIGHT = 760, 620
local SIDE = 28 -- поля окна слева и справа
local LEFT = 44 -- левый край содержимого
local TOP = 96 -- где начинается содержимое под шапкой
local STRIP_W = 480 -- ширина полосы «зачем»
local MAX_ICONS = 4

-- Строка «зачем», что создаёт (добывает), кому брать (текст или список
-- классов), цвет фона панели, если рисунка нет.
local ALL = "Всем классам"
local INFO = {
  alchemy = { "Расходники нужны всем и всегда: варишь себе и на аукцион.", "Зелья, эликсиры, настои", ALL, { 0.45, 0.2, 0.6 } },
  blacksmithing = { "Куёшь оружие и тяжёлую броню, точишь клинки.", "Оружие, кольчуга, латы", { "WARRIOR", "PALADIN" }, { 0.7, 0.3, 0.1 } },
  enchanting = { "Усиливаешь экипировку чарами. Материалы - из распылённых вещей.", "Чары, масла, жезлы", ALL, { 0.3, 0.3, 0.8 } },
  engineering = { "Бомбы и устройства, которых нет больше ни у кого.", "Бомбы, устройства, ружья", "Всем, особенно в PvP", { 0.7, 0.6, 0.1 } },
  leatherworking = { "Шьёшь кожаную и кольчужную броню из шкур.", "Кожаная и кольчужная броня", { "ROGUE", "DRUID", "HUNTER", "SHAMAN" }, { 0.5, 0.3, 0.15 } },
  tailoring = { "Тканевая броня и сумки. Ткань падает с врагов.", "Тканевая броня, сумки", { "MAGE", "PRIEST", "WARLOCK" }, { 0.6, 0.2, 0.4 } },
  mining = { "Руда и камень с жил по всему миру. Всегда в цене.", "Руда, слитки, камни", ALL, { 0.35, 0.45, 0.55 } },
  herbalism = { "Собираешь травы по пути - продаёшь алхимикам.", "Травы", ALL, { 0.2, 0.55, 0.2 } },
  skinning = { "Снимаешь шкуры с убитых зверей. Золото с первого уровня.", "Кожа и шкуры", ALL, { 0.55, 0.4, 0.25 } },
  cooking = { "Еда с бонусами и костёр для лагеря.", "Еда с «Сытостью»", ALL, { 0.7, 0.4, 0.15 } },
  firstaid = { "Лечишься сам, без лекаря и без маны.", "Бинты, лечебные зелья", ALL, { 0.7, 0.15, 0.15 } },
  fishing = { "Рыба для кулинарии и алхимии. Спокойный заработок.", "Рыба", ALL, { 0.1, 0.45, 0.6 } },
}
local CLASS_RU = { WARRIOR = "Воин", PALADIN = "Паладин", HUNTER = "Охотник", ROGUE = "Разбойник", PRIEST = "Жрец",
  SHAMAN = "Шаман", MAGE = "Маг", WARLOCK = "Чернокнижник", DRUID = "Друид" }
-- Рисунки окна профессий игры: имя профессии в названии атласа.
local ART = { alchemy = "Alchemy", blacksmithing = "Blacksmithing", enchanting = "Enchanting", engineering = "Engineering",
  leatherworking = "Leatherworking", tailoring = "Tailoring", mining = "Mining", herbalism = "Herbalism",
  skinning = "Skinning", cooking = "Cooking", fishing = "Fishing" }
local ART_ALT = { firstaid = { "FirstAid", "First-Aid", "Firstaid", "First Aid" } }
local ART_KINDS = { "Professions-Specializations-Background-%s", "Professions-Recipe-Background-%s" }
local CLASS_TEX = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local ALL_ICON = "Interface\\Icons\\Achievement_Character_Human_Male"
local NONE_ICON = "Interface\\Icons\\INV_Misc_Bag_08"

local function artAtlas(key)
  local names = ART_ALT[key] or { ART[key] }
  for _, n in ipairs(names) do
    for _, k in ipairs(ART_KINDS) do
      local name = format(k, n)
      if W.HasAtlas(name) then return name end
    end
  end
end

local function className(token)
  if TJ.IsRU then return CLASS_RU[token] or token end
  return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token]) or T(CLASS_RU[token] or token)
end

-- Профессии в паре: сбор для ремесла, ремёсла для сбора.
local function pairKeys(key)
  local p = TJ.Profs[key]
  if p.pair and TJ.Profs[p.pair] then return { p.pair } end
  local users = {}
  for _, k in ipairs(TJ.ProfOrder) do
    if TJ.Profs[k].pair == key then users[#users + 1] = k end
  end
  return users
end

-- Примеры добычи для профессий, в маршруте которых предметов нет: кожа от
-- лёгкой до грубой, рыба от мелкой до крупной.
local EXAMPLES = {
  skinning = { 2318, 2319, 4234, 8170 },
  fishing = { 6291, 6308, 6362, 13754 },
}

-- Что получается из профессии: предметы маршрута, равномерно от начала до конца.
local function products(key, limit)
  local p = TJ.Profs[key]
  local all, seen = {}, {}
  local function add(id)
    if type(id) == "number" and not seen[id] then seen[id] = true; all[#all + 1] = id end
  end
  for _, s in ipairs(p.steps) do
    if s.k == "craft" then add(s.id) end
    if s.k == "gather" and s.nodes then
      for _, nk in ipairs(s.nodes) do add(TJ.Nodes[nk] and TJ.Nodes[nk].item) end
    end
  end
  -- в маршруте предметов нет (снятие шкур, рыбная ловля): готовые примеры
  if #all == 0 and EXAMPLES[key] then return EXAMPLES[key] end
  if #all <= limit then return all end
  local out = {}
  for i = 1, limit do out[i] = all[1 + floor((i - 1) * (#all - 1) / (limit - 1) + 0.5)] end
  return out
end

local function rule(parent, w, a)
  local t = parent:CreateTexture(nil, "ARTWORK")
  t:SetSize(w, 1)
  t:SetColorTexture(0.85, 0.68, 0.3, a or 0.8)
  return t
end

local function tipButton(b)
  b:SetScript("OnEnter", function(s)
    if not s.tip then return end
    GameTooltip:SetOwner(s, "ANCHOR_TOP")
    GameTooltip:SetText(s.tip, 1, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local win

local function turn(f, delta)
  local order = TJ.ProfOrder
  for i, k in ipairs(order) do
    if k == f.key then
      local n = i + delta
      if n < 1 then n = #order elseif n > #order then n = 1 end
      W.Sound("IG_ABILITY_PAGE_TURN")
      TJ:ShowChoose(order[n])
      return
    end
  end
end

-- Блок-инфографика: заголовок золотом, ряд значков по центру, подпись.
local function infoCard(parent, width)
  local c = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  -- без рамки и подложки: значки лежат прямо на рисунке панели
  c:SetWidth(width)
  c.head = W.Text(c, "head", false)
  c.head:SetJustifyH("CENTER")
  c.head:SetPoint("TOP", 0, -8)
  c.head:SetShadowOffset(1, -1)
  c.head:SetShadowColor(0, 0, 0, 0.9)
  c.items, c.rings, c.classes = {}, {}, {}
  for i = 1, MAX_ICONS do
    c.items[i] = W.ItemIcon(c, 36)
    c.rings[i] = W.RingIcon(c, 44)
    local t = c:CreateTexture(nil, "ARTWORK")
    t:SetSize(40, 40)
    t:SetTexture(CLASS_TEX)
    c.classes[i] = t
  end
  c.caption = W.Text(c, "body")
  c.caption:SetJustifyH("CENTER")
  c.caption:SetWidth(width - 20)
  c.caption:SetTextColor(0.92, 0.9, 0.84)
  c.caption:SetShadowOffset(1, -1)
  c.caption:SetShadowColor(0, 0, 0, 0.9)
  -- kind: "items" | "rings" | "classes"; n значков по центру на высоте y
  function c:Row(kind, n, size)
    for _, list in pairs({ self.items, self.rings, self.classes }) do
      for _, w in ipairs(list) do w:Hide() end
    end
    local list = self[kind]
    local gap = 10
    local total = n * size + (n - 1) * gap
    local x0 = floor((width - total) / 2)
    for i = 1, n do
      local w = list[i]
      w:ClearAllPoints()
      w:SetPoint("TOPLEFT", self, "TOPLEFT", x0 + (i - 1) * (size + gap), -40)
      w:Show()
    end
    self.caption:ClearAllPoints()
    self.caption:SetPoint("TOP", self, "TOP", 0, -(40 + size + 12))
    return list
  end
  return c
end

local function build()
  local f = CreateFrame("Frame", "EasyCraftChooseFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  f:SetSize(WIDTH, HEIGHT)
  f:SetPoint("CENTER", -20, 20)
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetScale(TJ.settings.scale or 1)
  -- рамка - как у окна знакомства; фон - рисунок профессии на всё окно
  W.Backdrop(f, "Interface\\Buttons\\WHITE8X8", nil, 16, 0.04, 0.03, 0.02, 1, 0.75, 0.6, 0.3, 1)
  tinsert(UISpecialFrames, "EasyCraftChooseFrame")
  f.wash = f:CreateTexture(nil, "BORDER")
  f.wash:SetPoint("TOPLEFT", 4, -4)
  f.wash:SetPoint("BOTTOMRIGHT", -4, 4)
  f.wash:SetColorTexture(1, 1, 1, 1)
  f.art = f:CreateTexture(nil, "BORDER", nil, 1)
  f.art:SetPoint("TOPLEFT", 4, -4)
  f.art:SetPoint("BOTTOMRIGHT", -4, 4)
  f.glow = f:CreateTexture(nil, "BORDER", nil, 2) -- второй слой сложением: бледный рисунок заметнее
  f.glow:SetAllPoints(f.art)
  f.glow:SetBlendMode("ADD")
  f.glow:SetAlpha(0.7)
  f.emblem = f:CreateTexture(nil, "BORDER", nil, 2)
  f.emblem:SetSize(340, 340)
  f.emblem:SetPoint("RIGHT", -40, 10)
  f.emblem:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  -- затемнения: слева под текст, сверху под заголовок, снизу под кнопки
  local function shade(orient, a1, a2)
    local t = f:CreateTexture(nil, "BORDER", nil, 3)
    t:SetColorTexture(1, 1, 1, 1)
    local ok = CreateColor and pcall(t.SetGradient, t, orient, CreateColor(0, 0, 0, a1), CreateColor(0, 0, 0, a2))
    if not ok then t:SetColorTexture(0, 0, 0, (a1 + a2) / 2) end
    return t
  end
  local left = shade("HORIZONTAL", 0.85, 0)
  left:SetPoint("TOPLEFT", 4, -4)
  left:SetPoint("BOTTOMLEFT", 4, 4)
  left:SetWidth(floor(WIDTH * 0.75))
  local top = shade("VERTICAL", 0, 0.75)
  top:SetPoint("TOPLEFT", 4, -4)
  top:SetPoint("TOPRIGHT", -4, -4)
  top:SetHeight(110)
  local bottom = shade("VERTICAL", 0.9, 0)
  bottom:SetPoint("BOTTOMLEFT", 4, 4)
  bottom:SetPoint("BOTTOMRIGHT", -4, 4)
  bottom:SetHeight(170)

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 0, 0)

  -- шапка окна
  f.title = W.Text(f, "huge", false)
  f.title:SetJustifyH("CENTER")
  f.title:SetPoint("TOP", 0, -26)
  local file, _, flags = f.title:GetFont()
  if file then f.title:SetFont(file, 24, flags) end
  f.title:SetShadowOffset(1, -1)
  f.title:SetShadowColor(0, 0, 0, 0.9)
  f.rule = rule(f, 360)
  f.rule:SetPoint("TOP", f.title, "BOTTOM", 0, -10)

  -- основная она или вторичная - мелко над названием
  f.kind = W.Text(f, "head", false)
  f.kind:SetPoint("TOPLEFT", LEFT + 2, -TOP)
  f.kind:SetShadowOffset(1, -1)
  f.kind:SetShadowColor(0, 0, 0, 0.9)
  f.badge = W.RingIcon(f, 64)
  f.badge:SetPoint("TOPLEFT", LEFT, -(TOP + 26))
  f.name = W.Text(f, "huge", false)
  f.name:SetPoint("LEFT", f.badge, "RIGHT", 18, 0)
  file, _, flags = f.name:GetFont()
  if file then f.name:SetFont(file, 52, flags) end
  f.name:SetShadowOffset(2, -2)
  f.name:SetShadowColor(0, 0, 0, 0.9)
  -- изучена ли - сразу под названием
  f.state = W.Text(f, "body", false)
  f.state:SetPoint("TOPLEFT", f.badge, "BOTTOMLEFT", 2, -12)
  f.state:SetShadowOffset(1, -1)
  f.state:SetShadowColor(0, 0, 0, 0.9)
  -- строка «зачем» на тёмной полосе между двумя линиями
  f.lineTop = rule(f, STRIP_W, 0.7)
  f.lineTop:SetPoint("TOPLEFT", f.state, "BOTTOMLEFT", -6, -14)
  f.why = W.Text(f, "title")
  f.why:SetWidth(STRIP_W - 28)
  f.why:SetTextColor(0.95, 0.93, 0.88)
  f.why:SetPoint("TOPLEFT", f.lineTop, "BOTTOMLEFT", 14, -12)
  f.lineBot = rule(f, STRIP_W, 0.7)
  f.lineBot:SetPoint("TOPLEFT", f.why, "BOTTOMLEFT", -14, -12)
  f.whyBg = f:CreateTexture(nil, "BORDER", nil, 5)
  f.whyBg:SetPoint("TOPLEFT", f.lineTop, "BOTTOMLEFT", 0, 0)
  f.whyBg:SetPoint("BOTTOMRIGHT", f.lineBot, "TOPRIGHT", 0, 0)
  f.whyBg:SetColorTexture(0, 0, 0, 0.55)

  -- три группы значков под полосой, прямо на рисунке
  local colW = floor((WIDTH - LEFT * 2) / 3)
  f.cards = {}
  for i = 1, 3 do f.cards[i] = infoCard(f, colW) end
  f.colW = colW

  -- низ: три кнопки в ряд по центру, стрелки по углам
  local function bigFont(b)
    local fs = b:GetFontString()
    if fs then
      local tf, _, tfl = fs:GetFont()
      if tf then fs:SetFont(tf, 16, tfl) end
    end
  end
  f.trainer = W.Button(f, "", 250, 40)
  bigFont(f.trainer)
  f.trainer.pin = f.trainer:CreateTexture(nil, "OVERLAY")
  f.trainer.pin:SetSize(24, 24)
  f.trainer.pin:SetPoint("LEFT", 14, 0)
  f.trainer.pin:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
  f.trainer.pin:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  tipButton(f.trainer)
  f.go = W.Button(f, "", 250, 40)
  bigFont(f.go)
  f.go:SetScript("OnClick", function()
    W.Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
    -- при первом открытии окно аддона откроется само, когда это закроется
    local chained = f.after ~= nil
    f:Hide()
    local UI = TJ.UI
    if not chained and not (UI.frame and UI.frame:IsShown()) then
      TJ.skipIntro = true
      TJ:ToggleFrame()
    end
  end)
  f.route = W.Button(f, "", 160, S.btnBig)
  tipButton(f.route)
  local function nav(point, x, delta, arrow)
    local b = CreateFrame("Button", nil, f)
    b:SetSize(36, 36)
    b:SetPoint(point, x, 24)
    b:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. arrow .. "Page-Up")
    b:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. arrow .. "Page-Down")
    b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    b:SetScript("OnClick", function() turn(f, delta) end)
    return b
  end
  f.prev = nav("BOTTOMLEFT", SIDE, -1, "Prev")
  f.next = nav("BOTTOMRIGHT", -SIDE, 1, "Next")
  f:EnableMouseWheel(true)
  f:SetScript("OnMouseWheel", function(s, delta) turn(s, -delta) end)

  -- вкладки профессий справа - те же, что у окна аддона (W.SideTab):
  -- значок на ярлыке, название и навык - в подсказке
  f.tabs = {}
  for i, key in ipairs(TJ.ProfOrder) do
    local t = W.SideTab(f)
    t:SetPoint("TOPLEFT", f, "TOPRIGHT", 0, -40 - (i - 1) * 46)
    t.icon:SetTexture(TJ.Icon(TJ.Profs[key].icon))
    t.check = t:CreateTexture(nil, "OVERLAY", nil, 3)
    t.check:SetSize(16, 16)
    t.check:SetPoint("BOTTOMRIGHT", 5, -4)
    W.SetTex(t.check, "Interface\\RaidFrame\\ReadyCheck-Ready", 0.2, 0.9, 0.2, 1)
    t.key = key
    t:SetScript("OnClick", function()
      W.Sound("IG_ABILITY_PAGE_TURN")
      TJ:ShowChoose(key)
    end)
    f.tabs[i] = t
  end
  f:Hide()
  return f
end

-- Рисунок на всё окно без искажения: лишнее по длинной стороне срезается.
local function coverArt(f, atlas)
  local info = C_Texture.GetAtlasInfo(atlas)
  if not info then return false end
  f.art:SetAtlas(atlas)
  f.glow:SetAtlas(atlas)
  local l, r, t, b = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
  local aw, ah = info.width or 0, info.height or 0
  if l and r and t and b and aw > 0 and ah > 0 then
    local want, have = (WIDTH - 8) / (HEIGHT - 8), aw / ah
    if have > want then
      local cut = (r - l) * (1 - want / have) / 2
      l, r = l + cut, r - cut
    else
      local cut = (b - t) * (1 - have / want) / 2
      t, b = t + cut, b - cut
    end
    f.art:SetTexCoord(l, r, t, b)
    f.glow:SetTexCoord(l, r, t, b)
  end
  return true
end

local function fill(f, key)
  local p = TJ.Profs[key]
  local info = INFO[key] or { "", "", ALL, { 0.3, 0.3, 0.3 } }
  local rank, maxRank, learned = TJ:GetSkill(key)
  f.key = key
  f.title:SetText(T("Какую профессию выбрать"))

  -- фон окна
  local col = info[4]
  f.wash:SetVertexColor(col[1] * 0.35, col[2] * 0.35, col[3] * 0.35, 1)
  local atlas = artAtlas(key)
  local shown = atlas and coverArt(f, atlas) or false
  f.art:SetShown(shown)
  f.glow:SetShown(shown)
  f.emblem:SetShown(not shown)
  if not shown then
    f.emblem:SetTexture(TJ.Icon(p.icon))
    f.emblem:SetAlpha(0.45)
  end

  f.kind:SetText(p.kind == "secondary" and T("Вторичная") or T("Основная"))
  f.badge:SetIcon(TJ.Icon(p.icon))
  f.name:SetText(TJ:N(p))
  f.state:SetText(learned and ("|cff33dd33" .. format(T("Изучена: %d/%d"), rank, maxRank) .. "|r")
    or ("|cffb0aca0" .. T("Не изучена") .. "|r"))
  f.why:SetText(T(info[1]))
  -- где кончается полоса «зачем» (от верха окна)
  local stripEnd = TOP + 26 + 64 + 12 + f.state:GetStringHeight() + 14 + 1 + 12 + f.why:GetStringHeight() + 12 + 1

  -- 1. что создаёт или добывает: предметы с подсказками
  local c1 = f.cards[1]
  c1.head:SetText(p.kind == "gather" and T("Добывает") or T("Создаёт"))
  local items = products(key, MAX_ICONS)
  local list = c1:Row("items", #items, 44)
  for i, id in ipairs(items) do list[i]:SetItem(id) end
  c1.caption:SetText(T(info[2]))

  -- 2. с чем в паре: значки профессий
  local c2 = f.cards[2]
  c2.head:SetText(p.kind == "craft" and T("Сбор к ней") or T("Кому пригодится"))
  local pairs2 = pairKeys(key)
  if #pairs2 > 0 then
    local n = min(#pairs2, MAX_ICONS)
    list = c2:Row("rings", n, 44)
    local names = {}
    for i = 1, n do
      local q = TJ.Profs[pairs2[i]]
      list[i]:SetIcon(TJ.Icon(q.icon))
      names[i] = TJ:N(q)
    end
    c2.caption:SetText(table.concat(names, ", "))
  else
    list = c2:Row("rings", 1, 44)
    list[1]:SetIcon(NONE_ICON)
    c2.caption:SetText(p.kind == "craft" and T("сбор не нужен") or T("сама по себе"))
  end

  -- 3. кому брать: значки классов
  local c3 = f.cards[3]
  c3.head:SetText(T("Кому брать"))
  local who = info[3]
  if type(who) == "table" then
    local n = min(#who, MAX_ICONS)
    list = c3:Row("classes", n, 40)
    local names = {}
    for i = 1, n do
      local tc = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[who[i]]
      if tc then list[i]:SetTexCoord(tc[1], tc[2], tc[3], tc[4]) end
      names[i] = className(who[i])
    end
    c3.caption:SetText(table.concat(names, ", "))
  else
    list = c3:Row("rings", 1, 44)
    list[1]:SetIcon(ALL_ICON)
    c3.caption:SetText(T(who))
  end

  local h = 0
  for _, c in ipairs(f.cards) do h = max(h, 40 + 44 + 12 + c.caption:GetStringHeight() + 6) end
  for i, c in ipairs(f.cards) do
    c:SetHeight(h)
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", LEFT + (i - 1) * f.colW, -(stripEnd + 22))
  end

  -- низ: «учитель», «маршрут» (если изучена), «к аддону» - в ряд по центру
  local npc = TJ:NearestTrainer(key)
  f.trainer:SetText(T("Учитель на карте"))
  f.trainer:SetEnabled(npc ~= nil)
  f.trainer.tip = npc and (TJ:NpcName(npc) .. "\n" .. (TJ:NpcZone(npc) or "") .. "\n" .. T("Щелчок поставит метку и откроет карту."))
    or T("Учителя этой профессии аддон не знает.")
  f.trainer:SetScript("OnClick", function() if npc then TJ:Waypoint(npc, true) end end)
  f.go:SetText(T("Перейти к аддону"))
  f.route:SetText(T("Открыть маршрут"))
  f.route:SetShown(learned)
  f.route.tip = T("Маршрут прокачки этой профессии в окне EasyCraft.")
  f.route:SetScript("OnClick", function() f:Hide(); TJ.UI:Open(key) end)
  f.trainer:ClearAllPoints()
  f.go:ClearAllPoints()
  f.route:ClearAllPoints()
  if learned then
    f.route:SetPoint("BOTTOM", 0, 29)
    f.trainer:SetPoint("RIGHT", f.route, "LEFT", -10, 0)
    f.go:SetPoint("LEFT", f.route, "RIGHT", 10, 0)
    f.trainer:SetWidth(210)
    f.go:SetWidth(210)
  else
    f.trainer:SetPoint("BOTTOM", -131, 22)
    f.go:SetPoint("BOTTOM", 131, 22)
    f.trainer:SetWidth(250)
    f.go:SetWidth(250)
  end

  for _, t in ipairs(f.tabs) do
    local q = TJ.Profs[t.key]
    local r2, m2, l2 = TJ:GetSkill(t.key)
    t.tip = TJ:N(q)
    t.tip2 = l2 and format("%d/%d", r2, m2) or T("Не изучена")
    t:SetChecked(t.key == key)
    t.check:SetShown(l2 and true or false)
  end
end

-- Открыть окно выбора на профессии key (или на той, что была; первый раз -
-- на первой неизученной).
-- after - что сделать, когда окно закроют (любым способом), один раз.
function TJ:ShowChoose(key, after)
  if not win then
    win = build()
    win:SetScript("OnHide", function(s)
      local fn = s.after
      s.after = nil
      if fn then TJ:Safe(fn) end
    end)
  end
  if after then win.after = after end
  if not key then
    key = win.key
    if not key then
      for _, k in ipairs(self.ProfOrder) do
        if not self.char.profs[k] then key = k; break end
      end
    end
  end
  key = key or self.ProfOrder[1]
  self:Safe(fill, win, key)
  win:Show()
end

function TJ:ToggleChoose()
  if win and win:IsShown() then win:Hide() else self:ShowChoose() end
end

-- Главная у персонажа без профессий: одна карточка с кнопкой окна выбора.
function C:BuildChoose(UI)
  local c = UI:Card("current")
  c:Head({ ring = "Interface\\Icons\\INV_Misc_Book_11" }, T("Какую профессию взять"),
    { { T("Основных можно взять две, вторичные - все три. Посмотри, что даёт каждая."), "body" } })
  c:Buttons({ { text = T("Выбор профессии"), w = 220, onClick = function() TJ:ShowChoose() end } })
  c:Text(T("Как только выучишь профессию, здесь появится её маршрут прокачки: что делать сейчас, сколько и из чего."), "small")
  UI:End(c)
end
