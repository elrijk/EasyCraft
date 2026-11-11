local _, TJ = ...

-------------------------------------------------------------------------------
--  Что из созданного считается лучшим для подземелий (d), рейдов (r) и PvP (p)
--  и каким классам. Ключ - id предмета, p - профессия, t - где он лучший,
--  c - классы (нет поля - всем классам).
--  СТАРТОВЫЙ СПИСОК: собран по классической игре и на WoW Forever не сверен.
--  Перед релизом пройти по нему в игре: убрать лишнее, добавить новое.
-------------------------------------------------------------------------------
local MELEE = { "WARRIOR", "ROGUE", "HUNTER", "DRUID" }
local CASTER = { "MAGE", "WARLOCK", "PRIEST" }
local HEALER = { "PRIEST", "DRUID", "PALADIN", "SHAMAN" }
local MANA = { "MAGE", "WARLOCK", "PRIEST", "DRUID", "PALADIN", "SHAMAN", "HUNTER" }
local TANK = { "WARRIOR", "DRUID", "PALADIN" }

TJ.Best = {
  -- Алхимия
  [13510] = { p = "alchemy", t = "r", c = TANK }, -- Настой титанов
  [13511] = { p = "alchemy", t = "r", c = HEALER }, -- Настой чистой мудрости
  [13512] = { p = "alchemy", t = "r", c = CASTER }, -- Настой высшей силы
  [13452] = { p = "alchemy", t = "dr", c = MELEE }, -- Эликсир мангуста
  [13454] = { p = "alchemy", t = "r", c = CASTER }, -- Сильный эликсир тайной магии
  [13444] = { p = "alchemy", t = "dr", c = MANA }, -- Сильное зелье маны
  [13457] = { p = "alchemy", t = "r" }, -- Сильное зелье защиты от огня
  [5634] = { p = "alchemy", t = "p" }, -- Зелье свободы действий
  [3387] = { p = "alchemy", t = "rp" }, -- Зелье ограниченной неуязвимости
  -- Кузнечное дело
  [12640] = { p = "blacksmithing", t = "rp", c = { "WARRIOR", "PALADIN" } }, -- Шлем Львиного Сердца
  [12404] = { p = "blacksmithing", t = "dr", c = { "WARRIOR", "ROGUE" } }, -- Плотное точило
  [12643] = { p = "blacksmithing", t = "dr", c = { "WARRIOR", "PALADIN", "SHAMAN", "DRUID" } }, -- Плотный грузик
  -- Наложение чар
  [20748] = { p = "enchanting", t = "r", c = HEALER }, -- Великолепное масло маны
  [20749] = { p = "enchanting", t = "r", c = { "MAGE", "WARLOCK" } }, -- Великолепное волшебное масло
  -- Инженерное дело
  [10646] = { p = "engineering", t = "rp" }, -- Гоблинский сапёрный заряд
  [15993] = { p = "engineering", t = "p" }, -- Ториевая граната
  [4390] = { p = "engineering", t = "p" }, -- Железная граната
  [18638] = { p = "engineering", t = "r" }, -- Сверхсияющий отражатель пламени
  -- Кожевничество
  [15063] = { p = "leatherworking", t = "dr", c = { "WARRIOR", "ROGUE", "HUNTER", "DRUID", "SHAMAN" } }, -- Рукавицы из кожи девизавра
  [15062] = { p = "leatherworking", t = "dr", c = { "WARRIOR", "ROGUE", "HUNTER", "DRUID", "SHAMAN" } }, -- Поножи из кожи девизавра
  [18510] = { p = "leatherworking", t = "r", c = HEALER }, -- Шкура дикого зверя
  -- Портняжное дело
  [14154] = { p = "tailoring", t = "dr", c = { "PRIEST" } }, -- Одеяния истинной веры
  [14152] = { p = "tailoring", t = "rp", c = { "MAGE" } }, -- Одеяние верховного мага
  -- Кулинария
  [13931] = { p = "cooking", t = "r", c = MANA }, -- Суп из ночного луциана
  [18254] = { p = "cooking", t = "r", c = CASTER }, -- Сюрприз из клубней
  [20452] = { p = "cooking", t = "r", c = { "WARRIOR", "PALADIN", "SHAMAN" } }, -- Копчёные пустынные пельмени
  [13928] = { p = "cooking", t = "drp", c = MELEE }, -- Жареный кальмар
  -- Первая помощь
  [14530] = { p = "firstaid", t = "drp" }, -- Плотные бинты из рунической ткани
}
