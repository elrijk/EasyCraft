-------------------------------------------------------------------------------
--  EasyCraft: перевод текстов в данных (заметки маршрутов, описания лагеря,
--  где брать материалы). Загружается после файлов Data, до кода аддона.
--  Поля ru и en не трогаем: по ним аддон узнаёт профессии и зоны клиента.
-------------------------------------------------------------------------------
local ADDON, ns = ...

local KEEP = { ru = true, en = true }

local function Walk(t, depth)
  if depth > 12 then return end
  for k, v in pairs(t) do
    if type(v) == "table" then
      Walk(v, depth + 1)
    elseif type(v) == "string" and not KEEP[k] and v:find("[\208\209]") then
      t[k] = ns.T(v) -- английский или перевод с него
    end
  end
end

-- Один раз, когда язык уже известен (ns:SetLang на ADDON_LOADED).
function ns:ApplyLocaleData()
  if self.localeDataDone then return end
  self.localeDataDone = true
  for _, name in ipairs({ "Profs", "MatSources", "Nodes" }) do
    if type(ns[name]) == "table" then Walk(ns[name], 0) end
  end
end
