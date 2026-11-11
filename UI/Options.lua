local ADDON, ns = ...

-------------------------------------------------------------------------------
--  Страница аддона в «Настройки -> Модификации -> EasyCraft»
-------------------------------------------------------------------------------
local settingsCategory, panel

-- Подписи галочек - по-русски, переводятся при создании страницы (на
-- ADDON_LOADED язык из настроек уже известен).

local OPTIONS = {
  { "minimap", "Показывать кнопку у миникарты", function(v) ns:SetMinimapHidden(not v) end },
  { "miniGuide", "Мини-окно рядом с окном профессии", function(v) ns.settings.miniGuide = v; if ns.Tracker then ns.Tracker.hidden = nil end end },
  { "hideDone", "Скрывать выполненные шаги в маршруте" },
  { "mapMine", "Карта мира: мои находки" },
  { "itemTips", "Подсказки: сколько предмета нужно до учителя, цвет жилы и травы" },
  { "trainerStars", "Окно учителя: звезда у рецептов, нужных маршруту" },
  { "ahScan", "Аукцион: читать цены самому при открытии" },
  { "askShare", "Напоминать поделиться данными о рецептах" },
  { "useAlts", "Считать реагенты у других моих персонажей", function(v) ns.settings.useAlts = v; ns.altCache = nil end },
  { "hintsLocked", "Закрепить подсказки у окон профессии, банка и аукциона", function(v)
    ns.settings.hintsLocked = v
    if ns.W and ns.W.UpdateLocks then ns.W.UpdateLocks() end
  end },
}

function ns:RefreshOptions()
  if not panel then return end
  for _, c in ipairs(panel.checks) do c:SetChecked(ns.settings[c.opt] and true or false) end
  if panel.scale then panel.scale:SetValue(ns.settings.scale or 1) end
  if panel.areaAlpha then panel.areaAlpha:SetValue(ns.settings.mapAreaAlpha or 0.5) end
end

-- Команды чата: список в настройках и по /ec commands (описания по-русски,
-- переводятся при показе).
ns.COMMANDS = {
  { "/ec", "открыть или закрыть окно" },
  { "/ec help", "снова показать гайды вкладок" },
  { "/ec options", "открыть настройки" },
  { "/ec minimap", "показать или скрыть кнопку у миникарты" },
  { "/ec check", "где маршрут расходится с игрой" },
  { "/ec scan", "прочитать цены на открытом аукционе" },
  { "/ec colors", "код с цветами рецептов для автора" },
  { "/ec choose", "Выбор профессии" },
  { "/ec reset", "сбросить данные этого персонажа" },
  { "/ec commands", "этот список в чат" },
}

