local _, ns = ...
local W, C = ns.W, ns.Content
local format, min = string.format, math.min

-------------------------------------------------------------------------------
--  A crafting profession inside its card on the home tab (there are no
--  separate profession pages). The same idea as the mini window (Choice.lua):
--  a list of recipes that give skill now, the advice with the star, the
--  player picks one and it opens under its row: reagents, what the character
--  can make itself, minus, "Create" and plus. A recipe that is not learned
--  has the places to get it. At the skill cap there is nothing to level, so
--  the card shows what is profitable to craft for sale and which profitable
--  recipes are missing.
-------------------------------------------------------------------------------
local GREEN, RED, YELLOW, GREY = "|cff33dd33", "|cffff5555", "|cffffd100", "|cff9d9d9d"
local MAP_ICON = "Interface\\Icons\\INV_Misc_Map_01"
local CAP = 300

local function adviceRow(UI, key, e, X, picked)
  local isPick = e.spell == picked
  local where = e.known and "" or ns:AdviceWhere(e)
  local lines = {}
  if e.cost then lines[#lines + 1] = format(X.perCraft, W.Money(e.cost)) end
  return { tex = e.icon or ns.Icon(nil), text = ns:Hex(e.color) .. e.name .. "|r", sub = where ~= "" and where or nil,
    right = ns:AdviceRight(e, X), star = e.advice, hot = isPick,
    tip = { title = e.name, lines = lines, hint = isPick and X.unpickTip or X.pickTip },
    onClick = function()
      ns:Pick(key, (not isPick) and e.spell or nil)
      UI:Render(true)
    end }
end

-- The picked recipe, opened under its row.
local function detail(UI, c, key, plan, X)
  local e, b = plan.e, plan.b
  local inputs = {}
  for _, it in ipairs(b.items) do
    local col = it.have >= it.need and GREEN or (it.per and it.have >= it.per and YELLOW) or RED
    local tip = it.make and format(X.make, it.make.name) or nil
    if it.have < it.need and it.all > it.have then
      tip = YELLOW .. format(X.inBank, it.all - it.have) .. "|r" .. (tip and ("\n" .. tip) or "")
    end
    inputs[#inputs + 1] = { id = it.id, text = col .. min(it.have, 9999) .. "/" .. it.need .. "|r", done = it.have >= it.need, tip = tip }
  end
  local out = e.out and { id = e.out } or { tex = e.icon, spell = e.spell }
  out.text = "|cffffffff" .. plan.n .. "|r"
  c:Flow(inputs, out, 32, c.indent or UI.PAD, b.allHave and { GREEN .. X.allHave .. "|r" } or ns:StepBuyLines(b))

  -- reagents the character is short of but can make
  local rows = {}
  for _, it in ipairs(b.makes) do
    local mk = it.make
    rows[#rows + 1] = { id = it.id, text = format(X.make, mk.name), hot = mk.can > 0,
      right = (mk.can > 0 and GREEN or RED) .. mk.can .. "/" .. mk.crafts .. "|r",
      tip = { title = mk.name, lines = { X.makeTip } },
      onClick = function()
        if mk.can > 0 then ns:CraftOrOpen(mk.key, mk.spell, mk.can) else ns:OpenRecipe(mk.key, mk.spell) end
      end }
  end
  if #rows > 0 then c:Items(rows, 1, 26) end

  if not e.known then
    -- where to get the recipe: a click sets the pin or opens the zone on the map
    rows = {}
    for k, pl in ipairs(ns:AdvicePlaces(e, X)) do
      rows[#rows + 1] = { tex = MAP_ICON, text = pl.text, right = pl.right, hot = k == 1 and pl.go ~= nil,
        tip = { title = e.name, hint = pl.go and pl.tip or nil }, onClick = pl.go }
    end
    if #rows > 0 then c:Items(rows, 1, 26) else c:Text("|cffa03000" .. X.learn .. "|r", "body", { gap = 6 }) end
    return
  end

  -- minus, "Create", plus: the number is how many crafts are planned
  local st = ns:RecipeState(key, e.spell)
  local can
  if st then can = (not st.unknown and st.known and not st.enchant) and (st.count or 0) or 0
  else can = ns:CanMake({ rc = e.rc }) or 0 end
  can = min(can, plan.n)
  local function step(d)
    return function()
      ns:PickAdd(key, (IsShiftKeyDown and IsShiftKeyDown()) and d * 5 or d)
      UI:Render(true)
    end
  end
  c:Buttons({
    { text = "-", w = 34, tip = X.countTip, onClick = step(-1) },
    { text = (can >= plan.n or can == 0) and format(X.create, plan.n) or format(X.createOf, can, plan.n), w = 220, enabled = can > 0,
      tip = X.createTip, onClick = function() ns:CraftOrOpen(key, e.spell, can) end },
    { text = "+", w = 34, tip = X.countTip, onClick = step(1) },
  })
end

-- At the skill cap: what is profitable to craft for sale (learned recipes),
-- and profitable recipes the character does not have, with where to get them.
local function sellBody(UI, c, key, X)
  local known, unknown = ns:BookList(key)
  c:Text(X.capNote, "body", { gap = 6 })
  local function block(title, list, isKnown)
    local rows = {}
    for _, e in ipairs(list) do
      if #rows >= 4 then break end
      if e.profit and e.profit > 0 then
        local sub = (e.cost and e.sale) and format(X.costSale, W.Money(e.cost), W.Money(e.sale)) or nil
        local lines = sub and { sub } or {}
        local go, hint
        if isKnown then
          go, hint = function() ns:OpenRecipe(key, e.spell) end, X.openTip
        else
          local src = e.spell and ns:RecipeWhere(key, e.spell)
          local pl = src and ns:AdvicePlaces({ src = src }, X)[1]
          if pl then
            sub = pl.text .. (pl.right and (", " .. pl.right) or "")
            go, hint = pl.go, pl.go and pl.tip or nil
          end
        end
        rows[#rows + 1] = { id = e.out, tex = e.icon, text = e.name or "?", sub = sub, right = GREEN .. "+" .. W.Money(e.profit) .. "|r",
          star = #rows == 0, hot = #rows == 0, tip = { title = e.name or "?", lines = lines, hint = hint }, onClick = go }
      end
    end
    c:Text(title, "head", { gap = 6 })
    if #rows == 0 then c:Text(GREY .. X.sellNone .. "|r", "body") else c:Items(rows, 1, 28) end
  end
  block(X.sellHead, known, true)
  block(X.sellLearn, unknown, false)
end

-- The body of the card: the list to choose from with the picked recipe
-- opened in place, or the profitable recipes at the skill cap.
function C:HomeChoice(UI, c, key, rank, maxRank)
  local X = ns:ChoiceText()
  if rank >= CAP then return sellBody(UI, c, key, X) end
  local list = ns:Advice(key, rank)
  local plan = ns:PickPlan(key, rank, maxRank, nil, list)
  local picked = plan and plan.e.spell
  local function section(known, title, limit)
    local shown = 0
    for _, e in ipairs(list) do
      local isPick = e.spell == picked
      if e.known == known and (shown < limit or isPick) then
        if shown == 0 then c:Text(title, "head", { gap = 6 }) end
        shown = shown + 1
        c:Items({ adviceRow(UI, key, e, X, picked) }, 1, 28)
        if isPick then
          detail(UI, c, key, plan, X)
          c:Space(6)
        end
      end
    end
    return shown
  end
  if section(true, X.head, 5) + section(false, X.learnHead, 3) == 0 then c:Text(X.nothing, "body") end
end

-- One line for the heading of that card: what is being crafted, or a prompt.
function C:HomeChoiceLine(key, rank, maxRank)
  local X = ns:ChoiceText()
  if rank >= CAP then return X.sellHead end
  local plan = ns:PickPlan(key, rank, maxRank)
  if plan then return format(X.homePick, plan.e.name) .. " x" .. plan.n end
  return X.choose
end
