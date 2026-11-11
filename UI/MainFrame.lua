local ADDON, TJ = ...
local W = TJ.W
local UI = {}
TJ.UI = UI
local format, floor, max, min = string.format, math.floor, math.max, math.min

-------------------------------------------------------------------------------
--  Окно EasyCraft в стиле MacroCoach: рамка окна игры, пергамент,
--  справа вкладки (главная и изученные профессии), сверху вкладки разделов,
--  на пергаменте - тёмные карточки.
-------------------------------------------------------------------------------
local WIDTH, HEIGHT = 680, 670 -- как окно MacroCoach
local PAGE_W = WIDTH - 16
local ATTIC = 64
local CHILD_W = PAGE_W - 30
local CARD_W = CHILD_W - 20
local PAD = W.S.pad
local GAP = W.S.gap -- между карточками
UI.CARD_W, UI.PAD = CARD_W, PAD
-- Значок в начале блока (шаг, профессия, шапка карточки): одинаковые
-- отступы во всех блоках. ICON_X, ICON_Y - от края блока до рамки значка
-- (у кольца ещё ~7 прозрачных пикселей), ICON_GAP - от значка до текста.
local ICON_X, ICON_Y, ICON_GAP = 6, 6, 3
UI.ICON_X, UI.ICON_Y, UI.ICON_GAP = ICON_X, ICON_Y, ICON_GAP
-- Видимая высота страницы (пергамент без полей прокрутки): главная должна
-- влезать в неё целиком.
UI.VIEW_H = HEIGHT - ATTIC - 4 - 6 - 12

UI.view = "home"
UI.tab = {}
UI.focus = {} -- профессия -> какой шаг показать при открытии (номер или "cur")

local HOME_ICON = "Interface\\Icons\\INV_Misc_Book_11"

-------------------------------------------------------------------------------
--  Карточка: свой набор виджетов, раскладка сверху вниз (card.y)
-------------------------------------------------------------------------------
local CARD = { bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } }
local STYLE = {
  normal = { 0.05, 0.045, 0.04, 0.9, 0.6, 0.48, 0.25 },
  -- текущий шаг: яркая золотая рамка и золотой ореол вокруг (Begin)
  current = { 0.05, 0.045, 0.035, 0.95, 1, 0.84, 0.1 },
  done = { 0.035, 0.065, 0.035, 0.9, 0.26, 0.62, 0.26 },
  -- следующие шаги (до них ещё не дошли): рамка приглушённая
  future = { 0.045, 0.04, 0.035, 0.85, 0.34, 0.28, 0.17 },
  flat = { 0, 0, 0, 0, 0, 0, 0, 0 }, -- прямо на пергаменте, без рамки
}
UI.STYLE = STYLE
-- Тёмные чернила для текста на пергаменте (как в книге заклинаний).
local INK = {
  huge = { 1, 0.82, 0 },
  title = { 1, 0.82, 0 }, head = { 1, 0.82, 0 },
  body = { 0.9, 0.87, 0.8 }, small = { 0.62, 0.62, 0.62 },
}
local INK_HEAD_TEXT = { 0.9, 0.87, 0.8 }

local Card = {}
local function ceilDiv(a, b) return floor((a + b - 1) / b) end

function Card:Take(kind, make)
  local pool = self.pools[kind]
  if not pool then pool = { list = {}, used = 0 }; self.pools[kind] = pool end
  pool.used = pool.used + 1
  local w = pool.list[pool.used]
  if not w then w = make(); pool.list[pool.used] = w end
  w:ClearAllPoints()
  w:Show()
  return w
end

function Card:Begin(style)
  for _, pool in pairs(self.pools) do
    for i = 1, pool.used do pool.list[i]:Hide() end
    pool.used = 0
  end
  local s = STYLE[style] or STYLE.normal
  self:SetBackdropColor(s[1], s[2], s[3], s[4])
  self:SetBackdropBorderColor(s[5], s[6], s[7], s[8] or 1)

  self.ink = style == "flat"
  self.indent = nil -- отступ слева для текста, строк и картинок (тело шага)
  self.y = self.ink and 4 or PAD
  self:SetScript("OnMouseUp", nil)
end

function Card:Space(n) self.y = self.y + (n or 8) end

-- Текст на всю ширину (или от x шириной w). kind: title, head, body, small.
function Card:Text(text, kind, opts)
  if not text or text == "" then return end
  opts = opts or {}
  kind = kind or "body"
  local fs = self:Take("text:" .. kind, function() return W.Text(self, kind) end)
  local spec = W.FONTS[kind]
  local c = opts.color or (self.ink and INK[kind]) or spec[3]
  fs:SetTextColor(c[1], c[2], c[3], 1)
  fs:SetJustifyH(opts.justify or "LEFT")
  local x = opts.x or self.indent or (self.ink and 4 or PAD)
  fs:SetWidth(opts.w or (CARD_W - x - PAD))
  fs:SetWordWrap(not opts.nowrap) -- в строке профессии на главной - одна строка
  fs:SetText(text)
  fs:SetPoint("TOPLEFT", self, "TOPLEFT", x, -(opts.y or self.y))
  if not opts.y then self.y = self.y + fs:GetStringHeight() + (opts.gap or 8) end
  return fs
end

-- Текст в правом верхнем углу строки (не сдвигает раскладку). outline -
-- с тёмной обводкой букв (на пергаменте зелёный и жёлтый иначе плохо видно).
function Card:Corner(text, kind, y, color, outline)
  local fs = self:Take("corner:" .. (kind or "small"), function() return W.Text(self, kind or "small", false) end)
  local spec = W.FONTS[kind or "small"]
  -- шрифт заново: строка из запаса могла остаться с обводкой
  fs:SetFontObject(_G[spec[1]] or _G[spec[2]] or GameFontNormal)
  if outline then
    local file, size = fs:GetFont()
    if file then fs:SetFont(file, size, "OUTLINE") end
  end
  local c = color or (self.ink and INK[kind or "small"]) or spec[3]
  fs:SetTextColor(c[1], c[2], c[3], 1)
  fs:SetJustifyH("RIGHT")
  fs:SetWidth(0)
  fs:SetText(text or "")
  fs:SetPoint("TOPRIGHT", self, "TOPRIGHT", -PAD, -(y or self.y))
  return fs
end

function Card:Icon(size, x, y)
  local b = self:Take("icon" .. size, function() return W.ItemIcon(self, size) end)
  b:SetPoint("TOPLEFT", self, "TOPLEFT", x, -y)
  b.onClick, b.tip, b.gold = nil, nil, nil
  return b
end

-- Невидимая зона наведения на весь блок (значок и текст): подсказка
-- предмета у курсора, Shift-клик - ссылка в чат. Без подсветки.
function Card:Hover(itemID, y0, y1, tip)
  local z = self:Take("hover", function()
    local b = CreateFrame("Button", nil, self)
    b:SetScript("OnEnter", function(s)
      if not (s.itemID or s.tip) then return end
      GameTooltip:SetOwner(s, "ANCHOR_CURSOR")
      if s.itemID then
        if GameTooltip.SetItemByID then GameTooltip:SetItemByID(s.itemID) else GameTooltip:SetHyperlink("item:" .. s.itemID) end
        if s.tip then GameTooltip:AddLine(s.tip, 0.8, 0.8, 0.8, true) end
      else
        GameTooltip:SetText(s.tip, 1, 1, 1, 1, true)
      end
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(s)
      if s.itemID and IsModifiedClick and IsModifiedClick("CHATLINK") then
        local _, link = ((C_Item and C_Item.GetItemInfo) or GetItemInfo)(s.itemID)
        W.InsertLink(link)
      end
    end)
    return b
  end)
  z:SetFrameLevel(self:GetFrameLevel() + 5)
  z:SetPoint("TOPLEFT", self, "TOPLEFT", PAD - 4, -(y0 - 4))
  z:SetPoint("BOTTOMRIGHT", self, "TOPRIGHT", -PAD + 4, -(y1 + 2))
  z.itemID, z.tip = itemID, tip
  return z
end

function Card:Ring(size, x, y)
  local f = self:Take("ring" .. size, function() return W.RingIcon(self, size) end)
  f:SetPoint("TOPLEFT", self, "TOPLEFT", x, -y)
  return f
end

