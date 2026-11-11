local _, ns = ...

-------------------------------------------------------------------------------
--  Свои цены аукциона. EasyCraft читает их сам, когда игрок открывает
--  аукцион: листает общий список (минимальная цена каждого предмета) и
--  заодно запоминает цены из любых поисков игрока.
--  Хранится в EasyCraftDB.ah[сервер] = { p = { id -> медь за штуку },
--  d = { id -> день, когда видели }, t = время последнего полного обхода }.
--  Других источников цен нет: ни Auctionator, ни TSM аддон не читает. Пока
--  игрок не был на аукционе, цен нет - об этом аддон напоминает (в чате при
--  входе и в окне).
-------------------------------------------------------------------------------
local AH = C_AuctionHouse
local floor, min, time = math.floor, math.min, time

local RESCAN = 15 * 60 -- полный обход не чаще, чем раз в столько секунд
local scan = {}        -- active, n (сколько цен за обход), wait (ждём очередь)
local batch = {}       -- предметы, уже встреченные в текущем списке
local dirty

local function today() return floor(time() / 86400) end

local function store()
  local db = ns.db
  if not db then return nil end
  db.ah = db.ah or {}
  local realm = (GetRealmName and GetRealmName()) or "?"
  local s = db.ah[realm]
  if not s then s = { p = {}, d = {} } db.ah[realm] = s end
  s.p, s.d = s.p or {}, s.d or {}
  return s
end

function ns:CanScanAuction()
  return type(AH) == "table" and type(AH.SendBrowseQuery) == "function"
    and type(AH.GetBrowseResults) == "function" or false
end

-- Есть ли хоть одна своя цена.
function ns:HasOwnPrices()
  local s = store()
  return s and next(s.p) ~= nil or false
end

local function refreshSoon()
  if dirty then return end
  dirty = true
  local function run() dirty = nil ns:Safe(ns.RefreshAll, ns) end
  C_Timer.After(0.5, run)
end

-- Запомнить цену. exact - точная (поиск одного предмета), иначе в пределах
-- одного списка берём меньшую: у предмета бывает несколько строк (суффиксы).
local function note(id, price, exact)
  if type(id) ~= "number" or type(price) ~= "number" or price <= 0 then return end
  local s = store()
  if not s then return end
  if not exact and batch[id] and s.p[id] then s.p[id] = min(s.p[id], price) else s.p[id] = price end
  batch[id] = true
  s.d[id] = today()
  scan.n = (scan.n or 0) + 1
end

local function harvest(list)
  if type(list) ~= "table" then return end
  for _, r in ipairs(list) do
    if type(r) == "table" and type(r.itemKey) == "table" and (r.totalQuantity or 1) > 0 then
      note(r.itemKey.itemID, r.minPrice)
    end
  end
  refreshSoon()
end

local function ready()
  if type(AH.IsThrottledMessageSystemReady) ~= "function" then return true end
  local ok, r = pcall(AH.IsThrottledMessageSystemReady)
  return not ok or r
end

local function finish(done)
  if not scan.active then return end
  scan.active, scan.wait = nil, nil
  local s = store()
  if done and s then s.t = time() end
  if (scan.n or 0) > 0 then
    ns:Print(format(ns.T("цены аукциона прочитаны, предметов: %d."), scan.n))
  end
  refreshSoon()
end

-- Следующий шаг обхода: отправить запрос или попросить следующую страницу.
local function step()
  if not scan.active then return end
  if not ready() then scan.wait = true return end
  scan.wait = nil
  if not scan.sent then
    scan.sent = true
    local ok = pcall(AH.SendBrowseQuery, { searchString = "", sorts = {}, filters = {}, itemClassFilters = {} })
    if not ok then finish(false) end
    return
  end
  local okFull, full = pcall(AH.HasFullBrowseResults)
  if not okFull or full or type(AH.RequestMoreBrowseResults) ~= "function" then return finish(true) end
  if not pcall(AH.RequestMoreBrowseResults) then finish(true) end
end

-- Начать обход. force - по команде игрока, не глядя на паузу.
function ns:ScanAuction(force)
  if not self:CanScanAuction() then
    if force then self:Print(ns.T("этот клиент не даёт читать аукцион.")) end
    return false
  end
  if not self.ahOpen then
    if force then self:Print(ns.T("открой аукцион: цены читаются там.")) end
    return false
  end
  if scan.active then return true end
  if not force then
    if self.settings and self.settings.ahScan == false then return false end
    local s = store()
    if s and s.t and time() - s.t < RESCAN then return false end
  end
  scan = { active = true, n = 0 }
  batch = {}
  if force then self:Print(ns.T("читаю цены аукциона...")) end
  step()
  return true
end

