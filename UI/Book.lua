local _, TJ = ...
local W, C, T = TJ.W, TJ.Content, TJ.T
local format, min = string.format, math.min

-------------------------------------------------------------------------------
--  Вкладка «Рецепты» главной: очередь крафта, откаты по персонажам и книга
--  рецептов каждой профессии. Всё из тех же карточек, что и остальное окно:
--  шапка Card:Head, строки-кнопки Card:Items, строки списка Card:Row.
--  Порядок в книге и в очереди - по выгоде на аукционе (TJ.ByProfit).
--  Фильтр сверху: всё или лучшее для подземелий, рейдов, PvP (Data\Best.lua),
--  по желанию - только для своего класса.
-------------------------------------------------------------------------------
local GREEN, RED, GREY, GOLD = "|cff33dd33", "|cffff5555", "|cff9d9d9d", "|cffffd100"
local MAP_ICON, SCROLL_ICON = "Interface\\Icons\\INV_Misc_Map_01", "Interface\\Icons\\INV_Scroll_03"
local SHOWN = 10 -- строк в списке, пока не нажали «Показать все»

local function profitText(p)
  if not p then return GREY .. T("нет цены") .. "|r" end
  if p >= 0 then return GREEN .. "+" .. W.Money(p) .. "|r" end
  return RED .. "-" .. W.Money(-p) .. "|r"
end

