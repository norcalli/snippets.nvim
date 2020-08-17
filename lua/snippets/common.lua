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

local function is_snippet(t)
	return type(t) == 'table' and t.structure and t.variables
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

local function make_params(id, var, vars)
	return setmetatable({v=var, i=id, vars=vars}, {
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

-- local post_transform_mt = {}

local function make_post_transform(fn)
	return { transform = fn }
	-- return setmetatable({ transform = fn }, post_transform_mt)
end

local function is_post_transform(v)
	-- TODO(ashkan, 2020-08-17 12:33:40+0900) use mt?
	if type(v) == 'table' and v.transform then
		return true
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
	is_post_transform = is_post_transform;
	find_sub = find_sub;
	KINDS = KINDS;
}
-- vim:noet sw=3 ts=3
