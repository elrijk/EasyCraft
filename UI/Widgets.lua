local ADDON, TJ = ...
local W = {}
TJ.W = W

-------------------------------------------------------------------------------
--  Оформление в стиле MacroCoach: рамка окна игры, пергамент книги
--  заклинаний, тёмные карточки с бронзовой рамкой, золотые заголовки,
--  светлый основной текст и серый дополнительный.
-------------------------------------------------------------------------------
W.GOLD = { 1, 0.82, 0 }
W.LIGHT = { 0.92, 0.92, 0.92 }
W.GREY = { 0.62, 0.62, 0.62 }
W.GREEN = { 0.3, 0.9, 0.3 }
W.RED = { 1, 0.35, 0.35 }

-- Create a frame with the first template that exists in this client.
function W.Create(ftype, name, parent, templates)
  for _, t in ipairs(templates or {}) do
    local ok, f = pcall(CreateFrame, ftype, name, parent, t)
    if ok and f then return f, t end
  end
  return CreateFrame(ftype, name, parent), nil
end

local hasFileCheck = type(GetFileIDFromPath) == "function"
function W.TexExists(path)
  if not hasFileCheck or type(path) ~= "string" then return true end
  return GetFileIDFromPath(path) ~= nil
end

-- Set the first existing texture; otherwise a flat colour.
function W.SetTex(tex, paths, r, g, b, a)
  if type(paths) == "string" then paths = { paths } end
  for _, p in ipairs(paths or {}) do
    if W.TexExists(p) then
      tex:SetTexture(p)
      return true
    end
  end
  tex:SetColorTexture(r or 0, g or 0, b or 0, a or 0.6)
  return false
end

function W.HasAtlas(name)
  return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

