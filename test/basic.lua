local format = string.format
local tests = {}
local function run_tests()
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
    print("\n\n")
    print(format("TEST %d: %q", i, name))
    -- TODO(ashkan): inspect the results.
    print(pcall(fn))
  end
end

-- TODO(ashkan): move to utils.
local function D(...)
  local res = {}
  for i = 1, select("#", ...) do
    local v = select(i, ...)
    table.insert(res, vim.inspect(v, {newline='';indent=''}))
  end
  print(table.concat(res, ' '))
  return ...
end
local deep_equal = vim.deep_equal

package.path = '../lua/init.lua;../lua/?.lua;'..package.path
local S = require 'snippets'

tests[#tests+1] = {
  "make_iterator returns some good stuff",
  function()
    local f = S.make_iterator(ipairs{1, 2, 3})
    assert(f() == 1)
    assert(f() == 2)
    assert(f() == 3)
    assert(f() == nil)
    assert(f() == nil)
  end
}

tests[#tests+1] = {
  "our pattern is sane",
  function()
    local R = {}
    local body = [[local ${1:variable} = $0]]
    for a, b, c, d in body:gmatch("()%$(%d+)()") do
      R[#R+1] = {a,b,c,d}
    end
    assert(#R > 0)
    D(R)
  end
}

tests[#tests+1] = {
  "our gmatch with make_iterator is sane",
  function()
    local R = {}
    local body = [[local ${1:variable} = $0]]
    for a, b, c, d in S.make_iterator(body:gmatch("()%$(%d+)()")) do
      R[#R+1] = {a,b,c,d}
    end
    assert(#R > 0)
    D(R)
  end
}

tests[#tests+1] = {
  "parse_snippet returns some goooooooooooooooooooood stuff",
  function()
    local body = [[local ${1:variable} = $0]]
    print("Snippet", body)
    local structure, variables = S.parse_snippet(body)
    D(structure, variables)
    assert(deep_equal(variables[0], {}))
    assert(deep_equal(variables[1], {placeholder = "variable"}))
    assert(deep_equal(structure, {"local ", 1, " = ", 0}))
  end
}

tests[#tests+1] = {
  "recursive parsing works",
  function()
    local body = [[local ${1:name} = require '${2:$1}']]
    print("Snippet", body)
    local structure, variables = S.parse_snippet(body)
    D(structure, variables)
    assert(deep_equal(variables[0], {}))
    assert(deep_equal(variables[1], {placeholder = "variable"}))
    assert(deep_equal(structure, {"local ", 1, " = ", 0}))
  end
}

run_tests()
