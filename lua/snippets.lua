--[[
snippet name
\tBody
\t${1:VALUE}
\t$1
\t$0
--]]


local INTERNAL = false
local LOG_INTERNAL
do
  local noop = function()end
  if INTERNAL then
    local function D(...)
      local res = {}
      for i = 1, select("#", ...) do
        local v = select(i, ...)
        table.insert(res, vim.inspect(v, {newline='';indent=''}))
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
  -- Each pattern should return either 3 or 4 things:
  -- 1. { starting_index, variable_id, ending_index }
  -- 2. { starting_index, variable_id, placeholder, ending_index }
  -- NOTE: Ordering is important!
  -- If one pattern may contain the other, it should be placed higher up.
  local patterns = {
    -- TODO(ashkan): allow an empty value in the :} part or throw an error?
    -- Pattern for ${1:default body}
    make_iterator(body:gmatch("()%${(%d+):([^}]*)}()")),
    -- Pattern for $1, $2, etc..
    make_iterator(body:gmatch("()%$(%d+)()")),
  }

  local values = {}
  for i, pattern in ipairs(patterns) do
    values[i] = {pattern()}
    LOG_INTERNAL("initializing", i, vim.inspect(values[i]))
  end

  local variables = {}

  local N = #values
  local start_position = 1
  for LOOP_IDX = 1, 10000000 do
    local next_index
    local next_value
    for i = 1, N do
      LOG_INTERNAL(LOOP_IDX, "checking", i, vim.inspect(values[i]))
      if #values[i] > 0 then
        local new_value
        if not next_value then
          new_value = values[i]
        else
          -- TODO(ashkan): report which indices.
          assert(next_value[1] ~= values[i][1], "Multiple patterns matched the same thing")
          if next_value[1] > values[i][1] then
            LOG_INTERNAL("preferring", i, "over", next_index)
            new_value = values[i]
          end
        end
        if new_value then
          next_index = i
          next_value = new_value
        end
      end
    end

    if not next_value then
      break
    end

    local left_pos, var_id, placeholder, right_pos
    if #next_value == 3 then
      left_pos, var_id, right_pos = unpack(next_value)
    else
      assert(#next_value == 4)
      left_pos, var_id, placeholder, right_pos = unpack(next_value)
    end
    assert(var_id)
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
    start_position = right_pos
    -- push a new value from our patterns.
    values[next_index] = {patterns[next_index]()}
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
