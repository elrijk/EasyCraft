local ADDON, TJ = ...

-------------------------------------------------------------------------------
--  Страница аддона в «Настройки -> Модификации -> EasyCraft»
-------------------------------------------------------------------------------
local settingsCategory, panel

-- Подписи галочек - по-русски, переводятся при создании страницы (на
-- ADDON_LOADED язык из настроек уже известен).

local OPTIONS = {
  { "minimap", "Показывать кнопку у миникарты", function(v) TJ:SetMinimapHidden(not v) end },
  { "miniGuide", "Мини-окно рядом с окном профессии", function(v) TJ.settings.miniGuide = v; if TJ.Tracker then TJ.Tracker.hidden = nil end end },
  { "hideDone", "Скрывать выполненные шаги в маршруте" },
  { "mapMine", "Карта мира: мои находки" },
  { "itemTips", "Подсказки: сколько предмета нужно до учителя, цвет жилы и травы" },
  { "trainerStars", "Окно учителя: звезда у рецептов, нужных маршруту" },
  { "hintsLocked", "Закрепить подсказки у окон профессии, банка и аукциона", function(v)
    TJ.settings.hintsLocked = v
    if TJ.W and TJ.W.UpdateLocks then TJ.W.UpdateLocks() end
  end },
}

function TJ:RefreshOptions()
  if not panel then return end
  for _, c in ipairs(panel.checks) do c:SetChecked(TJ.settings[c.opt] and true or false) end
  if panel.scale then panel.scale:SetValue(TJ.settings.scale or 1) end
  if panel.areaAlpha then panel.areaAlpha:SetValue(TJ.settings.mapAreaAlpha or 0.5) end
end

-- Команды чата: список в настройках и по /ec commands (описания по-русски,
-- переводятся при показе).
TJ.COMMANDS = {
  { "/ec", "открыть или закрыть окно" },
  { "/ec help", "снова показать гайды вкладок" },
  { "/ec options", "открыть настройки" },
  { "/ec minimap", "показать или скрыть кнопку у миникарты" },
  { "/ec check", "где маршрут расходится с игрой" },
  { "/ec reset", "сбросить данные этого персонажа" },
  { "/ec commands", "этот список в чат" },
}

