local _, TJ = ...
local T = TJ.T

-------------------------------------------------------------------------------
--  Поделиться находками: чертежи лагеря, источник которых в данных аддона
--  неизвестен, а игроку они уже выпадали (Tracking.lua запоминает, с кого и
--  где). Код одной строкой можно скопировать и отправить автору.
--  Код: «EasyCraft:bp:1» и записи «предмет;с кого;где;карта;x;y» через « | ».
-------------------------------------------------------------------------------
local HEADER = "EasyCraft:bp:1"
local ISSUES = "github.com/elrijk/EasyCraft/issues"

-- Чертежи без известного источника: id -> true.
local unknown
local function unknownBlueprints()
  if unknown then return unknown end
  unknown = {}
  for _, p in pairs(TJ.Profs) do
    for _, e in ipairs(p.camp or {}) do
      -- у известного источника в описании после двоеточия идёт место
      if e.bp and not (e.how or ""):match(":%s*(.+)$") then unknown[e.bp] = true end
    end
  end
  return unknown
end

local function clean(s) return (tostring(s or ""):gsub("[;|]", " ")) end

-- Находки, которыми стоит поделиться: { код, сколько записей }.
function TJ:BlueprintReport()
  local parts, want = { HEADER }, unknownBlueprints()
  local ids = {}
  for id in pairs(self.db.bpFound or {}) do if want[id] then ids[#ids + 1] = id end end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local f = self.db.bpFound[id]
    parts[#parts + 1] = table.concat({ id, clean(f.who), clean(f.where), f.map or "",
      f.x and string.format("%.1f", f.x) or "", f.y and string.format("%.1f", f.y) or "" }, ";")
  end
  return table.concat(parts, " | "), #ids
end

-- Таблицу игры не переприсваиваем, только добавляем свой ключ.
StaticPopupDialogs.EASYCRAFT_SHARE = {
  text = "%s",
  button1 = CLOSE or "Close",
  hasEditBox = true,
  editBoxWidth = 320,
  OnShow = function(self, data)
    local box = self.editBox or self.EditBox
    if not box then return end
    box:SetText(data or "")
    box:HighlightText()
    box:SetFocus()
  end,
  EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}

function TJ:ShareBlueprints()
  local code, n = self:BlueprintReport()
  if n == 0 then return end
  StaticPopup_Show("EASYCRAFT_SHARE", T("Скопируй код (Ctrl+C) и отправь автору аддона:") .. "\n" .. ISSUES, nil, code)
end
