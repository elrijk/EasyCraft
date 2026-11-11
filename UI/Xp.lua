local _, ns = ...
local C, T, W = ns.Content, ns.T, ns.W
local floor, max, min = math.floor, math.max, math.min

-------------------------------------------------------------------------------
--  «Опыт: максимум в час» во вкладке «Лагерь»: какие бонусы к опыту есть,
--  как их получить и в каком порядке включать; как добыть «Уютный спальник».
--  Цифры - из гайдов (wowforeverleveling.com, wow-professions.com, mmoexp.com,
--  ноябрь 2026). Часть из них Blizzard не подтверждала: сверяй с подсказкой
--  бафа в игре.
-------------------------------------------------------------------------------
local ICON = "Interface\\Icons\\"
local XP_COLS, XP_GAP, XP_RING = 2, 28, 26

-- { значок, название, бонус, что сделать, подробности }
local SOURCES = {
  { "Spell_Nature_Sleep", "Отдых (синяя полоса)", "x2 за убийства",
    "Выходи из игры в таверне или городе.",
    "Копится, пока ты не в игре: около 5% уровня за 8 часов, до 150% уровня. Удваивает опыт за убийства, на задания не действует." },
  { "INV_Misc_Bag_10", "Уютный спальник", "до +3%",
    "Полежи 3 минуты: +1% за минуту. За убийства и задания.",
    "Держится 2 часа (по части гайдов - 1 час), перезарядка 1 час. Не пропадает при смерти. В городах и тавернах не ставится. Как добыть - ниже." },
  { "INV_Misc_Pelt_Wolf_01", "Палатка лагеря", "отдых до 5%",
    "Кожевничество 20, 5 лёгкой кожи. Поставь у костра и посиди минуту.",
    "Доливает синюю полосу отдыха до 5% уровня, раз в час. Если отдыха уже больше - ничего не даст. Получают все, кто сидит рядом." },
  { "INV_Misc_Food_15", "Еда, созданная кулинарией", "около +5%",
    "Съешь перед боем: «Сытость» с бонусом к опыту.",
    "По гайдам - +5% за убийства примерно на 15 минут, пропадает при смерти. Точную цифру Blizzard не называла: смотри подсказку бафа." },
  { "INV_Misc_Head_Dragon_01", "Подземелья", "больше за убийства",
    "Опыт за убийства в подземельях повышен.",
    "Задания подземелий дают меньше обычного, убийства - больше." },
}

local ORDER = "Порядок: зайди отдохнувшим - палатка, если отдыха мало - 3 минуты на спальнике и еда - качайся - закончи в таверне."

-- Цепочка заданий на спальник: с 14 уровня, шесть заданий.
local BAG = {
  { "1", "«...и та записка, что ты нашёл»", "Альянс: Западный край, ферма Алекстонов (37, 51). Орда: Степи, к югу от Лагеря Таураджо (46, 74).",
    "Альянс: прибитая доска на ферме. Орда: сгоревшие остатки в Степях. Потом иди к месту другой фракции и осмотри предмет там." },
  { "2", "«Ступеньки»", "Когтистые горы (41, 53)",
    "Заброшенный лагерь над Приютом у Солнечного Камня: бумажки на ящике. В награду - две сумки на 12 ячеек." },
  { "3", "«Вскарабкаться»", "Когтистые горы (40, 50)",
    "Холмик земли на уступе рядом. Возьми следующее задание, не уходя." },
  { "4", "«Мокрое дело»", "Лок Модан, Каменная плотина (49, 13)",
    "Резная фигурка на узком уступе под верхней дорожкой: спрыгни на него." },
  { "5", "«Кулак орла»", "Стена Торадина со стороны Хилсбрада (87, 50)",
    "Сумка гонца висит на стене: залезь по сломанной телеге и уступам." },
  { "6", "«Должно быть, это здесь»", "Нагорье Арати у Стены Торадина (23, 24)",
    "Свёрнутый ранец прямо под сумкой гонца. Награда - «Уютный спальник»." },
}

-- Где стоит каждый шаг: { зона (номер из Data/Zones.lua), x, y }.
local BAG_PIN = {
  { A = { 40, 37, 51 }, H = { 17, 46, 74 } },
  { 406, 41, 53 },
  { 406, 40, 50 },
  { 38, 49, 13 },
  { 267, 87, 50 },
  { 45, 23, 24 },
}

