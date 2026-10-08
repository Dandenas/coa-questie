local addonName, addonTable = ...
print("|cFF5EBAF3Questie|r|cFFDAFAFD-X|r [AscensionLoader] Loading...")

local function registerAndInject()
    if not QuestieLoader then
        return false
    end

    ---@type QuestiePluginAPI
    local QuestiePluginAPI = QuestieLoader:ImportModule("QuestiePluginAPI")
    if not QuestiePluginAPI then
        return false
    end

    local realmName = GetRealmName() or ""
    -- Broaden the check to match QuestieServer.lua logic
    local isAscension = (_G.IsAscensionServer or _G.C_CharacterAdvancement) or realmName:find("Ascension") or realmName:find("Area 52") or
                      realmName:find("Al'ar") or realmName:find("Thrall") or realmName:find("Elune") or
                      realmName:find("Bronzebeard") or realmName:find("Rexxar") or realmName:find("Grizzly Hills") or
                      realmName:find("CoA") or realmName:find("Conquest") or realmName:find("Vol")

    if not isAscension then 
        return true -- Not on Ascension, skip but don't retry
    end

    local plugin = QuestiePluginAPI:RegisterPlugin("Ascension")
    if not plugin then return true end -- Already registered or error

    print("|cFF5EBAF3Questie|r|cFFDAFAFD-X|r [AscensionLoader] Plugin registered, injecting data...")

    -- Sunstrider Isle note for future agents:
    -- the Ascension Sunstrider rows should keep their source areaIds intact
    -- (3430 for Eversong Woods, 3431 for Sunstrider Isle). ZoneDB handles the
    -- uiMapId rendering mapping later.

    if addonTable.zoneSort or addonTable.uiMapIdToAreaId then
        plugin:InjectZoneTables(addonTable)
    end

    if addonTable.uiMapData then
        print("[AscensionLoader] Using addonTable.uiMapData")
        plugin:InjectUiMapData(addonTable)
    elseif _G.AscensionUiMapData and _G.AscensionUiMapData.uiMapData then
        print("[AscensionLoader] Using _G.AscensionUiMapData.uiMapData")
        plugin:InjectUiMapData(_G.AscensionUiMapData)
    elseif AscensionUiMapData and AscensionUiMapData.uiMapData then
        print("[AscensionLoader] Using AscensionUiMapData.uiMapData")
        plugin:InjectUiMapData(AscensionUiMapData)
    else
        print("[AscensionLoader] No uiMapData found")
    end

    -- Inject the data into Questie-X
    if addonTable.npcData then
        plugin:InjectDatabase("NPC", addonTable.npcData)
    end
    if addonTable.questData then
        plugin:InjectDatabase("QUEST", addonTable.questData)
    end
    if addonTable.objectData then
        plugin:InjectDatabase("OBJECT", addonTable.objectData)
    end
    if addonTable.itemData then
        plugin:InjectDatabase("ITEM", addonTable.itemData)
    end

    _G.AscensionDB = addonTable

    print("|cFF5EBAF3Questie|r|cFFDAFAFD-X|r [AscensionLoader] Data injection complete.")
    plugin:FinishLoading("Ascension")
    return true
end

-- Defer registration until PLAYER_LOGIN so the database chunks loaded from the
-- TOC have finished populating addonTable.npcData/questData/objectData/itemData.
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    registerAndInject()
end)
