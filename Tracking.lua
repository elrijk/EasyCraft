local ADDON, ns = ...
local format = string.format

local ev = CreateFrame("Frame")
ns.eventFrame = ev
local handlers = {}

local function on(event, fn)
  handlers[event] = fn
  ev:RegisterEvent(event)
end
ev:SetScript("OnEvent", function(_, event, ...)
  local fn = handlers[event]
  if fn then ns:Safe(fn, ...) end
end)

local after = C_Timer.After

-- помощники с задержкой
local scheduled = {}
local function throttle(name, sec, fn)
  if scheduled[name] then return end
  scheduled[name] = true
  after(sec, function() scheduled[name] = nil; ns:Safe(fn) end)
end

---------------------------------------------------------------------------
-- Login
---------------------------------------------------------------------------
on("ADDON_LOADED", function(name)
  if name == "Blizzard_WorldMap" and ns.ready and ns.MapOverlay then ns.MapOverlay:Init() end
  if name ~= ADDON then return end
  ns:InitDB()
  ns:BuildLookups()
  if ns.BuildSettings then ns:Safe(ns.BuildSettings, ns) end
end)

on("PLAYER_LOGIN", function()
  if not ns.db then ns:InitDB(); ns:BuildLookups() end
  if ns.ApplyRealReagents then ns:Safe(ns.ApplyRealReagents, ns) end -- реагенты, которые игра показала другими
  ns:ResolveMaps()
  ns:ScanSkills()
  ns.ready = true
  if ns.CreateMinimapButton then ns:Safe(ns.CreateMinimapButton, ns) end
  if ns.MapOverlay then ns:Safe(ns.MapOverlay.Init, ns.MapOverlay) end
  if ns.Tracker then ns:Safe(ns.Tracker.Init, ns.Tracker) end
  if ns.HookItemTooltips then ns:Safe(ns.HookItemTooltips, ns) end
  if ns.HookNodeTooltips then ns:Safe(ns.HookNodeTooltips, ns) end
  ns:RegisterRefresh(function() if ns.UpdateMerchantButton then ns:UpdateMerchantButton() end end)
  -- Один раз на учётную запись: где открыть аддон.
  if not ns.db.introDone and not ns.db.introHinted then
    ns.db.introHinted = true
    after(5, function()
      ns:Print(ns.T("покажу, что качать в профессиях. Открыть - книга у миникарты или /ec."))
    end)
  end
end)

-- Торговец: кнопка «купить для шагов» под его окном.
for _, e in ipairs({ "MERCHANT_SHOW", "MERCHANT_UPDATE", "MERCHANT_CLOSED" }) do
  on(e, function() throttle("merchant", 0.2, function()
    ns.needCache = nil
    if e ~= "MERCHANT_CLOSED" then ns:Safe(ns.RecordMerchantPrices, ns) end
    ns:UpdateMerchantButton()
  end) end)
end

-- Аукцион открыт или закрыт: кнопка «Найти на аукционе» меняет вид.
for _, e in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED" }) do
  on(e, function() ns:RefreshAll() end)
end

on("PLAYER_ENTERING_WORLD", function()
  after(2, function() ns:Safe(ns.ScanSkills, ns) end)
end)
on("SKILL_LINES_CHANGED", function() throttle("skills", 0.5, function() ns:ScanSkills() end) end)
on("CHAT_MSG_SKILL", function() throttle("skills", 0.5, function() ns:ScanSkills() end) end)

-- Выучил рецепт (у учителя или из предмета-рецепта): отметить его в скане
-- окна профессии, чтобы карточка сразу перестала звать к учителю.
on("NEW_RECIPE_LEARNED", function(id)
  if type(id) ~= "number" then return end
  for key in pairs(ns.Profs) do
    local sc = ns.char.scan[key]
    local s = ns:SpellStep(key, id)
    if s and sc and sc.colors and sc.colors[id] == nil then
      local col = s.sk and ns:RecipeColor(s, ns:GetSkill(key))
      sc.colors[id] = (ns.COLOR_BY_D and ({ orange = 0, yellow = 1, green = 2, gray = 3 })[col or ""]) or 0
    end
  end
  ns:RefreshAll()
end)

-- Своё создание предмета прошло (окно профессии открыто): сумки сейчас
-- уменьшатся раньше, чем вырастет навык - подержать перерисовку.
-- только свои заклинания, а не каждого вокруг (в городе - сотни в секунду)
handlers["UNIT_SPELLCAST_SUCCEEDED"] = function()
  if ns.openKey then ns:HoldForSkill() end
