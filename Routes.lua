local _, TJ = ...

-------------------------------------------------------------------------------
--  Режимы маршрута. Игрок выбирает сам:
--    guide    - обычный: маршрут, записанный в данных (как раньше);
--    cheap    - дешевле: на каждом пункте навыка рецепт с наименьшей ожидаемой
--               ценой пункта (цена создания / шанс прокачки);
--    fast     - быстрее: рецепт с наибольшим шансом, меньше всего созданий;
--    balanced - сбалансировано: цена пункта, но редкая прокачка штрафуется.
--  Рецепты берутся из самого маршрута: у каждого есть пороги цвета
--  sk = { с какого навыка, жёлтый, зелёный, серый }. Шанс прокачки:
--  до жёлтого 100%, дальше (серый - навык) / (серый - жёлтый).
--  Целесообразность: рецепт, который надо покупать или искать (src="recipe"),
--  считается дороже, пока персонаж его не выучил.
--  Без цен режимы «дешевле» и «сбалансировано» посчитать нельзя - тогда
--  остаётся обычный маршрут.
-------------------------------------------------------------------------------
local ceil, huge = math.ceil, math.huge

TJ.ROUTE_MODES = { "guide", "cheap", "fast", "balanced" }
TJ.ROUTE_MODE_NAME = { guide = "Обычный", cheap = "Дешевле", fast = "Быстрее", balanced = "Сбалансировано" }
TJ.ROUTE_MODE_TIP = {
  guide = "Проверенный маршрут из гайда.",
  cheap = "Меньше золота: дольше держимся за дешёвый рецепт, даже когда он желтеет.",
  fast = "Меньше созданий: всегда рецепт, который даёт навык почти наверняка.",
  balanced = "Середина: дешёвые рецепты, но без долгого битья по зелёным.",
}

local MIN_CHANCE = { cheap = 0.25, fast = 0.5, balanced = 0.4 }
local KEEP = 1.05 -- текущий рецепт не меняем, пока новый не лучше на 5%

function TJ:RouteMode()
  local m = self.settings and self.settings.routeMode
  return self.ROUTE_MODE_NAME[m] and m or "guide"
end

local function baseSteps(p) return p.baseSteps or p.steps end

-- У профессии есть из чего выбирать (ремесло с порогами цветов).
function TJ:HasRouteModes(key)
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

-- Маршрут для режима или nil (считать не из чего - остаётся обычный).
local function compute(self, key, mode)
  local p = self.Profs[key]
  local base = baseSteps(p)
  local pool, seen = {}, {}
  local first, last = huge, 0
  local caps = {} -- навык, на котором нужен новый ранг: шаг там обрывается
  for _, s in ipairs(base) do
    if s.k == "craft" and s.f and s.t then
      if s.f < first then first = s.f end
      if s.t > last then last = s.t end
      local sk = s.sk
      local id = recipeKey(s)
      if sk and s.rc and id and not seen[id] and sk[2] and sk[4] then
        seen[id] = true
        pool[#pool + 1] = { s = s, learn = sk[1] or 0, yellow = sk[2], grey = sk[4] }
      end
    elseif s.at then
      caps[s.at] = true
    end
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
  if mode ~= "fast" and priced < #pool / 2 then return nil end

  local function score(c, skill)
    local ch = chance(c, skill)
    if ch < MIN_CHANCE[mode] then return nil end
    local cost = c.cost or 1e9
    if mode == "fast" then return (1 / ch) * c.feas + cost * 1e-12 end
    if mode == "cheap" then return cost / ch * c.feas end
    return cost / (ch * ch) * c.feas
  end

  -- шаг обычного маршрута на этом навыке: запасной вариант, если по порогам
  -- ничего не подходит
  local function fallback(skill)
    for _, s in ipairs(base) do
      if s.k == "craft" and s.f and s.t and skill >= s.f and skill < s.t then
        local sk = s.sk
        return { s = s, learn = 0, yellow = sk and sk[2] or s.t, grey = sk and sk[4] or (s.t + 1), plain = true }
      end
    end
  end

  local runs, cur = {}, nil
  for skill = first, last - 1 do
    local best, bestScore
    for _, c in ipairs(pool) do
      if skill >= c.learn then
        local sc = score(c, skill)
        if sc and (not bestScore or sc < bestScore) then best, bestScore = c, sc end
      end
    end
    if cur and cur.c ~= best and not cur.c.plain and not caps[skill] then
      local mine = score(cur.c, skill)
      if mine and bestScore and mine <= bestScore * KEEP then best = cur.c end
    end
    if not best then best = fallback(skill) end
    if not best then return nil end
    local same = cur and (cur.c == best or (best.plain and cur.c.plain and cur.c.s == best.s))
    if not same or caps[skill] then
      cur = { c = best, f = skill, t = skill, crafts = 0 }
      runs[#runs + 1] = cur
    end
    local ch = chance(best, skill)
    if ch <= 0 then ch = 1 end
    cur.crafts = cur.crafts + 1 / ch
    cur.t = skill + 1
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
    local src = r.c.s
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
    out[#out + 1] = step
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
function TJ:ApplyRoutes()
  local mode = self:RouteMode()
  local changed = false
  self.char.routeSig = self.char.routeSig or {}
  for key, p in pairs(self.Profs) do
    if type(p) == "table" and p.steps then
      p.baseSteps = p.baseSteps or p.steps
      local steps
      if mode ~= "guide" and self:HasRouteModes(key) then
        local ok, res = pcall(compute, self, key, mode)
        if ok and type(res) == "table" and #res > 0 then steps = res end
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

function TJ:SetRouteMode(mode)
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
    if not (TJ.db and TJ.char) then return end
    local ok, changed = pcall(TJ.ApplyRoutes, TJ)
    if ok and changed then TJ:RefreshAll() end
  end
  if C_Timer and C_Timer.After then C_Timer.After(4, run) else run() end
end)