-- «подземелья, рейды» по меткам записи.
local MODES = { { "d", "Подземелья" }, { "r", "Рейды" }, { "p", "PvP" } }
local function bestWhere(e)
  local parts = {}
  for _, m in ipairs(MODES) do
    if e.best:find(m[1], 1, true) then parts[#parts + 1] = T(m[2]) end
  end
  return table.concat(parts, ", ")
end

-- «Воин, Паладин» или «всем классам».
local function bestWho(e)
  if not e.classes then return T("всем классам") end
  local names = LOCALIZED_CLASS_NAMES_MALE or {}
  local parts = {}
  for _, c in ipairs(e.classes) do parts[#parts + 1] = names[c] or c end
  return table.concat(parts, ", ")
end

local function bestLine(e)
  return GOLD .. T("Лучшее: ") .. bestWhere(e) .. "|r " .. GREY .. "(" .. bestWho(e) .. ")|r"
end

local function nameText(e)
  local col = e.d and TJ.COLOR_BY_D[e.d]
  return col and (TJ:Hex(col) .. (e.name or "?") .. "|r") or (e.name or "?")
end

local function priceLines(e)
  local lines = {}
  if e.cost then lines[#lines + 1] = { T("Реагенты"), W.Money(e.cost) } end
  if e.sale then lines[#lines + 1] = { T("Продажа") .. ((e.q or 1) > 1 and format(" (%d)", e.q) or ""), W.Money(e.sale) } end
  if e.profit then
    lines[#lines + 1] = { T("Выгода за создание"), profitText(e.profit) }
    lines[#lines + 1] = T("Без комиссии аукциона.")
  else
    lines[#lines + 1] = TJ:PriceSource() and T("Цены на аукционе пока нет") or T("Цен нет: открой аукцион - EasyCraft прочитает их сам")
  end
  if e.best then
    lines[#lines + 1] = { T("Лучшее: ") .. bestWhere(e), color = W.GOLD }
    lines[#lines + 1] = T("Кому: ") .. bestWho(e)
  end
  return lines
end

local function chatLink(id)
  local _, link = ((C_Item and C_Item.GetItemInfo) or GetItemInfo)(id)
  W.InsertLink(link)
end

-------------------------------------------------------------------------------
--  Фильтр
-------------------------------------------------------------------------------
function C:BookFilter(UI)
  local c = UI:Card("flat")
  local function pick(mode) return function() UI.bookMode = mode; UI:Render(true) end end
  local list = { { text = T("Все рецепты"), w = 130, enabled = UI.bookMode ~= nil, onClick = pick(nil),
    tip = T("Все рецепты твоих профессий по выгоде на аукционе.") } }
  for _, m in ipairs(MODES) do
    list[#list + 1] = { text = T(m[2]), w = 120, enabled = UI.bookMode ~= m[1], onClick = pick(m[1]),
      tip = T("Только то, что считается лучшим для этого занятия.") }
  end
  c.indent = 10
  c:Buttons(list)
  c.indent = nil
  if UI.bookMode then
    c:Check(T("Только для моего класса"), UI.bookMine, function(v) UI.bookMine = v; UI:Render(true) end,
      T("Скрыть то, что нужно другим классам. Сделать на продажу можно и это - сними галочку."))
  end
  UI:End(c, 6)
end

-------------------------------------------------------------------------------
--  Очередь крафта
-------------------------------------------------------------------------------
function C:QueueCard(UI)
  local q = TJ:QueueList()
  local c = UI:Card(#q > 0 and "current" or "normal")
  if #q == 0 then
    c:Head({ ring = "Interface\\Icons\\INV_Misc_Note_02" }, T("Очередь крафта"),
      { { T("Пусто. Щёлкни по рецепту ниже."), "small" } }, 32)
    UI:End(c)
    return
  end
  local needs = TJ:QueueNeeds(q)
  local total, priced = 0, false
  for _, e in ipairs(q) do
    if e.profit then total, priced = total + e.profit * e.n, true end
  end
  c:Head({ ring = "Interface\\Icons\\INV_Misc_Note_02" }, T("Очередь крафта"),
    { { T("Сверху - самое выгодное по ценам аукциона.") .. (priced and (" " .. T("Выгода всей очереди: ") .. profitText(total)) or ""), "small" } }, 32)
  local nextUp = TJ:QueueNext(q)
  local rows = {}
  for _, e in ipairs(q) do
    local p = TJ.Profs[e.key]
    local state = not e.known and (RED .. T("рецепт не выучен") .. "|r")
      or (e.can > 0 and (GREEN .. format(T("хватит на %d"), e.can) .. "|r") or (GREY .. T("нет реагентов") .. "|r"))
    local lines = priceLines(e)
    rows[#rows + 1] = { id = e.out, tex = e.icon, text = format("%d × %s", e.n, nameText(e)),
      sub = TJ:N(p) .. ", " .. state, right = profitText(e.profit and e.profit * e.n),
      star = e == nextUp, hot = e == nextUp,
      tip = { title = e.name or "?", lines = lines, hint = T("Щелчок - создать. Крестик справа уберёт из очереди.") },
      onClick = function() TJ:QueueCraft(e) end,
      onDelete = function()
        TJ:QueueRemove(e.spell)
        UI:Render(true)
      end }
  end
  c:Items(rows, 1, 28)
  if needs.buyCount > 0 then
    c:Text(T("Докупить на аукционе: ") .. (needs.total > 0 and W.Money(needs.total) or "-")
      .. (needs.noPrice > 0 and ("  " .. GREY .. format(T("(и ещё %d без цены)"), needs.noPrice) .. "|r") or ""), "body", { color = W.LIGHT })
  else
    c:Text(GREEN .. T("Реагентов хватает на всю очередь.") .. "|r", "body")
  end
  local has, open = TJ:HasAuctionator(), TJ:IsAuctionOpen()
  c:Buttons({
    { text = T("Создать следующий"), w = 170, enabled = nextUp ~= nil,
      tip = nextUp and format(T("Создаст «%s»: %d шт."), nextUp.name or "?", min(nextUp.n, nextUp.can))
        or T("Ни на один рецепт очереди нет реагентов."),
      onClick = function() if nextUp then TJ:QueueCraft(nextUp) end end },
    { text = open and T("Найти на аукционе") or T("В список Auctionator"), w = 190, enabled = has and #needs.auction > 0,
      tip = has and (open and T("Найдёт недостающие реагенты на аукционе.")
        or T("Добавит недостающие реагенты в список «EasyCraft» в Auctionator: на аукционе останется нажать «Искать»."))
        or T("Нужен аддон Auctionator: через него EasyCraft ищет сразу весь список."),
      onClick = function() TJ:SendToAuction(needs.auction) end },
    { text = T("Очистить"), w = 110, onClick = function() TJ:QueueClear(); UI:Render(true) end,
      tip = T("Уберёт из очереди всё.") },
  })
  UI:End(c)
end

-------------------------------------------------------------------------------
--  Откаты по персонажам
-------------------------------------------------------------------------------
function C:CooldownCard(UI)
  local list = TJ:CooldownList()
  local c = UI:Card()
  c:Head({ ring = "Interface\\Icons\\INV_Misc_PocketWatch_01" }, T("Откаты по персонажам"),
    { { #list == 0 and T("Пусто. Создай предмет с откатом - аддон его запомнит.")
      or T("Что уже можно создавать снова и сколько ждать остальное."), "small" } }, 32)
  for _, e in ipairs(list) do
    local who = e.who:match("^[^-]+") or e.who
    c:Row({ tex = e.icon, text = (e.name or "?") .. "  " .. GREY .. who .. "|r",
      right = e.left == 0 and (GREEN .. T("готово") .. "|r") or TJ:TimeLeft(e.left),
      state = e.mine and e.left == 0 and "current" or nil,
      onDelete = function()
        TJ:ForgetCooldown(e.who, e.spell)
        UI:Render(true)
      end })
  end
  UI:End(c)
end

-------------------------------------------------------------------------------
--  Книга рецептов профессии
-------------------------------------------------------------------------------
-- Строка выученного рецепта: щелчок - в очередь.
local function knownRow(UI, key, e, first)
  local sub
  if e.cost and e.sale then sub = format(T("Реагенты %s, продажа %s"), W.Money(e.cost), W.Money(e.sale))
  elseif e.cost then sub = format(T("Реагенты %s"), W.Money(e.cost))
  else sub = GREY .. T("Цены на аукционе пока нет") .. "|r" end
  if e.can > 0 then sub = sub .. ", " .. GREEN .. format(T("хватит на %d"), e.can) .. "|r" end
  if e.best then sub = bestLine(e) end
  local hot = first and e.profit ~= nil and e.profit > 0
  return { id = e.out, tex = e.icon, text = nameText(e), sub = sub, right = profitText(e.profit), star = hot, hot = hot,
    tip = { title = e.name or "?", lines = priceLines(e),
      hint = e.out and T("Щелчок добавит в очередь. Shift+щелчок - ссылка в чат.") or T("Щелчок откроет его в окне профессии.") },
    onClick = function()
      if e.out and IsModifiedClick and IsModifiedClick("CHATLINK") then
        chatLink(e.out)
      elseif e.out then
        TJ:QueueAdd(key, e.spell, 1)
        UI:Render(true)
      else
        TJ:OpenRecipe(key, e.spell) -- чары: накладываются из окна профессии
      end
    end }
end

-- Строка невыученного рецепта: где его взять, щелчок - метка на карте.
local function unknownRow(key, e)
  local s = e.step
  local src = s and TJ:RecipeSource(key, s)
  local npc = src and src.npc
  local sub, right, icons
  if npc then
    local vendor = src.kind == "vendor"
    sub = (vendor and T("Торговец: ") or T("Учитель: ")) .. TJ:NpcName(npc) .. ", " .. TJ:NpcZone(npc)
    right = vendor and (src.copper and W.Money(src.copper) or src.price) or nil
    icons = { MAP_ICON, vendor and src.item and TJ:ItemIcon(src.item) or SCROLL_ICON }
  elseif src and src.info and src.info ~= "" then
    sub = src.info
  else
    sub = GREY .. T("Где взять рецепт, аддон пока не знает.") .. "|r"
  end
  if s and s.f then sub = sub .. GREY .. ", " .. format(T("С %d навыка"), s.f) .. "|r" end
  local lines = priceLines(e)
  return { id = e.out, tex = e.icon, text = e.name or "?", sub = sub,
    right = (right and (right .. "  ") or "") .. (e.profit and profitText(e.profit) or ""), icons = icons,
    star = e.best ~= nil,
    tip = { title = e.name or "?", lines = lines, hint = npc and T("Щелчок поставит метку и откроет карту.") or nil },
    onClick = function()
      if npc then
        TJ:Waypoint(npc, true)
      elseif e.out and IsModifiedClick and IsModifiedClick("CHATLINK") then
        chatLink(e.out)
      end
    end }
end

function C:BookCard(UI, key, known, unknown, scanned)
  local p = TJ.Profs[key]
  local PAD = UI.PAD
  UI.bookAll = UI.bookAll or {}
  local all = UI.bookAll[key]
  local c = UI:Card()
  local y0 = c.y
  if not scanned then
    c.headRight = c:CornerButtons({ { text = T("Окно профессии"), w = 150, onClick = function() TJ:OpenProfession(key) end } }, y0 + 6)
  end
  c:Head({ ring = TJ.Icon(p.icon) }, TJ:N(p),
    { { scanned and format(T("Выучено рецептов: %d. Сверху - самые выгодные."), #known)
      or T("Открой окно профессии - аддон прочитает рецепты."), "small" } }, 32)
  local rows = {}
  for i, e in ipairs(known) do
    if not all and i > SHOWN then break end
    rows[#rows + 1] = knownRow(UI, key, e, i == 1)
  end
  c:Items(rows, 1, 28)
  if #unknown > 0 then
    c:Space(2)
    c:Text(T("Ещё не выучены"), "head", { gap = 6 })
    rows = {}
    for i, e in ipairs(unknown) do
      if not all and i > SHOWN then break end
      rows[#rows + 1] = unknownRow(key, e)
    end
    c:Items(rows, 1, 28)
  end
  if #known > SHOWN or #unknown > SHOWN then
    c:Buttons({ { text = all and T("Свернуть") or format(T("Показать все (%d)"), #known + #unknown), w = 190,
      onClick = function() UI.bookAll[key] = not all; UI:Render(true) end } })
  end
  UI:End(c)
end

function C:BuildBook(UI)
  self:BookFilter(UI)
  local mode, mine = UI.bookMode, UI.bookMine
  if not mode then
    self:QueueCard(UI)
    self:CooldownCard(UI)
  end
  local shown = 0
  for _, key in ipairs(TJ:LearnedList()) do
    local known, unknown, scanned = TJ:BookList(key)
    if mode then
      local k2, u2 = {}, {}
      for _, e in ipairs(known) do if TJ:IsBest(e, mode, mine) then k2[#k2 + 1] = e end end
      for _, e in ipairs(unknown) do if TJ:IsBest(e, mode, mine) then u2[#u2 + 1] = e end end
      known, unknown = k2, u2
    end
    if #known + #unknown > 0 then
      shown = shown + 1
      self:BookCard(UI, key, known, unknown, scanned)
    end
  end
  if shown == 0 then
    local c = UI:Card()
    c:Text(mode and T("Среди рецептов твоих профессий такого нет.") or T("У твоих профессий нет рецептов создания."), "body")
    UI:End(c)
  end
end
