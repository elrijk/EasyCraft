local _, ns = ...

-------------------------------------------------------------------------------
--  Сколько можно выручить за созданный предмет: аукцион, торговец или
--  распыление. Выгода рецепта считается по самому выгодному способу.
--  Распыление учитывается, только если у персонажа есть наложение чар.
--  Таблица распыления - классическая (по уровню предмета). Сверена с гайдом
--  wow-professions.com/forever/disenchanting-guide (ноябрь 2026): ступени и
--  шансы те же. Выход - среднее, поэтому в подсказке «примерно».
-------------------------------------------------------------------------------
-- до какого уровня предмета, пыль { id, от, до }, субстанция { id, от, до }, осколок
local TIERS = {
  { 15, { 10940, 1, 2 }, { 10938, 1, 2 }, nil },
  { 20, { 10940, 2, 3 }, { 10939, 1, 2 }, 10978 },
  { 25, { 10940, 4, 6 }, { 10998, 1, 2 }, 10978 },
  { 30, { 11083, 1, 2 }, { 11082, 1, 2 }, 11084 },
  { 35, { 11083, 2, 5 }, { 11134, 1, 2 }, 11138 },
  { 40, { 11137, 1, 2 }, { 11135, 1, 2 }, 11139 },
  { 45, { 11137, 2, 5 }, { 11174, 1, 2 }, 11177 },
  { 50, { 11176, 1, 2 }, { 11175, 1, 2 }, 11178 },
  { 55, { 11176, 2, 5 }, { 16202, 1, 2 }, 14343 },
  { 60, { 16204, 1, 2 }, { 16203, 1, 2 }, 14344 },
  { 65, { 16204, 2, 5 }, { 16203, 2, 3 }, 14344 },
}

-- Что даёт распыление: { { id, сколько в среднем, шанс }, ... } или nil.
function ns:DisenchantYield(itemID)
  local name, _, quality, ilvl, _, _, _, _, equipLoc, _, _, classID = C_Item.GetItemInfo(itemID)
  if not name or not ilvl or (classID ~= 2 and classID ~= 4) then return nil end
  if not equipLoc or equipLoc == "" or quality ~= 2 and quality ~= 3 then return nil end
  local tier
  for _, t in ipairs(TIERS) do
    if ilvl <= t[1] then tier = t break end
  end
  if not tier then return nil end
  if quality == 3 then
    return tier[4] and { { tier[4], 1, 1 } } or nil
  end
  -- у оружия чаще субстанция, у брони - пыль
  local dust, ess = 0.75, 0.2
  if classID == 2 then dust, ess = 0.2, 0.75 end
  local shard = tier[4] and 0.05 or 0
  if not tier[4] then dust = dust + 0.05 end
  local out = {
    { tier[2][1], (tier[2][2] + tier[2][3]) / 2, dust },
    { tier[3][1], (tier[3][2] + tier[3][3]) / 2, ess },
  }
  if tier[4] then out[3] = { tier[4], 1, shard } end
  return out
end

-- Средняя выручка с распыления одного предмета или nil (нет цен, не распыляется).
function ns:DisenchantValue(itemID)
  local y = self:DisenchantYield(itemID)
  if not y then return nil end
  local total = 0
  for _, r in ipairs(y) do
    local p = self:AuctionPrice(r[1])
    if not p then return nil end
    total = total + p * r[2] * r[3]
  end
  return math.floor(total)
end

-- Цена продажи торговцу за штуку или nil.
function ns:VendorSellPrice(itemID)
  local sell = select(11, C_Item.GetItemInfo(itemID))
  return type(sell) == "number" and sell > 0 and sell or nil
end

-- Лучшая выручка за одно создание: сумма, способ ("ah", "vendor", "de") и
-- все три суммы { ah, vendor, de }.
function ns:SaleValue(itemID, count)
  if type(itemID) ~= "number" then return nil end
  count = count or 1
  local ah = self:AuctionPrice(itemID)
  local vendor = self:VendorSellPrice(itemID)
  local de = self.char and self.char.profs and self.char.profs.enchanting and self:DisenchantValue(itemID) or nil
  local all = { ah = ah and ah * count, vendor = vendor and vendor * count, de = de and de * count }
  local best, how
  for _, k in ipairs({ "ah", "de", "vendor" }) do
    if all[k] and (not best or all[k] > best) then best, how = all[k], k end
  end
  return best, how, all
end
