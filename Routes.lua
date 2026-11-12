local _, ns = ...

-------------------------------------------------------------------------------
--  Режимы маршрута. Игрок выбирает сам:
--    guide    - обычный: маршрут, записанный в данных (как раньше);
--    cheap    - дешевле: на каждом пункте навыка рецепт с наименьшей ожидаемой
--               ценой пункта (цена создания / шанс прокачки);
--    fast     - быстрее: рецепт с наибольшим шансом, меньше всего созданий;
--  Рецепты берутся из самого маршрута: у каждого есть пороги цвета
--  sk = { с какого навыка, жёлтый, зелёный, серый }. Шанс прокачки:
--  до жёлтого 100%, дальше (серый - навык) / (серый - жёлтый).
--  Целесообразность: рецепт, который надо покупать или искать (src="recipe"),
--  считается дороже, пока персонаж его не выучил.
--  Без цен режим «дешевле» посчитать нельзя - тогда
--  остаётся обычный маршрут.
-------------------------------------------------------------------------------
local ceil, huge = math.ceil, math.huge

ns.ROUTE_MODES = { "guide", "cheap", "fast" }
ns.ROUTE_MODE_NAME = { guide = "Обычный", cheap = "Дешевле", fast = "Быстрее" }
ns.ROUTE_MODE_TIP = {
  guide = "Проверенный маршрут из гайда.",
  cheap = "Меньше золота: дольше держимся за дешёвый рецепт, даже когда он желтеет.",
  fast = "Меньше созданий: всегда рецепт, который даёт навык почти наверняка.",
}

-- A green recipe is never part of a route, in any mode: skill comes from it
-- too rarely. Where the stored route has nothing else, the step stays and is
-- marked (step.green) - the window then says so instead of offering to craft.
local KEEP = 1.05 -- текущий рецепт не меняем, пока новый не лучше на 5%

function ns:RouteMode()
  local m = self.settings and self.settings.routeMode
  return self.ROUTE_MODE_NAME[m] and m or "guide"
end

local function baseSteps(p) return p.baseSteps or p.steps end

-- У профессии есть из чего выбирать (ремесло с порогами цветов).
function ns:HasRouteModes(key)
  local p = self.Profs[key]
  if not p or not p.steps then return false end
  local n = 0
  for _, s in ipairs(baseSteps(p)) do
    if s.k == "craft" and s.sk and s.rc then n = n + 1 end
  end
  return n >= 2
end

local function recipeKey(s) return s.spell or s.id or s.en end

local function chance(c, skill)
  if skill < c.yellow then return 1 end
  if skill >= c.grey then return 0 end
  local span = c.grey - c.yellow
  if span <= 0 then return 0 end
  return (c.grey - skill) / span
end

