local _, addonTable = ...

-- Helper to merge corrections into the main data tables
-- This ensures that overrides are applied correctly to the split-table format
local function merge(base, overrides)
    if not overrides then return end
    local id, data = next(overrides)
    while id do
        if not base[id] then
            base[id] = data
        else
            local key, value = next(data)
            while key do
                base[id][key] = value
                key, value = next(data, key)
            end
        end
        id, data = next(overrides, id)
    end
end

-- Apply all corrections before exporting to globals
local function applyAllCorrections()
    if not QuestieLoader then return end

    local modules = {
        { name = "QuestieTBCQuestFixes",    target = addonTable.questData,  methods = {"Load", "LoadFactionFixes"} },
        { name = "QuestieTBCNpcFixes",      target = addonTable.npcData,    methods = {"Load", "LoadFactionFixes"} },
        { name = "QuestieTBCItemFixes",     target = addonTable.itemData,   methods = {"Load", "LoadFactionFixes"} },
        { name = "QuestieTBCObjectFixes",   target = addonTable.objectData, methods = {"Load", "LoadFactionFixes"} },
        { name = "QuestieWotlkQuestFixes",  target = addonTable.questData,  methods = {"Load"} },
        { name = "QuestieWotlkNpcFixes",    target = addonTable.npcData,    methods = {"Load", "LoadFactionFixes", "LoadAutomatics"} },
        { name = "QuestieWotlkItemFixes",   target = addonTable.itemData,   methods = {"Load", "LoadFactionFixes"} },
        { name = "QuestieWotlkObjectFixes", target = addonTable.objectData, methods = {"Load", "LoadFactionFixes"} },
    }

    local i = 1
    while modules[i] do
        local modInfo = modules[i]
        local mod = QuestieLoader:ImportModule(modInfo.name)
        if mod then
            local j = 1
            while modInfo.methods[j] do
                local methodName = modInfo.methods[j]
                if mod[methodName] then
                    merge(modInfo.target, mod[methodName](mod))
                end
                j = j + 1
            end
        end
        i = i + 1
    end
end

applyAllCorrections()

_G.QuestieX_WotLKDB_npc = addonTable.npcData
_G.QuestieX_WotLKDB_item = addonTable.itemData
_G.QuestieX_WotLKDB_object = addonTable.objectData
_G.QuestieX_WotLKDB_quest = addonTable.questData

_G.QuestieX_WotLKDB_npcKeys = addonTable.npcKeys
_G.QuestieX_WotLKDB_itemKeys = addonTable.itemKeys
_G.QuestieX_WotLKDB_objectKeys = addonTable.objectKeys
_G.QuestieX_WotLKDB_questKeys = addonTable.questKeys

-- This Loader also registers the plugin.
local function registerAndInject()
    local QuestiePluginAPI = QuestieLoader and QuestieLoader.ImportModule and QuestieLoader:ImportModule("QuestiePluginAPI")
    if not QuestiePluginAPI then
        return false
    end

    local plugin = QuestiePluginAPI:RegisterPlugin("WotLKDB")
    if not plugin then return true end -- Already registered or error

    print("|cFF5EBAF3Questie|r|cFFDAFAFD-X|r [WotLKDB] Plugin registered, injecting data...")

    -- Inject the data into Questie-X
    if addonTable.npcData then plugin:InjectDatabase("NPC", addonTable.npcData) end
    if addonTable.itemData then plugin:InjectDatabase("ITEM", addonTable.itemData) end
    if addonTable.objectData then plugin:InjectDatabase("OBJECT", addonTable.objectData) end
    if addonTable.questData then plugin:InjectDatabase("QUEST", addonTable.questData) end

    -- Inject XP data if available
    if addonTable.xpDB then
        plugin:InjectXpData(addonTable.xpDB)
    end

    print("|cFF5EBAF3Questie|r|cFFDAFAFD-X|r [WotLKDB] Data injection complete.")
    plugin:FinishLoading("WotLKDB")
    return true
end

-- Try registering immediately (in case Questie-X is already loaded)
if not registerAndInject() then
    -- Fallback: Register at PLAYER_LOGIN if QuestieLoader wasn't ready (unlikely due to dependencies)
    local _wotlkDBFrame = CreateFrame("Frame")
    _wotlkDBFrame:RegisterEvent("PLAYER_LOGIN")
    _wotlkDBFrame:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_LOGIN")
        registerAndInject()
    end)
end

