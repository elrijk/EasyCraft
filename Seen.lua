local _, ns = ...

-------------------------------------------------------------------------------
--  Свои наблюдения цветов рецептов. Каждый раз, когда открыто окно профессии,
--  EasyCraft запоминает, какого цвета был каждый выученный рецепт на нынешнем
--  навыке. Из наблюдений получаются пороги: с какого навыка рецепт желтеет,
--  зеленеет и сереет - их игра не сообщает.
--  EasyCraftDB.seen[профессия][рецепт] = { o = наибольший навык, где был
--  оранжевым, y1/y2 = наименьший и наибольший жёлтый, g1/g2 = зелёный,
--  x = наименьший серый }. Общие на учётную запись: альты дополняют друг друга.
--  Режимы маршрута (Routes.lua) берут такие рецепты в выбор, а код из
--  /ec colors можно отправить автору - пороги попадут в данные для всех.
-------------------------------------------------------------------------------
local min, max = math.min, math.max
local HEADER = "EasyCraft:sk:1"

local function seenOf(self, key, make)
  local db = self.db
  if not db then return nil end
  if not db.seen then
    if not make then return nil end
    db.seen = {}
  end
  if not db.seen[key] and make then db.seen[key] = {} end
  return db.seen[key]
end

-- colors: рецепт -> 0 оранжевый, 1 жёлтый, 2 зелёный, 3 серый; rank - навык.
function ns:NoteColors(key, colors, rank)
  if type(colors) ~= "table" or type(rank) ~= "number" or rank <= 0 then return end
  local t = seenOf(self, key, true)
  if not t then return end
  for id, d in pairs(colors) do
    local r = t[id]
    if not r then r = {} t[id] = r end
    if d == 0 then r.o = max(r.o or rank, rank)
    elseif d == 1 then r.y1 = min(r.y1 or rank, rank) r.y2 = max(r.y2 or rank, rank)
    elseif d == 2 then r.g1 = min(r.g1 or rank, rank) r.g2 = max(r.g2 or rank, rank)
    elseif d == 3 then r.x = min(r.x or rank, rank) end
  end
end

-- Пороги по наблюдениям: с какого навыка видели, жёлтый, зелёный, серый -
-- или nil, если наблюдений мало. Оценка осторожная: считаем, что рецепт
-- желтеет и сереет раньше, а не позже - цена пути выйдет чуть выше, не ниже.
function ns:SeenThresholds(r)
  if type(r) ~= "table" then return nil end
  local yellow = (r.o and r.o + 1) or r.y1
  if not yellow then return nil end
  local green = (r.y2 and r.y2 + 1) or r.g1
  local grey
  if r.g2 then grey = r.g2 + 1
  elseif green and green > yellow then grey = 2 * green - yellow -- отрезки жёлтого и зелёного равны
  elseif r.x and r.x > yellow then grey = r.x end
  if r.x and grey and r.x < grey then grey = r.x end
  if not grey or grey <= yellow then return nil end
  local first = min(r.o or 999, r.y1 or 999, r.g1 or 999, r.x or 999)
  return first, yellow, green or yellow, grey
end

-- Выученные рецепты с порогами по наблюдениям - кандидаты для режимов
-- маршрута. skip[рецепт] - уже есть в маршруте.
function ns:SeenCandidates(key, skip)
  local out = {}
  local t = seenOf(self, key)
  local book = self.char and self.char.book and self.char.book[key]
  if not (t and book) then return out end
  for id, b in pairs(book) do
    if not (skip and skip[id]) and type(b) == "table" and b.rc and #b.rc >= 2 and b.out then
      local first, yellow, green, grey = self:SeenThresholds(t[id])
      if first then
        out[#out + 1] = { learn = first, yellow = yellow, grey = grey,
          s = { k = "craft", spell = id, id = b.out, en = b.n, ru = b.n, rc = b.rc, src = "seen",
            sk = { first, yellow, green, grey } } }
      end
    end
  end
  return out
end

-- Код наблюдений для автора: «профессия;рецепт;o;y1;y2;g1;g2;x;выход;реагенты».
function ns:ColorsReport()
  local parts, n = { HEADER }, 0
  local db = self.db
  for key, t in pairs(db and db.seen or {}) do
    local book = self.char and self.char.book and self.char.book[key]
    local ids = {}
    for id in pairs(t) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
      local r, b = t[id], book and book[id]
      local rc = b and b.rc and table.concat(b.rc, ",") or ""
      parts[#parts + 1] = table.concat({ key, id, r.o or "", r.y1 or "", r.y2 or "", r.g1 or "", r.g2 or "", r.x or "",
        b and b.out or "", rc }, ";")
      n = n + 1
    end
  end
  return table.concat(parts, "|"), n
