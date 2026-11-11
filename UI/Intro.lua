local _, ns = ...
local W, T = ns.W, ns.T
local floor, max = math.floor, math.max

-------------------------------------------------------------------------------
--  Знакомство с аддоном одним экраном (тот же вид - в MacroCoach): три
--  главные возможности, «И ещё» и одна кнопка. Показывается при первом
--  открытии; дальше - по кнопке «?» в заголовке окна и из настроек.
-------------------------------------------------------------------------------
local S = W.S
local WIDTH = 760
local SIDE = 28 -- поля окна слева и справа
local GAP = 12 -- между блоками
local COLS = 3

local TITLE = "EasyCraft: профессия до 300 без гайдов"
-- Главное: крупный значок, два-три слова и одна короткая строка.
local KILLER = {
  { "INV_Misc_Book_11", "Шаг за шагом", "Что создать и сколько" },
  { "INV_Misc_Bag_08", "Считает за тебя", "Сумки, банк, почта, альты" },
  { "Trade_BlackSmithing", "Одна кнопка", "Создаёт прямо у окна профессии" },
}
local MORE_HEAD = "И ещё"
-- Остальное: значок и название; что это - в подсказке при наведении.
local MORE = {
  { "INV_Misc_Map_01", "Карта сбора", "Руда и травы, что дают навык, - на карте мира." },
  { "INV_Misc_Coin_02", "Покупки", "Список до учителя с ценами аукциона." },
  { "INV_Scroll_03", "Рецепты", "Что выгодно создавать, очередь и откаты." },
  { "Spell_Fire_Fire", "Лагерь", "Бонусы у костра и где падают чертежи." },
  { "INV_Misc_Book_09", "Выбор профессии", "Что даёт каждая и кому её брать." },
  { "INV_Misc_Note_06", "Учителя", "Напомнит о новом ранге и поставит метку." },
}
local BUTTON = "Поехали"

local win

local function centered(fs, width)
  fs:SetJustifyH("CENTER")
  fs:SetWidth(width)
end

local function rule(parent, w)
  local t = parent:CreateTexture(nil, "ARTWORK")
  t:SetSize(w, 1)
  t:SetColorTexture(0.85, 0.68, 0.3, 0.8)
  return t
end

local function build()
  local f = CreateFrame("Frame", "EasyCraftIntroFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  f:SetSize(WIDTH, 400)
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  W.Backdrop(f, "Interface\\Buttons\\WHITE8X8", nil, 16, 0.04, 0.03, 0.02, 1, 0.75, 0.6, 0.3, 1)
  tinsert(UISpecialFrames, "EasyCraftIntroFrame")
  -- фон: сверху тёплый коричневый, книзу уходит в чёрный
  local bg = f:CreateTexture(nil, "BORDER")
  bg:SetPoint("TOPLEFT", 4, -4)
  bg:SetPoint("BOTTOMRIGHT", -4, 4)
  bg:SetColorTexture(1, 1, 1, 1)
  local ok = CreateColor and pcall(bg.SetGradient, bg, "VERTICAL", CreateColor(0.03, 0.025, 0.02, 1), CreateColor(0.2, 0.14, 0.08, 1))
  if not ok then bg:SetColorTexture(0.1, 0.075, 0.05, 1) end
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 0, 0)

  -- шапка: что за аддон
  f.title = W.Text(f, "huge")
  centered(f.title, WIDTH - SIDE * 2 - 40)
  f.title:SetPoint("TOP", 0, -26)
  local file, _, flags = f.title:GetFont()
  if file then f.title:SetFont(file, 24, flags) end
  f.rule = rule(f, 360)
  f.rule:SetPoint("TOP", f.title, "BOTTOM", 0, -10)
  -- три главные возможности: крупные блоки в золотой рамке
  f.killer = {}
  for i = 1, #KILLER do
    local c = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
    W.Backdrop(c, "Interface\\Buttons\\WHITE8X8", nil, 14, 0.2, 0.14, 0.05, 0.9, 1, 0.82, 0, 1)
    c.icon = W.RingIcon(c, 80)
    c.icon:SetPoint("TOP", 0, -20)
    c.head = W.Text(c, "title")
    c.head:SetJustifyH("CENTER")
    c.head:SetPoint("TOP", c.icon, "BOTTOM", 0, -12)
    c.text = W.Text(c, "body")
    c.text:SetJustifyH("CENTER")
    c.text:SetTextColor(0.92, 0.9, 0.84)
    c.text:SetPoint("TOP", c.head, "BOTTOM", 0, -8)
    f.killer[i] = c
  end

  -- «И ещё»: подзаголовок с линиями по бокам
  f.moreHead = W.Text(f, "head", false)
  f.moreHead:SetJustifyH("CENTER")
  f.moreL, f.moreR = rule(f, 10), rule(f, 10)
  f.moreL:SetColorTexture(0.75, 0.6, 0.3, 0.5)
  f.moreR:SetColorTexture(0.75, 0.6, 0.3, 0.5)

  -- остальное: значок и название под ним, в один ряд; что это - в подсказке
  f.more = {}
  for i = 1, #MORE do
    local c = CreateFrame("Frame", nil, f)
    c:EnableMouse(true)
    c.icon = W.RingIcon(c, 44)
    c.icon:SetPoint("TOP", 0, 0)
    c.head = W.Text(c, "body")
    c.head:SetJustifyH("CENTER")
    c.head:SetTextColor(1, 0.82, 0)
    c.head:SetPoint("TOP", c.icon, "BOTTOM", 0, -8)
    c:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText(T(MORE[i][2]), 1, 0.82, 0)
      GameTooltip:AddLine(T(MORE[i][3]), 1, 1, 1, true)
      GameTooltip:Show()
    end)
    c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.more[i] = c
  end

  -- одна кнопка
  f.go = W.Button(f, "", 220, 32)
  f.go:SetPoint("BOTTOM", 0, 22)
  f.go:SetScript("OnClick", function()
    W.Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
    f:Hide()
  end)
  f:Hide()
  return f