function W.Backdrop(frame, bg, edge, edgeSize, r, g, b, a, br, bgc, bb, ba)
  if not frame.SetBackdrop then
    if BackdropTemplateMixin then Mixin(frame, BackdropTemplateMixin) else return end
  end
  frame:SetBackdrop({
    bgFile = bg or "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = edge or "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = edgeSize or 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  frame:SetBackdropColor(r or 0, g or 0, b or 0, a or 0.85)
  frame:SetBackdropBorderColor(br or 0.6, bgc or 0.5, bb or 0.3, ba or 1)
end

function W.Font(parent, template, justify, layer)
  local fs = parent:CreateFontString(nil, layer or "OVERLAY", template or "GameFontHighlightSmall")
  if justify then fs:SetJustifyH(justify) end
  return fs
end

-- Шрифты: заголовок, подзаголовок, основной текст, дополнительный (серый).
W.FONTS = {
  huge = { "SystemFont_Huge1", "GameFontNormalHuge", W.GOLD }, -- заголовок страницы (как в MacroCoach)
  title = { "SystemFont_Large", "GameFontNormalLarge", W.GOLD },
  head = { "SystemFont_Med3", "GameFontNormal", W.GOLD },
  body = { "SystemFont_Med2", "GameFontHighlight", W.LIGHT },
  small = { "SystemFont_Med1", "GameFontHighlightSmall", W.GREY },
}

function W.Text(parent, kind, wrap)
  local spec = W.FONTS[kind] or W.FONTS.body
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFontObject(_G[spec[1]] or _G[spec[2]] or GameFontNormal)
  fs:SetTextColor(spec[3][1], spec[3][2], spec[3][3], 1)
  fs:SetShadowOffset(0, 0)
  fs:SetJustifyH("LEFT")
  fs:SetJustifyV("TOP")
  fs:SetWordWrap(wrap ~= false)
  fs.kind = kind
  return fs
end

function W.Sound(kit)
  if PlaySound and SOUNDKIT and SOUNDKIT[kit] then PlaySound(SOUNDKIT[kit]) end
end

function W.Button(parent, text, width, height)
  local b = W.Create("Button", nil, parent, { "UIPanelButtonTemplate" })
  b:SetSize(width or 100, height or 22)
  b:SetText(text or "")
  if not b:GetFontString() then
    local fs = W.Font(b, "GameFontNormal")
    fs:SetPoint("CENTER")
    b:SetFontString(fs)
    b:SetText(text or "")
  end
  return b
end

function W.Check(parent, label)
  local c = W.Create("CheckButton", nil, parent, { "UICheckButtonTemplate", "OptionsCheckButtonTemplate" })
  c:SetSize(24, 24)
  c.label = c.text or c.Text or W.Font(c, "GameFontHighlightSmall", "LEFT")
  c.label:ClearAllPoints()
  c.label:SetPoint("LEFT", c, "RIGHT", 2, 1)
  c.label:SetText(label or "")
  return c
end

-- Классическая полоса прокрутки, как в окне талантов и журнале заданий.
function W.ScrollTrack(sf)
  -- Тёмная подложка под полосой прокрутки, чтобы пергамент не просвечивал.
  local back = sf:CreateTexture(nil, "BACKGROUND", nil, -8)
  back:SetColorTexture(0.04, 0.03, 0.03, 0.92)
  back:SetPoint("TOPLEFT", sf, "TOPRIGHT", 0, 6)
  back:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", 30, -6)
  local file = "Interface\\PaperDollInfoFrame\\UI-Character-ScrollBar"
  local top = sf:CreateTexture(nil, "ARTWORK")
  top:SetTexture(file)
  top:SetSize(31, 102)
  top:SetPoint("TOPLEFT", sf, "TOPRIGHT", -2, 5)
  top:SetTexCoord(0, 0.484375, 0, 0.4)
  local bottom = sf:CreateTexture(nil, "ARTWORK")
  bottom:SetTexture(file)
  bottom:SetSize(31, 106)
  bottom:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", -2, -2)
  bottom:SetTexCoord(0.515625, 1, 0, 0.4140625)
  local mid = sf:CreateTexture(nil, "ARTWORK")
  mid:SetTexture(file)
  mid:SetWidth(31)
  mid:SetPoint("TOP", top, "BOTTOM")
  mid:SetPoint("BOTTOM", bottom, "TOP")
  mid:SetTexCoord(0, 0.484375, 0.75, 1)
  if type(sf.ScrollBar) == "table" then sf.ScrollBar.scrollStep = 60 end
end

-- Вкладка сбоку, как в книге заклинаний.
function W.SideTab(parent)
  local tab = CreateFrame("CheckButton", nil, parent)
  tab:SetSize(32, 32)
  local bg = tab:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
  bg:SetSize(64, 64)
  bg:SetPoint("TOPLEFT", -3, 11)
  tab.icon = tab:CreateTexture(nil, "ARTWORK")
  tab.icon:SetAllPoints()
  tab:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  tab:SetCheckedTexture("Interface\\Buttons\\CheckButtonHilight")
  local checked = tab:GetCheckedTexture()
  if checked and checked.SetBlendMode then checked:SetBlendMode("ADD") end
  tab:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
    GameTooltip:SetText(self.tip or "")
    if self.tip2 then GameTooltip:AddLine(self.tip2, 1, 1, 1) end
    GameTooltip:Show()
  end)
  tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return tab
end

-- Вкладка сверху: форма вкладки окна макросов игры, круглый значок в кольце
-- и название (как вкладки специализаций в MacroCoach).
W.TAB_H = 40
local TAB_ICON = 22 -- кольцо вокруг значка не должно вылезать за край вкладки
local TAB_ART = {
  normal = { "uiframe-tab-left", "_uiframe-tab-center", "uiframe-tab-right" },
  active = { "uiframe-activetab-left", "_uiframe-activetab-center", "uiframe-activetab-right" },
}

local function TabArt(b, names, layer, active)
  local parts = {}
  local ok = W.HasAtlas(names[1]) and W.HasAtlas(names[2]) and W.HasAtlas(names[3])
  for i = 1, 3 do
    local t = b:CreateTexture(nil, layer)
    if ok then
      t:SetAtlas(names[i], true)
      t:SetTexCoord(0, 1, 1, 0.25)
    else
      t:SetTexture(active and "Interface\\PaperDollInfoFrame\\UI-Character-ActiveTab"
        or "Interface\\PaperDollInfoFrame\\UI-Character-InActiveTab")
      local l, r = ({ 0, 0.15625, 0.84375 })[i], ({ 0.15625, 0.84375, 1 })[i]
      t:SetTexCoord(l, r, 1, 0)
      if i ~= 2 then t:SetWidth(20) end
    end
    t:SetHeight(W.TAB_H)
    parts[i] = t
  end
  local l, m, r = parts[1], parts[2], parts[3]
  l:SetPoint("BOTTOMLEFT", active and -1 or -3, 0)
  r:SetPoint("BOTTOMRIGHT", active and 8 or 7, 0)
  m:SetPoint("TOPLEFT", l, "TOPRIGHT")
  m:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT")
  return parts
end

local function ShowParts(parts, on)
  for _, t in ipairs(parts) do t:SetShown(on) end
end

-- Круглая маска и кольцо вокруг значка.
local function RoundMask(owner, tex, size, inset)
  if not (owner.CreateMaskTexture and tex.AddMaskTexture) then
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    return
  end
  local mask = owner:CreateMaskTexture()
  mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  mask:SetPoint("TOPLEFT", tex, "TOPLEFT", inset, -inset)
  mask:SetPoint("BOTTOMRIGHT", tex, "BOTTOMRIGHT", -inset, inset)
  tex:AddMaskTexture(mask)
  return mask
end

local function GoldRing(owner, tex, size)
  local ring = owner:CreateTexture(nil, "OVERLAY")
  local info = W.HasAtlas("Talents-Main-Ring-c60") and C_Texture.GetAtlasInfo("Talents-Main-Ring-c60")
  if info then
    ring:SetAtlas("Talents-Main-Ring-c60", false)
    local k = size / 36
    ring:SetSize((info.width or 48) * k, (info.height or 48) * k)
    ring:SetPoint("CENTER", tex, "CENTER", 0, 0)
  else
    ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    local k = size / 26
    ring:SetSize(48 * k, 48 * k)
    ring:SetPoint("TOPLEFT", tex, "TOPLEFT", -4 * k, 4 * k)
  end
  return ring
end

function W.TopTab(parent)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(W.TAB_H)
  b.normal = TabArt(b, TAB_ART.normal, "BACKGROUND")
  b.active = TabArt(b, TAB_ART.active, "BACKGROUND", true)
  local hl = TabArt(b, TAB_ART.normal, "HIGHLIGHT")
  for _, t in ipairs(hl) do
    t:SetBlendMode("ADD")
    t:SetAlpha(0.4)
  end
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(TAB_ICON, TAB_ICON)
  b.icon:SetPoint("LEFT", 9, -3) -- ближе к краю, по центру видимой части вкладки
  RoundMask(b, b.icon, TAB_ICON, -1)
  b.ring = GoldRing(b, b.icon, TAB_ICON)
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  b.text:SetPoint("LEFT", b.icon, "RIGHT", 5, -1) -- чуть ниже центра значка: по центру видимой вкладки
  function b:SetSelected(on)
    self.selected = on
    ShowParts(self.normal, not on)
    ShowParts(self.active, on)
    self.icon:SetAlpha(on and 1 or 0.8)
    if on then self.text:SetTextColor(1, 1, 1) else self.text:SetTextColor(1, 0.82, 0) end
  end
  -- Как в MacroCoach: одна надпись - одна ширина, длинная - с троеточием,
  -- целиком в подсказке.
  b.text:SetWordWrap(false)
  function b:Fit()
    self.text:SetWidth(0)
    local w = self.text:GetStringWidth() or 60
    self.full = w > 100 and self.text:GetText() or nil
    if self.full then w = 100 end
    self.text:SetWidth(w + 1)
    self:SetWidth(9 + TAB_ICON + 5 + w + 12)
  end
  b:SetScript("OnEnter", function(self)
    if not self.full then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(self.full)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return b
end

-- Круглый значок профессии в золотом кольце.
function W.RingIcon(parent, size)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(size, size)
  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetAllPoints()
  RoundMask(f, f.icon, size, -1)
  f.ring = GoldRing(f, f.icon, size)
  function f:SetIcon(tex) self.icon:SetTexture(tex) end
  return f
end

-------------------------------------------------------------------------------
--  Значок предмета, как в окне профессий WoW Forever: круглый, с кольцом
--  цвета редкости (рамки аукциона игры).
-------------------------------------------------------------------------------
local QUALITY_ATLAS = {
  [0] = "auctionhouse-itemicon-border-gray", [1] = "auctionhouse-itemicon-border-white",
  [2] = "auctionhouse-itemicon-border-green", [3] = "auctionhouse-itemicon-border-blue",
  [4] = "auctionhouse-itemicon-border-purple", [5] = "auctionhouse-itemicon-border-orange",
  [6] = "auctionhouse-itemicon-border-artifact", [7] = "auctionhouse-itemicon-border-account",
}

local GetItemInfoFn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
function W.ItemQuality(id)
  if type(id) ~= "number" then return nil end
  if C_Item and C_Item.GetItemQualityByID then
    local ok, q = pcall(C_Item.GetItemQualityByID, id)
    if ok and type(q) == "number" then return q end
  end
  if GetItemInfoFn then
    local name, _, q = GetItemInfoFn(id)
    if not name then TJ:WantItem(id) end
    if type(q) == "number" then return q end
  end
end

local function InsertLink(link)
  if not link then return end
  local CF = ChatFrameUtil
  if CF and CF.InsertLink and (not CF.GetActiveWindow or CF.GetActiveWindow()) then
    CF.InsertLink(link)
  elseif CF and CF.OpenChat then
    CF.OpenChat(link)
  elseif ChatEdit_InsertLink and ChatEdit_InsertLink(link) then
    return
  elseif ChatFrame_OpenChat then
    ChatFrame_OpenChat(link)
  end
end
W.InsertLink = InsertLink

function W.ItemIcon(parent, size)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(size, size)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetAllPoints()
  b.icon:SetTexCoord(0.078, 0.922, 0.078, 0.922)
  b.mask = RoundMask(b, b.icon, size, size * 2 / 46)
  b.border = b:CreateTexture(nil, "OVERLAY")
  b.border:SetPoint("CENTER")
  b.size = size
  b.count = W.Font(b, "NumberFontNormal", "RIGHT", "OVERLAY")
  b.count:SetPoint("BOTTOMRIGHT", 2, -2)
  -- Подсветка только у значков, по которым есть куда перейти (onClick).
  -- ровный круг той же маской, что и значок (картинка подсветки миникарты
  -- смещена и ложилась криво)
  local hl = b:CreateTexture(nil, "OVERLAY", nil, 1)
  hl:SetAllPoints()
  hl:SetColorTexture(1, 0.9, 0.5, 0.3)
  hl:SetBlendMode("ADD")
  RoundMask(b, hl, size, size * 2 / 46)
  hl:Hide()
  b.hl = hl
  -- gold - золотое кольцо, как у номера шага и значка профессии, вместо
  -- рамки редкости (значок шага). Ставится до SetItem / SetPlain.
  function b:SetQuality(q)
    local s = self.size
    local ring = self.gold and W.HasAtlas("Talents-Main-Ring-c60") and C_Texture.GetAtlasInfo("Talents-Main-Ring-c60")
    if self.mask then
      local inset = ring and -1 or s * 2 / 46
      self.mask:ClearAllPoints()
      self.mask:SetPoint("TOPLEFT", self.icon, "TOPLEFT", inset, -inset)
      self.mask:SetPoint("BOTTOMRIGHT", self.icon, "BOTTOMRIGHT", -inset, inset)
    end
    if ring then
      self.border:SetAtlas("Talents-Main-Ring-c60", false)
      self.border:SetVertexColor(1, 1, 1)
      self.border:SetSize((ring.width or 48) * s / 36, (ring.height or 48) * s / 36)
      return
    end
    local atlas = QUALITY_ATLAS[q or 1] or QUALITY_ATLAS[1]
    if W.HasAtlas(atlas) then
      self.border:SetAtlas(atlas, false)
      self.border:SetVertexColor(1, 1, 1)
      self.border:SetSize(s * 68 / 46, s * 68 / 46)
    else
      -- Нет атласа: квадратная рамка игры, окрашенная цветом редкости.
      self.border:SetTexture("Interface\\Common\\WhiteIconFrame")
      self.border:SetSize(s, s)
      local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q or 1]
      if c then self.border:SetVertexColor(c.r, c.g, c.b) else self.border:SetVertexColor(1, 1, 1) end
    end
  end
  -- Предмет: значок, рамка по редкости, подсказка, Shift-клик - ссылка в чат.
  function b:SetItem(id, count)
    self.itemID, self.spellID = id, nil
    self.icon:SetTexture(TJ:ItemIcon(id))
    self:SetQuality(W.ItemQuality(id) or 1)
    self.count:SetText(count and count > 1 and tostring(count) or "")
  end
  -- Не предмет (заклинание, профессия): белая рамка.
  function b:SetPlain(tex, spellID)
    self.itemID, self.spellID = nil, spellID
    self.icon:SetTexture(tex)
    self:SetQuality(1)
    self.count:SetText("")
  end
  b:SetScript("OnEnter", function(self)
    if self.onClick then self.hl:Show() end
    if not (self.itemID or self.spellID or self.tip) then return end
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
    if type(self.itemID) == "number" then
      if GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.itemID) else GameTooltip:SetHyperlink("item:" .. self.itemID) end
    elseif self.spellID and GameTooltip.SetSpellByID then
      GameTooltip:SetSpellByID(self.spellID)
    end
    if self.tip then GameTooltip:AddLine(self.tip, 0.8, 0.8, 0.8, true) end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function(self) self.hl:Hide(); GameTooltip:Hide() end)
  b:SetScript("OnClick", function(self)
    if IsModifiedClick and IsModifiedClick("CHATLINK") and type(self.itemID) == "number" then
      local _, link = GetItemInfoFn(self.itemID)
      InsertLink(link)
      return
    end
    if self.onClick then self.onClick(self) end
  end)
  return b
