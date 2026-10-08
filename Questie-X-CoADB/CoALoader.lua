-- Questie-X-CoADB: Conquest of Azeroth quests, NPCs, objects and items that differ from Questie-X's stock
-- WotLK data (new quests in full; changed quest givers/turn-ins/levels/names as single fields).
-- Loads only on the Ascension client (CoA runs on it). Injected at PLAYER_LOGIN, after the Ascension plugin.
local _, addonTable = ...

local function inject()
    if not (_G.C_CharacterAdvancement and QuestieLoader) then return end
    local api = QuestieLoader:ImportModule("QuestiePluginAPI")
    if not api then return end
    local plugin = api:RegisterPlugin("CoA")
    if not plugin then return end
    if addonTable.npcData then plugin:InjectDatabase("NPC", addonTable.npcData) end
    if addonTable.objectData then plugin:InjectDatabase("OBJECT", addonTable.objectData) end
    if addonTable.itemData then plugin:InjectDatabase("ITEM", addonTable.itemData) end
    if addonTable.questData then plugin:InjectDatabase("QUEST", addonTable.questData) end
    -- The plugin API lets fields from the Ascension plugin (Ascension's live servers) win over every other
    -- plugin. On a CoA server its own data is the truth, so re-apply ours on top for those records.
    local QuestieDB = QuestieLoader:ImportModule("QuestieDB")
    local function reapply(target, data)
        if type(target) ~= "table" or type(data) ~= "table" then return end
        for id, entry in pairs(data) do
            local existing = target[id]
            if type(existing) == "table" and existing ~= entry then
                for key, value in pairs(entry) do existing[key] = value end
            end
        end
    end
    if QuestieDB then
        reapply(QuestieDB.questDataOverrides, addonTable.questData)
        reapply(QuestieDB.npcDataOverrides, addonTable.npcData)
        reapply(QuestieDB.objectDataOverrides, addonTable.objectData)
        reapply(QuestieDB.itemDataOverrides, addonTable.itemData)
    end
    plugin:FinishLoading("CoA")
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    inject()
end)