function TJ:CommandLines()
  local out = {}
  for _, c in ipairs(TJ.COMMANDS) do out[#out + 1] = "|cffffd100" .. c[1] .. "|r - " .. TJ.T(c[2]) end
  return out
end

function TJ:PrintCommands()
  TJ:Print(TJ.T("команды:"))
  for _, line in ipairs(TJ:CommandLines()) do DEFAULT_CHAT_FRAME:AddMessage("  " .. line) end
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

function TJ:BuildSettings()
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
  local lang = TJ:LanguageDropdown(body)
  lang:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -14)

  local sub = body:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  sub:SetPoint("TOPLEFT", lang, "BOTTOMLEFT", 0, -6)
  sub:SetWidth(560)
  sub:SetJustifyH("LEFT")
  sub:SetText(TJ.T("Прокачка профессий WoW Forever: текущий шаг и цель, кнопки создания, учителя и рецепты, точки на карте."))

  local open = TJ.W.Button(body, TJ.T("Открыть окно"), 200, 26)
  open:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -14)
  open:SetScript("OnClick", function()
    -- Окно настроек игры не закрываем из кода аддона (это «заражает»
    -- настройки), а показываем окно EasyCraft поверх него.
    TJ.UI:Create()
    local f = TJ.UI.frame
    f:SetFrameStrata("DIALOG")
    if not f:IsShown() then TJ:ToggleFrame() end
    f:Raise()
  end)

  local intro = TJ.W.Button(body, TJ.T("Как пользоваться"), 200, 26)
  intro:SetPoint("LEFT", open, "RIGHT", 10, 0)
  intro:SetScript("OnClick", function()
    TJ.UI:Create()
    TJ.UI.frame:SetFrameStrata("DIALOG")
    TJ:ShowIntro()
    TJ.UI.frame:Raise()
  end)

  panel.checks = {}
  local prev = open
  for i, o in ipairs(OPTIONS) do
    local c = TJ.W.Check(body, TJ.T(o[2]))
    c:SetSize(26, 26)
    c.label:SetFontObject("GameFontHighlight")
    c:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", i == 1 and -2 or 0, i == 1 and -14 or -4)
    c.opt = o[1]
    c:SetScript("OnClick", function(self)
      local v = self:GetChecked() and true or false
      if o[3] then o[3](v) else TJ.settings[o[1]] = v end
      TJ:RefreshAll()
    end)
    panel.checks[i] = c
    prev = c
  end

  -- подсказки, которые перетаскивали, - на прежние места
  local reset = TJ.W.Button(body, TJ.T("Вернуть подсказки на место"), 240, 22)
  reset:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 2, -6)
  reset:SetScript("OnClick", function()
    TJ.db.hintPos = nil
    TJ:RefreshAll()
    TJ:Print(TJ.T("подсказки вернутся на свои места, когда появятся снова."))
  end)
  prev = reset

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
      if label then label:SetText(TJ.T("Размер окна") .. ": " .. math.floor(v * 100 + 0.5) .. "%") end
    end
    ShowValue(TJ.settings.scale or 1)
    local low, high = sl.Low or _G[sl:GetName() .. "Low"], sl.High or _G[sl:GetName() .. "High"]
    if low then low:SetText("70%") end
    if high then high:SetText("130%") end
    sl:SetScript("OnValueChanged", function(_, v)
      v = math.floor(v * 20 + 0.5) / 20
      TJ.settings.scale = v
      ShowValue(v)
      if TJ.UI and TJ.UI.frame then TJ.UI.frame:SetScale(v) end
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
      if label then label:SetText(TJ.T("Области сбора на карте: непрозрачность") .. " " .. math.floor(v * 100 + 0.5) .. "%") end
    end
    ShowValue(TJ.settings.mapAreaAlpha or 0.5)
    local low, high = al.Low or _G[al:GetName() .. "Low"], al.High or _G[al:GetName() .. "High"]
    if low then low:SetText("10%") end
    if high then high:SetText("100%") end
    al:SetScript("OnValueChanged", function(_, v)
      v = math.floor(v * 20 + 0.5) / 20
      TJ.settings.mapAreaAlpha = v
      ShowValue(v)
      -- ползунок двигают плавно: перерисовать области раз в 0.05 с, а не на каждый шаг
      if TJ.MapOverlay and WorldMapFrame and WorldMapFrame:IsShown() and not al.pending then
        al.pending = true
        local function go() al.pending = nil; TJ.MapOverlay:Refresh() end
        if C_Timer and C_Timer.After then C_Timer.After(0.05, go) else go() end
      end
    end)
    panel.areaAlpha = al
  end

  -- команды чата
  local cmdHead = body:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  cmdHead:SetPoint("TOPLEFT", al or sl or prev, "BOTTOMLEFT", (al or sl) and -4 or 2, -30)
  cmdHead:SetText(TJ.T("Команды в чате"))
  local cmds = body:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  cmds:SetPoint("TOPLEFT", cmdHead, "BOTTOMLEFT", 0, -8)
  cmds:SetWidth(560)
  cmds:SetJustifyH("LEFT")
  if cmds.SetSpacing then cmds:SetSpacing(4) end
  cmds:SetText(table.concat(TJ:CommandLines(), "\n") .. "\n|cff9d9d9d" .. TJ.T("То же по-русски: /ремесла, /ec помощь, /ec настройки, /ec миникарта.") .. "|r")

  panel:SetScript("OnShow", function()
    TJ:RefreshOptions()
    if lang then lang.Refresh() end
  end)
  -- Настройки закрыли: окно EasyCraft возвращается на обычный слой.
  panel:SetScript("OnHide", function()
    local f = TJ.UI and TJ.UI.frame
    if f then f:SetFrameStrata("HIGH") end
  end)
  -- Галочки ставим сразу: страница видима с создания, и при первом
  -- открытии настроек OnShow может не сработать.
  TJ:RefreshOptions()
  panel:Hide()

  if Settings and Settings.RegisterCanvasLayoutCategory then
    settingsCategory = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(settingsCategory)
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
    settingsCategory = panel
  end
end

-- Выбор языка: подпись, выпадающий список, пояснение и кнопка перезагрузки.
function TJ:LanguageDropdown(parent)
  local T = TJ.T
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
    local changed = TJ.ResolveLang(TJ.db and TJ.db.lang) ~= TJ.lang
    note:SetText(changed and T("Язык сменится после перезагрузки интерфейса.") or "")
    reload:SetShown(changed)
  end
  local ok, dd = pcall(CreateFrame, "DropdownButton", nil, box, "WowStyle1DropdownTemplate")
  if ok and dd and dd.SetupMenu then
    dd:SetWidth(240)
    dd:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -8)
    dd:SetupMenu(function(_, root)
      for _, l in ipairs(TJ.LANGS) do
        local text = l.code == "auto" and T(l.label) or l.label
        local r = root:CreateRadio(text, function() return ((TJ.db and TJ.db.lang) or "auto") == l.code end, function()
          if TJ.db then TJ.db.lang = l.code end
          Changed()
        end)
        if l.code ~= "auto" and not TJ.READY[l.code] and r then
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

function TJ:OpenSettings()
  if not settingsCategory then
    self:ToggleFrame()
    return
  end
  if Settings and Settings.OpenToCategory and settingsCategory.GetID then
    Settings.OpenToCategory(settingsCategory:GetID())
  elseif InterfaceOptionsFrame_OpenToCategory then
    InterfaceOptionsFrame_OpenToCategory(settingsCategory)
    InterfaceOptionsFrame_OpenToCategory(settingsCategory)
  end
end
