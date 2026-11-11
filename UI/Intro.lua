local _, TJ = ...
local W, C, T = TJ.W, TJ.Content, TJ.T
local format, floor, min = string.format, math.floor, math.min

-------------------------------------------------------------------------------
--  Знакомство с аддоном: отдельное окно поверх главного. Показывается само
--  один раз, при первом открытии EasyCraft; дальше - по кнопке «?» в
--  заголовке окна и из настроек.
--  Первая страница - что делает аддон, картинкой: шаг -> реагенты -> создать.
--  Дальше по странице на вкладку: заголовок и три-четыре шага значками
--  (те же тексты, что раньше занимали верх каждой вкладки).
-------------------------------------------------------------------------------
local S = W.S
local WIDTH, HEIGHT = 600, 400
local ARROW = { "Interface\\ChatFrame\\ChatFrameExpandArrow", "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up" }
local FLOW = {
  { "INV_Misc_Book_11", "Шаг" },
  { "INV_Misc_Bag_08", "Реагенты" },
  { "Trade_BlackSmithing", "Создать" },
}

local win

local function pages()
  local list = { { title = "EasyCraft ведёт профессию до 300",
    text = "Говорит, что делать сейчас, считает реагенты и создаёт одной кнопкой.", flow = true } }
  for i, how in ipairs(C.HOW or {}) do
    list[#list + 1] = { title = how.title, text = how.text, rows = C.GUIDE and C.GUIDE[i] }
  end
  return list
end

local function build()
  local f = CreateFrame("Frame", "EasyCraftIntroFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  f:SetSize(WIDTH, HEIGHT)
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  -- та же подложка, что у карточек окна: тёмная, в бурой рамке
  W.Backdrop(f, "Interface\\Buttons\\WHITE8X8", nil, 16, 0.05, 0.045, 0.04, 0.97, 0.6, 0.48, 0.25, 1)
  tinsert(UISpecialFrames, "EasyCraftIntroFrame")
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 0, 0)

  f.title = W.Text(f, "huge")
  f.title:SetPoint("TOPLEFT", S.s5, -S.s5)
  f.title:SetWidth(WIDTH - S.s5 * 2 - 20)
  f.text = W.Text(f, "body")
  f.text:SetWidth(WIDTH - S.s5 * 2)

  -- картинка «шаг -> реагенты -> создать»
  f.flow, f.arrows = {}, {}
  for i = 1, 3 do
    local c = CreateFrame("Frame", nil, f)
    c:SetSize(120, 100)
    c.icon = W.RingIcon(c, 56)
    c.icon:SetPoint("TOP", 0, 0)
    c.label = W.Text(c, "title", false)
    c.label:SetPoint("TOP", c.icon, "BOTTOM", 0, -S.s3)
    c.label:SetJustifyH("CENTER")
    f.flow[i] = c
    if i > 1 then
      local a = f:CreateTexture(nil, "ARTWORK")
      a:SetSize(24, 24)
      W.SetTex(a, ARROW, 1, 0.82, 0, 1)
      f.arrows[i - 1] = a
    end
  end

  -- шаги вкладки: значок, что сделать (золотом), строка пояснения
  f.tiles = {}
  for i = 1, 4 do
    local c = CreateFrame("Frame", nil, f)
    c.bg = c:CreateTexture(nil, "BACKGROUND")
    c.bg:SetAllPoints()
    c.bg:SetColorTexture(0, 0, 0, 0.3)
    c.icon = W.RingIcon(c, 32)
    c.icon:SetPoint("TOPLEFT", S.s2, -S.s2)
    c.head = W.Text(c, "head")
    c.head:SetPoint("TOPLEFT", c.icon, "TOPRIGHT", S.s2, -2)
    c.text = W.Text(c, "small")
    c.text:SetTextColor(W.LIGHT[1], W.LIGHT[2], W.LIGHT[3])
    f.tiles[i] = c
  end

  f.count = W.Text(f, "small", false)
  f.count:SetPoint("BOTTOMLEFT", S.s5, S.s4 + 5)
  f.next = W.Button(f, "", 130, S.btnBig)
  f.next:SetPoint("BOTTOMRIGHT", -S.s5, S.s4)
  f.back = W.Button(f, "", 110, S.btn)
  f.back:SetPoint("RIGHT", f.next, "LEFT", -S.s2, 0)
  f:Hide()
  return f
end

local function show(f, n)
  local list = pages()
  n = math.max(1, min(n, #list))
  f.page = n
  local p = list[n]
  f.title:SetText(T(p.title))
  f.text:SetText(T(p.text))
  f.text:ClearAllPoints()
  f.text:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -S.s2)
  local top = S.s5 + f.title:GetStringHeight() + S.s2 + f.text:GetStringHeight() + S.s5

  for i, c in ipairs(f.flow) do c:SetShown(p.flow and true or false) end
  for _, a in ipairs(f.arrows) do a:SetShown(p.flow and true or false) end
  if p.flow then
    local step = 170
    local x0 = floor((WIDTH - step * 2 - 120) / 2)
    for i, c in ipairs(f.flow) do
      c:ClearAllPoints()
      c:SetPoint("TOPLEFT", x0 + (i - 1) * step, -(top + S.s4))
      c.icon:SetIcon(TJ.Icon(FLOW[i][1]))
      c.label:SetText(T(FLOW[i][2]))
      if i > 1 then
        f.arrows[i - 1]:ClearAllPoints()
        f.arrows[i - 1]:SetPoint("CENTER", f, "TOPLEFT", x0 + (i - 1) * step - 25, -(top + S.s4 + 28))
      end
    end
  end

  local rows = p.rows or {}
  local cols = (#rows == 4) and 2 or math.max(1, min(#rows, 3))
  local colW = floor((WIDTH - S.s5 * 2 - S.s3 * (cols - 1)) / cols)
  local rowTop, rowH = top, 0
  for i, c in ipairs(f.tiles) do
    local r = rows[i]
    c:SetShown(r ~= nil)
    if r then
      local col = (i - 1) % cols
      if col == 0 and i > 1 then rowTop, rowH = rowTop + rowH + S.s3, 0 end
      c.icon:SetIcon(TJ.Icon(r[1]))
      c.head:SetWidth(colW - S.s2 * 3 - 32)
      c.head:SetText(T(r[2]))
      c.text:SetWidth(colW - S.s2 * 2)
      c.text:SetText(T(r[3]))
      c.text:ClearAllPoints()
      c.text:SetPoint("TOPLEFT", S.s2, -(S.s2 + math.max(32, c.head:GetStringHeight()) + S.s2))
      local h = S.s2 + math.max(32, c.head:GetStringHeight()) + S.s2 + c.text:GetStringHeight() + S.s2
      rowH = math.max(rowH, h)
      c:ClearAllPoints()
      c:SetPoint("TOPLEFT", S.s5 + col * (colW + S.s3), -rowTop)
      c:SetSize(colW, h)
    end
  end
  -- подложки одного ряда - одной высоты
  for i, c in ipairs(f.tiles) do
    if rows[i] then
      local first = i - ((i - 1) % cols)
      local h = 0
      for k = first, min(first + cols - 1, #rows) do h = math.max(h, f.tiles[k]:GetHeight()) end
      c:SetHeight(h)
    end
  end

  f.count:SetText(format("%d / %d", n, #list))
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

-- Первое открытие аддона: сначала знакомство; когда его закроют - выбор
-- профессии (если профессий ещё нет), и только потом само окно EasyCraft.
-- Возвращает true, если знакомство показано и окно открывать пока не надо.
-- ВРЕМЕННО, ДЛЯ ПРОВЕРКИ: знакомство и выбор профессии показываются при
-- каждом открытии аддона. Перед релизом поставить false.
local TEST_ALWAYS = true

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
