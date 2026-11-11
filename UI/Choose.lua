local _, TJ = ...
local W, C, T = TJ.W, TJ.Content, TJ.T
local format, floor = string.format, math.floor

-------------------------------------------------------------------------------
--  Выбор профессии: отдельное окно-витрина. На весь фон - картинка выбранной
--  профессии, слева крупное название, одна строка «зачем она» и три
--  преимущества значками, ниже - что из неё получается (предметы с
--  подсказками). Внизу ряд из всех профессий: щелчок переключает.
--  Открывается кнопкой «Выбор профессии» на вкладке «Профессии» (всегда) и
--  с главной у персонажа без профессий.
--  Картинка: фон окна профессий игры, если он есть в клиенте; иначе крупный
--  значок профессии и её цвет.
-------------------------------------------------------------------------------
local WIDTH, HEIGHT = 940, 580
local LEFT = 56 -- левый край текста
local TEXT_W = 400

-- Строка «зачем», что создаёт (добывает), кому нужна, цвет фона.
local INFO = {
  alchemy = { "Расходники нужны всем и всегда: варишь себе и на аукцион.", "Зелья, эликсиры, настои", "Всем классам", { 0.45, 0.2, 0.6 } },
  blacksmithing = { "Куёшь оружие и тяжёлую броню, точишь клинки.", "Оружие, кольчуга, латы", "Воин, паладин", { 0.7, 0.3, 0.1 } },
  enchanting = { "Усиливаешь экипировку чарами. Материалы - из распылённых вещей.", "Чары, масла, жезлы", "Всем классам", { 0.3, 0.3, 0.8 } },
  engineering = { "Бомбы и устройства, которых нет больше ни у кого.", "Бомбы, устройства, ружья", "Всем, особенно в PvP", { 0.7, 0.6, 0.1 } },
  leatherworking = { "Шьёшь кожаную и кольчужную броню из шкур.", "Кожаная и кольчужная броня", "Разбойник, друид, охотник, шаман", { 0.5, 0.3, 0.15 } },
  tailoring = { "Тканевая броня и сумки. Ткань падает с врагов.", "Тканевая броня, сумки", "Маг, жрец, чернокнижник", { 0.6, 0.2, 0.4 } },
  mining = { "Руда и камень с жил по всему миру. Всегда в цене.", "Руда, слитки, камни", "Кузнецам и инженерам", { 0.35, 0.45, 0.55 } },
  herbalism = { "Собираешь травы по пути - продаёшь алхимикам.", "Травы", "Алхимикам", { 0.2, 0.55, 0.2 } },
  skinning = { "Снимаешь шкуры с убитых зверей. Золото с первого уровня.", "Кожа и шкуры", "Кожевникам", { 0.55, 0.4, 0.25 } },
  cooking = { "Еда с бонусами и костёр для лагеря.", "Еда с «Сытостью»", "Всем классам", { 0.7, 0.4, 0.15 } },
  firstaid = { "Лечишься сам, без лекаря и без маны.", "Бинты, лечебные зелья", "Всем классам", { 0.7, 0.15, 0.15 } },
  fishing = { "Рыба для кулинарии и алхимии. Спокойный заработок.", "Рыба", "Всем классам", { 0.1, 0.45, 0.6 } },
}
local KIND = { craft = "Ремесло", gather = "Сбор", secondary = "Вторичная" }
local SLOT = { craft = "основная, можно взять две", gather = "основная, можно взять две", secondary = "не занимает место основных" }
-- Фоны окна профессий игры: имя профессии в названии атласа.
local ART = { alchemy = "Alchemy", blacksmithing = "Blacksmithing", enchanting = "Enchanting", engineering = "Engineering",
  leatherworking = "Leatherworking", tailoring = "Tailoring", mining = "Mining", herbalism = "Herbalism",
  skinning = "Skinning", cooking = "Cooking", fishing = "Fishing" }
local ART_KINDS = { "Professions-Specializations-Background-%s", "Professions-Recipe-Background-%s" }
local MAKE_ICON, PAIR_ICON, WHO_ICON = "Interface\\Icons\\INV_Misc_Gear_01", "Interface\\Icons\\INV_Misc_Bag_08", "Interface\\Icons\\Achievement_Character_Human_Male"

local function artAtlas(key)
  local n = ART[key]
  if not n then return nil end
  for _, k in ipairs(ART_KINDS) do
    local name = format(k, n)
    if W.HasAtlas(name) then return name end
  end
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

