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
local WIDTH = 760
local SIDE = 28 -- поля окна слева и справа
local GAP = 12 -- между блоками
local INNER = WIDTH - SIDE * 2
local HERO_H = 330 -- примерная высота панели профессии (точная - по содержимому)
local STRIP_W = 470 -- ширина полосы «зачем»
local TAB_W, TAB_H, TAB_STEP = 178, 34, 37
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
  f:SetSize(WIDTH, 560)
  f:SetPoint("CENTER", -TAB_W / 2, 20)
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetScale(TJ.settings.scale or 1)
  -- рамка и фон - как у окна знакомства
  W.Backdrop(f, "Interface\\Buttons\\WHITE8X8", nil, 16, 0.04, 0.03, 0.02, 1, 0.75, 0.6, 0.3, 1)
  tinsert(UISpecialFrames, "EasyCraftChooseFrame")
  local bg = f:CreateTexture(nil, "BORDER")
  bg:SetPoint("TOPLEFT", 4, -4)
  bg:SetPoint("BOTTOMRIGHT", -4, 4)
  bg:SetColorTexture(1, 1, 1, 1)
  local ok = CreateColor and pcall(bg.SetGradient, bg, "VERTICAL", CreateColor(0.03, 0.025, 0.02, 1), CreateColor(0.2, 0.14, 0.08, 1))
  if not ok then bg:SetColorTexture(0.1, 0.075, 0.05, 1) end
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 0, 0)

  -- шапка окна
  f.title = W.Text(f, "huge", false)
  f.title:SetJustifyH("CENTER")
  f.title:SetPoint("TOP", 0, -26)
  local file, _, flags = f.title:GetFont()
  if file then f.title:SetFont(file, 24, flags) end
  f.rule = rule(f, 360)
  f.rule:SetPoint("TOP", f.title, "BOTTOM", 0, -10)

  -- панель профессии: рисунок на всю панель, слева текст
  local hero = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
  W.Backdrop(hero, "Interface\\Buttons\\WHITE8X8", nil, 14, 0.03, 0.025, 0.02, 1, 0.75, 0.6, 0.3, 1)
  hero:SetSize(INNER, HERO_H)
  f.hero = hero
  hero.wash = hero:CreateTexture(nil, "BORDER")
  hero.wash:SetPoint("TOPLEFT", 4, -4)
  hero.wash:SetPoint("BOTTOMRIGHT", -4, 4)
  hero.art = hero:CreateTexture(nil, "BORDER", nil, 1)
  hero.art:SetPoint("TOPLEFT", 4, -4)
  hero.art:SetPoint("BOTTOMRIGHT", -4, 4)
  hero.glow = hero:CreateTexture(nil, "BORDER", nil, 2) -- второй слой сложением: бледный рисунок заметнее
  hero.glow:SetAllPoints(hero.art)
  hero.glow:SetBlendMode("ADD")
  hero.glow:SetAlpha(0.7)
  hero.emblem = hero:CreateTexture(nil, "BORDER", nil, 2)
  hero.emblem:SetSize(HERO_H - 30, HERO_H - 30)
  hero.emblem:SetPoint("RIGHT", -30, 0)
  hero.emblem:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  hero.shade = hero:CreateTexture(nil, "BORDER", nil, 3) -- слева темнее: там текст
  hero.shade:SetPoint("TOPLEFT", 4, -4)
  hero.shade:SetPoint("BOTTOMRIGHT", -4, 4)
  hero.shade:SetColorTexture(1, 1, 1, 1)
  ok = CreateColor and pcall(hero.shade.SetGradient, hero.shade, "HORIZONTAL", CreateColor(0, 0, 0, 0.85), CreateColor(0, 0, 0, 0.1))
  if not ok then hero.shade:SetColorTexture(0, 0, 0, 0.45) end
  -- основная она или вторичная - мелко над названием
  hero.kind = W.Text(hero, "head", false)
  hero.kind:SetPoint("TOPLEFT", 26, -20)
  hero.kind:SetShadowOffset(1, -1)
  hero.kind:SetShadowColor(0, 0, 0, 0.9)
  hero.badge = W.RingIcon(hero, 56)
  hero.badge:SetPoint("TOPLEFT", 24, -44)
  hero.name = W.Text(hero, "huge", false)
  hero.name:SetPoint("LEFT", hero.badge, "RIGHT", 16, 0)
  file, _, flags = hero.name:GetFont()
  if file then hero.name:SetFont(file, 44, flags) end
  hero.name:SetShadowOffset(2, -2)
  hero.name:SetShadowColor(0, 0, 0, 0.9)
  -- строка «зачем» на тёмной полосе между двумя линиями
  hero.lineTop = rule(hero, STRIP_W, 0.7)
  hero.lineTop:SetPoint("TOPLEFT", hero.badge, "BOTTOMLEFT", -4, -16)
  hero.why = W.Text(hero, "title")
  hero.why:SetWidth(STRIP_W - 28)
  hero.why:SetTextColor(0.95, 0.93, 0.88)
  hero.why:SetPoint("TOPLEFT", hero.lineTop, "BOTTOMLEFT", 14, -12)
  hero.lineBot = rule(hero, STRIP_W, 0.7)
  hero.lineBot:SetPoint("TOPLEFT", hero.why, "BOTTOMLEFT", -14, -12)
  hero.whyBg = hero:CreateTexture(nil, "BORDER", nil, 5)
  hero.whyBg:SetPoint("TOPLEFT", hero.lineTop, "BOTTOMLEFT", 0, 0)
  hero.whyBg:SetPoint("BOTTOMRIGHT", hero.lineBot, "TOPRIGHT", 0, 0)
  hero.whyBg:SetColorTexture(0, 0, 0, 0.55)
  hero.route = W.Button(hero, "", 180, S.btn)
  hero.route:SetPoint("TOPRIGHT", -14, -14)
  tipButton(hero.route)

  -- три блока-инфографики
  -- лежат на панели профессии, под полосой «зачем»
  local colW = floor((INNER - 40) / 3)
  f.cards = {}
  for i = 1, 3 do
    f.cards[i] = infoCard(f, colW)
    f.cards[i]:SetFrameLevel(hero:GetFrameLevel() + 3)
  end
  f.colW = colW

  -- низ: изучена ли, крупная кнопка учителя, листание
  f.state = W.Text(f, "title", false)
  f.state:SetJustifyH("CENTER")
  f.trainer = W.Button(f, "", 300, 40)
  f.trainer:SetPoint("BOTTOM", 0, 22)
  local tfs = f.trainer:GetFontString()
  if tfs then
    local tf, _, tfl = tfs:GetFont()
    if tf then tfs:SetFont(tf, 16, tfl) end
  end
  f.trainer.pin = f.trainer:CreateTexture(nil, "OVERLAY")
  f.trainer.pin:SetSize(24, 24)
  f.trainer.pin:SetPoint("LEFT", 14, 0)
  f.trainer.pin:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
  f.trainer.pin:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  tipButton(f.trainer)
  f.state:SetPoint("BOTTOM", f.trainer, "TOP", 0, 10)
  local function nav(text, point, x, delta, arrow)
    local b = W.Button(f, text, 140, 30)
    b:SetPoint(point, x, 27)
    local a = b:CreateTexture(nil, "OVERLAY")
    a:SetSize(26, 26)
    a:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. arrow .. "Page-Up")
    a:SetPoint(delta < 0 and "LEFT" or "RIGHT", delta < 0 and 4 or -4, 0)
    b:SetScript("OnClick", function() turn(f, delta) end)
    return b
  end
  f.prev = nav(T("Назад"), "BOTTOMLEFT", SIDE, -1, "Prev")
  f.next = nav(T("Дальше"), "BOTTOMRIGHT", -SIDE, 1, "Next")
  f:EnableMouseWheel(true)
  f:SetScript("OnMouseWheel", function(s, delta) turn(s, -delta) end)

  -- вкладки профессий справа у окна: значок и название
  f.tabs = {}
  for i, key in ipairs(TJ.ProfOrder) do
    local b = CreateFrame("Button", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
    b:SetSize(TAB_W, TAB_H)
    b:SetPoint("TOPLEFT", f, "TOPRIGHT", -3, -44 - (i - 1) * TAB_STEP)
    W.Backdrop(b, "Interface\\Buttons\\WHITE8X8", nil, 12, 0.06, 0.05, 0.04, 0.95, 0.5, 0.4, 0.22, 1)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(24, 24)
    b.icon:SetPoint("LEFT", 8, 0)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.icon:SetTexture(TJ.Icon(TJ.Profs[key].icon))
    b.text = W.Text(b, "body", false)
    b.text:SetPoint("LEFT", b.icon, "RIGHT", 8, 0)
    b.text:SetPoint("RIGHT", -24, 0)
    b.check = b:CreateTexture(nil, "OVERLAY")
    b.check:SetSize(16, 16)
    b.check:SetPoint("RIGHT", -6, 0)
    W.SetTex(b.check, "Interface\\RaidFrame\\ReadyCheck-Ready", 0.2, 0.9, 0.2, 1)
    local hlt = b:CreateTexture(nil, "HIGHLIGHT")
    hlt:SetPoint("TOPLEFT", 3, -3)
    hlt:SetPoint("BOTTOMRIGHT", -3, 3)
    hlt:SetColorTexture(1, 0.82, 0, 0.12)
    b.key = key
    b:SetScript("OnClick", function()
      W.Sound("IG_ABILITY_PAGE_TURN")
      TJ:ShowChoose(key)
    end)
    f.tabs[i] = b
  end
  f:Hide()
  return f
end

-- Рисунок на всю панель без искажения: лишнее по длинной стороне срезается.
local function coverArt(hero, atlas, height)
  local info = C_Texture.GetAtlasInfo(atlas)
  if not info then return false end
  hero.art:SetAtlas(atlas)
  hero.glow:SetAtlas(atlas)
  local l, r, t, b = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
  local aw, ah = info.width or 0, info.height or 0
  if l and r and t and b and aw > 0 and ah > 0 then
    local want, have = (INNER - 8) / ((height or HERO_H) - 8), aw / ah
    if have > want then
      local cut = (r - l) * (1 - want / have) / 2
      l, r = l + cut, r - cut
    else
      local cut = (b - t) * (1 - have / want) / 2
      t, b = t + cut, b - cut
    end
    hero.art:SetTexCoord(l, r, t, b)
    hero.glow:SetTexCoord(l, r, t, b)
  end
  return true
end

local function fill(f, key)
  local p = TJ.Profs[key]
  local info = INFO[key] or { "", "", ALL, { 0.3, 0.3, 0.3 } }
  local rank, maxRank, learned = TJ:GetSkill(key)
  f.key = key
  f.title:SetText(T("Какую профессию выбрать"))
  local y = 26 + f.title:GetStringHeight() + 10 + 1 + 20

  -- панель профессии
  local hero = f.hero
  hero:ClearAllPoints()
  hero:SetPoint("TOPLEFT", SIDE, -y)
  local col = info[4]
  hero.wash:SetColorTexture(col[1] * 0.4, col[2] * 0.4, col[3] * 0.4, 1)
  local atlas = artAtlas(key)
  local shown = atlas and coverArt(hero, atlas) or false
  hero.art:SetShown(shown)
  hero.glow:SetShown(shown)
  hero.emblem:SetShown(not shown)
  if not shown then
    hero.emblem:SetTexture(TJ.Icon(p.icon))
    hero.emblem:SetAlpha(0.5)
  end
  hero.badge:SetIcon(TJ.Icon(p.icon))
  hero.name:SetText(TJ:N(p))
  hero.kind:SetText(p.kind == "secondary" and T("Вторичная") or T("Основная"))
  hero.why:SetText(T(info[1]))
  -- где кончается полоса «зачем» (от верха панели)
  local stripEnd = 44 + 56 + 16 + 1 + 12 + hero.why:GetStringHeight() + 12 + 1
  hero.route:SetText(T("Открыть маршрут"))
  hero.route:SetShown(learned)
  hero.route.tip = T("Маршрут прокачки этой профессии в окне EasyCraft.")
  hero.route:SetScript("OnClick", function() f:Hide(); TJ.UI:Open(key) end)

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

  -- группы значков - на панели под полосой; высота панели - по содержимому
  local h = 0
  for _, c in ipairs(f.cards) do h = max(h, 40 + 44 + 12 + c.caption:GetStringHeight() + 6) end
  for i, c in ipairs(f.cards) do
    c:SetHeight(h)
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", SIDE + 20 + (i - 1) * f.colW, -(y + stripEnd + 10))
  end
  local heroH = stripEnd + 10 + h + 16
  hero:SetHeight(heroH)
  if shown then coverArt(hero, atlas, heroH) end
  y = y + heroH + 20

  -- низ
  f.state:SetText(learned and ("|cff33dd33" .. format(T("Изучена: %d/%d"), rank, maxRank) .. "|r")
    or ("|cff9d9d9d" .. T("Не изучена") .. "|r"))
  local npc = TJ:NearestTrainer(key)
  f.trainer:SetText(T("Учитель на карте"))
  f.trainer:SetEnabled(npc ~= nil)
  f.trainer.tip = npc and (TJ:NpcName(npc) .. "\n" .. (TJ:NpcZone(npc) or "") .. "\n" .. T("Щелчок поставит метку и откроет карту."))
    or T("Учителя этой профессии аддон не знает.")
  f.trainer:SetScript("OnClick", function() if npc then TJ:Waypoint(npc, true) end end)
  f:SetHeight(y + f.state:GetStringHeight() + 10 + 40 + 22)

  for _, b in ipairs(f.tabs) do
    local sel = b.key == key
    b.text:SetText(TJ:N(TJ.Profs[b.key]))
    if sel then
      b:SetBackdropColor(0.22, 0.16, 0.05, 1)
      b:SetBackdropBorderColor(1, 0.82, 0, 1)
      b.text:SetTextColor(1, 0.82, 0)
    else
      b:SetBackdropColor(0.06, 0.05, 0.04, 0.95)
      b:SetBackdropBorderColor(0.5, 0.4, 0.22, 1)
      b.text:SetTextColor(W.LIGHT[1], W.LIGHT[2], W.LIGHT[3])
    end
    b.check:SetShown(TJ.char.profs[b.key] ~= nil)
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
