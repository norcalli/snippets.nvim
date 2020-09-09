inspect = (vim and vim.inspect) or require 'inspect'
local inspect = inspect
local format = string.format
local concat = table.concat
local insert = table.insert

-- TODO(ashkan): move to utils.
function D(...)
  local res = {}
  for i = 1, select("#", ...) do
    local v = select(i, ...)
    insert(res, inspect(v, {newline='';indent=''}))
  end
  io.write(concat(res, ' '), '\n')
  return ...
end
local deep_equal = require 'deepeq'
assert(deep_equal)

local function run_tests(tests)
  print("TESTS COUNT:", #tests)
  for i, test in ipairs(tests) do
    local name = ""
    local fn
    if type(test) == "table" then
      name = test[1]
      fn = test[2]
    elseif type(test) == 'function' then
      fn = test
    else
      error("Invalid type for test "..i)
    end
    print(" ")
    print(format("TEST %d: %q", i, name))
    -- TODO(ashkan): use xpcall and print the backtrace on finish
    -- D(pcall(fn))
    D(fn())
  end
end

package.path = '../lua/init.lua;../lua/?.lua;'..package.path

return run_tests
