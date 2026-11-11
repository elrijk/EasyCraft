local _, TJ = ...
local W, C, T = TJ.W, TJ.Content, TJ.T
local floor, min, max = math.floor, math.min, math.max

-------------------------------------------------------------------------------
--  Знакомство с аддоном: отдельное окно. Показывается при первом открытии
--  EasyCraft раньше самого окна; дальше - по кнопке «?» в заголовке окна и
--  из настроек.
--  Вид - как у окон игры с одной главной мыслью: заголовок по центру, под
--  ним золотая линия и одна строка пояснения; ниже шаги карточками в один
--  ряд - номер, крупный значок, что сделать (золотом), строка пояснения.
--  Высота окна - по содержимому, внизу точки-страницы и кнопки.
--  Первая страница - что делает аддон: шаг -> реагенты -> создать.
-------------------------------------------------------------------------------
local S = W.S
local WIDTH = 720
local SIDE = 28 -- поля окна слева и справа
local GAP = 12 -- между карточками шагов
local ARROW = { "Interface\\ChatFrame\\ChatFrameExpandArrow", "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up" }
local FLOW = {
  { "INV_Misc_Book_11", "Шаг", "что делать сейчас" },
  { "INV_Misc_Bag_08", "Реагенты", "что есть и что докупить" },
  { "Trade_BlackSmithing", "Создать", "одной кнопкой" },
}
local MAX_TILES, MAX_DOTS = 4, 8

local win

local function pages()
  local list = { { title = "EasyCraft ведёт профессию до 300",
    text = "Говорит, что делать сейчас, считает реагенты и создаёт одной кнопкой.", flow = true } }
  for i, how in ipairs(C.HOW or {}) do
    list[#list + 1] = { title = how.title, text = how.text, rows = C.GUIDE and C.GUIDE[i] }
  end
  return list
end

local function centered(fs, width)
  fs:SetJustifyH("CENTER")
  fs:SetWidth(width)
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
  -- фон не плоский: сверху тёплый коричневый, книзу уходит в чёрный
  local bg = f:CreateTexture(nil, "BORDER")
  bg:SetPoint("TOPLEFT", 4, -4)
  bg:SetPoint("BOTTOMRIGHT", -4, 4)
  bg:SetColorTexture(1, 1, 1, 1)
  local ok = CreateColor and pcall(bg.SetGradient, bg, "VERTICAL", CreateColor(0.03, 0.025, 0.02, 1), CreateColor(0.2, 0.14, 0.08, 1))
  if not ok then bg:SetColorTexture(0.1, 0.075, 0.05, 1) end
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 0, 0)

  -- шапка: заголовок по центру, золотая линия, строка пояснения
  f.title = W.Text(f, "huge")
  centered(f.title, WIDTH - SIDE * 2 - 40)
  f.title:SetPoint("TOP", 0, -26)
  local file, _, flags = f.title:GetFont()
  if file then f.title:SetFont(file, 24, flags) end
  f.rule = f:CreateTexture(nil, "ARTWORK")
  f.rule:SetSize(320, 1)
  f.rule:SetColorTexture(0.85, 0.68, 0.3, 0.8)
  f.rule:SetPoint("TOP", f.title, "BOTTOM", 0, -10)
  f.text = W.Text(f, "body")
  centered(f.text, WIDTH - SIDE * 2 - 60)
  f.text:SetTextColor(0.9, 0.87, 0.8)
  f.text:SetPoint("TOP", f.rule, "BOTTOM", 0, -10)

  -- первая страница: три крупных значка со стрелками
  f.flow, f.arrows = {}, {}
  for i = 1, 3 do
    local c = CreateFrame("Frame", nil, f)
    c:SetSize(190, 150)
    c.icon = W.RingIcon(c, 72)
    c.icon:SetPoint("TOP", 0, 0)
    c.label = W.Text(c, "title", false)
    centered(c.label, 190)
    c.label:SetPoint("TOP", c.icon, "BOTTOM", 0, -12)
    c.sub = W.Text(c, "body")
    centered(c.sub, 180)
    c.sub:SetTextColor(0.8, 0.77, 0.7)
    c.sub:SetPoint("TOP", c.label, "BOTTOM", 0, -4)
    f.flow[i] = c
    if i > 1 then
      local a = f:CreateTexture(nil, "ARTWORK")
      a:SetSize(32, 32)
      W.SetTex(a, ARROW, 1, 0.82, 0, 1)
      f.arrows[i - 1] = a
    end
  end

  -- шаги вкладки: карточки в один ряд
  f.tiles = {}
  for i = 1, MAX_TILES do
    local c = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
    W.Backdrop(c, "Interface\\Buttons\\WHITE8X8", nil, 12, 0, 0, 0, 0.45, 0.6, 0.48, 0.25, 0.9)
    c.num = W.Text(c, "head", false)
    c.num:SetPoint("TOPLEFT", 10, -8)
    c.num:SetTextColor(0.75, 0.6, 0.3)
    c.icon = W.RingIcon(c, 48)
    c.icon:SetPoint("TOP", 0, -18)
    c.head = W.Text(c, "head")
    c.head:SetJustifyH("CENTER")
    c.head:SetPoint("TOP", c.icon, "BOTTOM", 0, -12)
    c.text = W.Text(c, "small")
    c.text:SetJustifyH("CENTER")
    c.text:SetTextColor(0.9, 0.87, 0.8)
    c.text:SetPoint("TOP", c.head, "BOTTOM", 0, -8)
    f.tiles[i] = c
  end

  -- низ: точки-страницы по центру, кнопки справа
  f.dots = {}
  for i = 1, MAX_DOTS do
    local d = f:CreateTexture(nil, "ARTWORK")
    d:SetSize(8, 8)
    f.dots[i] = d
  end
  f.next = W.Button(f, "", 140, S.btnBig)
  f.next:SetPoint("BOTTOMRIGHT", -SIDE, 20)
  f.back = W.Button(f, "", 110, S.btn)
  f.back:SetPoint("BOTTOMLEFT", SIDE, 22)
  f:Hide()
  return f