-- Recipes outside the stored routes for the stretches where every recipe of
-- the route is green. Trainer recipes only: nothing to hunt for. They are
-- used only where the route itself has nothing that is not green.
-- Ids and reagents: the WoW Forever database on Wowhead. Colour thresholds:
-- the WoW Forever profession tables on timesaver.gg (see THIRD-PARTY.md).
local EXTRA = {
  cooking = {
    { k = "craft", en = "Goblin Deviled Clams", spell = 6500, id = 5527, rc = { 5504, 1, 2692, 1 }, src = "trainer",
      sk = { 125, 165, 185, 205 } },
  },
  engineering = {
    { k = "craft", en = "Iron Grenade", spell = 3962, id = 4390, rc = { 3575, 1, 4377, 1, 4306, 1 }, src = "trainer",
      sk = { 175, 175, 195, 215 } },
    { k = "craft", en = "Mithril Gyro-Shot", spell = 12621, id = 10513, rc = { 3860, 2, 10505, 2 }, src = "trainer",
      sk = { 245, 245, 265, 285 } },
  },
}
-- Маршрут для режима или nil (считать не из чего - остаётся обычный).
local function compute(self, key, mode)
  local p = self.Profs[key]
  local base = baseSteps(p)
  local pool, seen, byKey = {}, {}, {}
  -- разовые шаги (жезл, философский камень: одно создание на один пункт)
  -- остаются на своём месте и в выбор не идут
  local pinAt = {}
  local first, last = huge, 0
  local caps = {} -- навык, на котором нужен новый ранг: шаг там обрывается
  for _, s in ipairs(base) do
    if s.k == "craft" and s.f and s.t then
      if s.f < first then first = s.f end
      if s.t > last then last = s.t end
      local sk = s.sk
      local id = recipeKey(s)
      if s.n == 1 and s.t - s.f == 1 then
        pinAt[s.f] = s
        if id then seen[id] = true end
      elseif sk and s.rc and id and not seen[id] and sk[2] and sk[4] then
        seen[id] = true
        pool[#pool + 1] = { s = s, learn = sk[1] or 0, yellow = sk[2], green = sk[3], grey = sk[4] }
        byKey[id] = pool[#pool]
      end
    elseif s.at then
      caps[s.at] = true
    end
  end
  for _, s in ipairs(EXTRA[key] or {}) do
    local id = recipeKey(s)
    if not seen[id] then
      seen[id] = true
      pool[#pool + 1] = { s = s, learn = s.sk[1], yellow = s.sk[2], green = s.sk[3], grey = s.sk[4], extra = true }
    end
  end
  -- выученные рецепты не из маршрута: пороги - по своим наблюдениям цветов
  if self.SeenCandidates then
    for _, c in ipairs(self:SeenCandidates(key, seen)) do pool[#pool + 1] = c end
  end
  if #pool < 2 or last <= first then return nil end

  local book = self.char and self.char.book and self.char.book[key]
  local priced = 0
  for _, c in ipairs(pool) do
    c.cost = self:RecipeCost(c.s.rc)
    if c.cost then priced = priced + 1 end
    -- рецепт надо купить или найти, а персонаж его ещё не знает
    local hard = c.s.src == "recipe" and not (book and c.s.spell and book[c.s.spell])
    c.feas = hard and (mode == "fast" and 1.15 or 1.4) or 1
  end
  if mode == "cheap" and priced < #pool / 2 then return nil end

  local function greenAt(c) return c.green or (c.yellow + c.grey) / 2 end
  local function score(c, skill)
    if skill >= greenAt(c) then return nil end
    local ch = chance(c, skill)
    local cost = c.cost or 1e9
    if mode == "fast" then return (1 / ch) * c.feas + cost * 1e-12 end
    return cost / ch * c.feas
  end
  -- шаг обычного маршрута на этом навыке: запасной вариант, если по порогам
  -- ничего не подходит
  local function fallback(skill)
    for _, s in ipairs(base) do
      if s.k == "craft" and s.f and s.t and skill >= s.f and skill < s.t then
        local sk = s.sk
        return { s = s, learn = 0, yellow = sk and sk[2] or s.t, green = sk and sk[3] or (s.t + 1), grey = sk and sk[4] or (s.t + 1), plain = true }
      end
    end
  end

  local runs, cur = {}, nil
  for skill = first, last - 1 do
    local best, bestScore
    if pinAt[skill] then
      runs[#runs + 1] = { fixed = pinAt[skill], f = skill, t = skill + 1 }
      cur = nil
    else
      -- the stored route: its own recipe for this skill, while it is not green
      local own
      if mode == "guide" then
        local b = fallback(skill)
        local c = b and byKey[recipeKey(b.s)]
        if c and skill < greenAt(c) then own = c elseif b and not c then own = b end
      end
      if own then
        best = own
      else
        -- the route's own recipes first; the extra ones only if none of them fits
        for pass = 1, 2 do
          for _, c in ipairs(pool) do
            if skill >= c.learn and (pass == 2) == (c.extra == true) then
              local sc = score(c, skill)
              if sc and (not bestScore or sc < bestScore) then best, bestScore = c, sc end
            end
          end
          if best then break end
        end
      end
      if cur and cur.c ~= best and not cur.c.plain and not caps[skill] then
        local mine = score(cur.c, skill)
        if mine and bestScore and mine <= bestScore * KEEP then best = cur.c end
      end
      if not best then best = fallback(skill) end
      if not best then return nil end
      local same = cur and (cur.c == best or (best.plain and cur.c.plain and cur.c.s == best.s))
      -- the green part of a stored step is a run of its own, so that it can be marked
      if same and best.plain and skill == best.green then same = false end
      -- the stored route is not cut where a new rank is needed: it never was
      if not same or (caps[skill] and mode ~= "guide") then
        cur = { c = best, f = skill, t = skill, crafts = 0 }
        runs[#runs + 1] = cur
      end
      local ch = chance(best, skill)
      if ch <= 0 then ch = 1 end
      cur.crafts = cur.crafts + 1 / ch
      cur.t = skill + 1
    end
  end

  -- шаги не-ремёсла (учитель, книга, задание) встают туда же по навыку, где
  -- стояли: перед первым шагом, который начинается не раньше
  local others = {}
  for i, s in ipairs(base) do
    if s.k ~= "craft" then
      local pos = 301
      for j = i + 1, #base do
        if base[j].k == "craft" and base[j].f then pos = base[j].f break end
      end
      others[#others + 1] = { s = s, pos = pos }
    end
  end

  local out, oi = {}, 1
  for _, r in ipairs(runs) do
    while others[oi] and others[oi].pos <= r.f do
      out[#out + 1] = others[oi].s
      oi = oi + 1
    end
    if r.fixed then
      out[#out + 1] = r.fixed
    else
      local src = r.c.s
      -- the stored route untouched where nothing changed: its own numbers stay
      local green = r.c.plain and src.sk and r.f >= greenAt(r.c)
      if mode == "guide" and src.f == r.f and src.t == r.t and not green then
        out[#out + 1] = src
      else
        local step = {}
        for k, v in pairs(src) do step[k] = v end
        local n = ceil(r.crafts - 1e-6)
        if n < 1 then n = 1 end
        step.f, step.t, step.n = r.f, r.t, n
        if src.rc then
          local m = {}
          for i = 1, #src.rc - 1, 2 do
            m[i] = src.rc[i]
            m[i + 1] = (src.rc[i + 1] or 1) * n
          end
          step.m = m
        end
        step.gen = mode
        -- nothing in the route replaces it here: the green part of the stored step
        -- a green step is not crafted, so nothing is counted or bought for it
        if green then step.green, step.n, step.m = true, nil, nil end
        out[#out + 1] = step
      end
    end
  end
  while others[oi] do
    out[#out + 1] = others[oi].s
    oi = oi + 1
  end
  return out
end

local function signature(steps)
  local t = {}
  for i, s in ipairs(steps) do
    t[i] = tostring(s.k) .. ":" .. tostring(recipeKey(s) or s.at or "") .. ":" .. tostring(s.f or "") .. "-" .. tostring(s.t or "")
  end
  return table.concat(t, "|")
end

-- Пересчитать маршруты под выбранный режим. Возвращает, изменилось ли что-то.
function ns:ApplyRoutes()
  local mode = self:RouteMode()
  local changed = false
  self.char.routeSig = self.char.routeSig or {}
  for key, p in pairs(self.Profs) do
    if type(p) == "table" and p.steps then
      p.baseSteps = p.baseSteps or p.steps
      local steps
      if self:HasRouteModes(key) then
        local ok, res = pcall(compute, self, key, mode)
        if ok and type(res) == "table" and #res > 0 then steps = res end
        -- the mode cannot be built (no prices yet): still the stored route without green recipes
        if not steps and mode ~= "guide" then
          ok, res = pcall(compute, self, key, "guide")
          if ok and type(res) == "table" and #res > 0 then steps, mode = res, "guide" end
        end
      end
      p.routeMode = steps and mode or "guide"
      steps = steps or p.baseSteps
      local sig = signature(steps)
      local old = self.char.routeSig[key]
      if old ~= sig then
        -- шаги сдвинулись: ручные отметки «сделано» относились к старым номерам
        if old and self.char.manual then self.char.manual[key] = nil end
        self.char.routeSig[key] = sig
        changed = true
      end
      p.steps = steps
      p._order, p._pos = nil, nil -- порядок показа считался по старым шагам
    end
  end
  if changed and self.UI and self.UI.focus then
    for k in pairs(self.UI.focus) do self.UI.focus[k] = "cur" end
  end
  return changed
end

function ns:SetRouteMode(mode)
  if not self.ROUTE_MODE_NAME[mode] then return end
  self.settings.routeMode = mode
  self:ApplyRoutes()
  self:RefreshAll()
end

-- При входе: цены из прошлых заходов уже загружены.
local ev = CreateFrame("Frame")
pcall(ev.RegisterEvent, ev, "PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function()
  local function run()
    if not (ns.db and ns.char) then return end
    local ok, changed = pcall(ns.ApplyRoutes, ns)
    if ok and changed then ns:RefreshAll() end
  end
  C_Timer.After(4, run)
end)
