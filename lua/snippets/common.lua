local INTERNAL = false
local LOG_INTERNAL
do
	local noop = function()end
	if INTERNAL then
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


return {
	LOG_INTERNAL = LOG_INTERNAL;
	make_iterator = make_iterator;
}
-- vim:noet sw=3 ts=3
