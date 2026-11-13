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
  { "itemTips", "Подсказки: сколько предмета нужно до учителя, цвет жилы и травы" },
  { "ahTip", "Подсказки: цена предмета на аукционе" },
  { "trainerStars", "Окно учителя: звезда у рецептов, нужных маршруту" },
  { "ahScan", "Аукцион: читать цены самому при открытии" }, { "ahRemind", "Аукцион: напоминать в чате при входе о старых ценах" },
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
  { "/ec help", "снова показать знакомство" },
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

  local title = body:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText("|cff33ff99Easy|rCraft")

  -- Язык EasyCraft (выбор - в EasyCraftDB.lang, меняется после перезагрузки)
  local lang = ns:LanguageDropdown(body)
  lang:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -14)

  local sub = body:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  sub:SetPoint("TOPLEFT", lang, "BOTTOMLEFT", 0, -6)
  sub:SetWidth(560)
  sub:SetJustifyH("LEFT")
  sub:SetText(ns.T("Прокачка профессий WoW Forever: текущий шаг и цель, кнопки создания, учителя и рецепты, точки на карте."))

  local open = ns.W.Button(body, ns.T("Открыть окно"), 200, 28)
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

  local intro = ns.W.Button(body, ns.T("Как пользоваться"), 200, 28)
  intro:SetPoint("LEFT", open, "RIGHT", 10, 0)
  intro:SetScript("OnClick", function()
    ns.UI:Create()
    ns.UI.frame:SetFrameStrata("DIALOG")
    ns:ShowIntro()
    ns.UI.frame:Raise()
  end)

  -- отправить автору наблюдения цветов рецептов (Seen.lua)
  local share = ns.W.Button(body, ns.T("Отправить данные"), 200, 28)
  share:SetPoint("LEFT", intro, "RIGHT", 10, 0)
  share:SetScript("OnClick", function() if ns.ShareColors then ns:ShareColors() end end)

  -- выбор профессии: окно поверх настроек игры
  local choose = ns.W.Button(body, ns.T("Выбор профессии"), 200, 28)
  choose:SetPoint("TOPLEFT", open, "BOTTOMLEFT", 0, -8)
  choose:SetScript("OnClick", function()
    ns:ShowChoose()
    local win = EasyCraftChooseFrame
    if win then
      win:SetFrameStrata("DIALOG")
      win:Raise()
    end
  end)

  -- Всё ниже кнопок - одним столбцом сверху вниз: разделы с линией под
  -- заголовком, галочки, кнопки, ползунки. y - где встанет следующий элемент.
  local list = CreateFrame("Frame", nil, body)
  list:SetSize(600, 10)
  local LABEL_FONT = _G.GameFontHighlightMedium or GameFontHighlight
  local function NewHeader(text)
    local h = CreateFrame("Frame", nil, list)
    h:SetSize(580, 28)
    local fs = h:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    fs:SetPoint("TOPLEFT", 0, 0)
    fs:SetText(text)
    local line = h:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.25)
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT", 0, 0)
    line:SetPoint("BOTTOMRIGHT", 0, 0)
    return h
  end
  list:SetPoint("TOPLEFT", choose, "BOTTOMLEFT", -16, -6)
  local y = 0
  local function Header(text)
    y = y + 18
    NewHeader(text):SetPoint("TOPLEFT", 16, -y)
    y = y + 28 + 8
  end
  local OPT = {}
  for _, o in ipairs(OPTIONS) do OPT[o[1]] = o end
  panel.checks = {}
  local function Check(key)
    local o = OPT[key]
    local c = ns.W.Check(list, ns.T(o[2]))
    c:SetSize(30, 30)
    c.label:SetFontObject(LABEL_FONT)
    c:SetPoint("TOPLEFT", 14, -y)
    c.opt = o[1]
    c:SetScript("OnClick", function(self)
      local v = self:GetChecked() and true or false
      if o[3] then o[3](v) else ns.settings[o[1]] = v end
      ns:RefreshAll()
    end)
    panel.checks[#panel.checks + 1] = c
    y = y + 32
  end
  -- ползунок: над ним место под подпись, под ним - под цифры краёв
  local function Slider(name, lo, hi, step)
    local ok, sl = pcall(CreateFrame, "Slider", name, list, "OptionsSliderTemplate")
    if not ok or not sl then return nil end
    sl:SetPoint("TOPLEFT", 22, -(y + 24))
    sl:SetWidth(260)
    sl:SetMinMaxValues(lo, hi)
    sl:SetValueStep(step)
    if sl.SetObeyStepOnDrag then sl:SetObeyStepOnDrag(true) end
    y = y + 24 + 17 + 26
    local n = sl:GetName()
    local function part(key)
      local p = sl[key] or (n and _G[n .. key])
      return type(p) == "table" and p.SetText and p or nil
    end
    return sl, part("Text"), part("Low"), part("High")
  end
  local function Row(button)
    button:SetPoint("TOPLEFT", list, "TOPLEFT", 16, -(y + 6))
    y = y + 6 + 26 + 8
  end

  ---------------------------------------------------------------- Общее
  Header(ns.T("Общее"))
  Check("minimap")
  Check("miniGuide")
  Check("hideDone")
  Check("useAlts")
  do
    local sl, label, low, high = Slider("EasyCraftScaleSlider", 0.7, 1.3, 0.05)
    if sl then
      local function ShowValue(v)
        if label then label:SetText(ns.T("Размер окна") .. ": " .. math.floor(v * 100 + 0.5) .. "%") end
      end
      ShowValue(ns.settings.scale or 1)
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
  end

  ------------------------------------------------------------ Подсказки
  Header(ns.T("Подсказки"))
  Check("itemTips")
  Check("ahTip")
  Check("trainerStars")
  Check("askShare")
  Check("hintsLocked")
  -- подсказки, которые перетаскивали, - на прежние места
  local reset = ns.W.Button(list, ns.T("Вернуть подсказки на место"), 260, 26)
  reset:SetScript("OnClick", function()
    ns.db.hintPos = nil
    ns:RefreshAll()
    ns:Print(ns.T("подсказки вернутся на свои места, когда появятся снова."))
  end)
  Row(reset)

  ------------------------------------------------------ Карта и аукцион
  Header(ns.T("Карта и аукцион"))
  Check("ahScan")
  Check("ahRemind")
  -- непрозрачность областей сбора на карте (щелчок по зоне в подсказке)
  do
    local al, alLabel, low, high = Slider("EasyCraftAreaAlphaSlider", 0.1, 1, 0.05)
    if al then
      local function ShowValue(v)
        if alLabel then alLabel:SetText(ns.T("Области сбора на карте: непрозрачность") .. " " .. math.floor(v * 100 + 0.5) .. "%") end
      end
      ShowValue(ns.settings.mapAreaAlpha or 0.5)
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
  end

  -------------------------------------------------------- Команды в чате
  Header(ns.T("Команды в чате"))
  local cmds = list:CreateFontString(nil, "ARTWORK")
  cmds:SetFontObject(LABEL_FONT)
  cmds:SetPoint("TOPLEFT", 16, -y)
  cmds:SetWidth(560)
  cmds:SetJustifyH("LEFT")
  if cmds.SetSpacing then cmds:SetSpacing(5) end
  cmds:SetText(table.concat(ns:CommandLines(), "\n"))
  local listTop = y
  local function FitHeight()
    local h = listTop + (cmds:GetStringHeight() or 200) + 20
    list:SetHeight(h)
    -- сверху над списком: название, язык, описание и два ряда кнопок
    body:SetHeight(250 + h)
  end
  FitHeight()

  panel:SetScript("OnShow", function()
    FitHeight()
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