end
-- через pcall: если игра уберёт это событие, загрузка файла не должна оборваться
pcall(ev.RegisterUnitEvent, ev, "UNIT_SPELLCAST_SUCCEEDED", "player")
on("BAG_UPDATE_DELAYED", function() throttle("bags", 0.5, function() ns:RefreshAll() end) end)
-- Сервер прислал сведения о предмете: перерисовать, только если это
-- предмет, который аддон сам ждал (а не любой из поиска на аукционе).
on("GET_ITEM_INFO_RECEIVED", function(id, ok)
  if not (id and ns.wantItem and ns.wantItem[id]) then return end
  ns.wantItem[id] = nil
  if ok == false then return end -- такого предмета нет: рисовать нечего
  ns.itemGen = (ns.itemGen or 0) + 1 -- карта: названия своих точек
  throttle("items", 0.4, function() ns:RefreshAll() end)
end)

---------------------------------------------------------------------------
-- Чтение окна профессии: какие рецепты сейчас дают навык
---------------------------------------------------------------------------
local DIFF = { optimal = 0, medium = 1, easy = 2, trivial = 3, difficult = 0 }
local function normDiff(d)
  if type(d) == "number" then return d end
  return DIFF[d or ""]
end

-- Чужая профессия: ссылка из чата, список гильдии, ремесленник-NPC.
-- Её навык и рецепты не наши, записывать их нельзя.
function ns:IsForeignTradeSkill()
  local api = C_TradeSkillUI
  return api.IsTradeSkillLinked() or api.IsTradeSkillGuild() or api.IsTradeSkillGuildMember() or api.IsNPCCrafting()
    or false
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

function ns:ScanTradeSkill()
  if self:IsForeignTradeSkill() then
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

  local info = C_TradeSkillUI.GetBaseProfessionInfo()
  if info and info.professionName then
    profName, rank, maxRank = info.professionName, info.skillLevel, info.maxSkillLevel
  end
  for _, id in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do
    local r = C_TradeSkillUI.GetRecipeInfo(id)
    if r and r.learned ~= false and r.type ~= "header" and r.type ~= "subheader" then
      add(r.name, r.relativeDifficulty or r.difficulty, r.numAvailable, r.icon, id)
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
  -- свои наблюдения цветов (Seen.lua): из них получаются пороги рецептов
  if self.NoteColors then self:Safe(self.NoteColors, self, key, colors, rank) end
  -- книга рецептов и откаты (Book.lua): все выученные рецепты окна
  if self.ScanBook then self:Safe(self.ScanBook, self, key) end
  -- полная база рецептов профессии, выученных и нет (Recipes.lua)
  if self.ScanAllRecipes then self:Safe(self.ScanAllRecipes, self, key) end
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
local tradeOpen = false
local function windowShown(names)
  for _, n in ipairs(names) do
    local f = _G[n]
    if type(f) == "table" and f.IsShown and f:IsShown() then return true end
  end
  return false
end
-- the game loads the profession window on its first opening
local TRADE_FRAMES = { "ProfessionsFrame" }
for _, e in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED" }) do
  on(e, function()
    if e == "TRADE_SKILL_SHOW" then tradeOpen = true end
    throttle("trade", 0.4, function()
      if tradeOpen or windowShown(TRADE_FRAMES) then ns:ScanTradeSkill() end
    end)
  end)
end
on("TRADE_SKILL_CLOSE", function()
  tradeOpen = false
  ns.openKey = nil
  -- окно закрыли раньше, чем начали создавать: само потом не начнём
  if ns.pendingCraft and GetTime() - ns.pendingCraft.t > 2 then ns.pendingCraft = nil end
  if ns.Tracker and ns.Tracker.Detach then ns.Tracker:Detach() end
  ns:RefreshAll()
end)

---------------------------------------------------------------------------
-- Журнал сбора (идея из Gather Together): что добыто с жил и трав,
-- со шкур и рыбалки по зонам, и где стояли точки - для карты мира.
---------------------------------------------------------------------------
function ns:PlayerPosition()
  local mapID = C_Map.GetBestMapForUnit("player")
  if not mapID then return end
  local pos = C_Map.GetPlayerMapPosition(mapID, "player")
  if not pos then return mapID end
  local x, y = pos:GetXY()
  return mapID, x, y
end

-- Свои находки на карте убраны (1.2): места сбора больше не записываются.
function ns:AddNode()
end

local function bump(t, k, n) t[k] = (t[k] or 0) + n end

