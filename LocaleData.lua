-------------------------------------------------------------------------------
--  EasyCraft: перевод текстов в данных (заметки маршрутов, описания лагеря,
--  где брать материалы). Загружается после файлов Data, до кода аддона.
--  Поля ru и en не трогаем: по ним аддон узнаёт профессии и зоны клиента.
-------------------------------------------------------------------------------
local ADDON, TJ = ...

local KEEP = { ru = true, en = true }

local function Walk(t, depth)
  if depth > 12 then return end
  for k, v in pairs(t) do
    if type(v) == "table" then
      Walk(v, depth + 1)
    elseif type(v) == "string" and not KEEP[k] and v:find("[\208\209]") then
      t[k] = TJ.T(v) -- английский или перевод с него
    end
  end
end

-- Один раз, когда язык уже известен (TJ:SetLang на ADDON_LOADED).
function TJ:ApplyLocaleData()
  if self.localeDataDone then return end
  self.localeDataDone = true
  for _, name in ipairs({ "Profs", "MatSources", "Nodes" }) do
    if type(TJ[name]) == "table" then Walk(TJ[name], 0) end
  end
end
