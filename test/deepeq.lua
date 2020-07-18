local function deepeq(a, b)
  if type(a) ~= type(b) then
    return false
  end
  if type(a) == 'table' then
    local seen = {}
    for k, v in pairs(a) do
      seen[k] = true
      if not deepeq(v, b[k]) then
        return false
      end
    end
    for k, v in pairs(b) do
      if not seen[k] then
        if not deepeq(v, a[k]) then
          return false
        end
      end
    end
    return true
  end
  return a == b
end

return deepeq