function C:XpCard(UI)
  local PAD, CW = UI.PAD, UI.CARD_W
  local c = UI:Card()
  c:Head({ ring = ICON .. "Spell_Holy_BlessingOfStrength" }, T("Опыт: максимум в час"),
    { { T("Бонусы складываются."), "small" } }, 32)
  -- источники блоками по два в ряд: значок, название и бонус зелёным,
  -- ниже - что сделать и подробности
  local rp = W.RingPad(XP_RING)
  local outer = XP_RING + rp * 2
  local colW = floor((CW - PAD * 2 - XP_GAP * (XP_COLS - 1)) / XP_COLS)
  local rowTop = c.y + 10
  for first = 1, #SOURCES, XP_COLS do
    local xs, rowH = {}, 0
    for i = first, min(first + XP_COLS - 1, #SOURCES) do
      local s = SOURCES[i]
      local x = PAD + (i - first) * (colW + XP_GAP)
      local by = rowTop
      c:Ring(XP_RING, x + rp, by + rp):SetIcon(ICON .. s[1])
      c:TextBlock(x + outer + 6, by, outer, colW - outer - 6, {
        { T(s[2]), "head", W.LIGHT, true },
        { "|cff33dd33" .. T(s[3]) .. "|r", "small" },
      })
      by = by + outer + 6
      local fs = c:Text(T(s[4]), "small", { x = x, y = by, w = colW, color = W.LIGHT })
      by = by + (fs and fs:GetStringHeight() or 14) + 4
      fs = c:Text(T(s[5]), "small", { x = x, y = by, w = colW })
      by = by + (fs and fs:GetStringHeight() or 14)
      rowH = max(rowH, by - rowTop)
      xs[#xs + 1] = x
    end
    -- подложка у блоков ряда одной высоты
    for _, x in ipairs(xs) do
      local bg = c:Take("xpbg", function()
        local t = c:CreateTexture(nil, "BORDER")
        t:SetColorTexture(0, 0, 0, 0.3)
        return t
      end)
      bg:SetPoint("TOPLEFT", c, "TOPLEFT", x - 8, -(rowTop - 8))
      bg:SetSize(colW + 16, rowH + 16)
    end
    rowTop = rowTop + rowH + XP_GAP
  end
  c.y = rowTop - XP_GAP + 14
  c:Text(T(ORDER), "small", { gap = 6 })
  local open = UI.xpBag
  c:Buttons({ { text = open and T("Скрыть путь к спальнику") or T("Как добыть спальник"), w = 220,
    tip = T("Шесть заданий с 14 уровня на двух материках."),
    onClick = function() UI.xpBag = not UI.xpBag; UI:Render(true) end } })
  if open then
    -- шаги блоками: слева название, где и что сделать; справа кнопка метки
    local BTN_W = 170
    local tw = CW - PAD * 2 - BTN_W - 16
    local me = ns:PlayerFaction()
    local y = c.y + 8
    for i, b in ipairs(BAG) do
      -- у первого шага место своё у каждой фракции
      local pin = BAG_PIN[i]
      if pin.A then pin = (me == "A") and pin.A or pin.H end
      local z = ns.Zones[pin[1]]
      local top = y
      local fs = c:Text(b[1] .. ". " .. T(b[2]), "head", { x = PAD, y = y, w = tw, color = W.LIGHT })
      y = y + (fs and fs:GetStringHeight() or 16) + 3
      fs = c:Text(T(b[3]), "small", { x = PAD, y = y, w = tw, color = W.LIGHT })
      y = y + (fs and fs:GetStringHeight() or 14) + 3
      fs = c:Text(T(b[4]), "small", { x = PAD, y = y, w = tw })
      y = y + (fs and fs:GetStringHeight() or 14)
      c:Button({ text = T("Показать на карте"), w = BTN_W, enabled = z ~= nil,
        tip = T("Щелчок поставит метку и откроет карту."),
        onClick = function()
          ns:MapPoint(z.uiMap or z.ui, pin[2], pin[3], T(b[2]), ns:ZoneName(pin[1]), true)
        end }, PAD, top, true)
      local bg = c:Take("xpbg", function()
        local t = c:CreateTexture(nil, "BORDER")
        t:SetColorTexture(0, 0, 0, 0.3)
        return t
      end)
      bg:SetPoint("TOPLEFT", c, "TOPLEFT", PAD - 8, -(top - 8))
      bg:SetSize(CW - PAD * 2 + 16, y - top + 16)
      y = y + 16 + 10
    end
    c.y = y - 6
    c:Text("|cff9d9d9d" .. T("Путь взят из гайдов; названия заданий в игре могут отличаться.") .. "|r", "small", { gap = 4 })
  end
  UI:End(c)
end
