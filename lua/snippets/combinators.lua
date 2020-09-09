-- Code taken from @archseer with his permission and modified by Ashkan Kiani

-- combinators
-- return success, value, pos

local function sym(t)
  return function(text, pos)
    if text:sub(pos, pos + #t - 1) == t then
        return true, nil, pos + #t
    else
        return false, text:sub(pos, pos + #t), pos + #t
    end
  end
end

local function pattern(pat, literal)
  return function(text, pos)
    if not literal and pat:sub(1,1) ~= '^' then
      pat = '^'..pat
    end
    local s, e = text:find(pat, pos, literal)
    if pos ~= s then
      return false, nil, pos
    end
    if s then
      local v = text:sub(s, e)
      return true, v, pos + #v
    else
      return false, nil, pos
    end
  end
end

-- Return this from map() to cancel the match success.
local MAP_SKIP = {}

local function map(p, f)
  return function(text, pos)
    local succ, val, new_pos = p(text, pos)
    if succ then
      val = f(val)
      if val ~= MAP_SKIP then
        return true, val, new_pos
      end
    end
    return false, nil, pos
  end
end

local function any(...)
  local parsers = { ... }
  return function(text, pos)
    for _, p in ipairs(parsers) do
      local succ, val, new_pos = p(text, pos)
      if succ then
        return true, val, new_pos
      end
    end
    return false, nil, pos
  end
end

local function seq(...)
  local parsers = { ... }
  return function(text, pos)
    local original_pos = pos
    local values = {}
    for i, p in ipairs(parsers) do
      local succ, val, new_pos = p(text, pos)
      pos = new_pos
      if not succ then
          return false, nil, original_pos
      end
      table.insert(values, val)
    end
    return true, values, pos
  end
end

local function many(p)
  return function(text, pos)
    local len = #text
    local values = {}

    while pos <= len do
      local succ, val, new_pos = p(text, pos)
      if succ then
        pos = new_pos
        table.insert(values, val)
      else
        break
      end
    end
    return #values > 0, values, pos
  end
end

local function take_until(patterns, literal)
  return function(text, pos)
    local s, e = text:find(patterns, pos, literal)
    -- TODO: handle escaping

    if s then
      -- would be empty string
      if pos == s then
        return false, nil, pos
      else
        -- consume up to the match point
        return true, text:sub(pos, s - 1), s
      end
    elseif pos <= #text then
      -- no match but there's text to consume
      return true, text:sub(pos), #text + 1
    else
      return false, nil, pos
    end
  end
end

local function separated(sep, p)
  return function(text, pos)
    local len = #text
    local values = {}

    local succ, val, new_pos = p(text, pos)
    if not succ then
      return false, nil, pos
    end
    table.insert(values, val)
    pos = new_pos

    while pos <= len do
      local succ, _, new_pos = sep(text, pos)
      if not succ then
        break
      end
      pos = new_pos


      local succ, val, new_pos = p(text, pos)
      if not succ then
        break
      end

      table.insert(values, val)
      pos = new_pos
    end
    return true, values, pos
  end
end

local function lazy(f)
  return function(text, pos)
    return f()(text, pos)
  end
end

return {
  sym = sym;
  pattern = pattern;
  map = map;
  any = any;
  seq = seq;
  many = many;
  take_until = take_until;
  separated = separated;
  lazy = lazy;
  SKIP = MAP_SKIP;
}
