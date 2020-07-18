--[[
snippet name
\tBody
\t${1:VALUE}
\t$1
\t$0
--]]


local INTERNAL = true
local LOG_INTERNAL
do
  local noop = function()end
  if INTERNAL then
    local inspect = require 'inspect'
    -- TODO(ashkan): move to utils.
    local function D(...)
      local res = {}
      for i = 1, select("#", ...) do
        local v = select(i, ...)
        table.insert(res, inspect(v, {newline='';indent=''}))
      end
      print(table.concat(res, ' '))
      return ...
    end
    LOG_INTERNAL = D
  else
    LOG_INTERNAL = noop
  end
end

-- Turn an iterator into a function you can call repeatedly
-- to consume the iterator.
local function make_iterator(f, s, var)
  local function helper(head, ...)
    if head == nil then
      return nil
    end
    var = head
    return head, ...
  end
  local first_run = true
  return function()
    if first_run or var then
      first_run = false
      return helper(f(s, var))
    end
  end
end

-- Take a string containing the variable substitutions and
-- turn it into a structural representation of a snippet.
--
-- Example:
-- parse_snippet("for ${1:i}, ${2:v} in ipairs(${3:t}) do $0 end")
--   == { 'for '; {'i'; id = 1}; ' '; {'v'; id = 2}; ' in ipairs('...
local function parse_snippet(body)
  local R = {}
  -- TODO(ashkan): error patterns that we can check which don't show up in here.
  -- Each pattern should return either 1 or 2 things:
  -- 1. { variable_id, }
  -- 2. { variable_id, placeholder, }
  -- NOTE: Ordering is important!
  -- If one pattern may contain the other, it should be placed higher up.
  local patterns = {
    -- TODO(ashkan): allow an empty value in the :} part or throw an error?
    -- Pattern for ${1:default body}
    "%${(%d+):([^}]*)}",
    -- Pattern for $1, $2, etc..
    "%$(%d+)",
  }

  local variables = {}

  local start_position = 1
  for LOOP_IDX = 1, 10000000 do
    -- try to find a new variable to parse out.
    local next_value
    for i, pattern in ipairs(patterns) do
      local value = {body:find(pattern, start_position)}
      LOG_INTERNAL(LOOP_IDX, "checking", i, value)
      if #value > 0 then
        local new_value
        if not next_value then
          new_value = value
        else
          -- TODO(ashkan): report which indices.
          assert(next_value[1] ~= value[1], "Multiple patterns matched the same thing")
          if next_value[1] > value[1] then
            LOG_INTERNAL("preferring", i, "over", next_index)
            new_value = value
          end
        end
        if new_value then
          next_value = new_value
        end
      end
    end

    if not next_value then
      break
    end

    local left_pos, var_id, placeholder, right_pos
    if #next_value == 3 then
      left_pos, right_pos, var_id = unpack(next_value)
    else
      assert(#next_value == 4, #next_value)
      left_pos, right_pos, var_id, placeholder = unpack(next_value)
    end
    assert(var_id, "var_id is nil")
    var_id = tonumber(var_id)
    assert(var_id, "var_id is not a number?")

    if variables[var_id] then
      if placeholder ~= nil then
        return nil, "Multiple placeholders defined for variable $"..var_id
      end
    end
    if left_pos ~= start_position then
      R[#R+1] = body:sub(start_position, left_pos - 1)
    end
    variables[var_id] = {
      placeholder = placeholder;
    }
    R[#R+1] = var_id
    start_position = right_pos+1
  end

  local tail = body:sub(start_position)
  if #tail > 0 then
    R[#R+1] = tail
  end
  return R, variables
end

return {
  make_iterator = make_iterator;
  parse_snippet = parse_snippet;
}
