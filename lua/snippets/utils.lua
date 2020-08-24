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

local U = require 'snippets.common'
local parser = require 'snippets.parser'
local nvim = require 'snippets.nvim'
local vim = vim
local api = vim.api
local nvim_get_current_line = api.nvim_get_current_line
local format = string.format
local concat = table.concat
local insert = table.insert
local min = math.min

local function identity1(x) return x.v end
local function noop(x) return "" end

local function get_line_indent()
	return nvim_get_current_line():match("^%s+") or ""
end

-- Only works with prefix comments.
local function get_line_comment()
	local cms = nvim.bo.commentstring
	-- This whole pesc dance is a bummer.
	local pattern = "^(%s*)"..
	(U.find_sub(vim.pesc((U.find_sub(cms, "\0", "%s", 1, true))), "(%s*).*", "\0", 1, true))
	local pre_ws, inner_ws = nvim_get_current_line():match(pattern)
	if pre_ws then
		return pre_ws..cms:format("")..inner_ws
	end
	return ""
end

local function once(fn, N)
	assert(type(fn) == 'function')
	local value
	return function(...)
		if not value then value = {fn(...)} end
		return unpack(value, 1, N or #value)
	end
end

local function into_snippet(s)
	if type(s) == 'string' then
		s = parser.parse_snippet(s)
	end
	return U.make_snippet(s)
end

local function lowest_variable_id(s)
	assert(U.is_snippet(s))
	local id = 0
	for i, v in ipairs(s) do
		if U.is_variable(v) and type(v.id) == 'number' then
			id = min(v.id or id, id)
		end
	end
	if id >= 0 then
		return 0
	end
	return id
end

local function iterate_variables_by_id(s, id, fn)
	local S = into_snippet(s)
	local count = 0
	for i, v in ipairs(S) do
		if U.is_variable(v) and v.id == id then
			count = count + 1
			S[i] = fn(v, count, i) or v
		end
	end
	return S
end

local function prefix_new_lines_with_function(s, fn)
	local S = into_snippet(s)
	local prefix_var = U.make_preorder_function_component(fn)
	-- Use a unique negative number so it's evaluated first.
	prefix_var.id = lowest_variable_id(S) - 1

	local function chain_transform(fn)
		local existing_transform = fn or identity1
		return function(S)
			-- Lookup the existing prefix created by our variable.
			local prefix = S[prefix_var.id]
			local value = existing_transform(S)
			-- TODO:
			--  Coerce into a string?
			--    - ashkan, Mon 24 Aug 2020 04:04:09 PM JST
			-- if value then value = tostring(value) end
			if type(value) == 'string' then
				local lines = vim.split(value, '\n', true)
				for i = 2, #lines do
					lines[i] = prefix..lines[i]
				end
				return concat(lines, '\n')
			end
		end
	end

	local R = {U.with_transform(prefix_var, noop)}
	for _, v in ipairs(S) do
		if type(v) == 'string' then
			local lines = vim.split(v, '\n', true)
			insert(R, lines[1])
			for i = 2, #lines do
				insert(R, '\n')
				insert(R, prefix_var)
				insert(R, lines[i])
			end
		else
			-- Add prefix to any variables which have NLs.
			v.transform = chain_transform(v.transform or identity1)
			insert(R, v)
		end
	end
	return U.make_snippet(R), prefix_var
end

local function match_indentation(s)
	return prefix_new_lines_with_function(s, get_line_indent)
end

local function match_comment(s)
	return prefix_new_lines_with_function(s, get_line_comment)
end

local function force_comment(s)
	local function get_comment_prefix()
		-- Add an extra space to it.
		return nvim.bo.commentstring:format(""):gsub("%S$", "%0 ")
	end
	local S = prefix_new_lines_with_function(s, get_comment_prefix)
	insert(S, 1, U.make_preorder_function_component(function()
		local comment = get_line_comment()
		if comment ~= "" then
			return ""
		end
		return get_comment_prefix()
	end))
	return S
end

local function match_comment_or_indentation(s)
	return prefix_new_lines_with_function(s, function()
		local comment = get_line_comment()
		if comment == "" then
			return get_line_indent()
		end
		return comment
	end)
end

local function comment_and_indent(s)
	return match_indentation(force_comment(s))
end

return {
	match_indentation = match_indentation;
	match_comment = match_comment;
	force_comment = force_comment;
	match_comment_or_indentation = match_comment_or_indentation;
	comment_and_indent = comment_and_indent;
	into_snippet = into_snippet;
	lowest_id = lowest_id;
	prefix_new_lines_with_function = prefix_new_lines_with_function;
	iterate_variables_by_id = iterate_variables_by_id;

	with_transform = U.with_transform;
}
-- vim:noet sw=3 ts=3
