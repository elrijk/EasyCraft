local ADDON, TJ = ...
local format = string.format

local ev = CreateFrame("Frame")
TJ.eventFrame = ev
local handlers = {}

local function on(event, fn)
  handlers[event] = fn
  pcall(ev.RegisterEvent, ev, event) -- unknown events must not break loading
end
ev:SetScript("OnEvent", function(_, event, ...)
  local fn = handlers[event]
  if fn then TJ:Safe(fn, ...) end
end)

local function after(sec, fn)
  if C_Timer and C_Timer.After then C_Timer.After(sec, fn) else fn() end
end

-- throttled helpers
local scheduled = {}
local function throttle(name, sec, fn)
  if scheduled[name] then return end
  scheduled[name] = true
  after(sec, function() scheduled[name] = nil; TJ:Safe(fn) end)
end

---------------------------------------------------------------------------
-- Login
---------------------------------------------------------------------------
on("ADDON_LOADED", function(name)
  if name == "Blizzard_WorldMap" and TJ.ready and TJ.MapOverlay then TJ.MapOverlay:Init() end
  if name ~= ADDON then return end
  TJ:InitDB()
  TJ:BuildLookups()
  if TJ.BuildSettings then TJ:Safe(TJ.BuildSettings, TJ) end
end)

on("PLAYER_LOGIN", function()
  if not TJ.db then TJ:InitDB(); TJ:BuildLookups() end
  if TJ.ApplyRealReagents then TJ:Safe(TJ.ApplyRealReagents, TJ) end -- реагенты, которые игра показала другими
  TJ:ResolveMaps()
  TJ:ScanSkills()
  TJ.ready = true
  if TJ.CreateMinimapButton then TJ:Safe(TJ.CreateMinimapButton, TJ) end
  if TJ.MapOverlay then TJ:Safe(TJ.MapOverlay.Init, TJ.MapOverlay) end
  if TJ.Tracker then TJ:Safe(TJ.Tracker.Init, TJ.Tracker) end
  if TJ.HookPriceUpdates then TJ:Safe(TJ.HookPriceUpdates, TJ) end
  if TJ.HookItemTooltips then TJ:Safe(TJ.HookItemTooltips, TJ) end
  if TJ.HookNodeTooltips then TJ:Safe(TJ.HookNodeTooltips, TJ) end
  TJ:RegisterRefresh(function() if TJ.UpdateMerchantButton then TJ:UpdateMerchantButton() end end)
  -- Один раз на учётную запись: где открыть аддон.
  if not TJ.db.introDone and not TJ.db.introHinted then
    TJ.db.introHinted = true
    after(5, function()
      TJ:Print(TJ.T("покажу, что качать в профессиях. Открыть - книга у миникарты или /ec."))
    end)
  end
end)

-- Торговец: кнопка «купить для шагов» под его окном.
for _, e in ipairs({ "MERCHANT_SHOW", "MERCHANT_UPDATE", "MERCHANT_CLOSED" }) do
  on(e, function() throttle("merchant", 0.2, function()
    TJ.needCache = nil
    if e ~= "MERCHANT_CLOSED" then TJ:Safe(TJ.RecordMerchantPrices, TJ) end
    TJ:UpdateMerchantButton()
  end) end)
end

-- Аукцион открыт или закрыт: кнопка «Найти на аукционе» меняет вид.
for _, e in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED" }) do
  on(e, function() TJ:RefreshAll() end)
end

on("PLAYER_ENTERING_WORLD", function()
  after(2, function() TJ:Safe(TJ.ScanSkills, TJ) end)
end)
on("SKILL_LINES_CHANGED", function() throttle("skills", 0.5, function() TJ:ScanSkills() end) end)
on("CHAT_MSG_SKILL", function() throttle("skills", 0.5, function() TJ:ScanSkills() end) end)
on("LEARNED_SPELL_IN_TAB", function() throttle("skills", 1, function() TJ:ScanSkills() end) end)