function ns:CommandLines()
  local out = {}
  for _, c in ipairs(ns.COMMANDS) do out[#out + 1] = "|cffffd100" .. c[1] .. "|r - " .. ns.T(c[2]) end
  return out
end

function ns:PrintCommands()
  ns:Print(ns.T("команды:"))
  for _, line in ipairs(ns:CommandLines()) do DEFAULT_CHAT_FRAME:AddMessage("  " .. line) end
end

-- Страница настроек с прокруткой: внизу список команд, всё может не влезть.
local function ScrollBody(panel)
  local ok, sf = pcall(CreateFrame, "ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
  if not ok or not sf then return panel end
  sf:SetPoint("TOPLEFT", 0, -2)
  sf:SetPoint("BOTTOMRIGHT", -28, 2)
  local body = CreateFrame("Frame", nil, sf)
  body:SetSize(600, 900)
  sf:SetScrollChild(body)
  sf:SetScript("OnSizeChanged", function(self, w) if w and w > 0 then body:SetWidth(w) end end)
  panel.scroll = sf
  return body
end

function ns:BuildSettings()
  if panel then return end
  panel = CreateFrame("Frame")
  panel.name = "EasyCraft"
  -- Одинаково у EasyCraft и MacroCoach: название, язык, описание, кнопки
  -- «Открыть окно» и «Как пользоваться», настройки, команды.
  local body = ScrollBody(panel)

  local title = body:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText("|cff33ff99Easy|rCraft")

  -- Язык EasyCraft (выбор - в EasyCraftDB.lang, меняется после перезагрузки)
  local lang = ns:LanguageDropdown(body)
  lang:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -14)

  local sub = body:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  sub:SetPoint("TOPLEFT", lang, "BOTTOMLEFT", 0, -6)
  sub:SetWidth(560)
  sub:SetJustifyH("LEFT")
  sub:SetText(ns.T("Прокачка профессий WoW Forever: текущий шаг и цель, кнопки создания, учителя и рецепты, точки на карте."))

  local open = ns.W.Button(body, ns.T("Открыть окно"), 200, 26)
  open:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -14)
  open:SetScript("OnClick", function()
    -- Окно настроек игры не закрываем из кода аддона (это «заражает»
    -- настройки), а показываем окно EasyCraft поверх него.
    ns.UI:Create()
    local f = ns.UI.frame
    f:SetFrameStrata("DIALOG")
    if not f:IsShown() then ns:ToggleFrame() end
    f:Raise()
  end)

  local intro = ns.W.Button(body, ns.T("Как пользоваться"), 200, 26)
  intro:SetPoint("LEFT", open, "RIGHT", 10, 0)
  intro:SetScript("OnClick", function()
    ns.UI:Create()
    ns.UI.frame:SetFrameStrata("DIALOG")
    ns:ShowIntro()
    ns.UI.frame:Raise()
  end)

  -- отправить автору наблюдения цветов рецептов (Seen.lua)
  local share = ns.W.Button(body, ns.T("Отправить данные"), 200, 26)
  share:SetPoint("LEFT", intro, "RIGHT", 10, 0)
  share:SetScript("OnClick", function() if ns.ShareColors then ns:ShareColors() end end)

  -- выбор профессии: окно поверх настроек игры
  local choose = ns.W.Button(body, ns.T("Выбор профессии"), 200, 26)
  choose:SetPoint("TOPLEFT", open, "BOTTOMLEFT", 0, -8)
  choose:SetScript("OnClick", function()
    ns:ShowChoose()
    local win = EasyCraftChooseFrame
    if win then
      win:SetFrameStrata("DIALOG")
      win:Raise()
    end
  end)

  panel.checks = {}
  local prev = choose
  for i, o in ipairs(OPTIONS) do
    local c = ns.W.Check(body, ns.T(o[2]))
    c:SetSize(26, 26)
    c.label:SetFontObject("GameFontHighlight")
    c:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", i == 1 and -2 or 0, i == 1 and -14 or -4)
    c.opt = o[1]
    c:SetScript("OnClick", function(self)
      local v = self:GetChecked() and true or false
      if o[3] then o[3](v) else ns.settings[o[1]] = v end
      ns:RefreshAll()
    end)
    panel.checks[i] = c
    prev = c
  end

  -- подсказки, которые перетаскивали, - на прежние места
  local reset = ns.W.Button(body, ns.T("Вернуть подсказки на место"), 240, 22)
  reset:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 2, -14)
  reset:SetScript("OnClick", function()
    ns.db.hintPos = nil
    ns:RefreshAll()
    ns:Print(ns.T("подсказки вернутся на свои места, когда появятся снова."))
  end)
  prev = reset

  -- свои точки сбора на карте мира: сколько их и очистка в два щелчка
  local clear = ns.W.Button(body, "", 240, 22)
  clear:SetPoint("LEFT", reset, "RIGHT", 10, 0)
  local function points()
    local total = 0
    for _, list in pairs(ns.db.nodes) do
      if type(list) == "table" then total = total + #list end
    end
    return total
  end
  local function label()
    local n = points()
    clear:SetText(clear.armed and ns.T("Точно очистить?") or (ns.T("Очистить точки") .. " (" .. n .. ")"))
    clear:SetEnabled(n > 0)
  end
  clear:SetScript("OnShow", function(s) s.armed = nil; label() end)
  clear:SetScript("OnClick", function(s)
    if not s.armed then
      s.armed = true
      label()
      C_Timer.After(3, function() s.armed = nil; label() end)
      return
    end
    s.armed = nil
    wipe(ns.db.nodes)
    ns.nodeGen = (ns.nodeGen or 0) + 1 -- карта: свои точки убрать
    ns:RefreshAll()
    label()
  end)
  clear:SetScript("OnEnter", function(s)
    GameTooltip:SetOwner(s, "ANCHOR_TOP")
    GameTooltip:SetText(ns.T("Мои точки на карте"), 1, 0.82, 0)
    GameTooltip:AddLine(ns.T("Когда ты собираешь руду или траву или ловишь рыбу, место запоминается и появляется на карте мира. Точки общие для всех твоих персонажей."), 1, 1, 1, true)
    GameTooltip:Show()
  end)
  clear:SetScript("OnLeave", function() GameTooltip:Hide() end)
  label()

  -- window scale
  local ok, sl = pcall(CreateFrame, "Slider", "EasyCraftScaleSlider", body, "OptionsSliderTemplate")
  if not ok then sl = nil end
  if sl then
    sl:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 4, -28)
    sl:SetWidth(220)
    sl:SetMinMaxValues(0.7, 1.3)
    sl:SetValueStep(0.05)
    if sl.SetObeyStepOnDrag then sl:SetObeyStepOnDrag(true) end
    local label = sl.Text or _G[sl:GetName() .. "Text"]
    local function ShowValue(v)
      if label then label:SetText(ns.T("Размер окна") .. ": " .. math.floor(v * 100 + 0.5) .. "%") end
    end
    ShowValue(ns.settings.scale or 1)
    local low, high = sl.Low or _G[sl:GetName() .. "Low"], sl.High or _G[sl:GetName() .. "High"]
    if low then low:SetText("70%") end
    if high then high:SetText("130%") end
    sl:SetScript("OnValueChanged", function(_, v)
      v = math.floor(v * 20 + 0.5) / 20
      ns.settings.scale = v
      ShowValue(v)
      if ns.UI and ns.UI.frame then ns.UI.frame:SetScale(v) end
    end)
    panel.scale = sl
  end

  -- непрозрачность областей сбора на карте (щелчок по зоне в подсказке)
  local ok2, al = pcall(CreateFrame, "Slider", "EasyCraftAreaAlphaSlider", body, "OptionsSliderTemplate")
  if not ok2 then al = nil end
  if al then
    al:SetPoint("TOPLEFT", sl or prev, "BOTTOMLEFT", sl and 0 or 4, -34)
    al:SetWidth(220)
    al:SetMinMaxValues(0.1, 1)
    al:SetValueStep(0.05)
    if al.SetObeyStepOnDrag then al:SetObeyStepOnDrag(true) end
    local label = al.Text or _G[al:GetName() .. "Text"]
    local function ShowValue(v)
      if label then label:SetText(ns.T("Области сбора на карте: непрозрачность") .. " " .. math.floor(v * 100 + 0.5) .. "%") end
    end
    ShowValue(ns.settings.mapAreaAlpha or 0.5)
    local low, high = al.Low or _G[al:GetName() .. "Low"], al.High or _G[al:GetName() .. "High"]
    if low then low:SetText("10%") end
    if high then high:SetText("100%") end
    al:SetScript("OnValueChanged", function(_, v)
      v = math.floor(v * 20 + 0.5) / 20
      ns.settings.mapAreaAlpha = v
      ShowValue(v)
      -- ползунок двигают плавно: перерисовать области раз в 0.05 с, а не на каждый шаг
      if ns.MapOverlay and WorldMapFrame and WorldMapFrame:IsShown() and not al.pending then
        al.pending = true
        local function go() al.pending = nil; ns.MapOverlay:Refresh() end
        C_Timer.After(0.05, go)
      end
    end)
    panel.areaAlpha = al
  end

  -- команды чата
  local cmdHead = body:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  cmdHead:SetPoint("TOPLEFT", al or sl or prev, "BOTTOMLEFT", (al or sl) and -4 or 2, -30)
  cmdHead:SetText(ns.T("Команды в чате"))
  local cmds = body:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  cmds:SetPoint("TOPLEFT", cmdHead, "BOTTOMLEFT", 0, -8)
  cmds:SetWidth(560)
  cmds:SetJustifyH("LEFT")
  if cmds.SetSpacing then cmds:SetSpacing(4) end
  cmds:SetText(table.concat(ns:CommandLines(), "\n"))

  panel:SetScript("OnShow", function()
    ns:RefreshOptions()
    if lang then lang.Refresh() end
  end)
  -- Настройки закрыли: окно EasyCraft возвращается на обычный слой.
  panel:SetScript("OnHide", function()
    local f = ns.UI and ns.UI.frame
    if f then f:SetFrameStrata("HIGH") end
  end)
  -- Галочки ставим сразу: страница видима с создания, и при первом
  -- открытии настроек OnShow может не сработать.
  ns:RefreshOptions()
  panel:Hide()

  if Settings and Settings.RegisterCanvasLayoutCategory then
    settingsCategory = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(settingsCategory)
  end
