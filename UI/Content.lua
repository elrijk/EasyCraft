local ADDON, ns = ...
local W = ns.W
local C = {}
ns.Content = C
local T = ns.T
local format, floor, ceil, max, min = string.format, math.floor, math.ceil, math.max, math.min

-------------------------------------------------------------------------------
--  Что показывает окно EasyCraft.
--  Главная: Профессии (текущий шаг и цель каждой изученной), Карта (что
--  показывать на карте мира и свои точки), Лагерь.
--  Профессия: шапка прямо на пергаменте, текущий шаг (цель, реагенты, кнопки
--  создания, цены), ниже ранги.
-------------------------------------------------------------------------------
local GREEN, RED, YELLOW, ORANGE = "|cff33dd33", "|cffff5555", "|cffffd100", "|cffff9933"

local RANKS = {
  { 1, 75, "Ученик (1-75)" }, { 75, 150, "Подмастерье (75-150)" },
  { 150, 225, "Умелец (150-225)" }, { 225, 300, "Искусник (225-300)" },
}

local function stepRank(s)
  local v = s.f or (s.at and s.at + 0.5) or 1
  if v < 75 then return 1 elseif v < 150 then return 2 elseif v < 225 then return 3 end
  return 4
end

-- Порядок шагов, как они показаны: по рангам, внутри ранга - как в данных.
local function routeOrder(p)
  if p._order then return p._order end
  local order = {}
  for b = 1, 4 do
    for i, s in ipairs(p.steps) do if stepRank(s) == b then tinsert(order, i) end end
  end
  local pos = {}
  for n, i in ipairs(order) do pos[i] = n end
  p._order, p._pos = order, pos
  return order, pos
end

local function isRankStep(s) return s.k == "train" or s.k == "book" or s.k == "quest" end

-- Номер шага на маршруте (как показан) и сколько всего: для мини-окна.
function C:StepPos(p, i)
  local order, pos = routeOrder(p)
  pos = pos or p._pos
  return pos[i], #order, order
end