-- Выучил рецепт (у учителя или из предмета-рецепта): отметить его в скане
-- окна профессии, чтобы карточка сразу перестала звать к учителю.
on("NEW_RECIPE_LEARNED", function(id)
  if type(id) ~= "number" then return end
  for key in pairs(TJ.Profs) do
    local sc = TJ.char.scan[key]
    local s = TJ:SpellStep(key, id)
    if s and sc and sc.colors and sc.colors[id] == nil then
      local col = s.sk and TJ:RecipeColor(s, TJ:GetSkill(key))
      sc.colors[id] = (TJ.COLOR_BY_D and ({ orange = 0, yellow = 1, green = 2, gray = 3 })[col or ""]) or 0
    end
  end
  TJ:RefreshAll()
end)

-- Своё создание предмета прошло (окно профессии открыто): сумки сейчас
-- уменьшатся раньше, чем вырастет навык - подержать перерисовку.
on("UNIT_SPELLCAST_SUCCEEDED", function(unit)
  if unit == "player" and TJ.openKey then TJ:HoldForSkill() end
end)
-- только свои заклинания, а не каждого вокруг (в городе - сотни в секунду)
if ev.RegisterUnitEvent then
  pcall(ev.UnregisterEvent, ev, "UNIT_SPELLCAST_SUCCEEDED")
  if not pcall(ev.RegisterUnitEvent, ev, "UNIT_SPELLCAST_SUCCEEDED", "player") then
    pcall(ev.RegisterEvent, ev, "UNIT_SPELLCAST_SUCCEEDED")
  end
end
on("BAG_UPDATE_DELAYED", function() throttle("bags", 0.5, function() TJ:RefreshAll() end) end)
-- Сервер прислал сведения о предмете: перерисовать, только если это
-- предмет, который аддон сам ждал (а не любой из поиска на аукционе).
on("GET_ITEM_INFO_RECEIVED", function(id, ok)
  if not (id and TJ.wantItem and TJ.wantItem[id]) then return end
  TJ.wantItem[id] = nil
  if ok == false then return end -- такого предмета нет: рисовать нечего
  TJ.itemGen = (TJ.itemGen or 0) + 1 -- карта: названия своих точек
  throttle("items", 0.4, function() TJ:RefreshAll() end)
end)

---------------------------------------------------------------------------
-- Profession window scan: which recipes currently give skill
---------------------------------------------------------------------------
local DIFF = { optimal = 0, medium = 1, easy = 2, trivial = 3, difficult = 0 }
local function normDiff(d)
  if type(d) == "number" then return d end
  return DIFF[d or ""]
end

-- Чужая профессия: ссылка из чата, список гильдии, ремесленник-NPC.
-- Её навык и рецепты не наши, записывать их нельзя.
function TJ:IsForeignTradeSkill(isCraft)
  local api = C_TradeSkillUI
  if api then
    for _, fn in ipairs({ "IsTradeSkillLinked", "IsTradeSkillGuild", "IsTradeSkillGuildMember", "IsNPCCrafting" }) do
      if api[fn] then
        local ok, v = pcall(api[fn])
        if ok and v then return true end
      end
    end
  end
  if not isCraft and IsTradeSkillLinked then
    local ok, v = pcall(IsTradeSkillLinked)
    if ok and v then return true end
  end
  return false
end

-- Одинаковы ли «сколько можно сделать» двух сканов.
local function sameCounts(a, b)
  if a == b then return true end
  if not (a and b) then return false end
  for k, v in pairs(a) do if b[k] ~= v then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end
local routeSig = {} -- профессия -> «навык:рецептов» последней сверки маршрута

