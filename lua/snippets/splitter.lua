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

local function splitter(sep, plain)
	local Z = ""
	local m = {}
	function m.update(chunk)
		if chunk then
			Z = Z..chunk
		end
	end
	function m.iter()
		local starti, endi, start2, end2 = Z:find(sep, 1, plain)
		if starti then
			if start2 then starti = start2 end
			if end2   then endi   = end2-1   end
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
-- vim:noet sw=3 ts=3