end

-------------------------------------------------------------------------------
--  Квадратная ячейка со значком, как в книге заклинаний и MacroCoach:
--  тёмная подложка, рамка ячейки панели, в углу - число (сколько ещё),
--  справа вверху - галочка. glow - золотое свечение кнопки (текущий шаг).
--  Мышь не ловит: ею занимается то, на чём ячейка лежит.
-------------------------------------------------------------------------------
function W.Slot(parent, size)
  local b = CreateFrame("Frame", nil, parent)
  b:SetSize(size, size)
  local k = size / 37
  local back = b:CreateTexture(nil, "BACKGROUND")
  back:SetColorTexture(0, 0, 0, 0.6)
  back:SetPoint("TOPLEFT", -1, 1)
  back:SetPoint("BOTTOMRIGHT", 1, -1)
  b.tex = b:CreateTexture(nil, "BORDER")
  b.tex:SetAllPoints()
  b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b.border = b:CreateTexture(nil, "ARTWORK")
  b.border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
  b.border:SetSize(64 * k, 64 * k)
  b.border:SetPoint("CENTER")
  -- свечение, как у кнопки на панели (надетый предмет, готовое умение)
  b.glow = b:CreateTexture(nil, "OVERLAY")
  b.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
  b.glow:SetBlendMode("ADD")
  b.glow:SetSize(size * 62 / 36, size * 62 / 36)
  b.glow:SetPoint("CENTER")
  b.glow:SetVertexColor(1, 0.82, 0, 0.9)
  b.glow:Hide()
  b.count = W.Font(b, "NumberFontNormal", "RIGHT", "OVERLAY")
  b.count:SetPoint("BOTTOMRIGHT", -2, 2)
  b.mark = b:CreateTexture(nil, "OVERLAY", nil, 2)
  b.mark:SetSize(size * 0.55, size * 0.55)
  b.mark:SetPoint("TOPRIGHT", size * 0.18, size * 0.18) -- галочка - в правом верхнем углу
  b.mark:Hide()
  function b:Set(tex, count, mark, grey, glow)
    self.tex:SetTexture(tex or TJ.Icon(nil))
    self.tex:SetDesaturated(grey and true or false)
    self.tex:SetAlpha(grey and 0.75 or 1)
    self.count:SetText(count and count > 0 and tostring(count) or "")
    if mark == "ok" then self.mark:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    elseif mark == "no" then self.mark:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
    elseif mark == "wait" then self.mark:SetTexture("Interface\\RaidFrame\\ReadyCheck-Waiting") end
    self.mark:SetShown(mark ~= nil)
    self.glow:SetShown(glow and true or false)
  end
  return b
end