-- Заголовок карточки: значок слева, название и строки под ним.
-- icon = { item = id } | { tex = path, spell = id } | { ring = path }
function Card:Head(icon, title, lines, size)
  size = size or 40
  -- шапка в начале карточки: значок с теми же отступами, что у шагов
  if icon and not self.ink and self.y == PAD then self.y = ICON_Y end
  local y0 = self.y
  local left = self.ink and 4 or (icon and ICON_X or PAD)
  local x = left
  if icon then
    -- внешний край кольца - ровно по краю текста
    local pad = icon.ring and W.RingPad(size) or W.IconPad(size)
    if icon.ring then
      self:Ring(size, left + pad, y0 + pad):SetIcon(icon.ring)
    else
      local b = self:Icon(size, left + pad, y0 + pad)
      if icon.item then b:SetItem(icon.item) else b:SetPlain(icon.tex, icon.spell) end
      b.tip = icon.tip
    end
    x = left + size + pad * 2 + ICON_GAP
    size = size + pad * 2
  end
  if not icon then size = 0 end
  local w = CARD_W - x - PAD - (self.headRight or 0)
  local placed = { { self:Text(title, "title", { x = x, w = w, gap = 4 }), self.y } }
  local first = y0
  for _, l in ipairs(lines or {}) do
    if l[1] and l[1] ~= "" then
      local yy = self.y
      placed[#placed + 1] = { self:Text(l[1], l[2] or "small", { x = x, w = w, gap = 4, color = l[3] }), yy }
    end
  end
  -- Текст ниже значка по высоте - по центру значка, а не прижат к верху.
  local textH = self.y - 4 - first
  if icon and textH < size then
    local off = floor((size - textH) / 2)
    local yy = first
    for _, e in ipairs(placed) do
      local fs = e[1]
      if fs then
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", self, "TOPLEFT", x, -(yy + off))
        yy = yy + fs:GetStringHeight() + 4
      end
    end
  end
  self.y = max(self.y, y0 + size + 4) + 10
  self.headRight = nil
end

-- Строка-кнопка, как строки подсказки у окна профессии: тёмный блок в
-- бурой рамке, слева квадратный значок (в углу - звезда «рекомендуем»),
-- название и подпись, справа - текст (цена) и значки (что там). Лучшая
-- (hot) - светлее и в золотой рамке. Нажимается целиком.
local CELL_BG = { 0.11, 0.09, 0.06, 0.95, 0.6, 0.48, 0.25, 0.85 }
local CELL_HOT = { 0.22, 0.16, 0.05, 0.95, 1, 0.82, 0, 1 }
local function MakeCell(parent, size)
  local b = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  if b.SetBackdrop then
    b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      edgeSize = 10, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
  end
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetPoint("TOPLEFT", 2, -2)
  hl:SetPoint("BOTTOMRIGHT", -2, 2)
  hl:SetColorTexture(1, 0.82, 0, 0.1)
  local is = size - 2
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(is, is)
  b.icon:SetPoint("LEFT", 7, 0)
  b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b.star = b:CreateTexture(nil, "OVERLAY", nil, 2)
  b.star:SetSize(16, 16)
  b.star:SetPoint("CENTER", b.icon, "TOPLEFT", 1, -1)
  W.SetTex(b.star, { "Interface\\COMMON\\ReputationStar" }, 1, 0.82, 0, 1)
  b.star:SetTexCoord(0, 0.5, 0, 0.5)
  b.nodes = {}
  for k = 1, 3 do
    local t = b:CreateTexture(nil, "ARTWORK")
    t:SetSize(is, is)
    t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if k == 1 then t:SetPoint("RIGHT", -8, 0) else t:SetPoint("RIGHT", b.nodes[k - 1], "LEFT", -3, 0) end
    b.nodes[k] = t
  end
  b.right = W.Text(b, "small", false)
  b.right:SetJustifyH("RIGHT")
  b.text = W.Text(b, "body", false)
  b.sub = W.Text(b, "small", false)
  b:SetScript("OnEnter", function(s)
    if not s.tip then return end
    GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
    W.FillTip(s.tip)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  function b:Set(it, w)
    self.icon:SetTexture(it.id and TJ:ItemIcon(it.id) or it.tex or TJ.Icon(nil))
    self.star:SetShown(it.star and true or false)
    local st = it.hot and CELL_HOT or CELL_BG
    self:SetBackdropColor(st[1], st[2], st[3], st[4])
    self:SetBackdropBorderColor(st[5], st[6], st[7], st[8])
    -- справа значки (что там) и текст (цена)
    local list = it.icons or {}
    local nI = min(#list, 3)
    for k = 1, 3 do
      self.nodes[k]:SetShown(k <= nI)
      if k <= nI then self.nodes[k]:SetTexture(list[k]) end
    end
    self.right:ClearAllPoints()
    if nI > 0 then self.right:SetPoint("RIGHT", self.nodes[nI], "LEFT", -6, -1) else self.right:SetPoint("RIGHT", -8, -1) end
    self.right:SetText(it.right or "")
    local rightEdge = (it.right and it.right ~= "") and self.right or (nI > 0 and self.nodes[nI]) or nil
    self.text:SetText(it.text or "")
    self.sub:SetText(it.sub or "")
    self.text:ClearAllPoints()
    self.sub:ClearAllPoints()
    if it.sub and it.sub ~= "" then
      -- две строки - блоком по центру значка (и ячейки)
      local hT, hS = self.text:GetStringHeight() or 14, self.sub:GetStringHeight() or 12
      local off = floor((hT + 2 + hS) / 2 + 0.5)
      self.text:SetPoint("TOPLEFT", self, "LEFT", 7 + self.icon:GetWidth() + 7, off - 1)
      self.sub:SetPoint("TOPLEFT", self.text, "BOTTOMLEFT", 0, -2)
      if rightEdge then self.sub:SetPoint("RIGHT", rightEdge, "LEFT", -6, 0) else self.sub:SetPoint("RIGHT", -8, 0) end
    else
      self.text:SetPoint("LEFT", self.icon, "RIGHT", 7, -1)
    end
    local dy = (it.sub and it.sub ~= "") and 0 or -1
    if rightEdge == self.right then dy = 0 end -- подпись справа уже опущена на 1
    if rightEdge then self.text:SetPoint("RIGHT", rightEdge, "LEFT", -6, dy) else self.text:SetPoint("RIGHT", -8, dy) end
    self.tip = it.tip
    local fn = it.onClick
    self:SetScript("OnClick", function() W.Sound("IG_MAINMENU_OPTION_CHECKBOX_ON"); fn() end)
    -- крестик у правого края (it.onDelete): убрать строку; текст справа - левее
    if it.onDelete then
      if not self.del then
        self.del = CreateFrame("Button", nil, self, "UIPanelCloseButton")
        self.del:SetSize(22, 22)
        self.del:SetPoint("RIGHT", -1, 0)
      end
      self.del:SetScript("OnClick", it.onDelete)
      self.del:Show()
      if nI == 0 then
        self.right:ClearAllPoints()
        self.right:SetPoint("RIGHT", -24, -1)
      end
    elseif self.del then
      self.del:Hide()
    end
  end
  return b
end

-- Список в колонках: { id=, tex=, text=, sub=, right=, icons=, star=, hot=,
-- onClick=, tip= }. С onClick строка - кнопка целиком (как строки подсказки
-- у окна профессии), без него - значок с подсказкой предмета.
function Card:Items(items, cols, size)
  if not items or #items == 0 then return end
  cols = cols or 2
  size = size or 30
  local gapX = 10
  local x0 = self.indent or PAD
  local colW = floor((CARD_W - x0 - PAD - gapX * (cols - 1)) / cols)
  local clickable, twoLines = false, false
  for _, it in ipairs(items) do
    if it.onClick then clickable = true end
    if it.sub and it.sub ~= "" then twoLines = true end
  end
  -- ячейка с двумя строками - не ниже 40, чтобы текст не налезал на рамку
  local cellH = max(size + 12, twoLines and 40 or 0)
  local rowH = clickable and (cellH + 6) or (max(size, twoLines and 32 or 0) + 14)
  for i, it in ipairs(items) do
    local col = (i - 1) % cols
    local row = floor((i - 1) / cols)
    local x, y = x0 + col * (colW + gapX), self.y + row * rowH
    if it.onClick then
      local cell = self:Take("cell" .. size, function() return MakeCell(self, size) end)
      cell:SetPoint("TOPLEFT", self, "TOPLEFT", x, -y)
      cell:SetSize(colW, cellH)
      cell:Set(it)
    else
      local row = self:Take("irow" .. size, function() return W.ItemRow(self, size) end)
      local pad = W.IconPad(size)
      row:SetPoint("TOPLEFT", self, "TOPLEFT", x + pad, -(y + 4))
      row:SetSize(colW - pad, size)
      row:Set(it)
    end
  end
  self.y = self.y + ceilDiv(#items, cols) * rowH + 4
end

-- Одна строка-кнопка (как в Items) в точке x, y шириной w; раскладку не
-- двигает. Возвращает её высоту.
function Card:CellAt(x, y, w, it, size)
  size = size or 22
  local h = max(size + 12, (it.sub and it.sub ~= "") and 40 or 0)
  local cell = self:Take("cell" .. size, function() return MakeCell(self, size) end)
  cell:SetPoint("TOPLEFT", self, "TOPLEFT", x, -y)
  cell:SetSize(w, h)
  cell:Set(it)
  return h
end

-- Строки текста блоком по центру высоты h (рядом со значком): x, y - левый
-- верх области, w - ширина. lines = { { text, kind, color, wrap } }.
-- Раскладку не двигает; возвращает высоту блока.
function Card:TextBlock(x, y, h, w, lines)
  local list, total = {}, 0
  for _, l in ipairs(lines) do
    if l[1] and l[1] ~= "" then
      local kind = l[2] or "body"
      local fs = self:Take("text:" .. kind, function() return W.Text(self, kind) end)
      local spec = W.FONTS[kind]
      local c = l[3] or (self.ink and INK[kind]) or spec[3]
      fs:SetTextColor(c[1], c[2], c[3], 1)
      fs:SetJustifyH("LEFT")
      fs:SetWidth(w)
      fs:SetWordWrap(l[4] and true or false)
      fs:SetText(l[1])
      local lh = fs:GetStringHeight() or 14
      list[#list + 1] = { fs, lh }
      total = total + lh + (#list > 1 and 3 or 0)
    end
  end
  local yy = y + max(0, floor((h - total) / 2 + 0.5))
  for _, e in ipairs(list) do
    e[1]:SetPoint("TOPLEFT", self, "TOPLEFT", x, -yy)
    yy = yy + e[2] + 3
  end
  return total
end

-- Картинка «было -> стало», как в «Зачем макросы» MacroCoach: значки
-- «было» серые (последний с крестиком), стрелка, значок «стало» с
-- галочкой; под ними подписи. В точке x, y; раскладку не двигает.
-- Возвращает ширину и высоту.
local ART_B, ART_A = 30, 40
function Card:Art(x, y, before, after, tagBefore, tagAfter)
  local n = #before
  local right = x
  local function slot(size)
    local f = self:Take("artslot" .. size, function() return W.Slot(self, size) end)
    return f
  end
  local first
  for i, tex in ipairs(before) do
    local f = slot(ART_B)
    f:SetPoint("TOPLEFT", self, "TOPLEFT", right + (i > 1 and 8 or 0), -(y + (ART_A - ART_B) / 2))
    f:Set(tex, nil, i == n and "no" or nil, true, false)
    right = right + (i > 1 and 8 or 0) + ART_B
    first = first or f
  end
  local arrow = self:Take("artarrow", function()
    local t = self:CreateTexture(nil, "ARTWORK")
    t:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
    t:SetSize(28, 28)
    return t
  end)
  arrow:SetPoint("LEFT", self, "TOPLEFT", right + 4, -(y + ART_A / 2))
  right = right + 4 + 28 + 4
  local a = slot(ART_A)
  a:SetPoint("TOPLEFT", self, "TOPLEFT", right, -y)
  a:Set(after, nil, "ok", false, true)
  local ax = right
  right = right + ART_A
  local function tag(text, col, anchor, cx)
    local fs = self:Take("arttag", function() return W.Text(self, "small", false) end)
    fs:SetTextColor(col[1], col[2], col[3], 1)
    fs:SetJustifyH("CENTER")
    fs:SetWidth(0)
    fs:SetText(text or "")
    fs:SetPoint("TOP", self, "TOPLEFT", cx, -(y + ART_A + 8))
    return fs
  end
  if tagBefore then tag(tagBefore, { 1, 0.45, 0.45 }, first, x + (right - x - ART_A - 36) / 2) end
  if tagAfter then tag(tagAfter, { 0.4, 1, 0.4 }, a, ax + ART_A / 2) end
  return right - x, ART_A + 8 + 14
end

-- Инфографика «как это работает»: шаги в ряд - крупный значок с номером,
-- стрелка к следующему, под значком название и пара слов. Наведение -
-- подробно. list = { { tex =, title =, text =, tip = } }.
local STEP_SLOT, STEP_ARROW = 40, 22
function Card:Steps(list)
  local n = #list
  if n == 0 then return end
  local x0 = self.indent or PAD
  local inner = CARD_W - x0 - PAD
  local colW = floor((inner - STEP_ARROW * (n - 1)) / n)
  local y0 = self.y
  local maxH = 0
  for i, d in ipairs(list) do
    local b = self:Take("step", function()
      local f = CreateFrame("Button", nil, self)
      f.slot = W.Slot(f, STEP_SLOT)
      f.slot:SetPoint("TOP", 0, -2)
      -- номер шага кружком в углу значка: свой кадр поверх ячейки (иначе
      -- рамка ячейки закрывает его)
      f.numIcon = W.RingIcon(f, 16)
      f.numIcon.icon:SetTexture("Interface\\Buttons\\WHITE8X8")
      f.numIcon.icon:SetVertexColor(0.09, 0.07, 0.04, 1)
      f.numIcon:SetPoint("CENTER", f.slot, "TOPLEFT", 2, -2)
      f.numIcon:SetFrameLevel(f.slot:GetFrameLevel() + 3)
      f.num = f.numIcon:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      f.num:SetPoint("CENTER", 0, 0)
      f.title = W.Text(f, "head", false)
      f.title:SetJustifyH("CENTER")
      f.title:SetPoint("TOP", f.slot, "BOTTOM", 0, -8)
      f.text = W.Text(f, "small", true)
      f.text:SetJustifyH("CENTER")
      f.text:SetPoint("TOP", f.title, "BOTTOM", 0, -3)
      local hl = f:CreateTexture(nil, "HIGHLIGHT")
      hl:SetAllPoints()
      hl:SetColorTexture(1, 0.82, 0, 0.06)
      f:SetScript("OnEnter", function(s)
        if not s.tip then return end
        GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
        W.FillTip(s.tip)
        GameTooltip:Show()
      end)
      f:SetScript("OnLeave", function() GameTooltip:Hide() end)
      return f
    end)
    local x = x0 + (i - 1) * (colW + STEP_ARROW)
    b:SetPoint("TOPLEFT", self, "TOPLEFT", x, -y0)
    b:SetWidth(colW)
    b.slot:Set(d.tex, nil, d.mark, false, d.glow)
    b.num:SetText(tostring(i))
    b.title:SetWidth(colW)
    b.title:SetText(d.title or "")
    b.text:SetWidth(colW - 4)
    b.text:SetText(d.text or "")
    b.tip = d.tip or (d.title and { title = d.title, lines = { d.text } }) or nil
    local h = 2 + STEP_SLOT + 8 + (b.title:GetStringHeight() or 16) + 3 + (b.text:GetStringHeight() or 14) + 4
    maxH = max(maxH, h)
    if i < n then
      local a = self:Take("steparrow", function()
        local t = self:CreateTexture(nil, "ARTWORK")
        t:SetTexture("Interface\Buttons\UI-SpellbookIcon-NextPage-Up")
        t:SetSize(STEP_ARROW + 4, STEP_ARROW + 4)
        return t
      end)
      a:SetPoint("CENTER", self, "TOPLEFT", x + colW + STEP_ARROW / 2, -(y0 + 2 + STEP_SLOT / 2))
    end
  end
  for k = 1, self.pools.step.used do self.pools.step.list[k]:SetHeight(maxH) end
  self.y = y0 + maxH + 8
end

-- Табличка на верхнем краю карточки (как навык над плиткой): «Текущий
-- шаг», «Отстаёшь на 11 уровней». x - от левого края; opts.center - по
-- середине края; opts.right - от правого края; opts.y - не на краю, а
-- внутри карточки (центр таблички на этой высоте); opts.edge - цвет рамки
-- (по умолчанию золотой); opts.tip и opts.onClick - подсказка и щелчок.
function Card:EdgeBadge(x, text, opts)
  opts = opts or {}
  local b = self:Take("edgebadge", function()
    local f = CreateFrame("Button", nil, self, BackdropTemplateMixin and "BackdropTemplate" or nil)
    if f.SetBackdrop then
      f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
      f:SetBackdropColor(0.07, 0.05, 0.03, 1)
    end
    f:SetHeight(22)
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.text:SetPoint("CENTER", 0, -1)
    f:SetScript("OnEnter", function(s)
      if not s.tip then return end
      GameTooltip:SetOwner(s, "ANCHOR_BOTTOM")
      W.FillTip(s.tip)
      GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return f
  end)
  b:SetFrameLevel(self:GetFrameLevel() + 7)
  local e = opts.edge or { 1, 0.82, 0 }
  if b.SetBackdropBorderColor then b:SetBackdropBorderColor(e[1], e[2], e[3], 1) end
  b.text:SetTextColor(1, 0.82, 0)
  -- big - крупнее (текущий шаг)
  b.text:SetFontObject(opts.big and (_G.SystemFont_Med3 or GameFontNormal) or GameFontNormalSmall)
  b.text:SetTextColor(1, 0.82, 0)
  b.text:SetText(text or "")
  b:SetHeight(opts.big and 28 or 22)
  b:SetWidth((b.text:GetStringWidth() or 70) + (opts.big and 30 or 22))
  local y = -(opts.y or 0)
  if opts.center then b:SetPoint("CENTER", self, "TOP", 0, y)
  elseif opts.right then b:SetPoint("RIGHT", self, "TOPRIGHT", -x, y)
  else b:SetPoint("LEFT", self, "TOPLEFT", x, y) end
  b.tip = opts.tip
  local fn = opts.onClick
  b:SetScript("OnClick", fn and function() W.Sound("IG_MAINMENU_OPTION_CHECKBOX_ON"); fn() end or nil)
  b:EnableMouse(opts.tip ~= nil or fn ~= nil)
  return b
end

-- Номер шага значком: тёмный кружок в кольце, внутри число. state -
-- "current" (золотое число), "done" (зелёное), иначе светлое.
function Card:NumIcon(x, y, size, n, state)
  local f = self:Take("num" .. size, function()
    local r = W.RingIcon(self, size)
    r.icon:SetTexture("Interface\\Buttons\\WHITE8X8")
    r.icon:SetVertexColor(0.09, 0.07, 0.04, 1)
    r.num = r:CreateFontString(nil, "OVERLAY", size >= 26 and "GameFontNormal" or "GameFontNormalSmall")
    r.num:SetPoint("CENTER", 0, 0)
    return r
  end)
  f:SetPoint("TOPLEFT", self, "TOPLEFT", x, -y)
  f.num:SetText(tostring(n))
  local c = state == "current" and { 1, 0.82, 0 } or (state == "done" and { 0.45, 0.9, 0.45 } or { 0.9, 0.9, 0.9 })
  f.num:SetTextColor(c[1], c[2], c[3])
  if f.ring and f.ring.SetDesaturated then f.ring:SetDesaturated(state ~= "current") end
  if f.ring then f.ring:SetAlpha(state == "current" and 1 or 0.7) end
  return f
end

-- Одна кнопка в точке x, y (от левого края) или от правого края (right).
function Card:Button(d, x, y, right)
  local b = self:Take("button", function()
    local btn = W.Button(self, "", 100, 24)
    btn:SetScript("OnEnter", function(s)
      if not s.tip then return end
      GameTooltip:SetOwner(s, "ANCHOR_CURSOR")
      GameTooltip:SetText(s.tip, 1, 1, 1, 1, true)
      GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return btn
  end)
  -- две высоты (обычная и главная - d.big); ширина по тексту, если не задана
  b:SetText(d.text)
  local bfs = b.GetFontString and b:GetFontString()
  local bw = d.w or max(W.S.btnMin, floor((bfs and bfs:GetStringWidth() or 90) + 30))
  b:SetSize(bw, d.big and W.S.btnBig or W.S.btn)
  b:SetEnabled(d.enabled ~= false)
  -- подсказка и у выключенной кнопки: почему она выключена
  if b.SetMotionScriptsWhileDisabled then b:SetMotionScriptsWhileDisabled(true) end
  b.tip = d.tip
  local fn = d.onClick
  b:SetScript("OnClick", function(s) W.Sound("IG_MAINMENU_OPTION_CHECKBOX_ON"); if fn then fn(s) end end)
  if right then b:SetPoint("TOPRIGHT", self, "TOPRIGHT", -x, -y)
  else b:SetPoint("TOPLEFT", self, "TOPLEFT", x, -y) end
  return b
end

-- Ряд кнопок: { text=, w=, onClick=, enabled=, tip= }. right - справа налево
-- (для второго набора в той же строке: stay - не переходить на новую строку).
function Card:Buttons(list, right, stay)
  if not list or #list == 0 then return end
  local x = right and PAD or (self.indent or PAD)
  local out = {}
  if right then
    for i = #list, 1, -1 do
      out[i] = self:Button(list[i], x, self.y, true)
      x = x + out[i]:GetWidth() + 6
    end
  else
    for i, d in ipairs(list) do
      out[i] = self:Button(d, x, self.y)
      x = x + out[i]:GetWidth() + 6
    end
  end
  if not stay then self.y = self.y + 34 end
  return out
end

-- Кнопки в правом верхнем углу (рядом с заголовком), раскладку не двигают.
function Card:CornerButtons(list, y)
  local rx = PAD
  local total = 0
  for i = #list, 1, -1 do
    local d = list[i]
    local b = self:Take("cbutton", function() return W.Button(self, "", 100, 22) end)
    b:SetSize(d.w or 120, 22)
    b:SetText(d.text)
    b:SetEnabled(d.enabled ~= false)
    local fn = d.onClick
    b:SetScript("OnClick", function(s) W.Sound("IG_MAINMENU_OPTION_CHECKBOX_ON"); if fn then fn(s) end end)
    b:SetPoint("TOPRIGHT", self, "TOPRIGHT", -rx, -(y or self.y))
    rx = rx + b:GetWidth() + 6
    total = total + b:GetWidth() + 6
  end
  return total
end

function Card:Check(label, checked, onClick, tip)
  local c = self:Take("check", function()
    local cb = W.Check(self, "")
    cb.label:SetFontObject(_G.SystemFont_Med1 or GameFontHighlightSmall)
    cb.label:SetTextColor(W.LIGHT[1], W.LIGHT[2], W.LIGHT[3])
    cb:SetScript("OnEnter", function(s)
      if not s.tip then return end
      GameTooltip:SetOwner(s, "ANCHOR_CURSOR")
      GameTooltip:SetText(s.tip, 1, 1, 1, 1, true)
      GameTooltip:Show()
    end)
    cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return cb
  end)
  c:SetPoint("TOPLEFT", self, "TOPLEFT", (self.ink and 0 or PAD - 4), -(self.y - 2))
  local col = self.ink and INK.body or W.LIGHT
  c.label:SetTextColor(col[1], col[2], col[3])
  c.label:SetText(label)
  c:SetChecked(checked and true or false)
  c.tip = tip
  c:SetScript("OnClick", function(s) onClick(s:GetChecked() and true or false) end)
  self.y = self.y + 30
  return c
end

-- Полоса шагов маршрута: квадратик на шаг - сделан (зелёный), текущий
-- (золотой), выбранный (белая рамка), впереди (тёмный). Наведение - название
-- шага, щелчок - показать его. steps = { { state =, sel =, cur =, tip =, onClick = } }
function Card:StepDots(steps)
  local n = #steps
  if n == 0 then return end
  local gap = 3
  local w = math.min(26, floor((CARD_W - PAD * 2 - gap * (n - 1)) / n))
  local hgt = 10
  for i, d in ipairs(steps) do
    local b = self:Take("dot", function()
      local btn = CreateFrame("Button", nil, self)
      btn.fill = btn:CreateTexture(nil, "ARTWORK")
      btn.fill:SetAllPoints()
      btn.edge = btn:CreateTexture(nil, "OVERLAY")
      btn.edge:SetPoint("TOPLEFT", -2, 2)
      btn.edge:SetPoint("BOTTOMRIGHT", 2, -2)
      btn.edge:SetColorTexture(1, 1, 1, 0.9)
      btn.edge:SetDrawLayer("BACKGROUND")
      local hl = btn:CreateTexture(nil, "HIGHLIGHT")
      hl:SetAllPoints()
      hl:SetColorTexture(1, 1, 1, 0.35)
      btn:SetScript("OnEnter", function(s)
        if not s.tip then return end
        GameTooltip:SetOwner(s, "ANCHOR_TOP")
        GameTooltip:SetText(s.tip, 1, 1, 1, 1, true)
        GameTooltip:Show()
      end)
      btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
      return btn
    end)
    b:SetSize(w, hgt)
    b:SetPoint("TOPLEFT", self, "TOPLEFT", PAD + (i - 1) * (w + gap), -(self.y + 2))
    if d.state == "done" then b.fill:SetColorTexture(0.3, 0.75, 0.3, 1)
    elseif d.cur then b.fill:SetColorTexture(1, 0.82, 0, 1)
    else b.fill:SetColorTexture(0.32, 0.27, 0.2, 1) end
    b.edge:SetShown(d.sel and true or false)
    b.tip = d.tip
    b:SetScript("OnClick", d.onClick)
  end
  self.y = self.y + hgt + 12
end

-- Картинка «реагенты -> результат» (W.Flow) с края текста. lines -
-- короткие строки справа от картинки, по центру значков (как текст справа
-- от картинки на карточке MacroCoach).
function Card:Flow(inputs, output, size, x, lines)
  size = size or 36
  local f = self:Take("flow" .. size, function() return W.Flow(self, size) end)
  local left = x or self.indent or (self.ink and 4 or PAD)
  f:SetPoint("TOPLEFT", self, "TOPLEFT", left, -self.y)
  local w, h = f:Set(inputs, output)
  if lines and #lines > 0 then
    local tx = left + w + 16
    local tw = CARD_W - tx - PAD
    local fss, total = {}, 0
    for i, l in ipairs(lines) do
      local fs = self:Take("flowtext", function() return W.Text(self, "body") end)
      fs:SetTextColor(W.LIGHT[1], W.LIGHT[2], W.LIGHT[3], 1)
      fs:SetWidth(tw)
      fs:SetText(l)
      fss[i] = fs
      total = total + fs:GetStringHeight() + (i > 1 and 4 or 0)
    end
    local iconH = size + W.IconPad(size) * 2
    local yy = self.y + math.max(0, floor((iconH - total) / 2))
    for _, fs in ipairs(fss) do
      fs:SetPoint("TOPLEFT", self, "TOPLEFT", tx, -yy)
      yy = yy + fs:GetStringHeight() + 4
    end
    h = math.max(h, yy - self.y)
  end
  self.y = self.y + h + 6
  return f
end

-- «Использовать» предмет из сумок (W.UseButton) в точке x, y.
function Card:UseButton(itemID, x, y, w)
  local b = self:Take("use", function() return W.UseButton(self) end)
  b:SetSize(w or 120, 22)
  b:SetPoint("TOPLEFT", self, "TOPLEFT", x, -y)
  b:SetFrameLevel(self:GetFrameLevel() + 8) -- над зоной подсказки предмета
  b.itemID = itemID
  return b
end

function Card:Bar(value, maxValue, text)
  local bar = self:Take("bar", function() return W.Bar(self) end)
  local left = self.ink and 4 or PAD
  bar:SetPoint("TOPLEFT", self, "TOPLEFT", left + 3, -(self.y + 3))
  bar:SetWidth(CARD_W - left * 2 - 6)
  bar:SetMinMaxValues(0, max(1, maxValue or 1))
  bar:SetValue(min(value or 0, maxValue or 1))
  bar.text:SetText(text or "")
  self.y = self.y + 28
  return bar
end

-- Строка списка (шаг маршрута): значок, текст, справа - число или галочка.
-- state: "done", "current", "sel", nil
function Card:Row(r)
  local b = self:Take("row", function()
    local row = CreateFrame("Button", nil, self)
    row:SetHeight(32)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.hl = row:CreateTexture(nil, "HIGHLIGHT")
    row.hl:SetAllPoints()
    row.hl:SetColorTexture(1, 0.82, 0, 0.08)
    -- тонкая черта под строкой: список читается по строкам
    row.sep = row:CreateTexture(nil, "BORDER")
    row.sep:SetPoint("BOTTOMLEFT", 4, 0)
    row.sep:SetPoint("BOTTOMRIGHT", -4, 0)
    row.sep:SetHeight(1)
    row.sep:SetColorTexture(1, 1, 1, 0.06)
    row.icon = W.ItemIcon(row, 22)
    row.icon:SetPoint("LEFT", 6 + W.IconPad(22), 0)
    row.icon:EnableMouse(false)
    row.text = W.Text(row, "body", false)
    row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, -1)
    row.right = W.Text(row, "small", false)
    row.right:SetJustifyH("RIGHT")
    row.right:SetPoint("RIGHT", -8, -1)
    row.mark = row:CreateTexture(nil, "OVERLAY")
    row.mark:SetSize(16, 16)
    row.mark:SetPoint("RIGHT", -8, 0)
    -- Подсказка предмета при наведении (строки «Покупок»).
    row:SetScript("OnEnter", function(s)
      if not s.itemID then return end
      GameTooltip:SetOwner(s, "ANCHOR_CURSOR")
      if GameTooltip.SetItemByID then GameTooltip:SetItemByID(s.itemID) else GameTooltip:SetHyperlink("item:" .. s.itemID) end
      if s.tip then GameTooltip:AddLine(s.tip, 0.8, 0.8, 0.8, true) end
      GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
  end)
  b:SetPoint("TOPLEFT", self, "TOPLEFT", PAD - 6, -self.y)
  b:SetWidth(CARD_W - PAD * 2 + 12)
  if r.id then b.icon:SetItem(r.id) else b.icon:SetPlain(r.tex or TJ.Icon(nil)) end
  local c = r.color or W.LIGHT
  b.text:SetTextColor(c[1], c[2], c[3], 1)
  b.text:SetText(r.text or "")
  b.text:SetWidth(CARD_W - PAD * 2 - 22 - 8 - 100)
  b.right:SetText(r.right or "")
  b.right:SetShown(not r.done)
  if r.done then
    W.SetTex(b.mark, "Interface\\RaidFrame\\ReadyCheck-Ready", 0.2, 0.9, 0.2, 1)
    b.mark:Show()
  else
    b.mark:Hide()
  end
  if r.state == "current" then
    b.bg:SetColorTexture(1, 0.82, 0, 0.16)
  elseif r.state == "sel" then
    b.bg:SetColorTexture(1, 1, 1, 0.1)
  else
    b.bg:SetColorTexture(0, 0, 0, 0)
  end
  b.icon:SetAlpha(r.done and 0.6 or 1)
  b.itemID = r.hoverItem and r.id or nil
  b.tip = r.hoverItem and TJ.T("Shift+щелчок - ссылка в чат. На открытом аукционе щелчок ищет этот реагент.") or nil
  b:SetScript("OnClick", r.onClick)
  -- крестик у правого края (r.onDelete): убрать строку; текст справа - левее
  b.right:ClearAllPoints()
  b.right:SetPoint("RIGHT", r.onDelete and -28 or -8, -1)
  if r.onDelete then
    if not b.del then
      b.del = CreateFrame("Button", nil, b, "UIPanelCloseButton")
      b.del:SetSize(22, 22)
      b.del:SetPoint("RIGHT", -2, 0)
    end
    b.del:SetScript("OnClick", r.onDelete)
    b.del:Show()
  elseif b.del then
    b.del:Hide()
  end
  self.y = self.y + 33
  return b
end

-- Строка-заголовок раздела (ранг): галочка или «+/-», название, рядом
-- серым - диапазон (sub), справа - счёт.
function Card:Section(text, right, done, collapsed, onClick, sub)
  local b = self:Take("section", function()
    -- плашка, как заголовки разделов в окнах игры (навыки, репутация):
    -- тёмная, в тонкой рамке, название золотом слева, «+/-» справа
    local s = CreateFrame("Button", nil, self, BackdropTemplateMixin and "BackdropTemplate" or nil)
    s:SetHeight(26)
    W.Backdrop(s, "Interface\\Buttons\\WHITE8X8", nil, 10, 0.1, 0.075, 0.05, 0.95, 0.5, 0.4, 0.22, 0.9)
    s.hl = s:CreateTexture(nil, "HIGHLIGHT")
    s.hl:SetPoint("TOPLEFT", 2, -2)
    s.hl:SetPoint("BOTTOMRIGHT", -2, 2)
    s.hl:SetColorTexture(1, 0.82, 0, 0.08)
    s.arrow = s:CreateTexture(nil, "OVERLAY")
    s.arrow:SetSize(16, 16)
    s.arrow:SetPoint("RIGHT", -6, 0)
    s.text = W.Text(s, "head", false)
    s.text:SetPoint("LEFT", 10, 0)
    s.sub = W.Text(s, "small", false)
    s.sub:SetPoint("BOTTOMLEFT", s.text, "BOTTOMRIGHT", 8, 1)
    s.right = W.Text(s, "head", false)
    s.right:SetJustifyH("RIGHT")
    s.right:SetPoint("RIGHT", s.arrow, "LEFT", -8, 0)
    return s
  end)
  b.sub:SetText(sub or "")
  -- заголовок чуть выше обычного отступа: сверху и снизу одинаково
  self.y = self.y - 6
  b:SetPoint("TOPLEFT", self, "TOPLEFT", PAD, -self.y)
  b:SetWidth(CARD_W - PAD * 2)
  if done then
    W.SetTex(b.arrow, "Interface\\RaidFrame\\ReadyCheck-Ready", 0.2, 0.9, 0.2, 1)
  else
    W.SetTex(b.arrow, collapsed and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up", 1, 0.82, 0, 1)
  end
  local c = done and W.GREEN or W.GOLD
  b.text:SetTextColor(c[1], c[2], c[3], 1)
  b.right:SetTextColor(c[1], c[2], c[3], 1)
  b.text:SetText(text)
  b.right:SetText(right or "")
  b:SetScript("OnClick", onClick)
  self.y = self.y + 26 + (collapsed and 0 or 6)
  return b
end

-- Шаги плитками, как награды в «Старинных испытаниях», в виде карточек
-- аддона и подсказки у окна профессии: тёмная плитка в бурой рамке
-- (текущая - в золотой, пройденная - в зелёной), сверху табличка с
-- навыком, квадратная ячейка значка, как в MacroCoach (внизу - сколько
-- ещё создать, вверху справа у пройденной - галочка, у текущей - стрелка
-- в золотой рамке, как табличка «Текущий шаг»), под ней название и
-- строка «что нужно»: хватает ли реагентов, сколько докупить, с какого
-- навыка учить. Наведение - всё о шаге, щелчок - открыть шаг.
-- mode: full - страница профессии; mini и tiny - главная (только значок).
-- t = { tex, item, badge, count, text, foot, state, cur, sel, tip, onClick }.
local TILE_MODE = {
  full = { h = 116, icon = 36, iconY = 17, name = true },
  home = { h = 70, icon = 40, iconY = 16 }, -- главная: шаги профессии
  mini = { h = 58, icon = 32, iconY = 15 },
  tiny = { h = 46, icon = 26, iconY = 12 },
}
local TILE_COLS, TILE_GAP, TILE_TOP = 5, 8, 13
UI.TILE_MODE, UI.TILE_TOP = TILE_MODE, TILE_TOP
-- wide - широкая плитка текущего шага на главной: значок слева, рядом
-- название и строка «что нужно», справа табличка «Текущий шаг» (как на
-- карточке шага) и стрелка.
-- Тёмная табличка в золотой рамке, как «Текущий шаг» на карточке шага.
local function GoldPlate(parent, edgeSize)
  local f = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  if f.SetBackdrop then
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      edgeSize = edgeSize or 10, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    f:SetBackdropColor(0.07, 0.05, 0.03, 1)
    f:SetBackdropBorderColor(1, 0.82, 0, 1)
  end
  return f
end
local ARROW_TEX = { "Interface\\ChatFrame\\ChatFrameExpandArrow", "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up" }

local function MakeTile(parent, mode, wide)
  local m = TILE_MODE[mode] or TILE_MODE.full
  local b = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  if b.SetBackdrop then
    b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
  end
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetPoint("TOPLEFT", 3, -3)
  hl:SetPoint("BOTTOMRIGHT", -3, 3)
  hl:SetColorTexture(1, 0.82, 0, 0.1)
  -- табличка с навыком на верхнем крае: тёмная, в рамке цвета плитки,
  -- число целиком внутри (ромб был мал - цифры налезали на его края)
  b.badge = CreateFrame("Frame", nil, b, BackdropTemplateMixin and "BackdropTemplate" or nil)
  if b.badge.SetBackdrop then
    b.badge:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      edgeSize = 8, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    b.badge:SetBackdropColor(0.07, 0.05, 0.03, 1)
  end
  -- навык крупно, чтобы читался (в самой мелкой плитке - мельче)
  local big = mode ~= "tiny"
  b.badge:SetHeight(big and 20 or 16)
  b.badge:SetFrameLevel(b:GetFrameLevel() + 3)
  b.badgeText = b.badge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  if big then b.badgeText:SetFontObject(_G.GameFontNormalMed2 or _G.GameFontNormalMed1 or GameFontNormal) end
  b.badgeText:SetPoint("CENTER", 0, 0)
  b.slot = W.Slot(b, m.icon)
  if wide then
    -- значок слева по центру высоты, табличка навыка - над ним, справа три
    -- строки блоком по центру значка (ставит Set: высота строк известна там)
    local sx = 12
    b.slot:SetPoint("LEFT", sx, -2)
    b.badge:SetPoint("CENTER", b, "TOPLEFT", sx + m.icon / 2, 0)
    b.tx = sx + m.icon + 10
    -- справа табличка «Текущий шаг» со стрелкой внутри (плитку можно
    -- открыть): по центру значка, от правого края - как значок от левого
    b.plate = GoldPlate(b)
    b.plate:SetHeight(28)
    b.plate:SetPoint("RIGHT", b, "RIGHT", -sx, -2)
    b.plate:SetFrameLevel(b:GetFrameLevel() + 3)
    b.label = b.plate:CreateFontString(nil, "OVERLAY")
    b.label:SetFontObject(_G.SystemFont_Med3 or GameFontNormal)
    b.label:SetTextColor(1, 0.82, 0, 1)
    b.label:SetPoint("LEFT", 12, -1)
    b.arrow = b.plate:CreateTexture(nil, "OVERLAY")
    b.arrow:SetSize(14, 14)
    b.arrow:SetPoint("RIGHT", -8, 0)
    W.SetTex(b.arrow, ARROW_TEX, 1, 0.82, 0, 1)
    b.arrow:SetVertexColor(1, 0.82, 0, 1)
    b.wname = W.Text(b, "body", false)
    b.wname:SetTextColor(1, 1, 1, 1)
    b.wfoot = W.Text(b, "small", false)
  else
    b.badge:SetPoint("CENTER", b, "TOP", 0, 0)
    b.slot:SetPoint("TOP", 0, -m.iconY)
    -- текущий шаг: стрелка в золотой рамке в углу значка (у пройденного
    -- там галочка)
    local ms = max(14, floor(m.icon * 0.42 + 0.5))
    b.curMark = GoldPlate(b, 8)
    b.curMark:SetSize(ms, ms)
    b.curMark:SetPoint("CENTER", b.slot, "TOPRIGHT", -1, -1)
    b.curMark:SetFrameLevel(b.slot:GetFrameLevel() + 3)
    local a = b.curMark:CreateTexture(nil, "OVERLAY")
    a:SetSize(ms - 2, ms - 2)
    a:SetPoint("CENTER", 1, 0)
    W.SetTex(a, ARROW_TEX, 1, 0.82, 0, 1)
    a:SetVertexColor(1, 0.82, 0, 1)
    b.curMark:Hide()
  end
  if m.name then
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("TOP", b.slot, "BOTTOM", 0, -7)
    b.text:SetPoint("LEFT", 6, 0)
    b.text:SetPoint("RIGHT", -6, 0)
    b.text:SetJustifyH("CENTER")
    b.text:SetJustifyV("TOP")
    if b.text.SetMaxLines then b.text:SetMaxLines(2) end
    b.text:SetWordWrap(true)
    -- строка «что нужно» внизу плитки, на тёмной полосе
    b.footBg = b:CreateTexture(nil, "ARTWORK")
    b.footBg:SetPoint("BOTTOMLEFT", 4, 4)
    b.footBg:SetPoint("BOTTOMRIGHT", -4, 4)
    b.footBg:SetHeight(19)
    b.footBg:SetColorTexture(0, 0, 0, 0.35)
    b.foot = W.Text(b, "small", false)
    b.foot:SetFontObject(_G.SystemFont_Small or GameFontHighlightSmall)
    b.foot:SetJustifyH("CENTER")
    b.foot:SetPoint("BOTTOMLEFT", 5, 8)
    b.foot:SetPoint("BOTTOMRIGHT", -5, 8)
  end
  b:SetScript("OnEnter", function(s)
    if not s.tip then return end
    GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
    W.FillTip(s.tip)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:SetScript("OnClick", function(s)
    if s.item and IsModifiedClick and IsModifiedClick("CHATLINK") then
      local _, link = ((C_Item and C_Item.GetItemInfo) or GetItemInfo)(s.item)
      W.InsertLink(link)
      return
    end
    W.Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
    if s.onClick then s.onClick() end
  end)
  function b:Set(t)
    local done, cur = t.state == "done", t.cur
    self.item, self.tip, self.onClick = t.item, t.tip, t.onClick
    -- текущий шаг - рамкой плитки и значком (стрелка / табличка), без
    -- свечения поверх значка
    self.slot:Set(t.tex or (t.item and TJ:ItemIcon(t.item)) or TJ.Icon(nil), not done and t.count or nil,
      done and "ok" or nil, not (done or cur), false)
    if self.curMark then self.curMark:SetShown(cur and true or false) end
    -- цвета карточек аддона (STYLE): текущая - ярко, пройденная - зелёная,
    -- следующие - приглушённые
    local st = cur and STYLE.current or (done and STYLE.done or STYLE.future)
    self:SetBackdropColor(st[1], st[2], st[3], st[4])
    if t.sel then self:SetBackdropBorderColor(1, 0.95, 0.75, 1)
    else self:SetBackdropBorderColor(st[5], st[6], st[7], 1) end
    local edge = cur and { 1, 0.84, 0.1 } or (done and { 0.26, 0.62, 0.26 } or { 0.42, 0.34, 0.2 })
    if self.badge.SetBackdropBorderColor then self.badge:SetBackdropBorderColor(edge[1], edge[2], edge[3], 1) end
    local tc = cur and { 1, 1, 1 } or (done and { 0.55, 0.9, 0.55 } or { 0.88, 0.75, 0.42 })
    self.badgeText:SetTextColor(tc[1], tc[2], tc[3], 1)
    self.badge:SetShown(t.badge ~= nil)
    self.badgeText:SetText(t.badge or "")
    self.badge:SetWidth(max(30, (self.badgeText:GetStringWidth() or 18) + 14))
    if self.plate then
      self.label:SetText(t.label or "")
      self.plate:SetShown((t.label or "") ~= "")
      self.plate:SetWidth(12 + (self.label:GetStringWidth() or 90) + 8 + 14 + 8)
      self.wname:SetText(t.text or "")
      self.wfoot:SetText(t.foot or "")
      -- название и «что нужно» блоком по центру значка
      local list = { self.wname }
      if (t.foot or "") ~= "" then list[2] = self.wfoot end
      self.wfoot:SetShown(list[2] ~= nil)
      local total = 0
      for i, fs in ipairs(list) do total = total + (fs:GetStringHeight() or 13) + (i > 1 and 3 or 0) end
      local y = -floor((self:GetHeight() - total) / 2 + 0.5) - 2
      -- справа место под табличку
      local right = 12 + (self.plate:IsShown() and (self.plate:GetWidth() + 12) or 0)
      for _, fs in ipairs(list) do
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", self, "TOPLEFT", self.tx, y)
        fs:SetPoint("RIGHT", self, "RIGHT", -right, 0)
        y = y - (fs:GetStringHeight() or 13) - 3
      end
    end
    if self.text then
      local c = cur and W.GOLD or (done and { 0.8, 0.85, 0.8 } or { 0.78, 0.72, 0.6 })
      self.text:SetTextColor(c[1], c[2], c[3], 1)
      self.text:SetText(t.text or "")
      self.foot:SetText(t.foot or "")
      self.foot:SetShown((t.foot or "") ~= "")
      self.footBg:SetShown((t.foot or "") ~= "")
    end
  end
  return b
end

-- Плитки рядами по cols (на странице профессии - по 5 во всю ширину).
-- opts = { mode, cols, x, y, w, gap }: с y - в этой точке, раскладку не
-- двигает. Возвращает высоту рядов.
function Card:Tiles(tiles, opts)
  if not tiles or #tiles == 0 then return 0 end
  opts = opts or {}
  local mode = opts.mode or "full"
  local m = TILE_MODE[mode] or TILE_MODE.full
  local cols = opts.cols or TILE_COLS
  local gap = opts.gap or TILE_GAP
  local x0 = opts.x or PAD
  local w = opts.w or floor((CARD_W - x0 - PAD - gap * (cols - 1)) / cols)
  local y0 = opts.y or self.y
  -- плитка шириной в span ячеек (текущий шаг на главной) не влезла в ряд -
  -- переходит на следующий
  local col, row = 0, 0
  for _, t in ipairs(tiles) do
    local span = min(t.span or 1, cols)
    if col > 0 and col + span > cols then col, row = 0, row + 1 end
    local b
    if span > 1 then b = self:Take("tilew:" .. mode, function() return MakeTile(self, mode, true) end)
    else b = self:Take("tile:" .. mode, function() return MakeTile(self, mode) end) end
    b:SetSize(w * span + gap * (span - 1), m.h)
    b:SetPoint("TOPLEFT", self, "TOPLEFT", x0 + col * (w + gap), -(y0 + TILE_TOP + row * (m.h + TILE_TOP + gap)))
    b:Set(t)
    col = col + span
    if col >= cols then col, row = 0, row + 1 end
  end
  local rows = col > 0 and row + 1 or row
  local h = rows * (m.h + TILE_TOP + gap) - gap
  if not opts.y then self.y = self.y + h + 10 end
  return h
end

-- Строка значков с числами («чипы»): что осталось до цели. Наведение -
-- подробно. chips = { { tex =, text =, tip =, onClick = } }.
function Card:Stats(chips)
  if not chips or #chips == 0 then return end
  local left = self.indent or PAD
  local x, y = left, self.y
  for _, d in ipairs(chips) do
    local b = self:Take("chip", function()
      local c = CreateFrame("Button", nil, self)
      c:SetHeight(22)
      c.slot = W.Slot(c, 18)
      c.slot:SetPoint("LEFT", 1, 0)
      c.text = W.Text(c, "body", false)
      c.text:SetPoint("LEFT", c.slot, "RIGHT", 7, 0)
      local hl = c:CreateTexture(nil, "HIGHLIGHT")
      hl:SetPoint("TOPLEFT", -3, 2)
      hl:SetPoint("BOTTOMRIGHT", 3, -2)
      hl:SetColorTexture(1, 0.82, 0, 0.1)
      c:SetScript("OnEnter", function(s)
        if not s.tip then return end
        GameTooltip:SetOwner(s, "ANCHOR_TOP")
        W.FillTip(s.tip)
        GameTooltip:Show()
      end)
      c:SetScript("OnLeave", function() GameTooltip:Hide() end)
      return c
    end)
    b.slot:Set(d.tex, nil, d.mark, d.grey)
    b.text:SetText(d.text or "")
    local w = 1 + 18 + 7 + (b.text:GetStringWidth() or 40) + 2
    if x > left and x + w > CARD_W - PAD then x, y = left, y + 28 end
    b:SetWidth(w)
    b:SetPoint("TOPLEFT", self, "TOPLEFT", x, -y)
    b.tip = d.tip
    local fn = d.onClick
    b:SetScript("OnClick", fn and function() W.Sound("IG_MAINMENU_OPTION_CHECKBOX_ON"); fn() end or nil)
    x = x + w + 22
  end
  self.y = y + 22 + 10
end

-- Значок-ячейка в точке x, y с подсказкой (и щелчком): пометки в строке
-- профессии, шаги знакомства. glow - золотое свечение (важно сейчас).
function Card:IconAt(x, y, size, tex, tip, onClick, glow)
  local b = self:Take("iconat" .. size, function()
    local f = CreateFrame("Button", nil, self)
    f:SetSize(size, size)
    f.slot = W.Slot(f, size)
    f.slot:SetPoint("CENTER")
    -- подсветка поверх значка (ячейка лежит над кнопкой и закрыла бы её)
    local hl = f.slot:CreateTexture(nil, "OVERLAY", nil, 3)
    hl:SetAllPoints()
    hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    hl:SetBlendMode("ADD")
    hl:Hide()
    f:SetScript("OnEnter", function(s)
      hl:Show()
      if not s.tip then return end
      GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
      W.FillTip(s.tip)
      GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() hl:Hide(); GameTooltip:Hide() end)
    return f
  end)
  b:SetPoint("TOPLEFT", self, "TOPLEFT", x, -y)
  b.slot:Set(tex, nil, nil, false, glow)
  b.tip = tip
  b:SetScript("OnClick", onClick and function() W.Sound("IG_MAINMENU_OPTION_CHECKBOX_ON"); onClick() end or nil)
  b:SetFrameLevel(self:GetFrameLevel() + 6) -- над областью щелчка строки
  return b
end

-- Нажимаемая область (x, y, w, h) с золотой подсветкой: строка профессии
-- на главной открывает её страницу.
function Card:Zone(x, y, w, h, onClick, tip)
  local z = self:Take("zone", function()
    local b = CreateFrame("Button", nil, self)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.82, 0, 0.07)
    b:SetScript("OnEnter", function(s)
      if not s.tip then return end
      GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
      W.FillTip(s.tip)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
  end)
  z:SetPoint("TOPLEFT", self, "TOPLEFT", x, -y)
  z:SetSize(w, h)
  z.tip = tip
  z:SetScript("OnClick", function() W.Sound("IG_ABILITY_PAGE_TURN"); if onClick then onClick() end end)
  return z
end

-- Пометка словами в точке x, y (не двигает раскладку): «Отстаёшь на 15
-- уровней», «Можно учить ранг». Наведение - подробно, щелчок - onClick.
-- Возвращает кнопку и её ширину.
function Card:Note(x, y, text, tip, onClick, right)
  local b = self:Take("note", function()
    local n = CreateFrame("Button", nil, self)
    n.text = W.Text(n, "small", false)
    n.text:SetPoint("LEFT", 0, 0)
    -- без подсветки: подсказка при наведении и так скажет, что тут
    n:SetScript("OnEnter", function(s)
      if not s.tip then return end
      GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
      W.FillTip(s.tip)
      GameTooltip:Show()
    end)
    n:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return n
  end)
  b.text:SetText(text or "")
  local w = (b.text:GetStringWidth() or 60) + 2
  b:SetSize(w, 16)
  if right then b:SetPoint("TOPRIGHT", self, "TOPRIGHT", -x, -y)
  else b:SetPoint("TOPLEFT", self, "TOPLEFT", x, -y) end
  b.tip = tip
  b:SetScript("OnClick", onClick and function() W.Sound("IG_MAINMENU_OPTION_CHECKBOX_ON"); onClick() end or nil)
  b:SetFrameLevel(self:GetFrameLevel() + 6) -- над областью щелчка шапки
  return b, w
end

-- Полоса навыка в точке x, y шириной w (на главной - в строке профессии):
-- слева ранг, справа «87/150».
function Card:BarAt(x, y, w, value, maxValue, left, right)
  local bar = self:Take("sbar", function()
    local b = W.Bar(self)
    b:SetHeight(16)
    return b
  end)
  bar:SetPoint("TOPLEFT", self, "TOPLEFT", x + 3, -(y + 3))
  bar:SetWidth(w - 6)
  bar:SetMinMaxValues(0, max(1, maxValue or 1))
  bar:SetValue(min(value or 0, maxValue or 1))
  -- одной строкой по центру полосы: «Подмастерье 124/150»
  local label = (left and left ~= "" and right and right ~= "") and (left .. "  " .. right) or (left or right or "")
  bar.text:SetText(label)
  bar.left:SetText("")
  bar.right:SetText("")
  bar:SetFrameLevel(self:GetFrameLevel() + 6) -- над областью щелчка: подсказка черты ранга
  return bar
end

-- Сколько создать: поле со стрелками, как в окне профессий игры.
-- Возвращает поле; GetCount() - выбранное число.
function Card:Spinner(x, y, value, maxValue, onChange)
  local e = self:Take("spinner", function()
    local box, tmpl = W.Create("EditBox", nil, self, { "NumericInputSpinnerTemplate", "InputBoxTemplate" })
    box.spin = tmpl == "NumericInputSpinnerTemplate"
    if not box.spin then
      box:SetSize(44, 22)
      if box.SetNumeric then box:SetNumeric(true) end
      box:SetMaxLetters(3)
    end
    box:SetAutoFocus(false)
    box:SetJustifyH("CENTER")
    box:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
    function box:GetCount()
      if self.spin and self.GetValue then return self:GetValue() end
      return tonumber(self:GetText() or "") or 1
    end
    return box
  end)
  -- у поля со стрелками кнопка «-» слева от него
  e:SetPoint("TOPLEFT", self, "TOPLEFT", x + (e.spin and 29 or 0), -y)
  local hi = math.max(1, maxValue or 1)
  if e.spin and e.SetMinMaxValues then
    if e.SetOnValueChangedCallback then e:SetOnValueChangedCallback(nil) end
    e:SetMinMaxValues(1, hi)
    if not (e.HasFocus and e:HasFocus()) then e:SetValue(math.min(math.max(value or 1, 1), hi)) end
    if e.SetOnValueChangedCallback then e:SetOnValueChangedCallback(function(_, v) if onChange then onChange(v) end end) end
  else
    e:SetScript("OnTextChanged", function(s, user)
      if user and onChange then onChange(tonumber(s:GetText() or "") or 0) end
    end)
    if not (e.HasFocus and e:HasFocus()) then e:SetText(tostring(value or 1)) end
  end
  return e, (e.spin and 29 + 31 + 23 or 44)
end

-------------------------------------------------------------------------------
--  Страница: карточки одна под другой
-------------------------------------------------------------------------------
function UI:NewCard()
  local f = CreateFrame("Frame", nil, self.child, BackdropTemplateMixin and "BackdropTemplate" or nil)
  if f.SetBackdrop then f:SetBackdrop(CARD) else W.Backdrop(f, "Interface\\Buttons\\WHITE8X8") end
  f:SetWidth(CARD_W)
  f.pools = {}
  for k, v in pairs(Card) do f[k] = v end
  return f
end

-- Шапка страницы прямо на пергаменте, как во всех страницах MacroCoach:
-- крупный заголовок тёмными чернилами и одна-две строки под ним.
-- buttons - кнопки в ряд под текстом (куда идти дальше), как у страниц
-- MacroCoach: { { text =, onClick =, tip =, enabled = } }.
function UI:PageHeader(title, text, buttons)
  local c = self:Card("flat")
  c:Text(title, "huge", { x = PAD, gap = 8 })
  if text and text ~= "" then c:Text(text, "body", { x = PAD, gap = 4, color = INK_HEAD_TEXT }) end
  local rule = c:Take("rule", function() return c:CreateTexture(nil, "ARTWORK") end)
  rule:SetColorTexture(0.75, 0.6, 0.3, 0.55)
  rule:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, -(c.y + 2))
  rule:SetSize(CARD_W - PAD * 2, 1)
  c.y = c.y + 10
  if buttons and #buttons > 0 then
    c:Space(6)
    local x = PAD
    for _, d in ipairs(buttons) do
      local b = c:Button(d, x, c.y)
      local fs = b.GetFontString and b:GetFontString()
      local w = d.w or max(110, floor((fs and fs:GetStringWidth() or 90) + 30))
      b:SetWidth(w)
      x = x + w + 8
    end
    c.y = c.y + 30
  end
  self:End(c)
  self.y = self.y - 4
  return c
end

-- Новая карточка внизу страницы.
function UI:Card(style)
  self.nCards = self.nCards + 1
  local c = self.cards[self.nCards]
  if not c then c = self:NewCard(); self.cards[self.nCards] = c end
  c:ClearAllPoints()
  c:SetPoint("TOPLEFT", self.child, "TOPLEFT", 10, -self.y)
  c:Show()
  c:Begin(style)
  return c
end

-- Закончить карточку: высота по содержимому (или h). gap - до следующей.
function UI:End(c, gap, h)
  h = h or (c.ink and c.y or max(c.y + PAD - 8, 30))
  c:SetHeight(h)
  self.y = self.y + h + (gap or GAP)
end

-------------------------------------------------------------------------------
--  Окно
-------------------------------------------------------------------------------
local function SetTitle(f, text)
  if type(f.TitleContainer) == "table" and f.SetTitle then f:SetTitle(text)
  elseif f.titleText then f.titleText:SetText(text) end
end

local function SetPortrait(f, tex)
  if type(f.PortraitContainer) == "table" and f.SetPortraitToAsset then
    f:SetPortraitToAsset(tex)
    if f.SetPortraitTexCoord then f:SetPortraitTexCoord(0, 1, 0, 1) end
  end
end

function UI:Create()
  if self.frame then return end
  local f = CreateFrame("Frame", "EasyCraftFrame", UIParent, "ButtonFrameTemplate")
  self.frame = f
  f:SetSize(WIDTH, HEIGHT)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 30)
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetScale(TJ.settings.scale or 1)
  tinsert(UISpecialFrames, "EasyCraftFrame")
  if type(f.TitleContainer) ~= "table" then
    local bg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints()
    bg:SetColorTexture(0.08, 0.08, 0.08, 0.95)
    f.titleText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.titleText:SetPoint("TOP", 0, -6)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    if type(f.CloseButton) ~= "table" then f.CloseButton = close end
  end

  -- «?» рядом с крестиком: вернуть знакомство с аддоном.
  local help = W.Button(f, "?", 22, 20)
  if type(f.CloseButton) == "table" then help:SetPoint("RIGHT", f.CloseButton, "LEFT", -2, 0)
  else help:SetPoint("TOPRIGHT", -28, -1) end
  help:SetFrameLevel(f:GetFrameLevel() + 10)
  help:SetScript("OnClick", function() W.Sound("IG_MAINMENU_OPTION_CHECKBOX_ON"); TJ:ShowIntro() end)
  help:SetScript("OnEnter", function(s)
    GameTooltip:SetOwner(s, "ANCHOR_BOTTOM")
    GameTooltip:SetText(TJ.T("Как пользоваться EasyCraft"), 1, 0.82, 0)
    GameTooltip:Show()
  end)
  help:SetScript("OnLeave", function() GameTooltip:Hide() end)
  f.helpButton = help

  -- Пергамент на месте внутренней панели, как в MacroCoach.
  local page = CreateFrame("Frame", nil, f)
  if type(f.Inset) == "table" then
    f.Inset:ClearAllPoints()
    f.Inset:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -ATTIC)
    f.Inset:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 4)
    page:SetPoint("TOPLEFT", f.Inset, "TOPLEFT", 3, -3)
    page:SetPoint("BOTTOMRIGHT", f.Inset, "BOTTOMRIGHT", -3, 3)
  else
    page:SetPoint("TOPLEFT", 7, -ATTIC - 3)
    page:SetPoint("BOTTOMRIGHT", -9, 7)
  end
  local parchment = page:CreateTexture(nil, "BACKGROUND")
  parchment:SetAllPoints()
  W.Parchment(parchment)

  f.scroll = CreateFrame("ScrollFrame", "EasyCraftScroll", page, "UIPanelScrollFrameTemplate")
  f.scroll:SetPoint("TOPLEFT", 0, -6)
  f.scroll:SetPoint("BOTTOMRIGHT", -30, 6)
  W.ScrollTrack(f.scroll)
  self.child = CreateFrame("Frame", nil, f.scroll)
  self.child:SetSize(CHILD_W, 10)
  f.scroll:SetScrollChild(self.child)
  if type(f.scroll.ScrollBar) ~= "table" then
    f.scroll:EnableMouseWheel(true)
    f.scroll:SetScript("OnMouseWheel", function(s, d)
      local range = s:GetVerticalScrollRange()
      s:SetVerticalScroll(min(range, max(0, s:GetVerticalScroll() - d * 60)))
    end)
  end
  self.cards, self.nCards, self.y = {}, 0, 10

  -- Вкладки разделов сверху
  self.topTabs = {}
  for i = 1, 5 do
    local b = W.TopTab(f)
    if i == 1 then b:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 62, -ATTIC + 1)
    else b:SetPoint("LEFT", self.topTabs[i - 1], "RIGHT", 2, 0) end
    b:SetScript("OnClick", function()
      if b.selected then return end
      W.Sound("IG_CHARACTER_INFO_TAB")
      UI.tab[UI.view] = i
      UI:Render()
    end)
    b:Hide()
    self.topTabs[i] = b
  end

  -- Шапка профессии в полосе под заголовком (на месте вкладок):
  -- полоса навыка, ссылка в чат и окно профессии.
  local head = CreateFrame("Frame", nil, f)
  head:SetPoint("TOPLEFT", f, "TOPLEFT", 66, -26)
  head:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", -10, -ATTIC + 2)
  head.open = W.Button(head, TJ.T("Окно профессии"), 140, 24)
  head.open:SetPoint("RIGHT", head, "RIGHT", 0, 0)
  head.link = W.Button(head, TJ.T("Ссылка в чат"), 130, 24)
  head.link:SetPoint("RIGHT", head.open, "LEFT", -6, 0)
  head.bar = W.Bar(head)
  head.bar:SetHeight(18)
  head.bar:SetPoint("LEFT", head, "LEFT", 6, 0)
  head.bar:SetPoint("RIGHT", head.link, "LEFT", -16, 0)
  head:Hide()
  self.profHead = head

  -- Вкладки справа: главная и изученные профессии
  self.sideTabs = {}
  for i = 1, 8 do
    local t = W.SideTab(f)
    t:SetPoint("TOPLEFT", f, "TOPRIGHT", 0, -40 - (i - 1) * 46)
    t:SetScript("OnClick", function(s)
      W.Sound("IG_ABILITY_PAGE_TURN")
      UI:Open(s.view)
    end)
    t:Hide()
    self.sideTabs[i] = t
  end

  f:Hide()
  -- Мини-окно у окна профессии прячется, пока это окно показывает ту же профессию.
  f:SetScript("OnShow", function() UI:Render(); if TJ.Tracker then TJ.Tracker:Update() end end)
  -- После открытия из настроек окно было над ними (DIALOG): вернуть обычный слой.
  f:SetScript("OnHide", function(s)
    s:SetFrameStrata("HIGH")
    if TJ.Tracker then TJ.Tracker:Update() end
  end)
end

function UI:UpdateSideTabs()
  local views = { "home" }
  for _, key in ipairs(TJ:LearnedList()) do views[#views + 1] = key end
  for i, t in ipairs(self.sideTabs) do
    local v = views[i]
    if v then
      t.view = v
      if v == "home" then
        t.icon:SetTexture(HOME_ICON)
        t.tip, t.tip2 = TJ.T("Главная"), TJ.T("Профессии, карта, лагерь")
      else
        local p = TJ.Profs[v]
        local rank, maxRank = TJ:GetSkill(v)
        t.icon:SetTexture(TJ.Icon(p.icon))
        t.tip, t.tip2 = TJ:N(p), format("%d/%d", rank, maxRank)
      end
      t:SetChecked(v == self.view)
      t:Show()
    else
      t:Hide()
    end
  end
end

-- Разделы: { label, icon }
function UI:SetTopTabs(list, sel)
  for i, b in ipairs(self.topTabs) do
    local t = list[i]
    if t then
      b.icon:SetTexture(t[2])
      b.text:SetText(t[1])
      b:Fit()
      b:SetSelected(i == sel)
      b:Show()
    else
      b:Hide()
    end
  end
end

-- Нарисовать текущую страницу. keepScroll - не сбрасывать прокрутку.
function UI:Render(keepScroll)
  local f = self.frame
  if not (f and f:IsShown()) then return end
  if self.view ~= "home" and not TJ.char.profs[self.view] then self.view = "home" end
  local pos = keepScroll and f.scroll:GetVerticalScroll() or 0
  for i = 1, self.nCards do self.cards[i]:Hide() end
  self.nCards, self.y = 0, 14
  self:UpdateSideTabs()

  local C = TJ.Content
  if self.view == "home" then
    SetTitle(f, TJ.T("EasyCraft: прокачка профессий"))
    self.profHead:Hide()
    SetPortrait(f, TJ.ICON)
    local tabs = C:HomeTabs()
    local sel = min(self.tab.home or 1, #tabs)
    self:SetTopTabs(tabs, sel)
    TJ:Safe(C.BuildHome, C, self, sel)
  else
    local key = self.view
    local p = TJ.Profs[key]
    SetTitle(f, "EasyCraft: " .. TJ:N(p))
    local rank, maxRank = TJ:GetSkill(key)
    local head = self.profHead
    -- Полоса до предела текущего ранга (как в окне профессии игры): 87 из 150.
    local cap = (maxRank and maxRank > 0) and maxRank or 300
    head.bar:SetMinMaxValues(0, cap)
    head.bar:SetValue(min(rank, cap))
    -- одной строкой по центру полосы: «Подмастерье 150/150»
    head.bar.text:SetText(TJ:RankName(maxRank) .. "  " .. format("%d/%d", rank, cap))
    head.bar.left:SetText("")
    head.bar.right:SetText("")
    TJ:MarkNextRank(head.bar, key, rank, cap)
    head.link:SetScript("OnClick", function(b) W.Sound("IG_MAINMENU_OPTION_CHECKBOX_ON"); TJ:LinkMenu(key, b) end)
    head.open:SetScript("OnClick", function() W.Sound("IG_MAINMENU_OPTION_CHECKBOX_ON"); TJ:OpenProfession(key) end)
    head:Show()
    SetPortrait(f, TJ.ICON) -- в портрете всегда значок аддона, профессия - в шапке
    local tabs = C:ProfTabs(key)
    local sel = min(self.tab[key] or 1, #tabs)
    self:SetTopTabs(tabs, sel)
    TJ:Safe(C.BuildProfession, C, self, key, sel)
  end

  self.child:SetHeight(max(self.y, 10))
  if f.scroll.UpdateScrollChildRect then f.scroll:UpdateScrollChildRect() end
  -- страница попросила показать место (шаг профессии): прокрутить к нему
  if self.jumpY then pos, self.jumpY = self.jumpY, nil end
  local range = max(f.scroll:GetVerticalScrollRange() or 0, self.y - self.VIEW_H)
  f.scroll:SetVerticalScroll(max(0, min(pos, range)))
end

-- Открыть страницу: "home" или профессия; sel = "step:N" - показать шаг.
function UI:Open(view, sel)
  self:Create()
  if view ~= "home" and not (view and TJ.char.profs[view]) then view = "home" end
  self.view = view
  TJ.char.lastView = view
  if view ~= "home" then
    -- страница профессии открывается на шаге: выбранном или текущем
    local i = sel and tonumber(tostring(sel):match("^step:(%d+)$"))
    self.focus[view] = i or "cur"
  end
  if not self.frame:IsShown() then self.frame:Show() else self:Render() end
end

function TJ:ToggleFrame()
  UI:Create()
  if UI.frame:IsShown() then UI.frame:Hide(); return end
  -- Первый раз - на главную, к знакомству.
  if not TJ.db.introDone then
    UI.tab.home = 1
    UI:Open("home")
  else
    local last = TJ.char.lastView
    UI:Open((last and TJ.char.profs[last]) and last or "home")
  end
  -- знакомство отдельным окном - один раз (UI/Intro.lua)
  if TJ.IntroOnce then TJ:IntroOnce() end
end

TJ:RegisterRefresh(function() UI:Render(true) end)

-------------------------------------------------------------------------------
--  Мини-окно рядом с окном профессии: шаг, сколько осталось, реагенты и
--  «Создать». Только то, что нужно у верстака; всё остальное - в окне EasyCraft.
-------------------------------------------------------------------------------
local Mini = {}
local BookShown -- ниже
TJ.Tracker = Mini -- Tracking.lua зовёт Attach/Detach, когда окно профессии открылось и закрылось

-- Два вида подсказки (настройка miniClassic, по умолчанию прежний):
--  * новый - как окна игры (ButtonFrameTemplate: металлическая рамка,
--    тёмная шапка с заголовком, тёмная панель), чуть меньше;
--  * прежний - тёмная рамка подсказки, крупная шапка «Шаг 7».
-- Размеры ниже - переменные: ApplyStyle ставит их под выбранный вид.
local MINI_W, MINI_PAD = 340, 12
local MINI_ICON = 36 -- реагенты всегда одного размера; больше 4 - «и ещё N»
local STYLE_MINI = {
  classic = { w = 316, icon = 32, headMid = 11, headH = 34, headIcon = 15, headFont = "head" },
  old = { w = 300, icon = 36, headMid = 25, headH = 48, headIcon = 24, headFont = "huge", ofFont = "body" },
}
local MAX_REAGENTS = 6 -- больше - «и ещё N»; в строке по 3 (ROW_REAGENTS)
local ROW_REAGENTS = 3
-- Сетка мини-окна: шапка (значки 24 в кольцах и «Шаг N» по их центру),
-- между частями - одинаковый отступ; рамки - от MINI_PAD - 4 до края.
local HEAD_ICON = 24
local INK_T, INK_B = { 1, 0.82, 0 }, { 0.9, 0.87, 0.8 } -- текст на тёмной странице
local HEAD_MID = 8 + 18 -- середина шапки от верха окна
local HEAD_H = HEAD_MID + 18 + 6 -- где начинается содержимое
local NewHeadIcons -- ниже
local GAP_SECTION = 8

-- Книга «Профессии» (обзор всех профессий) открыта поверх окна профессии:
-- подсказка шага тут ни к чему.
function BookShown()
  for _, f in ipairs({ _G.ProfessionsBookFrame or false, _G.SpellBookProfessionFrame or false }) do
    if f and f.IsVisible and f:IsVisible() then return true end
  end
  -- В WoW Forever «Профессии» - страница того же окна профессии (вкладка с
  -- молотком): заголовок окна - «Профессии», списка рецептов и кнопки
  -- «Создать» нет. Подсказка нужна только там, где рецепты.
  for _, w in ipairs({ _G.ProfessionsFrame or false, _G.TradeSkillFrame or false }) do
    if w and w.IsVisible and w:IsVisible() then
      local tc = rawget(w, "TitleContainer")
      local name = w.GetName and w:GetName()
      local fs = (type(tc) == "table" and rawget(tc, "TitleText")) or rawget(w, "TitleText") or (name and _G[name .. "TitleText"])
      local title = type(fs) == "table" and fs.GetText and fs:GetText()
      if title and (title == _G.TRADE_SKILLS or title == "Профессии" or title == "Professions") then return true end
    end
  end
  local known = false
  for _, name in ipairs({ "TradeSkillCreateButton", "CraftCreateButton", "TradeSkillListScrollFrame", "CraftListScrollFrame" }) do
    local b = _G[name]
    if type(b) == "table" and b.IsVisible then
      known = true
      if b:IsVisible() then return false end
    end
  end
  local pf = _G.ProfessionsFrame
  local cp = type(pf) == "table" and pf:IsVisible() and rawget(pf, "CraftingPage")
  if type(cp) == "table" and cp.IsVisible then
    known = true
    if cp:IsVisible() then return false end
  end
  return known -- окно знакомое, но страницы с рецептами не видно
end

-- Окно профессии игры. В классике у чар своё окно (CraftFrame) - для них оно первое.
local function ProfWindow(key)
  local order = key == "enchanting" and { CraftFrame or false, ProfessionsFrame or false, TradeSkillFrame or false }
    or { ProfessionsFrame or false, TradeSkillFrame or false, CraftFrame or false }
  for _, f in ipairs(order) do
    if f and f:IsShown() then return f end
  end
end

-- Что торчит справа из окна профессии (вкладки других профессий и т. п.):
-- мини-окно ставим правее, чтобы его не закрывали.
local tabsCache = setmetatable({}, { __mode = "k" })
local function SideTabsRight(anchor, insetR)
  local c = tabsCache[anchor]
  local now = GetTime and GetTime() or 0
  if c and now - c.t < 2 then return c.dx end
  -- видимый правый край: у классических окон справа прозрачное поле
  local right = anchor:GetRight()
  if right then right = right - (insetR or 0) end
  local dx = 0
  if right then
    local function scan(f)
      if f:IsShown() and f ~= Mini.f then
        local l, r = f:GetLeft(), f:GetRight()
        if l and r and l >= right - 12 and l < right + 20 and r > right then dx = max(dx, r - right) end
      end
    end
    for _, ch in ipairs({ anchor:GetChildren() }) do pcall(scan, ch) end
  end
  tabsCache[anchor] = { t = now, dx = dx }
  return dx
end

local function tipOn(frame, title, text)
  frame:SetScript("OnEnter", function(s)
    GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
    GameTooltip:SetText(title, 1, 0.82, 0)
    if text then GameTooltip:AddLine(text, 1, 1, 1, true) end
    GameTooltip:Show()
  end)
  frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function Mini:Create()
  if self.f then return end
  local f = CreateFrame("Frame", "EasyCraftMini", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  f:SetWidth(MINI_W)
  if f.SetBackdrop then
    -- классическая рамка подсказки и тёмный фон, как карточки EasyCraft
    f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    f:SetBackdropColor(0.05, 0.045, 0.04, 0.95)
    f:SetBackdropBorderColor(0.6, 0.48, 0.25, 1)
  end
  f:EnableMouse(true)
  -- тёмный пергамент: та же страница книги, что в окне EasyCraft, притемнённая
  f.parch = f:CreateTexture(nil, "BACKGROUND", nil, 1)
  f.parch:SetPoint("TOPLEFT", 4, -4)
  f.parch:SetPoint("BOTTOMRIGHT", -4, 4)
  W.Parchment(f.parch) -- пергамент как в окне макросов (светлый), блоки на нём - тёмные

  -- Шапка: «Шаг 7» крупно, «из 17» мелко; справа значок - открыть эту
  -- профессию в EasyCraft (весь маршрут, покупки, учителя).
  f.stepBig = W.Text(f, "title", false)
  -- по центру значков справа (см. HEAD_MID)
  f.stepBig:SetPoint("LEFT", f, "TOPLEFT", MINI_PAD, -HEAD_MID)
  f.stepOf = W.Text(f, "small", false)
  f.stepOf:SetPoint("BOTTOMLEFT", f.stepBig, "BOTTOMRIGHT", 6, 2)
  f.headIcons = {}
  -- вид «как окна игры»: рамка окна - отдельное окно позади подсказки
  local okSkin, skin = pcall(CreateFrame, "Frame", nil, UIParent, "ButtonFrameTemplate")
  if okSkin and skin then
    if ButtonFrameTemplate_HidePortrait then pcall(ButtonFrameTemplate_HidePortrait, skin) end
    if type(skin.CloseButton) == "table" then skin.CloseButton:Hide() end
    if type(skin.PortraitContainer) == "table" then skin.PortraitContainer:Hide() end
    if type(skin.Inset) == "table" then
      skin.Inset:ClearAllPoints()
      skin.Inset:SetPoint("TOPLEFT", skin, "TOPLEFT", 4, -24)
      skin.Inset:SetPoint("BOTTOMRIGHT", skin, "BOTTOMRIGHT", -6, 4)
    end
    skin:EnableMouse(false)
    skin:SetAllPoints(f)
    skin:Hide()
    f.skin = skin
    f:HookScript("OnHide", function() skin:Hide() end)
    f:HookScript("OnShow", function() if Mini.classic then skin:Show() end end)
  end
  self:CreateRest(f)
  self:ApplyStyle(f)
  -- подсказку можно перетащить (место запомнится), замочек - в углу
  W.Movable(f, "mini", "TOPRIGHT")
  W.Brand(f) -- «EasyCraft» на верхнем крае
  self:ApplyStyle(f) -- кнопка закрепления в углу, значки шапки - слева от неё
end

-- Значки шапки (книга - открыть EasyCraft, учитель - метка на нужного
-- учителя) нужного размера: у двух видов подсказки они разные.
function NewHeadIcons(f, RS)
  local rp = W.RingPad(RS)
  local set = {}
  set.open = W.RingIcon(f, RS)
  f.open = set.open
  f.open:SetIcon(TJ.ICON)
  f.open:EnableMouse(true)
  f.open:SetScript("OnMouseUp", function() if Mini.key then UI:Open(Mini.key) end end)
  tipOn(f.open, TJ.T("Открыть EasyCraft"), TJ.T("Там весь маршрут, покупки и учителя."))
  -- учитель: знак учителя из игры на тёмном круге
  set.trainer = W.RingIcon(f, RS)
  f.findTrainer = set.trainer
  f.findTrainer:SetPoint("RIGHT", f.open, "LEFT", -rp * 2 - 5, 0)
  -- полный значок на весь круг, как книга справа: свиток - «учиться»
  f.findTrainer:SetIcon("Interface\\Icons\\INV_Scroll_03")
  f.findTrainer.glyph = f.findTrainer.icon
  f.findTrainer:EnableMouse(true)
  -- учитель, который нужен сейчас: выучить рецепт шага или следующий ранг
  f.findTrainer:SetScript("OnMouseUp", function()
    local id = Mini.key and TJ:NeededTrainer(Mini.key)
    if id then TJ:Waypoint(id, true) end
  end)
  f.findTrainer:SetScript("OnEnter", function(s)
    GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
    local id, why = TJ:NeededTrainer(Mini.key or "")
    if id then
      GameTooltip:SetText(TJ.T("Нужный учитель"), 1, 0.82, 0)
      GameTooltip:AddLine(why, 1, 1, 1, true)
      GameTooltip:AddLine(TJ:NpcName(id) .. ", " .. TJ:NpcZone(id), 0.9, 0.9, 0.9, true)
      GameTooltip:AddLine(TJ.T("Щелчок поставит метку и откроет карту."), 0.7, 0.7, 0.7, true)
    else
      GameTooltip:SetText(TJ.T("Учитель пока не нужен"), 1, 0.82, 0)
      if why then GameTooltip:AddLine(why, 1, 1, 1, true) end
    end
    GameTooltip:Show()
  end)
  f.findTrainer:SetScript("OnLeave", function() GameTooltip:Hide() end)
  set.rp = rp
  f.headIcons[RS] = set
  return set
end

-- Поставить вид подсказки (новый «как окна игры» или прежний).
function Mini:ApplyStyle(f)
  local classic = TJ.settings.miniClassic == true and f.skin ~= nil
  local st = STYLE_MINI[classic and "classic" or "old"]
  MINI_W, MINI_ICON = st.w, st.icon
  HEAD_MID, HEAD_H, HEAD_ICON = st.headMid, st.headH, st.headIcon
  f:SetWidth(MINI_W)
  if f.SetBackdrop then
    if classic then
      f:SetBackdropColor(0, 0, 0, 0)
      f:SetBackdropBorderColor(0, 0, 0, 0)
    else
      f:SetBackdropColor(0.05, 0.045, 0.04, 0.95)
      f:SetBackdropBorderColor(0.6, 0.48, 0.25, 1)
    end
  end
  if f.parch then f.parch:SetShown(not classic) end
  self.classic = classic
  if f.skin then
    -- рамка окна видна вместе с подсказкой и чуть ниже неё
    f.skin:SetShown(classic and f:IsShown())
    if classic then
      f.skin:SetFrameStrata(f:GetFrameStrata())
      f.skin:SetFrameLevel(math.max(0, f:GetFrameLevel() - 1))
    end
  end
  -- шапка: в новом виде - в полосе заголовка окна, мельче
  local spec = W.FONTS[st.headFont] or W.FONTS.title
  f.stepBig:SetFontObject(_G[spec[1]] or _G[spec[2]] or GameFontNormal)
  local ofs = W.FONTS[st.ofFont or "small"] or W.FONTS.small
  f.stepOf:SetFontObject(_G[ofs[1]] or _G[ofs[2]] or GameFontHighlightSmall)
  -- на светлом пергаменте - тёмные чернила, как заголовки MacroCoach;
  -- в виде «как окна игры» (тёмный фон) - золото и светлый текст
  local head = classic and { 1, 0.82, 0 } or INK_T
  local body = classic and { 0.75, 0.75, 0.75 } or INK_B
  f.stepBig:SetTextColor(head[1], head[2], head[3])
  f.stepOf:SetTextColor(body[1], body[2], body[3])
  for _, k in ipairs({ "secHead", "npcHead", "name" }) do if f[k] then f[k]:SetTextColor(head[1], head[2], head[3]) end end
  for _, k in ipairs({ "note", "bestHead", "status" }) do if f[k] then f[k]:SetTextColor(body[1], body[2], body[3]) end end
  if f.find then f.find.text:SetTextColor(head[1], head[2], head[3]) end
  f.stepBig:ClearAllPoints()
  f.stepBig:SetPoint("LEFT", f, "TOPLEFT", MINI_PAD, -HEAD_MID)
  for _, set in pairs(f.headIcons) do set.open:Hide(); set.trainer:Hide() end
  local set = f.headIcons[HEAD_ICON] or NewHeadIcons(f, HEAD_ICON)
  f.open, f.findTrainer = set.open, set.trainer
  -- кнопка закрепления - в правом верхнем углу, как у других подсказок;
  -- значки шапки - слева от неё
  local lockW = 0
  if f.lockBtn then
    f.lockBtn:ClearAllPoints()
    if classic then
      f.lockBtn:SetSize(20, 18)
      f.lockBtn:SetPoint("RIGHT", f, "TOPRIGHT", -6, -HEAD_MID)
    else
      f.lockBtn:SetSize(24, 22)
      f.lockBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
    end
    lockW = f.lockBtn:GetWidth() + 6
  end
  set.open:ClearAllPoints()
  set.open:SetPoint("CENTER", f, "TOPRIGHT", -6 - lockW - set.rp - HEAD_ICON / 2 - 2, -HEAD_MID)
  set.open:Show()
  set.trainer:Show()
end

function Mini:CreateRest(f)
  -- Без крестика: окно само прячется вместе с окном профессии, а совсем
  -- выключить его можно в настройках EasyCraft.

  f.name = W.Text(f, "head")
  f.name:SetJustifyV("MIDDLE")
  -- щелчок по названию шага выбирает его рецепт в окне профессии
  f.nameBtn = CreateFrame("Button", nil, f)
  f.nameBtn:SetAllPoints(f.name)
  f.status = W.Text(f, "small")
  f.note = W.Text(f, "small")
  f.reag = {}
  for i = 1, MAX_REAGENTS do f.reag[i] = W.Text(f, "body", false) end
  -- реагенты картинкой: «есть/нужно» под значком, стрелка, что получится
  -- картинки реагентов разных размеров: берём самую крупную, что влезает
  -- реагенты в рамке, как карточка: тёмный фон, золотисто-бурая обводка
  f.flowBox = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
  W.Backdrop(f.flowBox, "Interface\\Buttons\\WHITE8X8", nil, 14, 0.05, 0.045, 0.04, 0.9, 0.6, 0.48, 0.25, 1)
  -- строки «где взять» - на самой рамке: текст окна оказался бы под её фоном
  f.boxText = W.Text(f.flowBox, "body", true)
  f.flows = {}
  f.flow = self:NewFlow(f, MINI_ICON)

  -- «Лучше сейчас»: щелчок выбирает этот рецепт в окне профессии.
  f.best = CreateFrame("Button", nil, f)
  f.best.icon = f.best:CreateTexture(nil, "ARTWORK")
  f.best.icon:SetSize(16, 16)
  f.best.icon:SetPoint("LEFT")
  f.best.text = W.Text(f.best, "small", false)
  f.best.text:SetPoint("LEFT", f.best.icon, "RIGHT", 4, 0)
  f.best.text:SetPoint("RIGHT")
  f.bestHead = W.Text(f, "small")
  -- заголовок части (жёлтый) и описание под ним (серое): «Где ловить» /
  -- «Столицы и соседние зоны»
  f.secHead = W.Text(f, "head")
  f.npcHead = W.Text(f, "head")
  f.secDesc = W.Text(f, "small")

  -- Главное действие - в рамке (акцент): «Сначала купи рецепт у торговца»,
  -- строка с торговцем или учителем и кнопка «На карте».
  f.box = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
  W.Backdrop(f.box, "Interface\\Buttons\\WHITE8X8", nil, 12, 0.16, 0.12, 0.05, 0.9, 0.85, 0.65, 0.2, 1)
  f.boxHead = W.Text(f.box, "small")
  f.trainer = CreateFrame("Button", nil, f.box)
  f.trainer.icon = W.ItemIcon(f.trainer, 22)
  f.trainer.icon:SetPoint("LEFT", W.IconPad(22), 0)
  f.trainer.icon:EnableMouse(false)
  f.trainer.text = W.Text(f.trainer, "body", false)
  f.trainer.text:SetPoint("TOPLEFT", f.trainer.icon, "TOPRIGHT", W.IconPad(22) + 6, 1)
  f.trainer.text:SetPoint("RIGHT", -74, 0)
  f.trainer.text:SetWordWrap(false)
  f.trainer.sub = W.Text(f.trainer, "small", false)
  f.trainer.sub:SetPoint("TOPLEFT", f.trainer.text, "BOTTOMLEFT", 0, -2)
  f.trainer.sub:SetPoint("RIGHT", -74, 0)
  f.trainer.sub:SetWordWrap(false)
  local thl = f.trainer:CreateTexture(nil, "HIGHLIGHT")
  thl:SetAllPoints()
  thl:SetColorTexture(1, 0.82, 0, 0.1)
  f.pin = W.Button(f.box, TJ.T("На карте"), 68, 22)
  -- черта между частями окна
  f.seps = {}
  for i = 1, 3 do
    local t = f:CreateTexture(nil, "ARTWORK")
    t:SetHeight(1)
    t:SetColorTexture(0.6, 0.48, 0.25, 0.45)
    f.seps[i] = t
  end
  -- кнопка у строки «где собирать»
  f.map = W.Button(f, TJ.T("Показать на карте"), MINI_W - MINI_PAD * 2, 22)
  -- «Включи поиск трав» и т. п.: щелчок включает
  f.find = CreateFrame("Button", nil, f)
  f.find.icon = f.find:CreateTexture(nil, "ARTWORK")
  f.find.icon:SetSize(16, 16)
  f.find.icon:SetPoint("LEFT")
  f.find.text = W.Text(f.find, "small", false)
  f.find.text:SetPoint("LEFT", f.find.icon, "RIGHT", 4, 0)
  f.find.text:SetPoint("RIGHT")
  local fhl = f.find:CreateTexture(nil, "HIGHLIGHT")
  fhl:SetAllPoints()
  fhl:SetColorTexture(1, 0.82, 0, 0.12)
  local hl = f.best:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 0.82, 0, 0.12)

  f.create = W.Button(f, TJ.T("Создать"), MINI_W - MINI_PAD * 2, 22)
  f.rows = {}
  f:SetClampedToScreen(true)
  f:Hide()
  self.f = f
end

local function place(fs, f, y, w)
  fs:ClearAllPoints()
  fs:SetPoint("TOPLEFT", f, "TOPLEFT", MINI_PAD, -y)
  fs:SetWidth(w or (MINI_W - MINI_PAD * 2))
  fs:Show()
  return y + fs:GetStringHeight() + 4
end

-- Полоса шагов в мини-окне: тот же вид, что на карточке шага, только меньше.
function Mini:Dots(f, key, order, sel, rank, maxRank, y)
  f.dots = f.dots or {}
  for _, d in ipairs(f.dots) do d:Hide() end
  local n = #order
  if n == 0 then return y end
  local gap = 2
  local w = math.min(14, floor((MINI_W - MINI_PAD * 2 - gap * (n - 1)) / n))
  local cur = TJ:CurrentStep(key, rank, maxRank)
  for k, si in ipairs(order) do
    local d = f.dots[k]
    if not d then d = f:CreateTexture(nil, "ARTWORK"); f.dots[k] = d end
    d:SetSize(w, 6)
    d:ClearAllPoints()
    d:SetPoint("TOPLEFT", f, "TOPLEFT", MINI_PAD + (k - 1) * (w + gap), -(y + 1))
    local st = TJ:StepState(key, si, rank, maxRank)
    if st == "done" then d:SetColorTexture(0.3, 0.75, 0.3, 1)
    elseif si == cur then d:SetColorTexture(1, 0.82, 0, 1)
    else d:SetColorTexture(0.32, 0.27, 0.2, 1) end
    d:Show()
  end
  return y + 6 + 8
end

-- Черта между частями окна.
local function sep(f, i, y)
  local t = f.seps[i]
  t:ClearAllPoints()
  t:SetPoint("TOPLEFT", f, "TOPLEFT", MINI_PAD, -y)
  t:SetPoint("TOPRIGHT", f, "TOPRIGHT", -MINI_PAD, -y)
  t:Show()
  return y + GAP_SECTION
end

-- Строка-кнопка: значок, текст, справа текст или значок. Лучшая (hot) -
-- в золотой рамке и чуть светлее.
local function MiniRow(f, i)
  local r = f.rows[i]
  if r then return r end
  r = CreateFrame("Button", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
  W.Backdrop(r, "Interface\\Buttons\\WHITE8X8", nil, 10, 0, 0, 0, 0, 0, 0, 0, 0)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(22, 22)
  r.icon:SetPoint("LEFT", 6, 0)
  r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  -- звезда «рекомендуем» в углу значка
  r.star = r:CreateTexture(nil, "OVERLAY", nil, 2)
  r.star:SetSize(16, 16)
  r.star:SetPoint("CENTER", r.icon, "TOPLEFT", 1, -1)
  W.SetTex(r.star, { "Interface\\COMMON\\ReputationStar" }, 1, 0.82, 0, 1)
  r.star:SetTexCoord(0, 0.5, 0, 0.5)
  r.right = W.Text(r, "small", false)
  r.right:SetJustifyH("RIGHT")
  r.right:SetPoint("RIGHT", -8, -1)
  -- значки справа (что там собирать) - такие же, как значок карты слева
  r.nodes = {}
  for k = 1, 3 do
    local t = r:CreateTexture(nil, "ARTWORK")
    t:SetSize(22, 22)
    t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if k == 1 then t:SetPoint("RIGHT", -7, 0) else t:SetPoint("RIGHT", r.nodes[k - 1], "LEFT", -3, 0) end
    r.nodes[k] = t
  end
  r.text = W.Text(r, "body", false)
  r.text:SetPoint("LEFT", r.icon, "RIGHT", 5, 0)
  r.text:SetPoint("RIGHT", r.right, "LEFT", -4, 0)
  r.text:SetWordWrap(false)
  local hl = r:CreateTexture(nil, "HIGHLIGHT")
  hl:SetPoint("TOPLEFT", 2, -2)
  hl:SetPoint("BOTTOMRIGHT", -2, 2)
  hl:SetColorTexture(1, 0.82, 0, 0.1)
  f.rows[i] = r
  return r
end

local function SetRow(f, _, y, d)
  f.nextRow = (f.nextRow or 0) + 1
  local r = MiniRow(f, f.nextRow)
  r:ClearAllPoints()
  r:SetPoint("TOPLEFT", f, "TOPLEFT", MINI_PAD - 4, -y)
  r:SetSize(MINI_W - MINI_PAD * 2 + 8, 34)
  r.icon:SetTexture(d.icon)
  r.icon:SetShown(d.icon ~= nil)
  r.star:SetShown(d.star and true or false)
  r.text:ClearAllPoints()
  if d.icon then r.text:SetPoint("LEFT", r.icon, "RIGHT", 5, -1) else r.text:SetPoint("LEFT", 6, -1) end
  r.text:SetText(d.text or "")
  r.right:SetText(d.right or "")
  -- значки справа; не влезает название - на один значок меньше
  local list = d.nodeIcons or {}
  local nIcons = math.min(#list, 3)
  local rowW = MINI_W - MINI_PAD * 2 + 8
  local textLeft = d.icon and (6 + 22 + 5) or 6
  if nIcons == 3 and r.text:GetStringWidth() > rowW - textLeft - (7 + 3 * 22 + 2 * 3) - 6 then nIcons = 2 end
  for k = 1, 3 do
    r.nodes[k]:SetShown(k <= nIcons)
    if k <= nIcons then r.nodes[k]:SetTexture(list[k]) end
  end
  r.right:ClearAllPoints()
  if nIcons > 0 then r.right:SetPoint("RIGHT", r.nodes[nIcons], "LEFT", -6, -1) else r.right:SetPoint("RIGHT", -8, -1) end
  if (d.right or "") ~= "" then
    r.text:SetPoint("RIGHT", r.right, "LEFT", -6, 0)
  elseif nIcons > 0 then
    r.text:SetPoint("RIGHT", r.nodes[nIcons], "LEFT", -6, -1)
  else
    r.text:SetPoint("RIGHT", -8, -1)
  end
  if d.hot then
    r:SetBackdropColor(0.2, 0.15, 0.05, 0.9)
    r:SetBackdropBorderColor(1, 0.82, 0, 1)
  else
    -- на пергаменте строка - тёмный блок, как карточка макроса
    r:SetBackdropColor(0.05, 0.045, 0.04, 0.9)
    r:SetBackdropBorderColor(0.6, 0.48, 0.25, 0.8)
  end
  r:SetScript("OnClick", d.onClick)
  tipOn(r, d.tipTitle or "", d.tip)
  if r.del then r.del:Hide() end
  r:Show()
  return y + 37
end

function Mini:Reset(f)
  for _, k in ipairs({ "status", "note", "flow", "bestHead", "secHead", "secDesc", "npcHead", "box", "create", "find", "name", "nameBtn", "map", "best" }) do f[k]:Hide() end
  for _, r in ipairs(f.reag) do r:Hide() end
  if f.boxText then f.boxText:Hide() end
  for _, t in ipairs(f.seps) do t:Hide() end
  for _, d in ipairs(f.dots or {}) do d:Hide() end
  for _, r in ipairs(f.rows) do r:Hide() end
  f.nextRow = 0
  if f.queueHead then f.queueHead:Hide() end
  if f.queueBtn then f.queueBtn:Hide() end
  for _, fl in pairs(f.flows) do fl:Hide() end
  for _, fl in pairs(f.flow2s or {}) do fl:Hide() end
  f.flowBox:Hide()
end

-- Картинка реагентов самого крупного размера, что влезает в ширину окна:
-- n значков (и стрелка, если есть результат).
function Mini:FlowFor(f)
  return f.flows[MINI_ICON] or self:NewFlow(f, MINI_ICON)
end

-- Картинка реагентов с крупными числами под значками.
function Mini:NewFlow(f, size)
  local fl = W.Flow(f, size)
  for _, l in ipairs(fl.labels) do l:SetFontObject(_G.SystemFont_Med1 or GameFontHighlightSmall) end
  -- числа ближе к значкам
  fl.labelGap, fl.labelH = -W.IconPad(size) + 3, 12
  f.flows[size] = fl
  return fl
end

-- Реагенты (или что собирать) в рамке, по центру. Возвращает новый y.
-- Ширина окна постоянная: реагенты всегда одного размера, а если их больше
-- трёх - остальные второй строкой под первыми.
function Mini:PlaceFlow(f, inputs, out, y, lines)
  local fl = self:FlowFor(f)
  local first, rest = inputs, nil
  if out and #inputs > ROW_REAGENTS then
    first, rest = {}, {}
    for i, it in ipairs(inputs) do tinsert(i <= ROW_REAGENTS and first or rest, it) end
  end
  local fw, fh = fl:Set(first, out)
  local w2 = MINI_W - MINI_PAD * 2
  local x = MINI_PAD + floor((w2 - fw) / 2)
  local box = f.flowBox
  box:ClearAllPoints()
  box:SetPoint("TOPLEFT", f, "TOPLEFT", MINI_PAD - 4, -y)
  box:SetFrameLevel(f:GetFrameLevel() + 1)
  fl:ClearAllPoints()
  fl:SetPoint("TOPLEFT", f, "TOPLEFT", x, -(y + 6))
  fl:SetFrameLevel(box:GetFrameLevel() + 2)
  fl:Show()
  local total = fh
  if rest and #rest > 0 then
    -- вторая строка: тот же размер, под первыми реагентами
    f.flow2s = f.flow2s or {}
    f.flow2 = f.flow2s[MINI_ICON] or self:NewFlowExtra(f)
    f.flow2s[MINI_ICON] = f.flow2
    local _, h2 = f.flow2:Set(rest, nil)
    f.flow2:ClearAllPoints()
    f.flow2:SetPoint("TOPLEFT", f, "TOPLEFT", x, -(y + 6 + fh))
    f.flow2:SetFrameLevel(box:GetFrameLevel() + 2)
    f.flow2:Show()
    total = total + h2
  end
  -- строки «где взять» - внутри той же тёмной рамки, под реагентами
  if lines and #lines > 0 then
    local l = f.boxText
    l:SetText(table.concat(lines, "\n"))
    l:SetWordWrap(true)
    l:SetTextColor(0.92, 0.92, 0.92)
    l:ClearAllPoints()
    -- с просветом от «есть/нужно» под значками
    l:SetPoint("TOPLEFT", f, "TOPLEFT", MINI_PAD + 4, -(y + 6 + total + 9))
    l:SetWidth(w2 - 8)
    l:Show()
    total = total + 9 + l:GetStringHeight() + 4
  end
  box:SetSize(w2 + 8, total + 12)
  box:Show()
  return y + total + 12 + GAP_SECTION
end

-- Вторая строка реагентов: отдельная картинка того же размера.
function Mini:NewFlowExtra(f)
  local fl = W.Flow(f, MINI_ICON)
  for _, l in ipairs(fl.labels) do l:SetFontObject(_G.SystemFont_Med1 or GameFontHighlightSmall) end
  fl.labelGap, fl.labelH = -W.IconPad(MINI_ICON) + 3, 12
  return fl
end

-- Название шага: справа от картинки, по центру значков; если места
-- мало (много реагентов) - под картинкой.
local function placeName(f, text, flowRight, flowTop, iconH, y)
  local free = MINI_W - MINI_PAD * 2 - flowRight - 10
  f.name:ClearAllPoints()
  f.name:SetText(text)
  if free >= 80 then
    f.name:SetPoint("LEFT", f, "TOPLEFT", MINI_PAD + flowRight + 10, -(flowTop + iconH / 2))
    f.name:SetWidth(free)
    f.name:Show()
    return y
  end
  f.name:SetPoint("TOPLEFT", f, "TOPLEFT", MINI_PAD, -y)
  f.name:SetWidth(MINI_W - MINI_PAD * 2)
  f.name:Show()
  return y + f.name:GetStringHeight() + 4
end

-- Мини-версия карточки шага у окна профессии. Сверху вниз:
-- 1) «Шаг 7» крупно, «из 17» мелко, справа значок - открыть EasyCraft;
--    полоса шагов;
-- 2) что делается: реагенты картинкой, справа название шага («Зубатка
--    ощетиненная»); строки, где взять недостающее (цены монетами);
--    у сбора и рыбалки - зоны отдельными кнопками, лучшая выделена;
-- 3) главное действие в рамке: купить/выучить рецепт или «Создать N»;
-- 4) под чертой - другие рецепты, на которых можно качаться, лучший выделен.
function Mini:Update()
  local f, key = self.f, self.key
  if not f then return end
  local anchor = key and ProfWindow(key)
  local mainOnIt = UI.frame and UI.frame:IsShown() and UI.view == key -- то же уже видно в окне EasyCraft
  self.anchor = anchor
  if not anchor or mainOnIt or self.hidden or TJ.settings.miniGuide == false or not TJ:IsProfOpen(key) or BookShown() then
    f:Hide()
    return
  end
  local rank, maxRank = TJ:GetSkill(key)
  local i, s = TJ:CurrentStep(key, rank, maxRank)
  -- маршрут пройден: окно остаётся ради очереди крафта (если рецепты прочитаны)
  local finished = not s
  if finished and not (TJ.char.book and TJ.char.book[key]) then f:Hide(); return end
  -- Горное дело у плавильни: шаг - сбор, а здесь полезно другое - что плавить.
  local smelt = not finished and key == "mining" and s.k == "gather" and TJ:SmeltNow(rank)
  if smelt and not smelt.real then smelt = nil end
  local state = not finished and TJ:StepState(key, i, rank, maxRank)

  -- справа от окна, без прозрачного края классических окон; не за экраном
  local _, insetR = 0, 0
  if anchor.GetHitRectInsets then _, insetR = anchor:GetHitRectInsets() end
  if not W.PlaceSaved(f, "mini") then
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 2 - (insetR or 0) + SideTabsRight(anchor, insetR), 0)
  end
  f:SetFrameStrata(anchor:GetFrameStrata())
  f:SetFrameLevel(anchor:GetFrameLevel() + 10)
  self:ApplyStyle(f)

  self:Reset(f)
  local T = TJ.T
  -- 1. Шапка
  local pos, count, order
  if not finished then pos, count, order = TJ.Content:StepPos(TJ.Profs[key], i) end
  f.stepBig:SetText(pos and format(T("Шаг %d"), pos) or TJ:N(TJ.Profs[key]))
  f.stepOf:SetText(pos and format(T("из %d"), count) or "")
  -- значок учителя ярко, только когда учитель нужен сейчас
  local need = TJ:NeededTrainer(key)
  -- не нужен - серый и тусклее; нужен - в цвете
  f.findTrainer.glyph:SetDesaturated(not need)
  f.findTrainer:SetAlpha(need and 1 or 0.65)
  local y = HEAD_H
  if finished then
    y = self:Queue(f, key, y + GAP_SECTION / 2)
    f:SetHeight(y + 4)
    f:Show()
    return
  end
  if smelt then return self:ShowSmelt(f, key, smelt, y) end

  local isCraft = s.k == "craft" and state ~= "done"
  local col = s.k == "craft" and (TJ:RealColor(key, s.spell, rank) or (s.sk and TJ:RecipeColor(s, rank)))
  local nameText = col and (TJ:Hex(col) .. TJ:StepName(s) .. "|r") or TJ:StepName(s)
  if isCraft and s.spell then
    f.nameBtn:SetScript("OnClick", function() TJ:OpenRecipe(key, s.spell) end)
    tipOn(f.nameBtn, TJ:StepName(s), T("Щелчок выберет рецепт в окне профессии."))
  end

  -- 2. Что делается
  local left = isCraft and TJ:RemainingCrafts(s, rank) or 0
  local n = 0
  local st = isCraft and s.spell and TJ:RecipeState(key, s.spell)
  if st and not st.unknown and st.known and not st.enchant then n = math.min(st.count or 0, math.max(left, 1)) end
  if isCraft and s.rc and left > 0 then
    local b = TJ:StepBuy(s, left)
    local inputs, total = {}, #b.items
    for _, e in ipairs(b.items) do
      if #inputs < MAX_REAGENTS then
        local tip = e.mail > 0 and (TJ.MAIL_COLOR .. format(T("на почте %d"), e.mail) .. "|r") or nil
        if e.have < e.need and e.all > e.have then
          tip = "|cffffd100" .. format(T("в банке %d - забери у банкира"), e.all - e.have) .. "|r" .. (tip and ("\n" .. tip) or "")
        end
        if e.buy > 0 then
          local how = e.vendor and (format(T("купить %d у торговца"), e.buy)
              .. (e.cost and (": " .. (e.approx and "~" or "") .. W.Money(e.cost)) or ""))
            or (e.cost and format(T("докупить %d: %s на аукционе"), e.buy, W.Money(e.cost)))
            or format(T("докупить %d"), e.buy)
          tip = (tip and (tip .. "\n") or "") .. how
        end
        tinsert(inputs, { id = e.id, done = e.have >= e.need,
          text = (e.have >= e.need and "|cff33dd33" or "|cffff5555") .. min(e.have, 999) .. "/" .. e.need .. "|r", tip = tip })
      end
    end
    local out = s.id and { id = s.id } or { tex = TJ:StepIcon(s, TJ.Profs[key]), spell = s.spell }
    out.text = "|cffffffff" .. left .. "|r"
    -- где взять недостающее (хватает - видно по галочкам, отдельно не пишем) -
    -- в той же рамке, что реагенты
    local lines = b.allHave and {} or TJ:StepBuyLines(b)
    if total > #inputs then tinsert(lines, 1, "|cff9d9d9d" .. format(T("и ещё %d"), total - #inputs) .. "|r") end
    y = self:PlaceFlow(f, inputs, out, y, lines)
  elseif s.k == "gather" or s.k == "zone" then
    y = self:Gather(f, key, s, rank, y, nameText)
  else
    -- ранг у учителя, книга, задание: если ниже будет кнопка «к кому идти»,
    -- название и «навык упёрся» не пишем - кнопка говорит всё сама
    local ra0 = TJ:RankAction(key)
    if not (ra0 and ra0.can and ra0.id and ra0.s == s) then
      y = placeName(f, nameText, MINI_W, y, 0, y)
      local stx = TJ:ShortStatus(key, s, rank, state)
      if stx then f.note:SetText(stx); y = place(f.note, f, y) end
    end
  end
  if f.name:IsShown() and isCraft and s.spell then f.nameBtn:SetAllPoints(f.name); f.nameBtn:Show() end

  -- 3. Главное действие
  local ra = TJ:RankAction(key)
  if isCraft and st and st.known == false and not st.unknown then
    y = self:LearnBox(f, key, s, y)
  elseif ra and ra.can and ra.id then
    -- следующий ранг уже можно взять: без него навык упрётся в предел
    y = self:RankBox(f, ra, y)
  elseif ra and maxRank > 0 and rank >= maxRank - 10 then
    -- скоро упрёшься в предел, а ранг ещё нельзя - сказать, когда можно
    local _, why = TJ:NeededTrainer(key)
    if why then
      f.note:SetText("|cffff5555" .. format(T("Предел навыка %d."), maxRank) .. "|r " .. why)
      y = place(f.note, f, y) + GAP_SECTION - 4
    end
  end
  if not (isCraft and st and st.known == false and not st.unknown) and n > 0 then
    self:CreateBtn(f, key, s.spell, n, y, T("Сделает столько, сколько нужно до конца шага (и сколько хватит реагентов)."))
    y = y + 22 + GAP_SECTION
  end

  -- 4. Другие рецепты: лучший в рамке
  local offers = isCraft and TJ:BestRecipes(key, s, rank, 3) or {}
  if #offers > 0 then
    y = sep(f, 1, y - GAP_SECTION / 2)
    local best = offers[1]
    local instead = best.instead and n <= 0
    -- заголовок жёлтым, без описания (почему - в подсказке строки)
    f.secHead:SetText(instead and T("Можно качать и на них") or T("Выгоднее сейчас"))
    y = place(f.secHead, f, y) + 3
    for k, o in ipairs(offers) do
      local right = o.a > 0 and format(T("хватит на %d"), o.a) or "|cff9d9d9d" .. T("нет реагентов") .. "|r"
      if o.cost then right = W.Money(o.cost) .. "  " .. right end
      local why = (k == 1 and (instead and T("Навык растёт и от него, а реагенты на шаг пока соберёшь.")
        or (o.sameColor and T("Того же цвета, что рецепт шага, но на него есть реагенты.") or T("Даст навык вернее, чем рецепт шага.")))
        or T("Ещё вариант.")) .. (o.cost and ("\n" .. format(T("~%s за создание"), W.Money(o.cost))) or "")
      if o.chance then why = why .. "\n" .. format(T("Навык растёт не всегда: %s за создание."), o.chance) end
      local id = o.id
      y = SetRow(f, k, y, { icon = o.icon or TJ.Icon(nil), star = k == 1, hot = k == 1,
        text = TJ:Hex(o.color) .. (o.name or "?") .. "|r", right = right,
        tipTitle = o.name, tip = why .. "\n" .. T("Щелчок откроет его в окне профессии."),
        onClick = function() TJ:OpenRecipe(key, id) end })
    end
    y = y + GAP_SECTION - 3
    if instead and best.n > 0 then
      self:CreateBtn(f, key, best.id, best.n, y,
        format(T("Создаст «%s»: %d шт. (не больше, чем осталось до конца шага)."), best.name or "?", best.n))
      f.create:SetText(format(T("Создать %d: %s"), best.n, best.name or "?"))
      y = y + 22 + GAP_SECTION
    end
  end
  y = self:Queue(f, key, y)
  f:SetHeight(y + 4)
  f:Show()
end

-- Очередь крафта этой профессии (Book.lua): строки по выгоде, щелчок -
-- создать, крестик справа - убрать из очереди. Очереди нет - кнопка, которая
-- открывает вкладку «Рецепты», где её собирают. Только у профессий, чьи
-- рецепты аддон уже прочитал.
function Mini:Queue(f, key, y)
  if not (TJ.QueueList and TJ.char.book and TJ.char.book[key]) then return y end
  local T = TJ.T
  local list = {}
  for _, e in ipairs(TJ:QueueList()) do
    if e.key == key then list[#list + 1] = e end
  end
  y = sep(f, 3, y - GAP_SECTION / 2)
  if not f.queueHead then f.queueHead = W.Text(f, "head") end
  f.queueHead:SetText(T("Очередь крафта"))
  y = place(f.queueHead, f, y) + 3
  if not f.queueBtn then f.queueBtn = W.Button(f, "", MINI_W - MINI_PAD * 2, 22) end
  local btn = f.queueBtn
  local function openBook()
    UI.tab.home = 5
    UI:Open("home")
  end
  if #list == 0 then
    btn:SetText(T("Добавить в очередь"))
    btn:SetScript("OnClick", openBook)
    tipOn(btn, T("Очередь крафта"), T("Откроет вкладку «Рецепты»: щёлкни по рецепту, и он появится здесь."))
  else
    local hot = TJ:QueueNext(list)
    for k, e in ipairs(list) do
      local right = not e.known and ("|cffff5555" .. T("рецепт не выучен") .. "|r")
        or (e.can > 0 and format(T("хватит на %d"), e.can) or ("|cff9d9d9d" .. T("нет реагентов") .. "|r"))
      y = SetRow(f, k, y, { icon = (e.out and TJ:ItemIcon(e.out)) or e.icon or TJ.Icon(nil), hot = e == hot, star = e == hot,
        text = format("%d × %s", e.n, e.name or "?"), right = right,
        tipTitle = e.name or "?", tip = T("Щелчок - создать. Крестик справа уберёт из очереди."),
        onClick = function() TJ:QueueCraft(e) end })
      -- крестик у правого края строки, текст справа - левее него
      local r = f.rows[f.nextRow]
      if not r.del then
        r.del = CreateFrame("Button", nil, r, "UIPanelCloseButton")
        r.del:SetSize(22, 22)
        r.del:SetPoint("RIGHT", -1, 0)
      end
      r.del:SetScript("OnClick", function()
        TJ:QueueRemove(e.spell)
        TJ:RefreshAll()
      end)
      r.del:Show()
      r.right:ClearAllPoints()
      r.right:SetPoint("RIGHT", -24, -1)
    end
    y = y + GAP_SECTION - 3
    btn:SetText(T("Все рецепты и очередь"))
    btn:SetScript("OnClick", openBook)
    tipOn(btn, T("Очередь крафта"), T("Откроет вкладку «Рецепты»: там вся очередь, что докупить и новые рецепты в неё."))
  end
  btn:ClearAllPoints()
  btn:SetPoint("TOPLEFT", f, "TOPLEFT", MINI_PAD, -y)
  btn:Show()
  return y + 22 + GAP_SECTION
end

-- Кнопка «Создать N» на всю ширину.
function Mini:CreateBtn(f, key, spell, count, y, tip)
  f.create:ClearAllPoints()
  f.create:SetWidth(MINI_W - MINI_PAD * 2)
  f.create:SetPoint("TOPLEFT", f, "TOPLEFT", MINI_PAD, -y)
  f.create:SetText(format(TJ.T("Создать %d"), count))
  f.create:SetEnabled(true)
  f.create:SetScript("OnClick", function() TJ:Craft(key, spell, count) end)
  tipOn(f.create, TJ.T("Создать"), tip)
  f.create:Show()
end

-- Рамка «выучи рецепт»: заголовок с ценой, торговец или учитель (значок
-- рецепта или учителя, имя, зона) и «На карте» - метка и карта.
function Mini:LearnBox(f, key, s, y)
  local T = TJ.T
  local src = TJ:RecipeSource(key, s)
  local head = src.kind == "vendor" and T("Купи рецепт") or (src.kind == "trainer" and src.npc and T("Выучи рецепт у учителя"))
    or TJ:RecipeSourceHead(src)
  local money = src.kind == "vendor" and (src.copper and W.Money(src.copper) or src.price) or nil
  return self:NpcBox(f, head, src.npc, src.kind == "vendor" and src.item or nil,
    src.extra, (src.kind == "vendor" and T("Ближайший торговец этим рецептом.") or T("Ближайший учитель.")), y, src.count, money)
end

-- Можно взять следующий ранг: у учителя, купить книгу, взять задание.
function Mini:RankBox(f, ra, y)
  local T = TJ.T
  local head
  -- цена книги: запомненная у торговца или примерная (по цене продажи)
  local price, approx
  if ra.item then price, approx = TJ:VendorPrice(ra.item) end
  -- коротко: что сделать и какой ранг; предел - в подсказке строки, цена -
  -- на самой строке справа
  if ra.kind == "book" then head = format(T("Купи книгу «%s»"), ra.name)
  elseif ra.kind == "quest" then head = format(T("Задание на ранг «%s»"), ra.name)
  else head = format(T("Выучи ранг «%s»"), ra.name) end
  local who = (ra.kind == "book" and T("Ближайший торговец этой книгой.")
    or (ra.kind == "quest" and T("Кто ближе всех даёт задание.") or T("Ближайший учитель.")))
    .. "\n" .. format(T("Предел навыка станет %d."), ra.max)
  local money = price and ((approx and "~" or "") .. W.Money(price)) or nil
  return self:NpcBox(f, head, ra.id, ra.item, nil, who, y, ra.count, money)
end

-- «Что сделать у NPC»: жёлтый заголовок и строка-кнопка, как кнопки зон:
-- слева значок (книга/рецепт или свиток учителя), имя и зона, справа -
-- значок карты; в золотой рамке - это главное действие. Щелчок - метка и карта.
function Mini:NpcBox(f, head, id, item, extra, who, y, count, money)
  local T = TJ.T
  f.npcHead:SetText(head)
  y = place(f.npcHead, f, y) + 3
  if not id then return y + GAP_SECTION - 4 end
  local which = count == 1 and T("Единственный.") or (count and count > 1 and format(T("Ближайший из %d."), count)) or nil
  local tip = (who or "") .. (which and ("\n" .. which) or "") .. (extra and ("\n" .. extra) or "")
    .. "\n" .. T("Щелчок поставит метку и откроет карту.")
  -- как кнопки зон: слева значок карты (щелчок - карта), справа - что там
  -- взять (книга, рецепт или свиток учителя)
  y = SetRow(f, nil, y, { icon = "Interface\\Icons\\INV_Misc_Map_01", hot = true,
    text = TJ:NpcName(id) .. "  |cff9d9d9d" .. TJ:NpcZone(id) .. "|r",
    right = money, nodeIcons = { item and TJ:ItemIcon(item) or "Interface\\Icons\\INV_Scroll_03" },
    tipTitle = TJ:NpcName(id), tip = tip,
    onClick = function() TJ:Waypoint(id, true) end })
  return y + GAP_SECTION - 3
end

-- Сбор и рыбалка: что собирать (значки с навыком, с которого берётся, цветом
-- по твоему навыку) и справа название шага; зоны - отдельными кнопками на
-- карту, лучшая в рамке; включить поиск; наживка.
function Mini:Gather(f, key, s, rank, y, nameText)
  local T = TJ.T
  local C = TJ.Content
  local inputs = {}
  if s.k == "gather" and s.nodes then
    for _, nk in ipairs(s.nodes) do
      local nd = TJ.Nodes[nk]
      if nd and #inputs < ROW_REAGENTS + 1 then
        local col = TJ:GatherColor(max(rank, 1), nd.req)
        tinsert(inputs, { id = nd.item, text = TJ:Hex(col) .. nd.req .. "|r",
          tip = format(T("с навыка %d, %s"), nd.req, TJ.ColorName[col] or "") })
      end
    end
  end
  if #inputs > 0 then
    y = self:PlaceFlow(f, inputs, nil, y)
  end
  -- зоны: где больше всего (сбор) или где ловить (зоны шага); первая - лучшая
  local zones = {}
  if s.k == "gather" then
    zones = TJ:StepGatherZones(s, rank, 6)
  else
    -- рыбалка: зоны шага по порядку, рекомендуем первую
    -- сначала лучшие зоны своей фракции (из маршрута), потом остальные
    local seen = {}
    local recList = s[TJ:PlayerFaction() == "A" and "recA" or "recH"] or {}
    for _, list in ipairs({ recList, s.areas or {} }) do
      for _, a in ipairs(list) do
        if not seen[a] and TJ:ZoneAllowed(a) and #zones < 4 then
          seen[a] = true
          tinsert(zones, { area = a, rec = #zones == 0 })
        end
      end
    end
  end
  if #zones > 0 then
    -- заголовок жёлтым, без описания; до кнопок чуть больше места
    f.secHead:SetText(s.k == "gather" and T("Где собирать") or T("Где ловить"))
    y = place(f.secHead, f, y) + 3
    for k, z in ipairs(zones) do
      local a = z.area
      -- справа - что из шага там растёт (значки); первая - лучшая, в рамке
      local _, what = TJ:ZoneNodesText(z, 19, 3)
      local nodeIcons = TJ:ZoneNodeIcons(z, 3)
      local why = TJ:ZoneWhy(z)
      -- одна пометка - звезда «рекомендуем»; список и так от лучшей к худшей
      y = SetRow(f, k, y, { icon = "Interface\\Icons\\INV_Misc_Map_01", star = z.rec, hot = z.rec,
        text = C:ZoneText(a, true), nodeIcons = nodeIcons,
        tipTitle = TJ:ZoneName(a), tip = why .. (what ~= "" and ("\n" .. what) or "")
          .. "\n" .. T("Щелчок откроет карту на этой зоне: места сбора отмечены."),
        onClick = function() C:ShowOnMap(a, s.nodes) end })
    end
    y = y + GAP_SECTION - 3
  elseif s.note and s.k == "craft" then
    f.note:SetText(s.note)
    y = place(f.note, f, y)
  end
  -- поиск руды и трав выключен - щелчок включит
  if s.k == "gather" then
    local t = TJ:FindTracking(key)
    if t and not t.active and not TJ:AnyFindActive() then
      f.find.icon:SetTexture(t.icon or TJ.Icon(nil))
      f.find.text:SetText(format(T("Включи «%s»"), t.name))
      f.find:ClearAllPoints()
      f.find:SetPoint("TOPLEFT", f, "TOPLEFT", MINI_PAD, -(y + 2))
      f.find:SetSize(MINI_W - MINI_PAD * 2, 18)
      f.find:SetScript("OnClick", function() TJ:EnableFindTracking(key) end)
      tipOn(f.find, t.name, T("Щелчок включит поиск на миникарте."))
      f.find:Show()
      y = y + 24
    end
  end
  -- рыбалка: наживка
  if key == "fishing" then
    local lure, bonus = TJ:LureHint(rank)
    if lure then
      f.note:SetText(format(T("Наживи «%s» на удочку: +%d к ловле."), TJ:ItemName(lure), bonus))
      y = place(f.note, f, y)
    end
  end
  return y
end

-- Плавильня: «Плавить сейчас: Бронзовый слиток», руды хватит на N, «Создать N».
function Mini:ShowSmelt(f, key, sm, y)
  local T = TJ.T
  y = y or 30
  f.name:ClearAllPoints()
  f.name:SetPoint("TOPLEFT", f, "TOPLEFT", MINI_PAD, -y)
  f.name:SetWidth(MINI_W - MINI_PAD * 2)
  f.name:SetText(T("Плавить сейчас: ") .. TJ:Hex(sm.color) .. (sm.name or "?") .. "|r")
  f.name:Show()
  y = y + f.name:GetStringHeight() + 4
  f.nameBtn:SetAllPoints(f.name)
  f.nameBtn:SetScript("OnClick", function() TJ:OpenRecipe(key, sm.id) end)
  tipOn(f.nameBtn, sm.name or "", T("Плавка тоже растит горное дело. Щелчок выберет рецепт в окне профессии."))
  f.nameBtn:Show()
  f.status:SetText(sm.a > 0 and format(T("хватит на %d"), sm.a) or T("реагентов нет"))
  y = place(f.status, f, y)
  if sm.a > 0 then
    self:CreateBtn(f, key, sm.id, sm.a, y, T("Сделает, сколько хватит."))
    y = y + 30
  end
  f:SetHeight(y + 6)
  f:Show()
end

function Mini:Attach(key)
  self.key = key
  self:Create()
  self:Update()
  self:Watch(true)
end

function Mini:Detach()
  self.key = nil
  if self.f then self.f:Hide() end
  self:Watch(false)
end

-- Переключение вкладок справа (другая профессия, книга «Профессии»)
-- прячет и показывает окна игры без событий профессии. Пока подсказка
-- привязана, раз в 0,25 с сверяем: окно профессии видно и книга не открыта?
-- Если что-то поменялось - перерисовать (спрятать или показать снова).
function Mini:Watch(on)
  if not self.watch then
    self.watch = CreateFrame("Frame")
    local acc = 0
    self.watch:SetScript("OnUpdate", function(_, el)
      acc = acc + el
      if acc < 0.25 then return end
      acc = 0
      local f = Mini.f
      if not (f and Mini.key) then return end
      local a = ProfWindow(Mini.key)
      local want = a ~= nil and not BookShown() and TJ:IsProfOpen(Mini.key)
      if want ~= f:IsShown() or (want and a ~= Mini.anchor) then Mini:Update() end
    end)
  end
  self.watch:SetShown(on and true or false)
end

function Mini:Init() end

TJ:RegisterRefresh(function() Mini:Update() end)

