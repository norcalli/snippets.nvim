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

local validate = require 'snippets.validate'
local format = string.format
local concat = table.concat
local insert = table.insert

local noop = function()end
local LOG_INTERNAL = noop
local function set_internal_state(is_internal)
	if is_internal then
		local inspect = (vim and vim.inspect) or require 'inspect'
		-- TODO(ashkan): move to utils.
		local function D(...)
			local res = {}
			for i = 1, select("#", ...) do
				local v = select(i, ...)
				insert(res, inspect(v, {newline='';indent=''}))
			end
			print(concat(res, ' '))
			return ...
		end
		LOG_INTERNAL = D
	else
		LOG_INTERNAL = noop
	end
end

local function materialize(v, ...)
	-- TODO(ashkan, 2020-08-16 02:01:26+0900) callable
	if type(v) == 'function' then
		return materialize(v(...), ...)
	end
	return v
end

local function nil_if_empty(s)
	if s == "" then return end
	return s
end

local function stringify_variable(v)
	return format("${%s%s%s}", v.id or "", v.default and "="..tostring(v.default) or "", v.transform and "|" or "")
end

local variable_mt = {
	__tostring = stringify_variable;
}

local snippet_mt = {
	__tostring = function(t)
		local T = {}
		for i, v in ipairs(t) do
			if type(v) ~= 'string' then
				v = stringify_variable(v)
			end
			T[i] = v
		end
		return concat(T)
	end;
}

local function is_snippet(v)
	if type(v) == 'table' then
		return getmetatable(v) == snippet_mt
	end
end

local function structure_variable(is_input, variable_name, default_value, evaluation_order, transform)
	validate {
		is_input = { is_input, 'b' };
		variable_name = { variable_name, {'n', 's'}, true };
		default_value = { default_value, {'s', 'c'}; true };
		evaluation_order = { evaluation_order, 'n' };
		transform = { transform, 'c', true };
	}
	if is_input then
		assert(variable_name)
	end
	return setmetatable({
		id = variable_name;
		is_input = is_input;
		default = default_value;
		order = evaluation_order;
		transform = transform;
	}, variable_mt)
end

local function structure_matches_variable(v)
	return v.order and (v.id or v.default or v.is_input or v.transform) ~= nil
end

local function is_variable(v)
	if type(v) == 'table' then
		if getmetatable(v) == variable_mt then
			return true
		elseif structure_matches_variable(v) then
			setmetatable(v, variable_mt)
			return true
		end
	end
end

local function is_normalized_structure_component(v)
	return is_variable(v) or type(v) == 'string'
end

local function make_preorder_function_component(fn)
	return structure_variable(false, nil, fn, -1, nil)
end

local function make_postorder_function_component(fn)
	return structure_variable(false, nil, nil, math.huge, fn)
end

local function with_transform(var, transform)
	return structure_variable(
		var.is_input,
		var.id,
		var.default,
		var.order,
		transform)
end

local function normalize_structure_component(v)
	if is_normalized_structure_component(v) then
		return v
	elseif v == 0 then
		return structure_variable(false, 0, nil, 0, nil)
	elseif type(v) == 'number' then
		return structure_variable(v > 0, v, "", v, nil)
	elseif type(v) == 'function' then
		return make_preorder_function_component(v)
		-- Alternatively, evaluate after the fact with:
		-- return make_postorder_function_component(v)
	elseif type(v) == 'table' then
		-- Structural matching hack.
		if v.order and (v.id or v.default or v.is_input or v.transform) ~= nil then
			return setmetatable(v, variable_mt)
		end
	else
		error("No idea how to handle structure component: "..vim.inspect(v))
	end
end

local function make_context(current_variable_value, variable_dictionary)
	return setmetatable({
		v = current_variable_value;
	}, {
		__index = function(_, k)
			return rawget(variable_dictionary, k) or ""
		end
	})
end

