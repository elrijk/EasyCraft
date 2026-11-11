local _, ns = ...

-------------------------------------------------------------------------------
--  Полная база рецептов профессии. Игра сама отдаёт все рецепты открытой
--  профессии - и выученные, и нет - с реагентами, результатом и строкой
--  «где взять». EasyCraft читает их при открытии окна профессии и хранит в
--  EasyCraftDB.recipes[профессия][рецепт] = { n = название, i = значок,
--  out = предмет, q = сколько, rc = реагенты, src = где взять }.
--  База общая на учётную запись. Невыученные рецепты попадают в книгу
--  рецептов (раздел «Ещё не выучены») с ценой, выгодой и источником.
--  ns.RecipeBase (Data\Recipes.lua, если есть) - та же база, собранная
--  заранее: с ней список полон и до первого открытия окна.
-------------------------------------------------------------------------------
local TS = C_TradeSkillUI
local PER_TICK = 20 -- рецептов за один шаг чтения: чтобы игра не подвисала

local function baseOf(self, key, make)
  local db = self.db
  if not db then return nil end
  db.recipes = db.recipes or {}
  if not db.recipes[key] and make then db.recipes[key] = {} end
  return db.recipes[key]
end

local function sourceText(id)
  if not TS.GetRecipeSourceText then return nil end
  local ok, s = pcall(TS.GetRecipeSourceText, id)
  if not ok or type(s) ~= "string" or s == "" then return nil end
  -- без цветов и переносов: в одну строку
  s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|n", ", "):gsub("%s*\n%s*", ", ")
  if #s > 240 then s = s:sub(1, 240) end
  return s
end

local function readOne(id)
  local ok, sch = pcall(TS.GetRecipeSchematic, id, false)
  if not ok or type(sch) ~= "table" then return nil end
  local out = type(sch.outputItemID) == "number" and sch.outputItemID > 0 and sch.outputItemID or nil
  return out, math.max(1, tonumber(sch.quantityMin) or 1)
end

local job -- { key, ids, i }
local function step()
  local j = job
  if not j then return end
  local t = baseOf(ns, j.key, true)
  local n = 0
  while j.i <= #j.ids and n < PER_TICK do
    local id = j.ids[j.i]
    j.i = j.i + 1
    local r = TS.GetRecipeInfo(id)
    if r and r.name and r.type ~= "header" and r.type ~= "subheader" then
      local e = t[id] or {}
      t[id] = e
      e.n, e.i = r.name, r.icon
      if not e.rc then
        e.rc = ns:ReadRecipeReagents(id)
        e.out, e.q = readOne(id)
        n = n + 1
      end
      if not e.src and r.learned == false then e.src = sourceText(id) end
    end
  end
  if j.i > #j.ids then
    job = nil
    ns:RefreshAll()
  else
    C_Timer.After(0.05, step)
  end
end

-- Прочитать все рецепты открытой профессии (вызывает Tracking.lua).
function ns:ScanAllRecipes(key)
  if not (TS and TS.GetAllRecipeIDs and TS.GetRecipeInfo and TS.GetRecipeSchematic) then return end
  if job and job.key == key then return end
  local ok, ids = pcall(TS.GetAllRecipeIDs)
  if not ok or type(ids) ~= "table" or #ids == 0 then return end
  job = { key = key, ids = ids, i = 1 }
  step()
end

-- Сколько рецептов профессии в базе.
function ns:RecipeBaseCount(key)
  local n = 0
  for _ in pairs(baseOf(self, key) or {}) do n = n + 1 end
  for id in pairs(self.RecipeBase and self.RecipeBase[key] or {}) do
    if not (self.db.recipes and self.db.recipes[key] and self.db.recipes[key][id]) then n = n + 1 end
  end
  return n
end

-- Книга рецептов: к невыученным добавляются все рецепты из базы.
local bookList = ns.BookList
function ns:BookList(key)
  local known, unknown, scanned = bookList(self, key)
  local have = {}
  for _, e in ipairs(known) do if e.spell then have[e.spell] = true end end
  for _, e in ipairs(unknown) do if e.spell then have[e.spell] = true end end
  local added = false
  local function add(id, r)
    if have[id] or type(r) ~= "table" then return end
    have[id] = true
    added = true
    unknown[#unknown + 1] = self:PriceEntry({ key = key, spell = id, name = r.n or self:SpellName(id), icon = r.i,
      out = r.out, q = r.q or 1, rc = r.rc, known = false, src = r.src })
  end
  for id, r in pairs(baseOf(self, key) or {}) do add(id, r) end
  for id, r in pairs(self.RecipeBase and self.RecipeBase[key] or {}) do add(id, r) end
  if added and self.ByProfit then table.sort(unknown, self.ByProfit) end
  return known, unknown, scanned
end