-- Подсказка GameTooltip: строка, функция (её итог) или { title =, color =, lines = { "текст" |
-- { left, right } | { text, color = {r,g,b} } }, hint = серым внизу }.
function W.FillTip(t)
  if type(t) == "function" then t = t() end -- считается только при наведении
  if type(t) ~= "table" then
    GameTooltip:SetText(t or "", 1, 1, 1, 1, true)
    return
  end
  local c = t.color or W.GOLD
  GameTooltip:SetText(t.title or "", c[1], c[2], c[3], 1, true)
  for _, l in ipairs(t.lines or {}) do
    if type(l) == "string" then
      GameTooltip:AddLine(l, 0.92, 0.92, 0.92, true)
    elseif l[2] then
      GameTooltip:AddDoubleLine(l[1], l[2], 0.92, 0.92, 0.92, 0.92, 0.92, 0.92)
    else
      local lc = l.color or W.LIGHT
      GameTooltip:AddLine(l[1], lc[1], lc[2], lc[3], true)
    end
  end
  if t.hint then GameTooltip:AddLine(t.hint, 0.6, 0.6, 0.6, true) end
end

-------------------------------------------------------------------------------
--  Подсказки у окон игры (профессия, банк, аукцион): их можно перетащить
--  мышкой, место запоминается. Замочек в углу (и настройка) закрепляет все
--  подсказки; правый щелчок по замочку возвращает подсказку на её место.
-------------------------------------------------------------------------------
-- значок на красной кнопке: замок - закреплены, стрелки - можно двигать
local LOCK_ON = { "Interface\\PetBattles\\PetBattle-LockIcon", "Interface\\LFGFrame\\UI-LFG-ICON-LOCK" }
local LOCK_OFF = { "Interface\\CURSOR\\UI-Cursor-Move", "Interface\\CURSOR\\Point" }
local movers = {}

function W.UpdateLocks()
  local locked = TJ.settings and TJ.settings.hintsLocked
  for _, f in ipairs(movers) do
    local b = f.lockBtn
    if b then
      W.SetTex(b.tex, locked and LOCK_ON or LOCK_OFF, 1, 0.82, 0, 1)
      b.tex:SetDesaturated(false)
      b:SetAlpha(1)
    end
  end
end

-- Поставить подсказку туда, куда её перетащили (true), или ничего (false).
function W.PlaceSaved(f, key)
  if f.dragging then return true end -- тащат прямо сейчас: не мешать
  local p = TJ.db and TJ.db.hintPos and TJ.db.hintPos[key]
  if not p then return false end
  local s = f:GetScale() or 1
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p.x / s, p.y / s)
  return true
end

-- Сделать подсказку перетаскиваемой; corner - угол замочка (TOPRIGHT/TOPLEFT),
-- ox, oy, size - его сдвиг и размер.
function W.Movable(f, key, corner, ox, oy, size)
  f.moveKey = key
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(s)
    if TJ.settings.hintsLocked then return end
    s.dragging = true
    s:StartMoving()
  end)
  f:SetScript("OnDragStop", function(s)
    s:StopMovingOrSizing()
    s.dragging = nil
    local sc = s:GetScale() or 1
    local l, t = s:GetLeft(), s:GetTop()
    if l and t then
      TJ.db.hintPos = TJ.db.hintPos or {}
      TJ.db.hintPos[key] = { x = l * sc, y = t * sc }
      W.PlaceSaved(s, key)
    end
  end)
  -- красная кнопка игры со значком (подсветка при наведении - её же)
  local b = W.Button(f, "", size or 24, 22)
  if corner == "TOPLEFT" then b:SetPoint("TOPLEFT", ox or 6, oy or -6) else b:SetPoint("TOPRIGHT", ox or -6, oy or -6) end
  b:SetFrameLevel(f:GetFrameLevel() + 30)
  b.tex = b:CreateTexture(nil, "OVERLAY")
  b.tex:SetSize(14, 14)
  b.tex:SetPoint("CENTER", 0, 0)
  if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  b:SetScript("OnClick", function(_, button)
    if button == "RightButton" then
      if TJ.db.hintPos then TJ.db.hintPos[key] = nil end
      TJ:RefreshAll()
      return
    end
    TJ.settings.hintsLocked = not TJ.settings.hintsLocked
    W.UpdateLocks()
    if TJ.RefreshOptions then TJ:RefreshOptions() end
  end)
  b:SetScript("OnEnter", function(s)
    GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
    local locked = TJ.settings.hintsLocked
    GameTooltip:SetText(locked and TJ.T("Подсказки закреплены") or TJ.T("Подсказки можно двигать"), 1, 0.82, 0)
    GameTooltip:AddLine(locked and TJ.T("Щелчок - открепить: тогда их можно перетащить мышкой.")
      or TJ.T("Перетащи подсказку мышкой - место запомнится. Щелчок - закрепить."), 1, 1, 1, true)
    GameTooltip:AddLine(TJ.T("Правый щелчок - вернуть эту подсказку на место."), 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  f.lockBtn = b
  tinsert(movers, f)
  W.UpdateLocks()
end

-------------------------------------------------------------------------------
--  Подсказка у окна игры в одном виде с подсказкой у окна профессии:
--  светлый пергамент, заголовок чернилами, строки - тёмные блоки.
--  f:Head(i) - заголовок части, f:Row(i) - строка-кнопка предмета,
--  f:CheckHead(i) - заголовок части с галочкой.
-------------------------------------------------------------------------------
local INK_T, INK_B = { 0.16, 0.08, 0 }, { 0.24, 0.14, 0.04 }
W.INK_T, W.INK_B = INK_T, INK_B
W.HINT_PAD, W.HINT_ROW = 12, 34

-- Шапка с названием аддона над подсказкой: полоса во всю ширину на
-- верхнем крае, по центру - значок аддона и «EasyCraft». Чья подсказка,
-- видно сразу; раскладку самой подсказки не трогает.
function W.Brand(f)
  local b = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
  if b.SetBackdrop then
    b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    b:SetBackdropColor(0.07, 0.05, 0.03, 0.97)
    b:SetBackdropBorderColor(0.6, 0.48, 0.25, 1)
  end
  b:SetHeight(30)
  -- нижний край полосы заходит на рамку подсказки
  b:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, -4)
  b:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, -4)
  b:SetFrameLevel(f:GetFrameLevel() + 20)
  -- значок и название блоком по центру полосы
  local box = CreateFrame("Frame", nil, b)
  box:SetHeight(20)
  local icon = box:CreateTexture(nil, "ARTWORK")
  icon:SetSize(20, 20)
  icon:SetPoint("LEFT", 0, 0)
  icon:SetTexture(TJ.ICON)
  if box.CreateMaskTexture and icon.AddMaskTexture then
    -- круглый, как значок у миникарты
    local mask = box:CreateMaskTexture()
    mask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(icon)
    icon:AddMaskTexture(mask)
  end
  local text = box:CreateFontString(nil, "OVERLAY")
  text:SetFontObject(_G.SystemFont_Med3 or _G.GameFontNormalMed2 or GameFontNormal)
  text:SetPoint("LEFT", icon, "RIGHT", 6, -1)
  text:SetText("|cff33ff99Easy|r|cffffd100Craft|r")
  box:SetWidth(20 + 6 + math.ceil(text:GetStringWidth() or 60))
  box:SetPoint("CENTER", b, "CENTER", 0, 0)
  f.brand = b
  return b
