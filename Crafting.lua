local ADDON, ns = ...
local floor, min = math.floor, math.min
local format = string.format

-------------------------------------------------------------------------------
--  Окно профессии: открыть, создать предметы, ссылка на профессию в чат.
--  ns.openKey - какая своя профессия сейчас открыта (ставит ScanTradeSkill).
-------------------------------------------------------------------------------
local TS = C_TradeSkillUI

function ns:IsProfOpen(key)
  return key ~= nil and self.openKey == key
end

-- Открыть окно своей профессии.
function ns:OpenProfession(key)
  local p = self.Profs[key]
  if not (p and TS and TS.OpenTradeSkill) then return false end
  if InCombatLockdown and InCombatLockdown() then
    self:Print(ns.T("в бою окно профессии не открыть."))
    return false
  end
  local ok, opened = pcall(TS.OpenTradeSkill, p.skill)
  return ok and opened ~= false
end

-- Открыть окно профессии сразу на рецепте. Если окно закрыто - сначала
-- открываем его, рецепт выберем, когда игра его покажет.
-- The game's own call does not always move the selection when the window
-- is already open on another recipe. A moment later we look at what the
-- window shows and, if it is still not our recipe, select it through the
-- window itself.
local function selectInWindow(spell)
  local pf = _G.ProfessionsFrame
  local page = pf and pf:IsShown() and pf.CraftingPage
  if type(page) ~= "table" or not (TS and TS.GetRecipeInfo) then return end
  local form = page.SchematicForm
  local cur = type(form) == "table" and form.GetRecipeInfo and form:GetRecipeInfo()
  if type(cur) == "table" and cur.recipeID == spell then return end
  local info = TS.GetRecipeInfo(spell)
  if type(info) ~= "table" then return end
  if page.SelectRecipe then
    page:SelectRecipe(info)
  elseif type(page.RecipeList) == "table" and page.RecipeList.SelectRecipe then
    page.RecipeList:SelectRecipe(info, true)
  end
end

function ns:OpenRecipe(key, spell)
  if self:IsProfOpen(key) then
    if spell and TS and TS.OpenRecipe then
      pcall(TS.OpenRecipe, spell)
      C_Timer.After(0.2, function() pcall(selectInWindow, spell) end)
    end
    return true
  end
  self.pendingRecipe = spell
  return self:OpenProfession(key)
end

-- Рецепт в открытом окне: выучен ли и сколько можно сделать из того, что есть.
-- Возвращает nil, если окно этой профессии не открыто.
function ns:RecipeState(key, spell)
  if not (spell and self:IsProfOpen(key) and TS and TS.GetRecipeInfo) then return nil end
  local ok, info = pcall(TS.GetRecipeInfo, spell)
  if not ok or not info then return { unknown = true } end
  local n = info.numAvailable
  if TS.GetCraftableCount then
    local ok2, c = pcall(TS.GetCraftableCount, spell)
    if ok2 and type(c) == "number" then n = c end
  end
  return { known = info.learned ~= false, count = n or 0, enchant = info.isEnchantingRecipe }
end

-- Выучен ли рецепт: по открытому окну, иначе по игре и прошлому скану окна.
-- nil - не знаем (окно профессии ещё не открывали).
function ns:RecipeKnown(key, spell)
  if not spell then return nil end
  local st = self:RecipeState(key, spell)
  if st then
    if st.unknown then return nil end -- рецепта в игре нет: не «выучи»
    return st.known
  end
  if IsPlayerSpell then
    local ok, v = pcall(IsPlayerSpell, spell)
    if ok and v then return true end
  end
  local sc = self.char and self.char.scan[key]
  if sc and sc.colors then return sc.colors[spell] ~= nil end
  return nil
end

-- Где выучить рецепт шага: { kind = "trainer" | "vendor" | "other",
-- npc = ближайший учитель или торговец, item = предмет-рецепт,
-- price = «12с», extra = «ограниченный запас», info = как есть }.
-- Учитель - того ранга, на котором рецепт открывается.
function ns:RecipeSource(key, s)
  if s.src == "recipe" then
    -- в английском виде заметка переведена: «price: 80s»
    local info = s.info or ""
    local price, extra = info:match("^цена:%s*([^,]+),?%s*(.*)$")
    if not price then price, extra = info:match("^price:%s*([^,]+),?%s*(.*)$") end
    local all = s.npcs and self:NpcsFor(s.npcs) or {}
    return { kind = "vendor", npc = all[1], all = all, item = s.recipe,
      price = price, copper = self:ParseMoney(price), extra = extra ~= "" and extra or nil, info = s.info }
  end
  if s.src and s.src ~= "trainer" and s.src ~= "rank" then return { kind = "other", info = s.info and ns.T(s.info) or nil } end
  local req = (s.sk and s.sk[1] and s.sk[1] > 0 and s.sk[1]) or s.f or 0
  local pick
  for _, st in ipairs(self.Profs[key].steps) do
    if st.k == "train" and st.npcs and st.max and st.max > req and (not pick or st.max < pick.max) then pick = st end
  end
  local all = pick and self:NpcsFor(pick.npcs) or {}
  return { kind = "trainer", npc = all[1], all = all }
end

-- «1з 20с», «42м» (или «1g 20s», «42c» в английском виде) -> медь; nil - не цена.
function ns:ParseMoney(text)
  if type(text) ~= "string" then return nil end
  local g = text:match("(%d+)%s*з") or text:match("(%d+)%s*g")
  local sv = text:match("(%d+)%s*с") or text:match("(%d+)%s*s")
  local c = text:match("(%d+)%s*м") or text:match("(%d+)%s*c")
  if not (g or sv or c) then return nil end
  return (tonumber(g) or 0) * 10000 + (tonumber(sv) or 0) * 100 + (tonumber(c) or 0)
end

-- Следующий ранг и что для него сделать: у учителя (train), купить книгу
-- (book), взять задание (quest). { s, kind, id = ближайший NPC, item,
-- name, max, learn, can = можно уже сейчас, lvl } или nil (всё выучено).
function ns:RankAction(key)
  local nr = self:NextRank(key)
  if not nr then return nil end
  local rank = self:GetSkill(key)
  local s = nr.s
  local all = s.npcs and self:NpcsFor(s.npcs) or {}
  return { s = s, kind = s.k, id = all[1], all = all, item = s.k == "book" and s.id or nil,
    name = self:RankName(nr.max), max = nr.max, learn = nr.learn or 0, can = self:CanLearnRank(s, rank), lvl = s.lvl }
end

-- Кто нужен прямо сейчас (ближайший): учитель для рецепта шага или
-- учитель / торговец книгой / кто даёт задание - для следующего ранга,
-- если его уже можно взять. Иначе nil и почему пока никто не нужен.
-- Возвращает id, «зачем».
function ns:NeededTrainer(key)
  local p = self.Profs[key]
  if not p then return nil end
  local T = ns.T
  local rank, maxRank = self:GetSkill(key)
  local _, s = self:CurrentStep(key, rank, maxRank)
  if s and s.k == "craft" and self:RecipeKnown(key, s.spell) == false then
    local src = self:RecipeSource(key, s)
    if src.kind == "trainer" and src.npc then
      return src.npc, format(T("Выучить рецепт шага: %s."), self:StepName(s))
    end
  end
  local ra = self:RankAction(key)
  if not ra then return nil, T("Всё нужное уже выучено.") end
  if ra.can and ra.id then
    if ra.kind == "book" then return ra.id, format(T("Купить книгу ранга «%s»."), ra.name) end
    if ra.kind == "quest" then return ra.id, format(T("Взять задание на ранг «%s»."), ra.name) end
    return ra.id, format(T("Выучить ранг «%s»."), ra.name)
  end
  if rank < ra.learn then return nil, format(T("Следующий ранг «%s» - с навыка %d."), ra.name, ra.learn) end
  if ra.lvl then return nil, format(T("Следующий ранг «%s» - с %d уровня."), ra.name, ra.lvl) end
  return nil, T("Всё нужное уже выучено.")
end




-- Ближайший учитель профессии твоего ранга (учит следующий ранг и рецепты).
function ns:NearestTrainer(key)
  local rank = self:GetSkill(key)
  local pick, last
  for _, st in ipairs(self.Profs[key].steps) do
    if st.k == "train" and st.npcs and st.max then
      last = st
      if st.max > rank and (not pick or st.max < pick.max) then pick = st end
    end
  end
  pick = pick or last
  return pick and self:NpcsFor(pick.npcs, 1)[1]
end

-- Заголовок «где выучить»: «Сначала выучи рецепт у учителя:» и т. п.
function ns:RecipeSourceHead(src)
  local T = ns.T
  if src.kind == "vendor" then
    -- цена монетами, как в игре
    local money = src.copper and self.W.Money(src.copper) or src.price
    return money and format(T("Сначала купи рецепт у торговца за %s:"), money) or T("Сначала купи рецепт у торговца:")
  elseif src.kind == "trainer" and src.npc then
    return T("Сначала выучи рецепт у учителя:")
  end
  return T("Сначала выучи этот рецепт.") .. (src.info and (" " .. src.info) or "")
end

function ns:Craft(key, spell, count)
  if not (spell and TS and TS.CraftRecipe) then return false end
  if InCombatLockdown and InCombatLockdown() then
    self:Print(ns.T("в бою создавать предметы нельзя."))
    return false
  end
  count = math.max(1, floor(tonumber(count) or 1))
  local ok, err = pcall(TS.CraftRecipe, spell, count)
  if not ok then self:Print(ns.T("не получилось создать: ") .. tostring(err)) end
  return ok
end

-- Сколько раз можно создать шаг из того, что лежит в сумках (withBank -
-- вместе с банком). Нужно, пока окно профессии закрыто и игра сама не
-- считает. nil - не знаем реагентов.
function ns:CanMake(s, withBank)
  local rc = s and s.rc
  if not rc or #rc < 2 then return nil end
  local n
  for i = 1, #rc - 1, 2 do
    local q = math.max(1, rc[i + 1] or 1)
    local have = withBank and self:ItemCount(rc[i]) or self:BagCount(rc[i])
    local k = floor(have / q)
    n = n and min(n, k) or k
  end
  return n or 0
end

-- «Создать» при закрытом окне: открыть профессию и начать создание само,
-- как только игра покажет рецепты. Ждём не дольше PENDING_SEC.
local PENDING_SEC = 15

-- Игра раньше не дала создавать само (запоминаем до новой версии аддона).
function ns:NoAutoCraft()
  return self.db ~= nil and self.db.noAutoCraft == ns.version
end

-- Игра не дала начать создание само: окно уже открыто, просим нажать ещё раз.
local function askAgain()
  ns:Print(ns.T("игра не дала начать сразу. Окно открыто - нажми «Создать» ещё раз."))
end

function ns:CraftOrOpen(key, spell, count)
  if self:IsProfOpen(key) then return self:Craft(key, spell, count) end
  if InCombatLockdown and InCombatLockdown() then
    self:Print(ns.T("в бою создавать предметы нельзя."))
    return false
  end
  -- Игра уже раз не дала создавать само: просто открываем окно на рецепте.
  if self:NoAutoCraft() then
    if self:OpenRecipe(key, spell) then self:Print(ns.T("окно профессии открыто - нажми «Создать» ещё раз.")) end
    return false
  end
  local pc = { key = key, spell = spell, count = count, t = GetTime(), tries = 0 }
  self.pendingCraft = pc
  self.pendingRecipe = spell
  if not self:OpenProfession(key) then
    self.pendingCraft, self.pendingRecipe = nil, nil
    return false
  end
  -- Не дождались рецептов: окно открыто - просим нажать самому.
  C_Timer.After(PENDING_SEC, function()
    if ns.pendingCraft ~= pc then return end
    ns.pendingCraft = nil
    if ns:IsProfOpen(pc.key) then askAgain() end
  end)
  return true
end

-- Проверяем, что создание правда началось: игра может не дать аддону
-- начать его без нажатия. Тогда просим нажать ещё раз - окно уже открыто.
local watch = CreateFrame("Frame")
local WATCH_EVENTS = { "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED",
  "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_FAILED_QUIET", "UNIT_SPELLCAST_INTERRUPTED" }