end

local function show(f)
  f.title:SetText(T(TITLE))
  local y = 26 + f.title:GetStringHeight() + 10 + 1 + 24

  -- главные возможности
  local colW = floor((WIDTH - SIDE * 2 - GAP * (COLS - 1)) / COLS)
  local h = 0
  for i, c in ipairs(f.killer) do
    local d = KILLER[i]
    c.icon:SetIcon(ns.Icon(d[1]))
    c.head:SetWidth(colW - 24)
    c.head:SetText(T(d[2]))
    c.text:SetWidth(colW - 28)
    c.text:SetText(T(d[3]))
    h = max(h, 20 + 80 + 12 + c.head:GetStringHeight() + 8 + c.text:GetStringHeight() + 20)
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", SIDE + (i - 1) * (colW + GAP), -y)
    c:SetWidth(colW)
  end
  for _, c in ipairs(f.killer) do c:SetHeight(h) end
  y = y + h + 24

  -- подзаголовок с линиями по бокам
  f.moreHead:SetText(T(MORE_HEAD))
  f.moreHead:ClearAllPoints()
  f.moreHead:SetPoint("TOP", f, "TOP", 0, -y)
  local tw = f.moreHead:GetStringWidth() or 60
  local lw = floor((WIDTH - SIDE * 2 - tw - 32) / 2)
  f.moreL:SetWidth(lw)
  f.moreR:SetWidth(lw)
  f.moreL:ClearAllPoints()
  f.moreL:SetPoint("RIGHT", f.moreHead, "LEFT", -16, 0)
  f.moreR:ClearAllPoints()
  f.moreR:SetPoint("LEFT", f.moreHead, "RIGHT", 16, 0)
  y = y + f.moreHead:GetStringHeight() + 18

  -- остальное: все значки в один ряд
  local n = #MORE
  local cellW = floor((WIDTH - SIDE * 2) / n)
  local mh = 0
  for i, c in ipairs(f.more) do
    local d = MORE[i]
    c.icon:SetIcon(ns.Icon(d[1]))
    c.head:SetWidth(cellW - 8)
    c.head:SetText(T(d[2]))
    mh = max(mh, 44 + 8 + c.head:GetStringHeight())
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", SIDE + (i - 1) * cellW, -y)
    c:SetWidth(cellW)
  end
  for _, c in ipairs(f.more) do c:SetHeight(mh) end
  y = y + mh

  f.go:SetText(T(BUTTON))
  f:SetHeight(y + 26 + 32 + 22)
end

-- Показать знакомство (кнопка «?», настройки, первое открытие аддона).
-- after - что сделать, когда окно закроют (любым способом), один раз.
function ns:ShowIntro(after)
  local UI = self.UI
  if not win then
    win = build()
    win:SetScript("OnHide", function(s)
      local fn = s.after
      s.after = nil
      if fn then ns:Safe(fn) end
    end)
  end
  local main = UI.frame and UI.frame:IsShown() and UI.frame
  win:ClearAllPoints()
  win:SetPoint("CENTER", main or UIParent, "CENTER", 0, main and 0 or 40)
  win:SetScale(self.settings.scale or 1)
  self.db.onboarded = true
  win.after = after
  self:Safe(show, win)
  win:Show()
  win:Raise()
end

-- ВРЕМЕННО, ДЛЯ ПРОВЕРКИ: знакомство и выбор профессии показываются при
-- каждом открытии аддона. Перед релизом поставить false.
local TEST_ALWAYS = true

-- Первое открытие аддона: сначала знакомство; когда его закроют - выбор
-- профессии (если профессий ещё нет), и только потом само окно EasyCraft.
-- Возвращает true, если знакомство показано и окно открывать пока не надо.
function ns:IntroFirst()
  if not self.db then return false end
  if self.skipIntro then self.skipIntro = nil; return false end -- открываем окно после знакомства
  if self.db.onboarded and not TEST_ALWAYS then return false end
  local function openMain()
    local UI = ns.UI
    if not (UI.frame and UI.frame:IsShown()) then
      ns.skipIntro = true
      ns:ToggleFrame()
    end
  end
  self:ShowIntro(function()
    if (TEST_ALWAYS or #ns:LearnedList() == 0) and ns.ShowChoose then
      ns:ShowChoose(nil, openMain)
    else
      openMain()
    end
  end)
  return true
end
