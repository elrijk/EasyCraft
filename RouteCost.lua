local _, ns = ...

-------------------------------------------------------------------------------
--  Цена всего оставшегося пути профессии до 300: что ещё докупить по всем
--  шагам (а не только до учителя) по ценам аукциона и торговцев.
--  Возвращает: медь, сколько реагентов без цены.
-------------------------------------------------------------------------------
function ns:RouteCost(key)
  local total, noPrice = 0, 0
  for _, e in ipairs(self:ShoppingList(key)) do
    if not e.crafted and e.buy > 0 then
      local price = self:UnitPrice(e.id)
      if price then
        total = total + price * e.buy
      else
        noPrice = noPrice + 1
      end
    end
  end
  return total, noPrice
end
