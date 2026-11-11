local _, ns = ...
local C, T, W = ns.Content, ns.T, ns.W
local floor, max, min = math.floor, math.max, math.min

-------------------------------------------------------------------------------
--  The "XP bonuses from professions" card on the Camp tab: the Camp Tent
--  (leatherworking) and cooked food (cooking).
--  The numbers come from player guides (wowforeverleveling.com,
--  wow-professions.com, mmoexp.com, November 2026). Blizzard has not confirmed
--  some of them: check the buff tooltip in the game.
-------------------------------------------------------------------------------
local ICON = "Interface\\Icons\\"
-- XP_GAP - просвет между блоками, XP_BP - поле внутри блока (со всех сторон), XP_BG - насколько блок темнее карточки
local XP_COLS, XP_GAP, XP_RING, XP_BP, XP_BG = 2, 12, 26, 12, 0.55

-- { значок, название, бонус, что сделать, подробности }
local SOURCES = {
  { "INV_Misc_Pelt_Wolf_01", "Палатка лагеря", "отдых до 5%",
    "Кожевничество 20, 5 лёгкой кожи. Поставь у костра и посиди минуту.",
    "Доливает синюю полосу отдыха до 5% уровня, раз в час. Если отдыха уже больше - ничего не даст. Получают все, кто сидит рядом." },
  { "INV_Misc_Food_15", "Еда, созданная кулинарией", "около +5%",
    "Съешь перед боем: «Сытость» с бонусом к опыту.",
    "По гайдам - +5% за убийства примерно на 15 минут, пропадает при смерти. Точную цифру Blizzard не называла: смотри подсказку бафа." },
}

function C:XpCard(UI)
  local PAD, CW = UI.PAD, UI.CARD_W
  local c = UI:Card()
  c:Head({ ring = ICON .. "Spell_Holy_BlessingOfStrength" }, T("Бонусы к опыту от профессий"),
    { { T("Бонусы складываются."), "small" } }, 32)
  -- источники блоками по два в ряд: значок, название и бонус зелёным,
  -- ниже - что сделать и подробности
  local rp = W.RingPad(XP_RING)
  local outer = XP_RING + rp * 2
  local blockW = floor((CW - PAD * 2 - XP_GAP * (XP_COLS - 1)) / XP_COLS)
  local colW = blockW - XP_BP * 2
  local rowTop = c.y + 8 + XP_BP
  for first = 1, #SOURCES, XP_COLS do
    local xs, rowH = {}, 0
    for i = first, min(first + XP_COLS - 1, #SOURCES) do
      local s = SOURCES[i]
      local x = PAD + XP_BP + (i - first) * (blockW + XP_GAP)
      local by = rowTop
      c:Ring(XP_RING, x + rp, by + rp):SetIcon(ICON .. s[1])
      c:TextBlock(x + outer + 6, by, outer, colW - outer - 6, {
        { T(s[2]), "head", W.LIGHT, true },
        { "|cff33dd33" .. T(s[3]) .. "|r", "small" },
      })
      by = by + outer + 6
      local fs = c:Text(T(s[4]), "small", { x = x, y = by, w = colW, color = W.LIGHT })
      by = by + (fs and fs:GetStringHeight() or 14) + 6
      -- подробности: сколько даёт, как часто, когда пропадает
      fs = c:Text(T(s[5]), "small", { x = x, y = by, w = colW })
      by = by + (fs and fs:GetStringHeight() or 14)
      rowH = max(rowH, by - rowTop)
      xs[#xs + 1] = x
    end
    -- подложка у блоков ряда одной высоты
    for _, x in ipairs(xs) do
      local bg = c:Take("xpbg", function()
        local t = c:CreateTexture(nil, "BORDER")
        t:SetColorTexture(0, 0, 0, XP_BG)
        return t
      end)
      bg:SetPoint("TOPLEFT", c, "TOPLEFT", x - XP_BP, -(rowTop - XP_BP))
      bg:SetSize(blockW, rowH + XP_BP * 2)
    end
    rowTop = rowTop + rowH + XP_BP * 2 + XP_GAP
  end
  -- rowTop - верх содержимого следующего ряда: низ последнего блока выше на поле и просвет
  c.y = rowTop - XP_BP - XP_GAP + 12
  UI:End(c)
end
