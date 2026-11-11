local _, ns = ...

-------------------------------------------------------------------------------
--  Реагенты у других персонажей из Syndicator (Baganator). Если его нет -
--  из BagBrother (Core.lua), а без обоих - свой учёт (ниже).
--  Syndicator отвечает по одному предмету, поэтому таблица заполняется по
--  мере обращений: alts[id] -> сколько лежит у альтов (сумки, банк, почта).
-------------------------------------------------------------------------------
local fromBagBrother = ns.AltCounts

local function syndicator()
  local api = _G.Syndicator and _G.Syndicator.API
  if not (api and api.GetInventoryInfoByItemID) then return nil end
  if api.IsReady and not api.IsReady() then return nil end
  return api
end

function ns:AltSource()
  if syndicator() then return "Syndicator" end
  if type(_G.BrotherBags) == "table" then return "BagBrother" end
end

function ns:AltCounts()
  if self.altCache then return self.altCache end
  local api = syndicator()
  if not api then return fromBagBrother(self) end
  local me = UnitName("player")
  local realm = GetNormalizedRealmName and GetNormalizedRealmName() or nil
  local out = setmetatable({}, { __index = function(t, id)
    local n = 0
    local ok, info = pcall(api.GetInventoryInfoByItemID, id, true, true)
    if ok and type(info) == "table" and type(info.characters) == "table" then
      for _, c in ipairs(info.characters) do
        local mine = c.character == me and (not realm or not c.realmNormalized or c.realmNormalized == realm)
        if not mine then n = n + (c.bags or 0) + (c.bank or 0) + (c.mail or 0) end
      end
    end
    rawset(t, id, n)
    return n
  end })
  self.altCache = out
  return out
end

-------------------------------------------------------------------------------
--  Свой учёт альтов: работает без других аддонов. Каждый персонаж при входе,
--  выходе и у банка записывает, что у него лежит, в общий EasyCraftDB.alts:
--  alts[сервер][имя] = { bags = { id -> шт }, bank = { ... }, mail = { ... } }.
--  Syndicator и BagBrother, если стоят, остаются главнее: они знают и тех
--  персонажей, на которых EasyCraft ещё не заходил.
-------------------------------------------------------------------------------
local function ownStore()
  local db = ns.db
  if not db then return nil end
  db.alts = db.alts or {}
  local realm = (GetRealmName and GetRealmName()) or "?"
  db.alts[realm] = db.alts[realm] or {}
  return db.alts[realm]
end

local function countBags(list)
  local out = {}
  local CC = C_Container
  if not (CC and CC.GetContainerNumSlots and CC.GetContainerItemInfo) then return out end
  for _, bag in ipairs(list) do
    local ok, n = pcall(CC.GetContainerNumSlots, bag)
    for slot = 1, ok and tonumber(n) or 0 do
      local ok2, info = pcall(CC.GetContainerItemInfo, bag, slot)
      if ok2 and type(info) == "table" and info.itemID then
        out[info.itemID] = (out[info.itemID] or 0) + (info.stackCount or 1)
      end
    end
  end
  return out
end

-- Номера сумок: свои (с сумкой реагентов) и банка (старый банк или вкладки).
local function bagLists()
  local bags, bank, seen = { 0, 1, 2, 3, 4 }, { -1 }, { [-1] = true }
  local idx = type(Enum) == "table" and Enum.BagIndex
  if type(idx) == "table" then
    if type(idx.ReagentBag) == "number" then bags[#bags + 1] = idx.ReagentBag end
    for k, v in pairs(idx) do
      if type(k) == "string" and type(v) == "number" and k:find("Bank") and not k:find("Account")
        and not seen[v] then
        seen[v] = true
        bank[#bank + 1] = v
      end
    end
  else
    for b = 5, 11 do bank[#bank + 1] = b end
  end
  return bags, bank
end

function ns:SaveOwnItems(withBank)
  local s, me = ownStore(), UnitName and UnitName("player")
  if not (s and me) then return end
  local rec = s[me] or {}
  s[me] = rec
  local bags, bank = bagLists()
  rec.bags = countBags(bags)
  if withBank then rec.bank = countBags(bank) end
  rec.mail = self.char and self.char.mail or rec.mail
  rec.t = time()
end

local function ownCounts()
  local out = {}
  local s, me = ownStore(), UnitName and UnitName("player")
  if not s then return out end
  for name, rec in pairs(s) do
    if name ~= me and type(rec) == "table" then
      for _, part in ipairs({ "bags", "bank", "mail" }) do
        if type(rec[part]) == "table" then
          for id, n in pairs(rec[part]) do
            if type(n) == "number" then out[id] = (out[id] or 0) + n end
          end
        end
      end
    end
  end
  return out
end

local viaAddons, addonSource = ns.AltCounts, ns.AltSource

function ns:AltSource() return addonSource(self) or "EasyCraft" end

local NO_ALTS = {}
function ns:AltCounts()
  -- в настройках выключено: чужие сумки не считаем
  if self.settings and self.settings.useAlts == false then return NO_ALTS end
  if addonSource(self) then return viaAddons(self) end
  if self.altCache then return self.altCache end
  self.altCache = ownCounts()
  return self.altCache
end

local ownEv = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_LOGOUT", "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "BAG_UPDATE_DELAYED" }) do
  pcall(ownEv.RegisterEvent, ownEv, e)
end
local bankOpen
local function later(sec, withBank)
  local function run() pcall(ns.SaveOwnItems, ns, withBank and bankOpen) end
  C_Timer.After(sec, run)
end
-- Банк читается, только пока он открыт: записываем при открытии и при
-- перекладывании, а при закрытии - уже нет.
ownEv:SetScript("OnEvent", function(_, e)
  if e == "PLAYER_ENTERING_WORLD" then later(5)
  elseif e == "BANKFRAME_OPENED" then bankOpen = true later(0.5, true)
  elseif e == "BANKFRAME_CLOSED" then bankOpen = nil
  elseif e == "BAG_UPDATE_DELAYED" then if bankOpen then later(0.2, true) end
  else pcall(ns.SaveOwnItems, ns) end
end)
