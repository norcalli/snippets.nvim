local vim = vim
local parser = require 'snippets.parser'
local ux = require 'snippets.nonextmark_inserter'
local U = require 'snippets.common'
local api = vim.api
local deepcopy = vim.deepcopy
local format = string.format

local snippets = {}

local active_snippet

local function materialize(v, ...)
	-- TODO(ashkan, 2020-08-16 02:01:26+0900) callable
	if type(v) == 'function' then
		return materialize(v(...), ...)
	end
	return v
end

local function validate_placeholder(placeholder)
	if type(placeholder) == 'function' then
		-- TODO(ashkan): pcall?
		return validate_placeholder(materialize(placeholder))
	elseif type(placeholder) == 'string' or U.is_snippet(placeholder) then
		return placeholder
	elseif placeholder then
		return tostring(placeholder)
	end
end

-- local function validate_transform(transform)
-- 	-- TODO(ashkan, 2020-08-16 00:07:13+0900) check callable
-- 	if type(transform) == 'function' then
-- 		-- TODO(ashkan): pcall?
-- 		return transform
-- 	elseif type(transform) == 'string' then
-- 		-- TODO(ashkan, 2020-08-16 00:22:43+0900) chunkname
-- 		return U.make_lambda(transform)
-- 	else
-- 		return function() return transform end
-- 	end
-- end

local snippet_mt = {}

-- IMPORTANT(ashkan): For function calling to work correctly, this needs to be called! NOT OPTIONAL!
-- TODO(ashkan): validate snippets
-- 1. Should not have discontinuities in number (or I can auto correct it and pack them together)
-- 2. $0 should not have a placeholder.
-- 3. If there's no 0 in the structure, it should be empty in variables?
-- 4. Check variables exist n' shit.
local function validate_snippet(structure, variables)
	local S = {}
	local V = {}
	for i, var in pairs(variables) do
		local placeholder = ""
		if var.placeholder then
			assert(not var.expression, "Have both expression and placeholder")
			placeholder = assert(validate_placeholder(var.placeholder))
			-- placeholder = tostring(assert(materialize(var.placeholder)))
		elseif var.expression then
			placeholder = assert(validate_placeholder(var.expression))
			-- placeholder = tostring(assert(materialize(var.expression)))
		end
		if var.id then
			assert(placeholder)
		-- elseif var.id < 0 then
		-- 	assert(type(placeholder) == 'string', "Negative variable has no stringable placeholder")
		-- elseif not var.id then
		else
			assert(var.transforms[1])
			-- assert(placeholder or var.transforms[1])
		end
		V[i] = {
			id = var.id;
			-- count = var.count;
			placeholder = placeholder;
			-- TODO(ashkan, 2020-08-16 01:56:34+0900) add validation
			transforms = var.transforms or {};
		}
	end
	-- TODO(ashkan): mutate this?
	for i, part in ipairs(structure) do
		if type(part) == 'number' then
			local var = V[part]
			-- It's a variable id.
			if not var then
				var = {
					-- TODO(ashkan, 2020-08-16 02:06:19+0900) this is important...
					id = part;
				}
				V[part] = var
			end
			var.count = (var.count or 0) + 1

			local should_immediately_substitute = (var.id or -1) < 0 and var.placeholder

			-- Negative variables should just be replaced without user input.
			-- Same goes for anonymous variables
			if should_immediately_substitute then
				-- local placeholder, transform = var.placeholder, var.transforms[var.count]
				-- TODO(ashkan, 2020-08-16 02:19:30+0900) use transforms?
				-- if transform then
				-- 	-- TODO(ashkan, 2020-08-16 02:16:57+0900) make chunkname
				-- 	-- placeholder = U.evaluate_transform(transform, nil, U.make_params(var.id, placeholder, V
				-- end
				S[i] = var.placeholder
			else
				S[i] = part
			end
		elseif type(part) == 'string' then
			S[i] = part
		elseif type(part) == 'function' then
			-- TODO(ashkan): pcall
			S[i] = tostring(assert(materialize(part)))
			-- S[i] = tostring(part())
		elseif type(part) == 'table' and part.transform then
			S[i] = part
		else
			error(format("Invalid type in structure: %d, %q", i, type(part)))
		end
	end
	return S, V
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
				-- Compile/parse the snippet upon using if it's a string and store the result back.
				if type(snippet) == 'string' then
					-- TODO(ashkan): check for parse errors.
					local s, v = parser.parse_snippet(snippet, nil, lutname..'.'..word)
					if not s then
						error(v)
					end
					snippet = {structure = s, variables = v}
					lut[word] = snippet
				elseif type(snippet) == 'function' then
					snippet = {structure = {snippet}, variables = {}}
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
			local s, v = parser.parse_snippet(snippet, nil, ft..'.'..word)
			if not s then
				error(v)
			end
			snippet = {structure = s, variables = v}
		elseif type(snippet) == 'function' then
			snippet = {structure = {snippet}, variables = {}}
		else
			assert(type(snippet) == 'table', "snippet passed must be a table")
		end
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
		local structure, variables = validate_snippet(snippet.structure, snippet.variables)
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

local function expand_or_advance(offset)
	if active_snippet then
		local result = advance_snippet(offset or 1)
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
	}
}

return setmetatable({
	expand_at_cursor = expand_at_cursor;
	expand_or_advance = expand_or_advance;
	advance_snippet = advance_snippet;
	mappings = example_keymap;
	debug = U.debug;
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
