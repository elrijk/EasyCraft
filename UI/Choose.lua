local _, TJ = ...
local W, C, T = TJ.W, TJ.Content, TJ.T
local format, floor, min = string.format, math.floor, math.min

-------------------------------------------------------------------------------
--  Выбор профессии: отдельное окно-витрина.
--  Справа у окна - вкладки всех профессий: значок и название (изученные - с
--  галочкой). В окне: вид профессии, крупное название, одна строка «зачем
--  она», три строки преимуществ (что создаёт, с чем в паре, кому брать - со
--  значками классов и профессий прямо в тексте), что из неё получается
--  (предметы с подсказками), ниже - изучена ли и кнопки «учитель на карте» и
--  «маршрут». Внизу окна - «Назад» и «Дальше».
--  Фон - рисунок профессии из окна профессий игры: целиком, без обрезки,
--  прижат к правому нижнему углу. Нет рисунка - крупный значок профессии.
--  Открывается кнопкой «Выбор профессии» на вкладке «Профессии» и при
--  первом открытии аддона (UI/Intro.lua).
-------------------------------------------------------------------------------
local WIDTH, HEIGHT = 520, 640
local LEFT = 36 -- левый край содержимого
local ROW_W = WIDTH - LEFT * 2 -- ширина строк и линий
local TAB_W, TAB_H, TAB_STEP = 178, 34, 37

-- Строка «зачем», что создаёт (добывает), кому брать (текст или список
-- классов), цвет фона.
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
local KIND = { craft = "Ремесло", gather = "Сбор", secondary = "Вторичная" }
local SLOT = { craft = "основная, можно взять две", gather = "основная, можно взять две", secondary = "не занимает место основных" }
local CLASS_RU = { WARRIOR = "Воин", PALADIN = "Паладин", HUNTER = "Охотник", ROGUE = "Разбойник", PRIEST = "Жрец",
  SHAMAN = "Шаман", MAGE = "Маг", WARLOCK = "Чернокнижник", DRUID = "Друид" }
-- Рисунки окна профессий игры: имя профессии в названии атласа.
local ART = { alchemy = "Alchemy", blacksmithing = "Blacksmithing", enchanting = "Enchanting", engineering = "Engineering",
  leatherworking = "Leatherworking", tailoring = "Tailoring", mining = "Mining", herbalism = "Herbalism",
  skinning = "Skinning", cooking = "Cooking", fishing = "Fishing" }
local ART_ALT = { firstaid = { "FirstAid", "First-Aid", "Firstaid", "First Aid" } }
local ART_KINDS = { "Professions-Specializations-Background-%s", "Professions-Recipe-Background-%s" }
local MAKE_ICON, PAIR_ICON, WHO_ICON = "Interface\\Icons\\INV_Misc_Gear_01", "Interface\\Icons\\INV_Misc_Bag_08", "Interface\\Icons\\Achievement_Character_Human_Male"
local CLASS_TEX = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"

local function artAtlas(key)
  local names = ART_ALT[key] or { ART[key] }
  for _, n in ipairs(names) do
    for _, k in ipairs(ART_KINDS) do
      local name = format(k, n)
      if W.HasAtlas(name) then return name end
    end
  end
end

-- Значок в строке текста: обычный (файл значка) и значок класса.
local function iconTag(path)
  return format("|T%s:16:16:0:0:64:64:5:59:5:59|t ", tostring(path))
end
local function classTag(token)
  local c = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[token]
  if not c then return "" end
  return format("|T%s:16:16:0:0:256:256:%d:%d:%d:%d|t ", CLASS_TEX, c[1] * 256, c[2] * 256, c[3] * 256, c[4] * 256)
end
local function className(token)
  if TJ.IsRU then return CLASS_RU[token] or token end
  return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token]) or T(CLASS_RU[token] or token)
end