local watchGen = 0
-- Игра запретила действие аддона: больше не пробуем создавать само,
-- дальше кнопка при закрытом окне только открывает рецепт.
for _, e in ipairs({ "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do pcall(watch.RegisterEvent, watch, e) end
watch:SetScript("OnEvent", function(_, event, addon)
  if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
    if addon == ADDON and ns.autoCraftAt and GetTime() - ns.autoCraftAt < 2 and ns.db then ns.db.noAutoCraft = ns.version end
    return
  end
  ns.autoCraftSeen = true
end)

local function stopWatch()
  for _, e in ipairs(WATCH_EVENTS) do pcall(watch.UnregisterEvent, watch, e) end
end

function ns:AutoCraft(key, spell, count)
  if InCombatLockdown and InCombatLockdown() then
    self:Print(ns.T("в бою создавать предметы нельзя."))
    return
  end
  self.autoCraftSeen = nil
  self.autoCraftAt = GetTime()
  watchGen = watchGen + 1
  local gen = watchGen
  for _, e in ipairs(WATCH_EVENTS) do pcall(watch.RegisterUnitEvent, watch, e, "player") end
  -- без Craft(): его текст ошибки для игрока непонятен, здесь он не нужен
  local ok = TS and TS.CraftRecipe and pcall(TS.CraftRecipe, spell, math.max(1, floor(tonumber(count) or 1)))
  if not ok then
    stopWatch()
    askAgain()
    return
  end
  local function check()
    if gen ~= watchGen then return end -- уже идёт новая попытка
    stopWatch()
    if not ns.autoCraftSeen then
      -- создание не началось: игра не даёт делать это само - запомним
      if ns.db then ns.db.noAutoCraft = ns.version end
      askAgain()
    end
  end
  C_Timer.After(1.5, function() ns:Safe(check) end)
end

local function flushPendingCraft(self)
  local pc = self.pendingCraft
  if not pc then return end
  if GetTime() - pc.t > PENDING_SEC then
    self.pendingCraft = nil -- устарело: окно открыли позже и сами
    return
  end
  if not self:IsProfOpen(pc.key) then return end
  local st = self:RecipeState(pc.key, pc.spell)
  if not st or st.unknown then
    -- Список рецептов ещё грузится: заглянем чуть позже, но недолго.
    if pc.waiting then return end
    if pc.tries >= 4 then
      self.pendingCraft = nil
      self:Print(ns.T("не нашёл рецепт в окне профессии: выбери его там и нажми «Создать»."))
      return
    end
    pc.tries, pc.waiting = pc.tries + 1, true
    C_Timer.After(0.5, function()
      pc.waiting = nil
      if ns.pendingCraft == pc then ns:Safe(flushPendingCraft, ns) end
    end)
    return
  end
  self.pendingCraft = nil
  if not st.known then
    self:Print(ns.T("этот рецепт ещё не выучен: где его взять, написано в шаге."))
  elseif st.enchant then
    self:Print(ns.T("Чары накладываются из окна профессии: выбери там вещь."))
  elseif (st.count or 0) < 1 then
    self:Print(ns.T("не хватает реагентов."))
  else
    self:AutoCraft(pc.key, pc.spell, min(math.max(1, tonumber(pc.count) or 1), st.count))
  end
end

-- Ссылка на свою профессию в чат. Игра даёт ссылку только для открытого
-- окна профессии, поэтому, если оно закрыто, сначала открываем его.
-- chatType: nil - вставить в строку чата; "SAY", "PARTY", "RAID", "GUILD"
-- или "CHANNEL" (channel - номер канала) - отправить сразу.
local SendChat = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
local CHAT_SLASH = { SAY = "/s ", PARTY = "/p ", RAID = "/ra ", GUILD = "/g " }

local function OpenChatWith(text)
  local CF = ChatFrameUtil
  if CF and CF.OpenChat then CF.OpenChat(text)
  elseif ChatFrame_OpenChat then ChatFrame_OpenChat(text) end
end

local function SendLink(link, chatType, channel, direct)
  if not chatType then ns.W.InsertLink(link); return end
  -- Сказать и каналы игра пускает только по щелчку игрока: если окно
  -- профессии открывалось само, ставим ссылку в строку чата нужного канала.
  if not direct and (chatType == "SAY" or chatType == "CHANNEL") then
    OpenChatWith((chatType == "CHANNEL" and ("/" .. tostring(channel) .. " ") or CHAT_SLASH[chatType]) .. link)
    return
  end
  local ok = SendChat and pcall(SendChat, link, chatType, nil, channel)
  if not ok then OpenChatWith((CHAT_SLASH[chatType] or "") .. link) end
end

function ns:LinkProfession(key, chatType, channel, fromPending)
  if self:IsProfOpen(key) and TS and TS.GetTradeSkillListLink then
    local ok, link = pcall(TS.GetTradeSkillListLink)
    if ok and link then
      SendLink(link, chatType, channel, not fromPending)
      return
    end
  end
  self.pendingLink = { key = key, chatType = chatType, channel = channel }
  if not self:OpenProfession(key) then
    self.pendingLink = nil
    self:Print(ns.T("открой окно профессии, тогда ссылка встанет в чат."))
  end
end

-- Свои каналы чата: { { id, name } } (Общий, Торговля и т. п.).
local function JoinedChannels()
  local out = {}
  if not GetChannelList then return out end
  local list = { GetChannelList() }
  local i = 1
  while i <= #list do
    local id, name = list[i], list[i + 1]
    if type(id) == "number" and type(name) == "string" then
      local step = (type(list[i + 2]) == "boolean") and 3 or 2
      if not (step == 3 and list[i + 2]) then out[#out + 1] = { id = id, name = name } end
      i = i + step
    else
      i = i + 1
    end
  end
  return out
end

-- Меню «Ссылка в чат»: куда отправить ссылку на профессию.
function ns:LinkMenu(key, anchor)
  local T = ns.T
  local list = {
    { text = T("Вставить в строку чата"), tip = T("Ссылка встанет в строку чата: допиши текст и нажми Enter."),
      onClick = function() ns:LinkProfession(key) end },
    { text = T("Сказать"), onClick = function() ns:LinkProfession(key, "SAY") end },
    { text = T("Группа"), enabled = IsInGroup and IsInGroup() or false, onClick = function() ns:LinkProfession(key, "PARTY") end },
    { text = T("Рейд"), enabled = IsInRaid and IsInRaid() or false, onClick = function() ns:LinkProfession(key, "RAID") end },
    { text = T("Гильдия"), enabled = IsInGuild and IsInGuild() or false, onClick = function() ns:LinkProfession(key, "GUILD") end },
  }
  for _, ch in ipairs(JoinedChannels()) do
    list[#list + 1] = { text = ch.id .. ". " .. ch.name, onClick = function() ns:LinkProfession(key, "CHANNEL", ch.id) end }
  end
  ns.W.Menu(anchor, list)
end

-- Окно своей профессии открылось: доделать то, ради чего его открывали.
function ns:FlushPendingLink()
  local spell = self.pendingRecipe
  if spell and self.openKey then
    self.pendingRecipe = nil
    if TS and TS.OpenRecipe then pcall(TS.OpenRecipe, spell) end
  end
  flushPendingCraft(self)
  local pl = self.pendingLink
  if not pl or not self:IsProfOpen(pl.key) then return end
  self.pendingLink = nil
  self:LinkProfession(pl.key, pl.chatType, pl.channel, true)
end

-------------------------------------------------------------------------------
--  Цены аукциона - в Prices.lua: EasyCraft читает их сам, когда игрок
--  открывает аукцион. Чужие аддоны для цен не используются.
-------------------------------------------------------------------------------
local GetItemInfoFn = C_Item.GetItemInfo

-- Цена старше стольких дней помечается как устаревшая.
ns.PRICE_OLD_DAYS = 3

-- Продаётся у торговцев (колбы, нитки, соль): на аукционе не ищем.
function ns:IsVendorItem(id)
  local src = self.MatSources and self.MatSources[id]
  return src and src.src == "vendor" or false
end

-- Можно собрать своей профессией сбора: ключ этой профессии или nil.
local GATHER_BY_SRC = { herb = "herbalism", ore = "mining", skin = "skinning", fish = "fishing" }
function ns:OwnGather(id)
  local src = self.MatSources and self.MatSources[id]
  local key = (src and GATHER_BY_SRC[src.src]) or self.ItemCategory[id]
  if key and self.char.profs[key] and self.Profs[key] and self.Profs[key].kind ~= "craft" then return key end
end

function ns:IsAuctionOpen()
  return self.ahOpen or (AuctionHouseFrame and AuctionHouseFrame:IsShown()) or false
end

-- Название на языке клиента: по нему ищет аукцион.
function ns:ClientItemName(id)
  local name = GetItemInfoFn and GetItemInfoFn(id)
  if not name then
    self:WantItem(id)
    if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
  end
  return name
end

-------------------------------------------------------------------------------
--  Настоящие цвета рецептов из окна профессии и лучший рецепт сейчас.
--  Скан окна (Tracking.lua) хранит цвета выученных рецептов: 0 оранжевый,
--  1 жёлтый, 2 зелёный, 3 серый. Он годится, пока навык не изменился.
-------------------------------------------------------------------------------
local COLOR_BY_D = { [0] = "orange", [1] = "yellow", [2] = "green", [3] = "gray" }
ns.COLOR_BY_D = COLOR_BY_D

function ns:FreshScan(key, rank)
  local sc = self.char.scan[key]
  if not (sc and sc.colors and sc.list) then return nil end
  if not self:IsProfOpen(key) and sc.rank ~= rank then return nil end
  return sc
end

-- Цвет рецепта по окну профессии; nil - неизвестно (окно не открывали).
function ns:RealColor(key, spell, rank)
  local sc = spell and self:FreshScan(key, rank)
  local d = sc and sc.colors[spell]
  return d and COLOR_BY_D[d]
end

-- Реагенты рецепта из открытого окна профессии: {id, кол-во, ...} или nil.
local reagentCache = {} -- реагенты рецептов не меняются: спрашиваем игру один раз
function ns:RecipeReagents(spell)
  if not spell then return nil end
  if reagentCache[spell] then return reagentCache[spell] end
  local rc = self:ReadRecipeReagents(spell)
  reagentCache[spell] = rc -- неудачу не запоминаем: рецепт могут выучить позже
  return rc
end

function ns:ReadRecipeReagents(spell)
  if not (TS and TS.GetRecipeSchematic) then return nil end
  local ok, sch = pcall(TS.GetRecipeSchematic, spell, false)
  if not ok or type(sch) ~= "table" or type(sch.reagentSlotSchematics) ~= "table" then return nil end
  local basic = Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic or 1
  local rc = {}
  for _, slot in ipairs(sch.reagentSlotSchematics) do
    local r = slot.reagents and slot.reagents[1]
    if r and r.itemID and (slot.reagentType == nil or slot.reagentType == basic) then
      tinsert(rc, r.itemID)
      tinsert(rc, slot.quantityRequired or 1)
    end
  end
  return #rc > 0 and rc or nil
end

-- Цена у торговца за штуку: настоящая, если видели этот товар у торговца
-- (запоминаем), иначе примерно - торговец продаёт в 4 раза дороже, чем
-- покупает. Второе значение true - цена примерная.
function ns:VendorPrice(id)
  local v = self.db and self.db.vprice and self.db.vprice[id]
  if v then return v, false end
  if GetItemInfoFn then
    local name, _, _, _, _, _, _, _, _, _, sell = GetItemInfoFn(id)
    if not name then self:WantItem(id) end
    if type(sell) == "number" and sell > 0 then return sell * 4, true end
  end
  return nil
end

-- Книги рангов и рецепты маршрута, которые покупают у торговцев: их цену
-- тоже запоминаем у торговца (на подсказке - «купить книгу за 10з»).
local shopItems
function ns:IsRouteShopItem(id)
  if not shopItems then
    shopItems = {}
    for _, p in pairs(self.Profs) do
      for _, s in ipairs(p.steps) do
        if s.k == "book" and s.id then shopItems[s.id] = true end
        if s.recipe then shopItems[s.recipe] = true end
      end
    end
  end
  return shopItems[id] or false
end

-- Торговец открыт: запомнить цены реагентов, которые продают торговцы.
function ns:RecordMerchantPrices()
  if not (self.db and GetMerchantNumItems and GetMerchantItemID) then return end
  for i = 1, GetMerchantNumItems() or 0 do
    local id = GetMerchantItemID(i)
    if id and (self:IsVendorItem(id) or self:IsRouteShopItem(id)) then
      local price, stack, extended
      if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local info = C_MerchantFrame.GetItemInfo(i)
        price, stack, extended = info and info.price, info and info.stackCount, info and info.hasExtendedCost
      end
      if price and price > 0 and not extended then
        self.db.vprice[id] = math.floor(price / math.max(1, stack or 1) + 0.5)
      end
    end
  end
end

-- Что нужно на оставшиеся left крафтов шага, по реагентам:
-- { id, need, have (сумки - из них создают), all (с банком), mail, alts,
--   buy (докупить), cost/age (аукцион), vendor }.
-- Итог: total (медь на аукционе), noPrice, vendor (имена), vendorCost
-- (медь у торговцев), vendorApprox (цена примерная), auction
-- ({id, buy} - что докупить на аукционе), bank/mail (часть лежит там), allHave.
-- Банк, почта и альты не докупаются - их надо забрать.
function ns:StepBuy(s, left, pool)
  local out = { items = {}, total = 0, noPrice = 0, vendor = {}, vendorCost = 0, auction = {}, allHave = true }
  local rc = s and (s.rc or s.m)
  if not rc then return out end
  local alts = self:AltCounts()
  for j = 1, #rc - 1, 2 do
    local id = rc[j]
    local need = self:StepNeed(s, rc[j + 1], left or 0)
    -- per: how many one craft takes (the counts on the step are for all the crafts left)
    local e = { id = id, need = need, per = s.rc and rc[j + 1] or nil, have = self:BagCount(id), all = self:ItemCount(id),
      mail = self:MailCount(id), alts = alts[id] or 0, buy = 0 }
    -- pool: общий запас на несколько профессий - что ушло одной, другой не достанется
    local stock = e.all + e.alts + e.mail
    if pool then
      local used = pool[id] or 0
      stock = math.max(0, stock - used)
      pool[id] = used + need
    end
    e.buy = math.max(0, need - stock)
    e.stock = stock -- что досталось этому шагу из общего запаса
    if e.have < need or e.buy > 0 then
      out.allHave = false
      if e.all > e.have then out.bank = true end
      if e.mail > 0 then out.mail = true end
      if e.buy > 0 then
        if self:IsVendorItem(id) then
          e.vendor = true
          tinsert(out.vendor, self:ItemName(id))
          local p, approx = self:VendorPrice(id)
          if p then
            e.cost, e.approx = p * e.buy, approx
            out.vendorCost = out.vendorCost + e.cost
            if approx then out.vendorApprox = true end
          end
        else
          local p, age = self:AuctionPrice(id)
          if p then
            e.cost, e.age = p * e.buy, (age and age >= self.PRICE_OLD_DAYS) and age or nil
            out.total = out.total + e.cost
          else
            out.noPrice = out.noPrice + 1
          end
          tinsert(out.auction, { id = id, buy = e.buy })
        end
      end
    end
    tinsert(out.items, e)
  end
  return out
end

-- Строки «где взять недостающее» для шага (без чисел - они на картинке):
-- забрать из банка, у торговца, сколько докупить на аукционе, нет цен.
function ns:StepBuyLines(b)
  local T, lines = ns.T, {}
  if b.bank then tinsert(lines, "|cffffd100" .. T("Часть лежит в банке: забери у банкира") .. "|r") end
  if #b.vendor > 0 then
    -- сколько потратить у торговца и на что (сами количества - на картинке)
    local money = b.vendorCost > 0 and ("|cffffffff" .. (b.vendorApprox and "~" or "") .. self.W.Money(b.vendorCost) .. "|r  ") or ""
    tinsert(lines, T("У торговца: ") .. money .. "|cff9d9d9d" .. table.concat(b.vendor, ", ") .. "|r")
  end
  if b.total > 0 then
    tinsert(lines, T("Докупить на аукционе: ") .. "|cffffffff" .. self.W.Money(b.total) .. "|r"
      .. (b.noPrice > 0 and ("  |cff9d9d9d" .. format(T("(и ещё %d без цены)"), b.noPrice) .. "|r") or ""))
  end
  if b.noPrice > 0 then
    if not self:PriceSource() then
      tinsert(lines, "|cffff5555" .. T("Цен нет: открой аукцион - EasyCraft прочитает их сам") .. "|r")
    elseif b.total == 0 then
      tinsert(lines, "|cff9d9d9d" .. T("Цен нет: открой аукцион - EasyCraft прочитает их сам") .. "|r")
    end
  end
  if b.mail then tinsert(lines, self.MAIL_COLOR .. T("Часть ждёт на почте") .. "|r") end
  return lines
end

-- Цена одного реагента для сравнения рецептов. Аукцион; для товаров
-- торговца без цены на аукционе - примерно: торговец продаёт где-то в 4 раза
-- дороже, чем покупает.
function ns:UnitPrice(id)
  if self:IsVendorItem(id) then
    local p = self:VendorPrice(id)
    if p then return p end
  end
  return (self:AuctionPrice(id))
end

-- Стоимость одного создания по реагентам {id, кол-во, ...}; nil - есть
-- реагент без цены.
function ns:RecipeCost(rc)
  if type(rc) ~= "table" or #rc < 2 then return nil end
  local total = 0
  for i = 1, #rc - 1, 2 do
    local p = self:UnitPrice(rc[i])
    if not p then return nil end
    total = total + p * (rc[i + 1] or 1)
  end
  return total
end

-- Рецепт, который сейчас даст навык вернее, чем рецепт шага s, или на
-- который есть реагенты, когда на шаг их нет:
-- { id, name, icon, color, a = сколько можно сделать, n = сколько советуем,
--   instead = шаг сейчас не сделать, а этот можно, cost = цена штуки,
--   chance, cheaperBy, cheaperThan } или nil.
-- Цвета - из окна профессии; если его ещё не открывали на этом навыке -
-- по порогам маршрута для рецептов, которые уже были в окне (выучены).
-- Запас при закрытом окне считаем по сумкам: скан окна мог устареть.
local D_BY_COLOR = { orange = 0, yellow = 1, green = 2, gray = 3 }
function ns:BestRecipe(key, s, rank)
  return (self:BestRecipes(key, s, rank, 1))[1]
end

-- То же, но несколько вариантов по порядку (первый - лучший).
function ns:BestRecipes(key, s, rank, limit)
  local open = self:IsProfOpen(key)
  local sc = self:FreshScan(key, rank)
  local cands, cost, avail = {}, {}, {}
  local stepD, stepA
  local function add(r, rs)
    tinsert(cands, r)
    cost[r] = self:RecipeCost(rs)
    if not open and rs then avail[r] = self:CanMake({ rc = rs }) or 0 else avail[r] = r.a or 0 end
  end
  local known = self:RecipeKnown(key, s.spell)
  if sc then
    stepD = s.spell and sc.colors[s.spell]
    -- выучен после скана окна (у учителя): цвет по порогам маршрута
    if stepD == nil and known and s.sk then stepD = D_BY_COLOR[self:RecipeColor(s, rank)] end
    -- запас на рецепт шага: из полного списка (в sc.list только 40 рецептов)
    stepA = sc.avail and s.spell and sc.avail[s.spell]
    for _, r in ipairs(sc.list) do
      if r.id == s.spell then
        stepA = r.a or stepA
      elseif r.id and r.d and r.d <= 1 then -- orange or yellow only: green is never an option
        add(r, r.rc or (self:SpellStep(key, r.id) or {}).rc)
      end
    end
  else
    local learned = self.char.scan[key] and self.char.scan[key].colors
    if not learned then return {} end -- окно профессии ещё не открывали: не с чем сравнивать
    local col = s.sk and self:RecipeColor(s, rank)
    stepD = col and D_BY_COLOR[col]
    if known == false then stepD = nil end
    local seen, p = {}, self.Profs[key]
    for _, rs in ipairs(p.steps) do
      local sp = rs.spell
      if rs.k == "craft" and sp and sp ~= s.spell and rs.sk and rs.rc and learned[sp] and not seen[sp] then
        seen[sp] = true
        local d = D_BY_COLOR[self:RecipeColor(rs, rank)]
        if d and d <= 1 then
          add({ id = sp, n = self:StepName(rs), i = self:StepIcon(rs, p), d = d }, rs.rc)
        end
      end
    end
  end
  if not open and s.rc then stepA = self:CanMake(s) end
  -- Сначала то, что можно сделать прямо сейчас, затем по цвету, затем
  -- что дешевле (рецепты без цены - после), затем по запасу.
  table.sort(cands, function(x, y)
    local xa, ya = avail[x] > 0, avail[y] > 0
    if xa ~= ya then return xa end
    if x.d ~= y.d then return x.d < y.d end
    local xc, yc = cost[x], cost[y]
    if xc and yc and xc ~= yc then return xc < yc end
    if (xc ~= nil) ~= (yc ~= nil) then return xc ~= nil end
    if avail[x] ~= avail[y] then return avail[x] > avail[y] end
    return (x.n or "") < (y.n or "")
  end)
  local stuck = stepA == 0 -- на шаг сейчас нет реагентов (nil - не знаем)
  local list = {}
  for i, r in ipairs(cands) do
    local a = avail[r]
    -- every orange or yellow recipe is an option: the player chooses
    tinsert(list, i)
    if #list >= (limit or 1) then break end
  end
  local out = {}
  for _, bi in ipairs(list) do tinsert(out, self:RecipeOffer(key, s, rank, cands, bi, avail, cost, stepD, known, stuck)) end
  return out
end

-- Recipes the character has not learned yet that would give skill right now
-- (orange or yellow at this skill) and can already be learned, each with
-- where to get it. Two sources: the recipes of the route, and the rest of
-- the game's own recipe list (read when the profession window opens) with
-- the thresholds from Data\Skills.lua.
-- The first one is the recommendation. Order: what a trainer or a vendor
-- gives before quests and drops; then what the reagents in the bags are
-- already enough for; then the larger share of reagents on hand; orange
-- before yellow; a trainer before a vendor; the cheaper craft.
-- The recipe of step s is left out: the step shows it itself.
local SRC_BY_KIND = { t = "trainer" }
function ns:LearnableRecipes(key, s, rank, limit)
  local p = self.Profs[key]
  local out, seen = {}, {}
  if not p then return out end
  local ORDER = { trainer = 0, vendor = 1, other = 2 }
  local function consider(rs)
    local sp = rs.spell
    if seen[sp] or (s and s.spell == sp) then return end
    seen[sp] = true
    local col = self:RecipeColor(rs, rank)
    if rank < (rs.sk[1] or 0) or not (col == "orange" or col == "yellow") or self:RecipeKnown(key, sp) ~= false then return end
    local src = self:RecipeSource(key, rs)
    -- reagents in the bags: for how many crafts, and how many of the reagents are there at all
    local rc, got, total = rs.rc, 0, 0
    for i = 1, rc and #rc - 1 or 0, 2 do
      total = total + 1
      if self:BagCount(rc[i]) >= math.max(1, rc[i + 1] or 1) then got = got + 1 end
    end
    tinsert(out, { s = rs, color = col, src = src, d = D_BY_COLOR[col], o = ORDER[src.kind] or 2, cost = self:RecipeCost(rc),
      easy = (src.kind == "trainer" or src.kind == "vendor") and 0 or 1,
      a = rc and self:CanMake({ rc = rc }) or 0, got = got, total = total })
  end
  for _, rs in ipairs(p.steps) do
    if rs.k == "craft" and rs.spell and rs.sk then consider(rs) end
  end
  local skill = self.RecipeSkill and self.RecipeSkill[key]
  local base = self.db and self.db.recipes and self.db.recipes[key]
  for sp, r in pairs(skill and base or {}) do
    local t = skill[sp]
    -- a recipe with no known source and no source text from the game cannot be recommended
    if t and (t[5] ~= "o" or r.src) then
      consider({ k = "craft", spell = sp, sk = t, rc = r.rc, src = SRC_BY_KIND[t[5]] or "other", info = r.src, name = r.n, tex = r.i })
    end
  end
  table.sort(out, function(x, y)
    if x.easy ~= y.easy then return x.easy < y.easy end
    if (x.a > 0) ~= (y.a > 0) then return x.a > 0 end
    local xs, ys = x.total > 0 and x.got / x.total or 0, y.total > 0 and y.got / y.total or 0
    if xs ~= ys then return xs > ys end
    if x.d ~= y.d then return x.d < y.d end
    if x.o ~= y.o then return x.o < y.o end
    if x.cost and y.cost and x.cost ~= y.cost then return x.cost < y.cost end
    if (x.cost ~= nil) ~= (y.cost ~= nil) then return x.cost ~= nil end
    return (x.s.spell or 0) < (y.s.spell or 0)
  end)
  for i = #out, (limit or 3) + 1, -1 do out[i] = nil end
  return out
end

-- The same as ready rows for the page and the mini window, and the heading.
-- On the right: how many crafts the reagents in the bags are enough for, or
-- how many of the reagents are there. A click sets the map pin on the nearest
-- trainer or vendor; a recipe from a quest or a drop has nobody to go to, so
-- the click opens it instead.
function ns:LearnRows(key, s, rank, limit)
  local T, rows = ns.T, {}
  local why, hint, enough, part = T("Ещё не выучен, а навык сейчас даст."), T("Щелчок поставит метку и откроет карту."), T("хватит на %d"), T("реагенты: %d из %d")
  for k, e in ipairs(self:LearnableRecipes(key, s, rank, limit)) do
    local src, rs = e.src, e.s
    local npc, vendor, spell = src.npc, src.kind == "vendor", rs.spell
    local name = rs.name or self:StepName(rs)
    local where = npc and (self:NpcName(npc) .. ", " .. self:NpcZone(npc)) or (src.info and T(src.info)) or ""
    local price = vendor and (src.copper and self.W.Money(src.copper) or src.price) or nil
    if npc and price then where = where .. ", " .. price end
    if npc and src.extra then where = where .. ", " .. src.extra end
    local right = (e.a > 0 and format(enough, e.a)) or (e.got > 0 and format(part, e.got, e.total)) or nil
    rows[k] = { icon = rs.tex or self:StepIcon(rs, self.Profs[key]), name = name, text = self:Hex(e.color) .. name .. "|r", where = where,
      right = right, why = why, hint = npc and hint or nil,
      onClick = function() if npc then ns:Waypoint(npc, true) else ns:OpenRecipe(key, spell) end end }
  end
  return rows, T("Можно выучить")
end

-- Описание одного варианта для BestRecipes.
function ns:RecipeOffer(key, s, rank, cands, bi, avail, cost, stepD, known, stuck)
  local best = cands[bi]
  local a = avail[best]
  local left = self:RemainingCrafts(s, rank)
  local out = { id = best.id, name = best.n, icon = best.i, color = COLOR_BY_D[best.d], a = a, cost = cost[best],
    sameColor = stepD ~= nil and best.d == stepD, worse = stepD ~= nil and best.d > stepD, better = stepD ~= nil and best.d < stepD,
    unknownStep = known == false,
    instead = (stuck or known == false) and a > 0,
    -- сколько делать: не больше, чем осталось до конца шага
    n = left > 0 and min(a, left) or a }
  -- Шанс навыка: если рецепт есть в маршруте, у нас есть его пороги цветов.
  local rs = self:SpellStep(key, best.id)
  if rs then out.chance = self:ChanceText(rs, rank, out.color) end
  -- Почему этот, а не соседний того же цвета: он дешевле.
  local nx = cands[bi + 1]
  if nx and nx.d == best.d and (avail[nx] > 0) == (a > 0) and out.cost and cost[nx] and cost[nx] > out.cost then
    out.cheaperBy, out.cheaperThan = cost[nx] - out.cost, nx.n
  end
  return out
end

-------------------------------------------------------------------------------
--  Почта: купленное на аукционе ждёт в ящике - считаем его своим, чтобы
--  не купить второй раз. Ящик читаем, пока он открыт; покупку добавляем
--  сразу, как аукцион её подтвердит.
-------------------------------------------------------------------------------
ns.MAIL_COLOR = "|cff66b8ff" -- голубой: «на почте», как у почтовых писем

local function secret(v) return issecretvalue ~= nil and issecretvalue(v) end
-- Ящик открыт - по событиям игры, а не по окну: почтовые аддоны прячут MailFrame.
local mailOpen = false
local function MailOpen() return mailOpen end

function ns:MailCount(id)
  local m = self.char and self.char.mail
  return m and m[id] or 0
end

function ns:ScanMail()
  if not (self.char and MailOpen() and GetInboxNumItems and GetInboxItem) then return end
  local counts = {}
  for i = 1, GetInboxNumItems() or 0 do
    local _, _, _, _, _, cod, _, hasItem = GetInboxHeaderInfo(i)
    -- письма без вложений пропускаем (hasItem - сколько их; нет поля - смотрим всё)
    if (not cod or cod == 0) and hasItem ~= false and hasItem ~= 0 then -- наложенный платёж - ещё не твоё
      for j = 1, ATTACHMENTS_MAX_RECEIVE or 16 do
        local link = GetInboxItemLink and GetInboxItemLink(i, j)
        local id = type(link) == "string" and not secret(link) and tonumber(link:match("item:(%d+)"))
        if id then
          -- новые клиенты: имя, id, значок, число; старые: имя, значок, число
          local _, b, c, d = GetInboxItem(i, j)
          local n = tonumber(b == id and d or c) or 1
          counts[id] = (counts[id] or 0) + n
        end
      end
    end
  end
  self.char.mail = counts
  self.needCache = nil
  self:RefreshAll()
end

-- Куплено на аукционе: уже наше, ждёт на почте.
function ns:AddBought(id, qty)
  if type(id) ~= "number" or type(qty) ~= "number" or qty <= 0 or not self.char then return end
  if MailOpen() then return end -- ящик открыт: его чтение посчитает само
  local m = self.char.mail or {}
  self.char.mail = m
  m[id] = (m[id] or 0) + qty
  self.needCache = nil
  -- в чат - один раз на предмет за визит на аукцион, а не на каждую пачку
  self.boughtSaid = self.boughtSaid or {}
  if self:AllNeeds()[id] and not self.boughtSaid[id] then
    self.boughtSaid[id] = true
    self:Print(format(ns.T("%s: покупка ждёт на почте."), self:ItemName(id)))
  end
  self:RefreshAll()
end

local mailEv = CreateFrame("Frame")
local mailOn = {}
local function onMail(e, fn) mailOn[e] = fn; pcall(mailEv.RegisterEvent, mailEv, e) end
mailEv:SetScript("OnEvent", function(_, e, ...) local fn = mailOn[e]; if fn then ns:Safe(fn, ...) end end)

local mailScanQueued
local function queueMailScan(delay)
  if mailScanQueued then return end
  mailScanQueued = true
  C_Timer.After(delay, function() mailScanQueued = nil; ns:Safe(ns.ScanMail, ns) end)
end
onMail("MAIL_SHOW", function() mailOpen = true; queueMailScan(0.5) end)
onMail("MAIL_INBOX_UPDATE", function() if mailOpen then queueMailScan(0.1) end end)
-- закрыли ящик: прочитать его в последний раз сразу, пока игра помнит письма
onMail("MAIL_CLOSED", function()
  if mailOpen then ns:Safe(ns.ScanMail, ns) end
  mailOpen = false
end)

-- Аукцион нового вида: товары в стопках («commodities»).
local AH = C_AuctionHouse
if AH and AH.ConfirmCommoditiesPurchase then
  local last
  hooksecurefunc(AH, "ConfirmCommoditiesPurchase", function(itemID, quantity)
    if secret(itemID) or secret(quantity) then return end
    last = { id = itemID, qty = quantity }
  end)
  -- клиенты шлют одно из двух: что пришло первым, то и считаем, один раз
  onMail("COMMODITY_PURCHASE_SUCCEEDED", function()
    if last then ns:AddBought(last.id, last.qty); last = nil end
  end)
  onMail("COMMODITY_PURCHASED", function(itemID, quantity)
    if last and not secret(itemID) and last.id == itemID then
      ns:AddBought(itemID, (not secret(quantity) and tonumber(quantity)) or last.qty); last = nil
    end
  end)
  onMail("COMMODITY_PURCHASE_FAILED", function() last = nil end)
end

-- Аукцион нового вида, отдельный лот: только выкуп (ставку могут перебить).
if AH and AH.PlaceBid and AH.GetAuctionInfoByID then
  local buying = {}
  -- сколько штук в лоте: у самого лота этого нет, берём из результатов поиска
  local function LotQty(itemKey, auctionID)
    local n = AH.GetNumItemSearchResults and AH.GetNumItemSearchResults(itemKey) or 0
    for i = 1, n do
      local r = AH.GetItemSearchResultInfo and AH.GetItemSearchResultInfo(itemKey, i)
      if r and r.auctionID == auctionID then return r.quantity end
    end
  end
  hooksecurefunc(AH, "PlaceBid", function(auctionID, bid)
    if secret(auctionID) or secret(bid) then return end
    pcall(function()
      local info = AH.GetAuctionInfoByID(auctionID)
      local key = info and info.itemKey
      local buyout = info and info.buyoutAmount
      if key and key.itemID and buyout and buyout > 0 and bid and bid >= buyout then
        buying[auctionID] = { id = key.itemID, qty = LotQty(key, auctionID) or 1 }
      end
    end)
  end)
  onMail("AUCTION_HOUSE_PURCHASE_COMPLETED", function(auctionID)
    local b = not secret(auctionID) and buying[auctionID]
    if b then buying[auctionID] = nil; ns:AddBought(b.id, b.qty) end
  end)
end

-- Аукцион закрыли: сообщения о покупках в чат - заново.
onMail("AUCTION_HOUSE_CLOSED", function()
  ns.boughtSaid = nil
end)

-------------------------------------------------------------------------------
--  Купить у торговца: при открытом торговце - кнопка под его окном, которая
--  докупает только недостающие реагенты (колбы, нитки, соль и т. п.).
-------------------------------------------------------------------------------
local function MerchantOpen() return MerchantFrame and MerchantFrame:IsShown() end

-- Что из покупок продаёт этот торговец: { index, id, buy, stack, bundles, cost }.
function ns:MerchantNeeds()
  local out = {}
  if not (MerchantOpen() and GetMerchantNumItems and GetMerchantItemID) then return out end
  local all = self:AllNeeds()
  for i = 1, GetMerchantNumItems() or 0 do
    local id = GetMerchantItemID(i)
    local a = id and all[id]
    if a and a.buy > 0 then
      local price, stack, avail
      if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local info = C_MerchantFrame.GetItemInfo(i)
        price, stack, avail = info and info.price, info and info.stackCount, info and info.numAvailable
      end
      stack = math.max(1, stack or 1)
      local bundles = math.ceil(a.buy / stack)
      if avail and avail >= 0 then bundles = math.min(bundles, avail) end -- -1 = без ограничения
      if bundles > 0 and price then
        tinsert(out, { index = i, id = id, buy = a.buy, stack = stack, bundles = bundles, cost = bundles * price })
      end
    end
  end
  return out
end

-- only: the merchant slot of the one item to buy; nil - everything needed
function ns:BuyFromMerchant(only)
  if not MerchantOpen() then return end
  if InCombatLockdown and InCombatLockdown() then
    self:Print(ns.T("в бою покупать нельзя."))
    return
  end
  local list = self:MerchantNeeds()
  if only then
    local one = {}
    for _, e in ipairs(list) do
      if e.index == only then one[#one + 1] = e end
    end
    list = one
  end
  local money = GetMoney and GetMoney() or 0
  local bought, spent, short = 0, 0, false
  for _, e in ipairs(list) do
    local per = e.cost / e.bundles
    local can = per > 0 and math.min(e.bundles, math.floor((money - spent) / per)) or e.bundles
    if can < e.bundles then short = true end
    if can > 0 then
      if e.stack > 1 then
        for _ = 1, can do BuyMerchantItem(e.index) end -- одна пачка за раз
      else
        local maxStack = (GetMerchantItemMaxStack and GetMerchantItemMaxStack(e.index)) or 20
        local left = can
        while left > 0 do
          local q = math.min(left, math.max(1, maxStack))
          BuyMerchantItem(e.index, q)
          left = left - q
        end
      end
      bought = bought + can * e.stack
      spent = spent + can * per
    end
  end
  if bought > 0 then
    self:Print(format(ns.T("куплено у торговца: %d шт. за %s."), bought, ns.W.Money(spent)))
  end
  if short then self:Print(ns.T("не хватило денег на всё: купил, сколько смог.")) end
  self.needCache = nil
end

-- The hint beside the merchant window, in the same form as the ones at the
-- bank and the auction house: a row per item with its own "Buy" button, the
-- total, and "Buy all" at the bottom.
local MERCHANT_W = 400
local merchantPanel
function ns:UpdateMerchantButton()
  local list = MerchantOpen() and self:MerchantNeeds() or {}
  if #list == 0 then
    if merchantPanel then merchantPanel:Hide() end
    return
  end
  local W, T = ns.W, ns.T
  if not merchantPanel then
    merchantPanel = W.HintPanel("EasyCraftMerchantPanel", MERCHANT_W, T("Купить нужные реагенты"), "merchant")
  end
  local f = merchantPanel
  f:Reset()
  local y = f.top
  local total, count = 0, 0
  for _, e in ipairs(list) do
    local n = e.bundles * e.stack
    local index = e.index
    total, count = total + e.cost, count + n
    y = f:Row({ id = e.id, count = n, btn = T("Купить"), right = W.Money(e.cost),
      tip = format(T("Купить %d"), n) .. ": " .. W.Money(e.cost),
      onClick = function() ns:BuyFromMerchant(index) end }, y)
  end
  y = f:EndList(y)
  y = f:Head(T("Всего: ") .. W.Money(total), y + 3) + 2
  f.btn:Show()
  local h = f:Button(format(T("Купить всё (%d)"), count), true, function() ns:BuyFromMerchant() end,
    T("Докупит только то, чего не хватает до следующего учителя."), y + 2)
  f:SetHeight(h)
  if not W.PlaceSaved(f, "merchant") then
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", MerchantFrame, "TOPRIGHT", 4, 0)
  end
  f:Show()
end

-------------------------------------------------------------------------------
--  Забрать из банка: при открытом банке - блок рядом с его окном: по
--  профессиям, что из банка нужно для шагов до учителя. Отмеченное
--  переносится в сумки целыми стопками, как правый щелчок.
-------------------------------------------------------------------------------
local CT = C_Container
local GetSlots = CT.GetContainerNumSlots
local GetFree = CT.GetContainerNumFreeSlots
local UseItem = CT.UseContainerItem
local bankOpen = false

local function SlotInfo(bag, slot)
  if CT and CT.GetContainerItemInfo then
    local info = CT.GetContainerItemInfo(bag, slot)
    return info and info.itemID, info and info.stackCount, info and info.isLocked
  end
end

-- Банк: вкладки нового банка (свой и общий) или старый банк с сумками.
local function BankBags()
  local ids, seen = {}, {}
  local function add(id) if id and not seen[id] then seen[id] = true; tinsert(ids, id) end end
  local own = 0 -- вкладок личного банка
  if C_Bank and C_Bank.FetchPurchasedBankTabIDs and Enum and Enum.BankType then
    for _, t in ipairs({ Enum.BankType.Character or false, Enum.BankType.Account or false }) do
      if t then
        local ok, list = pcall(C_Bank.FetchPurchasedBankTabIDs, t)
        if ok and type(list) == "table" then
          for _, id in ipairs(list) do add(id) end
          if t == Enum.BankType.Character then own = #list end
        end
      end
    end
  end
  if own == 0 then -- личный банк старого вида: -1 и сумки банка
    add(-1)
    local first = (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) + 1
    for b = first, first + (7) - 1 do add(b) end
  end
  return ids
end

-- Свободные места: обычные сумки (сумки профессий не считаем - туда лезет не всё)
-- и отдельно сумка реагентов, куда идут только ремесленные товары.
local function BagFreeSlots()
  local plain, reagent = 0, 0
  if not GetFree then return 0, 0 end
  for b = 0, NUM_BAG_SLOTS or 4 do
    local free, family = GetFree(b)
    if (family or 0) == 0 then plain = plain + (free or 0) end
  end
  local last = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
  for b = (NUM_BAG_SLOTS or 4) + 1, last do reagent = reagent + (GetFree(b) or 0) end
  return plain, reagent
end

local ItemInstant = C_Item.GetItemInfoInstant
local function IsTradeGood(id)
  return ItemInstant and select(6, ItemInstant(id)) == 7 -- 7: ремесленные товары
end

-- Что лежит в банке: id -> штук.
local function BankStock()
  local stock = {}
  if not GetSlots then return stock end
  for _, bag in ipairs(BankBags()) do
    for slot = 1, GetSlots(bag) or 0 do
      local id, n = SlotInfo(bag, slot)
      if id then stock[id] = (stock[id] or 0) + (n or 1) end
    end
  end
  return stock
end

-- Чего не хватает в сумках каждой профессии: key -> { id -> штук }.
-- То, что уже в сумках, достаётся профессиям по порядку списка.
function ns:BankLacks()
  local lack = {}
  for id, a in pairs(self:AllNeeds()) do
    local bags = self:BagCount(id)
    for _, pr in ipairs(a.profs) do
      local covered = math.min(pr.need, bags)
      bags = bags - covered
      local n = pr.need - covered
      if n > 0 then
        lack[pr.key] = lack[pr.key] or {}
        lack[pr.key][id] = (lack[pr.key][id] or 0) + n
      end
    end
  end
  return lack
end

-- Выбор в окне у банка: снятые профессии и предметы (до перезахода).
ns.bankOff = ns.bankOff or { prof = {}, item = {} }

-- Какие стопки забрать: чего в сумках меньше, чем нужно отмеченным
-- профессиям (и отмеченным предметам).
function ns:BankPlan()
  local off = self.bankOff
  local want = {}
  for key, ids in pairs(self:BankLacks()) do
    if not off.prof[key] then
      for id, n in pairs(ids) do
        if not off.item[id] then want[id] = (want[id] or 0) + n end
      end
    end
  end
  local plan, count = {}, 0
  if not next(want) or not GetSlots then return plan, 0 end
  for _, bag in ipairs(BankBags()) do
    for slot = 1, GetSlots(bag) or 0 do
      local id, n, locked = SlotInfo(bag, slot)
      if id and not locked and (want[id] or 0) > 0 then
        tinsert(plan, { bag = bag, slot = slot, id = id, n = n or 1 })
        count = count + math.min(n or 1, want[id]) -- сколько нужно, а не размер стопок
        want[id] = want[id] - (n or 1)
      end
    end
  end
  return plan, count
end

function ns:TakeFromBank()
  if not (bankOpen and UseItem) then return end
  if InCombatLockdown and InCombatLockdown() then return end
  local plan = self:BankPlan()
  local plain, reagent = BagFreeSlots()
  local moved, MAX_PER_CLICK = 0, 12 -- больше за раз сервер может не принять
  for _, e in ipairs(plan) do
    if moved >= MAX_PER_CLICK then break end
    if reagent > 0 and IsTradeGood(e.id) then reagent = reagent - 1
    elseif plain > 0 then plain = plain - 1
    else break end
    UseItem(e.bag, e.slot)
    moved = moved + 1
  end
  if moved < #plan then
    if moved >= MAX_PER_CLICK then
      self:Print(ns.T("забрал часть - нажми кнопку ещё раз."))
    else
      self:Print(format(ns.T("Сумки полны: забрал стопок %d из %d."), moved, #plan))
    end
  end
end

-- Все ремесленные товары (реагенты профессий) из сумок - в банк. Игра
-- переносит за раз немного: по 12 стопок с паузой, пока всё не уйдёт или
-- банк не заполнится.
local function BagReagents()
  local list = {}
  if not GetSlots then return list end
  local last = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
  for b = 0, last do
    for slot = 1, GetSlots(b) or 0 do
      local id = SlotInfo(b, slot)
      if id and IsTradeGood(id) then tinsert(list, { bag = b, slot = slot }) end
    end
  end
  return list
end

function ns:DepositReagents(prev)
  if not (bankOpen and UseItem) then return end
  if InCombatLockdown and InCombatLockdown() then return end
  local list = BagReagents()
  if #list == 0 then
    if prev then self:Print(ns.T("все реагенты в банке.")) end
    return
  end
  if prev and #list >= prev then
    self:Print(ns.T("банк полон: часть реагентов осталась в сумках."))
    return
  end
  for i = 1, math.min(#list, 12) do UseItem(list[i].bag, list[i].slot) end
  local n = #list
  C_Timer.After(0.4, function() ns:DepositReagents(n) end)
end

-- The game's bank window while it is shown; otherwise the block goes to the top of the screen.
local function BankWindow()
  if BankFrame and BankFrame:IsVisible() then return BankFrame end
end

-------------------------------------------------------------------------------
--  Блок у банка: по профессиям - что из банка нужно для шагов до учителя.
--  Галочка у профессии и щелчок по значку предмета выбирают, что забрать;
--  внизу «Забрать отмеченное».
-------------------------------------------------------------------------------
local BANK_W = 340 -- заголовок «Забрать нужные реагенты» крупно, рядом кнопка закрепления
local bankPanel

local function BankPanel()
  if not bankPanel then bankPanel = ns.W.HintPanel("EasyCraftBankPanel", BANK_W, ns.T("Забрать нужные реагенты"), "bank") end
  return bankPanel
end

local READY, NOT_READY = "Interface\\RaidFrame\\ReadyCheck-Ready", "Interface\\RaidFrame\\ReadyCheck-NotReady"

function ns:UpdateBankButton()
  if not bankOpen then
    if bankPanel then bankPanel:Hide() end
    return
  end
  local W, T = ns.W, ns.T
  local lacks = self:BankLacks()
  local stock = BankStock()
  local off = self.bankOff
  -- профессии, которым есть что взять из банка; запас банка делится
  -- по профессиям по порядку, чтобы сумма строк не была больше, чем есть
  local profs = {}
  for _, key in ipairs(self:LearnedList()) do
    local ids = lacks[key]
    if ids then
      local items = {}
      for id, n in pairs(ids) do
        local inBank = math.min(n, stock[id] or 0)
        if inBank > 0 then
          tinsert(items, { id = id, n = inBank })
          stock[id] = stock[id] - inBank
        end
      end
      if #items > 0 then
        table.sort(items, function(x, z) return x.id < z.id end)
        tinsert(profs, { key = key, items = items })
      end
    end
  end
  local inBags = #BagReagents()
  if #profs == 0 and inBags == 0 then
    if bankPanel then bankPanel:Hide() end
    return
  end
  local f = BankPanel()
  f:Reset()
  local y = f.top
  if #profs == 0 then y = f:Note(T("Из банка для шагов брать нечего."), y) end
  for k, pr in ipairs(profs) do
    local p = self.Profs[pr.key]
    local key = pr.key
    local on = not off.prof[key]
    local total = 0
    for _, it in ipairs(pr.items) do total = total + it.n end
    if k > 1 then y = y + 4 end
    -- профессия: галочка, название и сколько всего - одной линией
    y = f:CheckHead(self:N(p), format(T("%d шт."), total), on, function(v)
      off.prof[key] = (not v) or nil
      ns:UpdateBankButton()
    end, y)
    -- каждый предмет - своя строка: справа сколько и знак «беру / не беру»
    for _, it in ipairs(pr.items) do
      local id = it.id
      local itemOn = on and not off.item[id]
      y = f:Row({ id = id, dim = not itemOn, mark = itemOn and READY or NOT_READY, markGrey = not itemOn,
        right = (itemOn and "|cffffffff" or "|cff9d9d9d") .. it.n .. "|r",
        tip = itemOn and T("Щелчок - не брать этот предмет.") or T("Щелчок - снова брать этот предмет."),
        onClick = function()
          if not on then
            -- профессия снята: щелчок по её предмету снова берёт и его, и профессию
            off.prof[key] = nil
            off.item[id] = nil
          else
            off.item[id] = (not off.item[id]) or nil
          end
          ns:UpdateBankButton()
        end }, y)
    end
  end
  y = f:EndList(y)
  local h = y
  f.btn:SetShown(#profs > 0)
  if #profs > 0 then
    local _, count = self:BankPlan()
    h = f:Button(count > 0 and format(T("Забрать отмеченное (%d)"), count) or T("Ничего не отмечено"), count > 0,
      function() ns:TakeFromBank() end, T("Перенесёт в сумки отмеченное - целыми стопками."), y + 2)
    h = h - 8
  end
  -- и обратно: все реагенты из сумок - в банк
  h = f:Button(inBags > 0 and format(T("Убрать все реагенты в банк (%d)"), inBags) or T("Реагентов в сумках нет"), inBags > 0,
    function() ns:DepositReagents() end, T("Перенесёт в банк все ремесленные товары из сумок: руду, травы, ткань, кожу и прочие реагенты."),
    h + 2, true)
  f:SetHeight(h)
  if not W.PlaceSaved(f, "bank") then
    local win = BankWindow()
    f:ClearAllPoints()
    if win then f:SetPoint("TOPLEFT", win, "TOPRIGHT", 4, 0) else f:SetPoint("TOP", UIParent, "TOP", 0, -110) end
  end
  f:Show()
end

local bankEv = CreateFrame("Frame")
local bankQueued
local function bankRefresh()
  if bankQueued then return end
  bankQueued = true
  C_Timer.After(0.3, function() bankQueued = nil; ns:Safe(ns.UpdateBankButton, ns) end)
end
for _, e in ipairs({ "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED", "BAG_UPDATE_DELAYED" }) do
  pcall(bankEv.RegisterEvent, bankEv, e)
end
bankEv:SetScript("OnEvent", function(_, e)
  if e == "BANKFRAME_OPENED" then bankOpen = true
  elseif e == "BANKFRAME_CLOSED" then bankOpen = false; if bankPanel then bankPanel:Hide() end; return
  elseif not bankOpen then return end
  bankRefresh()
end)

-------------------------------------------------------------------------------
--  Подсказка у аукциона - в том же виде, что подсказка у окна профессии:
--  светлый пергамент, заголовки чернилами, строки - тёмные блоки. Что
--  купить для текущих шагов (по профессиям), каждый предмет - отдельной
--  строкой со своей кнопкой поиска; внизу итог.
--  Для текущих шагов всё есть - что купить дальше, до учителя.
-------------------------------------------------------------------------------
local AH_W, AH_PAD, AH_ROW, AH_MAX = 400, 12, 34, 60 -- список прокручивается
local ahPanel

-- Find one item at the auction house with the game's own search.
function ns:SearchAuction(id, buy)
  local name = self:ClientItemName(id)
  if not name then self:Print(ns.T("названия предметов ещё загружаются: нажми ещё раз через секунду.")) return end
  local ok = false
  local bar = AuctionHouseFrame and AuctionHouseFrame.SearchBar
  if bar and bar.SearchBox and bar.StartSearch then
    ok = pcall(function() bar.SearchBox:SetText(name); bar:StartSearch() end)
  end
  if not ok then self:Print(format(ns.T("найди на аукционе: %s"), name)) end
end

local function AuctionWindow()
  if AuctionHouseFrame and AuctionHouseFrame:IsVisible() then return AuctionHouseFrame end
end

local function AhPanel()
  if not ahPanel then ahPanel = ns.W.HintPanel("EasyCraftAuctionPanel", AH_W, ns.T("Купить нужные реагенты"), "ah") end
  return ahPanel
end

-- Что купить на аукционе для текущих шагов: { {key, s, pos, b}, ... }.
function ns:AuctionNeeds()
  local out, pool = {}, {}
  for _, key in ipairs(self:LearnedList()) do
    local rank, maxRank = self:GetSkill(key)
    local i, s = self:CurrentStep(key, rank, maxRank)
    if s and s.k == "craft" and (s.rc or s.m) then
      local left = self:RemainingCrafts(s, rank)
      if left > 0 then
        local b = self:StepBuy(s, left, pool)
        if #b.auction > 0 then tinsert(out, { key = key, s = s, i = i, b = b }) end
      end
    end
  end
  return out
end

function ns:UpdateAuctionPanel()
  local win = AuctionWindow()
  if not win then
    if ahPanel then ahPanel:Hide() end
    return
  end
  local W, T = ns.W, ns.T
  local f = AhPanel()
  f:Reset()
  local y = f.top
  local shown, hidden = 0, 0
  local all, allIdx, total, noPrice = {}, {}, 0, 0
  local function row(id, buy, cost)
    if allIdx[id] then all[allIdx[id]].buy = all[allIdx[id]].buy + buy
    else tinsert(all, { id = id, buy = buy }); allIdx[id] = #all end
    if cost then total = total + cost else noPrice = noPrice + 1 end
    if shown >= AH_MAX then hidden = hidden + 1; return end
    shown = shown + 1
    -- every item has its own row with a "Find" button: the button and a click on the row both search for it
    -- сколько купить - числом на значке, справа только цена
    y = f:Row({ id = id, count = buy, btn = T("Найти"),
      right = cost and W.Money(cost) or ("|cff9d9d9d" .. T("нет цены") .. "|r"),
      tip = format(T("Купить %d"), buy) .. (cost and (": " .. W.Money(cost)) or "") .. "\n" .. T("Щелчок - найти на аукционе."),
      onClick = function() ns:SearchAuction(id, buy) end }, y)
  end
  -- 1. Текущие шаги: по профессиям
  local list = self:AuctionNeeds()
  for k, e in ipairs(list) do
    local p = self.Profs[e.key]
    local noRecipe = self:RecipeKnown(e.key, e.s.spell) == false
    if k > 1 then y = y + 4 end
    y = f:Head(self:N(p) .. ": " .. self:StepName(e.s) .. (noRecipe and ("  |cffa03000" .. T("(сначала рецепт)") .. "|r") or ""), y)
    for _, it in ipairs(e.b.items) do
      if it.buy > 0 and not it.vendor then row(it.id, it.buy, it.cost) end
    end
  end
  -- 2. На текущие шаги всё есть - что купить дальше, до учителя
  if #list == 0 then
    local rest = {}
    for id, a in pairs(self:AllNeeds()) do
      if a.buy > 0 and not self:IsVendorItem(id) then tinsert(rest, { id = id, buy = a.buy }) end
    end
    if #rest > 0 then
      table.sort(rest, function(x, z) return x.buy > z.buy end)
      -- что уже есть - не пишем: только чего не хватает
      y = f:Head(T("Дальше, до учителя"), y)
      for _, e in ipairs(rest) do
        local pr = self:AuctionPrice(e.id)
        row(e.id, e.buy, pr and pr * e.buy or nil)
      end
    end
  end
  if shown == 0 then f:Hide(); return end -- покупать нечего
  if hidden > 0 then y = f:Head(format(T("и ещё %d"), hidden), y) end
  y = f:EndList(y)
  -- 3. Итог и «Найти всё»
  local sum
  if not self:PriceSource() then sum = "|cffa03000" .. T("Цен нет: открой аукцион - EasyCraft прочитает их сам") .. "|r"
  elseif total > 0 then
    sum = T("Всего: ") .. W.Money(total) .. (noPrice > 0 and ("  " .. format(T("(и ещё %d без цены)"), noPrice)) or "")
  end
  if sum then y = f:Head(sum, y + 3) + 2 end
  -- кнопки «найти всё» нет: у игры поиск по одному предмету - лупа в строке
  f.btn:Hide()
  f:SetHeight(y + 10)
  if not W.PlaceSaved(f, "ah") then
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", win, "TOPRIGHT", 4, 0)
  end
  f:Show()
end

-- Окно аукциона появляется чуть позже события, а при первом открытии игра
-- ещё догружает его код: пробуем несколько раз и ловим само появление окна.
local function ahSoon()
  for _, t in ipairs({ 0.1, 0.5, 1.2 }) do
    C_Timer.After(t, function() if not (ahPanel and ahPanel:IsShown()) then ns:Safe(ns.UpdateAuctionPanel, ns) end end)
  end
end
local hookedAH = {}
local function hookAH()
  for _, n in ipairs({ "AuctionHouseFrame" }) do
    local w = _G[n]
    if type(w) == "table" and w.HookScript and not hookedAH[n] then
      hookedAH[n] = true
      w:HookScript("OnShow", ahSoon)
      w:HookScript("OnHide", function() if ahPanel then ahPanel:Hide() end end)
    end
  end
end
local ahEv = CreateFrame("Frame")
for _, e in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "ADDON_LOADED" }) do pcall(ahEv.RegisterEvent, ahEv, e) end
ahEv:SetScript("OnEvent", function(_, e, name)
  if e == "ADDON_LOADED" then
    if name == "Blizzard_AuctionHouseUI" or name == "Blizzard_AuctionUI" then hookAH() end
    return
  end
  if e == "AUCTION_HOUSE_CLOSED" then if ahPanel then ahPanel:Hide() end return end
  hookAH()
  ahSoon()
end)
-- купил (ушло на почту), цены обновились, сумки изменились - пересчитать
ns:RegisterRefresh(function() if ahPanel and ahPanel:IsShown() then ns:UpdateAuctionPanel() end end)

-------------------------------------------------------------------------------
--  Напоминания в поле: поиск руды или трав выключен; есть наживка, а удочка
--  без неё.
-------------------------------------------------------------------------------
local FIND = { mining = 2580, herbalism = 2383 } -- «Поиск минералов», «Поиск трав»

local function SpellNameByID(id)
  if C_Spell and C_Spell.GetSpellName then
    local ok, n = pcall(C_Spell.GetSpellName, id)
    if ok and n then return n end
  end
end

-- Поиск на миникарте для профессии: {index, name, icon, active} или nil (нет такого поиска).
function ns:FindTracking(key)
  local spell = FIND[key]
  local M = C_Minimap
  if not (spell and M and M.GetNumTrackingTypes and M.GetTrackingInfo) then return nil end
  local want = SpellNameByID(spell)
  for i = 1, M.GetNumTrackingTypes() or 0 do
    local a, b, c, _, _, f = M.GetTrackingInfo(i)
    local name, icon, active, sid
    if type(a) == "table" then name, icon, active, sid = a.name, a.texture, a.active, a.spellID
    else name, icon, active, sid = a, b, c, f end
    if (sid and sid == spell) or (want and name == want) then
      return { index = i, name = name, icon = icon, active = active and true or false }
    end
  end
end

-- Включён ли хоть один поиск сбора: в классике отслеживать можно что-то одно,
-- и у горняка-травника не надо просить включить второй.
function ns:AnyFindActive()
  for key in pairs(FIND) do
    local t = self:FindTracking(key)
    if t and t.active then return true end
  end
  return false
end

function ns:EnableFindTracking(key)
  local t = self:FindTracking(key)
  if t and C_Minimap and C_Minimap.SetTracking then pcall(C_Minimap.SetTracking, t.index, true) end
end

-- Поиск включили или выключили (и после смерти): перерисовать.
local trackEv = CreateFrame("Frame")
pcall(trackEv.RegisterEvent, trackEv, "MINIMAP_UPDATE_TRACKING")
trackEv:SetScript("OnEvent", function()
  C_Timer.After(0.3, function() ns:RefreshAll() end)
end)

-- Наживка: {id, +к ловле, с какого навыка}, лучшая первой.
local LURES = { { 6533, 100, 100 }, { 6532, 75, 100 }, { 7307, 75, 100 }, { 6530, 50, 50 }, { 6811, 50, 50 }, { 6529, 25, 1 } }

-- Есть подходящая наживка, удочка в руках и без неё: id наживки и прибавка.
function ns:LureHint(rank)
  local pole = GetInventoryItemID and GetInventoryItemID("player", 16)
  local info = C_Item.GetItemInfoInstant
  if not (pole and info) then return nil end
  local classID, subID = select(6, info(pole))
  if classID ~= 2 or subID ~= 20 then return nil end -- не удочка
  if GetWeaponEnchantInfo and GetWeaponEnchantInfo() then return nil end -- наживка уже стоит
  for _, l in ipairs(LURES) do
    if rank >= l[3] and self:BagCount(l[1]) > 0 then return l[1], l[2] end
  end
end

-------------------------------------------------------------------------------
--  Что плавить сейчас (горное дело): по настоящим цветам из окна горного
--  дела, а пока его не открывали - по маршруту Forever.
-------------------------------------------------------------------------------
-- {слиток, с навыка, до навыка}: «Медь до 65, олово 65-75, бронза 75-105,
-- серебро 105-120, железо до 135, золото 155-175» (заметка маршрута).
local SMELT = { { 2840, 1, 65 }, { 3576, 65, 75 }, { 2841, 75, 105 }, { 2842, 105, 120 }, { 3575, 125, 135 }, { 3577, 155, 175 } }

function ns:SmeltNow(rank)
  local sc = self:FreshScan("mining", rank)
  if sc and sc.list then
    -- оранжевый или жёлтый; сначала то, на что есть руда, затем по цвету и запасу
    local function score(r) return ((r.a or 0) > 0 and 0 or 10) + r.d end
    local best
    for _, r in ipairs(sc.list) do
      if r.id and r.d and r.d <= 1 then
        if not best or score(r) < score(best) or (score(r) == score(best) and (r.a or 0) > (best.a or 0)) then best = r end
      end
    end
    if best then return { id = best.id, name = best.n, color = COLOR_BY_D[best.d], a = best.a or 0, real = true } end
    return nil
  end
  for _, e in ipairs(SMELT) do
    if rank >= e[2] and rank < e[3] then return { item = e[1], name = self:ItemName(e[1]) } end
  end
end

-------------------------------------------------------------------------------
--  Строка в подсказке предмета: сколько его нужно до следующего учителя.
-------------------------------------------------------------------------------
local function AddNeedLine(tooltip, id, ours)
  local a = ns:AllNeeds()[id]
  if not a then return end
  -- в окне EasyCraft «есть X из Y» уже написано в строке - там только «Где взять»
  for _, pr in ipairs(ours and {} or a.profs) do
    local have = a.have
    local col = have + (a.mail or 0) >= pr.need and "|cff33dd33" or "|cffff5555"
    local line = format(ns.T("%s: есть %s%d|r из %d до %d"), ns:N(ns.Profs[pr.key]), col, have, pr.need, pr.cap)
    if a.alts > 0 then line = line .. format(ns.T(", у альтов %d"), a.alts) end
    tooltip:AddLine("|cff33ff99Easy|rCraft: " .. line, 0.9, 0.9, 0.9)
  end
  -- где взять - одной строкой, только для того, чего не хватает
  local where = a.buy > 0 and ns:SourceLine(id)
  if where then tooltip:AddLine(ns.T("Где взять: ") .. where, 0.65, 0.65, 0.65, true) end
  tooltip:Show() -- подогнать размер под новые строки
end

-- Auction price of one item in the item tooltip, with coin icons. The price
-- comes from the addon's own pass over the auction house; an item that was
-- never seen there gets no line. A price older than a day says how old it is.
-- How many items are in the stack under the cursor: a bag or bank slot is
-- asked from the game, any other item button keeps its count on itself.
-- nil when the tooltip is not over a stack (a link in chat, a recipe row).
local function stackUnder(tooltip, id)
  local owner = tooltip.GetOwner and tooltip:GetOwner()
  if type(owner) ~= "table" then return nil end
  if owner.GetBagID and owner.GetID and C_Container and C_Container.GetContainerItemInfo then
    local ok, info = pcall(C_Container.GetContainerItemInfo, owner:GetBagID(), owner:GetID())
    if ok and type(info) == "table" and info.itemID == id then return tonumber(info.stackCount) end
  end
  return type(owner.count) == "number" and owner.count or nil
end

function ns:AddPriceLine(tooltip, id, count)
  if not (self.settings and self.settings.ahTip ~= false) then return false end
  local price, age = self:AuctionPrice(id)
  if not price then return false end
  local label = ns.T("На аукционе: ") .. (age and age > 0 and "|cff808080(" .. format(ns.T("%d дн."), age) .. ")|r" or "")
  local money = ns.W.Money(price)
  -- a stack: the price of the whole stack in brackets after the price of one
  count = count or stackUnder(tooltip, id)
  if count and count > 1 then money = money .. " |cffb0b0b0(\195\151" .. count .. ":|r " .. ns.W.Money(price * count) .. "|cffb0b0b0)|r" end
  tooltip:AddDoubleLine(label, money, 0.9, 0.9, 0.9, 1, 1, 1)
  tooltip:Show() -- fit the tooltip to the new line
  return true
end

-- «Где взять» коротко: у торговца, трава или жила и где их больше, с кого падает.
function ns:SourceLine(id)
  local src = self.MatSources and self.MatSources[id]
  if not src then return nil end
  if src.src == "vendor" then return ns.T("у торговцев (ремесленные товары, снабженцы)") end
  if src.text then return src.text end -- описание из маршрута точнее (слитки, быстрорепей)
  if src.nodes then
    local names, zones = {}, {}
    local own = self:ItemName(id)
    for i, nk in ipairs(src.nodes) do
      local n = self.Nodes[nk]
      -- трава зовётся так же, как предмет: её имя не повторяем, хватит зон
      if n and i <= 2 and ns:N(n) ~= own then tinsert(names, ns:N(n)) end
    end
    for _, a in ipairs(self:MaterialAreas(id, 2)) do tinsert(zones, self:ZoneName(a[1])) end
    if #names == 0 then return #zones > 0 and table.concat(zones, ", ") or nil end
    return table.concat(names, ", ") .. (#zones > 0 and (" - " .. table.concat(zones, ", ")) or "")
  end
  return src.text
end

-- Подсказка вызвана из окна EasyCraft: там «есть X из Y» уже написано в строке.
local function OwnedByUs(tooltip)
  local f = tooltip.GetOwner and tooltip:GetOwner()
  local main, mini = ns.UI and ns.UI.frame, ns.Tracker and ns.Tracker.f
  for _ = 1, 25 do
    if not f then return false end
    if f == main or f == mini then return true end
    f = f.GetParent and f:GetParent()
  end
  return false
end

function ns:HookItemTooltips()
  if self.tipHooked then return end
  self.tipHooked = true
  local function OnItem(tooltip, data)
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
    local id = data and data.id
    if not id and tooltip.GetItem then
      local _, link = tooltip:GetItem()
      id = link and tonumber(link:match("item:(%d+)"))
    end
    if type(id) ~= "number" then return end
    -- the two lines have their own settings: one can be off while the other is on
    if ns.settings and ns.settings.itemTips ~= false then AddNeedLine(tooltip, id, OwnedByUs(tooltip)) end
    ns:AddPriceLine(tooltip, id)
  end
  local safe = function(tooltip, data) pcall(OnItem, tooltip, data) end
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, safe)
  elseif GameTooltip and GameTooltip.HookScript then
    GameTooltip:HookScript("OnTooltipSetItem", safe)
    if ItemRefTooltip then ItemRefTooltip:HookScript("OnTooltipSetItem", safe) end
  end
end

-------------------------------------------------------------------------------
--  Жила или трава в мире: под её подсказкой одна строка - какого она цвета
--  для твоего навыка и сколько навыка до следующего цвета.
-------------------------------------------------------------------------------
local nodeByName
-- «чёрного» и «черного» - одно и то же: ё сводим к е
local function norm(s) return (ns.Lower(s):gsub("\209\145", "\208\181")) end
-- «Покрытая слизью медная жила» - та же медная жила
local OOZE = { "^покрыт[ао][яе] слизью ", "^ooze covered " }
local function NodeByName(name)
  if not nodeByName then
    nodeByName = {}
    for key, n in pairs(ns.Nodes) do
      for _, nm in ipairs({ n.ru or false, n.en or false }) do
        if nm then nodeByName[norm(nm)] = key end
      end
    end
  end
  local key = norm(name)
  for _, p in ipairs(OOZE) do key = key:gsub(p, "") end
  return nodeByName[key]
end

-- Пороги цветов сбора (как в классике): жёлтый +25, зелёный +50, серый +100.
local NEXT_COLOR = { orange = { "yellow", 25 }, yellow = { "green", 50 }, green = { "gray", 100 } }

function ns:NodeLine(name)
  if secret(name) or type(name) ~= "string" or name == "" then return nil end
  local key = NodeByName(name)
  local n = key and self.Nodes[key]
  if not n then return nil end
  local rank, _, has = self:GetSkill(n.prof)
  if not has then return nil end -- профессии нет: строка ни к чему
  local color = self:GatherColor(rank, n.req)
  -- «нужен навык» игра пишет на жиле сама - не повторяем
  if color == "red" then return nil end
  local head = "|cff33ff99Easy|rCraft: "
  if color == "gray" then
    return head .. ns.ColorRGBText("gray", ns.T("серый - навык не растёт"))
  end
  local nx = NEXT_COLOR[color]
  -- «зелёный · серый с навыка 101»
  return head .. self:Hex(color) .. (ns.ColorName[color] or "") .. "|r, "
    .. self:Hex(nx[1]) .. (ns.ColorName[nx[1]] or "") .. "|r" .. format(ns.T(" с навыка %d"), n.req + nx[2])
end

-- Minimap: the game lists the nodes under the cursor by name. Every ore or
-- herb gets the skill it needs in brackets, in the colour it has for the
-- player's skill (red: cannot gather yet; no such profession: plain grey).
-- A name that already has its brackets is not a node name any more, so a
-- text that went through here once comes back unchanged (nil).
function ns:MinimapNodeText(text)
  if secret(text) or type(text) ~= "string" or text == "" then return nil end
  local out, changed = {}, false
  for line in (text .. "\n"):gmatch("(.-)\n") do
    local plain = line:gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s+", ""):gsub("%s+$", "")
    local key = plain ~= "" and NodeByName(plain)
    local n = key and self.Nodes[key]
    if n and n.req then
      local rank, _, has = self:GetSkill(n.prof)
      local col = has and self:Hex(self:GatherColor(rank, n.req)) or "|cffb0b0b0"
      line = line .. " " .. col .. "(" .. n.req .. ")|r"
      changed = true
    end
    out[#out + 1] = line
  end
  return changed and table.concat(out, "\n") or nil
end

-- The minimap keeps one tooltip open and only swaps its text while the
-- cursor moves over the dots, so the text is checked on every frame the
-- tooltip is shown; a text seen already costs one comparison.
local function MinimapTip(tooltip)
  if not (ns.settings and ns.settings.itemTips ~= false) then return end
  if not (Minimap and tooltip.GetOwner and tooltip:GetOwner() == Minimap) then return end
  local fs = _G.GameTooltipTextLeft1
  local text = fs and fs:GetText()
  if not text or secret(text) or text == tooltip.ecMapText then return end
  local new = ns:MinimapNodeText(text)
  tooltip.ecMapText = new or text
  if new then
    fs:SetText(new)
    tooltip:Show() -- fit the tooltip to the longer lines
  end
end

function ns:HookNodeTooltips()
  if self.nodeTipHooked then return end
  self.nodeTipHooked = true
  local function Add(tooltip, data)
    if tooltip ~= GameTooltip or tooltip.godNode then return end
    if not (ns.settings and ns.settings.itemTips ~= false) then return end
    local name = type(data) == "table" and data.lines and data.lines[1] and data.lines[1].leftText
    if not name then
      local fs = _G.GameTooltipTextLeft1
      name = fs and fs:GetText()
    end
    local line = ns:NodeLine(name)
    if not line then return end
    tooltip.godNode = true
    tooltip:AddLine(line, 0.9, 0.9, 0.9)
    tooltip:Show()
  end
  local safe = function(tooltip, data) pcall(Add, tooltip, data) end
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType
    and Enum.TooltipDataType.Object then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Object, safe)
  end
  -- запасной путь: подсказка предмета в мире (её хозяин - мир, не окно)
  if GameTooltip and GameTooltip.HookScript then
    GameTooltip:HookScript("OnShow", function(tooltip)
      if UnitExists and UnitExists("mouseover") then return end
      local owner = tooltip.GetOwner and tooltip:GetOwner()
      if owner and owner ~= UIParent and owner ~= WorldFrame then return end
      if tooltip.GetItem and tooltip:GetItem() then return end
      safe(tooltip)
    end)
    GameTooltip:HookScript("OnTooltipCleared", function(tooltip) tooltip.godNode = nil end)
    GameTooltip:HookScript("OnHide", function(tooltip) tooltip.godNode = nil end)
    GameTooltip:HookScript("OnShow", function(tooltip) pcall(MinimapTip, tooltip) end)
    GameTooltip:HookScript("OnUpdate", function(tooltip) pcall(MinimapTip, tooltip) end)
  end
end

-------------------------------------------------------------------------------
--  Сверка маршрута с игрой: окно профессии показало настоящие цвета рецептов -
--  сравниваем их с данными маршрута. Расхождения хранятся в EasyCraftDB.routeCheck
--  (общие для персонажей) и видны в шаге и по команде /ec check.
-------------------------------------------------------------------------------
function ns:CheckRoute(key, colors, rank)
  local p = self.Profs[key]
  if not (p and colors and rank) then return end
  self.db.routeCheck = self.db.routeCheck or {}
  local rc = self.db.routeCheck[key] or {}
  self.db.routeCheck[key] = rc
  local api = C_TradeSkillUI
  for _, s in ipairs(p.steps) do
    if s.k == "craft" and s.spell then self:CheckReagents(s) end
    if s.k == "craft" and s.spell then
      local d = colors[s.spell]
      if d ~= nil then
        local real = COLOR_BY_D[d]
        local data = s.sk and self:RecipeColor(s, rank)
        if data and real and data ~= real then
          rc[s.spell] = { rank = rank, real = real, data = data, t = time() }
        else
          rc[s.spell] = nil
        end
      elseif api and api.GetRecipeInfo then
        -- рецепта нет среди выученных: есть ли он в игре вообще
        local ok, info = pcall(api.GetRecipeInfo, s.spell)
        if ok and info == nil then
          rc[s.spell] = { missing = true, rank = rank, t = time() }
        elseif rc[s.spell] and rc[s.spell].missing then
          rc[s.spell] = nil
        end
      end
    end
  end
  if not next(rc) then self.db.routeCheck[key] = nil end
end

-- Реагенты рецепта в игре другие, чем в маршруте: дальше считаем по игре
-- (шаг, покупки, мини-окно) и помним это между входами.
local function sameReagents(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  local m = {}
  for i = 1, #a - 1, 2 do m[a[i]] = (m[a[i]] or 0) + a[i + 1] end
  for i = 1, #b - 1, 2 do
    if m[b[i]] ~= b[i + 1] then return false end
    m[b[i]] = nil
  end
  return next(m) == nil
end

function ns:CheckReagents(s)
  local real = self:RecipeReagents(s.spell)
  if not real then return end
  self.db.realRC = self.db.realRC or {}
  local route = s.rcData or s.rc
  if route and not sameReagents(real, route) then
    s.rcData = route
    s.rc = real
    self.db.realRC[s.spell] = real
  elseif s.rcData then -- маршрут снова совпадает с игрой
    s.rc, s.rcData = s.rcData, nil
    self.db.realRC[s.spell] = nil
  end
end

-- При входе: реагенты, которые игра уже показала другими.
function ns:ApplyRealReagents()
  local fixed = self.db and self.db.realRC
  if not fixed then return end
  for _, p in pairs(self.Profs) do
    for _, s in ipairs(p.steps) do
      local real = s.spell and fixed[s.spell]
      if real and s.rc then
        if sameReagents(real, s.rc) then
          fixed[s.spell] = nil -- маршрут уже догнал игру
        else
          s.rcData = s.rcData or s.rc
          s.rc = real
        end
      end
    end
  end
end

-- Расхождение по шагу или nil.
function ns:StepCheck(key, s)
  local rc = s.spell and self.db.routeCheck and self.db.routeCheck[key]
  return rc and rc[s.spell]
end

function ns:PrintRouteCheck()
  local any = false
  for _, key in ipairs(self.ProfOrder) do
    local rc = self.db.routeCheck and self.db.routeCheck[key]
    if rc and next(rc) then
      any = true
      self:Print("|cffffd100" .. ns:N(self.Profs[key]) .. "|r")
      for i, s in ipairs(self.Profs[key].steps) do
        local c = s.spell and rc[s.spell]
        if c then
          local what = c.missing and ns.T("рецепта нет в игре")
            or format(ns.T("на навыке %d в игре %s, по маршруту %s"), c.rank, ns.ColorName[c.real] or c.real, ns.ColorName[c.data] or c.data)
          print(format("  %d. %s (%d) - %s", i, self:StepTitle(s), s.spell, what))
        end
      end
    end
  end
  -- реагенты, которые в игре другие (аддон уже считает по игре)
  local function list(rc)
    local parts = {}
    for i = 1, #rc - 1, 2 do tinsert(parts, rc[i + 1] .. " × " .. self:ItemName(rc[i])) end
    return table.concat(parts, ", ")
  end
  local header
  for _, key in ipairs(self.ProfOrder) do
    for i, s in ipairs(self.Profs[key].steps) do
      if s.rcData then
        any = true
        if not header then header = true; self:Print("|cffffd100" .. ns.T("Реагенты в игре другие (считаю по игре):") .. "|r") end
        print(format("  %s %d. %s - %s %s; %s %s", ns:N(self.Profs[key]), i, self:StepTitle(s),
          ns.T("по маршруту"), list(s.rcData), ns.T("в игре"), list(s.rc)))
      end
    end
  end
  if not any then self:Print(ns.T("расхождений маршрута с игрой нет (проверяется, когда открываешь окно профессии).")) end
end

-------------------------------------------------------------------------------
--  Окно учителя: звезда у рецептов, нужных маршруту, и у следующего ранга,
--  а в строке рецепта - «учи сейчас» или с какого навыка. В подсказке -
--  шаг маршрута. В строки игры добавляем только текстуру и надпись.
-------------------------------------------------------------------------------
local STAR = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"
local trainerHooked, trainerState = false, nil

local function SpellName(id)
  if C_Spell and C_Spell.GetSpellName then
    local ok, n = pcall(C_Spell.GetSpellName, id)
    if ok and n then return n end
  end
end

-- Профессия учителя: по тому, к какой профессии относятся его рецепты.
local function TrainerKey()
  for i = 1, (GetNumTrainerServices and GetNumTrainerServices() or 0) do
    for _, fn in ipairs({ GetTrainerServiceSkillLine or false, GetTrainerServiceSkillReq or false }) do
      if fn then
        local ok, name = pcall(fn, i)
        if ok and type(name) == "string" then
          local k = ns.NameToKey[name] or ns.NameToKey[ns.Lower(name)]
          if k then return k end
        end
      end
    end
  end
end

-- Что этот учитель значит для маршрута; считаем раз за визит.
local function TrainerState()
  if trainerState ~= nil then return trainerState or nil end
  trainerState = false
  if IsTradeskillTrainer and not IsTradeskillTrainer() then return nil end
  local key = TrainerKey()
  local keys = key and { key } or ns:LearnedList()
  local names = {}
  for _, k in ipairs(keys) do
    local p = ns.Profs[k]
    local rank, maxRank, has = ns:GetSkill(k)
    if p and has then
      local cur = ns:CurrentStep(k, rank, maxRank)
      for i, s in ipairs(p.steps) do
        if s.k == "craft" and s.spell and ns:StepState(k, i, rank, maxRank) ~= "done" then
          local e = { key = k, i = i, s = s, now = (i == cur), rank = rank }
          for _, n in ipairs({ SpellName(s.spell) or false, ns:StepName(s) or false }) do
            if n and not names[n] then names[n] = e end
          end
        end
      end
    end
  end
  local nr = key and ns:NextRank(key)
  if not next(names) and not nr then return nil end
  trainerState = { key = key, names = names, nextRank = nr }
  return trainerState
end

-- Нужна ли строка учителя маршруту: шаг маршрута или "rank".
local function Wanted(st, index)
  local ok, name, kind = pcall(GetTrainerServiceInfo, index)
  if not ok or not name or kind == "used" or kind == "header" then return nil end
  if GetTrainerServiceStepIndex then
    local ok2, si = pcall(GetTrainerServiceStepIndex)
    if ok2 and si == index then return st.nextRank and "rank" or nil end
  end
  return st.names[name]
end

-- Надпись только у того, что можно выучить сейчас: у остального игра
-- сама пишет «Требуется ...», а звезда (бледная) говорит, что пригодится.
local function MarkText(index)
  local _, kind = GetTrainerServiceInfo(index)
  if kind == "available" then return ns.T("Нужен для прокачки"), true end
end

local function ApplyMark(button, on, text, ready)
  if not on then
    if button.godStar then button.godStar:Hide(); button.godText:Hide() end
    return
  end
  if not button.godStar then
    local star = button:CreateTexture(nil, "OVERLAY", nil, 7)
    star:SetTexture(STAR)
    star:SetSize(14, 14)
    star:SetPoint("TOPLEFT", button.icon or button, "TOPLEFT", -4, 4)
    button.godStar = star
    local fs = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetJustifyH("LEFT")
    if button.subText then fs:SetPoint("LEFT", button.subText, "LEFT", 0, 0)
    else fs:SetPoint("BOTTOMRIGHT", -10, 8) end
    button.godText = fs
  end
  button.godStar:SetAlpha(ready and 1 or 0.5)
  button.godStar:Show()
  local fs = button.godText
  fs:SetText(text or "")
  if ready then fs:SetTextColor(0.25, 1, 0.25) else fs:SetTextColor(0.62, 0.62, 0.62) end
  -- надпись - на месте строки игры и только если та пуста (иначе там
  -- «Требуется ...», и хватает одной звезды)
  local gameText = button.subText and button.subText.GetText and button.subText:GetText()
  fs:SetShown(text ~= nil and (gameText == nil or gameText == ""))
end

local function MarkButton(button, elementData)
  local data = type(elementData) == "table" and (elementData.data or elementData) or nil
  local index = data and data.skillIndex
  local st = index and ns.settings and ns.settings.trainerStars ~= false and TrainerState()
  local w = st and Wanted(st, index)
  if not w then return ApplyMark(button, false) end
  ApplyMark(button, true, MarkText(index))
end

local function RefreshTrainer()
  local f = ClassTrainerFrame
  if not (trainerHooked and f and f:IsShown()) then return end
  if f.ScrollBox and f.ScrollBox.ForEachFrame then
    f.ScrollBox:ForEachFrame(function(b) ns:Safe(MarkButton, b, b.GetElementData and b:GetElementData()) end)
  end
  local rb = f.skillStepButton
  if rb and rb:IsShown() then ns:Safe(MarkButton, rb, { skillIndex = rb:GetID() }) end
end

-- Под подсказкой рецепта у учителя: какой шаг маршрута его использует.
local function TrainerTip(tip, index)
  if ns.settings and ns.settings.trainerStars == false then return end
  local st = type(index) == "number" and TrainerState()
  local w = st and Wanted(st, index)
  if not w then return end
  tip:AddLine(" ")
  if w == "rank" then
    tip:AddLine("|cff33ff99Easy|rCraft: " .. format(ns.T("следующий ранг: предел навыка станет %d"), st.nextRank.max), 1, 0.82, 0)
  else
    local s = w.s
    if w.now then
      tip:AddLine("|cff33ff99Easy|rCraft: " .. ns.T("это твой шаг сейчас"), 0.25, 1, 0.25)
      local left = ns:RemainingCrafts(s, w.rank)
      if left > 0 then tip:AddLine(format(ns.T("Сделать ещё ~%d шт., до навыка %d"), left, s.t), 1, 1, 1) end
    else
      tip:AddLine("|cff33ff99Easy|rCraft: " .. format(ns.T("понадобится на навыке %d-%d"), s.f, s.t), 1, 0.82, 0)
    end
    local colors = ns:RecipeColorText(s)
    if colors then tip:AddLine(colors, 1, 1, 1, true) end
  end
  tip:Show()
end

local function HookTrainer()
  if trainerHooked or not ClassTrainerFrame_InitServiceButton then return end
  trainerHooked = true
  hooksecurefunc("ClassTrainerFrame_InitServiceButton", function(b, d) ns:Safe(MarkButton, b, d) end)
  if GameTooltip.SetTrainerService then
    hooksecurefunc(GameTooltip, "SetTrainerService", function(tip, i) ns:Safe(TrainerTip, tip, i) end)
  end
end

local trainerEv = CreateFrame("Frame")
for _, e in ipairs({ "ADDON_LOADED", "TRAINER_SHOW", "TRAINER_UPDATE", "TRAINER_CLOSED", "SKILL_LINES_CHANGED" }) do
  pcall(trainerEv.RegisterEvent, trainerEv, e)
end
trainerEv:SetScript("OnEvent", function(_, event, name)
  if event == "ADDON_LOADED" then
    if name == "Blizzard_TrainerUI" then ns:Safe(HookTrainer) end
    return
  end
  if event == "TRAINER_CLOSED" then trainerState = nil return end
  trainerState = nil
  ns:Safe(HookTrainer)
  ns:Safe(RefreshTrainer)
  -- список у учителя иногда заполняется чуть позже - пометим ещё раз
  if event == "TRAINER_SHOW" then
    C_Timer.After(0.5, function() trainerState = nil; ns:Safe(RefreshTrainer) end)
  end
end)