end

function W.HintPanel(name, width, title, key)
  local f = CreateFrame("Frame", name, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  f:SetWidth(width)
  f.w = width
  if f.SetBackdrop then
    f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    f:SetBackdropColor(0.05, 0.045, 0.04, 0.95)
    f:SetBackdropBorderColor(0.6, 0.48, 0.25, 1)
  end
  local parch = f:CreateTexture(nil, "BACKGROUND", nil, 1)
  parch:SetPoint("TOPLEFT", 4, -4)
  parch:SetPoint("BOTTOMRIGHT", -4, 4)
  W.Parchment(parch)
  f:SetFrameStrata("HIGH")
  f:SetClampedToScreen(true)
  -- заголовок как «Шаг 7» в подсказке у окна профессии: крупно, чернилами
  f.title = W.Text(f, "huge", false)
  f.title:SetTextColor(INK_T[1], INK_T[2], INK_T[3])
  f.title:SetPoint("TOPLEFT", W.HINT_PAD, -12)
  f.title:SetText(title or "")
  f.top = 12 + 34 -- где начинается содержимое
  f.heads, f.rows, f.checks = {}, {}, {}
  f.note = W.Text(f, "small")
  f.note:SetTextColor(INK_B[1], INK_B[2], INK_B[3])
  f.note:SetWidth(width - W.HINT_PAD * 2)
  f.btn = W.Button(f, "", width - W.HINT_PAD * 2, 22)
  if key then W.Movable(f, key, "TOPRIGHT") end
  W.Brand(f)
  function f:Reset()
    for _, h in ipairs(self.heads) do h:Hide() end
    for _, r in ipairs(self.rows) do r:Hide() end
    for _, c in ipairs(self.checks) do c:Hide() end
    self.note:Hide()
    if self.btn2 then self.btn2:Hide() end
    self.nh, self.nr, self.nc = 0, 0, 0
  end
  -- заголовок части чернилами в точке y; вернёт новый y
  function f:Head(text, y)
    self.nh = self.nh + 1
    local h = self.heads[self.nh]
    if not h then
      h = W.Text(self, "head", false)
      h:SetTextColor(INK_T[1], INK_T[2], INK_T[3])
      h:SetWidth(self.w - W.HINT_PAD * 2)
      self.heads[self.nh] = h
    end
    h:SetText(text)
    h:ClearAllPoints()
    h:SetPoint("TOPLEFT", self, "TOPLEFT", W.HINT_PAD, -y)
    h:Show()
    return y + h:GetStringHeight() + 4
  end
  -- заголовок с галочкой слева и числом справа, всё по одной линии
  function f:CheckHead(text, right, on, onClick, y)
    self.nc = self.nc + 1
    local c = self.checks[self.nc]
    if not c then
      c = CreateFrame("Frame", nil, self)
      c:SetHeight(24)
      c.check = W.Check(c, "")
      c.check:SetPoint("LEFT", c, "LEFT", -4, 0)
      c.text = W.Text(c, "head", false)
      c.text:SetPoint("LEFT", c.check, "RIGHT", 2, -1)
      c.right = W.Text(c, "body", false)
      c.right:SetJustifyH("RIGHT")
      c.right:SetPoint("RIGHT", c, "RIGHT", 0, -1)
      self.checks[self.nc] = c
    end
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", self, "TOPLEFT", W.HINT_PAD, -y)
    c:SetWidth(self.w - W.HINT_PAD * 2)
    local col = on and INK_T or { 0.45, 0.4, 0.33 }
    c.text:SetTextColor(col[1], col[2], col[3])
    c.right:SetTextColor(INK_B[1], INK_B[2], INK_B[3])
    c.text:SetText(text)
    c.right:SetText(right or "")
    c.check:SetChecked(on and true or false)
    c.check:SetScript("OnClick", function(cb) onClick(cb:GetChecked() and true or false) end)
    c:Show()
    return y + 26
  end
  -- строка предмета: значок, название (цвет редкости), справа текст и значок
  -- (лупа - найти, галочка - брать); d = { id, text, right, mark, dim, tip, onClick }
  function f:Row(d, y)
    self.nr = self.nr + 1
    local r = self.rows[self.nr]
    if not r then
      r = CreateFrame("Button", nil, self, BackdropTemplateMixin and "BackdropTemplate" or nil)
      W.Backdrop(r, "Interface\\Buttons\\WHITE8X8", nil, 10, 0.05, 0.045, 0.04, 0.9, 0.6, 0.48, 0.25, 0.8)
      r.icon = r:CreateTexture(nil, "ARTWORK")
      r.icon:SetSize(22, 22)
      r.icon:SetPoint("LEFT", 6, 0)
      r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      r.mark = r:CreateTexture(nil, "ARTWORK")
      r.mark:SetSize(16, 16)
      r.mark:SetPoint("RIGHT", -8, 0)
      r.right = W.Text(r, "small", false)
      r.right:SetJustifyH("RIGHT")
      -- буквы шрифта сидят выше середины строки: текст на 1 ниже - ровно по
      -- центру значков
      r.right:SetPoint("RIGHT", r, "RIGHT", -30, -1)
      r.text = W.Text(r, "body", false)
      r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, -1)
      r.text:SetPoint("RIGHT", r.right, "LEFT", -6, 0)
      r.text:SetWordWrap(false)
      local hl = r:CreateTexture(nil, "HIGHLIGHT")
      hl:SetPoint("TOPLEFT", 2, -2)
      hl:SetPoint("BOTTOMRIGHT", -2, 2)
      hl:SetColorTexture(1, 0.82, 0, 0.1)
      r:SetScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
        if s.itemID and GameTooltip.SetItemByID then
          GameTooltip:SetItemByID(s.itemID)
          if s.tip then GameTooltip:AddLine(s.tip, 1, 0.82, 0, true) end
        elseif s.tip then
          GameTooltip:SetText(s.tip, 1, 1, 1, 1, true)
        end
        GameTooltip:Show()
      end)
      r:SetScript("OnLeave", function() GameTooltip:Hide() end)
      self.rows[self.nr] = r
    end
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", self, "TOPLEFT", W.HINT_PAD - 4, -y)
    r:SetSize(self.w - W.HINT_PAD * 2 + 8, W.HINT_ROW)
    r.icon:SetTexture(d.id and TJ:ItemIcon(d.id) or d.tex or TJ.Icon(nil))
    r.icon:SetDesaturated(d.dim and true or false)
    r:SetAlpha(d.dim and 0.6 or 1)
    if d.id then
      local qr, qg, qb = TJ:ItemQualityColor(d.id)
      r.text:SetTextColor(qr or 1, qg or 1, qb or 1)
    else
      r.text:SetTextColor(0.92, 0.92, 0.92)
    end
    r.text:SetText(d.text or (d.id and TJ:ItemName(d.id)) or "")
    r.right:SetText(d.right or "")
    if d.mark then r.mark:SetTexture(d.mark); r.mark:Show() else r.mark:Hide() end
    r.mark:SetDesaturated(d.markGrey and true or false)
    -- у лупы стекло сверху: опустить, чтобы на глаз была по центру
    r.mark:ClearAllPoints()
    r.mark:SetPoint("RIGHT", -8, d.markY or 0)
    r.right:ClearAllPoints()
    r.right:SetPoint("RIGHT", r, "RIGHT", d.mark and -30 or -8, -1)
    r.itemID, r.tip = d.id, d.tip
    local fn = d.onClick
    r:SetScript("OnClick", fn and function() W.Sound("IG_MAINMENU_OPTION_CHECKBOX_ON"); fn() end or nil)
    r:Show()
    return y + W.HINT_ROW + 3
  end
  -- текст под строками (чернилами)
  function f:Note(text, y)
    self.note:SetText(text)
    self.note:ClearAllPoints()
    self.note:SetPoint("TOPLEFT", self, "TOPLEFT", W.HINT_PAD, -y)
    self.note:Show()
    return y + self.note:GetStringHeight() + 6
  end
  -- кнопка внизу; вернёт полную высоту подсказки. second - вторая кнопка
  -- (под первой)
  function f:Button(text, enabled, onClick, tip, y, second)
    local b = self.btn
    if second then
      self.btn2 = self.btn2 or W.Button(self, "", width - W.HINT_PAD * 2, 22)
      b = self.btn2
    end
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", self, "TOPLEFT", W.HINT_PAD, -(y + 2))
    b:SetText(text)
    b:SetEnabled(enabled and true or false)
    if b.SetMotionScriptsWhileDisabled then b:SetMotionScriptsWhileDisabled(true) end
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(s)
      if not tip then return end
      GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
      GameTooltip:SetText("|cff33ff99Easy|rCraft")
      GameTooltip:AddLine(type(tip) == "function" and tip() or tip, 1, 1, 1, true)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Show()
    return y + 2 + 22 + 12
  end
  f:Reset()
  f:Hide()
  return f
