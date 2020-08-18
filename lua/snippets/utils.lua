local U = require 'snippets.common'
local parser = require 'snippets.parser'
local format = string.format
local concat = table.concat
local insert = table.insert

local function identity1(x) return x.v end

local function line_indent()
  return vim.api.nvim_get_current_line():match("^%s+") or ""
end

local function into_snippet(s)
  if type(s) == 'string' then
    s = parser.parse_snippet(s)
  end
  return U.make_snippet(s)
end

local function match_indentation(s)
  local S = into_snippet(s)
  
  local indent = U.make_preorder_function_component(line_indent)
  -- Large negative number so it's evaluated first ish.
  indent.id = -123456789

  local R = {}
  for _, v in ipairs(S) do
    if type(v) == 'string' then
      local lines = vim.split(v, '\n', true)
      insert(R, lines[1])
      for i = 2, #lines do
        insert(R, '\n')
        insert(R, indent)
        insert(R, lines[i])
      end
    else
      local existing_transform = v.transform or identity1
      -- Add indentation to any variables which have newlines.
      v.transform = function(S)
        -- Lookup the existing indentation created by our variable.
        local indentation = S[indent.id]
        local value = existing_transform(S)
        local lines = vim.split(value, '\n', true)
        for i = 2, #lines do
          lines[i] = indentation..lines[i]
        end
        return concat(lines, '\n')
      end
      insert(R, v)
    end
  end
  return U.make_snippet(R)
end

return {
  match_indentation = match_indentation;
  into_snippet = into_snippet;
}