-- Кому брать: «[значок] Воин  [значок] Паладин» или строка как есть.
local function whoText(who)
  if type(who) ~= "table" then return T(who) end
  local parts = {}
  for _, token in ipairs(who) do parts[#parts + 1] = classTag(token) .. className(token) end
  return table.concat(parts, "   ")
end

-- С чем профессия в паре: сбор для ремесла, ремёсла для сбора - со значками.
local function pairText(key)
  local p = TJ.Profs[key]
  local function name(k)
    local q = TJ.Profs[k]
    return iconTag(TJ.Icon(q.icon)) .. TJ:N(q)
  end
  if p.pair and TJ.Profs[p.pair] then return name(p.pair) end
  local users = {}
  for _, k in ipairs(TJ.ProfOrder) do
    if TJ.Profs[k].pair == key then users[#users + 1] = name(k) end
  end
  if #users > 0 then return table.concat(users, "   ") end
  return p.kind == "craft" and T("сбор не нужен") or T("сама по себе")
end

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
  if #all <= limit then return all end
  local out = {}
  for i = 1, limit do out[i] = all[1 + floor((i - 1) * (#all - 1) / (limit - 1) + 0.5)] end
  return out
end

local function line(parent, w)
  local t = parent:CreateTexture(nil, "ARTWORK")
  t:SetSize(w, 1)
  t:SetColorTexture(0.75, 0.6, 0.3, 0.7)
  return t
end

local function bigFont(fs, size)
  local file, _, flags = fs:GetFont()
  if file then fs:SetFont(file, size, flags) end
  fs:SetShadowOffset(2, -2)
  fs:SetShadowColor(0, 0, 0, 0.9)
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

local function build()
  local f = CreateFrame("Frame", "EasyCraftChooseFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  f:SetSize(WIDTH, HEIGHT)
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
  W.Backdrop(f, "Interface\\Buttons\\WHITE8X8", nil, 16, 0.02, 0.02, 0.03, 1, 0.75, 0.6, 0.3, 1)
  tinsert(UISpecialFrames, "EasyCraftChooseFrame")

  -- фон: цвет профессии, рисунок целиком в правом нижнему углу, затемнение
  f.wash = f:CreateTexture(nil, "BORDER")
  f.wash:SetPoint("TOPLEFT", 4, -4)
  f.wash:SetPoint("BOTTOMRIGHT", -4, 4)
  f.art = f:CreateTexture(nil, "BORDER", nil, 1)
  f.art:SetPoint("BOTTOMRIGHT", -4, 4)
  f.artGlow = f:CreateTexture(nil, "BORDER", nil, 2) -- второй слой сложением: бледный рисунок заметнее
  f.artGlow:SetAllPoints(f.art)
  f.artGlow:SetBlendMode("ADD")
  f.artGlow:SetAlpha(0.5)
  f.emblem = f:CreateTexture(nil, "BORDER", nil, 2)
  f.emblem:SetSize(300, 300)
  f.emblem:SetPoint("BOTTOMRIGHT", -20, 60)
  f.emblem:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  f.shade = f:CreateTexture(nil, "BORDER", nil, 3) -- сверху темнее: там заголовок и название
  f.shade:SetPoint("TOPLEFT", 4, -4)
  f.shade:SetPoint("BOTTOMRIGHT", -4, 4)
  f.shade:SetColorTexture(1, 1, 1, 1)
  local ok = CreateColor and pcall(f.shade.SetGradient, f.shade, "VERTICAL", CreateColor(0, 0, 0, 0.25), CreateColor(0, 0, 0, 0.8))
  if not ok then f.shade:SetColorTexture(0, 0, 0, 0.5) end

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 0, 0)

  -- шапка окна
  f.head = W.Text(f, "huge", false)
  f.head:SetPoint("TOP", 0, -20)
  f.head:SetJustifyH("CENTER")
  bigFont(f.head, 22)
  local hl = line(f, 240)
  hl:SetPoint("TOP", f.head, "BOTTOM", 0, -8)

  -- значок профессии и название - одной строкой; рядом с названием серым -
  -- основная она или вторичная
  f.badge = W.RingIcon(f, 48)
  f.badge:SetPoint("TOPLEFT", LEFT + 2, -76)
  f.name = W.Text(f, "huge", false)
  f.name:SetPoint("LEFT", f.badge, "RIGHT", 14, 0)
  bigFont(f.name, 34)
  f.kind = W.Text(f, "body", false)
  f.kind:SetTextColor(0.62, 0.62, 0.62)
  f.kind:SetPoint("BOTTOMLEFT", f.name, "BOTTOMRIGHT", 12, 5)
  f.lineTop = line(f, ROW_W)
  f.lineTop:SetPoint("TOPLEFT", f.badge, "BOTTOMLEFT", -2, -14)
  f.why = W.Text(f, "title")
  f.why:SetWidth(ROW_W - 20)
  f.why:SetTextColor(W.LIGHT[1], W.LIGHT[2], W.LIGHT[3])
  f.why:SetPoint("TOPLEFT", f.lineTop, "BOTTOMLEFT", 10, -10)
  f.lineBot = line(f, ROW_W)
  f.lineBot:SetPoint("TOPLEFT", f.why, "BOTTOMLEFT", -10, -10)
  f.whyBg = f:CreateTexture(nil, "BORDER", nil, 5)
  f.whyBg:SetPoint("TOPLEFT", f.lineTop, "BOTTOMLEFT", 0, 0)
  f.whyBg:SetPoint("BOTTOMRIGHT", f.lineBot, "TOPRIGHT", 0, 0)
  f.whyBg:SetColorTexture(0, 0, 0, 0.5)

  -- три строки преимуществ, как характеристики в окне персонажа: тёмная
  -- полоса, значок, подпись золотом слева, значение светлым справа
  f.chips = {}
  for i = 1, 3 do
    local c = CreateFrame("Frame", nil, f)
    c:SetSize(ROW_W, 38)
    if i == 1 then c:SetPoint("TOPLEFT", f.lineBot, "BOTTOMLEFT", 0, -12)
    else c:SetPoint("TOPLEFT", f.chips[i - 1], "BOTTOMLEFT", 0, -4) end
    c.bg = c:CreateTexture(nil, "BACKGROUND")
    c.bg:SetAllPoints()
    c.bg:SetColorTexture(0, 0, 0, 0.5)
    c.icon = W.RingIcon(c, 24)
    c.icon:SetPoint("LEFT", 10, 0)
    c.label = W.Text(c, "head", false)
    c.label:SetPoint("LEFT", c.icon, "RIGHT", 12, 0)
    c.value = W.Text(c, "body")
    c.value:SetWidth(270)
    c.value:SetJustifyH("RIGHT")
    c.value:SetJustifyV("MIDDLE")
    c.value:SetPoint("RIGHT", -10, 0)
    f.chips[i] = c
  end

  -- что получится: предметы с подсказками
  f.madeHead = W.Text(f, "small", false)
  f.madeHead:SetPoint("TOPLEFT", f.chips[3], "BOTTOMLEFT", 0, -14)
  f.made = {}
  for i = 1, 7 do
    local b = W.ItemIcon(f, 36)
    b:SetPoint("TOPLEFT", f.madeHead, "BOTTOMLEFT", 6 + (i - 1) * 52, -12)
    f.made[i] = b
  end

  -- под всем блоком: изучена ли, учитель и маршрут
  f.stateLine = line(f, ROW_W)
  f.stateLine:SetPoint("TOPLEFT", f.madeHead, "BOTTOMLEFT", 0, -12 - 48 - 14)
  f.state = W.Text(f, "title", false)
  f.state:SetPoint("TOPLEFT", f.stateLine, "BOTTOMLEFT", 0, -14)
  f.trainer = W.Button(f, "", 190, W.S.btnBig)
  f.trainer:SetPoint("TOPRIGHT", f.stateLine, "BOTTOMRIGHT", 0, -8)
  f.route = W.Button(f, "", 190, W.S.btnBig)
  f.route:SetPoint("TOPRIGHT", f.trainer, "BOTTOMRIGHT", 0, -6)
  tipButton(f.trainer)
  tipButton(f.route)

  -- внизу окна: листать профессии (и колесом мыши)
  local function nav(text, point, x, delta, arrow)
    local b = W.Button(f, text, 150, 30)
    b:SetPoint(point, x, 18)
    local a = b:CreateTexture(nil, "OVERLAY")
    a:SetSize(26, 26)
    a:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. arrow .. "Page-Up")
    a:SetPoint(delta < 0 and "LEFT" or "RIGHT", delta < 0 and 4 or -4, 0)
    b:SetScript("OnClick", function() turn(f, delta) end)
    return b
  end
  f.prev = nav(T("Назад"), "BOTTOMLEFT", LEFT, -1, "Prev")
  f.next = nav(T("Дальше"), "BOTTOMRIGHT", -LEFT, 1, "Next")
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

local function fill(f, key)
  local p = TJ.Profs[key]
  local info = INFO[key] or { "", "", ALL, { 0.3, 0.3, 0.3 } }
  local rank, maxRank, learned = TJ:GetSkill(key)
  f.key = key

  -- фон: рисунок целиком, с сохранением пропорций, в правом нижнем углу
  local col = info[4]
  f.wash:SetColorTexture(col[1] * 0.45, col[2] * 0.45, col[3] * 0.45, 1)
  local atlas = artAtlas(key)
  local shown = false
  if atlas then
    local ai = C_Texture.GetAtlasInfo(atlas)
    local aw, ah = ai and ai.width or 0, ai and ai.height or 0
    if aw > 0 and ah > 0 then
      local k = min((WIDTH - 8) / aw, (HEIGHT - 8) / ah)
      f.art:SetAtlas(atlas)
      f.art:SetSize(floor(aw * k), floor(ah * k))
      f.artGlow:SetAtlas(atlas)
      shown = true
    end
  end
  f.art:SetShown(shown)
  f.artGlow:SetShown(shown)
  f.emblem:SetShown(not shown)
  if not shown then
    f.emblem:SetTexture(TJ.Icon(p.icon))
    f.emblem:SetAlpha(0.45)
  end

  f.head:SetText(format(T("Профессий: %d"), #TJ.ProfOrder))
  f.badge:SetIcon(TJ.Icon(p.icon))
  f.kind:SetText(p.kind == "secondary" and T("Вторичная") or T("Основная"))
  f.name:SetText(TJ:N(p))
  f.why:SetText(T(info[1]))

  local gather = p.kind == "gather"
  local chips = {
    { MAKE_ICON, gather and T("Добывает") or T("Создаёт"), T(info[2]) },
    { PAIR_ICON, p.kind == "craft" and T("Сбор к ней") or T("Кому пригодится"), pairText(key) },
    { WHO_ICON, T("Кому брать"), whoText(info[3]) },
  }
  for i, c in ipairs(f.chips) do
    local d = chips[i]
    c.icon:SetIcon(d[1])
    c.label:SetText(d[2])
    c.value:SetText(d[3])
  end

  local items = products(key, #f.made)
  f.madeHead:SetText(T("Что получится (наведи на значок)"))
  for i, b in ipairs(f.made) do
    if items[i] then b:SetItem(items[i]); b:Show() else b:Hide() end
  end

  f.state:SetText(learned and ("|cff33dd33" .. format(T("Изучена: %d/%d"), rank, maxRank) .. "|r")
    or ("|cff9d9d9d" .. T("Не изучена") .. "|r"))

  local npc = TJ:NearestTrainer(key)
  f.trainer:SetText(T("Учитель на карте"))
  f.trainer:SetEnabled(npc ~= nil)
  f.trainer.tip = npc and (TJ:NpcName(npc) .. "\n" .. (TJ:NpcZone(npc) or "") .. "\n" .. T("Щелчок поставит метку и откроет карту."))
    or T("Учителя этой профессии аддон не знает.")
  f.trainer:SetScript("OnClick", function() if npc then TJ:Waypoint(npc, true) end end)
  f.route:SetText(T("Открыть маршрут"))
  f.route:SetShown(learned)
  f.route.tip = T("Маршрут прокачки этой профессии в окне EasyCraft.")
  f.route:SetScript("OnClick", function() f:Hide(); TJ.UI:Open(key) end)

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