-- Идёт ли обход и сколько цен уже прочитано.
function ns:AuctionScanState() return scan.active or false, scan.n or 0 end

local ev = CreateFrame("Frame")
for _, e in ipairs({
  "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "AUCTION_HOUSE_THROTTLED_SYSTEM_READY",
  "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_ADDED", "AUCTION_HOUSE_BROWSE_FAILURE",
  "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED",
}) do pcall(ev.RegisterEvent, ev, e) end

local function onEvent(e, a)
  if e == "AUCTION_HOUSE_SHOW" then
    ns.ahOpen = true
    local function go() if ns.ahOpen then ns:ScanAuction() end end
    C_Timer.After(1, go)
  elseif e == "AUCTION_HOUSE_CLOSED" then
    ns.ahOpen = nil
    finish(false)
  elseif e == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
    if scan.active and scan.wait then step() end
  elseif e == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then
    if not scan.active then batch = {} end
    local ok, list = pcall(AH.GetBrowseResults)
    if ok then harvest(list) end
    step()
  elseif e == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
    harvest(a)
    step()
  elseif e == "AUCTION_HOUSE_BROWSE_FAILURE" then
    finish(false)
  elseif e == "COMMODITY_SEARCH_RESULTS_UPDATED" then
    if type(a) == "number" and AH.GetCommoditySearchResultInfo then
      local ok, r = pcall(AH.GetCommoditySearchResultInfo, a, 1)
      if ok and type(r) == "table" then note(a, r.unitPrice, true) refreshSoon() end
    end
  elseif e == "ITEM_SEARCH_RESULTS_UPDATED" then
    if type(a) == "table" and a.itemID and AH.GetNumItemSearchResults and AH.GetItemSearchResultInfo then
      local ok, n = pcall(AH.GetNumItemSearchResults, a)
      local best
      for i = 1, min(ok and tonumber(n) or 0, 50) do
        local ok2, r = pcall(AH.GetItemSearchResultInfo, a, i)
        local price = ok2 and type(r) == "table" and r.buyoutAmount
        if type(price) == "number" and price > 0 and (not best or price < best) then best = price end
      end
      if best then note(a.itemID, best, true) refreshSoon() end
    end
  end
end
ev:SetScript("OnEvent", function(_, e, a) if type(AH) == "table" then ns:Safe(onEvent, e, a) end end)

-------------------------------------------------------------------------------
--  Источник цен для остального аддона.
-------------------------------------------------------------------------------
-- Есть ли цены: "EasyCraft" или nil (на аукционе ещё не были).
function ns:PriceSource()
  return self:HasOwnPrices() and "EasyCraft" or nil
end

-- Цена одной штуки в меди и сколько дней назад её видели.
function ns:AuctionPrice(id)
  if type(id) ~= "number" then return nil end
  local s = store()
  local own = s and s.p[id]
  if not own then return nil end
  local age = today() - (s.d[id] or 0)
  return own, age < 0 and 0 or age
end

-- Пора ли на аукцион: "none" - цен нет вовсе, "old" - последний обход
-- старше PRICE_OLD_DAYS дней, nil - цены свежие (или клиент не даёт читать).
function ns:PricesStale()
  if not self:CanScanAuction() then return nil end
  local s = store()
  if not (s and s.t) then return "none" end
  if time() - s.t > (self.PRICE_OLD_DAYS or 3) * 86400 then return "old" end
end

-- Строка-напоминание для окна (или nil).
function ns:PricesNote()
  local st = self:PricesStale()
  if st == "none" then return ns.T("Цен нет: открой аукцион - EasyCraft прочитает их сам") end
  if st == "old" then return format(ns.T("Цены старше %d дней: открой аукцион - EasyCraft обновит их сам"), self.PRICE_OLD_DAYS or 3) end
end

-- При входе, один раз: напомнить в чате сходить на аукцион (только тем, у
-- кого есть профессии, где что-то покупают).
local remind = CreateFrame("Frame")
remind:RegisterEvent("PLAYER_ENTERING_WORLD")
remind:SetScript("OnEvent", function(self)
  self:UnregisterAllEvents()
  C_Timer.After(12, function()
    if not (ns.db and ns.char and ns.LearnedList) then return end
    if #ns:LearnedList() == 0 then return end
    local st = ns:PricesStale()
    if st == "none" then
      ns:Print(ns.T("цен аукциона пока нет: загляни на аукцион - EasyCraft прочитает их сам, и покупки с выгодой будут с ценами."))
    elseif st == "old" then
      ns:Print(format(ns.T("цены аукциона старше %d дней: загляни на аукцион - EasyCraft обновит их сам."), ns.PRICE_OLD_DAYS or 3))
    end
  end)
end)
