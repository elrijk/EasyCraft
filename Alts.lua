local _, TJ = ...

-------------------------------------------------------------------------------
--  Реагенты у других персонажей из Syndicator (Baganator). Если его нет,
--  работает прежний подсчёт по BagBrother (Core.lua).
--  Syndicator отвечает по одному предмету, поэтому таблица заполняется по
--  мере обращений: alts[id] -> сколько лежит у альтов (сумки, банк, почта).
-------------------------------------------------------------------------------
local fromBagBrother = TJ.AltCounts

local function syndicator()
  local api = _G.Syndicator and _G.Syndicator.API
  if not (api and api.GetInventoryInfoByItemID) then return nil end
  if api.IsReady and not api.IsReady() then return nil end
  return api
end

function TJ:AltSource()
  if syndicator() then return "Syndicator" end
  if type(_G.BrotherBags) == "table" then return "BagBrother" end
end

function TJ:AltCounts()
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