end

-- Выбор языка: подпись, выпадающий список, пояснение и кнопка перезагрузки.
function ns:LanguageDropdown(parent)
  local T = ns.T
  local box = CreateFrame("Frame", nil, parent)
  box:SetSize(560, 66)
  local label = box:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  label:SetPoint("TOPLEFT", 0, 0)
  label:SetText(T("Язык"))
  local note = box:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  note:SetJustifyH("LEFT")
  local reload = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
  reload:SetSize(200, 24)
  reload:SetText(T("Перезагрузить интерфейс"))
  reload:SetScript("OnClick", function() ReloadUI() end)
  local function Changed()
    local changed = ns.ResolveLang(ns.db and ns.db.lang) ~= ns.lang
    note:SetText(changed and T("Язык сменится после перезагрузки интерфейса.") or "")
    reload:SetShown(changed)
  end
  local ok, dd = pcall(CreateFrame, "DropdownButton", nil, box, "WowStyle1DropdownTemplate")
  if ok and dd and dd.SetupMenu then
    dd:SetWidth(240)
    dd:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -8)
    dd:SetupMenu(function(_, root)
      for _, l in ipairs(ns.LANGS) do
        local text = l.code == "auto" and T(l.label) or l.label
        local r = root:CreateRadio(text, function() return ((ns.db and ns.db.lang) or "auto") == l.code end, function()
          if ns.db then ns.db.lang = l.code end
          Changed()
        end)
        if l.code ~= "auto" and not ns.READY[l.code] and r then
          if r.SetEnabled then r:SetEnabled(false) end
          if r.SetTooltip then
            r:SetTooltip(function(tip) tip:SetText(T("Перевода на этот язык пока нет.")) end)
          end
        end
      end
    end)
    -- кнопка перезагрузки в той же строке, пояснение под списком
    reload:SetPoint("LEFT", dd, "RIGHT", 12, 0)
    note:SetPoint("TOPLEFT", dd, "BOTTOMLEFT", 2, -6)
  else
    box:SetHeight(76)
    note:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -8)
    reload:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -10)
  end
  box.Refresh = Changed
  box:SetScript("OnShow", Changed)
  Changed()
  return box
end

function ns:OpenSettings()
  if not settingsCategory then
    self:ToggleFrame()
    return
  end
  if Settings and Settings.OpenToCategory and settingsCategory.GetID then
    Settings.OpenToCategory(settingsCategory:GetID())
  end
end