local function evaluate_variable(var, defined_variables)
	LOG_INTERNAL("Evaluating variable", var, defined_variables)
	local value
	if var.id then
		LOG_INTERNAL("evaluate_variable lookup", defined_variables[var.id])
		value = defined_variables[var.id]
	end
	if not value and var.default then
		if type(var.default) == 'function' then
			-- TODO(ashkan, Tue 18 Aug 2020 08:37:58 AM JST) pcall?
			local context = make_context(nil, defined_variables)
			value = materialize(var.default, context)
		else
			value = var.default
		end
	end
	if not value then
		value = ""
	end
	if var.transform then
		local context = make_context(value, defined_variables)
		value = materialize(var.transform, context)
	end
	LOG_INTERNAL("evaluate_variable result", value)
	return value
end

local readonly_mt = {
	__newindex = function()end;
}

-- It will return a pair of rendering commands to evaluate next, and
-- any requests for further input.
local function evaluate_snippet(structure)
	LOG_INTERNAL("Evaluating", structure)
	local dynamic_components = {}
	local required_inputs = {}
	local seen_inputs = {}
	local S = {}
	local zero_index

	-- Normalize/validate and extract dynamic components so we can figure out
	-- their evaluation order.
	for i, part in ipairs(structure) do
		part = normalize_structure_component(part)
		S[i] = part
		if is_variable(part) then
			assert(part.order, "Our structure components aren't being normalized properly.")
			if part.id == 0 then
				zero_index = i
			else
				-- Ignore 0 since it shouldn't be evaluated.
				insert(dynamic_components, {i=i, v=part})
			end
			if part.is_input then
				assert(part.id)
				if seen_inputs[part.id] then
					local input = seen_inputs[part.id]
					-- The default should only be specified once, but hard erroring on
					-- it seems excessive, so instead we're just going to take the
					-- first one and call that "good enough," leaving the responsibility
					-- to the caller to make it work well.
					-- Since we use "" as the default value often, we add an extra
					-- step here of preferring any new values if they exist.
					input.default = nil_if_empty(input.default) or part.default or ""
				else
					local input = {
						id = part.id;
						default = part.default;
						order = part.order;
						first_index = i;
					}
					seen_inputs[part.id] = input
					insert(required_inputs, input)
				end
			end
		end
	end

	-- We use the index to disambiguate the evaluation order of dynamic
	-- components with the same `order` since table.sort is not stable.
	table.sort(dynamic_components, function(a, b)
		if a.v.order == b.v.order then
			return a.i < b.i
		else
			return a.v.order < b.v.order
		end
	end)

	table.sort(required_inputs, function(v1, v2)
		return v1.order < v2.order
	end)

	local evaluate_inputs = function(user_inputs)
		local result = {}
		local defined_variables = {}
		for i, var in ipairs(required_inputs) do
			local user_input = user_inputs[i]
			LOG_INTERNAL("evaluate_inputs", i, var, user_input)
			if user_input then
				assert(var.id)
				defined_variables[var.id] = user_input
				result[i] = user_input
			else
				result[i] = evaluate_variable(var, defined_variables)
			end
		end
		return result, defined_variables
	end

	local evaluate_structure = function(user_inputs)
		local inputs, var_dict = evaluate_inputs(user_inputs)
		local result = {}
		-- Make a copy of the structure, but skip the dynamic components for now
		-- since we need to evaluate them in a particular order.
		for i, part in ipairs(S) do
			if is_variable(part) then
				result[i] = ""
			else
				result[i] = part
			end
			assert(type(result[i]) == 'string', type(result[i]))
		end
		for _, v in ipairs(dynamic_components) do
			local index = v.i
			local var = v.v
			-- For non-interactive variables, the first value shall be the
			-- value for all instances. Further transformations will still
			-- apply due to the call to evaluate_variable after this branch.
			if not var.is_input and var.id and not var_dict[var.id] then
				var_dict[var.id] = evaluate_variable(with_transform(var, nil), var_dict)
				LOG_INTERNAL("Updating var dict", var, var_dict[var.id])
			end
			LOG_INTERNAL("Var dict", index, var.id and var_dict[var.id], var, var_dict)
			-- TODO(ashkan, Tue 18 Aug 2020 01:27:16 PM JST) keep this `or ""`?
			-- without it, the `req` snippet for lua returns nil.
			local value = evaluate_variable(var, var_dict) or ""
			assert(type(value) == 'string', type(value))
			result[index] = value
		end
		-- Sanity check
		for i, part in ipairs(result) do
			assert(type(part) == 'string', type(part))
		end
		LOG_INTERNAL("evaluate_structure", result)
		return result
	end

	local function evaluate_defaults(resolved_inputs, default_fn)
		local inputs = {}
		for i, v in ipairs(required_inputs) do
			if resolved_inputs[i] then
				inputs[i] = resolved_inputs[i]
			else
				inputs[i] = default_fn(v)
			end
		end
		-- Use the transformations/defaults.
		return evaluate_inputs(inputs)
	end

	return {
		zero_index = zero_index;
		structure = setmetatable(S, readonly_mt);
		inputs = setmetatable(required_inputs, readonly_mt);
		evaluate_inputs = evaluate_inputs;
		evaluate_structure = evaluate_structure;
		evaluate_defaults = evaluate_defaults;
	}
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