end

-- Строка предмета: значок и текст - одна кнопка. Наведение показывает
-- подсказку предмета, Shift-клик - ссылка в чат. Подсветка - только если
-- по строке есть куда перейти (onClick).
function W.ItemRow(parent, size)
  local b = CreateFrame("Button", nil, parent)
  b.icon = W.ItemIcon(b, size)
  b.icon:SetPoint("LEFT", 0, 0)
  b.icon:EnableMouse(false)
  b.text = W.Text(b, "body", false)
  b.sub = W.Text(b, "small", false)
  b.hl = b:CreateTexture(nil, "BACKGROUND")
  b.hl:SetAllPoints()
  b.hl:SetColorTexture(1, 0.82, 0, 0.1)
  b.hl:Hide()
  function b:Set(it)
    self.itemID, self.tip, self.onClick = it.id, it.tip, it.onClick
    if it.id then self.icon:SetItem(it.id) else self.icon:SetPlain(it.tex or TJ.Icon(nil)) end
    self.text:SetText(it.text or "")
    self.sub:SetText(it.sub or "")
    self.text:ClearAllPoints()
    self.sub:ClearAllPoints()
    if it.sub and it.sub ~= "" then
      -- две строки - блоком по центру значка
      local hT, hS = self.text:GetStringHeight() or 14, self.sub:GetStringHeight() or 12
      local off = math.floor((hT + 3 + hS) / 2 + 0.5)
      self.text:SetPoint("TOPLEFT", self.icon, "RIGHT", 10, off - 1)
      self.sub:SetPoint("TOPLEFT", self.text, "BOTTOMLEFT", 0, -3)
      self.sub:SetPoint("RIGHT", self, "RIGHT", 0, 0)
    else
      self.text:SetPoint("LEFT", self.icon, "RIGHT", 10, -1)
    end
    self.text:SetPoint("RIGHT", self, "RIGHT", 0, (it.sub and it.sub ~= "") and 0 or -1)
  end
  b:SetScript("OnEnter", function(self)
    if self.onClick then self.hl:Show() end
    if not (self.itemID or self.tip) then return end
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
    if type(self.itemID) == "number" then
      if GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.itemID) else GameTooltip:SetHyperlink("item:" .. self.itemID) end
      if self.tip then GameTooltip:AddLine(self.tip, 0.8, 0.8, 0.8, true) end
    else
      GameTooltip:SetText(self.tip, 1, 1, 1, 1, true)
    end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function(self) self.hl:Hide(); GameTooltip:Hide() end)
  b:SetScript("OnClick", function(self)
    if IsModifiedClick and IsModifiedClick("CHATLINK") and type(self.itemID) == "number" then
      local _, link = GetItemInfoFn(self.itemID)
      InsertLink(link)
      return
    end
    if self.onClick then self.onClick(self) end
  end)
  return b
end

-- Полоса прогресса навыка.
function W.Bar(parent)
  local bar = CreateFrame("StatusBar", nil, parent)
  bar:SetHeight(14)
  -- заливка как у навыков в классике (окно персонажа, «Навыки»): с бликом;
  -- нет такой картинки в игре - обычная полоса
  local fill = "Interface\\TargetingFrame\\UI-StatusBar"
  if W.TexExists("Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar") then
    fill = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar"
  end
  bar:SetStatusBarTexture(fill)
  bar:SetStatusBarColor(0.15, 0.6, 0.15)
  bar:SetMinMaxValues(0, 1)
  bar.bg = bar:CreateTexture(nil, "BACKGROUND")
  bar.bg:SetAllPoints()
  bar.bg:SetColorTexture(0, 0, 0, 0.75)
  bar.edge = CreateFrame("Frame", nil, bar, BackdropTemplateMixin and "BackdropTemplate" or nil)
  bar.edge:SetPoint("TOPLEFT", -3, 3)
  bar.edge:SetPoint("BOTTOMRIGHT", 3, -3)
  if bar.edge.SetBackdrop then
    bar.edge:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10 })
    bar.edge:SetBackdropBorderColor(0.6, 0.48, 0.25, 1)
  end
  bar.text = W.Text(bar.edge, "small", false)
  bar.text:SetTextColor(1, 1, 1)
  bar.text:SetJustifyH("CENTER")
  bar.text:SetPoint("CENTER", bar, "CENTER", 0, 0)
  -- подписи по краям: слева ранг, справа «87 из 300»
  bar.left = W.Text(bar.edge, "small", false)
  bar.left:SetTextColor(1, 1, 1)
  bar.left:SetPoint("LEFT", bar, "LEFT", 6, 0)
  bar.right = W.Text(bar.edge, "small", false)
  bar.right:SetTextColor(1, 1, 1)
  bar.right:SetJustifyH("RIGHT")
  bar.right:SetPoint("RIGHT", bar, "RIGHT", -6, 0)
  return bar
end

