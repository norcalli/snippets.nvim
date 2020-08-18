-- Copyright (C) 2020 Ashkan Kiani
-- This is part of the snippets.nvim distribution.
-- https://github.com/norcalli/snippets.nvim
-- 
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
-- 
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
-- 
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <https://www.gnu.org/licenses/>.

local vim = vim
local parser = require 'snippets.parser'
local ux = require 'snippets.inserters.text_markers'
-- local ux = require 'snippets.inserters.vim_input'
local U = require 'snippets.common'
local api = vim.api
local deepcopy = vim.deepcopy
local format = string.format

local snippets = {}

local active_snippet

local function validate_snippet(structure)
	local S = {}
	for i, part in ipairs(structure) do
		S[i] = U.normalize_structure_component(part)
	end
	return S
end

local ERRORS = {
	NONE = 1;
	ABORTED = 2;
}

local function advance_snippet(offset)
	offset = offset or 1
	if not active_snippet then
		U.LOG_INTERNAL("No active snippet")
		return false
	end
	local result = ERRORS.NONE
	-- This indicates finished by returning true.
	if active_snippet.advance(offset) then
		if active_snippet.aborted then
			result = ERRORS.ABORTED
		end
		active_snippet = nil
	end
	return result
end

local function lookup_snippet(ft, word)
	for _, lutname in ipairs{ft, "_global"} do
		local lut = snippets[lutname]
		if lut then
			local snippet = lut[word]
			if snippet then
				if not U.is_snippet(snippet) then
					-- Compile/parse the snippet upon using if it's a string and store the result back.
					if type(snippet) == 'string' then
						snippet = assert(parser.parse_snippet(snippet, nil, lutname..'.'..word))
					end
					snippet = U.make_snippet(snippet)
					lut[word] = snippet
				end
				return snippet
			end
		end
	end
end

-- TODO(ashkan): if someone undos, the active_snippet has to be erased...?
local function expand_at_cursor(snippet, expected_word)
	if active_snippet then
		U.LOG_INTERNAL("Snippet is already active")
		return
	end
	local is_anonymous = snippet ~= nil

	-- If it's anonymous, you can insert as is and handle deletion yourself,
	-- or pass in the word to replace.
	if is_anonymous then
		expected_word = expected_word or ""
	end

	local row, col = unpack(api.nvim_win_get_cursor(0))
	local line = api.nvim_get_current_line()
	-- TODO(ashkan): vim.region?
	-- unicode... multibyte...
	-- local col = vim.str_utfindex(line, col)

	-- Check if the expected word matches ("" doesn't work with :sub(-#word)).
	if expected_word and expected_word ~= '' and line:sub(-#expected_word) ~= expected_word then
		return
	end
	local ft = vim.bo.filetype
	local word = expected_word or line:sub(1, col):match("%S+$")
	U.LOG_INTERNAL("expand_at_cursor: filetype,cword=", ft, word)
	-- Lookup the snippet.
	-- Check the _global keyword as a fallback for non-filetype specific keys..
	U.LOG_INTERNAL("Snippets", snippets)

	local snippet_name
	if is_anonymous then
		if type(snippet) == 'string' then
			snippet = assert(parser.parse_snippet(snippet, nil, ft..'.'..word))
		end
		snippet = U.make_snippet(snippet)
		snippet_name = ("anonymous|snippet=%s|word=%s"):format(snippet or "?", expected_word or "")
	else
		snippet = lookup_snippet(ft, word)
		snippet_name = ("%s|%s"):format(ft, word)
	end
	U.LOG_INTERNAL("found snippet:", snippet)

	if snippet then
		-- assert(type(snippet) == 'table', "snippet passed must be a table")
		if not U.is_snippet(snippet) then
			error("not a snippet: "..vim.inspect(snippet))
		end
		local structure = validate_snippet(snippet)
		api.nvim_win_set_cursor(0, {row, col-#word})
		api.nvim_set_current_line(line:sub(1, col-#word)..line:sub(col+1))
		-- By the end of insertion, the position of the cursor should be
		active_snippet = ux(structure)
		-- After insertion we need to start advancing the snippet
		-- - If there's nothing to advance, we should jump to the $0.
		-- - If there is no $0 in the structure/variables, we should
		-- jump to the end of insertion.
		advance_snippet(1)
		return true
	end
	return false
end

local function expand_or_advance(offset)
	if active_snippet then
		local result = advance_snippet(offset or 1)
		U.LOG_INTERNAL("expand_or_advance: advance", result)
		if result == ERRORS.ABORTED then
			return expand_at_cursor()
		elseif result == ERRORS.NONE then
			return true
		else
			error("Unreachable")
		end
	end
	return expand_at_cursor()
end

local example_keymap = {
	["i<c-k>"] = {
		"<cmd>lua require'snippets'.expand_or_advance()<CR>",
		noremap = true;
	};
	["i<c-j>"] = {
		"<cmd>lua require'snippets'.advance_snippet(-1)<CR>",
		noremap = true;
	};
}

return setmetatable({
	expand_at_cursor = expand_at_cursor;
	expand_or_advance = expand_or_advance;
	advance_snippet = advance_snippet;
	mappings = example_keymap;
	debug = U.debug;
	u = require 'snippets.utils';
	use_suggested_mappings = function(buffer_local)
		for k, v in pairs(example_keymap) do
			local mode = k:sub(1,1)
			local lhs = k:sub(2)
			local rhs = table.remove(v, 1)
			local opts = v
			if buffer_local then
				api.nvim_buf_set_keymap(0, mode, lhs, rhs, opts)
			else
				api.nvim_set_keymap(mode, lhs, rhs, opts)
			end
		end
	end;
}, {
	__index = function(t, k, v)
		U.LOG_INTERNAL("index", k, v)
		if k == 'snippets' then
			return deepcopy(snippets)
		end
	end;
	__newindex = function(t, k, v)
		U.LOG_INTERNAL("newindex", k, v)
		if k == 'snippets' then
			snippets = deepcopy(v)
		end
	end;
})

-- vim:noet sw=3 ts=3