end

function ns:ShareColors()
  local code, n = self:ColorsReport()
  if n == 0 then
    self:Print(ns.T("наблюдений пока нет: открой окно профессии."))
    return
  end
  self:ShowShareWindow(code, n)
end

-------------------------------------------------------------------------------
--  Окно отправки. Игра не открывает браузер и не выходит в интернет, поэтому
--  аддон готовит ссылку на новое обращение в GitHub с уже вставленным кодом:
--  игрок копирует её, открывает в браузере и нажимает Submit. Если код в
--  ссылку не помещается (у адреса есть предел длины), даём ссылку и код
--  отдельно, двумя шагами.
-------------------------------------------------------------------------------
local SHARE_URL = "https://github.com/elrijk/EasyCraft/issues/new"
local SHARE_MAX = 7000 -- длиннее адрес браузеры и GitHub могут не принять
local shareWin

local function urlEncode(text)
  return (text:gsub("[^%w%-_%.~]", function(c) return format("%%%02X", c:byte()) end))
end

-- поле с текстом только для копирования: набранное возвращается обратно
local function copyBox(parent, width)
  local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  e:SetSize(width, 22)
  e:SetAutoFocus(false)
  e:SetMaxLetters(0)
  e:SetScript("OnTextChanged", function(box, user)
    if user and box:GetText() ~= box.value then
      box:SetText(box.value or "")
      box:HighlightText()
    end
  end)
  e:SetScript("OnEditFocusGained", function(box) box:HighlightText() end)
  e:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
  function e:Put(text)
    self.value = text
    self:SetText(text)
    self:SetCursorPosition(0)
  end
  return e
end

