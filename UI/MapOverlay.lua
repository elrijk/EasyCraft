local ADDON, TJ = ...
local W = TJ.W
local M = {}
TJ.MapOverlay = M
local format, max = string.format, math.max

local KNOWN_SIZE, MINE_SIZE, MAX_KNOWN = 11, 15, 900
-- Области, где растёт нужное (как в GatherTogether): карта делится на
-- мелкие клетки, клетки, где мест сбора рядом много, сливаются в единые
-- области - ровная полупрозрачная заливка и одна обводка по краю области.
-- Точки по отдельности не рисуем - иначе каша из значков. Непрозрачность -
-- в настройках (mapAreaAlpha).
local AREA_GRID = 44
local WHITE = "Interface\\Buttons\\WHITE8X8"
local floor = math.floor

local function mapFrame() return _G.WorldMapFrame end

function M:Init()
  local map = mapFrame()
  if self.inited or not map or not map.GetCanvas then return end
  self.inited = true
  self.known, self.nknown = {}, 0
  self.mine, self.nmine = {}, 0

  if map.AddDataProvider and MapCanvasDataProviderMixin and CreateFromMixins then
    local p = CreateFromMixins(MapCanvasDataProviderMixin)
    p.RefreshAllData = function() TJ:Safe(M.Refresh, M) end
    p.RemoveAllData = function() M:Clear() end
    p.OnCanvasScaleChanged = function() TJ:Safe(M.Rescale, M) end
    map:AddDataProvider(p)
    self.provider = p
  else
    map:HookScript("OnShow", function() TJ:Safe(M.Refresh, M) end)
    local last
    local poll = CreateFrame("Frame", nil, map)
    poll:SetScript("OnUpdate", function()
      local id = map.GetMapID and map:GetMapID()
      if id ~= last then last = id; TJ:Safe(M.Refresh, M) end
    end)
  end

  -- focus banner ("showing: copper vein ...  [x]")
  local parent = map.ScrollContainer or map
  local banner = CreateFrame("Frame", nil, parent)
  banner:SetSize(360, 22)
  banner:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -8)
  banner:SetFrameLevel((parent:GetFrameLevel() or 1) + 900)
  W.Backdrop(banner, nil, nil, 10, 0, 0, 0, 0.7, 0.7, 0.6, 0.3, 0.9)
  banner.text = W.Font(banner, "GameFontHighlightSmall", "LEFT")
  banner.text:SetPoint("LEFT", 8, 0)
  banner.text:SetPoint("RIGHT", -24, 0)
  banner.text:SetWordWrap(false)
  local x = W.Create("Button", nil, banner, { "UIPanelCloseButton" })
  x:SetSize(22, 22)
  x:SetPoint("RIGHT", 2, 0)
  x:SetScript("OnClick", function() TJ.mapFocus, TJ.mapFocusArea = nil, nil; TJ.mapTarget = nil; M:Refresh() end)
  banner:Hide()
  self.banner = banner

  -- справа внизу карты: вкл/выкл всё от EasyCraft на карте (места сбора,
  -- свои находки, области)
  local tog = CreateFrame("Button", nil, parent)
  tog:SetSize(30, 30)
  tog:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 10, 10)
  tog:SetFrameLevel((parent:GetFrameLevel() or 1) + 900)
  tog.ring = W.RingIcon(tog, 26)
  tog.ring:SetPoint("CENTER")
  tog.ring:SetIcon("Interface\\Icons\\INV_Misc_Flower_02")
  tog:SetScript("OnClick", function()
    TJ.settings.mapShow = not (TJ.settings.mapShow ~= false)
    if TJ.settings.mapShow == false then TJ.mapFocus, TJ.mapFocusArea = nil, nil end
    M:Refresh()
    if GameTooltip:IsOwned(tog) then tog:GetScript("OnEnter")(tog) end
  end)
  tog:SetScript("OnEnter", function(s)
    GameTooltip:SetOwner(s, "ANCHOR_LEFT")
    GameTooltip:SetText("|cff33ff99Easy|rCraft", 1, 1, 1)
    GameTooltip:AddLine(TJ.settings.mapShow ~= false and TJ.T("Места сбора на карте показаны. Щелчок - скрыть.")
      or TJ.T("Места сбора на карте скрыты. Щелчок - показать."), 1, 0.82, 0, true)
    GameTooltip:Show()
  end)
  tog:SetScript("OnLeave", function() GameTooltip:Hide() end)
  self.toggle = tog

  -- над ним - что сейчас показано (области трав или метка учителя):
  -- значок того, что показано, с крестиком; щелчок - убрать
  local cur = CreateFrame("Button", nil, parent)
  cur:SetSize(30, 30)
  cur:SetPoint("BOTTOM", tog, "TOP", 0, 6)
  cur:SetFrameLevel((parent:GetFrameLevel() or 1) + 900)
  cur.ring = W.RingIcon(cur, 26)
  cur.ring:SetPoint("CENTER")
  cur.x = cur:CreateTexture(nil, "OVERLAY", nil, 3)
  cur.x:SetSize(13, 13)
  cur.x:SetPoint("BOTTOMRIGHT", 2, -1)
  cur.x:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
  cur:SetScript("OnClick", function()
    TJ.mapFocus, TJ.mapFocusArea, TJ.mapTarget = nil, nil, nil
    GameTooltip:Hide()
    M:Refresh()
  end)
  cur:SetScript("OnEnter", function(s)
    GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
    GameTooltip:SetText("|cff33ff99Easy|rCraft", 1, 1, 1)
    GameTooltip:AddLine(s.what or "", 1, 0.82, 0, true)
    GameTooltip:AddLine(TJ.T("Щелчок - убрать с карты."), 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)
  cur:SetScript("OnLeave", function() GameTooltip:Hide() end)
  cur:Hide()
  self.current = cur

  TJ:RegisterRefresh(function() if map:IsShown() then M:Refresh() end end)
end

function M:Overlay()
  local map = mapFrame()
  local canvas = map:GetCanvas()
  if not self.overlay or self.overlay:GetParent() ~= canvas then
    self.overlay = CreateFrame("Frame", nil, canvas)
    self.overlay:SetAllPoints(canvas)
  end
  self.overlay:SetFrameLevel((canvas:GetFrameLevel() or 1) + 800)
  self.overlay:Show()
  return self.overlay, canvas
end

function M:Clear()
  self.sig = nil -- нарисованного больше нет: следующий Refresh рисует заново
  for i = 1, self.nknown or 0 do self.known[i]:Hide() end
  for i = 1, self.nmine or 0 do self.mine[i]:Hide() end
  for i = 1, self.narea or 0 do self.area[i]:Hide() end
  self.nknown, self.nmine, self.narea = 0, 0, 0
end

function M:AreaTex(parent, layer)
  self.area = self.area or {}
  self.narea = (self.narea or 0) + 1
  local t = self.area[self.narea]
  if not t then
    t = parent:CreateTexture(nil, "ARTWORK")
    t:SetTexture(WHITE)
    self.area[self.narea] = t
  end
  if t:GetParent() ~= parent then t:SetParent(parent) end
  t:SetDrawLayer("ARTWORK", layer or 1)
  t:ClearAllPoints()
  t:Show()
  return t
end

-- Подсветить области, где больше всего нужного (keys) на этой карте.
-- 1) места сбора по клеткам; 2) клетка в области, если рядом (3x3) мест
-- достаточно; 3) область чуть расширяем, чтобы края были плавнее;
-- 4) заливка - полосами по строкам, обводка - только по краю области.
function M:DrawAreas(overlay, keys, mapID, w, h, scale)
  local G = AREA_GRID
  local cnt = {}
  local function idx(cx, cy) return cy * G + cx end
  for _, key in ipairs(keys) do
    local packed = TJ.Spawns[key] and TJ.Spawns[key][mapID]
    if packed then
      for i = 1, #packed, 6 do
        local x = tonumber(packed:sub(i, i + 2)) / 1000
        local y = tonumber(packed:sub(i + 3, i + 5)) / 1000
        local cx, cy = math.min(G - 1, floor(x * G)), math.min(G - 1, floor(y * G))
        local k = idx(cx, cy)
        cnt[k] = (cnt[k] or 0) + 1
      end
    end
  end
  if not next(cnt) then return end
  -- плотность рядом
  local dens, most = {}, 0
  for k in pairs(cnt) do
    local cx, cy = k % G, floor(k / G)
    for dy = -1, 1 do
      for dx = -1, 1 do
        local nx, ny = cx + dx, cy + dy
        if nx >= 0 and ny >= 0 and nx < G and ny < G then
          local j = idx(nx, ny)
          if dens[j] == nil then
            local sum = 0
            for ey = -1, 1 do
              for ex = -1, 1 do
                local ax, ay = nx + ex, ny + ey
                if ax >= 0 and ay >= 0 and ax < G and ay < G then sum = sum + (cnt[idx(ax, ay)] or 0) end
              end
            end
            dens[j] = sum
            if sum > most then most = sum end
          end
        end
      end
    end
  end
  local need = max(2, most * 0.1)
  local core = {}
  for j, d in pairs(dens) do if d >= need then core[j] = true end end
  -- расширить на клетку: края плавнее, дырки внутри закрываются
  local inA = {}
  for j in pairs(core) do
    local cx, cy = j % G, floor(j / G)
    for dy = -1, 1 do
      for dx = -1, 1 do
        local nx, ny = cx + dx, cy + dy
        if nx >= 0 and ny >= 0 and nx < G and ny < G and (dx == 0 or dy == 0) then inA[idx(nx, ny)] = true end
      end
    end
  end
  local a = TJ.settings.mapAreaAlpha or 0.5
  local cw, ch = w / G, h / G
  local line = 2 / (scale or 1)
  local function rect(x1, y1, x2, y2, r, g, b, al, layer)
    local t = self:AreaTex(overlay, layer)
    t:SetVertexColor(r, g, b, al)
    t:SetPoint("TOPLEFT", overlay, "TOPLEFT", x1, -y1)
    t:SetPoint("BOTTOMRIGHT", overlay, "TOPLEFT", x2, -y2)
  end
  for cy = 0, G - 1 do
    local run
    for cx = 0, G do
      local on = cx < G and inA[idx(cx, cy)]
      if on and not run then run = cx end
      if not on and run then
        rect(run * cw, cy * ch, cx * cw, (cy + 1) * ch, 0.3, 0.62, 1, 0.28 * a, 1)
        run = nil
      end
    end
  end
  -- обводка: горизонтальные края (сверху/снизу клетки нет области)
  for cy = 0, G - 1 do
    for side = 0, 1 do
      local run
      for cx = 0, G do
        local edge = cx < G and inA[idx(cx, cy)] and not inA[idx(cx, cy + (side == 0 and -1 or 1))]
          or (cx < G and inA[idx(cx, cy)] and ((side == 0 and cy == 0) or (side == 1 and cy == G - 1)))
        if edge and not run then run = cx end
        if not edge and run then
          local yy = (cy + side) * ch
          rect(run * cw, yy - line / 2, cx * cw, yy + line / 2, 0.6, 0.88, 1, 0.9 * a, 2)
          run = nil
        end
      end
    end
  end
  -- вертикальные края
  for cx = 0, G - 1 do
    for side = 0, 1 do
      local run
      for cy = 0, G do
        local nb = cx + (side == 0 and -1 or 1)
        local edge = cy < G and inA[idx(cx, cy)] and (nb < 0 or nb >= G or not inA[idx(nb, cy)])
        if edge and not run then run = cy end
        if not edge and run then
          local xx = (cx + side) * cw
          rect(xx - line / 2, run * ch, xx + line / 2, cy * ch, 0.6, 0.88, 1, 0.9 * a, 2)
          run = nil
        end
      end
    end
  end
