-- Dumps a compact index of Questie-X's stock WotLK database (and the Ascension plugin's records) so the
-- CoA export can be compared against it. Output: tab-separated lines on stdout.
--   Q <id> <name> <creatureStarts,> <objectStarts,> <itemStarts,> <creatureEnds,> <objectEnds,> <reqLevel> <questLevel>
--   N <id> <name> <zone>:<x>,<y>;...      (first 20 spawns)
--   O <id> <name> <zone>:<x>,<y>;...
--   I <id> <name>
-- Usage: lua dump_stock.lua <Questie-X-WotLKDB dir> <Questie-X-AscensionDB dir>
local wotlk, asc = arg[1] .. "/", arg[2] .. "/"

local function loadInto(path, addonTable)
	local f = assert(io.open(path, "rb")); local src = f:read("*a"); f:close()
	src = src:gsub("^\239\187\191", "")  -- some files start with a UTF-8 BOM, which WoW accepts and Lua 5.1 doesn't
	local chunk = assert(loadstring(src, "@" .. path))
	local env = setmetatable({ DEFAULT_CHAT_FRAME = { AddMessage = function() end } }, { __index = _G })
	env._G = env
	setfenv(chunk, env)
	chunk("x", addonTable)
	return env
end

local t = {}
for _, f in ipairs({ "wotlkQuestDB_1", "wotlkNpcDB_1", "wotlkNpcDB_2", "wotlkObjectDB_1",
                     "wotlkItemDB_1", "wotlkItemDB_2", "wotlkItemDB_3" }) do
	loadInto(wotlk .. "Database/Wotlk/Split/" .. f .. ".lua", t)
end
local a = {}
for _, f in ipairs({ "AscensionQuestDB_questData_1", "AscensionNpcDB_npcData_1", "AscensionObjectDB_objectData_1",
                     "AscensionItemDB_itemData_1" }) do
	loadInto(asc .. "Bronzebeard/Split/" .. f .. ".lua", a)
end

local function list(v) if type(v) ~= "table" then return "" end local o = {} for _, x in ipairs(v) do o[#o + 1] = tostring(x) end return table.concat(o, ",") end
local function spawns(v)
	if type(v) ~= "table" then return "" end
	local o, n = {}, 0
	for zone, pts in pairs(v) do
		if type(pts) == "table" then
			for _, p in ipairs(pts) do
				if n < 20 and type(p) == "table" then n = n + 1; o[#o + 1] = zone .. ":" .. tostring(p[1]) .. "," .. tostring(p[2]) end
			end
		end
	end
	return table.concat(o, ";")
end
local function clean(s) return (tostring(s or ""):gsub("[\t\r\n]", " ")) end

local function dump(src, tag, data)
	if type(data) ~= "table" then return end
	for id, r in pairs(data) do
		if type(id) == "number" and type(r) == "table" then
			if tag == "Q" then
				local sb, fb = r[2] or {}, r[3] or {}
				print(table.concat({ src .. "Q", id, clean(r[1]), list(sb[1]), list(sb[2]), list(sb[3]), list(fb[1]), list(fb[2]),
				                     tostring(r[4] or ""), tostring(r[5] or "") }, "\t"))
			elseif tag == "N" then
				print(table.concat({ src .. "N", id, clean(r[1]), spawns(r[7]) }, "\t"))
			elseif tag == "O" then
				print(table.concat({ src .. "O", id, clean(r[1]), spawns(r[4]) }, "\t"))
			else
				print(table.concat({ src .. "I", id, clean(r[1]) }, "\t"))
			end
		end
	end
end
dump("W", "Q", t.questData); dump("W", "N", t.npcData); dump("W", "O", t.objectData); dump("W", "I", t.itemData)
dump("A", "Q", a.questData); dump("A", "N", a.npcData); dump("A", "O", a.objectData); dump("A", "I", a.itemData)
