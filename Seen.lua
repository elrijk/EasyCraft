local _, TJ = ...

-------------------------------------------------------------------------------
--  Свои наблюдения цветов рецептов. Каждый раз, когда открыто окно профессии,
--  EasyCraft запоминает, какого цвета был каждый выученный рецепт на нынешнем
--  навыке. Из наблюдений получаются пороги: с какого навыка рецепт желтеет,
--  зеленеет и сереет - их игра не сообщает.
--  EasyCraftDB.seen[профессия][рецепт] = { o = наибольший навык, где был
--  оранжевым, y1/y2 = наименьший и наибольший жёлтый, g1/g2 = зелёный,
--  x = наименьший серый }. Общие на учётную запись: альты дополняют друг друга.
--  Режимы маршрута (Routes.lua) берут такие рецепты в выбор, а код из
--  /ec colors можно отправить автору - пороги попадут в данные для всех.
-------------------------------------------------------------------------------
local min, max = math.min, math.max
local HEADER = "EasyCraft:sk:1"

local function seenOf(self, key, make)
  local db = self.db
  if not db then return nil end
  if not db.seen then
    if not make then return nil end
    db.seen = {}
  end
  if not db.seen[key] and make then db.seen[key] = {} end
  return db.seen[key]
end

-- colors: рецепт -> 0 оранжевый, 1 жёлтый, 2 зелёный, 3 серый; rank - навык.
function TJ:NoteColors(key, colors, rank)
  if type(colors) ~= "table" or type(rank) ~= "number" or rank <= 0 then return end
  local t = seenOf(self, key, true)
  if not t then return end
  for id, d in pairs(colors) do
    local r = t[id]
    if not r then r = {} t[id] = r end
    if d == 0 then r.o = max(r.o or rank, rank)
    elseif d == 1 then r.y1 = min(r.y1 or rank, rank) r.y2 = max(r.y2 or rank, rank)
    elseif d == 2 then r.g1 = min(r.g1 or rank, rank) r.g2 = max(r.g2 or rank, rank)
    elseif d == 3 then r.x = min(r.x or rank, rank) end
  end
end

-- Пороги по наблюдениям: с какого навыка видели, жёлтый, зелёный, серый -
-- или nil, если наблюдений мало. Оценка осторожная: считаем, что рецепт
-- желтеет и сереет раньше, а не позже - цена пути выйдет чуть выше, не ниже.
function TJ:SeenThresholds(r)
  if type(r) ~= "table" then return nil end
  local yellow = (r.o and r.o + 1) or r.y1
  if not yellow then return nil end
  local green = (r.y2 and r.y2 + 1) or r.g1
  local grey
  if r.g2 then grey = r.g2 + 1
  elseif green and green > yellow then grey = 2 * green - yellow -- отрезки жёлтого и зелёного равны
  elseif r.x and r.x > yellow then grey = r.x end
  if r.x and grey and r.x < grey then grey = r.x end
  if not grey or grey <= yellow then return nil end
  local first = min(r.o or 999, r.y1 or 999, r.g1 or 999, r.x or 999)
  return first, yellow, green or yellow, grey
end

-- Выученные рецепты с порогами по наблюдениям - кандидаты для режимов
-- маршрута. skip[рецепт] - уже есть в маршруте.
function TJ:SeenCandidates(key, skip)
  local out = {}
  local t = seenOf(self, key)
  local book = self.char and self.char.book and self.char.book[key]
  if not (t and book) then return out end
  for id, b in pairs(book) do
    if not (skip and skip[id]) and type(b) == "table" and b.rc and #b.rc >= 2 and b.out then
      local first, yellow, green, grey = self:SeenThresholds(t[id])
      if first then
        out[#out + 1] = { learn = first, yellow = yellow, grey = grey,
          s = { k = "craft", spell = id, id = b.out, en = b.n, ru = b.n, rc = b.rc, src = "seen",
            sk = { first, yellow, green, grey } } }
      end
    end
  end
  return out
end

-- Код наблюдений для автора: «профессия;рецепт;o;y1;y2;g1;g2;x;выход;реагенты».
function TJ:ColorsReport()
  local parts, n = { HEADER }, 0
  local db = self.db
  for key, t in pairs(db and db.seen or {}) do
    local book = self.char and self.char.book and self.char.book[key]
    local ids = {}
    for id in pairs(t) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
      local r, b = t[id], book and book[id]
      local rc = b and b.rc and table.concat(b.rc, ",") or ""
      parts[#parts + 1] = table.concat({ key, id, r.o or "", r.y1 or "", r.y2 or "", r.g1 or "", r.g2 or "", r.x or "",
        b and b.out or "", rc }, ";")
      n = n + 1
    end
  end
  return table.concat(parts, "|"), n
end

function TJ:ShareColors()
  local code, n = self:ColorsReport()
  if n == 0 then
    self:Print(TJ.T("наблюдений пока нет: открой окно профессии."))
    return
  end
  if StaticPopupDialogs and StaticPopupDialogs.EASYCRAFT_SHARE then
    StaticPopup_Show("EASYCRAFT_SHARE", format(TJ.T("Цвета рецептов (%d). Скопируй код (Ctrl+C) и отправь автору аддона:"), n)
      .. "\ngithub.com/elrijk/EasyCraft/issues", nil, code)
  end
end