local function make_lambda(body, chunkname)
	if type(body) == 'function' then
		return body
	end
	return assert(loadstring("local S = ... return "..body, chunk_name))
end

-- TODO(ashkan, Wed 19 Aug 2020 12:28:10 AM JST) move this to text_markers or delete it.
local function variable_needs_postprocessing(var, vars)
	-- TODO(ashkan, 2020-08-17 13:49:27+0900) normal variable transforms may reference
	-- previous variables, so this should actually check if any variable has transforms...
	-- TODO(ashkan, 2020-08-17 13:14:14+0900) post processing variables may reference
	-- all variables, so this could always be true
	-- TODO(ashkan, 2020-08-17 13:14:30+0900) pass variables dictionary in
	-- so I can see if there are any post processing transforms.
	for var_id, var in pairs(vars) do
		-- TODO(ashkan, 2020-08-17 13:23:33+0900) this is specific to nonextmark_inserter...
		if var_id > 0 and var_id < 1 then
			return true
		end
		if var.transforms and var.transforms[1] then
			return true
		end
	end
	-- return true
	return var.count > 1 or (var.transforms and var.transforms[1])
end

local function make_snippet(v)
	if is_snippet(v) then
		return v
	elseif type(v) == 'table' then
		return setmetatable(v, snippet_mt)
	else
		return setmetatable({normalize_structure_component(v)}, snippet_mt)
	end
end

local function find_sub(s, replacement, pattern, start, special)
	local x1, x2 = s:find(pattern, start, special)
	if x1 then
		return s:sub(1, x1-1)..replacement..s:sub(x2+1), x1, x2
	end
	return s
end

-- local function make_snippet_into_placeholder_function(s)
--   local evaluator = evaluate_snippet(s)
--   return function(context)
--     local inputs = {}
--     for i, v in ipairs(evaluator.inputs) do
--       -- TODO(ashkan, Tue 18 Aug 2020 09:37:37 AM JST) ignore the v.default here?
--       inputs[i] = context[v.id]
--     end
--     return concat(evaluator.evaluate_structure(inputs))
--   end
-- end

return {
	debug = function(v)
		set_internal_state(not not v)
	end;
	LOG_INTERNAL = function(...)
		return LOG_INTERNAL(...)
	end;

	make_iterator = make_iterator;
	make_lambda = make_lambda;
	is_snippet = is_snippet;
	materialize = materialize;
	variable_needs_postprocessing = variable_needs_postprocessing;

	evaluate_snippet = evaluate_snippet;
	structure_variable = structure_variable;
	is_normalized_structure_component = is_normalized_structure_component;
	make_preorder_function_component = make_preorder_function_component;
	make_postorder_function_component = make_postorder_function_component;
	is_variable = is_variable;
	normalize_structure_component = normalize_structure_component;
	evaluate_variable = evaluate_variable;
	make_snippet = make_snippet;
	with_transform = with_transform;

	find_sub = find_sub;
}
-- vim:noet sw=3 ts=3
