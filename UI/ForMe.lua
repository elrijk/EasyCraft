local _, TJ = ...
local C, T = TJ.Content, TJ.T
local W = TJ.W

-------------------------------------------------------------------------------
--  «Что создать себе сейчас» (вкладка «Рецепты»): из выученных рецептов -
--  вещи лучше надетых и расходники под уровень персонажа.
--  Вещь лучше, если её уровень предмета выше, чем у надетой в том же месте,
--  персонаж может её носить (тип брони по классу) и подходит по уровню.
-------------------------------------------------------------------------------
local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local MAX_ROWS = 6

-- куда надевается: место в игре -> ячейки персонажа
local SLOTS = {
  INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
  INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
  INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
  INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
  INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
  INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 },
}

-- броня: подкласс предмета (1 ткань, 2 кожа, 3 кольчуга, 4 латы, 6 щит) ->
-- с какого уровня класс её носит
local ARMOR = {
  WARRIOR = { [1] = 1, [2] = 1, [3] = 1, [4] = 40, [6] = 1 },
  PALADIN = { [1] = 1, [2] = 1, [3] = 1, [4] = 40, [6] = 1 },
  HUNTER = { [1] = 1, [2] = 1, [3] = 40 },
  SHAMAN = { [1] = 1, [2] = 1, [3] = 40, [6] = 1 },
  ROGUE = { [1] = 1, [2] = 1 },
  DRUID = { [1] = 1, [2] = 1 },
  MAGE = { [1] = 1 }, PRIEST = { [1] = 1 }, WARLOCK = { [1] = 1 },
}

local function itemLevelOf(link)
  if not (link and GetInfo) then return nil end
  local ok, _, _, _, ilvl = pcall(GetInfo, link)
  return ok and tonumber(ilvl) or nil
end

-- Насколько вещь лучше надетой (в уровнях предмета) или nil.
local function upgrade(out, level, class)
  local ok, name, _, quality, ilvl, reqLevel, _, _, _, equipLoc, _, _, classID, subID = pcall(GetInfo, out)
  if not ok or not name then return nil end
  local slots = equipLoc and SLOTS[equipLoc]
  if not slots or not ilvl then return nil end
  if (reqLevel or 0) > level then return nil end
  if classID == 4 and subID and subID >= 1 and subID <= 6 and subID ~= 5 then
    local from = ARMOR[class] and ARMOR[class][subID]
    if not from or level < from then return nil end
  end
  -- сравниваем с худшей из подходящих ячеек (кольца, аксессуары)
  local worst
  for _, slot in ipairs(slots) do
    local link = GetInventoryItemLink and GetInventoryItemLink("player", slot)
    local have = link and itemLevelOf(link) or 0
    if not worst or have < worst then worst = have end
  end
  local gain = ilvl - (worst or 0)
  if gain <= 0 then return nil end
  return gain, quality, worst
end

-- Расходник под уровень: зелья, еда, бинты (класс предметов 0).
local function consumable(out, level)
  local ok, name, _, _, _, reqLevel, _, _, _, _, _, _, classID = pcall(GetInfo, out)
  if not ok or not name or classID ~= 0 then return false end
  reqLevel = reqLevel or 0
  return reqLevel <= level and reqLevel >= level - 12
end

function TJ:CraftForMe()
  local level = UnitLevel and UnitLevel("player") or 1
  local _, class = UnitClass("player")
  local gear, use, seen = {}, {}, {}
  for _, key in ipairs(self:LearnedList()) do
    local known = self:BookList(key)
    for _, e in ipairs(known) do
      if e.out and not seen[e.out] then
        seen[e.out] = true
        local gain, _, worst = upgrade(e.out, level, class)
        if gain then
          gear[#gear + 1] = { e = e, key = key, gain = gain, worst = worst }
        elseif (e.can or 0) > 0 and consumable(e.out, level) then
          use[#use + 1] = { e = e, key = key }
        end
      end
    end
  end
  table.sort(gear, function(a, b) return a.gain > b.gain end)
  return gear, use
end

function C:ForMeCard(UI)
  local ok, gear, use = pcall(TJ.CraftForMe, TJ)
  if not ok or (#gear == 0 and #use == 0) then return end
  local c = UI:Card()
  c:Head({ ring = "Interface\\Icons\\INV_Chest_Chain_05" }, T("Что создать себе сейчас"),
    { { T("Вещи лучше надетых и расходники под твой уровень. Щелчок добавит в очередь."), "small" } }, 32)
  local rows = {}
  local function add(x, sub, right)
    if #rows >= MAX_ROWS then return end
    local e = x.e
    rows[#rows + 1] = { id = e.out, tex = e.icon, text = e.name or "?", sub = sub, right = right,
      onClick = function()
        TJ:QueueAdd(x.key, e.spell, 1)
        UI:Render(true)
      end }
  end
  for _, x in ipairs(gear) do
    local sub = x.worst > 0 and format(T("Уровень предмета выше надетого на %d"), x.gain) or T("Ячейка пустая")
    if (x.e.can or 0) > 0 then sub = sub .. ", |cff33dd33" .. T("реагенты есть") .. "|r" end
    add(x, sub, x.e.cost and W.Money(x.e.cost) or nil)
  end
  for _, x in ipairs(use) do
    add(x, "|cff33dd33" .. format(T("хватит на %d"), x.e.can) .. "|r", nil)
  end
  c:Items(rows, 1, 28)
  UI:End(c)
end
