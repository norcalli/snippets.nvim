local function splitter(sep, plain)
	local Z = ""
	local m = {}
	function m.update(chunk)
		if chunk then
			Z = Z..chunk
		end
	end
	function m.iter()
		local starti, endi = Z:find(sep, 1, plain)
		if starti then
			local data = Z:sub(1, starti - 1)
			Z = Z:sub(endi+1)
			return data
		end
	end
	function m.finish()
		return Z
	end
  function m.drain(chunk)
    if chunk then m.update(chunk) end
    local finished = false
    return function()
      if finished then return end
      local v = m.iter()
      if v then return v end
      finished = true
      return m.finish()
    end
  end
  function m.collect(chunk)
    if chunk then m.update(chunk) end
    local r = {}
    for s in m.iter do
      r[#r+1] = s
    end
    r[#r+1] = m.finish()
    return r
  end
	return m
end

return splitter

