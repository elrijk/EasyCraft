local ADDON, TJ = ...

-------------------------------------------------------------------------------
--  Кнопка у миникарты (можно скрыть): ЛКМ - окно, ПКМ - настройки
-------------------------------------------------------------------------------
local button

local function place()
  local a = math.rad(TJ.settings.minimapAngle or 205)
  local r = (Minimap:GetWidth() / 2) + 5
  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

local function create()
  local b = CreateFrame("Button", "EasyCraftMinimapButton", Minimap)
  b:SetSize(31, 31)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")

  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetTexture(TJ.ICON)
  icon:SetSize(19, 19)
  icon:SetPoint("CENTER", 0, 1)
  if b.CreateMaskTexture and icon.AddMaskTexture then
    local mask = b:CreateMaskTexture()
    mask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(icon)
    icon:AddMaskTexture(mask)
  else
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  end
  local ring = b:CreateTexture(nil, "OVERLAY")
  ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  ring:SetSize(53, 53)
  ring:SetPoint("TOPLEFT")
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  hl:SetAllPoints()
  hl:SetBlendMode("ADD")

  b:SetScript("OnClick", function(_, btn)
    if btn == "RightButton" then
      TJ:OpenSettings()
    else
      TJ:ToggleFrame()
    end
  end)
  b:SetScript("OnDragStart", function(self)
    -- кнопку забрал сборщик кнопок (MBB и т. п.) - двигает он, не мы
    if self:GetParent() ~= Minimap then return end
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local x, y = GetCursorPosition()
      local sc = Minimap:GetEffectiveScale()
      TJ.settings.minimapAngle = math.deg(math.atan2(y / sc - my, x / sc - mx))
      place()
    end)
  end)
  b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  -- подсказка в одном виде с MacroCoach: название, что это, свои строки,
  -- потом кнопки мыши (ЛКМ, ПКМ, перетащить)
  b:SetScript("OnEnter", function(self)
    local T = TJ.T
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("|cff33ff99Easy|rCraft")
    GameTooltip:AddLine(T("Прокачка профессий"), 0.7, 0.7, 0.7)
    local list = TJ:LearnedList()
    if #list > 0 then GameTooltip:AddLine(" ") end
    for _, key in ipairs(list) do
      local r, m = TJ:GetSkill(key)
      GameTooltip:AddDoubleLine(TJ:N(TJ.Profs[key]), string.format("%d/%d", r, m), 1, 1, 1, 1, 0.82, 0)
    end
    GameTooltip:AddLine(" ")
    local KEY = "|cffffd100%s|r - %s"
    GameTooltip:AddLine(KEY:format(T("ЛКМ"), T("открыть окно")), 1, 1, 1)
    GameTooltip:AddLine(KEY:format(T("ПКМ"), T("настройки")), 1, 1, 1)
    GameTooltip:AddLine(KEY:format(T("Перетащить"), T("передвинуть кнопку")), 1, 1, 1)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return b
end

function TJ:UpdateMinimapButton()
  if not Minimap then return end
  if not self.settings.minimap then
    if button then button:Hide() end
    return
  end
  -- Ставим у миникарты только при создании: если кнопку забрал сборщик
  -- кнопок (MinimapButtonButton и др.), обратно её не уводим.
  if not button then
    button = create()
    place()
  end
  self.minimapButton = button
  button:Show()
end

function TJ:SetMinimapHidden(hide)
  self.settings.minimap = not hide
  self:UpdateMinimapButton()
  if self.RefreshOptions then self:RefreshOptions() end
end

-- Меню аддонов у миникарты: ЛКМ - окно, ПКМ - настройки.
function EasyCraft_OnAddonCompartmentClick(_, mouseButton)
  if mouseButton == "RightButton" then TJ:OpenSettings() else TJ:ToggleFrame() end
end

function TJ:CreateMinimapButton()
  self:UpdateMinimapButton()
  self:RegisterRefresh(function() TJ:UpdateMinimapButton() end)
end