end

local function show(f, n)
  local list = pages()
  n = max(1, min(n, #list))
  f.page = n
  local p = list[n]
  f.title:SetText(T(p.title))
  f.text:SetText(T(p.text))
  -- где кончается шапка
  local top = 26 + f.title:GetStringHeight() + 10 + 1 + 10 + f.text:GetStringHeight() + 26
  local bottom = top

  for _, c in ipairs(f.flow) do c:SetShown(p.flow and true or false) end
  for _, a in ipairs(f.arrows) do a:SetShown(p.flow and true or false) end
  if p.flow then
    local step = 220
    local x0 = floor((WIDTH - step * 2 - 190) / 2)
    local h = 0
    for i, c in ipairs(f.flow) do
      c:ClearAllPoints()
      c:SetPoint("TOPLEFT", x0 + (i - 1) * step, -top)
      c.icon:SetIcon(TJ.Icon(FLOW[i][1]))
      c.label:SetText(T(FLOW[i][2]))
      c.sub:SetText(T(FLOW[i][3]))
      h = max(h, 72 + 12 + c.label:GetStringHeight() + 4 + c.sub:GetStringHeight())
      if i > 1 then
        f.arrows[i - 1]:ClearAllPoints()
        f.arrows[i - 1]:SetPoint("CENTER", f, "TOPLEFT", x0 + (i - 1) * step - 15, -(top + 36))
      end
    end
    bottom = top + h
  end

  local rows = p.rows or {}
  local cols = max(1, min(#rows, MAX_TILES))
  local colW = floor((WIDTH - SIDE * 2 - GAP * (cols - 1)) / cols)
  local rowH = 0
  for i, c in ipairs(f.tiles) do
    local r = rows[i]
    c:SetShown(r ~= nil)
    if r then
      c.num:SetText(tostring(i))
      c.icon:SetIcon(TJ.Icon(r[1]))
      c.head:SetWidth(colW - 20)
      c.head:SetText(T(r[2]))
      c.text:SetWidth(colW - 24)
      c.text:SetText(T(r[3]))
      rowH = max(rowH, 18 + 48 + 12 + c.head:GetStringHeight() + 8 + c.text:GetStringHeight() + 16)
      c:ClearAllPoints()
      c:SetPoint("TOPLEFT", SIDE + (i - 1) * (colW + GAP), -top)
      c:SetWidth(colW)
    end
  end
  if #rows > 0 then
    for i, c in ipairs(f.tiles) do
      if rows[i] then c:SetHeight(rowH) end
    end
    bottom = top + rowH
  end

  -- высота окна - по содержимому: без пустой половины
  f:SetHeight(bottom + 26 + S.btnBig + 20)

  local total = min(#list, MAX_DOTS)
  local dotStep = 16
  local dx = floor((WIDTH - (total - 1) * dotStep - 8) / 2)
  for i, d in ipairs(f.dots) do
    d:SetShown(i <= total)
    if i <= total then
      d:ClearAllPoints()
      d:SetPoint("BOTTOMLEFT", dx + (i - 1) * dotStep, 29)
      if i == n then d:SetColorTexture(1, 0.82, 0, 1) else d:SetColorTexture(0.45, 0.38, 0.26, 1) end
    end
  end

  local last = n == #list
  f.next:SetText(last and T("Понятно") or T("Дальше"))
  f.next:SetScript("OnClick", function()
    W.Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
    if last then f:Hide() else show(f, n + 1) end
  end)
  f.back:SetText(T("Назад"))
  f.back:SetShown(n > 1)
  f.back:SetScript("OnClick", function()
    W.Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
    show(f, n - 1)
  end)
end

-- Показать знакомство (кнопка «?», настройки, первое открытие аддона).
-- after - что сделать, когда окно закроют (любым способом), один раз.
function TJ:ShowIntro(after)
  local UI = self.UI
  if not win then
    win = build()
    win:SetScript("OnHide", function(s)
      local fn = s.after
      s.after = nil
      if fn then TJ:Safe(fn) end
    end)
  end
  local main = UI.frame and UI.frame:IsShown() and UI.frame
  win:ClearAllPoints()
  win:SetPoint("CENTER", main or UIParent, "CENTER", 0, main and 0 or 40)
  win:SetScale(self.settings.scale or 1)
  self.db.onboarded = true
  win.after = after
  self:Safe(show, win, 1)
  win:Show()
  win:Raise()
end

-- ВРЕМЕННО, ДЛЯ ПРОВЕРКИ: знакомство и выбор профессии показываются при
-- каждом открытии аддона. Перед релизом поставить false.
local TEST_ALWAYS = true

-- Первое открытие аддона: сначала знакомство; когда его закроют - выбор
-- профессии (если профессий ещё нет), и только потом само окно EasyCraft.
-- Возвращает true, если знакомство показано и окно открывать пока не надо.
function TJ:IntroFirst()
  if not self.db then return false end
  if self.skipIntro then self.skipIntro = nil; return false end -- открываем окно после знакомства
  if self.db.onboarded and not TEST_ALWAYS then return false end
  local function openMain()
    local UI = TJ.UI
    if not (UI.frame and UI.frame:IsShown()) then
      TJ.skipIntro = true
      TJ:ToggleFrame()
    end
  end
  self:ShowIntro(function()
    if (TEST_ALWAYS or #TJ:LearnedList() == 0) and TJ.ShowChoose then
      TJ:ShowChoose(nil, openMain)
    else
      openMain()
    end
  end)
  return true
end
