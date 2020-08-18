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
				table.insert(res, inspect(v, {newline='';indent=''}))
			end
			print(table.concat(res, ' '))
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

local snippet_mt = {}

-- local function is_snippet(t)
-- 	return type(t) == 'table' and t.structure
-- end

local function is_snippet(v)
	if type(v) == 'table' then
		return getmetatable(v) == snippet_mt
	end
end

local variable_mt = {}

local function structure_variable(is_input, variable_name, default_value, evaluation_order, transform)
	validate {
		variable_name = { variable_name, {'n', 's'}, true };
		default_value = { default_value, {'s', 'c'}; true };
		evaluation_order = { evaluation_order, 'n' };
		is_input = { is_input, 'b' };
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

local function is_variable(v)
	if type(v) == 'table' then
		return getmetatable(v) == variable_mt
	end
end

local function is_normalized_structure_component(v)
	return is_variable(v) or type(v) == 'string'
	-- if is_variable(v) then
	-- 	return true
	-- elseif type(v) == 'string' then
	-- 	return true
	-- else
	-- 	return false
	-- end
end

local function make_preorder_function_component(fn)
	return structure_variable(false, nil, fn, -1, nil)
end

local function make_postorder_function_component(fn)
	return structure_variable(false, nil, nil, math.huge, fn)
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
	else
		error("No idea how to handle structure component: "..vim.inspect(v))
	end
end

local function make_context(current_variable_value, variable_dictionary)
	return setmetatable({
		v = current_variable_value;
	}, {
		__index = setmetatable(variable_dictionary, {
			__index = function() return "" end;
		});
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

local function snippet_render_command()
end

local readonly_mt = {
	__newindex = function()end;
}

-- It will return a pair of rendering commands to evaluate next, and
-- any requests for further input.
local function evaluate_snippet(structure)
	LOG_INTERNAL("Evaluating", structure)
	-- local dynamic_components = {}
	local required_inputs = {}
	local seen_inputs = {}
	local S = {}
	local zero_index

	for i, part in ipairs(structure) do
		-- TODO(ashkan, Tue 18 Aug 2020 09:11:47 AM JST) do the normalization here?
		-- assert(is_normalized_structure_component(part))
		part = normalize_structure_component(part)
		S[i] = part
		if is_variable(part) then
			if part.id == 0 then
				zero_index = i
			end
			-- insert(dynamic_components, {i, part})
			if part.is_input then
				assert(part.id)
				if seen_inputs[part.id] then
					local input = seen_inputs[part.id]
					-- The default should only be specified once.
					-- TODO(ashkan, Tue 18 Aug 2020 09:18:31 AM JST) error message
					-- assert(not (part.default and input.default))
					input.default = input.default or part.default
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

	-- table.sort(dynamic_components, function(a, b)
	-- 	return a[2].order < b[2].order
	-- end)

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
		for i, part in ipairs(S) do
			if is_variable(part) then
				local var = part
				-- TODO(ashkan, Tue 18 Aug 2020 11:58:48 AM JST) @performance
				-- For non-interactive variables, the first value shall be the
				-- value for all instances. Further transformations will still
				-- apply due to the call to evaluate_variable after this branch.
				if not var.is_input and var.id and not var_dict[var.id] then
					var_dict[var.id] = evaluate_variable(var, var_dict)
				end
				-- TODO(ashkan, Tue 18 Aug 2020 01:27:16 PM JST) keep this `or ""`?
				-- without it, the `req` snippet for lua returns nil.
				result[i] = evaluate_variable(var, var_dict) or ""
			else
				result[i] = part
			end
			assert(type(result[i]) == 'string', type(result[i]))
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

local function validate_placeholder(placeholder)
	if type(placeholder) == 'function' then
		-- TODO(ashkan): pcall?
		return validate_placeholder(materialize(placeholder))
	elseif type(placeholder) == 'string' or is_snippet(placeholder) then
		return placeholder
	elseif placeholder then
		return tostring(placeholder)
	end
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

local function make_params(id, user_input, vars)
	return setmetatable({v=user_input, i=id, vars=vars}, {
		__index = function(_, k)
			return (vars[k] or {}).user_input
		end;
	})
end

local function evaluate_placeholder(placeholder, id, var, vars, params)
	if type(placeholder) == 'function' then
		local params = params or make_params(id, var, vars)
		-- TODO(ashkan): pcall?
		return evaluate_placeholder(assert(placeholder(params)), id, var, vars, params)
		-- return tostring(assert(placeholder{var=var, id=var_id, vars=vars}))
	elseif type(placeholder) == 'string' then
		return placeholder
	elseif placeholder then
		return tostring(placeholder)
	end
end

local function make_lambda(body, chunkname)
	if type(body) == 'function' then
		return body
	end
	return assert(loadstring("local S = ... return "..body, chunk_name))
end

local function evaluate_transform(transform, chunkname, ...)
	transform = make_lambda(transform, chunkname)
	local s, err = pcall(transform, ...)
	if not s then
		vim.api.nvim_err_writeln("snippets: Failed to evaluate transform: "..err)
		vim.api.nvim_command "mode"
		return
	end
	return err
end

local KINDS = {
	NORMAL           = 0;
	AUTO_EXPAND_PRE  = 1;
	AUTO_EXPAND_POST = 2;
}

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
	validate_placeholder = validate_placeholder;
	make_params = make_params;
	evaluate_placeholder = evaluate_placeholder;
	evaluate_transform = evaluate_transform;
	variable_needs_postprocessing = variable_needs_postprocessing;
	make_post_transform = make_post_transform;

	evaluate_snippet = evaluate_snippet;
	structure_variable = structure_variable;
	is_normalized_structure_component = is_normalized_structure_component;
	make_preorder_function_component = make_preorder_function_component;
	make_postorder_function_component = make_postorder_function_component;
	is_variable = is_variable;
	normalize_structure_component = normalize_structure_component;
	evaluate_variable = evaluate_variable;
	make_snippet = make_snippet;

	find_sub = find_sub;
	KINDS = KINDS;
}
-- vim:noet sw=3 ts=3
