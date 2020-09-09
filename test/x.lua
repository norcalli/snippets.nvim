local format = string.format
local concat = table.concat
local insert = table.insert

require 'prelude' {
  {
    'Correctly parses stuff';
    function()
      local C = require 'snippets.common'
      local parse = require'snippets.parser'.make_ashkan_parser()
      local function z(s, inputs, expected)
        local ok, v, p = parse(s, 1)
        assert(p == #s+1, format("%d != %d\n%s\n%s^", p, #s, s, (" "):rep(p-1)))
        assert(ok, s)
        local result = table.concat(C.evaluate_snippet(v).evaluate_structure(inputs or {}))
        local should_print = not expected or result ~= expected
        if expected and result ~= expected then
          print(format("S: %s\n\tI: %s\n\tR: %s\n\tE: %s",
            v,
            inspect(inputs),
            result,
            expected))
          print(inspect(v))
          error(format("%q != %q", result, expected))
        elseif not expected then
          print(format("S: %s\n\tI: %s\n\tR: %s",
            v,
            inspect(inputs),
            result))
          print(inspect(v))
          assert(p == #s)
        end
      end
      z("Butts",                   {"hello"}, [[Butts]])
      z([[\begin]],   {},        [[\begin]])
      z("$1",                      {"hello"}, [[hello]])
      z("${1}",                    {"hello"}, [[hello]])
      z("${1|'123'} = $1",         {"hello"}, [[123 = hello]])
      z("${1='321'} = $1",         {"hello"}, [[hello = hello]])
      z("${1:'321'} = $1",         {},        [['321' = '321']])
      z("${1='321'} = ${1|'123'}", {},        [[321 = 123]])
      z("${1='321'|'123'} = $1",   {"hello"}, [[123 = hello]])
      z("${1:'321'|'123'} = $1",   {"hello"}, [[123 = hello]])
      z("${1:'321'|'123'} = $1",   {},        [[123 = '321']])
      z([[hello$0world]],   {},        [[helloworld]])
      -- z([[${1:$0'321'}]],   {},        [[$0'321']])
      -- z([[${1=\$0'321'}]],   {},        [[$0'321']])
      z([[${1:\$0'321'}]],   {},        [[$0'321']])
      -- TODO:
      --  $0 in placeholder...?
      --    - ashkan, Wed 09 Sep 2020 12:15:29 PM JST
      z([[${1:\\$0'321'}]],   {},        [[\'321']])
      z([[${1:\|$0'321'|'123'}]],   {},        [[123]])
    end
  }
}