end

function M:KnownTex(parent)
  self.nknown = self.nknown + 1
  local t = self.known[self.nknown]
  if not t then
    t = parent:CreateTexture(nil, "OVERLAY")
    self.known[self.nknown] = t
  end
  t:ClearAllPoints()
  t:Show()
  return t
end

function M:MinePin(parent)
  self.nmine = self.nmine + 1
  local b = self.mine[self.nmine]
  if not b then
    b = CreateFrame("Button", nil, parent)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.ring = b:CreateTexture(nil, "OVERLAY")
    b.ring:SetPoint("CENTER")
    W.SetTex(b.ring, "Interface\\Minimap\\MiniMap-TrackingBorder", 0, 0, 0, 0)
    b:SetScript("OnEnter", function(s)
      GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
      GameTooltip:AddLine(s.title or "", 1, 0.82, 0)
      if s.count then GameTooltip:AddLine(format(TJ.T("Собрано здесь: %d"), s.count), 1, 1, 1) end
      if s.when then GameTooltip:AddLine(TJ.T("Последний раз: ") .. date("%d.%m %H:%M", s.when), 0.7, 0.7, 0.7) end
      GameTooltip:AddLine("EasyCraft", 0.5, 0.5, 0.5)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.mine[self.nmine] = b
  end
  b:SetParent(parent)
  b:SetFrameLevel(parent:GetFrameLevel() + 2)
  b:ClearAllPoints()
  b:Show()
  return b
end

-- Ресурс на карте: то, что сейчас даёт навык изученной профессии сбора.
function M:NodeShown(key)
  local n = TJ.Nodes[key]
  if not n then return false end
  local rank, _, learned = TJ:GetSkill(n.prof)
  if not learned then return false end
  local c = TJ:GatherColor(max(rank, 1), n.req)
  return c ~= "red" and c ~= "gray"
end

function M:VisibleNodeKeys()
  if TJ.mapFocus then return TJ.mapFocus end
  local out = {}
  for _, key in ipairs(TJ.NodeOrder) do
    if self:NodeShown(key) then tinsert(out, key) end
  end
  return out
end

local function canvasScale(map)
  local s = map.GetCanvasScale and map:GetCanvasScale()
  return (s and s > 0) and s or 1
end

function M:Refresh()
  local map = mapFrame()
  if not (self.inited and map and map:IsShown()) then return end
  local on = TJ.settings.mapShow ~= false
  if self.toggle then
    self.toggle.ring.icon:SetDesaturated(not on)
    self.toggle.ring:SetAlpha(on and 1 or 0.6)
  end
  if not on then
    self:Clear()
    self.banner:Hide()
    if self.current then self.current:Hide() end
    return
  end
  local overlay, canvas = self:Overlay()
  local w, h = canvas:GetSize()
  if not w or w <= 0 then self:Clear(); return end
  local mapID = map:GetMapID()
  local scale = canvasScale(map)

  local keys = self:VisibleNodeKeys()
  -- Перерисовка аддона (сумки, добыча) при открытой карте: если на карте
  -- ничего не поменялось, сотни точек заново не ставим.
  local tg = TJ.mapTarget
  local sig = table.concat({ tostring(overlay), mapID or 0, floor(w), floor(h), table.concat(keys, ","),
    tostring(TJ.mapFocus), tostring(TJ.settings.mapKnown), tostring(TJ.settings.mapMine), tostring(TJ.settings.mapAreaAlpha),
    tg and (tostring(tg.ui) .. ":" .. tostring(tg.x) .. ":" .. tostring(tg.y)) or "-", TJ.nodeGen or 0, TJ.itemGen or 0 }, "|")
  if sig == self.sig then return end
  self:Clear()
  self.sig = sig
  -- плашку сверху больше не показываем (налезала на значки других аддонов):
  -- что показано - круглым значком слева внизу, щелчок убирает
  self.banner:Hide()
  local cur = self.current
  if cur then
    if TJ.mapFocus then
      local names, first = {}, nil
      for _, k in ipairs(keys) do
        local n = TJ.Nodes[k]
        if n then first = first or n; tinsert(names, TJ:N(n)) end
      end
      cur.ring:SetIcon(first and TJ:ItemIcon(first.item) or "Interface\\Icons\\INV_Misc_Flower_02")
      cur.what = TJ.T("Показаны области: ") .. table.concat(names, ", ")
      cur:Show()
    elseif TJ.mapTarget then
      cur.ring:SetIcon("Interface\\Icons\\INV_Misc_Book_11")
      cur.what = TJ.T("Метка: ") .. (TJ.mapTarget.title or "")
      cur:Show()
    else
      cur:Hide()
    end
  end

  -- показать на карте из шага: области, где растёт нужное, и сами места ярче
  if TJ.mapFocus then self:DrawAreas(overlay, keys, mapID, w, h, scale) end
  if TJ.settings.mapKnown and not TJ.mapFocus then
    do
      for _, key in ipairs(keys) do
        local packed = TJ.Spawns[key] and TJ.Spawns[key][mapID]
        if packed then
          local icon = TJ:ItemIcon(TJ.Nodes[key].item)
          for i = 1, #packed, 6 do
            if self.nknown >= MAX_KNOWN then break end
            local x = tonumber(packed:sub(i, i + 2)) / 1000
            local y = tonumber(packed:sub(i + 3, i + 5)) / 1000
            local t = self:KnownTex(overlay)
            t:SetTexture(icon)
            t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            t:SetAlpha(TJ.mapFocus and 0.95 or 0.6)
            local ks = TJ.mapFocus and KNOWN_SIZE + 3 or KNOWN_SIZE
            t:SetSize(ks / scale, ks / scale)
            t:SetPoint("CENTER", overlay, "TOPLEFT", x * w, -y * h)
          end
        end
      end
    end
  end

  local tg = TJ.mapTarget
  if tg and tg.ui == mapID then
    local b = self:MinePin(overlay)
    b.icon:SetTexture("Interface\\GossipFrame\\TrainerGossipIcon")
    b.title, b.count, b.when = tg.title, nil, nil
    b.base = 22 -- метка учителя крупнее точек сбора
    local s = 22 / scale
    b:SetSize(s, s)
    b.ring:SetSize(s * 2.65, s * 2.65)
    b.ring:SetPoint("CENTER", b, "CENTER", s * 0.55, -s * 0.55)
    b:SetPoint("CENTER", overlay, "TOPLEFT", tg.x * w, -tg.y * h)
  end

  if TJ.settings.mapMine then
    local list = TJ.db.nodes[mapID]
    for _, n in ipairs(list or {}) do
      local key = n[3]
      local node = TJ.Nodes[key]
      local icon, title
      if key == "fish" then
        icon, title = TJ.Icon("Trade_Fishing"), TJ.T("Место рыбалки")
      elseif node then
        icon, title = TJ:ItemIcon(node.item), TJ:N(node)
      else
        local id = tonumber(tostring(key):match("item:(%d+)"))
        icon, title = id and TJ:ItemIcon(id) or TJ.Icon(nil), id and TJ:ItemName(id) or "?"
      end
      local b = self:MinePin(overlay)
      b.icon:SetTexture(icon)
      b.title, b.count, b.when = title, n[4], n[5]
      b.base = MINE_SIZE
      local s = MINE_SIZE / scale
      b:SetSize(s, s)
      b.ring:SetSize(s * 2.65, s * 2.65)
      b.ring:SetPoint("CENTER", b, "CENTER", s * 0.55, -s * 0.55)
      b:SetPoint("CENTER", overlay, "TOPLEFT", n[1] * w, -n[2] * h)
    end
  end
end

function M:Rescale()
  local map = mapFrame()
  if not map then return end
  -- области: толщина обводки зависит от масштаба - перерисовать, но один
  -- раз в конце приближения (событие идёт каждый кадр анимации)
  if (self.narea or 0) > 0 then
    if not self.rescalePending then
      self.rescalePending = true
      local function go() self.rescalePending = nil; self.sig = nil; TJ:Safe(M.Refresh, M) end
      if C_Timer and C_Timer.After then C_Timer.After(0.05, go) else go() end
    end
    return
  end
  local scale = canvasScale(map)
  local ks = TJ.mapFocus and KNOWN_SIZE + 3 or KNOWN_SIZE
  for i = 1, self.nknown or 0 do self.known[i]:SetSize(ks / scale, ks / scale) end
  for i = 1, self.nmine or 0 do
    local b = self.mine[i]
    local s = (b.base or MINE_SIZE) / scale
    b:SetSize(s, s)
    b.ring:SetSize(s * 2.65, s * 2.65)
    b.ring:SetPoint("CENTER", b, "CENTER", s * 0.55, -s * 0.55)
  end
end

function M:OpenMap(uiMapID)
  local map = mapFrame()
  if not map then return end
  if not map:IsShown() and InCombatLockdown and InCombatLockdown() then
    TJ:Print(TJ.T("в бою карту из аддона не открыть: открой её сам (M)."))
    return
  end
  if TJ.UI and TJ.UI.frame then TJ.UI.frame:Hide() end
  if not map:IsShown() then
    if ToggleWorldMap then ToggleWorldMap() elseif ShowUIPanel then ShowUIPanel(map) end
  end
  if uiMapID and map.SetMapID then map:SetMapID(uiMapID) end
  self:Init()
  self:Refresh()
end