-- Тонкая золотая черта на полосе (с какого навыка брать следующий ранг)
-- и подсказка к ней при наведении на полосу. value = nil - убрать черту.
local function PlaceBarMark(bar)
  local m = bar.mark
  if not (m and bar.markFrac) then return end
  local x = math.floor((bar:GetWidth() or 0) * bar.markFrac + 0.5)
  m:ClearAllPoints()
  m:SetPoint("TOP", bar, "TOPLEFT", x, 0)
  m:SetPoint("BOTTOM", bar, "BOTTOMLEFT", x, 0)
end

-- Полоса ловит только наведение (подсказка черты), щелчки идут дальше - в
-- строку-кнопку под ней. EnableMouse(true) вернул бы и щелчки.
local function BarHover(bar, on)
  if bar.SetMouseMotionEnabled then
    pcall(bar.SetMouseMotionEnabled, bar, on)
    if bar.SetMouseClickEnabled then pcall(bar.SetMouseClickEnabled, bar, false) end
  else
    bar:EnableMouse(on)
    if on and bar.SetMouseClickEnabled then pcall(bar.SetMouseClickEnabled, bar, false) end
  end
end

function W.SetBarMark(bar, value, maxValue, tipTitle, tipText)
  if not (value and maxValue and maxValue > 0 and value > 0 and value < maxValue) then
    if bar.mark then bar.mark:Hide() end
    bar.markFrac, bar.markTip = nil, nil
    -- без черты полоса мышь не ловит: под ней строка-кнопка (главная)
    BarHover(bar, false)
    return
  end
  if not bar.mark then
    -- на самой полосе, под подписями: текст остаётся читаемым
    local m = bar:CreateTexture(nil, "OVERLAY")
    m:SetColorTexture(1, 0.82, 0, 0.95)
    m:SetWidth(2)
    bar.mark = m
    bar:HookScript("OnSizeChanged", PlaceBarMark)
    bar:EnableMouse(true)
    -- только наведение: щелчки идут дальше, в карточку
    if bar.SetMouseClickEnabled then pcall(bar.SetMouseClickEnabled, bar, false) end
    bar:HookScript("OnEnter", function(self)
      if not self.markTip then return end
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText(self.markTip[1], 1, 0.82, 0)
      if self.markTip[2] then GameTooltip:AddLine(self.markTip[2], 1, 1, 1, true) end
      GameTooltip:Show()
    end)
    bar:HookScript("OnLeave", function() GameTooltip:Hide() end)
  end
  BarHover(bar, true) -- полосу могли взять из запаса без черты
  bar.markFrac = value / maxValue
  bar.markTip = tipTitle and { tipTitle, tipText } or nil
  PlaceBarMark(bar)
  bar.mark:Show()
end

-- Деньги: значки золота, серебра и меди игры.
-- Пергамент: страница книги заклинаний игры (без рамок по краям); нет
-- атласа - ровный цвет пергамента.
function W.Parchment(tex)
  local info = W.HasAtlas("spellbook-Page-Right-C60") and C_Texture.GetAtlasInfo("spellbook-Page-Right-C60")
  local file = info and (info.file or info.filename)
  if file and info.leftTexCoord and info.topTexCoord then
    local l, r, t, b = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
    local w, h = r - l, b - t
    tex:SetTexture(file)
    tex:SetTexCoord(l + w * 0.025, r - w * 0.02, t + h * 0.085, b - h * 0.025)
  elseif info then
    tex:SetAtlas("spellbook-Page-Right-C60", false)
  else
    tex:SetColorTexture(0.86, 0.77, 0.6)
  end
end