-- С чем профессия в паре: сбор для ремесла, ремёсла для сбора.
local function pairText(key)
  local p = TJ.Profs[key]
  if p.pair and TJ.Profs[p.pair] then return TJ:N(TJ.Profs[p.pair]) end
  local users = {}
  for _, k in ipairs(TJ.ProfOrder) do
    if TJ.Profs[k].pair == key then users[#users + 1] = TJ:N(TJ.Profs[k]) end
  end
  if #users > 0 then return table.concat(users, ", ") end
  return p.kind == "craft" and T("сбор не нужен") or T("сама по себе")
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

local win

local function build()
  local f = CreateFrame("Frame", "EasyCraftChooseFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  f:SetSize(WIDTH, HEIGHT)
  f:SetPoint("CENTER", 0, 20)
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetScale(TJ.settings.scale or 1)
  W.Backdrop(f, "Interface\\Buttons\\WHITE8X8", nil, 16, 0.02, 0.02, 0.03, 1, 0.6, 0.48, 0.25, 1)
  tinsert(UISpecialFrames, "EasyCraftChooseFrame")

  -- фон: цвет профессии, картинка, затемнение слева под текст
  f.wash = f:CreateTexture(nil, "BORDER")
  f.wash:SetPoint("TOPLEFT", 4, -4)
  f.wash:SetPoint("BOTTOMRIGHT", -4, 4)
  f.art = f:CreateTexture(nil, "BORDER", nil, 1)
  f.art:SetPoint("TOPRIGHT", -4, -4)
  f.art:SetPoint("BOTTOMRIGHT", -4, 4)
  f.art:SetWidth(floor(WIDTH * 0.68))
  f.emblem = f:CreateTexture(nil, "BORDER", nil, 2)
  f.emblem:SetSize(360, 360)
  f.emblem:SetPoint("RIGHT", -70, 10)
  f.emblem:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  f.shade = f:CreateTexture(nil, "BORDER", nil, 3)
  f.shade:SetPoint("TOPLEFT", 4, -4)
  f.shade:SetPoint("BOTTOMRIGHT", -4, 4)
  f.shade:SetColorTexture(1, 1, 1, 1)
  local ok = CreateColor and pcall(f.shade.SetGradient, f.shade, "HORIZONTAL", CreateColor(0, 0, 0, 0.94), CreateColor(0, 0, 0, 0.1))
  if not ok then f.shade:SetColorTexture(0, 0, 0, 0.55) end
  f.floor = f:CreateTexture(nil, "BORDER", nil, 4) -- затемнение снизу под ряд профессий
  f.floor:SetPoint("BOTTOMLEFT", 4, 4)
  f.floor:SetPoint("BOTTOMRIGHT", -4, 4)
  f.floor:SetHeight(130)
  f.floor:SetColorTexture(1, 1, 1, 1)
  ok = CreateColor and pcall(f.floor.SetGradient, f.floor, "VERTICAL", CreateColor(0, 0, 0, 0.9), CreateColor(0, 0, 0, 0))
  if not ok then f.floor:SetColorTexture(0, 0, 0, 0.5) end

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 0, 0)

  -- шапка окна
  f.head = W.Text(f, "huge", false)
  f.head:SetPoint("TOP", 0, -22)
  f.head:SetJustifyH("CENTER")
  bigFont(f.head, 26)
  local hl = line(f, 260)
  hl:SetPoint("TOP", f.head, "BOTTOM", 0, -8)

  -- слева: вид, название, строка «зачем»
  f.kind = W.Text(f, "head", false)
  f.kind:SetPoint("TOPLEFT", LEFT, -130)
  f.name = W.Text(f, "huge", false)
  f.name:SetPoint("TOPLEFT", f.kind, "BOTTOMLEFT", -2, -6)
  bigFont(f.name, 46)
  f.lineTop = line(f, TEXT_W + 20)
  f.lineTop:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", -8, -14)
  f.why = W.Text(f, "title")
  f.why:SetWidth(TEXT_W)
  f.why:SetTextColor(W.LIGHT[1], W.LIGHT[2], W.LIGHT[3])
  f.why:SetPoint("TOPLEFT", f.lineTop, "BOTTOMLEFT", 10, -10)
  f.lineBot = line(f, TEXT_W + 20)
  f.lineBot:SetPoint("TOPLEFT", f.why, "BOTTOMLEFT", -10, -10)

  -- три преимущества: значок, подпись серым, значение
  f.chips = {}
  for i = 1, 3 do
    local c = CreateFrame("Frame", nil, f)
    c:SetSize(TEXT_W, 34)
    if i == 1 then c:SetPoint("TOPLEFT", f.lineBot, "BOTTOMLEFT", 8, -16)
    else c:SetPoint("TOPLEFT", f.chips[i - 1], "BOTTOMLEFT", 0, -8) end
    c.icon = W.RingIcon(c, 28)
    c.icon:SetPoint("LEFT", 4, 0)
    c.label = W.Text(c, "small", false)
    c.label:SetPoint("TOPLEFT", c.icon, "TOPRIGHT", 12, 2)
    c.value = W.Text(c, "body", false)
    c.value:SetPoint("TOPLEFT", c.label, "BOTTOMLEFT", 0, -2)
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

  -- справа: изучена ли
  f.state = W.Text(f, "title", false)
  f.state:SetPoint("BOTTOMRIGHT", -40, 150)
  f.state:SetJustifyH("RIGHT")

  -- кнопки: учитель и маршрут
  f.trainer = W.Button(f, "", 200, 26)
  f.trainer:SetPoint("BOTTOMRIGHT", -40, 112)
  f.route = W.Button(f, "", 200, 26)
  f.route:SetPoint("RIGHT", f.trainer, "LEFT", -8, 0)
  for _, b in ipairs({ f.trainer, f.route }) do
    b:SetScript("OnEnter", function(s)
      if not s.tip then return end
      GameTooltip:SetOwner(s, "ANCHOR_TOP")
      GameTooltip:SetText(s.tip, 1, 1, 1, 1, true)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end

  -- внизу: все профессии в ряд
  f.picks = {}
  local n, size, step = #TJ.ProfOrder, 44, 60
  local x0 = floor((WIDTH - (n - 1) * step - size) / 2)
  for i, key in ipairs(TJ.ProfOrder) do
    local b = CreateFrame("Button", nil, f)
    b:SetSize(size, size)
    b:SetPoint("BOTTOMLEFT", x0 + (i - 1) * step, 34)
    b.glow = b:CreateTexture(nil, "BACKGROUND")
    b.glow:SetPoint("CENTER")
    b.glow:SetSize(size * 1.9, size * 1.9)
    b.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    b.glow:SetBlendMode("ADD")
    b.glow:SetVertexColor(1, 0.82, 0.2, 0.9)
    b.ring = W.RingIcon(b, size)
    b.ring:SetPoint("CENTER")
    b.ring:SetIcon(TJ.Icon(TJ.Profs[key].icon))
    b.check = b:CreateTexture(nil, "OVERLAY", nil, 3)
    b.check:SetSize(18, 18)
    b.check:SetPoint("BOTTOMRIGHT", 5, -4)
    W.SetTex(b.check, "Interface\\RaidFrame\\ReadyCheck-Ready", 0.2, 0.9, 0.2, 1)
    local hlt = b:CreateTexture(nil, "HIGHLIGHT")
    hlt:SetAllPoints()
    hlt:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    hlt:SetBlendMode("ADD")
    b.key = key
    b:SetScript("OnClick", function()
      W.Sound("IG_ABILITY_PAGE_TURN")
      TJ:ShowChoose(key)
    end)
    b:SetScript("OnEnter", function(s)
      GameTooltip:SetOwner(s, "ANCHOR_TOP")
      GameTooltip:SetText(TJ:N(TJ.Profs[key]), 1, 0.82, 0)
      GameTooltip:AddLine(T(KIND[TJ.Profs[key].kind] or ""), 0.8, 0.8, 0.8)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.picks[i] = b
  end
  f:Hide()
  return f
end

local function fill(f, key)
  local p = TJ.Profs[key]
  local info = INFO[key] or { "", "", "", { 0.3, 0.3, 0.3 } }
  local rank, maxRank, learned = TJ:GetSkill(key)
  f.key = key

  -- фон
  local col = info[4]
  f.wash:SetColorTexture(col[1] * 0.5, col[2] * 0.5, col[3] * 0.5, 1)
  local atlas = artAtlas(key)
  if atlas then
    f.art:SetAtlas(atlas)
    f.art:SetAlpha(0.9)
    f.art:Show()
    f.emblem:Hide()
  else
    f.art:Hide()
    f.emblem:SetTexture(TJ.Icon(p.icon))
    f.emblem:SetAlpha(0.5)
    f.emblem:Show()
  end

  f.head:SetText(format(T("Профессий: %d"), #TJ.ProfOrder))
  f.kind:SetText(T(KIND[p.kind] or "") .. "  |cff9d9d9d" .. T(SLOT[p.kind] or "") .. "|r")
  f.name:SetText(TJ:N(p))
  f.why:SetText(T(info[1]))

  local gather = p.kind == "gather"
  local chips = {
    { MAKE_ICON, gather and T("Добывает") or T("Создаёт"), T(info[2]) },
    { PAIR_ICON, p.kind == "craft" and T("Сбор к ней") or T("Кому пригодится"), pairText(key) },
    { WHO_ICON, T("Кому брать"), T(info[3]) },
  }
  for i, c in ipairs(f.chips) do
    local d = chips[i]
    c.icon:SetIcon(d[1])
    c.label:SetText(d[2])
    c.value:SetText(d[3])
  end

  local items = products(key, #f.made)
  f.madeHead:SetText(#items > 0 and T("Что получится (наведи на значок)") or "")
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

  for _, b in ipairs(f.picks) do
    local sel = b.key == key
    b.glow:SetShown(sel)
    b:SetAlpha(sel and 1 or 0.8)
    b.check:SetShown(TJ.char.profs[b.key] ~= nil)
  end
end

-- Открыть окно выбора на профессии key (или на той, что была; первый раз -
-- на первой неизученной).
function TJ:ShowChoose(key)
  if not win then win = build() end
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