function TJ:ScanTradeSkill(isCraft)
  if self:IsForeignTradeSkill(isCraft) then
    self.openKey = nil
    if self.Tracker and self.Tracker.Detach then self.Tracker:Detach() end
    self:RefreshAll()
    return
  end
  local profName, rank, maxRank
  local list, colors, avail = {}, {}, {}
  local ncolors = 0
  -- colors: цвет каждого выученного рецепта (по id), для «лучшего рецепта»;
  -- avail: сколько каждого можно сделать (список ниже режется до 40)
  local function add(name, diff, num, icon, id)
    local d = normDiff(diff)
    if id and d then colors[id] = d; ncolors = ncolors + 1 end
    if id and num then avail[id] = num end
    if name and d and d <= 2 then tinsert(list, { n = name, d = d, a = num or 0, i = icon, id = id }) end
  end

  if isCraft and GetCraftDisplaySkillLine and GetNumCrafts then
    profName, rank, maxRank = GetCraftDisplaySkillLine()
    for i = 1, GetNumCrafts() or 0 do
      local name, _, kind, num = GetCraftInfo(i)
      if kind ~= "header" then add(name, kind, num, GetCraftIcon and GetCraftIcon(i)) end
    end
  end

  if not profName and C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs then
    local info = C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo()
    if info and info.professionName then
      profName, rank, maxRank = info.professionName, info.skillLevel, info.maxSkillLevel
    end
    if not profName and C_TradeSkillUI.GetTradeSkillLine then
      local _, n, r, m = C_TradeSkillUI.GetTradeSkillLine()
      profName, rank, maxRank = n, r, m
    end
    local ids = C_TradeSkillUI.GetAllRecipeIDs() or {}
    for _, id in ipairs(ids) do
      local r = C_TradeSkillUI.GetRecipeInfo(id)
      if r and r.learned ~= false and r.type ~= "header" and r.type ~= "subheader" then
        add(r.name, r.relativeDifficulty or r.difficulty, r.numAvailable, r.icon, id)
      end
    end
  end

  if (not profName or #list == 0) and GetTradeSkillLine and GetNumTradeSkills then
    local n, r, m = GetTradeSkillLine()
    if n and n ~= "UNKNOWN" then
      profName, rank, maxRank = n, r, m
      wipe(list)
      for i = 1, GetNumTradeSkills() or 0 do
        local name, kind, num = GetTradeSkillInfo(i)
        if kind and kind ~= "header" and kind ~= "subheader" then
          add(name, kind, num, GetTradeSkillIcon and GetTradeSkillIcon(i))
        end
      end
    end
  end

  local key = profName and (self.NameToKey[profName] or self.NameToKey[self.Lower(profName)])
  if not key then return end
  table.sort(list, function(a, b) if a.d ~= b.d then return a.d < b.d end return a.n < b.n end)
  while #list > 40 do tremove(list) end
  -- Реагенты рецептов - чтобы «лучший рецепт» мог сравнить цены.
  if self.RecipeReagents then
    for _, r in ipairs(list) do
      if r.id then r.rc = self:RecipeReagents(r.id) end
    end
  end
  local prev = self.char.scan[key]
  -- ничего не поменялось (тот же навык и столько же можно сделать) - не
  -- перерисовываем: сумки и так перерисуют по BAG_UPDATE_DELAYED
  local same = prev and self.openKey == key and prev.rank == rank and prev.max == maxRank
    and sameCounts(prev.avail, next(avail) and avail or nil)
  self.char.scan[key] = { t = time(), list = list, rank = rank, max = maxRank, colors = next(colors) and colors or nil,
    avail = next(avail) and avail or nil }
  -- сверка маршрута с игрой: только когда сменился навык или число рецептов
  local sig = tostring(rank) .. ":" .. ncolors
  if ncolors > 0 and self.CheckRoute and routeSig[key] ~= sig then
    routeSig[key] = sig
    self:Safe(self.CheckRoute, self, key, colors, rank)
  end
  self.openKey = key
  if self.Tracker and self.Tracker.Attach then self.Tracker:Attach(key) end
  self:SetSkillFromWindow(key, rank, maxRank)
  if self.FlushPendingLink then self:FlushPendingLink() end
  if not same then self:RefreshAll() end
end

-- Окно профессии открыто? Скан, назначенный до закрытия, после закрытия не
-- делаем: иначе «Создать» решит, что окно открыто, а скан затрётся пустым.
local tradeOpen, craftOpen = false, false
local function windowShown(names)
  for _, n in ipairs(names) do
    local f = _G[n]
    if type(f) == "table" and f.IsShown and f:IsShown() then return true end
  end
  return false
end
local TRADE_FRAMES, CRAFT_FRAMES = { "ProfessionsFrame", "TradeSkillFrame" }, { "CraftFrame" }
for _, e in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED" }) do
  on(e, function()
    if e == "TRADE_SKILL_SHOW" then tradeOpen = true end
    throttle("trade", 0.4, function()
      if tradeOpen or windowShown(TRADE_FRAMES) then TJ:ScanTradeSkill(false) end
    end)
  end)
end
for _, e in ipairs({ "TRADE_SKILL_CLOSE", "CRAFT_CLOSE" }) do
  on(e, function()
    if e == "CRAFT_CLOSE" then craftOpen = false else tradeOpen = false end
    TJ.openKey = nil
    -- окно закрыли раньше, чем начали создавать: само потом не начнём
    if TJ.pendingCraft and GetTime() - TJ.pendingCraft.t > 2 then TJ.pendingCraft = nil end
    if TJ.Tracker and TJ.Tracker.Detach then TJ.Tracker:Detach() end
    TJ:RefreshAll()
  end)
end
for _, e in ipairs({ "CRAFT_SHOW", "CRAFT_UPDATE" }) do
  on(e, function()
    if e == "CRAFT_SHOW" then craftOpen = true end
    throttle("craft", 0.4, function()
      if craftOpen or windowShown(CRAFT_FRAMES) then TJ:ScanTradeSkill(true) end
    end)
  end)
end

---------------------------------------------------------------------------
-- Gathering journal (idea from Gather Together): what you loot from nodes,
-- skinning and fishing, per zone, plus node positions for the world map.
---------------------------------------------------------------------------
function TJ:PlayerPosition()
  if not (C_Map and C_Map.GetBestMapForUnit) then return end
  local mapID = C_Map.GetBestMapForUnit("player")
  if not mapID then return end
  local pos = C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(mapID, "player")
  if not pos then return mapID end
  local x, y = pos:GetXY()
  return mapID, x, y
end

function TJ:AddNode(mapID, x, y, key)
  if not (mapID and x and y and x > 0 and y > 0) then return end
  self.nodeGen = (self.nodeGen or 0) + 1 -- карта: свои находки изменились
  local list = self.db.nodes[mapID] or {}
  self.db.nodes[mapID] = list
  for _, n in ipairs(list) do
    if n[3] == key and (n[1] - x) ^ 2 + (n[2] - y) ^ 2 < 0.00004 then
      n[4] = (n[4] or 1) + 1
      n[5] = time()
      return
    end
  end
  tinsert(list, { x, y, key, 1, time() })
end

local function bump(t, k, n) t[k] = (t[k] or 0) + n end

local lootDone = false
on("LOOT_CLOSED", function() lootDone = false end)
-- Чертежи лагеря: id -> true (собираем из данных один раз).
local bpSet
local function isBlueprint(id)
  if not bpSet then
    bpSet = {}
    for _, p in pairs(TJ.Profs) do
      for _, e in ipairs(p.camp or {}) do if e.bp then bpSet[e.bp] = true end end
    end
  end
  return bpSet[id]
end

-- Чертёж выпал: запомнить, с кого и где (у части чертежей источник пока
-- никому не известен - так он станет известен хотя бы тебе).
local function rememberBlueprint(id, slot)
  local who
  if UnitExists and UnitExists("target") and UnitIsDead and UnitIsDead("target") then who = UnitName("target") end
  local where = GetInstanceInfo and select(1, GetInstanceInfo()) or nil
  local zone = GetRealZoneText and GetRealZoneText() or nil
  if not where or where == "" or (IsInInstance and not IsInInstance()) then where = zone end
  local mapID, x, y = TJ:PlayerPosition()
  TJ.db.bpFound = TJ.db.bpFound or {}
  TJ.db.bpFound[id] = { who = who, where = where, map = mapID, x = x and x * 100, y = y and y * 100, t = time() }
end

local function onLoot()
  if lootDone then return end
  local numItems = GetNumLootItems and GetNumLootItems() or 0
  if numItems == 0 then return end
  lootDone = true
  local fishing = IsFishingLoot and IsFishingLoot()
  local mapID, x, y = TJ:PlayerPosition()
  local nodeKey, any
  for slot = 1, numItems do
    local link = GetLootSlotLink and GetLootSlotLink(slot)
    local itemID = link and tonumber(link:match("item:(%d+)"))
    if itemID then
      local _, _, qty = GetLootSlotInfo(slot)
      qty = tonumber(qty) or 1
      if isBlueprint(itemID) then TJ:Safe(rememberBlueprint, itemID, slot) end
      if fishing then
        any = true
        if mapID then
          TJ.char.fish[mapID] = TJ.char.fish[mapID] or {}
          bump(TJ.char.fish[mapID], itemID, qty)
        end
        bump(TJ.char.gathered, itemID, qty)
      else
        local cat = TJ.ItemCategory[itemID]
        if cat then
          any = true
          bump(TJ.char.gathered, itemID, qty)
          if mapID then
            TJ.char.zones[mapID] = TJ.char.zones[mapID] or {}
            bump(TJ.char.zones[mapID], itemID, qty)
          end
          if cat ~= "skinning" and GetLootSourceInfo then
            local guid = GetLootSourceInfo(slot)
            if type(guid) == "string" then
              local kind, _, _, _, _, objID = strsplit("-", guid)
              if kind == "GameObject" then
                nodeKey = nodeKey or TJ.NodeByObject[tonumber(objID) or 0] or TJ.NodeByItem[itemID] or ("item:" .. itemID)
              end
            end
          end
        end
      end
    end
  end
  if nodeKey then TJ:AddNode(mapID, x, y, nodeKey) end
  if fishing and any then TJ:AddNode(mapID, x, y, "fish") end
  if any then TJ:RefreshAll() end
end
on("LOOT_OPENED", onLoot)
on("LOOT_READY", onLoot)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
SLASH_EASYCRAFT1 = "/ec"
SLASH_EASYCRAFT2 = "/easycraft"
SLASH_EASYCRAFT3 = "/ремесла"
SlashCmdList.EASYCRAFT = function(msg)
  msg = TJ.Lower(strtrim and strtrim(msg or "") or (msg or ""))
  if msg == "reset" then
    TJ:Print(TJ.T("это сотрёт данные этого персонажа: отметки шагов, журнал сбора, историю навыка. Подтвердить: /ec reset confirm"))
  elseif msg == "reset confirm" then
    EasyCraftCharDB = nil
    TJ:InitDB()
    TJ:ScanSkills()
    TJ:Print(TJ.T("данные персонажа сброшены."))
    TJ:RefreshAll()
  elseif msg == "map" then
    TJ.settings.mapKnown = not TJ.settings.mapKnown
    TJ:Print(TJ.T("известные точки на карте: ") .. (TJ.settings.mapKnown and TJ.T("вкл") or TJ.T("выкл")))
    TJ:RefreshAll()
  elseif msg == "minimap" or msg == "миникарта" then
    TJ:SetMinimapHidden(TJ.settings.minimap)
    TJ:Print(TJ.settings.minimap and TJ.T("кнопка у миникарты показана.") or TJ.T("кнопка у миникарты скрыта (вернуть: /ec minimap)."))
  elseif msg == "check" or msg == "сверка" then
    TJ:PrintRouteCheck()
  elseif msg == "options" or msg == "config" or msg == "настройки" then
    TJ:OpenSettings()
  elseif msg == "help" or msg == "intro" or msg == "помощь" then
    TJ:ShowIntro()
  elseif msg == "" then
    if TJ.ToggleFrame then TJ:ToggleFrame() end
  else
    -- commands, ?, команды и всё незнакомое - список команд
    TJ:PrintCommands()
  end
end