local lootDone = false
on("LOOT_CLOSED", function() lootDone = false end)
-- Чертежи лагеря: id -> true (собираем из данных один раз).
local bpSet
local function isBlueprint(id)
  if not bpSet then
    bpSet = {}
    for _, p in pairs(ns.Profs) do
      for _, e in ipairs(p.camp or {}) do if e.bp then bpSet[e.bp] = true end end
    end
  end
  return bpSet[id]
end

-- Чертёж выпал: запомнить, с кого и где (у части чертежей источник пока
-- никому не известен - так он станет известен хотя бы тебе).
local function rememberBlueprint(id, slot)
  local who
  if UnitExists("target") and UnitIsDead("target") then who = UnitName("target") end
  local where = GetInstanceInfo()
  if not where or where == "" or not IsInInstance() then where = GetRealZoneText() end
  local mapID, x, y = ns:PlayerPosition()
  ns.db.bpFound = ns.db.bpFound or {}
  ns.db.bpFound[id] = { who = who, where = where, map = mapID, x = x and x * 100, y = y and y * 100, t = time() }
end

local function onLoot()
  if lootDone then return end
  local numItems = GetNumLootItems() or 0
  if numItems == 0 then return end
  lootDone = true
  local fishing = IsFishingLoot()
  local mapID, x, y = ns:PlayerPosition()
  local nodeKey, any
  for slot = 1, numItems do
    local link = GetLootSlotLink(slot)
    local itemID = link and tonumber(link:match("item:(%d+)"))
    if itemID then
      local _, _, qty = GetLootSlotInfo(slot)
      qty = tonumber(qty) or 1
      if isBlueprint(itemID) then ns:Safe(rememberBlueprint, itemID, slot) end
      if fishing then
        any = true
        if mapID then
          ns.char.fish[mapID] = ns.char.fish[mapID] or {}
          bump(ns.char.fish[mapID], itemID, qty)
        end
        bump(ns.char.gathered, itemID, qty)
      else
        local cat = ns.ItemCategory[itemID]
        if cat then
          any = true
          bump(ns.char.gathered, itemID, qty)
          if mapID then
            ns.char.zones[mapID] = ns.char.zones[mapID] or {}
            bump(ns.char.zones[mapID], itemID, qty)
          end
          if cat ~= "skinning" then
            local guid = GetLootSourceInfo(slot)
            if type(guid) == "string" then
              local kind, _, _, _, _, objID = strsplit("-", guid)
              if kind == "GameObject" then
                nodeKey = nodeKey or ns.NodeByObject[tonumber(objID) or 0] or ns.NodeByItem[itemID] or ("item:" .. itemID)
              end
            end
          end
        end
      end
    end
  end
  if nodeKey then ns:AddNode(mapID, x, y, nodeKey) end
  if fishing and any then ns:AddNode(mapID, x, y, "fish") end
  if any then ns:RefreshAll() end
end
on("LOOT_OPENED", onLoot)
on("LOOT_READY", onLoot)

---------------------------------------------------------------------------
-- Команды чата
---------------------------------------------------------------------------
SLASH_EASYCRAFT1 = "/ec"
SLASH_EASYCRAFT2 = "/easycraft"
SlashCmdList.EASYCRAFT = function(msg)
  msg = ns.Lower(strtrim(msg or ""))
  if msg == "reset" then
    ns:Print(ns.T("это сотрёт данные этого персонажа: отметки шагов, журнал сбора, историю навыка. Подтвердить: /ec reset confirm"))
  elseif msg == "reset confirm" then
    EasyCraftCharDB = nil
    ns:InitDB()
    ns:ScanSkills()
    ns:Print(ns.T("данные персонажа сброшены."))
    ns:RefreshAll()
  elseif msg == "minimap" then
    ns:SetMinimapHidden(ns.settings.minimap)
    ns:Print(ns.settings.minimap and ns.T("кнопка у миникарты показана.") or ns.T("кнопка у миникарты скрыта (вернуть: /ec minimap)."))
  elseif msg == "choose" then
    ns:ShowChoose()
  elseif msg == "colors" then
    ns:ShareColors()
  elseif msg == "scan" then
    ns:ScanAuction(true)
  elseif msg == "check" then
    ns:PrintRouteCheck()
  elseif msg == "options" or msg == "config" then
    ns:OpenSettings()
  elseif msg == "help" or msg == "intro" then
    ns:ShowIntro()
  elseif msg == "" then
    if ns.ToggleFrame then ns:ToggleFrame() end
  else
    -- commands, ?, команды и всё незнакомое - список команд
    ns:PrintCommands()
  end
end