function W.Money(copper)
  copper = math.floor((copper or 0) + 0.5)
  if GetMoneyString then
    local ok, s = pcall(GetMoneyString, copper, true)
    if ok and s then return s end
  end
  local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
  local out = {}
  if g > 0 then out[#out + 1] = "|cffffd700" .. g .. TJ.T("з") .. "|r" end
  if s > 0 or g > 0 then out[#out + 1] = "|cffc7c7cf" .. s .. TJ.T("с") .. "|r" end
  out[#out + 1] = "|cffeda55f" .. c .. TJ.T("м") .. "|r"
  return table.concat(out, " ")
end

-------------------------------------------------------------------------------
--  Значки не выходят за край текста: кольцо редкости и золотое кольцо
--  шире самого значка. Отступ, на который значок сдвигается вправо, чтобы
--  его внешний край совпал с краем текста.
-------------------------------------------------------------------------------
function W.IconPad(size)
  if W.HasAtlas("auctionhouse-itemicon-border-white") then return math.floor(size * 11 / 46 + 0.5) end
  return 0
end

function W.RingPad(size)
  if W.HasAtlas("Talents-Main-Ring-c60") then
    local info = C_Texture.GetAtlasInfo("Talents-Main-Ring-c60")
    return math.floor(((info and info.width or 48) * size / 36 - size) / 2 + 0.5)
  end
  return math.floor(4 * size / 26 + 0.5)
end

-------------------------------------------------------------------------------
--  Картинка «реагенты -> результат», как «Было -> Макрос» в MacroCoach:
--  значки реагентов с «есть/нужно» под каждым, стрелка, значок результата.
--  Наведение - подсказка предмета и что с ним делать (it.tip).
--  flow:Set(inputs, output) -> ширина и высота.
--  inputs: { { id =, text =, tip = } }, output: { id = | tex =, text =, tip = }
-------------------------------------------------------------------------------
local FLOW_MAX = 6
function W.Flow(parent, size)
  local f = CreateFrame("Frame", nil, parent)
  f.size = size
  local pad = W.IconPad(size)
  f.pad = pad
  f.ins, f.labels = {}, {}
  for i = 1, FLOW_MAX + 1 do
    local b = W.ItemIcon(f, size)
    local l = W.Text(f, "small", false)
    l:SetFontObject(_G.SystemFont_Small or GameFontHighlightSmall)
    l:SetJustifyH("CENTER")
    f.ins[i], f.labels[i] = b, l
  end
  f.arrow = f:CreateTexture(nil, "ARTWORK")
  f.arrow:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
  f.arrow:SetSize(28, 28)
  function f:Set(inputs, output)
    local s, p = self.size, self.pad
    local n = math.min(#inputs, FLOW_MAX)
    for i = 1, FLOW_MAX + 1 do self.ins[i]:Hide(); self.labels[i]:Hide() end
    -- x - внешний левый край кольца; right - внешний правый край последнего
    local right = 0
    local function place(i, it, x)
      local b, l = self.ins[i], self.labels[i]
      if it.id then b:SetItem(it.id) else b:SetPlain(it.tex or TJ.Icon(nil), it.spell) end
      b.tip, b.onClick = it.tip, it.onClick
      -- реагента хватает - зелёная галочка в углу
      if not b.check then
        b.check = b:CreateTexture(nil, "OVERLAY", nil, 3)
        b.check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
        b.check:SetSize(s * 0.5, s * 0.5)
        b.check:SetPoint("TOPRIGHT", b, "TOPRIGHT", p * 0.6, p * 0.6) -- галочка - справа вверху
      end
      b.check:SetShown(it.done and true or false)
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", self, "TOPLEFT", x + p, -p)
      b:Show()
      l:SetText(it.text or "")
      l:ClearAllPoints()
      l:SetPoint("TOP", b, "BOTTOM", 0, self.labelGap or (-p - 2))
      l:SetShown((it.text or "") ~= "")
      right = x + s + p * 2
    end
    -- кольца уже дают просвет: значки почти вплотную
    for i = 1, n do place(i, inputs[i], i == 1 and 0 or right + 2) end
    self.arrow:Hide()
    if output then
      local x = 0
      if n > 0 then
        self.arrow:ClearAllPoints()
        self.arrow:SetPoint("LEFT", self, "TOPLEFT", right + 1, -(p + s / 2))
        self.arrow:Show()
        x = right + 1 + 28 + 1
      end
      place(FLOW_MAX + 1, output, x)
    end
    local h = s + p * 2 + (self.labelH or 16)
    self:SetSize(math.max(right, 1), h)
    return right, h
  end
  return f
end

-------------------------------------------------------------------------------
--  «Использовать» для предмета из сумок. Предмет можно применить только
--  защищённой кнопкой игры: она одна на весь аддон и встаёт поверх
--  обычной кнопки, пока на неё наведён курсор. Так сами карточки остаются
--  обычными и спокойно перерисовываются.
-------------------------------------------------------------------------------
local useOverlay
local function UseOverlay()
  if useOverlay then return useOverlay end
  local o = CreateFrame("Button", "EasyCraftUseItemButton", UIParent, "SecureActionButtonTemplate")
  o:RegisterForClicks("AnyUp", "AnyDown")
  o:SetAttribute("type", "item")
  o:Hide()
  o:SetScript("OnEnter", function(self)
    if not self.itemID then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.itemID) end
    GameTooltip:Show()
  end)
  o:SetScript("OnLeave", function(self)
    GameTooltip:Hide()
    if self.owner then self.owner:UnlockHighlight() end
    self.owner = nil
    if not InCombatLockdown() then self:Hide() end
  end)
  -- после щелчка карточка может перерисоваться: кнопку убираем
  o:HookScript("OnClick", function(self)
    if self.owner then self.owner:UnlockHighlight() end
  end)
  -- окно закрыли, прокрутили или курсор ушёл: невидимую кнопку убрать
  o:SetScript("OnUpdate", function(self)
    if InCombatLockdown() then return end
    if not (self.owner and self.owner:IsVisible() and self.owner.itemID == self.itemID and self.owner:IsMouseOver()) then
      if self.owner then self.owner:UnlockHighlight() end
      self.owner = nil
      self:Hide()
    end
  end)
  -- Перед боем убрать: в бою её уже не спрятать, и она осталась бы
  -- невидимой, но живой кнопкой на экране.
  o:RegisterEvent("PLAYER_REGEN_DISABLED")
  o:SetScript("OnEvent", function(self)
    if self.owner then self.owner:UnlockHighlight() end
    self.owner = nil
    self:Hide()
  end)
  useOverlay = o
  return o
end

function W.UseButton(parent)
  local b = W.Button(parent, TJ.T("Использовать"), 120, 22)
  b:SetScript("OnEnter", function(self)
    if not self.itemID then return end
    if InCombatLockdown() then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(TJ.T("В бою предметы отсюда не применить."), 1, 1, 1, 1, true)
      GameTooltip:Show()
      return
    end
    local o = UseOverlay()
    -- по координатам экрана, без привязки к карточке
    local l, bt, w, h = self:GetLeft(), self:GetBottom(), self:GetWidth(), self:GetHeight()
    if not (l and bt) then return end
    local k = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
    o:ClearAllPoints()
    o:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l * k, bt * k)
    o:SetSize(w * k, h * k)
    o:SetFrameStrata(self:GetFrameStrata())
    o:SetFrameLevel(self:GetFrameLevel() + 10)
    o:SetAttribute("item", "item:" .. self.itemID)
    o.itemID, o.owner = self.itemID, self
    self:LockHighlight()
    o:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return b
end

-------------------------------------------------------------------------------
--  Меню из строк в рамке подсказки (как выпадающие списки игры).
--  W.Menu(anchor, { { text =, onClick =, enabled =, tip = } })
-------------------------------------------------------------------------------
local menu
function W.Menu(anchor, list)
  -- повторный щелчок по той же кнопке закрывает меню
  if menu and menu:IsShown() and menu.anchor == anchor then menu:Hide(); return menu end
  if not menu then
    menu = CreateFrame("Frame", "EasyCraftMenu", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    W.Backdrop(menu, nil, nil, 14, 0.05, 0.045, 0.04, 0.95, 0.6, 0.48, 0.25, 1)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    menu.rows = {}
    tinsert(UISpecialFrames, "EasyCraftMenu")
    -- щелчок мимо меню закрывает его
    menu:SetScript("OnShow", function(self) self.t = 0 end)
    menu:SetScript("OnUpdate", function(self, el)
      self.t = (self.t or 0) + el
      if self.anchor and self.anchor:IsMouseOver() then return end -- щелчок по своей кнопке - она и решит
      if self.t > 0.3 and not self:IsMouseOver() and IsMouseButtonDown and (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")) then
        self:Hide()
      end
    end)
  end
  for _, r in ipairs(menu.rows) do r:Hide() end
  local y, w = 8, 160
  for i, d in ipairs(list) do
    local r = menu.rows[i]
    if not r then
      r = CreateFrame("Button", nil, menu)
      r:SetHeight(20)
      r.text = W.Text(r, "body", false)
      r.text:SetPoint("LEFT", 8, 0)
      local hl = r:CreateTexture(nil, "HIGHLIGHT")
      hl:SetAllPoints()
      hl:SetColorTexture(1, 0.82, 0, 0.15)
      r:SetScript("OnLeave", function() GameTooltip:Hide() end)
      menu.rows[i] = r
    end
    r.text:SetText(d.text)
    local on = d.enabled ~= false
    r:SetEnabled(on)
    if on then r.text:SetTextColor(W.LIGHT[1], W.LIGHT[2], W.LIGHT[3]) else r.text:SetTextColor(0.45, 0.45, 0.45) end
    r:SetScript("OnClick", function()
      menu:Hide()
      W.Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
      if d.onClick then d.onClick() end
    end)
    r:SetScript("OnEnter", function(self)
      if not d.tip then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(d.tip, 1, 1, 1, 1, true)
      GameTooltip:Show()
    end)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", menu, "TOPLEFT", 6, -y)
    r:SetPoint("RIGHT", menu, "RIGHT", -6, 0)
    r:Show()
    w = math.max(w, (r.text:GetStringWidth() or 100) + 34)
    y = y + 20
  end
  menu:SetSize(w, y + 8)
  menu.anchor = anchor
  menu:ClearAllPoints()
  menu:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2)
  menu:Show()
  return menu
end
