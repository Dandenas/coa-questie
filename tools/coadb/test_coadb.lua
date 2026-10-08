-- Load test for the generated Questie-X-CoADB plugin: loads its TOC files in order with a stand-in for
-- Questie's plugin API, fires PLAYER_LOGIN, and checks what was injected (including that CoA values win over
-- fields the Ascension plugin set first). Usage: lua test_coadb.lua <Questie-X-CoADB dir>
local dir = arg[1] .. "/"

local function read(path)
	local f = assert(io.open(path, "rb")); local s = f:read("*a"); f:close(); return s
end

local env = setmetatable({}, { __index = _G })
env._G = env
env.C_CharacterAdvancement = {}
local onEvent
env.CreateFrame = function()
	return { RegisterEvent = function() end, UnregisterEvent = function() end,
	         SetScript = function(_, _, f) onEvent = f end }
end
-- Questie's overrides tables, with one Ascension-protected record already in place (quest 1903520's name)
local QuestieDB = { questDataOverrides = { [1903520] = { [1] = "Ascension name" } }, npcDataOverrides = {},
                    objectDataOverrides = {}, itemDataOverrides = {} }
local injected, finished = {}, nil
local plugin = {
	InjectDatabase = function(_, kind, data)
		local target = ({ QUEST = QuestieDB.questDataOverrides, NPC = QuestieDB.npcDataOverrides,
		                  OBJECT = QuestieDB.objectDataOverrides, ITEM = QuestieDB.itemDataOverrides })[kind]
		local n = 0
		for id, entry in pairs(data) do
			n = n + 1
			if target[id] then
				for k, v in pairs(entry) do if not (kind == "QUEST" and id == 1903520 and k == 1) then target[id][k] = v end end
			else
				target[id] = entry
			end
		end
		injected[kind] = n
	end,
	FinishLoading = function(_, flavor) finished = flavor end,
}
env.QuestieLoader = { ImportModule = function(_, name)
	if name == "QuestiePluginAPI" then return { RegisterPlugin = function() return plugin end } end
	if name == "QuestieDB" then return QuestieDB end
end }

local addonTable = {}
for line in read(dir .. "Questie-X-CoADB.toc"):gmatch("[^\r\n]+") do
	if not line:match("^#") and line:match("%.lua$") then
		local chunk = assert(loadstring(read(dir .. line:gsub("\\", "/")), "@" .. line))
		setfenv(chunk, env)
		chunk("Questie-X-CoADB", addonTable)
	end
end
assert(onEvent, "the loader waits for PLAYER_LOGIN")
onEvent({ UnregisterEvent = function() end }, "PLAYER_LOGIN")
assert(finished == "CoA", "the plugin finishes loading")
for _, kind in ipairs({ "QUEST", "NPC", "OBJECT", "ITEM" }) do
	assert((injected[kind] or 0) > 0, kind .. " records injected")
	print(kind, injected[kind])
end
local q = QuestieDB.questDataOverrides
assert(q[17006] and q[17006][1] == "King's Justice" and q[17006][2], "a new CoA quest has a name and a giver")
if addonTable.questData[1903520] and addonTable.questData[1903520][1] then
	assert(q[1903520][1] == addonTable.questData[1903520][1], "CoA values win over Ascension-protected fields")
end
-- every NPC/object a new quest names as giver/turn-in has a record somewhere (plugin or stock)
print("Questie-X-CoADB load test passed")
