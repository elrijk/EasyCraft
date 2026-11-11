local _, ns = ...

-------------------------------------------------------------------------------
--  Reagents on the player's other characters.
--  Each character writes what it holds into the shared EasyCraftDB.alts on
--  login, on logout and at the bank:
--  alts[realm][name] = { bags = { id -> count }, bank = { ... }, mail = { ... } }.
--  A character is known only after it has logged in with EasyCraft enabled.
-------------------------------------------------------------------------------
local function ownStore()
  local db = ns.db
  if not db then return nil end
  db.alts = db.alts or {}
  local realm = GetRealmName() or "?"
  db.alts[realm] = db.alts[realm] or {}
  return db.alts[realm]
end

local function countBags(list)
  local out = {}
  local CC = C_Container
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

-- Bag numbers: the character's own bags (with the reagent bag) and the bank
-- (the old bank container or the bank tabs, whichever the client has).
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
  local s, me = ownStore(), UnitName("player")
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
  local s, me = ownStore(), UnitName("player")
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

-- id -> how many the other characters hold. Built once per session: other
-- characters cannot change while this one is logged in.
local NO_ALTS = {}
function ns:AltCounts()
  -- turned off in the settings: other characters are not counted
  if self.settings and self.settings.useAlts == false then return NO_ALTS end
  if not self.altCache then self.altCache = ownCounts() end
  return self.altCache
end

local ownEv = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_LOGOUT", "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "BAG_UPDATE_DELAYED" }) do
  ownEv:RegisterEvent(e)
end
local bankOpen
local function later(sec, withBank)
  local function run() pcall(ns.SaveOwnItems, ns, withBank and bankOpen) end
  C_Timer.After(sec, run)
end
-- The bank can be read only while it is open: save on opening and on every
-- move of items, but not on closing.
ownEv:SetScript("OnEvent", function(_, e)
  if e == "PLAYER_ENTERING_WORLD" then later(5)
  elseif e == "BANKFRAME_OPENED" then bankOpen = true later(0.5, true)
  elseif e == "BANKFRAME_CLOSED" then bankOpen = nil
  elseif e == "BAG_UPDATE_DELAYED" then if bankOpen then later(0.2, true) end
  else pcall(ns.SaveOwnItems, ns) end
end)