function ns:ShowShareWindow(code, n)
  local W, T = self.W, self.T
  local f = shareWin
  local WIDTH, PAD = 460, 20
  local inner = WIDTH - PAD * 2
  if not f then
    f = CreateFrame("Frame", "EasyCraftShareFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    shareWin = f
    f:SetWidth(WIDTH)
    f:SetPoint("CENTER", 0, 60)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    W.Backdrop(f, "Interface\\Buttons\\WHITE8X8", nil, 16, 0.06, 0.045, 0.03, 1, 0.75, 0.6, 0.3, 1)
    tinsert(UISpecialFrames, "EasyCraftShareFrame")
    local x = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    x:SetPoint("TOPRIGHT", 0, 0)
    f.title = W.Text(f, "title", false)
    f.title:SetPoint("TOPLEFT", PAD, -16)
    f.step1 = W.Text(f, "body")
    f.step1:SetWidth(inner)
    f.link = copyBox(f, inner - 6)
    f.step2 = W.Text(f, "body")
    f.step2:SetWidth(inner)
    f.code = copyBox(f, inner - 6)
    f.note = W.Text(f, "small")
    f.note:SetWidth(inner)
    f.close = W.Button(f, CLOSE or "Close", 160, 26)
    f.close:SetScript("OnClick", function() f:Hide() end)
  end
  local full = SHARE_URL .. "?title=" .. urlEncode("Recipe colours (" .. n .. ")") .. "&body=" .. urlEncode(code)
  local fits = #full <= SHARE_MAX
  f.title:SetText(format(T("Цвета рецептов: %d"), n))
  local y = 16 + f.title:GetStringHeight() + 12
  f.step1:SetText(fits and T("Скопируй ссылку (Ctrl+C), вставь в адресную строку браузера и нажми Submit на странице.")
    or T("1. Скопируй ссылку (Ctrl+C) и открой её в браузере."))
  f.step1:ClearAllPoints()
  f.step1:SetPoint("TOPLEFT", PAD, -y)
  y = y + f.step1:GetStringHeight() + 6
  f.link:Put(fits and full or (SHARE_URL .. "?title=" .. urlEncode("Recipe colours (" .. n .. ")")))
  f.link:ClearAllPoints()
  f.link:SetPoint("TOPLEFT", PAD + 6, -y)
  y = y + 22 + 12
  f.step2:SetShown(not fits)
  f.code:SetShown(not fits)
  if not fits then
    f.step2:SetText(T("2. Скопируй код, вставь его в текст обращения и нажми Submit."))
    f.step2:ClearAllPoints()
    f.step2:SetPoint("TOPLEFT", PAD, -y)
    y = y + f.step2:GetStringHeight() + 6
    f.code:Put(code)
    f.code:ClearAllPoints()
    f.code:SetPoint("TOPLEFT", PAD + 6, -y)
    y = y + 22 + 12
  end
  f.note:SetText(T("Игра не умеет открывать браузер, поэтому ссылку нужно скопировать. Нужна учётная запись GitHub; страница видна всем. В коде только рецепты и навык."))
  f.note:ClearAllPoints()
  f.note:SetPoint("TOPLEFT", PAD, -y)
  y = y + f.note:GetStringHeight() + 14
  f.close:ClearAllPoints()
  f.close:SetPoint("TOP", f, "TOP", 0, -y)
  f:SetHeight(y + 26 + 16)
  f:Show()
  f:Raise()
  f.link:SetFocus()
  f.link:HighlightText()
end

-------------------------------------------------------------------------------
--  Просьба поделиться наблюдениями: отдельная подсказка по центру экрана у
--  окна профессии. Раз за сессию, только когда накопилось новое. Кнопка
--  открывает код для отправки, крестик просто закрывает.
-------------------------------------------------------------------------------
local ASK_MIN = 1 -- просим, если накопилось хоть что-то
local askPanel

local function seenCount(self)
  local n = 0
  for _, t in pairs(self.db and self.db.seen or {}) do
    for _ in pairs(t) do n = n + 1 end
  end
  return n
end

local function profWindow()
  for _, name in ipairs({ "ProfessionsFrame", "TradeSkillFrame", "CraftFrame" }) do
    local w = _G[name]
    if type(w) == "table" and w.IsShown and w:IsShown() then return w end
  end
end

function ns:AskShare()
  if self.askedShare or not self.db or not (self.W and self.W.HintPanel) then return end
  if self.settings and self.settings.askShare == false then return end
  local n = seenCount(self)
  if n < ASK_MIN or n <= (self.db.seenSent or 0) then return end
  local win = profWindow()
  if not win then return end
  self.askedShare = true
  local W, T = self.W, self.T
  local f = askPanel
  if not f then
    f = W.HintPanel("EasyCraftSharePanel", 270, T("Помоги улучшить EasyCraft"))
    askPanel = f
    local x = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    x:SetPoint("TOPRIGHT", 2, 2)
    x:SetScript("OnClick", function() f:Hide() end)
  end
  f:Reset()
  f.note:SetText(format(T("Аддон запомнил цвета рецептов: %d. Отправь их автору - маршруты станут точнее у всех. Личного в коде нет: только рецепты и навык."), n))
  f.note:ClearAllPoints()
  f.note:SetPoint("TOPLEFT", f, "TOPLEFT", W.HINT_PAD, -f.top)
  f.note:Show()
  local y = f.top + f.note:GetStringHeight() + 10
  f.btn:SetText(T("Отправить данные"))
  f.btn:ClearAllPoints()
  f.btn:SetPoint("TOPLEFT", f, "TOPLEFT", W.HINT_PAD, -y)
  f.btn:SetScript("OnClick", function()
    ns.db.seenSent = seenCount(ns)
    f:Hide()
    ns:ShareColors()
  end)
  f.btn:Show()
  y = y + W.HINT_BTN + 6
  -- «больше не напоминать»: выключает просьбу навсегда (вернуть - в настройках)
  if not f.never then
    f.never = W.Check(f, T("Больше не напоминать"))
    f.never.label:SetTextColor(0.25, 0.18, 0.1)
    f.never:SetScript("OnClick", function(self)
      ns.settings.askShare = not self:GetChecked()
      if ns.RefreshOptions then ns:RefreshOptions() end
      if self:GetChecked() then f:Hide() end
    end)
  end
  f.never:SetChecked(false)
  f.never:ClearAllPoints()
  f.never:SetPoint("TOPLEFT", f, "TOPLEFT", W.HINT_PAD - 4, -y)
  f.never:Show()
  f:SetHeight(y + 24 + 12)
  f:ClearAllPoints()
  -- всегда по центру экрана, поверх остальных окон аддона
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  f:SetFrameStrata("DIALOG")
  f:Show()
  f:Raise()
end

-- Окно профессии закрыли - подсказка уходит вместе с ним.
local askEv = CreateFrame("Frame")
for _, e in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE", "CRAFT_CLOSE" }) do pcall(askEv.RegisterEvent, askEv, e) end
askEv:SetScript("OnEvent", function(_, e)
  if e == "TRADE_SKILL_SHOW" then
    -- после чтения окна (Tracking.lua) и появления мини-окна
    C_Timer.After(2, function() pcall(ns.AskShare, ns) end)
  elseif askPanel then
    askPanel:Hide()
  end
end)

-- Запасной путь: если события открытия окна в клиенте нет, просьбу покажет
-- само чтение окна профессии.
local noteColors = ns.NoteColors
function ns:NoteColors(key, colors, rank)
  noteColors(self, key, colors, rank)
  if not self.askedShare then
    C_Timer.After(2, function() pcall(ns.AskShare, ns) end)
  end
end