local function colorCode(c)
  return format("|cff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255)
end

local function haveNeed(have, need)
  return format("%s%d/%d|r", have >= need and GREEN or RED, min(have, 9999), need)
end


-- Сколько стоит докупить buy штук на аукционе (медь) или nil; вторым -
-- возраст цены в днях (Auctionator), если она старая.
local function buyCost(id, buy)
  if ns:IsVendorItem(id) then return nil end
  local p, age = ns:AuctionPrice(id)
  if not p then return nil end
  return p * buy, (age and age >= ns.PRICE_OLD_DAYS) and age or nil
end

-- Возраст цены словами: «5 дн.» или «больше 3 нед.».
local function ageWord(age)
  if age > 21 then return T("3+ нед.") end
  return format(T("%d дн."), age)
end

-- Пометка старой цены: « · 5 дн.» серым.
local function ageText(age)
  return age and ("|cff9d9d9d, " .. T("цена ") .. ageWord(age) .. "|r") or ""
end

-- Подпись под реагентом: на почте, у альтов, сколько докупить и почём.
local function vendorMoney(id, buy, cost, approx)
  if not cost then
    local p
    p, approx = ns:VendorPrice(id)
    cost = p and p * buy
  end
  return cost and ((approx and "~" or "") .. W.Money(cost)) or nil
end

local function buyText(id, buy, cost, age, alts, mail, approx)
  local parts = {}
  if mail and mail > 0 then tinsert(parts, ns.MAIL_COLOR .. format(T("на почте %d"), mail) .. "|r") end
  if alts and alts > 0 then tinsert(parts, format(T("у альтов %d"), alts)) end
  local altPart = #parts > 0 and (table.concat(parts,  ", ") .. (buy > 0 and  ", " or "")) or ""
  if buy <= 0 then return altPart ~= "" and altPart or nil end
  if ns:IsVendorItem(id) then
    local money = vendorMoney(id, buy, cost, approx)
    return altPart .. format(T("купить %d у торговца"), buy) .. (money and (": " .. money) or "")
  end
  if cost then return altPart .. format(T("докупить %d: %s на аукционе"), buy, W.Money(cost)) .. ageText(age) end
  if ns:PriceSource() then return altPart .. format(T("докупить %d, цены на аукционе пока нет"), buy) end
  return altPart .. format(T("докупить %d"), buy)
end

-- «уровень», «уровня», «уровней» по числу.
local function levelWord(n)
  local n10, n100 = n % 10, n % 100
  if n10 == 1 and n100 ~= 11 then return T("уровень") end
  if n10 >= 2 and n10 <= 4 and (n100 < 12 or n100 > 14) then return T("уровня") end
  return T("уровней")
end

-- Навык отстал от уровня персонажа: «Отстаёшь на 15 уровней» и подсказка
-- (на каком уровне такой навык и до скольки поднять).
local function lagInfo(key)
  local lag = ns:Lag(key)
  if not lag then return nil end
  local n = max(1, lag.level - lag.skillLevel)
  local rank = ns:GetSkill(key)
  -- значок-предупреждение перед текстом (чуть выше: буквы сидят высоко)
  local text = "|TInterface\\DialogFrame\\UI-Dialog-Icon-AlertNew:15:15:0:1|t " .. ORANGE
    .. format(T("Отстаёшь на %d %s"), n, levelWord(n)) .. "|r"
  local tip = { title = T("Навык отстаёт от уровня"), lines = {
    format(T("Навык %d обычно бывает на %d уровне, а тебе %d."), rank, lag.skillLevel, lag.level),
    format(T("Чтобы догнать, подними навык до %d."), lag.expected) } }
  return text, tip
end

-- Уровни зоны цветом: красным, если зона заметно выше персонажа.
local function zoneLevels(area)
  local z = ns.Zones[area]
  if not (z and z.lo and z.hi) then return "" end
  local my = UnitLevel and UnitLevel("player") or 0
  local col = (z.lo > my + 3) and RED or "|cff9d9d9d"
  return " " .. col .. format("(%d-%d)", z.lo, z.hi) .. "|r"
end

-- Зона цветом и с уровнями - для мини-окна у профессии.
-- levelsFirst: «15-27  Когтистые горы» - уровни в начале, столбиком.
function C:ZoneText(area, levelsFirst)
  if levelsFirst then
    local z = ns.Zones[area]
    local lv = ""
    if z and z.lo and z.hi then
      local my = UnitLevel and UnitLevel("player") or 0
      lv = ((z.lo > my + 3) and RED or "|cff9d9d9d") .. format("%d-%d", z.lo, z.hi) .. "|r  "
    end
    return lv .. ns:ZoneColor(area) .. ns:ZoneName(area) .. "|r"
  end
  return ns:ZoneColor(area) .. ns:ZoneName(area) .. "|r" .. zoneLevels(area)
end

-- Показать зону на карте с областями нужного. Тот же щелчок ещё раз (карта
-- открыта на этой зоне) - убрать подсветку.
function C:ShowOnMap(area, nodeKeys)
  local z = ns.Zones[area]
  local ui = z and (z.uiMap or z.ui)
  local map = WorldMapFrame
  if ns.mapFocus and ns.mapFocusArea == area and map and map:IsShown() then
    ns.mapFocus, ns.mapFocusArea = nil, nil
    if ns.MapOverlay then ns.MapOverlay:Refresh() end
    return
  end
  ns.mapFocus = nodeKeys and #nodeKeys > 0 and nodeKeys or nil
  ns.mapFocusArea = ns.mapFocus and area or nil
  ns.settings.mapShow = true -- просили показать - включаем, даже если выключали
  if ns.MapOverlay then ns.MapOverlay:OpenMap(ui) end
end

-- Название шага с цветом рецепта (как в окне профессии).
local function stepColor(s, rank, state)
  if state == "done" then return W.GREY end
  if s.k == "craft" and s.sk and state == "current" then
    local col = ns:RecipeColor(s, rank)
    return col and ns.ColorRGB[col] or W.LIGHT
  end
  return W.LIGHT
end

-- Что осталось по шагу, одной короткой фразой.
function C:Left(s, rank, state)
  if state == "done" then return GREEN .. T("Шаг выполнен.") .. "|r" end
  if s.k == "craft" then
    -- сколько делать, видно по реагентам («79/11»), отдельной строки не нужно
    return nil
  elseif s.k == "gather" or s.k == "zone" then
    if state == "current" then return YELLOW .. T("Осталось поднять навык: ") .. "|r" .. format("%d", max(s.t - rank, 0)) end
    return YELLOW .. T("Поднять навык: ") .. "|r" .. format("%d", s.t - s.f)
  end
end

-- Черты следующего ранга на полосе навыка нет: когда учить ранг,
-- показывают значок книги у профессии и цели в рангах.
function ns:MarkNextRank(bar)
  W.SetBarMark(bar, nil)
end

-- Полоса навыка до предела текущего ранга: «87 из 150».
local function rankBar(c, rank, maxRank, key)
  local cap = (maxRank and maxRank > 0) and maxRank or 300
  local bar = c:Bar(rank, cap, format(T("%d из %d"), rank, cap))
  if key then ns:MarkNextRank(bar, key, rank, cap) else W.SetBarMark(bar, nil) end
end

-- Можно ли уже учить ранг и что мешает.
local function rankStatus(s, rank)
  local learn = s.learn or s.at
  local lvl = s.lvl
  local myLvl = UnitLevel and UnitLevel("player") or 0
  local lvlText = lvl and format(T(" и %d уровня"), lvl) or ""
  if rank >= s.at then
    -- кто нужен - по виду шага: учитель, торговец книгой, задание
    local who = s.k == "book" and T("Навык упёрся в %d: купи книгу у торговца.")
      or (s.k == "quest" and T("Навык упёрся в %d: возьми задание на новый ранг.") or T("Навык упёрся в %d: пора к учителю."))
    return RED .. format(who, s.at) .. "|r"
  elseif rank >= learn and (not lvl or myLvl >= lvl) then
    return YELLOW .. T("Уже можно выучить.") .. "|r"
  end
  return format(T("Можно выучить с %d навыка%s."), learn, lvlText)
end

-- Одна строка о том, что осталось по шагу (для мини-окна у верстака).
function ns:ShortStatus(key, s, rank, state)
  if state == "done" then return GREEN .. T("Шаг выполнен.") .. "|r" end
  if isRankStep(s) then return rankStatus(s, rank) end
  if s.k == "craft" then
    local left = self:RemainingCrafts(s, rank)
    if left > 0 then return format(T("Сделать ещё ~%d шт., до навыка %d"), left, s.t) end
    return nil
  end
  return C:Left(s, rank, state)
end

local function missingTools(c, key, rank)
  local missing = ns:MissingTools(key, rank)
  if #missing == 0 then return end
  local names = {}
  for _, id in ipairs(missing) do tinsert(names, ns:ItemName(id)) end
  c:Text(RED .. T("Нет в сумках: ") .. "|r" .. table.concat(names, ", "), "body")
end

-- Подсказки в поле для текущего шага: поиск руды или трав, что плавить,
-- наживка на удочке. Каждая - одна строка, и только когда она к делу.
local function fieldHints(c, key, s, rank)
  if s.k == "gather" then
    -- в классике поиск один на всё: если включён любой (руда или травы), не просим
    local t = ns:FindTracking(key)
    if t and not t.active and not ns:AnyFindActive() then
      c:Items({ { tex = t.icon or ns.Icon(nil), text = format(T("Включи «%s»"), t.name),
        tip = T("Щелчок включит поиск на миникарте."), onClick = function() ns:EnableFindTracking(key) end } }, 1, 26)
    end
  end
  if key == "mining" and s.k == "gather" then
    -- одна строка; цвет и сколько хватит - в мини-окне у плавильни
    local sm = ns:SmeltNow(rank)
    if sm then c:Text(T("Плавить сейчас: ") .. (sm.name or "?") .. T(" - это тоже растит навык."), "small", { gap = 6 }) end
  end
  if key == "fishing" then
    local lure, bonus = ns:LureHint(rank)
    if lure then
      c:Text(YELLOW .. format(T("Наживи «%s» на удочку: +%d к ловле."), ns:ItemName(lure), bonus) .. "|r", "small", { gap = 6 })
    end
  end
end

-- NPC строками, как в подсказке у окна профессии: слева значок карты,
-- имя и зона, справа - что у него взять (книга, рецепт, свиток учителя).
-- Ближайший - со звездой и в золотой рамке. Щелчок - метка и карта.
local MAP_ICON, SCROLL_ICON = "Interface\\Icons\\INV_Misc_Map_01", "Interface\\Icons\\INV_Scroll_03"
local function npcItems(npcs, limit, what, right)
  local items = {}
  local list, sorted = ns:NpcsFor(npcs, limit or 4)
  for k, id in ipairs(list) do
    -- «ближайший» и звезда - только когда знаем, где игрок (не в подземелье)
    local near = k == 1 and sorted
    tinsert(items, { tex = MAP_ICON, text = ns:NpcName(id), sub = ns:NpcZone(id) .. (near and (", " .. T("ближайший")) or ""),
      icons = { what or SCROLL_ICON }, right = k == 1 and right or nil, star = near, hot = near,
      tip = { title = ns:NpcName(id), lines = { ns:NpcZone(id) }, hint = T("Щелчок поставит метку и откроет карту.") },
      onClick = function() ns:Waypoint(id, true) end })
  end
  return items
end

-------------------------------------------------------------------------------
--  Плитки шагов: одна система на странице профессии (ранги) и на главной.
--  На плитке - навык (ромб), значок, сколько ещё создать (число в углу),
--  название и строка «что нужно»; всё остальное - в подсказке.
-------------------------------------------------------------------------------
local MONEY_ICON = "Interface\\Icons\\INV_Misc_Coin_01"
local TRAIN_ICON = "Interface\\Icons\\INV_Misc_Book_11"
local QUEST_ICON = "Interface\\Icons\\INV_Misc_Note_06"
local GREY_C = "|cff9d9d9d"

-- Значок предмета в строке текста.
local function itemTag(id, size)
  return format("|T%s:%d:%d:0:0:64:64:5:59:5:59|t", tostring(ns:ItemIcon(id) or 134400), size or 14, size or 14)
end

-- Сколько всего докупить (штук) по итогу StepBuy.
local function buyCount(b)
  local n = 0
  for _, e in ipairs(b.items) do n = n + (e.buy or 0) end
  return n
end

-- Где лежит то, что не в сумках (банк, почта, альты) - одним словом.
local function fetchWord(b)
  if b.bank then return T("в банке") end
  if b.mail then return T("на почте") end
  return T("у альтов")
end

-- Ранг коротко, для плитки и строки профессии: «пора к учителю»,
-- «уже можно», «с 125 навыка, 20 ур.».
local function rankShort(s, rank, short)
  if rank >= s.at then
    if s.k == "book" then return RED .. T("купи книгу") .. "|r" end
    if s.k == "quest" then return RED .. T("возьми задание") .. "|r" end
    return RED .. T("пора к учителю") .. "|r"
  end
  if ns:CanLearnRank(s, rank) then return YELLOW .. T("уже можно") .. "|r" end
  -- на плитке коротко: навык и так в ромбе над ней
  local t = short and format("%d", s.learn or s.at) or format(T("с %d навыка"), s.learn or s.at)
  if short then return s.lvl and format(T("с %s, %d ур."), t, s.lvl) or format(T("с %s"), t) end
  if s.lvl then t = t .. ", " .. format(T("%d ур."), s.lvl) end
  return t
end

-- Строка «что нужно» внизу плитки.
local function tileFoot(key, s, st, rank, isCur, b, cost)
  if st == "done" then
    if isRankStep(s) then return GREEN .. T("выучено") .. "|r" end
    return GREEN .. T("выполнено") .. "|r"
  end
  if isRankStep(s) then
    if s.k == "book" and s.id and rank < s.at and not ns:CanLearnRank(s, rank) then
      local price, approx = ns:VendorPrice(s.id)
      if price then return (approx and "~" or "") .. W.Money(price) end
    end
    return rankShort(s, rank, true)
  end
  if s.k == "craft" then
    if isCur and s.spell and ns:RecipeKnown(key, s.spell) == false then return ORANGE .. T("выучи рецепт") .. "|r" end
    if b and #b.items > 0 then
      if b.allHave then return GREEN .. T("всё есть") .. "|r" end
      if buyCount(b) == 0 then return YELLOW .. fetchWord(b) .. "|r" end
      if cost > 0 then return (b.vendorApprox and "~" or "") .. W.Money(cost) end
      return RED .. T("не хватает") .. "|r"
    end
  end
  return GREY_C .. format("%d-%d", s.f, s.t) .. "|r"
end

-- Подсказка плитки: что за шаг, сколько осталось, реагенты (есть/нужно),
-- что докупить, где учить или собирать.
local function stepTip(key, s, st, rank, isCur, b, cost, hint)
  local lines = {}
  local title = ns:StepName(s)
  local color = isCur and W.GOLD or (st == "done" and W.GREEN or W.LIGHT)
  if isRankStep(s) then
    tinsert(lines, { format(T("Предел навыка станет %d"), s.max), color = W.GREY })
    if st == "done" then
      tinsert(lines, GREEN .. T("Ранг выучен.") .. "|r")
    else
      tinsert(lines, rankStatus(s, rank))
      local npc = s.npcs and ns:NpcsFor(s.npcs, 1)[1]
      if npc then
        local who = s.k == "book" and T("Торговец:") or (s.k == "quest" and T("Задание:") or T("Учитель:"))
        tinsert(lines, { who .. " " .. ns:NpcName(npc), ns:NpcZone(npc) })
      end
      if s.k == "book" and s.id then
        local price, approx = ns:VendorPrice(s.id)
        if price then tinsert(lines, { T("Книга стоит"), (approx and "~" or "") .. W.Money(price) }) end
      end
    end
  else
    tinsert(lines, { format(T("Навык %d-%d"), s.f, s.t), color = W.GREY })
    if st == "done" then
      tinsert(lines, GREEN .. T("Шаг выполнен.") .. "|r")
    elseif s.k == "craft" then
      local left = ns:RemainingCrafts(s, rank)
      if left > 0 then tinsert(lines, { T("Сделать ещё"), "|cffffffff" .. left .. "|r" }) end
      if isCur and s.spell and ns:RecipeKnown(key, s.spell) == false then
        tinsert(lines, ORANGE .. ns:RecipeSourceHead(ns:RecipeSource(key, s)) .. "|r")
      end
      if b then
        for _, e in ipairs(b.items) do
          -- «есть» - то, что досталось этому шагу (раньше по маршруту могли забрать)
          tinsert(lines, { itemTag(e.id) .. " " .. ns:ItemName(e.id), haveNeed(min(e.have, e.stock or e.have), e.need) })
        end
        if not b.allHave then
          if buyCount(b) == 0 then
            tinsert(lines, YELLOW .. T("Остальное - ") .. fetchWord(b) .. "|r")
          elseif cost > 0 then
            tinsert(lines, { T("Докупить на"), (b.vendorApprox and "~" or "") .. W.Money(cost) })
          end
          if b.noPrice > 0 then tinsert(lines, GREY_C .. format(T("Без цены: %d"), b.noPrice) .. "|r") end
        end
      end
    elseif s.k == "gather" then
      for _, nk in ipairs(s.nodes or {}) do
        local n = ns.Nodes[nk]
        if n then tinsert(lines, { itemTag(n.item) .. " " .. ns:N(n), format(T("с %d"), n.req) }) end
      end
      local z = ns:StepGatherZones(s, rank, 1)[1]
      if z then tinsert(lines, { T("Где лучше:"), ns:ZoneColor(z.area) .. ns:ZoneName(z.area) .. "|r" }) end
    elseif s.k == "zone" and s.areas and s.areas[1] then
      tinsert(lines, { T("Где ловить:"), ns:ZoneColor(s.areas[1]) .. ns:ZoneName(s.areas[1]) .. "|r" })
    end
  end
  if hint and (s.id or s.k == "gather") and not isRankStep(s) then hint = hint .. " " .. T("Shift - ссылка на предмет.") end
  return { title = title, color = color, lines = lines, hint = hint }
end

-- Плитка шага i профессии key. pool - общий запас реагентов (шаги по
-- порядку: что ушло одному, другому не достанется). opts.hint, opts.onClick.
local function stepTile(key, p, i, rank, maxRank, cur, sel, pool, opts)
  local s = p.steps[i]
  local st = ns:StepState(key, i, rank, maxRank)
  local isCur = i == cur
  local b, cost
  local left = (s.k == "craft" and st ~= "done") and ns:RemainingCrafts(s, rank) or 0
  if left > 0 and (s.rc or s.m) then
    b = ns:StepBuy(s, left, pool)
    cost = b.total + b.vendorCost
  end
  local icon = s.id or (s.k == "gather" and s.nodes and s.nodes[1] and ns.Nodes[s.nodes[1]].item) or nil
  local tex
  if not icon then
    tex = ns:StepIcon(s, p)
    if s.k == "quest" then tex = QUEST_ICON end
  end
  return {
    item = icon, tex = tex,
    badge = tostring(isRankStep(s) and (s.learn or s.at) or s.t),
    count = left > 0 and left or nil,
    text = ns:StepName(s) .. (s.approx and (ORANGE .. " ~|r") or ""),
    foot = tileFoot(key, s, st, rank, isCur, b, cost),
    state = st, cur = isCur, sel = sel == i and i ~= cur,
    -- подсказку считаем при наведении: зоны сбора и NPC искать дорого
    tip = function() return stepTip(key, s, st, rank, isCur, b, cost, opts and opts.hint) end,
    onClick = opts and opts.onClick,
  }, st, b, cost
end

-------------------------------------------------------------------------------
--  Вкладки
-------------------------------------------------------------------------------
-- { название, значок, подсказка, режим, номер страницы }. Номера страниц
-- постоянные (по ним HOW, BuildHome и переходы): 2 была «Карта», её
-- настройки теперь в настройках аддона.
function C:HomeTabs()
  return {
    { T("Профессии"), "Interface\\Icons\\INV_Misc_Book_11", nil, nil, 1 },
    { T("Лагерь"), "Interface\\Icons\\Spell_Fire_Fire", nil, nil, 3 },
    { T("Покупки"), "Interface\\Icons\\INV_Misc_Coin_02", nil, nil, 4 },
    { T("Рецепты"), "Interface\\Icons\\INV_Scroll_03", nil, nil, 5 },
  }
end

-- У страницы профессии вкладок нет: режим маршрута выбирают на главной
-- (RouteModeCard).
function C:ProfTabs(key)
  return {}
end

-- «Путь прокачки»: крупный переключатель режима маршрута на главной. Один
-- на все профессии; показывается, если хоть у одной изученной есть выбор.
local MODE_ICON = { guide = "INV_Misc_Book_09", cheap = "INV_Misc_Coin_02", fast = "Ability_Rogue_Sprint" }
function C:RouteModeCard(UI)
  if not ns.HasRouteModes then return end
  local any, waiting = false, false
  local mode = ns:RouteMode()
  for _, key in ipairs(ns:LearnedList()) do
    if ns:HasRouteModes(key) then
      any = true
      -- режиму не хватило цен: у профессии пока обычный маршрут
      if mode ~= "guide" and ns.Profs[key].routeMode ~= mode then waiting = true end
    end
  end
  if not any then return end
  local c = UI:Card("normal")
  c:Head({ ring = "Interface\\Icons\\INV_Misc_Map_01" }, T("Путь прокачки"),
    { { T("Как идти до 300. Выбери один раз - действует на все профессии."), "small" } }, 32)
  c:Space(4)
  local tiles = {}
  for _, md in ipairs(ns.ROUTE_MODES) do
    tiles[#tiles + 1] = { text = T(ns.ROUTE_MODE_NAME[md]), icon = MODE_ICON[md], tip = T(ns.ROUTE_MODE_TIP[md]), sel = md == mode,
      onClick = function()
        if md == ns:RouteMode() then return end
        ns:SetRouteMode(md)
        UI:Render(true)
      end }
  end
  c:HeadTiles(tiles, { equal = true, h = 54 })
  -- что значит выбранный режим - словами под переключателем
  c:Text(T(ns.ROUTE_MODE_TIP[mode]), "body", { gap = 2 })
  if waiting then
    c:Text(YELLOW .. T("Для этого режима нужны цены: открой аукцион. Пока показан обычный маршрут.") .. "|r", "small", { gap = 4 })
  end
  UI:End(c, 10)
end

-- Гайды вкладок снова (кнопка «?», настройки, /ec помощь): показать на
-- главной и прокрутить к началу.
-- ns:ShowIntro() - в UI/Intro.lua: знакомство отдельным окном.

-- Свёрнутый блок-подсказка: строка с «+», щелчок раскрывает.
local function foldHead(c, title, open, onToggle)
  c:Section(title, nil, false, not open, onToggle)
end

-- Шапки вкладок главной, как у страниц MacroCoach: заголовок - главная
-- мысль, строка пояснения, кнопки «куда дальше».
local HOW = {
  { title = "Профессия до 300 - шаг за шагом",
    text = "Делай текущий шаг: аддон сам засчитает его по навыку и покажет следующий. Без гайдов и подсчётов." },
  { title = "Карта: где собирать",
    text = "Руда и травы, которые сейчас дают навык, - прямо на карте мира." },
  { title = "Лагерь: бонусы у костра",
    text = "Костёр и предметы твоих профессий рядом с ним дают бонусы всем, кто в лагере." },
  { title = "Покупки до учителя",
    text = "Чего не хватает до следующего учителя по всем профессиям. Что уже есть, не считается." },
  { title = "Рецепты: что выгодно создавать",
    text = "Все твои рецепты по выгоде на аукционе, очередь крафта, откаты персонажей и лучшее для подземелий, рейдов и PvP." },
}

-- Короткий гайд своей вкладки: что здесь делать, по шагам. Значок, что
-- сделать (золотом) и строка пояснения. Скрывается кнопкой у каждой
-- вкладки отдельно, вернуть - «?» в заголовке окна.
local GUIDE = {
  { -- Профессии
    { "INV_Misc_Book_11", "Смотри текущий шаг", "Вверху карточки профессии: что создать и сколько. Щелчок - все шаги подробно." },
    { "Trade_BlackSmithing", "Создавай у окна профессии", "Рядом с ним мини-окно: рецепт шага и кнопка создания." },
    { "INV_Misc_Bag_08", "Докупи, чего не хватает", "Список - во вкладке «Покупки». Сумки, банк и почта уже учтены." },
    { "INV_Misc_Book_09", "Учи новый ранг вовремя", "На 75, 150 и 225 нужен учитель: аддон напомнит и поставит метку." },
  },
  { -- Карта
    { "INV_Misc_Map_01", "Открой карту мира", "На ней руда и травы, которые сейчас дают навык." },
    { "INV_Ore_Copper_01", "Собирай, что даёт навык", "Цвет как у рецептов: оранжевое и жёлтое растят навык, серое - уже нет." },
    { "INV_Misc_Note_01", "Иди в зону своей фракции", "Лучшие зоны для Орды и для Альянса - в шаге сбора профессии." },
  },
  { -- Лагерь
    { "Spell_Fire_Fire", "Поставь костёр", "Набор для костра учит учитель кулинарии. Костёр больше - места больше: 3, 5, 10 предметов." },
    { "INV_Scroll_03", "Найди чертёж", "Чертежи падают в подземельях: кнопка у предмета поставит метку у входа." },
    { "INV_Misc_Gear_01", "Создай предмет и поставь у костра", "Бонус получат все, кто в лагере. Нужный навык - в описании предмета." },
  },
  { -- Покупки
    { "INV_Misc_Bag_08", "Что есть - уже посчитано", "Сумки, банк, почта и альты учтены: в списке только то, чего не хватает до учителя." },
    { "INV_Misc_Coin_02", "Цена и где купить", "У каждого реагента: у торговца или на аукционе и почём." },
    { "INV_Misc_Note_02", "Остальное - на аукционе", "Кнопка вверху отправит список в Auctionator, у аукциона - найдёт всё сразу." },
  },
  { -- Рецепты
    { "Trade_BlackSmithing", "Открой окно профессии", "Аддон прочитает все выученные рецепты, что из них выходит и какие на откате." },
    { "INV_Misc_Coin_02", "Смотри выгоду", "Справа у рецепта - продажа минус реагенты по ценам аукциона. Самое выгодное - сверху." },
    { "INV_Misc_Note_02", "Собери очередь", "Щелчок по рецепту добавит его в очередь: видно, чего докупить, и создаётся одной кнопкой." },
  },
}

-- Знакомство с аддоном (UI/Intro.lua) показывает эти тексты отдельным окном.
C.HOW, C.GUIDE = HOW, GUIDE

-- Кнопки шапки вкладки: куда идти дальше.
local function headButtons(UI, tab, data)
  if tab == 1 then
    -- на главной одна плитка - «Выбор профессии» (остальные разделы - во
    -- вкладках окна). У персонажа без профессий выбор открыт и так.
    if #ns:LearnedList() == 0 then return nil end
    return {
      { text = T("Выбор профессии"), icon = "INV_Misc_Book_09", onClick = function() ns:ShowChoose() end,
        tip = T("Что делает каждая профессия и какой сбор к ней нужен. Пригодится, если решишь сменить профессию.") },
    }
  elseif tab == 4 then
    local list = data and data.toAuction or {}
    local open = ns:IsAuctionOpen()
    local has = ns:HasAuctionator()
    return {
      { text = open and T("Найти на аукционе") or T("В список Auctionator"), icon = "INV_Misc_Coin_01", enabled = #list > 0 and has,
        tip = has and (open and T("Найдёт всё нужное на аукционе.") or T("Добавит всё нужное в список «EasyCraft» в Auctionator."))
          or T("Нужен аддон Auctionator: через него EasyCraft ищет сразу весь список."),
        onClick = function() ns:SendToAuction(list) end },
    }
  end
end

function C:GuideCard(UI, tab)
  local rows = GUIDE[tab]
  if not rows then return end
  local hidden = ns.db.guideHidden
  if type(hidden) == "table" and hidden[tab] then return end
  local PAD, CW = UI.PAD, UI.CARD_W
  local c = UI:Card("normal")
  local y0 = c.y
  c:CornerButtons({ { text = T("Скрыть"), w = 90, onClick = function()
    if type(ns.db.guideHidden) ~= "table" then ns.db.guideHidden = {} end
    ns.db.guideHidden[tab] = true
    UI:Render(true)
  end } }, y0 - 4)
  c:Text(T("Как пользоваться?"), "title", { gap = 12, w = CW - PAD * 2 - 100 })
  -- шаги блоками, как предметы лагеря: тёмный блок, сверху значок и что
  -- сделать, под ними пояснение. Четыре - сеткой 2x2, иначе в один ряд.
  local cols = (#rows == 4) and 2 or math.min(#rows, 3)
  local GX, GY, BP = 20, 12, 6 -- просветы между блоками и поля блока
  local colW = floor((CW - PAD * 2 - GX * (cols - 1)) / cols)
  local size = 30
  local rowTop = c.y + BP
  for first = 1, #rows, cols do
    local xs, h = {}, 0
    for i = first, min(first + cols - 1, #rows) do
      local r = rows[i]
      local x = PAD + (i - first) * (colW + GX)
      c:IconAt(x, rowTop, size, ns.Icon(r[1]))
      -- длинный заголовок занимает больше строк, чем высота значка: пояснение ниже него
      local th = c:TextBlock(x + size + 8, rowTop, size, colW - size - 8, { { T(r[2]), "head", W.GOLD, true } })
      local top = max(size, th or 0)
      local fs = c:Text(T(r[3]), "small", { x = x, y = rowTop + top + 6, w = colW, color = W.LIGHT })
      h = max(h, top + 6 + (fs and fs:GetStringHeight() or 14))
      xs[#xs + 1] = x
    end
    -- подложка у всех блоков ряда одной высоты
    for _, x in ipairs(xs) do
      local bg = c:Take("guidebg", function()
        local t = c:CreateTexture(nil, "BORDER")
        t:SetColorTexture(0, 0, 0, 0.3)
        return t
      end)
      bg:SetPoint("TOPLEFT", c, "TOPLEFT", x - BP, -(rowTop - BP))
      bg:SetSize(colW + BP * 2, h + BP * 2)
    end
    rowTop = rowTop + h + BP * 2 + GY
  end
  c.y = rowTop - GY - BP + 4
  UI:End(c, 10)
end

function C:BuildHome(UI, tab)
  tab = tab or 1
  local how = HOW[tab] or HOW[1]
  if tab == 1 then ns.db.introDone = true end -- главную видели: дальше окно открывается там, где было
  local shop = tab == 4 and self:ShoppingData() or nil
  UI:PageHeader(T(how.title), T(how.text), headButtons(UI, tab, shop))
  -- «Как пользоваться» - не на каждой вкладке, а отдельным окном (UI/Intro.lua)
  if tab == 3 then
    self:BuildCamp(UI)
  elseif tab == 4 then
    self:BuildShopping(UI, shop)
  elseif tab == 5 then
    self:BuildBook(UI)
  else
    self:RouteModeCard(UI)
    self:BuildProfList(UI)
  end
end

function C:BuildProfession(UI, key)
  self:BuildRoute(UI, key)
end

-------------------------------------------------------------------------------
--  Главная: профессии. Карточка на профессию: значок, название, пометки
--  словами (отстаёшь, можно учить ранг) и полоса навыка; ниже - все шаги
--  маршрута плитками. Текущий - широкой плиткой с подписью «Текущий шаг».
--  Наведение на плитку - что нужно для шага, щелчок - открыть его.
-------------------------------------------------------------------------------
local HOME_COLS, HOME_GAP, HOME_BAR_W, HOME_RING = 8, 6, 210, 34

function C:ProfCard(UI, key, pool)
  local p = ns.Profs[key]
  local rank, maxRank = ns:GetSkill(key)
  local cur, _, train = ns:CurrentStep(key)
  local order = routeOrder(p)
  local hide = ns.settings.hideDone
  local PAD, CW = UI.PAD, UI.CARD_W
  local c = UI:Card("normal")
  local cap = (maxRank and maxRank > 0) and maxRank or 300
  local function open() UI:Open(key) end

  -- шапка: щелчок по ней открывает профессию
  local rp = W.RingPad(HOME_RING)
  local top = UI.ICON_Y
  local headH = HOME_RING + rp * 2
  c:Zone(6, top - 5, CW - 12, headH + 10, open, function()
    local lines = { { T("Навык"), format("%d / %d", rank, cap) } }
    local nr = ns:NextRank(key)
    if nr then tinsert(lines, { format(T("Ранг «%s»"), ns:RankName(nr.max)), rankShort(nr.s, rank) }) end
    return { title = ns:N(p), lines = lines, hint = T("Щелчок - открыть профессию: все шаги подробно.") }
  end)
  c:Ring(HOME_RING, UI.ICON_X + rp, top + rp):SetIcon(ns.Icon(p.icon))
  local tx = UI.ICON_X + HOME_RING + rp * 2 + UI.ICON_GAP
  local barX = CW - PAD - HOME_BAR_W
  -- слева две строки по центру кольца: название; где ты на маршруте и
  -- отставание. Справа так же: полоса навыка; следующий ранг.
  local nameH, lineH, gap = 17, 14, 1
  local y1 = top + floor((headH - (nameH + gap + lineH)) / 2)
  local y2 = y1 + nameH + gap
  c:Text(ns:N(p), "title", { x = tx, y = y1, w = barX - tx - 10, nowrap = true })
  -- справа полоса навыка (22 с рамкой) и строка ранга под ней - блоком по
  -- центру шапки, как название и шаг слева
  local BAR_H, BAR_GAP = 22, 2
  local ry = top + floor((headH - (BAR_H + BAR_GAP + lineH)) / 2)
  local bar = c:BarAt(barX, ry, HOME_BAR_W, rank, cap, ns:RankName(maxRank), format("%d/%d", rank, cap))
  ns:MarkNextRank(bar)
  local nx = tx
  local pos, total = C:StepPos(p, cur or 0)
  local where = cur and format(T("Шаг %d из %d"), pos or 1, total) or (GREEN .. T("Маршрут пройден") .. "|r")
  local _, ww = c:Note(nx, y2, where, cur and { title = format(T("Шаг %d из %d"), pos or 1, total),
    lines = { ns:StepName(p.steps[cur]) }, hint = T("Щелчок - открыть профессию на этом шаге.") } or nil, open)
  -- отставание - табличкой посередине верхнего края карточки
  local lag, lagTip = lagInfo(key)
  if lag then c:EdgeBadge(0, lag, { center = true, edge = { 0.85, 0.45, 0.1 }, tip = lagTip, onClick = open }) end
  -- справа под полосой: следующий ранг (можно учить - жёлтым, щелчок - метка)
  local nr = ns:NextRank(key)
  if nr then
    local rs = nr.s
    local can = ns:CanLearnRank(rs, rank)
    local npc = rs.npcs and ns:NpcsFor(rs.npcs, 1)[1]
    local text = can and (YELLOW .. format(T("Можно учить «%s»"), ns:RankName(nr.max)) .. "|r")
      or (format(T("«%s»: "), ns:RankName(nr.max)) .. rankShort(rs, rank))
    -- под полосой - с просветом, чтобы не слипалось с её рамкой
    c:Note(PAD, ry + BAR_H + BAR_GAP, text, { title = format(T("Ранг «%s» (до %d)"), ns:RankName(nr.max), nr.max),
      lines = { rankStatus(rs, rank), npc and { ns:NpcName(npc), ns:NpcZone(npc) } or nil },
      hint = npc and T("Щелчок поставит метку на ближайшего.") or nil },
      npc and function() ns:Waypoint(npc, true) end or open, true)
  end

  -- текущий шаг - строкой во всю ширину над плитками (подпись, название,
  -- что нужно, стрелка); ниже все шаги одинаковыми плитками без дыр в
  -- рядах, текущий среди них - в золотой рамке
  local tiles, wide = {}, nil
  for _, si in ipairs(order) do
    local t, st, bb, cost = stepTile(key, p, si, rank, maxRank, cur, nil, pool, {
      hint = T("Щелчок - открыть этот шаг."),
      onClick = function() UI:Open(key, "step:" .. si) end })
    if si == cur then
      local s = p.steps[si]
      wide = {}
      for k, v in pairs(t) do wide[k] = v end
      wide.span, wide.label = HOME_COLS, T("Текущий шаг")
      if s.k == "gather" or s.k == "zone" then
        wide.foot = YELLOW .. format(T("до навыка %d"), s.t) .. "|r"
      elseif bb and not bb.allHave and buyCount(bb) > 0 and (cost or 0) > 0 then
        wide.foot = T("докупить: ") .. (bb.vendorApprox and "~" or "") .. W.Money(cost)
      end
    end
    if not (hide and st == "done") then tinsert(tiles, t) end
  end
  if wide then tinsert(tiles, 1, wide) end
  c.y = top + headH + 6
  if #tiles == 0 then
    c:Text(GREEN .. T("Все шаги выполнены.") .. "|r", "body", { x = tx })
  else
    local w = floor((CW - PAD * 2 - HOME_GAP * (HOME_COLS - 1)) / HOME_COLS)
    local h = c:Tiles(tiles, { mode = "home", cols = HOME_COLS, x = PAD, y = c.y, w = w, gap = HOME_GAP })
    c.y = c.y + h + 6
  end
  UI:End(c, 10)
end

function C:BuildProfList(UI)
  local learned = ns:LearnedList()
  if #learned == 0 then
    self:BuildChoose(UI) -- UI/Choose.lua
    return
  end
  local pool = {} -- общий запас реагентов на все профессии
  for _, key in ipairs(learned) do ns:Safe(self.ProfCard, self, UI, key, pool) end
end

-------------------------------------------------------------------------------
--  Лагерь
-------------------------------------------------------------------------------
function C:BuildCamp(UI)
  if self.XpCard then ns:Safe(self.XpCard, self, UI) end
  -- как устроен лагерь - в «Как это работает» над этим; здесь - галочка и
  -- предметы профессий блоками в ряд
  local f = UI:Card("flat")
  f:Check(T("Показать предметы всех профессий"), ns.settings.campAll, function(v) ns.settings.campAll = v; UI:Render(true) end,
    T("Не только твоих профессий: что дают предметы лагеря других и где взять рецепты."))
  local _, finds = ns:BlueprintReport()
  if finds > 0 then
    f:Buttons({ { text = format(T("Поделиться находками (%d)"), finds), w = 240, onClick = function() ns:ShareBlueprints() end,
      tip = T("Чертежи, которые тебе выпадали, а где они падают, аддон ещё не знает. Отправь код автору - место появится у всех.") } })
  end
  UI:End(f, 6)
  local list = ns.settings.campAll and ns.ProfOrder or ns:LearnedList()
  for _, key in ipairs(list) do
    local p = ns.Profs[key]
    if p.camp and #p.camp > 0 then self:CampCard(UI, key) end
  end
end

local QUESTION_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

-- Где падают чертежи лагеря: подземелье - его зона и вход (метка на
-- карте), место под открытым небом - зона (карта открывается на ней).
local BP_PLACE = {
  ["Мертвые копи"] = { 40, 42.6, 71.8 }, ["Крепость Темного Клыка"] = { 130, 44.8, 67.8 },
  ["Пещеры Стенаний"] = { 17, 46.0, 36.4 }, ["Непроглядная Пучина"] = { 331, 14.5, 14.2 },
  ["Лабиринты Иглошкурых"] = { 17, 42.3, 89.9 },
  ["Руины Лордерона"] = { 85 }, ["Альтеракские горы"] = { 36 }, ["раскопки в Болотине"] = { 11 },
}

-- Где взять рецепт предмета лагеря - строки-кнопки, как везде: слева
-- значок карты, кто и где, справа - что там взять (свиток учителя или
-- чертёж). Щелчок - метка на карте (вход в подземелье) или карта зоны.
-- Возвращает список строк.
function C:CampSource(p, e)
  if e.bp then
    local bpName = ns:ItemNameIfCached(e.bp) or T("Чертёж")
    local list = (e.how or ""):match(":%s*(.+)$")
    if not list then
      -- источник пока неизвестен; если чертёж уже выпадал тебе - где
      local f = ns.db.bpFound and ns.db.bpFound[e.bp]
      if f then
        local ui = f.map
        return { { tex = MAP_ICON, text = T("Чертёж: ") .. (f.who or "?"), sub = (f.where or "") .. ", " .. T("тебе уже выпадал"),
          icons = { ns:ItemIcon(e.bp) },
          tip = { title = bpName, lines = { T("Источник в базах пока неизвестен - это место из твоей добычи.") },
            hint = (ui and f.x) and T("Щелчок поставит метку и откроет карту.") or nil },
          onClick = function() if ui and f.x then ns:MapPoint(ui, f.x, f.y, f.who or bpName, f.where, true) end end } }
      end
      -- неизвестно где - такая же кнопка: щелчок объяснит, что аддон запомнит
      return { { tex = QUESTION_ICON, text = T("Чертёж: где падает?"), sub = T("пока неизвестно"),
        icons = { ns:ItemIcon(e.bp) },
        tip = { title = bpName, lines = { T("Где падает этот чертёж, пока никто не знает."),
          T("Выпадет тебе - аддон запомнит место и покажет его здесь.") } },
        onClick = function() ns:Print(format(T("где падает «%s», пока неизвестно. Выпадет тебе - аддон запомнит место."), bpName)) end } }
    end
    local rows = {}
    for part in (list:gsub("%.%s*$", "") .. " / "):gmatch("(.-)%s*/%s*") do
      local boss, place = part:match("^(.-),%s*(.+)$")
      boss, place = boss or part, place or ""
      local pl = BP_PLACE[place]
      local z = pl and ns.Zones[pl[1]]
      local zoneName = z and ns:ZoneName(pl[1]) or nil
      local sub = (z and zoneName ~= place) and (place .. ", " .. zoneName) or place
      local onClick
      if pl and pl[2] then
        onClick = function() ns:MapPoint(z.ui, pl[2], pl[3], place, zoneName, true) end
      elseif z then
        onClick = function() C:ShowOnMap(pl[1]) end
      end
      tinsert(rows, { tex = MAP_ICON, text = T("Чертёж: ") .. boss, sub = sub, icons = { ns:ItemIcon(e.bp) },
        tip = { title = bpName, lines = { format(T("Падает с: %s"), boss), sub },
          hint = onClick and (pl[2] and T("Щелчок поставит метку у входа и откроет карту.") or T("Щелчок откроет карту на этой зоне.")) or nil },
        onClick = onClick or function() end })
    end
    return rows
  end
  if e.tier == 1 then -- первый уровень - у учителя
    for _, st in ipairs(p.steps) do
      if st.k == "train" and st.npcs then
        local id = ns:NpcsFor(st.npcs, 1)[1]
        if id then
          return { { tex = MAP_ICON, text = T("Учитель: ") .. ns:NpcName(id), icons = { SCROLL_ICON },
            sub = (ns:NpcZone(id) or "") ..  ", " .. T("или за задание «Лагерь 101»"),
            tip = { title = ns:NpcName(id), lines = { ns:NpcZone(id) }, hint = T("Щелчок поставит метку и откроет карту.") },
            onClick = function() ns:Waypoint(id, true) end } }
        end
      end
    end
  end
end

-- Предметы лагеря одной профессии: заголовок - значок и название
-- профессии, ниже блоки в ряд (по 3): значок предмета, название, что даёт и
-- с какого навыка; под ними - кнопки «где взять рецепт» (учитель, чертёж,
-- даже если где падает - неизвестно) и «Использовать», если он в сумках.
-- CAMP_GAP - просвет между блоками, CAMP_BP - поле внутри блока (со всех сторон), CAMP_BG - насколько блок темнее карточки
local CAMP_COLS, CAMP_GAP, CAMP_ICON, CAMP_BP, CAMP_BG = 2, 12, 32, 12, 0.55
function C:CampCard(UI, key)
  local p = ns.Profs[key]
  local rank, _, learned = ns:GetSkill(key)
  local PAD, CW = UI.PAD, UI.CARD_W
  local c = UI:Card()
  -- шапка карточки: кольцо и название профессии по центру кольца
  local ring = 26
  local rp = W.RingPad(ring)
  local IX, IY = UI.ICON_X, UI.ICON_Y
  c:Ring(ring, IX + rp, IY + rp):SetIcon(ns.Icon(p.icon))
  c:TextBlock(IX + ring + rp * 2 + UI.ICON_GAP, IY, ring + rp * 2, CW - PAD * 2 - 60, { { ns:N(p), "title" } })
  local y = IY + ring + rp * 2 + 10
  local blockW = floor((CW - PAD * 2 - CAMP_GAP * (CAMP_COLS - 1)) / CAMP_COLS)
  local colW = blockW - CAMP_BP * 2
  local ip = W.IconPad(CAMP_ICON)
  local outer = CAMP_ICON + ip * 2
  -- блоки рядами по CAMP_COLS: сверху значок, название и описание, кнопки
  -- «где взять» - по низу блока, на одной линии во всём ряду
  local function cellH(it) return (it.sub and it.sub ~= "") and 40 or 34 end
  local rowTop = y + CAMP_BP
  local camp = p.camp
  for first = 1, #camp, CAMP_COLS do
    local blocks = {}
    local topH, btnH = 0, 0
    for ci = first, min(first + CAMP_COLS - 1, #camp) do
      local e = camp[ci]
      local col = ci - first
      local x = PAD + CAMP_BP + col * (blockW + CAMP_GAP)
      -- значок и название по центру значка
      local by = rowTop
      local icon = c:Icon(CAMP_ICON, x + ip, by + ip)
      if e.out then icon:SetItem(e.out) else icon:SetPlain(ns.Icon("Spell_Fire_Fire")) end
      -- у кольца редкости прозрачные края: текст ближе к значку
      local tx = x + outer + 3 -- просвет как у шапок: ~10 от видимого кольца
      c:TextBlock(tx, by, outer, colW - outer - 3, { { (e.out and ns:ItemNameIfCached(e.out)) or ns:N(e), "head", W.LIGHT, true } })
      by = by + outer + 4
      -- вторая строка: что даёт и с какого навыка
      local can = learned and rank >= e.skill
      local have = e.out and ns:InBags(e.out) or 0
      local desc = (e.effect and e.effect ~= "" and (e.effect .. " ") or "")
        .. (can and GREEN or RED) .. format(T("Навык %d."), e.skill) .. "|r"
        .. (have > 0 and ("  " .. GREEN .. format(T("В сумках: %d."), have) .. "|r") or "")
      local fs = c:Text(desc, "small", { x = x, y = by, w = colW })
      by = by + (fs and fs:GetStringHeight() or 14)
      -- сколько места займут кнопки
      local where = self:CampSource(p, e)
      local h = 0
      if where then
        for k, it in ipairs(where) do h = h + cellH(it) + (k > 1 and 4 or 0) end
      end
      if have > 0 then h = h + (h > 0 and 4 or 0) + 24 end
      topH = max(topH, by - rowTop)
      btnH = max(btnH, h)
      tinsert(blocks, { e = e, x = x, where = where, have = have, h = h })
    end
    local rowH = topH + 16 + btnH -- просвет от описания до кнопок
    for _, bl in ipairs(blocks) do
      local bg = c:Take("campbg", function()
        local t = c:CreateTexture(nil, "BORDER")
        t:SetColorTexture(0, 0, 0, CAMP_BG)
        return t
      end)
      bg:SetPoint("TOPLEFT", c, "TOPLEFT", bl.x - CAMP_BP, -(rowTop - CAMP_BP))
      bg:SetSize(blockW, rowH + CAMP_BP * 2)
      -- кнопки прижаты к низу блока
      local by = rowTop + rowH - bl.h
      for _, it in ipairs(bl.where or {}) do by = by + c:CellAt(bl.x, by, colW, it, 22) + 4 end
      if not bl.where then
        c:Text(bl.e.how, "small", { x = bl.x, y = rowTop + topH + 6, w = colW })
      end
      if bl.have > 0 then c:UseButton(bl.e.out, bl.x, rowTop + rowH - 24, colW) end
    end
    rowTop = rowTop + rowH + CAMP_BP * 2 + CAMP_GAP
  end
  -- rowTop - верх содержимого следующего ряда: низ последнего блока выше на поле и просвет
  c.y = rowTop - CAMP_BP - CAMP_GAP + 6
  UI:End(c, 10)
end

-------------------------------------------------------------------------------
--  Покупки: что докупить до следующего учителя по всем профессиям и почём
-------------------------------------------------------------------------------
-- Что докупить по всем профессиям: карточки, общий список для аукциона, итоги.
function C:ShoppingData()
  local source = ns:PriceSource()
  local cards, toAuction = {}, {}
  local grand, noPrice, count, oldPrices, vendorCount = 0, 0, 0, 0, 0
  -- Один запас на все профессии: что ушло на одну, другой уже не достанется.
  local pool = {}
  for _, key in ipairs(ns:LearnedList()) do
    local cap = ns:ShoppingCap(key)
    local list = ns:ShoppingList(key, cap)
    if #list > 0 then
      local card = { key = key, cap = cap, rows = {}, total = 0 }
      for _, e in ipairs(list) do
        if not e.crafted then
          local stock = pool[e.id] or (e.have + e.alts + (e.mail or 0))
          e.buy = max(0, e.need - stock)
          pool[e.id] = max(0, stock - e.need)
        end
        if e.buy > 0 then
          local cost, age = buyCost(e.id, e.buy)
          e.cost, e.age = cost, age
          if cost then
            card.total = card.total + cost
            if age then oldPrices = oldPrices + 1 end
          elseif not ns:IsVendorItem(e.id) then
            noPrice = noPrice + 1
          end
          if ns:IsVendorItem(e.id) then vendorCount = vendorCount + 1 end
          if not ns:IsVendorItem(e.id) then tinsert(toAuction, e) end
          tinsert(card.rows, e)
          count = count + 1
        end
      end
      grand = grand + card.total
      tinsert(cards, card)
    end
  end
  return { source = source, cards = cards, toAuction = toAuction, grand = grand, noPrice = noPrice, count = count,
    oldPrices = oldPrices, vendorCount = vendorCount }
end

function C:BuildShopping(UI, d)
  d = d or self:ShoppingData()
  local source, cards, grand, noPrice, count, oldPrices, vendorCount =
    d.source, d.cards, d.grand, d.noPrice, d.count, d.oldPrices, d.vendorCount
  -- Итог сверху (кнопка аукциона - в шапке вкладки)
  local c = UI:Card()
  local topW = nil
  if count == 0 then
    c:Text(GREEN .. T("Докупать ничего не нужно.") .. "|r", "body", { w = topW })
  else
    c:Text(T("На аукционе: ") .. (grand > 0 and W.Money(grand) or "-")
      .. (noPrice > 0 and ("  |cff9d9d9d" .. format(T("(и ещё %d без цены)"), noPrice) .. "|r") or ""), "title", { gap = 6, color = W.LIGHT, w = topW })
    if not source then
      c:Text(RED .. T("Цен нет: открой аукцион - EasyCraft прочитает их сам.") .. "|r", "small")
    elseif noPrice > 0 or oldPrices > 0 then
      c:Text(format(T("Цены из %s. Открой аукцион, чтобы обновить: без цены %d, старше %d дн. - %d."), source, noPrice, ns.PRICE_OLD_DAYS, oldPrices), "small")
    else
      c:Text(format(T("Цены из %s."), source), "small")
    end
  end
  UI:End(c)

  -- По профессиям
  for _, card in ipairs(cards) do
    local p = ns.Profs[card.key]
    local pc = UI:Card(#card.rows == 0 and "done" or "normal")
    local py = pc.y
    if card.total > 0 then pc:Corner(W.Money(card.total), "body", py + 8, W.LIGHT) end
    pc:Head({ ring = ns.Icon(p.icon) }, ns:N(p), { { format(T("до %d навыка"), card.cap), "small" } }, 32)
    if #card.rows == 0 then
      pc:Text(GREEN .. format(T("Всё есть для шагов до %d."), card.cap) .. "|r", "body")
    else
      for _, e in ipairs(card.rows) do
        -- «у торговца» уже справа вместо цены, здесь только «можно собрать»
        local tag = ns:OwnGather(e.id) and T("можно собрать") or nil
        local right
        if e.cost then right = W.Money(e.cost) .. (e.age and ("|cff9d9d9d ~" .. ageWord(e.age) .. "|r") or "")
        elseif ns:IsVendorItem(e.id) then
          local money = vendorMoney(e.id, e.buy)
          right = (money and (money .. " ") or "") .. "|cff9d9d9d" .. T("у торговца") .. "|r"
        else right = "|cff9d9d9d" .. T("нет цены") .. "|r" end
        local id, buy = e.id, e.buy
        pc:Row({
          id = id, hoverItem = true,
          text = format("%d × %s", buy, ns:ItemName(id))
            .. "  |cff9d9d9d" .. format(T("есть %d из %d"), e.have, e.need)
            .. ((e.mail or 0) > 0 and (", " .. format(T("на почте %d"), e.mail)) or "")
            .. (e.alts > 0 and (", " .. format(T("у альтов %d"), e.alts)) or "") .. (tag and (", " .. tag) or "") .. "|r",
          right = right,
          onClick = function()
            if IsModifiedClick and IsModifiedClick("CHATLINK") then
              local _, link = C_Item.GetItemInfo(id)
              W.InsertLink(link)
            elseif ns:IsAuctionOpen() and not ns:IsVendorItem(id) then
              ns:SendToAuction({ { id = id, buy = buy } })
            end
          end,
        })
      end
    end
    local route, routeNoPrice = ns:RouteCost(card.key)
    if route > 0 then
      pc:Text(format(T("Весь путь до 300: около %s"), W.Money(route))
        .. (routeNoPrice > 0 and ("  |cff9d9d9d" .. format(T("(и ещё %d без цены)"), routeNoPrice) .. "|r") or ""), "small")
    end
    UI:End(pc)
  end
end

-------------------------------------------------------------------------------
--  Профессия: все шаги маршрута по порядку, раскрытыми и в одном виде.
--  Сверху - «Скрывать выполненные» и сколько сделано; ранг - строкой на
--  пергаменте. Карточка шага: значок, «5. Название», справа метка (текущий,
--  выполнено, можно сейчас), строка навыка; ниже - из чего, где или у кого.
--  Текущий шаг - в золотой рамке, с предупреждениями и кнопками создания.
-------------------------------------------------------------------------------

local function nodeItem(nk, rank)
  local n = ns.Nodes[nk]
  local col = ns:GatherColor(max(rank, 1), n.req)
  return { id = n.item, text = ns:Hex(col) .. ns:N(n) .. "|r", sub = format(T("С %d навыка"), n.req) }
end

-- Строка под названием шага: навык и коротко, что осталось.
local function stepSub(key, s, st, rank, left)
  if isRankStep(s) then
    local t = format(T("Предел навыка станет %d"), s.max)
    if st ~= "done" then t = t .. ", " .. rankShort(s, rank) end
    return t
  end
  local t = format(T("Навык %d-%d"), s.f, s.t)
  if st == "done" then return t end
  if s.k == "craft" then
    -- цвет рецепта: из окна профессии точнее данных маршрута
    if rank >= (s.f or 0) then
      local col = ns:RealColor(key, s.spell, rank) or (s.sk and ns:RecipeColor(s, rank))
      if col then
        t = t .. ", " .. T("рецепт ") .. ns:Hex(col) .. (ns.ColorName[col] or "") .. "|r"
        local chance = ns:ChanceText(s, rank, col)
        if chance then t = t .. " (" .. chance .. ")" end
      end
    end
    if left and left > 0 then t = t .. ", " .. format(T("сделать ещё %d"), left) end
  elseif st == "current" and s.t then
    t = t .. ", " .. format(T("осталось %d"), max(s.t - rank, 0))
  end
  return t
end

-- Заголовок ранга на пергаменте: «Подмастерье 75-150», справа «5/7».
function C:RankHead(UI, bk, done, total)
  local lo, hi = RANKS[bk][1], RANKS[bk][2]
  local c = UI:Card("flat")
  local y = c.y + 4
  -- справа «5/7»; ранг пройден - зелёным и с галочкой (отдельным значком,
  -- по центру строки)
  local all = total > 0 and done == total
  local fs = c:Corner((all and "|cff33dd33" or "") .. format("%d/%d", done, total) .. (all and "|r" or ""), "head", y + 3, nil, all)
  if all then
    local ok = c:Take("rankok", function()
      local t = c:CreateTexture(nil, "OVERLAY")
      t:SetSize(16, 16)
      t:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
      return t
    end)
    ok:SetPoint("RIGHT", fs, "LEFT", -4, 1)
  end
  c:Text(ns:RankName(hi) .. "  " .. format("%d-%d", lo, hi), "title", { y = y, nowrap = true })
  c.y = y + 24
  UI:End(c, 4)
end

function C:BuildRoute(UI, key)
  local p = ns.Profs[key]
  local rank, maxRank = ns:GetSkill(key)
  local cur, _, train = ns:CurrentStep(key)
  local order = routeOrder(p)
  local hide = ns.settings.hideDone
  local states = {}
  local inRank, doneInRank = {}, {}
  for _, i in ipairs(order) do
    local st = ns:StepState(key, i, rank, maxRank)
    local bk = stepRank(p.steps[i])
    states[i] = st
    inRank[bk] = (inRank[bk] or 0) + 1
    if st == "done" then
      doneInRank[bk] = (doneInRank[bk] or 0) + 1
    end
  end

  -- режим маршрута выбирают вкладками окна; здесь - только если режиму
  -- не хватает цен
  if ns.HasRouteModes and ns:HasRouteModes(key) then
    local mode = ns:RouteMode()
    if mode ~= "guide" and p.routeMode ~= mode then
      local mc = UI:Card("flat")
      mc:Text(T("Для этого режима нужны цены: открой аукцион. Пока показан обычный маршрут."), "small")
      UI:End(mc, 6)
    end
  end

  -- куда прокрутить: выбранный шаг или текущий
  local focus = UI.focus[key]
  UI.focus[key] = nil
  if focus == "cur" then focus = cur end
  if focus and hide and states[focus] == "done" then focus = cur end

  local pool = {} -- запас реагентов идёт по маршруту: что ушло шагу, следующему не достанется
  local lastB, shown = nil, 0
  UI.stepBuy = nil
  for n, i in ipairs(order) do
    local s = p.steps[i]
    local st = states[i]
    local left = (s.k == "craft" and st ~= "done") and ns:RemainingCrafts(s, rank) or 0
    local b
    if left > 0 and (s.rc or s.m) then b = ns:StepBuy(s, left, pool) end
    if not (hide and st == "done") then
      local bk = stepRank(s)
      if bk ~= lastB then
        lastB = bk
        self:RankHead(UI, bk, doneInRank[bk] or 0, inRank[bk] or 0)
      end
      if focus == i then UI.jumpY = max(0, UI.y - 6) end
      ns:Safe(self.StepCard, self, UI, key, i, n, st, cur, train, rank, maxRank, b, left)
      shown = shown + 1
    end
  end
  if shown == 0 then
    local c = UI:Card("done")
    c:Head({ ring = ns.Icon(p.icon) }, T("Маршрут пройден"), { { T("Все шаги до 300 выполнены."), "body" } })
    UI:End(c)
  end
end

local STEP_ICON, NUM_ICON = 36, 20

-- Карточка шага: круглый значок в золотом кольце, на его нижнем крае -
-- номер шага кружком; справа от значка по его центру - название и строка
-- навыка; у правого края - метка («Выполнено», «Можно сейчас») или
-- табличка «Текущий шаг» на том же месте. Сделанный шаг - без тела.
function C:StepCard(UI, key, i, n, st, cur, train, rank, maxRank, b, left)
  local p = ns.Profs[key]
  local s = p.steps[i]
  local isCur = i == cur
  local done = st == "done"
  local PAD, CW = UI.PAD, UI.CARD_W
  -- текущий - ярко, пройденный - зелёный, «можно сейчас» - обычная рамка,
  -- до остальных ещё не дошли - рамка приглушённая
  local c = UI:Card(isCur and "current" or (done and "done" or (st == "current" and "normal" or "future")))
  local y0 = UI.ICON_Y
  -- значок шага (у предмета - подсказка предмета и ссылка в чат)
  local ip = W.RingPad(STEP_ICON)
  local outer = STEP_ICON + ip * 2
  local ix = UI.ICON_X
  local ic = c:Icon(STEP_ICON, ix + ip, y0 + ip)
  ic.gold = true
  local item = s.id or (s.k == "gather" and s.nodes and s.nodes[1] and ns.Nodes[s.nodes[1]].item) or nil
  if item then ic:SetItem(item) else ic:SetPlain(s.k == "quest" and QUEST_ICON or ns:StepIcon(s, p), s.spell) end
  ic:SetAlpha(done and 0.6 or 1)
  -- номер шага - кружком на нижнем крае значка
  local nrp = W.RingPad(NUM_ICON)
  local num = c:NumIcon(ix + floor((outer - NUM_ICON) / 2), y0 + outer - nrp - NUM_ICON + 6, NUM_ICON, n,
    isCur and "current" or (done and "done" or nil))
  num:SetFrameLevel(ic:GetFrameLevel() + 3)
  local bottom = y0 + outer + 6 -- нижний край кружка с номером
  local tx = ix + outer + UI.ICON_GAP
  -- справа по центру значка: табличка «Текущий шаг» или метка словами
  local mid = y0 + floor(outer / 2)
  local tagW = 0
  if isCur then
    local plate = c:EdgeBadge(PAD, T("Текущий шаг"), { right = true, big = true, y = mid })
    tagW = (plate:GetWidth() or 120) + 12
  else
    local tag
    if done then tag = GREEN .. T("Выполнено") .. "|r"
    elseif st == "current" then tag = YELLOW .. T("Можно сейчас") .. "|r" end
    if tag then
      -- по центру значка (буквы рисуются на пиксель выше середины строки)
      local fs = c:Corner(tag, "head", 0, W.LIGHT)
      fs:ClearAllPoints()
      fs:SetPoint("RIGHT", c, "TOPRIGHT", -PAD, -mid - 1)
      tagW = (fs:GetStringWidth() or 80) + 12
      if done then
        -- галочка перед «Выполнено», ровно по середине букв
        local ok = c:Take("doneok", function()
          local t = c:CreateTexture(nil, "OVERLAY")
          t:SetSize(18, 18)
          t:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
          return t
        end)
        ok:SetPoint("RIGHT", fs, "LEFT", -5, 1)
        tagW = tagW + 23
      end
    end
  end
  local nameCol = isCur and W.GOLD or (done and { 0.75, 0.85, 0.75 } or W.LIGHT)
  c:TextBlock(tx, y0, outer, CW - tx - PAD - tagW, {
    { ns:StepName(s) .. (s.approx and (ORANGE .. " ~|r") or ""), "title", nameCol },
    { stepSub(key, s, st, rank, left), "small" },
  })
  c.y = bottom + 6
  if done then
    UI:End(c, 6, bottom + UI.ICON_Y)
    return
  end
  c.indent = tx -- тело шага - под названием
  if isCur then self:CurrentWarnings(UI, c, key, s, st, rank, maxRank) end
  if s.k == "craft" then
    self:CraftBody(UI, c, key, s, rank, isCur, b, left)
  elseif isRankStep(s) then
    self:RankBody(UI, c, s, isCur)
  elseif s.k == "gather" then
    self:GatherBody(UI, c, s, rank, isCur)
  elseif s.k == "zone" then
    self:ZoneBody(UI, c, s, isCur)
  end
  if isCur then self:CurrentActions(UI, c, key, i, s, st, train, rank, maxRank, left) end
  c.indent = nil
  UI:End(c, 6)
end

-- Текущий шаг: что мешает (отстаёшь, не тот навык, рецепта нет в игре).
function C:CurrentWarnings(UI, c, key, s, st, rank, maxRank)
  local lag, lagTip = lagInfo(key)
  if lag then
    c:Note(c.indent, c.y, lag, lagTip)
    c.y = c.y + 22
  end
  local mismatch = self:Mismatch(s, rank, maxRank, st)
  if mismatch then c:Text(mismatch, "small", { gap = 6 }) end
  if s.k == "craft" then
    local real = ns:RealColor(key, s.spell, rank)
    if s.approx and not real then
      c:Text(ORANGE .. T("Отрезок примерный: смотри на цвет рецепта в окне профессии.") .. "|r", "small", { gap = 6 })
    end
    if rank >= (s.f or 0) and (real or (s.sk and ns:RecipeColor(s, rank))) == "gray" then
      c:Text(RED .. T("Рецепт уже серый, навык не растёт: переходи дальше.") .. "|r", "small", { gap = 6 })
    end
  end
  local check = ns:StepCheck(key, s)
  if check and check.missing then
    c:Text(ORANGE .. T("Этого рецепта в игре нет: пропусти шаг кнопкой «Пропустить шаг».") .. "|r", "small", { gap = 6 })
  end
  -- заметки к сбору и ловле повторяют список жил и зон - не показываем
  if s.note and s.k == "craft" then c:Text(s.note, "small", { gap = 6 }) end
end

-- Рецепт не выучен - одной строкой (у шагов впереди): где взять.
local function recipeShort(src)
  if src.kind == "vendor" then
    local money = src.copper and W.Money(src.copper) or src.price
    return money and format(T("Рецепт: купить у торговца за %s"), money) or T("Рецепт: купить у торговца")
  elseif src.kind == "trainer" then
    return T("Рецепт: выучить у учителя")
  end
  return T("Рецепт ещё не выучен")
end

-- Создание: если рецепт не выучен - где его взять; картинка «реагенты ->
-- результат» (есть/нужно), справа - что докупить или «Всё есть».
function C:CraftBody(UI, c, key, s, rank, isCur, b, left)
  local known = ns:RecipeKnown(key, s.spell)
  if known == false then
    if isCur then self:TrainerBlock(UI, c, key, s)
    else c:Text(ORANGE .. recipeShort(ns:RecipeSource(key, s)) .. "|r", "small", { gap = 6 }) end
  elseif known == nil and s.src == "recipe" and isCur then
    c:Text(T("Рецепт нужно купить") .. (s.info and (": " .. s.info) or "."), "small", { gap = 6 })
    local items = npcItems(s.npcs, 2, s.recipe and ns:ItemIcon(s.recipe) or nil)
    if #items > 0 then c:Items(items, 2, 22) end
  end
  if not b then return end
  local inputs = {}
  for _, e in ipairs(b.items) do
    -- «есть» - то, что досталось этому шагу (раньше по маршруту могли забрать)
    local have = min(e.have, e.stock or e.have)
    local it = { id = e.id, text = haveNeed(have, e.need), done = e.need > 0 and have >= e.need }
    if have < e.need then
      local tip = buyText(e.id, e.buy, e.cost, e.age, e.alts, e.mail, e.approx)
      if e.all > e.have then
        tip = YELLOW .. format(T("в банке %d - забери у банкира"), e.all - e.have) .. "|r" .. (tip and ("\n" .. tip) or "")
      end
      it.tip = tip
    end
    tinsert(inputs, it)
  end
  local out = s.id and { id = s.id } or { tex = ns:StepIcon(s, ns.Profs[key]), spell = s.spell }
  if left and left > 0 then out.text = "|cffffffff" .. left .. "|r" end
  local lines
  if b.allHave then lines = { GREEN .. T("Всё есть") .. "|r" }
  else
    lines = ns:StepBuyLines(b)
    if isCur then UI.stepBuy = b end -- для «Найти на аукционе»
  end
  c:Flow(inputs, out, 32, c.indent - 2, lines)
end

-- Ранг: ближайшие учителя, торговцы книгой или кто даёт задание.
function C:RankBody(UI, c, s, isCur)
  if s.text and isCur then c:Text(s.text, "small", { gap = 6 }) end
  local money
  if s.k == "book" and s.id then
    local price, approx = ns:VendorPrice(s.id)
    if price then money = (approx and "~" or "") .. W.Money(price) end
  end
  local what = s.k == "book" and s.id and ns:ItemIcon(s.id) or (s.k == "quest" and QUEST_ICON or nil)
  local items = npcItems(s.npcs, isCur and 4 or 2, what, money)
  if #items > 0 then c:Items(items, 2, 22) end
end

-- Сбор: что собирать (с какого навыка) и где - кнопками на карту.
function C:GatherBody(UI, c, s, rank, isCur)
  local nodes = {}
  for _, nk in ipairs(s.nodes or {}) do tinsert(nodes, nodeItem(nk, rank)) end
  -- что собирать - крупными значками в два столбца
  if #nodes > 0 then c:Items(nodes, 2, 30) end
  local best = ns:StepGatherZones(s, rank, isCur and 4 or 2)
  if #best == 0 then return end
  local zones = {}
  for _, z in ipairs(best) do
    local area = z.area
    local _, what = ns:ZoneNodesText(z, 14, 3)
    -- лучшая для своей фракции - со звездой (без подписи: лишний текст)
    tinsert(zones, { tex = MAP_ICON, text = C:ZoneText(area, true), icons = ns:ZoneNodeIcons(z, 3),
      star = z.rec, hot = z.rec,
      tip = { title = ns:ZoneName(area), lines = { ns:ZoneWhy(z), what ~= "" and what or nil },
        hint = T("Щелчок откроет карту на этой зоне: места сбора отмечены.") },
      onClick = function() C:ShowOnMap(area, s.nodes) end })
  end
  c:Items(zones, 2, 22)
end

-- Ловля и снятие шкур: зоны кнопками на карту, первая - рекомендуемая.
function C:ZoneBody(UI, c, s, isCur)
  local items = {}
  -- сначала лучшие зоны своей фракции (из маршрута), потом остальные
  local me = ns:PlayerFaction()
  local areas, seen = {}, {}
  for _, area in ipairs(s[me == "A" and "recA" or "recH"] or {}) do
    if not seen[area] then seen[area] = true; tinsert(areas, area) end
  end
  local nRec = #areas
  for _, area in ipairs(s.areas or {}) do
    if not seen[area] then seen[area] = true; tinsert(areas, area) end
  end
  for k, area in ipairs(areas) do
    if ns:ZoneAllowed(area) and #items < (isCur and 6 or 2) then
      local best = #items == 0
      tinsert(items, { tex = MAP_ICON, text = C:ZoneText(area, true), star = best, hot = best,
        tip = { title = ns:ZoneName(area), hint = T("Щелчок откроет карту на этой зоне.") }, onClick = function() C:ShowOnMap(area) end })
    end
  end
  c:Items(items, 2, 22)
end

-- Текущий шаг, низ карточки: другие рецепты, подсказки в поле и кнопки.
-- Шаг засчитывается сам по навыку; «Пропустить шаг» - только когда его не
-- сделать (рецепта нет в игре, он уже серый), «Вернуть шаг» - если его
-- пропускали вручную.
function C:CurrentActions(UI, c, key, i, s, st, train, rank, maxRank, left)
  if s.k == "craft" then
    local offers = ns:BestRecipes(key, s, rank, 3)
    if #offers > 0 then self:BestBlock(UI, c, key, offers) end
    local rs = s.spell and ns:RecipeState(key, s.spell)
    if rs and rs.enchant then c:Text(T("Чары накладываются из окна профессии: выбери там вещь."), "small", { gap = 6 }) end
  end
  local p = ns.Profs[key]
  if train and train ~= i and ns:CanLearnRank(p.steps[train], rank) then
    c:Text(YELLOW .. T("Уже можно выучить ранг: ") .. "|r" .. ns:RankName(p.steps[train].max), "body", { gap = 6 })
  end
  missingTools(c, key, max(rank, s.f or 0))
  ns:Safe(fieldHints, c, key, s, rank)

  local check = ns:StepCheck(key, s)
  local manual = ns.char.manual[key] and ns.char.manual[key][i]
  local stuck = (check and check.missing)
    or (s.k == "craft" and rank >= (s.f or 0) and (ns:RealColor(key, s.spell, rank) or (s.sk and ns:RecipeColor(s, rank))) == "gray")
  local craft = s.k == "craft" and s.spell
  if not (manual ~= nil or stuck or craft) then return end
  local y = c.y + 4
  local placed = false
  if manual ~= nil or stuck then
    placed = true
    c:Button({ text = manual ~= nil and T("Вернуть шаг") or T("Пропустить шаг"), w = 140,
      tip = manual ~= nil and T("Шаг снова будет засчитываться сам, по навыку.")
        or T("Шаг засчитывается сам, когда навык дорастёт. Пропусти его, если сделать его нельзя."),
      onClick = function()
        ns:ToggleManual(key, i)
        UI:Render(true)
      end }, c.indent or UI.PAD, y)
  end
  if craft then
    if self:CraftButtons(UI, c, key, s, left, y) or self:AuctionButton(UI, c, y) then placed = true end
  end
  -- строку под кнопки - только если они есть: иначе пустое место снизу
  if placed then c.y = y + 32 end
end

-- Шаг не совпадает с навыком профессии: подсказать, что не так.
function C:Mismatch(s, rank, maxRank, state)
  if state == "done" or isRankStep(s) or not s.f then return nil end
  if rank < s.f then
    local msg = format(T("Твой навык %d, а этот шаг начинается с %d."), rank, s.f)
    if maxRank > 0 and s.f >= maxRank then
      msg = msg .. " " .. format(T("Навык упёрся в предел %d: сначала выучи следующий ранг."), maxRank)
    end
    return ORANGE .. msg .. "|r"
  elseif rank >= s.t then
    return ORANGE .. format(T("Твой навык %d уже выше этого шага (%d-%d): переходи дальше."), rank, s.f, s.t) .. "|r"
  end
end

-- «Где выучить рецепт» - как в подсказке у окна профессии: жёлтый
-- заголовок и строка в золотой рамке: слева значок карты, имя и зона,
-- справа цена и что взять (рецепт или свиток учителя). Щелчок - метка и карта.
function C:TrainerBlock(UI, c, key, s)
  local src = ns:RecipeSource(key, s)
  local id = src.npc
  if not id then
    c:Text(YELLOW .. ns:RecipeSourceHead(src) .. "|r", "body", { gap = 8 })
    return
  end
  local vendor = src.kind == "vendor"
  c:Text(vendor and T("Купи рецепт") or T("Выучи рецепт у учителя"), "head", { gap = 6 })
  local money = vendor and (src.copper and W.Money(src.copper) or src.price) or nil
  local which = src.count == 1 and T("Единственный.") or (src.count and src.count > 1 and format(T("Ближайший из %d."), src.count)) or nil
  c:Items({ { tex = MAP_ICON, text = ns:NpcName(id), sub = ns:NpcZone(id) .. (src.extra and (", " .. src.extra) or ""),
    right = money, icons = { vendor and src.item and ns:ItemIcon(src.item) or SCROLL_ICON }, hot = true,
    tip = { title = ns:NpcName(id), lines = { vendor and T("Ближайший торговец этим рецептом.") or T("Ближайший учитель."), which },
      hint = T("Щелчок поставит метку и откроет карту.") },
    onClick = function() ns:Waypoint(id, true) end } }, 1, 26)
end

-- Другие рецепты, как в подсказке у окна профессии: «Можно качать и на
-- них» (на шаг нет реагентов или рецепт не выучен) или «Выгоднее сейчас».
-- Строки: значок, название цветом рецепта, справа цена и сколько хватит;
-- лучший - со звездой и в золотой рамке, у него «Создать N».
function C:BestBlock(UI, c, key, offers)
  local best = offers[1]
  c:Space(2)
  c:Text(best.instead and T("Можно качать и на них") or T("Выгоднее сейчас"), "head", { gap = 6 })
  local rows = {}
  for k, o in ipairs(offers) do
    local why = k == 1 and (best.instead and T("Навык растёт и от него, а реагенты на шаг пока соберёшь.")
      or (o.sameColor and T("Того же цвета, что рецепт шага, но на него есть реагенты.") or T("Даст навык вернее, чем рецепт шага.")))
      or T("Ещё вариант.")
    local lines = { why }
    if o.cost then tinsert(lines, { T("За создание"), "~" .. W.Money(o.cost) }) end
    if o.chance then tinsert(lines, format(T("Навык растёт не всегда: %s за создание."), o.chance)) end
    if o.cheaperBy then
      tinsert(lines, format(T("Самый дешёвый из рецептов этого цвета: на %s дешевле «%s»."), W.Money(o.cheaperBy), o.cheaperThan or "?"))
    end
    local id = o.id
    local col = ns:Hex(o.color) .. (ns.ColorName[o.color] or "") .. "|r" .. (o.chance and (", " .. o.chance) or "")
    tinsert(rows, { tex = o.icon or ns.Icon(nil), text = ns:Hex(o.color) .. (o.name or "?") .. "|r", sub = col,
      right = (o.cost and (W.Money(o.cost) .. "  ") or "") .. (o.a > 0 and format(T("хватит на %d"), o.a) or (GREY_C .. T("нет реагентов") .. "|r")),
      star = k == 1, hot = k == 1,
      tip = { title = o.name or "?", lines = lines, hint = T("Щелчок откроет его в окне профессии.") },
      onClick = function() ns:OpenRecipe(key, id) end })
  end
  c:Items(rows, 1, 28)
  -- «Создать N» для лучшего - когда на него есть реагенты, а на шаг нет
  if best.a > 0 and best.n > 0 then
    c:Buttons({ { text = format(T("Создать %d: %s"), best.n, best.name or "?"), w = 300,
      tip = format(T("Создаст «%s»: %d шт. (не больше, чем осталось до конца шага)."), best.name or "?", best.n),
      onClick = function() ns:CraftOrOpen(key, best.id, best.n) end } })
  end
end

-- Нечего создавать, а реагенты есть на аукционе: «Найти на аукционе»
-- (открыт) или «В список Auctionator»; без Auctionator - поставить его.
function C:AuctionButton(UI, c, y)
  local b = UI.stepBuy
  if not (b and #b.auction > 0) then return end
  local has = ns:HasAuctionator()
  local open = ns:IsAuctionOpen()
  c:Button({ text = open and T("Найти на аукционе") or T("В список Auctionator"), w = 190, enabled = has,
    tip = has and (open and T("Найдёт недостающие реагенты на аукционе.")
      or T("Добавит недостающие реагенты в список «EasyCraft» в Auctionator: на аукционе останется нажать «Искать»."))
      or T("Нужен аддон Auctionator: через него EasyCraft ищет сразу весь список."),
    onClick = function() ns:SendToAuction(b.auction) end }, UI.PAD, y, true)
  return true
end

-- Кнопка создания справа в нижней строке: одна, «Создать все (N)» - сколько
-- нужно до конца шага. При закрытом окне она сама откроет профессию; для
-- чар и неизвестных рецептов - «Открыть рецепт».
function C:CraftButtons(UI, c, key, s, left, y)
  if ns:RecipeKnown(key, s.spell) == false then
    -- сначала выучить; окно закрыто - может, уже выучил: окно обновит скан
    if not ns:IsProfOpen(key) then
      c:Button({ text = T("Открыть рецепт"), w = 160, onClick = function() ns:OpenRecipe(key, s.spell) end,
        tip = T("Откроет окно профессии. Тогда здесь появятся кнопки создания.") }, UI.PAD, y, true)
      return true
    end
    return false
  end
  local open = ns:IsProfOpen(key)
  local n, tip
  if open then
    local st = ns:RecipeState(key, s.spell)
    if st and not st.unknown and st.known and not st.enchant then n = st.count or 0 end
  elseif key ~= "enchanting" or s.id then
    -- Окно закрыто: считаем по сумкам, кнопка сама откроет профессию.
    n = ns:CanMake(s)
    tip = ns:NoAutoCraft() and T("Откроет окно профессии на этом рецепте.") or T("Откроет окно профессии и сразу начнёт создавать.")
  end
  if not n then
    c:Button({ text = T("Открыть рецепт"), w = 160, onClick = function() ns:OpenRecipe(key, s.spell) end,
      tip = T("Откроет окно профессии. Тогда здесь появятся кнопки создания.") }, UI.PAD, y, true)
    return true
  end
  -- «Создать все» - сколько нужно до конца шага (не больше, чем хватит)
  local all = (left and left > 0) and min(n, left) or n
  -- не из чего - кнопок создания нет: что докупить и чем заняться пока,
  -- видно на карточке выше
  if n <= 0 then return false end
  -- кнопка откроет окно профессии (если закрыто) и начнёт создавать
  c:Button({ text = format(T("Создать все (%d)"), all), w = 190, tip = tip,
    onClick = function() ns:CraftOrOpen(key, s.spell, all) end }, UI.PAD, y, true)
  return true
end
