local parser = require 'snippets.parser'
local ux = require 'snippets.nonextmark_inserter'
local nvu = require 'nvim_utils'
local api = vim.api

local snippets = {
-- SNIPPETS_COPYRIGHT_2020_AK_INDUSTRIES_THE_BEST_IN_THE_WORLD = {
  lua = {
    req = {
      {"local ", 1, " = require '", 2, "' ", 1, " ", 0 },
      {{placeholder = "name"}, {placeholder = "aslkdfja"}}
      -- {[0] = {}, {placeholder = "name"}, {placeholder = "aslkdfja"}}
    };
    req2 = "local $1 = ${2:$1}";
    todo = "TODO(ashkan): ";
    ["for"] = "for ${1:i}, ${2:v} in ipairs(${3:t}) do\n$0\nend";
  };
  [""] = {
    loc = "local ${1:11231} = $1";
    copyright = "COPYRIGHT 2020 ASHKAN KIANI BABYYYYYYYYYY";
    todo = "TODO(ashkan): ";
    note = "NOTE($0): ";
  };
}

SNIPPETS = snippets

local active_snippet

-- TODO(ashkan): validate snippets
-- 1. Should not have discontinuities in number (or I can auto correct it and pack them together)
-- 2. $0 should not have a placeholder.
-- 3. If there's no 0 in the structure, it should be empty in variables?
-- 4. Check variables exist n' shit.

local function advance_snippet(offset)
  offset = offset or 1
  if not active_snippet then
    -- print("No active snippet")
    return false
  end
  -- This indicates finished by returning true.
  if active_snippet.advance(offset) then
    active_snippet = nil
  end
  return true
end

-- TODO(ashkan): if someone undos, the active_snippet has to be erased...?
local function expand_at_cursor()
  if active_snippet then
    -- print("Snippet is already active")
    return
  end
	local row, col = unpack(api.nvim_win_get_cursor(0))
	local line = api.nvim_get_current_line()
  -- TODO(ashkan): vim.region?
  -- unicode... multibyte...
  -- local col = vim.str_utfindex(line, col)

	local word = line:sub(1, col):match("%S+$")
  local ft = vim.bo.filetype
  print(ft, word)
	local snippet = (snippets[ft] or {})[word]

	if snippet then
    -- lazily parse.
    if type(snippet) == 'string' then
      snippet = {parser.parse_snippet(snippet)}
      snippets[ft][word] = snippet
    end
    api.nvim_win_set_cursor(0, {row, col-#word})
    api.nvim_set_current_line(line:sub(1, col-#word)..line:sub(col+1))
    -- By the end of insertion, the position of the cursor should be 
    active_snippet = ux(snippet[1], snippet[2])
    -- After insertion we need to start advancing the snippet
    -- - If there's nothing to advance, we should jump to the $0.
    -- - If there is no $0 in the structure/variables, we should
    -- jump to the end of insertion.
    advance_snippet(1)
		return true
	end
	return false
end

vim.api.nvim_set_keymap("i", "<c-k>", "<cmd>lua return require'snippets'.expand_at_cursor() or require'snippets'.advance_snippet(1)<CR>", { noremap = true; })

return {
  expand_at_cursor = expand_at_cursor;
  advance_snippet = advance_snippet;
}

