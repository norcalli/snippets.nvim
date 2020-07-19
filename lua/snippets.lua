local parser = require 'snippets.parser'
local ux = require 'snippets.nonextmark_inserter'
local U = require 'snippets.common'
local api = vim.api
local deepcopy = vim.deepcopy

local snippets = {}

local active_snippet

-- IMPORTANT(ashkan): For function calling to work correctly, this needs to be called! NOT OPTIONAL!
-- TODO(ashkan): validate snippets
-- 1. Should not have discontinuities in number (or I can auto correct it and pack them together)
-- 2. $0 should not have a placeholder.
-- 3. If there's no 0 in the structure, it should be empty in variables?
-- 4. Check variables exist n' shit.
local function validate_snippet(structure, variables)
	local S = {}
	-- TODO(ashkan): mutate this?
	for i, part in ipairs(structure) do
		if type(part) == 'number' then
			S[i] = part
		elseif type(part) == 'string' then
			S[i] = part
		elseif type(part) == 'function' then
			-- TODO(ashkan): pcall
			S[i] = tostring(part())
		else
			error(format("Invalid type in structure: %d, %q", i, type(part)))
		end
	end
	return S, variables or {}
end

local function advance_snippet(offset)
	offset = offset or 1
	if not active_snippet then
		U.LOG_INTERNAL("No active snippet")
		return false
	end
	-- This indicates finished by returning true.
	if active_snippet.advance(offset) then
		active_snippet = nil
	end
	return true
end

local function lookup_snippet(ft, word)
	for _, lutname in ipairs{ft, "_global"} do
		local lut = snippets[lutname]
		if lut then
			local snippet = lut[word]
			if snippet then
				-- Compile/parse the snippet upon using if it's a string and store the result back.
				if type(snippet) == 'string' then
					-- TODO(ashkan): check for parse errors.
					local s, v = parser.parse_snippet(snippet)
					if not s then
						error(v)
					end
					snippet = {s, v}
					lut[word] = snippet
				end
				return snippet
			end
		end
	end
end

-- TODO(ashkan): if someone undos, the active_snippet has to be erased...?
local function expand_at_cursor()
	if active_snippet then
		U.LOG_INTERNAL("Snippet is already active")
		return
	end
	local row, col = unpack(api.nvim_win_get_cursor(0))
	local line = api.nvim_get_current_line()
	-- TODO(ashkan): vim.region?
	-- unicode... multibyte...
	-- local col = vim.str_utfindex(line, col)

	local word = line:sub(1, col):match("%S+$")
	local ft = vim.bo.filetype
	U.LOG_INTERNAL("expand_at_cursor: filetype,cword=", ft, word)
	-- Lookup the snippet.
	-- Check the _global keyword as a fallback for non-filetype specific keys..
	U.LOG_INTERNAL("Snippets", snippets)
	local snippet = lookup_snippet(ft, word)
	U.LOG_INTERNAL("found snippet:", snippet)

	if snippet then
		local structure, variables = validate_snippet(snippet[1], snippet[2])
		api.nvim_win_set_cursor(0, {row, col-#word})
		api.nvim_set_current_line(line:sub(1, col-#word)..line:sub(col+1))
		-- By the end of insertion, the position of the cursor should be 
		active_snippet = ux(structure, variables)
		-- After insertion we need to start advancing the snippet
		-- - If there's nothing to advance, we should jump to the $0.
		-- - If there is no $0 in the structure/variables, we should
		-- jump to the end of insertion.
		advance_snippet(1)
		return true
	end
	return false
end

local example_keymap = {
	["i<c-k>"] = {
		"<cmd>lua local s = require'snippets'; return s.expand_at_cursor() or s.advance_snippet(1)<CR>",
		noremap = true;
	}
}

return setmetatable({
	expand_at_cursor = expand_at_cursor;
	advance_snippet = advance_snippet;
	mappings = example_keymap;
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
