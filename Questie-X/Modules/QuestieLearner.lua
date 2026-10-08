---@class QuestieLearner
local QuestieLearner = QuestieLoader:CreateModule("QuestieLearner")

---@type QuestieDB
local QuestieDB = QuestieLoader:ImportModule("QuestieDB")
---@type QuestieQuest
local QuestieQuest = QuestieLoader:ImportModule("QuestieQuest")
---@type QuestiePlayer
local QuestiePlayer = QuestieLoader:ImportModule("QuestiePlayer")
---@type QuestLogCache
local QuestLogCache = QuestieLoader:ImportModule("QuestLogCache")
---@type l10n
local l10n = QuestieLoader:ImportModule("l10n")
---@type ZoneDB
local ZoneDB = QuestieLoader:ImportModule("ZoneDB")

local _Learner = QuestieLearner.private or {}

local GetDataSourceMode
local DeepCopy
local HasQuestNpcReferences
local HasQuestNpcGiverReferences
local HasQuestObjectGiverReferences

local floor = math.floor
local abs   = math.abs
local time  = time
local tinsert = table.insert
local ipairs = ipairs
local pairs = pairs
local next = next
local type = type
local tostring = tostring
local tonumber = tonumber
local string_trim = string.trim
if not string_trim then
    local whitespace = {
        [" "] = true,
        ["\t"] = true,
        ["\r"] = true,
        ["\n"] = true,
    }
    string_trim = function(text, chars)
        if text == nil then return nil end
        text = tostring(text)
        local trimSet = {}
        if not chars or chars == "" then
            for ch in pairs(whitespace) do
                trimSet[ch] = true
            end
        else
            for i = 1, string.len(chars) do
                trimSet[string.sub(chars, i, i)] = true
            end
        end
        local startPos = 1
        local endPos = string.len(text)
        while startPos <= endPos and trimSet[string.sub(text, startPos, startPos)] do
            startPos = startPos + 1
        end
        while endPos >= startPos and trimSet[string.sub(text, endPos, endPos)] do
            endPos = endPos - 1
        end
        if startPos > endPos then
            return ""
        end
        return string.sub(text, startPos, endPos)
    end
end
local string_sub = string.sub
local string_len = string.len
local string_upper = string.upper
local AceConfigRegistry = LibStub and LibStub("AceConfigRegistry-3.0", true)

local function IsAscensionProtected(dbType, id, key)
    local mode = GetDataSourceMode and GetDataSourceMode() or "auto"
    if mode == "learner" or mode == "none" then
        return false
    end
    local protected = QuestieDB
        and QuestieDB.ascensionOverrideKeys
        and QuestieDB.ascensionOverrideKeys[dbType]
        and QuestieDB.ascensionOverrideKeys[dbType][id]

    return protected and protected[key] == true
end

-- Direct AscensionDB-ownership check that is NOT bypassed in learner/none mode.
-- IsAscensionProtected() returns false in learner mode so the learner can override
-- most fields — but spawn data ([7]) for AscensionDB-curated NPCs (e.g. Sunstrider's
-- Mana Wyrm) must NEVER be overridden by learner coords, which are often in the wrong
-- map/zone space and produce pins in the wrong corner of the map. Use this for the
-- spawn-injection guards so AscensionDB always wins for owned NPCs regardless of mode.
local function AscensionOwnsNpcSpawns(npcId)
    return QuestieDB
        and QuestieDB.ascensionOverrideKeys
        and QuestieDB.ascensionOverrideKeys["NPC"]
        and QuestieDB.ascensionOverrideKeys["NPC"][npcId]
        and QuestieDB.ascensionOverrideKeys["NPC"][npcId][7] == true
end

-- Mode-independent check for AscensionDB-curated OBJECT spawns ([4]).
local function AscensionOwnsObjectSpawns(objectId)
    return QuestieDB
        and QuestieDB.ascensionOverrideKeys
        and QuestieDB.ascensionOverrideKeys["OBJECT"]
        and QuestieDB.ascensionOverrideKeys["OBJECT"][objectId]
        and QuestieDB.ascensionOverrideKeys["OBJECT"][objectId][4] == true
end

local function HasAscensionQuestObjectiveData(questId)
    return IsAscensionProtected("QUEST", questId, 10)
end

local function IsBaseDatabaseMissing()
    return QuestieDB
        and QuestieDB.IsBaseDatabaseMissing
        and QuestieDB:IsBaseDatabaseMissing()
end

local function GetDataSourceMode()
    if IsBaseDatabaseMissing() then
        return "learner"
    end

    local settings = Questie
        and Questie.dbLearner
        and Questie.dbLearner.global
        and Questie.dbLearner.global.settings
    if not settings then
        return "auto"
    end

    local mode = settings.dataSourceMode
    if mode == "auto" or mode == "learner" or mode == "static" or mode == "none" then
        return mode
    end

    if settings.prioritizeMyData == false then
        return "static"
    end

    return "auto"
end

local function WipeTable(tbl)
    if type(tbl) ~= "table" then return end
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end

local function CopyTable(dst, src)
    WipeTable(dst)
    if type(src) ~= "table" then return end
    for key, value in pairs(src) do
        dst[key] = DeepCopy(value)
    end
end

local function NormalizeSpawnZoneKey(zoneKey)
    -- Convert raw area IDs (e.g. 3431 from GetAreaID()) to the canonical map IDs
    -- used by AscensionDB and the rendering system (e.g. 1241 for Sunstrider Isle).
    -- ZoneDB.private.areaIdToUiMapId is the single source of truth for this mapping
    -- (zoneDB.lua: 3431→1241, 3430→1941, 668→1238, etc.).  Using the same table
    -- ensures learner-stored zone keys are always valid for DrawWorldIcon / HBD.
    --
    -- IMPORTANT: Never store raw area IDs (3430, 3431) in spawn data — the pin
    -- rendering pipeline only knows about map IDs (1241, 1941).  Any future zone
    -- additions must be registered in ZoneDB.private.areaIdToUiMapId first.
    if ZoneDB and ZoneDB.private and ZoneDB.private.areaIdToUiMapId then
        local mapped = ZoneDB.private.areaIdToUiMapId[zoneKey]
        if mapped then return mapped end
    end
    return zoneKey
end

local function IsSunstriderNativeZone(zoneKey)
    return zoneKey == 1241 or zoneKey == 3431
end

-- WoW API locals
local UnitExists = UnitExists
local UnitIsVisible = UnitIsVisible
local UnitIsPlayer = UnitIsPlayer
local UnitGUID = QuestieCompat and QuestieCompat.UnitGUID or UnitGUID or function() return nil end
local UnitName = UnitName
local UnitLevel = UnitLevel
local UnitFactionGroup = UnitFactionGroup
local UnitReaction = UnitReaction
local UnitCreatureFamily = UnitCreatureFamily
local UnitCreatureType = UnitCreatureType
local GetRealZoneText = GetRealZoneText
local GetTitleText = GetTitleText
local GetObjectiveText = GetObjectiveText
local GetQuestDescription = GetQuestDescription
local GetRewardText = GetRewardText
local GetQuestID = GetQuestID
local GetNumQuestLogEntries = GetNumQuestLogEntries
local GetItemInfo = GetItemInfo
local CombatLogGetCurrentEventInfo = CombatLogGetCurrentEventInfo
local CreateFrame = CreateFrame
local GetTime = GetTime

-- Cache for zone lookup: zoneText -> areaId
_Learner.zoneCache = {}

-- NPC flags (WoW bitmask)
local NPC_FLAG_GOSSIP          = 0x00000001
local NPC_FLAG_QUESTGIVER      = 0x00000002
local NPC_FLAG_TRAINER         = 0x00000010
local NPC_FLAG_VENDOR          = 0x00000080
local NPC_FLAG_FLIGHTMASTER    = 0x00000200
local NPC_FLAG_INNKEEPER       = 0x00000800
local NPC_FLAG_BANKER          = 0x00001000
local NPC_FLAG_AUCTIONEER      = 0x00004000
local NPC_FLAG_STABLEMASTER    = 0x00010000

-- Only cache/learn mouseover NPCs that carry one of these flags
local MOUSEOVER_LEARN_FLAGS = NPC_FLAG_QUESTGIVER

-- Coordinate grid cell size (in 0–100 map units).
-- ~2 grid units ≈ 2% of zone width — keeps clusters tight without over-splitting.
local COORD_GRID = 2.0

-- Minimum match count (Confidence) for a learned pin to appear on the map.
-- Set to 1 so that even a single kill/mouseover confirms a spawn location on
-- Ascension, where NPC databases are incomplete and every data point matters.
local MIN_CONFIDENCE_PINS = 1

local function GetCoordGridForZone(zoneId)
    -- Sunstrider's starter mobs are packed tightly; a 2% bucket collapses
    -- distinct spawn points such as 58.68/43.19 and 59.11/44.00 into one pin.
    if IsSunstriderNativeZone(zoneId) then
        return 0.5
    end
    return COORD_GRID
end

_Learner.pendingNpcs    = {}
_Learner.pendingQuests  = {}
_Learner.pendingItems   = {}
_Learner.pendingObjects = {}
_Learner.pendingNetworkMerges = {}
_Learner.pendingItemLinks = {} -- queue for async GetItemInfo retries
_Learner.npcNameIndex = nil
_Learner.npcNameIndexDirty = true

-- Direct reference to learnedData, set on Initialize
QuestieLearner.data = nil

------------------------------------------------------------------------
-- Coordinate helpers
------------------------------------------------------------------------

local function GetZoneId()
    -- Prefer the most specific zone available: GetRealZoneText() returns the
    -- sub-zone name when the player is on a child map (e.g. "Sunstrider Isle"
    -- on map 1241 → areaId 3431), and the parent zone name otherwise (e.g.
    -- "Eversong Woods" → areaId 3430). Using the sub-zone is correct because
    -- Questie resolves subzones to parents via GetParentZoneId() automatically.
    local zoneText = GetRealZoneText and GetRealZoneText() or ""
    if zoneText ~= "" then
        local areaId = _Learner.zoneCache[zoneText]
        if not areaId and l10n and l10n.GetAreaIdByLocalName then
            areaId = l10n:GetAreaIdByLocalName(zoneText)
            if areaId and areaId > 0 then
                _Learner.zoneCache[zoneText] = areaId
            end
        end
        if areaId and areaId > 0 then
            return areaId
        end
    end

    -- Fallback: uiMapId-based conversion (e.g. 1241→3431 for Sunstrider).
    local uiMapId = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if uiMapId then
        if ZoneDB and ZoneDB.GetAreaIdByUiMapId then
            local areaId = ZoneDB:GetAreaIdByUiMapId(uiMapId)
            if areaId and areaId > 0 then
                return areaId
            end
        end
        return uiMapId  -- fallback: no ZoneDB mapping available
    end
    -- Lua 5.0 compat: replace select(8, GetInstanceInfo()) with explicit GetInstanceInfo unpack
    local _, _, _, _, _, _, _, instanceMapID = GetInstanceInfo()
    return instanceMapID or 0
end

local function GetPlayerCoords()
    -- Use the robust position helper (handles SetMapToCurrentZone and the Sunstrider
    -- parent/child coordinate-space correction) rather than the raw GetPlayerMapPosition,
    -- which returns 0,0 whenever the world map isn't set to the player's zone. Returns nil
    -- when no valid position is available so callers that record the player's location as a
    -- spawn (mouseover quest-givers, object use) simply skip rather than logging a 0,0 pin.
    local _mapId, x, y = QuestieCompat.GetCurrentPlayerPosition()
    if x and y and x > 0 and y > 0 then
        -- Native APIs return 0–1; store in 0–100 scale, 2-decimal precision.
        return floor(x * 10000) / 100, floor(y * 10000) / 100
    end
    return nil, nil
end

local function NormalizeCoordValue(value)
    local coord = tonumber(value)
    if not coord or coord <= 0 then return nil end

    -- Native map APIs return 0-1, Questie stores 0-100, and a previous
    -- learner path accidentally persisted 0-10000 values like 5868.
    if coord <= 1 then
        coord = coord * 100
    elseif coord > 100 then
        coord = coord / 100
    end

    if coord <= 0 or coord > 100 then return nil end
    return floor(coord * 100 + 0.5) / 100
end

local function NormalizeCoordPair(x, y)
    local nx = NormalizeCoordValue(x)
    local ny = NormalizeCoordValue(y)
    if not nx or not ny then return nil, nil end
    return nx, ny
end

local function CopyWithoutField(data, skippedKey)
    local copy = {}
    for key, value in pairs(data) do
        if key ~= skippedKey then
            copy[key] = value
        end
    end
    return copy
end

local function DeepCopy(value)
    if type(value) ~= "table" then return value end

    local copy = {}
    for key, child in pairs(value) do
        copy[key] = DeepCopy(child)
    end
    return copy
end

local function CaptureStaticOverrideSnapshot()
    if _Learner.staticOverrideSnapshot then
        return
    end

    _Learner.staticOverrideSnapshot = {
        npcs    = DeepCopy(QuestieDB.npcDataOverrides or {}),
        quests  = DeepCopy(QuestieDB.questDataOverrides or {}),
        items   = DeepCopy(QuestieDB.itemDataOverrides or {}),
        objects = DeepCopy(QuestieDB.objectDataOverrides or {}),
    }
end

local function RestoreStaticOverridesForMode()
    local snapshot = _Learner.staticOverrideSnapshot
    local mode = GetDataSourceMode()

    if mode == "learner" or mode == "none" then
        WipeTable(QuestieDB.npcDataOverrides)
        WipeTable(QuestieDB.questDataOverrides)
        WipeTable(QuestieDB.itemDataOverrides)
        WipeTable(QuestieDB.objectDataOverrides)
        return
    end

    if not snapshot then return end

    CopyTable(QuestieDB.npcDataOverrides, snapshot.npcs)
    CopyTable(QuestieDB.questDataOverrides, snapshot.quests)
    CopyTable(QuestieDB.itemDataOverrides, snapshot.items)
    CopyTable(QuestieDB.objectDataOverrides, snapshot.objects)
end

-- Returns the grid-bucket key for a coordinate so nearby points share the same slot
local function CoordBucket(x, y)
    return floor(x / COORD_GRID) * COORD_GRID, floor(y / COORD_GRID) * COORD_GRID
end

-- Inserts {x, y} into coordList only when no existing point falls in the same grid bucket.
-- If a point already exists in that bucket, gently heal it toward the new evidence
-- using a weighted average so repeated kills converge instead of duplicating pins.
local function InsertIfNewBucket(coordList, x, y, customGrid)
    x, y = NormalizeCoordPair(x, y)
    if not x or not y then return false end

    local grid = customGrid or COORD_GRID
    local bx, by = floor(x / grid) * grid, floor(y / grid) * grid
    for _, coord in ipairs(coordList) do
        local existingX, existingY = NormalizeCoordPair(coord[1], coord[2])
        if existingX and existingY then
            coord[1], coord[2] = existingX, existingY
        end
        local cx, cy = floor((existingX or coord[1]) / grid) * grid, floor((existingY or coord[2]) / grid) * grid
        if cx == bx and cy == by then
            local count = tonumber(coord[3]) or 1
            local healedCount = count + 1
            local healedX = ((existingX or coord[1]) * count + x) / healedCount
            local healedY = ((existingY or coord[2]) * count + y) / healedCount
            coord[1], coord[2] = NormalizeCoordPair(healedX, healedY)
            coord[3] = healedCount
            return false
        end
    end
    table.insert(coordList, {x, y, 1})
    return true
end

local function CountUniqueSpawnPositions(spawns)
    if type(spawns) ~= "table" then return 0 end

    local seen = {}
    local count = 0
    for _, coords in pairs(spawns) do
        if type(coords) == "table" then
            for _, coord in ipairs(coords) do
                local x, y = NormalizeCoordPair(coord[1], coord[2])
                if x and y then
                    local key = tostring(x) .. "," .. tostring(y)
                    if not seen[key] then
                        seen[key] = true
                        count = count + 1
                    end
                end
            end
        end
    end

    return count
end

-- Detects if the current map is a "Micro-Dungeon" (small interior map)
-- This is a heuristic: if we lack map data, we default to standard grid.
local function GetCustomGridPrecision()
    local uiMapId = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not uiMapId then return COORD_GRID end

    -- Known micro-dungeons or small interior maps where 2% precision is too coarse.
    -- (e.g., Northshire Abbey, Anvilmar, Crypts, etc.)
    -- For now, we use a simple list of common starting sub-zones if available.
    -- Or we could check map bounds if we had that data.
    local microDungeons = {
        [425] = 0.5, -- Northshire Abbey
        [468] = 0.5, -- Anvilmar
        [469] = 0.5, -- Coldridge Valley (Interior)
        -- Add more as needed
    }
    return microDungeons[uiMapId] or COORD_GRID
end

------------------------------------------------------------------------
-- Internal state guards
------------------------------------------------------------------------

local function EnsureLearnedData()
    if not Questie.db or not Questie.dbLearner then return false end

    -- Migration: If data exists in the old QuestieConfig.global.learnedData, move it to the new QuestieLearnerDB.global
    if Questie.db.global.learnedData then
        Questie:Debug(Questie.DEBUG_INFO, "[QuestieLearner] Migrating learnedData to separate SavedVariable...")
        for k, v in pairs(Questie.db.global.learnedData) do
            Questie.dbLearner.global[k] = v
        end
        Questie.db.global.learnedData = nil
        Questie:Print("|cFF5EBAF3Questie-X:|r Learned data has been migrated to a separate SavedVariable for better performance.")
    end

    local ld = Questie.dbLearner.global
    if (not ld.npcs) and (not ld.quests) then
        ld.npcs    = {}
        ld.quests  = {}
        ld.items   = {}
        ld.objects = {}
        ld.settings = {
            enabled      = true,
            learnNpcs    = true,
            learnQuests  = true,
            learnItems   = true,
            learnObjects = true,
            minConfidencePins = 1,
            spawnDedupRadius = 4.0,
            prioritizeMyData = true,
            dataSourceMode   = "auto",
            staleThreshold   = 90,    -- days
            pruneVerified    = false, -- protect verified data by default
            performanceMode  = "balanced",
            pinRefreshDelay  = 0.75,
            pinRefreshMode   = "batched",
            pinRefreshMaxWait = 5.0,
            liveNpcUpdateDelay = 0.75,
            learnerCommsIntensity = "normal",
        }
    else
        -- Backfill sub-tables that may be missing from older SavedVariables
        ld.npcs    = ld.npcs    or {}
        ld.quests  = ld.quests  or {}
        ld.items   = ld.items   or {}
        ld.objects = ld.objects or {}
        ld.settings = ld.settings or {}
        local s = ld.settings
        if s.enabled      == nil then s.enabled      = true end
        if s.learnNpcs    == nil then s.learnNpcs    = true end
        if s.learnQuests  == nil then s.learnQuests  = true end
        if s.learnItems   == nil then s.learnItems   = true end
        if s.learnObjects == nil then s.learnObjects = true end
        if s.minConfidencePins == nil then s.minConfidencePins = 1 end
        if s.spawnDedupRadius == nil then s.spawnDedupRadius = 4.0 end
        if s.prioritizeMyData == nil then s.prioritizeMyData = true end
        if s.dataSourceMode == nil then
            if s.prioritizeMyData == false then
                s.dataSourceMode = "static"
            else
                s.dataSourceMode = "auto"
            end
        end
        if s.dataSourceMode == "static" or s.dataSourceMode == "none" then
            s.prioritizeMyData = false
        else
            s.prioritizeMyData = true
        end
        if s.staleThreshold == nil then
            s.staleThreshold = 90
        end
        if s.pruneVerified == nil then
            s.pruneVerified = false
        end
        if s.performanceMode == nil then
            s.performanceMode = "balanced"
        end
        if s.pinRefreshDelay == nil then
            s.pinRefreshDelay = 0.75
        end
        if s.pinRefreshMode == nil then
            s.pinRefreshMode = "batched"
        end
        if s.pinRefreshMaxWait == nil then
            s.pinRefreshMaxWait = 5.0
        end
        if s.liveNpcUpdateDelay == nil then
            s.liveNpcUpdateDelay = 0.75
        end
        if s.learnerCommsIntensity == nil then
            s.learnerCommsIntensity = "normal"
        end
    end
    return true
end

------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------

function QuestieLearner:IsEnabled()
    if not EnsureLearnedData() then return false end
    if IsBaseDatabaseMissing() then
        return true
    end
    return Questie.dbLearner.global.settings.enabled
end

local function NotifyLearnerOptionsChanged()
    if AceConfigRegistry and AceConfigRegistry.NotifyChange then
        AceConfigRegistry:NotifyChange("Questie")
    end
end

function QuestieLearner:GetSettings()
    if not EnsureLearnedData() then return {} end
    return Questie.dbLearner.global.settings
end

function QuestieLearner:GetDataSourceMode()
    if not EnsureLearnedData() then return "auto" end
    return GetDataSourceMode()
end

function QuestieLearner:IsLearnerLiveEnabled()
    local mode = self:GetDataSourceMode()
    return mode == "auto" or mode == "learner"
end

function QuestieLearner:CanShowLearnerTooltips()
    if not EnsureLearnedData() then return false end
    local mode = self:GetDataSourceMode()
    return mode == "auto" or mode == "learner"
end

function QuestieLearner:ApplyDataSourceMode()
    if not EnsureLearnedData() then return end
    local settings = Questie.dbLearner and Questie.dbLearner.global and Questie.dbLearner.global.settings
    if settings and GetDataSourceMode() == "learner" and settings.enabled == false then
        settings.enabled = true
    end
    CaptureStaticOverrideSnapshot()
    RestoreStaticOverridesForMode()
    self:InjectLearnedData()
    -- Rebuild every per-entity cache (including the per-zone quest cache) so the
    -- mode switch takes effect immediately for reads, pins, and zone lookups.
    if QuestieDB and QuestieDB.ClearModeCaches then
        QuestieDB:ClearModeCaches()
    elseif QuestieDB and QuestieDB.private then
        QuestieDB.private.questCache = {}
        QuestieDB.private.itemCache = {}
        QuestieDB.private.npcCache = {}
        QuestieDB.private.objectCache = {}
        QuestieDB.private.zoneCache = {}
    end
    QuestieLearner.data = Questie.dbLearner.global
end

function QuestieLearner:RefreshLiveState()
    if not EnsureLearnedData() then return end

    self:ApplyDataSourceMode()

    -- Re-evaluate any pending learner-driven redraws immediately so option
    -- changes (confidence, dedup, batching, and mode switches) take effect in
    -- the active session instead of waiting for stale timers to expire.
    if _Learner.pendingNpcLiveUpdates and next(_Learner.pendingNpcLiveUpdates) then
        _FlushNpcLiveUpdates()
    end
    if _pendingQuestPinRefreshes and next(_pendingQuestPinRefreshes) then
        _FlushActiveQuestPins()
    end

    if QuestieQuest and QuestieQuest.SmoothReset then
        QuestieQuest:SmoothReset()
    elseif QuestieTracker and QuestieTracker.Update then
        QuestieTracker:Update()
    end
end

local function GetLearnerSetting(key, defaultValue)
    if Questie and Questie.dbLearner and Questie.dbLearner.global and Questie.dbLearner.global.settings then
        local value = Questie.dbLearner.global.settings[key]
        if value ~= nil then
            return value
        end
    end
    return defaultValue
end

------------------------------------------------------------------------
-- Cross-link engine
-- After ANY entity is learned, scan all other learned data and stitch
-- relationships automatically. Both learnedData (SavedVariables) and
-- live *DataOverrides tables are kept in sync.
--
-- Schema reference:
--  NPC    [7]=spawns  [10]=questStarts  [11]=questEnds
--  Object [2]=questStarts  [3]=questEnds  [4]=spawns
--  Quest  [2]=startedBy{[1]=npcIds,[2]=objIds,[3]=itemIds}
--         [3]=finishedBy{[1]=npcIds,[2]=objIds}
--         [10]=objectives{[1]={{npcId,text},...},[2]={{objId,text},...},[3]={{itemId,text},...}}
--         [11]=sourceItemId  [17]=zoneOrSort
--  Item   [2]=dropNpcs{npcId,...}  [9]=questSource (questId that gives this item)
------------------------------------------------------------------------

-- Add value to array tbl[key] if not already present. Mirrors to live override table.
local function _AddToArray(tbl, key, value, ovrTable, ovrId)
    if not tbl then return end
    tbl[key] = tbl[key] or {}
    for _, v in ipairs(tbl[key]) do if v == value then return end end
    table.insert(tbl[key], value)
    if ovrTable and ovrId then
        local ovr = ovrTable[ovrId] or {}
        ovrTable[ovrId] = ovr
        ovr[key] = ovr[key] or {}
        for _, v in ipairs(ovr[key]) do if v == value then return end end
        table.insert(ovr[key], value)
    end
end

-- Add value to nested array tbl[outerKey][innerKey] if not already present.
local function _AddToNestedArray(tbl, outerKey, innerKey, value, ovrTable, ovrId)
    if not tbl then return end
    tbl[outerKey] = tbl[outerKey] or {}
    tbl[outerKey][innerKey] = tbl[outerKey][innerKey] or {}
    for _, v in ipairs(tbl[outerKey][innerKey]) do if v == value then return end end
    table.insert(tbl[outerKey][innerKey], value)
    if ovrTable and ovrId then
        local ovr = ovrTable[ovrId] or {}
        ovrTable[ovrId] = ovr
        ovr[outerKey] = ovr[outerKey] or {}
        ovr[outerKey][innerKey] = ovr[outerKey][innerKey] or {}
        for _, v in ipairs(ovr[outerKey][innerKey]) do if v == value then return end end
        table.insert(ovr[outerKey][innerKey], value)
    end
end

-- Add {id, text} pair to quest objectives slot (quest[10][slot]).
local function _AddToQuestObjective(qData, slot, entityId, text, ovrTable, questId)
    if not qData then return end
    qData[10] = qData[10] or {}
    qData[10][slot] = qData[10][slot] or {}
    for _, entry in ipairs(qData[10][slot]) do if entry[1] == entityId then return end end
    table.insert(qData[10][slot], { entityId, text or "" })
    if ovrTable and questId then
        local ovr = ovrTable[questId] or {}
        ovrTable[questId] = ovr
        ovr[10] = ovr[10] or {}
        ovr[10][slot] = ovr[10][slot] or {}
        for _, entry in ipairs(ovr[10][slot]) do if entry[1] == entityId then return end end
        table.insert(ovr[10][slot], { entityId, text or "" })
    end
end

local function _GetDB() return Questie.dbLearner.global end

-- Triggers QuestieQuest:UpdateQuest for every active quest in the player's log
-- that is referenced in the provided set (table with questId keys).
-- Called after cross-linking so map pins refresh immediately.
local _pendingQuestPinRefreshes = {}
local _pendingQuestPinRefreshTimer = nil
local _pendingQuestPinFirstDirty = nil      -- GetTime() of first pending change since last flush
local _pendingQuestPinLastActivity = nil    -- GetTime() of most recent queued change
local _pendingQuestFrameUnloads = {}

-- Trailing-debounce gate. When new learner activity keeps arriving, the flush is
-- pushed out by pinRefreshDelay (the "quiet window") so a fast kill streak — or a
-- crowd of nearby players — does not redraw pins every window. pinRefreshMaxWait
-- caps the worst-case latency: once that many seconds have elapsed since the first
-- pending change, the flush fires even if kills are still coming (0 = pure debounce,
-- never force). Only "batched" mode debounces; "immediate" flushes on first fire.
-- Performs the actual pin rebuild for every pending quest. No debounce gate — the
-- caller is responsible for deciding when to fire (either the trailing-debounce
-- wrapper below, or an immediate flush from the already-debounced NPC live-update
-- flush, which makes the redundant second debounce stage unnecessary).
local function _DoFlushActiveQuestPins()
    local questIdSet = _pendingQuestPinRefreshes
    _pendingQuestPinRefreshes = {}
    _pendingQuestPinRefreshTimer = nil
    _pendingQuestPinFirstDirty = nil
    _pendingQuestPinLastActivity = nil

    if not next(questIdSet) then return end
    if GetLearnerSetting("pinRefreshMode", "batched") == "manual" then
        _pendingQuestFrameUnloads = {}
        return
    end
    if not QuestieQuest or not QuestieQuest.UpdateQuest then return end
    if not QuestiePlayer or not QuestiePlayer.currentQuestlog then return end

    for questId in pairs(questIdSet) do
        if QuestiePlayer.currentQuestlog[questId] then
            if QuestieMap and QuestieMap.UnloadQuestFrames and _pendingQuestFrameUnloads[questId] then
                QuestieMap:UnloadQuestFrames(questId)
            end
            QuestieQuest:UpdateQuest(questId)
        end
    end
    _pendingQuestFrameUnloads = {}
end

local function _FlushActiveQuestPins()
    -- Only defer while there is genuine pending activity. If the timestamps were
    -- already cleared (e.g. the NPC live-update flush force-flushed the pins via
    -- _DoFlushActiveQuestPins), a leftover timer must NOT treat the nil timestamp
    -- as "now" and re-arm forever — it should fall through and flush (a no-op when
    -- the pending set is empty).
    if GetTime and GetLearnerSetting("pinRefreshMode", "batched") == "batched"
            and _pendingQuestPinLastActivity then
        local timer = (C_Timer) or (QuestieCompat and QuestieCompat.C_Timer)
        local now = GetTime()
        local delay = GetLearnerSetting("pinRefreshDelay", 0.75)
        local maxWait = GetLearnerSetting("pinRefreshMaxWait", 5.0)
        local quiet = now - _pendingQuestPinLastActivity
        local waited = now - (_pendingQuestPinFirstDirty or _pendingQuestPinLastActivity)
        if timer and timer.After and quiet < delay and (maxWait <= 0 or waited < maxWait) then
            local remaining = delay - quiet
            if maxWait > 0 then
                local capRemaining = maxWait - waited
                if capRemaining < remaining then remaining = capRemaining end
            end
            if remaining < 0 then remaining = 0 end
            -- _pendingQuestPinRefreshTimer stays true so concurrent queues don't double-arm.
            timer.After(remaining, _FlushActiveQuestPins)
            return
        end
    end

    _DoFlushActiveQuestPins()
end

-- When true, _RefreshActiveQuestPins only accumulates pending quests and does NOT
-- arm its own trailing-debounce timer. Set by _FlushNpcLiveUpdates, which already
-- debounced via liveNpcUpdateDelay and force-flushes the pins itself afterwards —
-- so the second debounce stage would only add redundant latency.
local _deferPinRefreshScheduling = false

local function _RefreshActiveQuestPins(questIdSet)
    -- Skip scheduling when the set is empty (avoids no-op timer callbacks)
    if not next(questIdSet) then return end
    if GetLearnerSetting("pinRefreshMode", "batched") == "manual" then
        for questId in pairs(questIdSet) do
            _pendingQuestFrameUnloads[questId] = nil
        end
        return
    end
    for questId in pairs(questIdSet) do
        _pendingQuestPinRefreshes[questId] = true
    end

    -- Record activity so the debounce gate in _FlushActiveQuestPins can re-arm.
    local now = (GetTime and GetTime()) or 0
    _pendingQuestPinLastActivity = now
    if not _pendingQuestPinFirstDirty then
        _pendingQuestPinFirstDirty = now
    end

    -- Caller (NPC live-update flush) will force-flush; don't arm a redundant timer.
    if _deferPinRefreshScheduling then
        return
    end

    if _pendingQuestPinRefreshTimer then
        return
    end

    local timer = (C_Timer) or (QuestieCompat and QuestieCompat.C_Timer)
    if timer and timer.After then
        _pendingQuestPinRefreshTimer = true
        timer.After(GetLearnerSetting("pinRefreshDelay", 0.75), _FlushActiveQuestPins)
    else
        _FlushActiveQuestPins()
    end
end

-- Invalidates cached objective.spawnList for any active quest whose objectives
-- reference the given npcId. Unloads existing world/minimap icons, resets
-- tooltip registration, and forces the map system to rebuild spawn lists from
-- QuestieDB on the next update — picking up newly learned coordinates in real time.
-- Helper: check if a single objective references the given npcId and, if so,
-- unload its icons and reset its cached spawnList so the map rebuilds it.
-- Returns true if the objective was invalidated.
local function _TryInvalidateObjective(objective, npcId, quest)
    local shouldInvalidate = false
    -- Monster objectives reference NPCs directly in spawnList keys
    if objective.spawnList then
        if objective.spawnList[npcId] then
            shouldInvalidate = true
        end
        -- Also check killcredit IdList
        if not shouldInvalidate and objective.IdList then
            for _, id in ipairs(objective.IdList) do
                if id == npcId then shouldInvalidate = true; break end
            end
        end
    else
        -- spawnList is nil (first-ever encounter, never populated).
        -- Check the quest's ObjectiveData for NPC references so killcredit
        -- and item objectives are still invalidated on the first kill.
        if quest and quest.ObjectiveData and objective.Index then
            local objData = quest.ObjectiveData[objective.Index]
            if objData and objData.IdList then
                for _, id in ipairs(objData.IdList) do
                    if id == npcId then shouldInvalidate = true; break end
                end
            end
            -- Also match the primary objective Id (e.g. single-target monster objectives)
            if not shouldInvalidate and objData and objData.Id == npcId then
                shouldInvalidate = true
            end
        end
    end
    -- Fallback: if objective Id matches the NPC (some objectives use NPC as their primary Id)
    if not shouldInvalidate and objective.Id == npcId then
        shouldInvalidate = true
    end
    if shouldInvalidate then
        -- Unload existing icons manually so frames are removed from map/minimap.
        -- We can't call QuestieQuest's local _UnloadAlreadySpawnedIcons from here,
        -- so we iterate the refs directly.
        if objective.AlreadySpawned then
            for _, spawn in pairs(objective.AlreadySpawned) do
                if spawn then
                    if spawn.mapRefs then
                        for _, mapIcon in ipairs(spawn.mapRefs) do
                            if mapIcon and mapIcon.Unload then mapIcon:Unload() end
                        end
                    end
                    if spawn.minimapRefs then
                        for _, minimapIcon in ipairs(spawn.minimapRefs) do
                            if minimapIcon and minimapIcon.Unload then minimapIcon:Unload() end
                        end
                    end
                end
            end
        end
        objective.spawnList = nil
        objective.AlreadySpawned = {}  -- empty table, NOT nil (_DetermineIconsToDraw indexes this)
        objective.hasRegisteredTooltips = false
        objective.registeredItemTooltips = false
    end
    return shouldInvalidate
end

------------------------------------------------------------------------
-- Debounce table: tracks pending (npcId, questId) invalidate pairs.
-- Prevents scheduling multiple unload+refresh cycles for the same
-- (npcId, questId) within the debounce window.
local _invalidateDebounce = {}

local function _InvalidateSpawnListsForNPC(npcId)
    if not QuestieQuest or not QuestiePlayer or not QuestiePlayer.currentQuestlog then return end
    local timer = (C_Timer) or (QuestieCompat and QuestieCompat.C_Timer)
    local now = (GetTime and GetTime()) or 0
    local debounceWindow = 0.5  -- seconds; coalesces rapid-fire calls

    local questsToRefresh = {}
    for questId, _ in pairs(QuestiePlayer.currentQuestlog) do
        local quest = QuestieDB.GetQuest and QuestieDB.GetQuest(questId)
        if quest then
            local needsUnload = false
            -- Scan standard Objectives
            if quest.Objectives then
                for _, objective in pairs(quest.Objectives) do
                    if _TryInvalidateObjective(objective, npcId, quest) then
                        needsUnload = true
                    end
                end
            end
            -- Scan SpecialObjectives (demonic runestones, custom Ascension objectives, etc.)
            if quest.SpecialObjectives then
                for _, objective in pairs(quest.SpecialObjectives) do
                    if _TryInvalidateObjective(objective, npcId, quest) then
                        needsUnload = true
                    end
                end
            end
            if needsUnload then
                -- Debounce frame unload only. The spawnList is always cleared by
                -- _TryInvalidateObjective (runs before this), so a debounced second call
                -- clears an already-nil spawnList safely. The refresh, however, must always
                -- fire so the map is eventually rebuilt with the latest npcDataOverrides
                -- data (already written by LearnNPC before this call).
                local debounceKey = npcId .. ":" .. questId
                local suppressUnload = _invalidateDebounce[debounceKey]
                    and (now - _invalidateDebounce[debounceKey]) < debounceWindow
                if not suppressUnload then
                    _invalidateDebounce[debounceKey] = now
                    if GetLearnerSetting("pinRefreshMode", "batched") == "immediate" and QuestieMap and QuestieMap.UnloadQuestFrames then
                        QuestieMap:UnloadQuestFrames(questId)
                    else
                        _pendingQuestFrameUnloads[questId] = true
                    end
                end
                questsToRefresh[questId] = true  -- always refresh when data changed
            end
        end
    end
    -- _RefreshActiveQuestPins guards against empty set internally
    _RefreshActiveQuestPins(questsToRefresh)

    -- Prune stale debounce keys (>2x window age) to prevent unbounded growth.
    -- Keys expire naturally after their window; this is just cleanup.
    if timer then
        for key, ts in pairs(_invalidateDebounce) do
            if (now - ts) > (debounceWindow * 2) then
                _invalidateDebounce[key] = nil
            end
        end
    end
end

------------------------------------------------------------------------
-- Live learner update batching
--
-- Kill/loot bursts can call LearnNPC multiple times for the same NPC:
-- combat-log kill, quest-log objective progress, and loot correlation may all
-- arrive within a few frames. Saved learner evidence is updated immediately,
-- but live QuestieDB override/cache invalidation is batched so the large DB
-- layer is not churned on every single kill.

local function _ApplyNpcLiveUpdate(npcId)
    local existing = Questie.dbLearner
        and Questie.dbLearner.global
        and Questie.dbLearner.global.npcs
        and Questie.dbLearner.global.npcs[npcId]
    if not existing then return false end

    local threshold = (Questie.dbLearner.global.settings and Questie.dbLearner.global.settings.minConfidencePins) or MIN_CONFIDENCE_PINS
    if existing.mc < threshold then return false end
    if not (QuestieDB and QuestieDB.npcDataOverrides and existing[7] and next(existing[7])) then return false end

    local ovr = QuestieDB.npcDataOverrides[npcId]
    local allowQuestGiverSpawns = HasQuestNpcGiverReferences and HasQuestNpcGiverReferences(npcId)
    if not ovr then
        -- Learner mode: IsAscensionProtected returns false, so learner data
        -- (including spawns) is used exclusively. Auto/static modes: strip
        -- learner spawns for AscensionDB-curated NPCs unless the learner
        -- explicitly tied this entity to a starter/finisher arrow.
        if IsAscensionProtected("NPC", npcId, 7) and not allowQuestGiverSpawns then
            QuestieDB.npcDataOverrides[npcId] = DeepCopy(CopyWithoutField(existing, 7))
        else
            QuestieDB.npcDataOverrides[npcId] = DeepCopy(existing)
        end
    else
        -- Merge non-spawn fields. IsAscensionProtected is mode-dependent:
        -- returns false in learner mode (learner fills all gaps), true in
        -- auto/static (curated fields are protected).
        for k, v in pairs(existing) do
            if k ~= 7 and not IsAscensionProtected("NPC", npcId, k) and (ovr[k] == nil or (k == 1 and ovr[k] == "")) then
                ovr[k] = DeepCopy(v)
            end
        end
        -- Merge spawn coords. allowSpawnMerge bypass removed — it was
        -- the original hole letting learner coords leak into curated spawns.
        if existing[7] and (allowQuestGiverSpawns or not IsAscensionProtected("NPC", npcId, 7)) then
            ovr[7] = ovr[7] or {}
            for zid, coords in pairs(existing[7]) do
                ovr[7][zid] = ovr[7][zid] or {}
                for _, coord in ipairs(coords) do
                    InsertIfNewBucket(ovr[7][zid], coord[1], coord[2], GetCoordGridForZone(zid))
                end
            end
        end
    end

    -- Clear the compiled DB cache once per flush so GetNPC rebuilds with the
    -- latest coalesced override data instead of once per kill.
    if QuestieDB.private and QuestieDB.private.npcCache then
        QuestieDB.private.npcCache[npcId] = nil
    end

    return true
end

-- Trailing-debounce gate, mirroring _FlushActiveQuestPins. liveNpcUpdateDelay is
-- the quiet window; pinRefreshMaxWait is the shared worst-case cap (0 = never force).
local function _FlushNpcLiveUpdates()
    local timer = QuestieCompat and QuestieCompat.C_Timer
    local now = (GetTime and GetTime()) or 0
    local delay = GetLearnerSetting("liveNpcUpdateDelay", 0.75)
    local maxWait = GetLearnerSetting("pinRefreshMaxWait", 5.0)
    local quiet = now - (_Learner.pendingNpcLiveUpdateLastActivity or now)
    local waited = now - (_Learner.pendingNpcLiveUpdateFirstDirty or now)
    if GetTime and timer and timer.After and quiet < delay and (maxWait <= 0 or waited < maxWait) then
        local remaining = delay - quiet
        if maxWait > 0 then
            local capRemaining = maxWait - waited
            if capRemaining < remaining then remaining = capRemaining end
        end
        if remaining < 0 then remaining = 0 end
        -- pendingNpcLiveUpdateTimer stays true so concurrent queues don't double-arm.
        timer.After(remaining, _FlushNpcLiveUpdates)
        return
    end

    local pending = _Learner.pendingNpcLiveUpdates
    _Learner.pendingNpcLiveUpdates = {}
    _Learner.pendingNpcLiveUpdateTimer = nil
    _Learner.pendingNpcLiveUpdateFirstDirty = nil
    _Learner.pendingNpcLiveUpdateLastActivity = nil

    -- This flush already coalesced kills over liveNpcUpdateDelay. Suppress the
    -- per-NPC pin-refresh debounce while invalidating, then flush all affected
    -- quests once, immediately — instead of waiting out a second pinRefreshDelay.
    _deferPinRefreshScheduling = true
    for npcId in pairs(pending) do
        if _ApplyNpcLiveUpdate(npcId) then
            _InvalidateSpawnListsForNPC(npcId)
        end
    end
    _deferPinRefreshScheduling = false
    _DoFlushActiveQuestPins()
end

local function _QueueNpcLiveUpdate(npcId)
    if not (QuestieLearner and QuestieLearner.IsLearnerLiveEnabled and QuestieLearner:IsLearnerLiveEnabled()) then
        return
    end
    _Learner.pendingNpcLiveUpdates = _Learner.pendingNpcLiveUpdates or {}
    _Learner.pendingNpcLiveUpdates[npcId] = true

    -- Record activity so the debounce gate in _FlushNpcLiveUpdates can re-arm.
    local now = (GetTime and GetTime()) or 0
    _Learner.pendingNpcLiveUpdateLastActivity = now
    if not _Learner.pendingNpcLiveUpdateFirstDirty then
        _Learner.pendingNpcLiveUpdateFirstDirty = now
    end

    if _Learner.pendingNpcLiveUpdateTimer then return end

    local timer = QuestieCompat and QuestieCompat.C_Timer
    if timer and timer.After then
        _Learner.pendingNpcLiveUpdateTimer = true
        timer.After(GetLearnerSetting("liveNpcUpdateDelay", 0.75), _FlushNpcLiveUpdates)
    else
        _FlushNpcLiveUpdates()
    end
end

local function _MarkNpcNameIndexDirty()
    _Learner.npcNameIndexDirty = true
end

local function _RebuildNpcNameIndex()
    local overrideIndex = {}
    local baseIndex = {}

    if QuestieDB and QuestieDB.npcDataOverrides then
        for npcId, data in pairs(QuestieDB.npcDataOverrides) do
            local name = data and data[1]
            if type(name) == "string" and name ~= "" then
                overrideIndex[string.lower(name)] = npcId
            end
        end
    end

    if QuestieDB and QuestieDB.npcData then
        for npcId, data in pairs(QuestieDB.npcData) do
            local name = data and data[1]
            if type(name) == "string" and name ~= "" then
                local lowerName = string.lower(name)
                if overrideIndex[lowerName] == nil and baseIndex[lowerName] == nil then
                    baseIndex[lowerName] = npcId
                end
            end
        end
    end

    _Learner.npcNameIndex = {
        override = overrideIndex,
        base = baseIndex,
    }
    _Learner.npcNameIndexDirty = false
end

local function _EnsureNpcNameIndex()
    if _Learner.npcNameIndex and not _Learner.npcNameIndexDirty then
        return _Learner.npcNameIndex
    end

    _RebuildNpcNameIndex()
    return _Learner.npcNameIndex
end

------------------------------------------------------------------------
-- CrossLinkAfterNPC: called when a new NPC is first learned.
-- Scans all learned quests for any reference to this npcId and stitches
-- back-links in both directions.
local function CrossLinkAfterNPC(npcId)
    local learned = _GetDB()
    local npcData = learned.npcs[npcId]
    if not npcData then return end
    local liveEnabled = QuestieLearner and QuestieLearner.IsLearnerLiveEnabled and QuestieLearner:IsLearnerLiveEnabled()
    local npcOvr = liveEnabled and QuestieDB and QuestieDB.npcDataOverrides or nil

    for questId, qData in pairs(learned.quests) do
        local qOvr = liveEnabled and QuestieDB and QuestieDB.questDataOverrides or nil

        -- Quest starters: quest[2][1] lists NPCs that start this quest
        if qData[2] and qData[2][1] then
            for _, id in ipairs(qData[2][1]) do
                if id == npcId then
                    _AddToArray(npcData, 10, questId, npcOvr, npcId)
                    break
                end
            end
        end
        -- Quest finishers: quest[3][1]
        if qData[3] and qData[3][1] then
            for _, id in ipairs(qData[3][1]) do
                if id == npcId then
                    _AddToArray(npcData, 11, questId, npcOvr, npcId)
                    break
                end
            end
        end
        -- Creature objectives: quest[10][1] — this NPC is a kill target
        -- (no back-link needed; NPC spawn data already linked via spawns[7])

        -- Item objective drop chain: quest[10][3] lists items; if any item's
        -- drop list (item[2]) includes this NPC, mark NPC as creature source.
        if qData[10] and qData[10][3] then
            for _, entry in ipairs(qData[10][3]) do
                local itemId = entry[1]
                local iData = learned.items[itemId]
                if iData and iData[2] then
                    for _, dropNpc in ipairs(iData[2]) do
                        if dropNpc == npcId then
                            -- NPC drops a quest objective item → add as creature objective
                            _AddToQuestObjective(qData, 1, npcId, nil, qOvr, questId)
                            break
                        end
                    end
                end
            end
        end
    end

    -- Refresh map pins for any active quests now linked to this NPC
    local activeRefs = {}
    if learned.quests then
        for questId, qData in pairs(learned.quests) do
            local refs = (qData[2] and qData[2][1]) or {}
            for _, id in ipairs(refs) do if id == npcId then activeRefs[questId] = true end end
            refs = (qData[3] and qData[3][1]) or {}
            for _, id in ipairs(refs) do if id == npcId then activeRefs[questId] = true end end
            if qData[10] and qData[10][1] then
                for _, entry in ipairs(qData[10][1]) do
                    if entry[1] == npcId then activeRefs[questId] = true end
                end
            end
        end
    end
    _RefreshActiveQuestPins(activeRefs)
end

------------------------------------------------------------------------
-- CrossLinkAfterQuest: called when a new quest is first learned.
-- Stitches NPCs, objects, and items referenced in the quest data.
local function CrossLinkAfterQuest(questId)
    local learned = _GetDB()
    local qData = learned.quests[questId]
    if not qData then return end
    local liveEnabled = QuestieLearner and QuestieLearner.IsLearnerLiveEnabled and QuestieLearner:IsLearnerLiveEnabled()
    local qOvr   = liveEnabled and QuestieDB and QuestieDB.questDataOverrides or nil
    local npcOvr = liveEnabled and QuestieDB and QuestieDB.npcDataOverrides or nil
    local objOvr = liveEnabled and QuestieDB and QuestieDB.objectDataOverrides or nil

    -- Starter NPCs: quest[2][1] → npc[10]
    if qData[2] and qData[2][1] then
        for _, npcId in ipairs(qData[2][1]) do
            if learned.npcs[npcId] then
                _AddToArray(learned.npcs[npcId], 10, questId, npcOvr, npcId)
            end
        end
    end
    -- Starter objects: quest[2][2] → obj[2]
    if qData[2] and qData[2][2] then
        for _, objId in ipairs(qData[2][2]) do
            if learned.objects[objId] then
                _AddToArray(learned.objects[objId], 2, questId, objOvr, objId)
            end
        end
    end
    -- Finisher NPCs: quest[3][1] → npc[11]
    if qData[3] and qData[3][1] then
        for _, npcId in ipairs(qData[3][1]) do
            if learned.npcs[npcId] then
                _AddToArray(learned.npcs[npcId], 11, questId, npcOvr, npcId)
            end
        end
    end
    -- Finisher objects: quest[3][2] → obj[3]
    if qData[3] and qData[3][2] then
        for _, objId in ipairs(qData[3][2]) do
            if learned.objects[objId] then
                _AddToArray(learned.objects[objId], 3, questId, objOvr, objId)
            end
        end
    end
    -- Source item: quest[11] → item[5] (item starts this quest, via startQuest key)
    if qData[11] and qData[11] > 0 then
        local iData = learned.items[qData[11]]
        if iData then
            iData.questRelevant = true
            if not iData[5] then
                iData[5] = questId
                if liveEnabled and QuestieDB and QuestieDB.itemDataOverrides then
                    local ovr = QuestieDB.itemDataOverrides[qData[11]] or {}
                    QuestieDB.itemDataOverrides[qData[11]] = ovr
                    if ovr[1] == nil and iData[1] ~= nil and not IsAscensionProtected("ITEM", qData[11], 1) then
                        ovr[1] = iData[1]
                    end
                    if not ovr[5] then ovr[5] = questId end
                    for k, v in pairs(iData) do
                        if k ~= 1 and k ~= 5 and k ~= "mc" and ovr[k] == nil and not IsAscensionProtected("ITEM", qData[11], k) then
                            ovr[k] = v
                        end
                    end
                end
            end
        end
    end
    -- Item drop chain: quest has item objectives [10][3]; if any of those
    -- items have known drop NPCs (item[2]), add those NPCs as creature objectives.
    if qData[10] and qData[10][3] then
        for _, entry in ipairs(qData[10][3]) do
            local itemId = entry[1]
            local iData = learned.items[itemId]
            if iData and iData[2] then
                iData.questRelevant = true
                for _, dropNpcId in ipairs(iData[2]) do
                    _AddToQuestObjective(qData, 1, dropNpcId, nil, qOvr, questId)
                end
            end
        end
    end
end

------------------------------------------------------------------------
-- CrossLinkAfterObject: called when a new object is first learned.
-- Scans all learned quests for references to this objectId.
local function CrossLinkAfterObject(objectId)
    local learned = _GetDB()
    local objData = learned.objects[objectId]
    if not objData then return end
    local liveEnabled = QuestieLearner and QuestieLearner.IsLearnerLiveEnabled and QuestieLearner:IsLearnerLiveEnabled()
    local objOvr = liveEnabled and QuestieDB and QuestieDB.objectDataOverrides or nil
    local qOvr   = liveEnabled and QuestieDB and QuestieDB.questDataOverrides or nil

    for questId, qData in pairs(learned.quests) do
        -- Object starters: quest[2][2]
        if qData[2] and qData[2][2] then
            for _, id in ipairs(qData[2][2]) do
                if id == objectId then
                    _AddToArray(objData, 2, questId, objOvr, objectId)
                    break
                end
            end
        end
        -- Object finishers: quest[3][2]
        if qData[3] and qData[3][2] then
            for _, id in ipairs(qData[3][2]) do
                if id == objectId then
                    _AddToArray(objData, 3, questId, objOvr, objectId)
                    break
                end
            end
        end
        -- Object objectives: quest[10][2] — this object is an interact target
        -- Coords are already stored in object spawns; no extra link needed
    end

    -- Refresh map pins for active quests now linked to this object
    local activeRefs = {}
    for questId, qData in pairs(learned.quests) do
        local function checkList(list)
            if list then for _, id in ipairs(list) do if id == objectId then activeRefs[questId] = true end end end
        end
        checkList(qData[2] and qData[2][2])
        checkList(qData[3] and qData[3][2])
        if qData[10] and qData[10][2] then
            for _, entry in ipairs(qData[10][2]) do
                if entry[1] == objectId then activeRefs[questId] = true end
            end
        end
    end
    _RefreshActiveQuestPins(activeRefs)
end

------------------------------------------------------------------------
-- CrossLinkAfterItem: called when an item is first learned or when a
-- new drop-NPC relationship is added to an item.
-- Links drop NPCs → quest creature objectives for any quest needing this item.
local function CrossLinkAfterItem(itemId)
    local learned = _GetDB()
    local iData = learned.items[itemId]
    if not iData then return end
    local liveEnabled = QuestieLearner and QuestieLearner.IsLearnerLiveEnabled and QuestieLearner:IsLearnerLiveEnabled()
    local qOvr = liveEnabled and QuestieDB and QuestieDB.questDataOverrides or nil
    local activeRefs = {}

    -- If this item starts a quest (item[5]=startQuest), ensure that quest knows
    -- about it via quest[2][3] (starter items slot)
    for questId, qData in pairs(learned.quests) do
        if qData[11] == itemId then
            if not iData[5] then
                iData[5] = questId
                if liveEnabled and QuestieDB and QuestieDB.itemDataOverrides then
                    local ovr = QuestieDB.itemDataOverrides[itemId] or {}
                    QuestieDB.itemDataOverrides[itemId] = ovr
                    if not ovr[5] then ovr[5] = questId end
                end
            end
        end
        -- If any quest has this item as an objective (quest[10][3]),
        -- and we know NPCs that drop it (item[2]), add those NPCs as creature objectives.
        if qData[10] and qData[10][3] then
            for _, entry in ipairs(qData[10][3]) do
                if entry[1] == itemId and iData[2] then
                    for _, dropNpcId in ipairs(iData[2]) do
                        _AddToQuestObjective(qData, 1, dropNpcId, nil, qOvr, questId)
                        activeRefs[questId] = true
                    end
                end
            end
        end
    end

    _RefreshActiveQuestPins(activeRefs)
end

------------------------------------------------------------------------
-- CrossLinkAfterQuestGiver: called when a starter/finisher relationship
-- is explicitly recorded. Stitches both the NPC→quest and quest→NPC
-- directions (and objects/items if typeSlot indicates them).
local function CrossLinkAfterQuestGiver(questId, entityId, typeSlot, isStart)
    local learned = _GetDB()
    local qData  = learned.quests[questId]
    local liveEnabled = QuestieLearner and QuestieLearner.IsLearnerLiveEnabled and QuestieLearner:IsLearnerLiveEnabled()
    local npcOvr = liveEnabled and QuestieDB and QuestieDB.npcDataOverrides or nil
    local objOvr = liveEnabled and QuestieDB and QuestieDB.objectDataOverrides or nil
    local qOvr   = liveEnabled and QuestieDB and QuestieDB.questDataOverrides or nil

    if typeSlot == 1 then
        -- NPC ↔ quest
        local npcData = learned.npcs[entityId]
        if npcData then
            _AddToArray(npcData, isStart and 10 or 11, questId, npcOvr, entityId)
        end
        if qData then
            _AddToNestedArray(qData, isStart and 2 or 3, 1, entityId, qOvr, questId)
        end
    elseif typeSlot == 2 then
        -- Object ↔ quest
        local objData = learned.objects[entityId]
        if objData then
            _AddToArray(objData, isStart and 2 or 3, questId, objOvr, entityId)
        end
        if qData then
            _AddToNestedArray(qData, isStart and 2 or 3, 2, entityId, qOvr, questId)
        end
    elseif typeSlot == 3 then
        -- Item ↔ quest starter (item[3] = starts quest; quest[2][3])
        if qData then
            _AddToNestedArray(qData, 2, 3, entityId, qOvr, questId)
        end
    end
end

------------------------------------------------------------------------
-- NPC learning
------------------------------------------------------------------------

-- Player-spawned NPCs that should never be learned (totems, guardians, etc.)
local PLAYER_SPAWNED_NPC_SET = {
    [2523] = true,    -- Searing Totem
    [2630] = true,    -- Earthbind Totem
    [10183] = true,   -- Moonflare Totem
    [1103907] = true, -- Healing Stream Totem III
    [1107398] = true, -- Stoneclaw Totem V
}

-- Critters are never quest-relevant, so they should never enter the learner DB.
-- This static set covers the common classic critters; Ascension's custom critters are
-- caught at runtime via UnitCreatureType (see _NoteUnitCreatureType / _Learner.critterIds).
local CRITTER_NPC_SET = {
    [721]  = true, -- Rabbit
    [883]  = true, -- Deer
    [1933] = true, -- Sheep
    [2442] = true, -- Cow
    [6368] = true, -- Cat
    [2620] = true, -- Prairie Dog
    [4953] = true, -- Cat (Wisp)
    [9700] = true, -- Squirrel
    [5113] = true, -- Mouse
    [5114] = true, -- Rat
    [5115] = true, -- Snake
    [5116] = true, -- Toad
    [2914] = true, -- Frog
    [385]  = true, -- Small Frog
    [890]  = true, -- Crab
    [299]  = true, -- Chicken
    [620]  = true, -- Chicken
    [2719] = true, -- Battered Rabbit
}

-- Runtime-discovered critters (npcId -> true), populated by _NoteUnitCreatureType when a
-- unit token is available, so Ascension's custom critters are excluded even if not in the
-- static set above.
_Learner.critterIds = _Learner.critterIds or {}

local function IsCritterNpc(npcId)
    return npcId and (CRITTER_NPC_SET[npcId] or _Learner.critterIds[npcId]) or false
end

-- Records the creature type for a unit we currently have a token for (mouseover/target).
-- When the unit is a Critter, remember its npcId and purge any learner data for it, since
-- critters are never quest-relevant and only pollute the learner DB.
local function _NoteUnitCreatureType(unit, npcId)
    if not unit or not npcId or npcId <= 0 then return end
    if not (UnitCreatureType and UnitExists and UnitExists(unit)) then return end
    if UnitCreatureType(unit) == "Critter" then
        _Learner.critterIds[npcId] = true
        local ld = Questie.dbLearner and Questie.dbLearner.global
        if ld and ld.npcs and ld.npcs[npcId] then
            ld.npcs[npcId] = nil
            Questie:Debug(Questie.DEBUG_INFO, "[QuestieLearner] Removed critter from learner data:", npcId)
        end
    end
end

function QuestieLearner:LearnNPC(npcId, name, level, subName, npcFlags, factionString, spawnX, spawnY, spawnZoneId)
    if not self:IsEnabled() then return end
    if not Questie.dbLearner.global.settings.learnNpcs then return end
    if not npcId or npcId <= 0 then return end
    -- Never learn player-spawned totems
    if PLAYER_SPAWNED_NPC_SET[npcId] then return end
    -- Never learn critters (not quest-relevant)
    if IsCritterNpc(npcId) then return end

    -- Use provided spawn coords (e.g. from kill event) or fall back to current player position.
    -- Normalize area IDs → map IDs immediately so all storage uses the same key space
    -- as AscensionDB (e.g. 3431 → 1241, 3430 → 1941).
    local zoneId = NormalizeSpawnZoneKey(spawnZoneId or GetZoneId())
    local x, y
    if spawnX and spawnY then
        x, y = spawnX, spawnY
    else
        x, y = GetPlayerCoords()
    end

    local existing = Questie.dbLearner.global.npcs[npcId]
    local isNew = existing == nil
    if not existing then
        existing = {}
        Questie.dbLearner.global.npcs[npcId] = existing
    end

    if name and name ~= "" and (not existing[1] or existing[1] == "") then
        existing[1] = name
        _MarkNpcNameIndexDirty()
    end
    if level then
        if not existing[4] or level < existing[4] then existing[4] = level end
        if not existing[5] or level > existing[5] then existing[5] = level end
    end
    if zoneId        and zoneId > 0 and not existing[9]  then existing[9]  = zoneId end
    if factionString and not existing[13] then existing[13] = factionString end
    if subName       and not existing[14] then existing[14] = subName end
    if x and y and zoneId and zoneId > 0 then
        existing[7] = existing[7] or {}
        existing[7][zoneId] = existing[7][zoneId] or {}
        InsertIfNewBucket(existing[7][zoneId], x, y, GetCoordGridForZone(zoneId))
        if spawnX and spawnY then
            existing.spawnSource = "explicit"
        elseif existing.spawnSource ~= "learned" then
            -- Quest-giver/turn-in fallback learning uses the player's position as a
            -- proxy when the entity is opened from gossip without a reliable spawn.
            existing.spawnSource = "fallback"
        end
    elseif existing.spawnSource ~= "explicit" and existing.spawnSource ~= "learned" then
        -- Quest-giver/turn-in fallback learning uses the player's position as a proxy.
        -- Keep that separate from actual learned spawn evidence so we can safely
        -- discard it later without deleting real kill/object-driven coordinates.
        existing.spawnSource = "fallback"
    end

    existing.ls = time() -- Update last seen
    existing.mc = (existing.mc or 0) + 1

    -- Live injection is intentionally batched: repeated kill/log/loot events for
    -- the same NPC update saved evidence immediately, then flush QuestieDB once.
    if self:IsLearnerLiveEnabled() then
        _QueueNpcLiveUpdate(npcId)
    end

    if isNew then
        Questie:Debug(Questie.DEBUG_LEARNER, "[QuestieLearner] New NPC learned:", npcId, name or "?")
        CrossLinkAfterNPC(npcId)
    end
    _Learner:BroadcastIfCommsAvailable("NPC", npcId, existing)

    return isNew
end

------------------------------------------------------------------------
-- Phase 2: Per-GUID spawn evidence
------------------------------------------------------------------------

-- Extracts the spawn UID (low 24 bits / last 6 hex chars) from a WoW GUID.
-- This is the per-spawn-instance identifier — different GUIDs for the same
-- npcId indicate different spawn points (e.g. three boars at three corners
-- of a field, not one boar teleporting around).
-- IMPORTANT: Do not revert this to a single GUID format. Ascension clients
-- may emit either dashed GUIDs or compact hex GUIDs ("0x..."), and both must
-- remain supported or GUID-based learner evidence will silently stop storing.
-- Format: "Creature-0-RR-RI-0-NNNNNNNN" where NNNNNNNN = spawn UID
local function _ExtractSpawnUID(guid)
    if not guid or type(guid) ~= "string" then return nil end
    -- Client-arg combat log GUIDs on Ascension commonly arrive as compact hex
    -- strings (e.g. "0xF130003BAA009E40"). Use the low 24 bits so different
    -- spawn instances of the same npcId still resolve to distinct evidence keys.
    local hexTail = guid:match("^0x%x+(%x%x%x%x%x%x)$")
    if hexTail then
        return tonumber(hexTail, 16)
    end
    -- Dash format: Creature-0-1234-567-89-21878-0000001234
    -- Last numeric segment after the 5th dash is the spawn UID
    local spawnUID = guid:match("^[^%-]+%-[^%-]+%-[^%-]+%-[^%-]+%-[^%-]+%-(%d+)$")
    if spawnUID then
        return tonumber(spawnUID)
    end
    -- Fallback for other dash formats: take everything after the last dash
    spawnUID = guid:match("^.+%-(%d+)$")
    if spawnUID then
        return tonumber(spawnUID)
    end
    return nil
end

-- Ensures entry[8] (guidSpawns) exists on the learned NPC data table.
-- entry[8] schema: { [spawnUID] = { zoneId, x, y, ts, source, confidence } }
local function _GetOrCreateGuidSpawnTable(entry)
    if not entry then return nil end
    if not entry[8] then entry[8] = {} end
    return entry[8]
end

-- Stores a per-GUID kill event under the learned NPC data.
-- Each unique spawn UID (per npcId per zone) gets one evidence entry.
-- On repeated kills at the same spawn UID, the entry is updated (moved to
-- the current position if the NPC has wandered slightly, timestamp refreshed).
-- Storage is bounded: max MAX_GUID_SPAWNS_PER_NPC_PER_ZONE entries per zone;
-- oldest entry evicted when at capacity.
local MAX_GUID_SPAWNS_PER_NPC_PER_ZONE = 8

function QuestieLearner:_StoreGuidSpawnEvidence(npcId, dstGUID, zoneId, x, y)
    if not self:IsEnabled() then return end
    if not npcId or npcId <= 0 then return end
    if not dstGUID or type(dstGUID) ~= "string" then return end
    if not zoneId or zoneId <= 0 then return end
    if not x or not y or x <= 0 or y <= 0 then return end

    -- Normalize area IDs → map IDs so evidence is keyed identically to AscensionDB.
    -- Without this, kills on Sunstrider store under zone 3431 (area ID) while the
    -- renderer expects zone 1241 (map ID), causing pins to silently not appear.
    zoneId = NormalizeSpawnZoneKey(zoneId)

    local spawnUID = _ExtractSpawnUID(dstGUID)
    if not spawnUID then return end

    local learnedNpc = Questie.dbLearner.global.npcs[npcId]
    if not learnedNpc then return end

    local guidSpawns = _GetOrCreateGuidSpawnTable(learnedNpc)
    if not guidSpawns then return end

    -- Normalize coords to Questie's 0-100 map scale. NormalizeCoordPair handles all
    -- three input formats: native 0-1, already-scaled 0-100, or buggy 0-10000.
    local nx, ny = NormalizeCoordPair(x, y)
    if not nx or not ny then return end

    -- DEBUG: log raw x/y and normalized nx/ny being stored
    -- Questie:Debug(Questie.DEBUG_LEARNER,
        -- "_StoreGuidSpawnEvidence: npcId=", npcId,
        -- "spawnUID=", spawnUID,
        -- "x=", x, "y=", y,
        -- "nx=", nx, "ny=", ny,
        -- "zoneId=", zoneId)

    if guidSpawns[spawnUID] then
        -- Existing spawn UID: update position and timestamp
        local existingCount = tonumber(guidSpawns[spawnUID].count) or 1
        local healedCount = existingCount + 1
        local healedX = ((guidSpawns[spawnUID].x or nx) * existingCount + nx) / healedCount
        local healedY = ((guidSpawns[spawnUID].y or ny) * existingCount + ny) / healedCount
        guidSpawns[spawnUID].x, guidSpawns[spawnUID].y = NormalizeCoordPair(healedX, healedY)
        guidSpawns[spawnUID].count = healedCount
        guidSpawns[spawnUID].ts = time()
    else
        -- New spawn UID: insert, bounded by npcId+zoneId.
        -- Evict oldest entry if at capacity.
        local zoneCount = 0
        local oldestUID = nil
        local oldestTS = nil
        for uid in pairs(guidSpawns) do
            local e = guidSpawns[uid]
            if e and e.zoneId == zoneId then
                zoneCount = zoneCount + 1
                if not oldestTS or e.ts < oldestTS then
                    oldestTS = e.ts
                    oldestUID = uid
                end
            end
        end
        if zoneCount >= MAX_GUID_SPAWNS_PER_NPC_PER_ZONE and oldestUID then
            guidSpawns[oldestUID] = nil
        end
        guidSpawns[spawnUID] = {
            zoneId = zoneId,
            x = nx,
            y = ny,
            ts = time(),
            source = "local",
            confidence = 1,
            count = 1,
        }
    end

    learnedNpc.spawnSource = "learned"
end

------------------------------------------------------------------------
-- Phase 3: Weighted spawn merge
------------------------------------------------------------------------

-- Merges learned GUID-based spawn evidence into the static NPC spawn list.
-- Scoring: spawn UID with most evidence across all zones wins.
-- Override condition: top spawn appears in >60% of total evidence AND
-- differs from static DB entry. Below 60% confidence, learned does not
-- override static and both sources coexist.
-- Called from the kill handler after _StoreGuidSpawnEvidence when
-- evidence count >= 3 for that npcId.
--@param npcId number  The NPC ID to merge evidence for
--@return boolean      True if static DB spawn list was overridden
local function _MergeSpawnEvidence(npcId)
    if not npcId or npcId <= 0 then return false end

    local learnedNpc = Questie.dbLearner and Questie.dbLearner.global
        and Questie.dbLearner.global.npcs[npcId]
    if not learnedNpc then return false end

    local guidSpawns = learnedNpc[8]
    if not guidSpawns or not next(guidSpawns) then return false end

    -- Collect all evidence: group by (zoneId, x, y) rounded to 2 decimal places
    -- Key format: "zoneId|x|y" → count
    local evidence = {}  -- { [key] = { zoneId, x, y, count } }
    local totalEvidence = 0

    for spawnUID, entry in pairs(guidSpawns) do
        if entry and entry.zoneId and entry.x and entry.y then
            local evidenceX, evidenceY = NormalizeCoordPair(entry.x, entry.y)
            if not evidenceX or not evidenceY then
                Questie:Debug(Questie.DEBUG_INFO,
                    "[QuestieLearner] _MergeSpawnEvidence skipping invalid coords: spawnUID=", spawnUID,
                    "entry.x=", tostring(entry.x), "entry.y=", tostring(entry.y))
            else
                entry.x = evidenceX
                entry.y = evidenceY

                local rx, ry = NormalizeCoordPair(evidenceX, evidenceY)
                -- Group kills by a coordinate bucket, not by exact coords. Kill
                -- evidence is the player's position at kill time, which drifts a
                -- little every kill, so exact keys would treat each kill as its own
                -- "location" — producing one pin per kill and never letting any
                -- single spot accumulate enough evidence to clear the confidence
                -- threshold. Bucketing collapses repeated kills at the same spawn
                -- into one location (matching the [7] InsertIfNewBucket behavior).
                local grid = GetCoordGridForZone(entry.zoneId)
                local bx = floor(rx / grid)
                local by = floor(ry / grid)
                local key = entry.zoneId .. "|" .. bx .. "|" .. by
                if not evidence[key] then
                    evidence[key] = { zoneId = entry.zoneId, x = rx, y = ry, count = 0 }
                end
                local evidenceWeight = tonumber(entry.count) or 1
                if evidenceWeight < 1 then
                    evidenceWeight = 1
                end
                evidence[key].count = evidence[key].count + evidenceWeight
                totalEvidence = totalEvidence + evidenceWeight
            end
        end
    end

    if totalEvidence < 3 then return false end

    -- Find top-scoring spawn
    local topKey = nil
    local topCount = 0
    for key, e in pairs(evidence) do
        if e.count > topCount then
            topCount = e.count
            topKey = key
        end
    end

    if not topKey then return false end

    local topEvidence = evidence[topKey]
    local topPct = (topCount / totalEvidence) * 100

    -- Info-only trace: raw top evidence is useful for diagnosing coordinate corruption
    Questie:Debug(Questie.DEBUG_INFO,
        "[QuestieLearner] _MergeSpawnEvidence: topKey=", topKey,
        "topEvidence.x=", topEvidence.x, "topEvidence.y=", topEvidence.y,
        "topCount=", topCount, "totalEvidence=", totalEvidence)

    -- Sunstrider Isle: zone IDs are now normalized via NormalizeSpawnZoneKey so
    -- topEvidence.zoneId will be 1241 (map ID), not 3431 (area ID).
    -- IsSunstriderNativeZone checks both to be safe against old saved data.
    -- Confidence threshold is bypassed for Sunstrider because spawn points are
    -- distributed across 5+ locations — no single point ever reaches 60% of kills.
    local isSunstrider = IsSunstriderNativeZone(topEvidence.zoneId)
    local confidenceThreshold = isSunstrider and 0 or 60

    -- Only override if > confidence threshold AND spawn differs from static DB
    if topPct <= confidenceThreshold then
        Questie:Debug(Questie.DEBUG_INFO,
            "[QuestieLearner] _MergeSpawnEvidence: npcId", npcId,
            "top spawn", topCount .. "/" .. totalEvidence,
            "= " .. floor(topPct + 0.5) .. "%" ..
            (isSunstrider and " — Sunstrider, threshold bypassed" or (" — below " .. confidenceThreshold .. "%, no override")))
        -- For Sunstrider, fall through and apply the learned spawn anyway
        if not isSunstrider then
            return false
        end
    end

    if isSunstrider then
        -- AscensionDB owns spawn data for known Sunstrider NPCs — never overwrite it.
        -- Key 7 = spawns. Without this guard the learner would pollute the curated
        -- AscensionDB coords with in-game kill evidence, causing wrong pin counts.
        -- REGRESSION NOTE: If AscensionDB protection check is removed or disabled,
        -- learner pins will reappear at wrong locations. Do not remove this guard.
        -- This MUST be unconditional — commit 0f20ea8 added a `(not learnerLiveMode)`
        -- bypass that re-enabled the bug in learner mode (Sunstrider Mana Wyrm kills
        -- overwrote AscensionDB's curated coords). Use the mode-independent ownership
        -- check, not IsAscensionProtected (which returns false in learner mode).
        if AscensionOwnsNpcSpawns(npcId) then
            Questie:Debug(Questie.DEBUG_INFO,
                "[QuestieLearner] _MergeSpawnEvidence: npcId", npcId,
                "Sunstrider zone but AscensionDB owns spawns — skipping learner injection")
            return false
        end

        -- topEvidence.zoneId is now a map ID (e.g. 1241) because NormalizeSpawnZoneKey
        -- converted the area ID at storage time. This matches AscensionDB's key space
        -- so DrawWorldIcon and HBD can resolve the coordinates correctly.
        QuestieDB.npcDataOverrides[npcId] = QuestieDB.npcDataOverrides[npcId] or {}
        QuestieDB.npcDataOverrides[npcId][7] = QuestieDB.npcDataOverrides[npcId][7] or {}
        QuestieDB.npcDataOverrides[npcId][7][topEvidence.zoneId] = QuestieDB.npcDataOverrides[npcId][7][topEvidence.zoneId] or {}

        local promoted = 0
        local duplicates = 0
        local zoneSpawns = QuestieDB.npcDataOverrides[npcId][7][topEvidence.zoneId]
        local seen = {}
        for _, spawnEvidence in pairs(evidence) do
            local sx, sy = NormalizeCoordPair(spawnEvidence.x, spawnEvidence.y)
            if sx and sy and not seen[sx..","..sy] then
                seen[sx..","..sy] = true
                local grid = GetCoordGridForZone(topEvidence.zoneId)
                if InsertIfNewBucket(zoneSpawns, sx, sy, grid) then
                    promoted = promoted + 1
                else
                    duplicates = duplicates + 1
                end
            else
                duplicates = duplicates + 1
            end
        end

        Questie:Debug(Questie.DEBUG_INFO,
            "[QuestieLearner] _MergeSpawnEvidence: npcId", npcId,
            "promoted Sunstrider evidence groups", promoted,
            "duplicates", duplicates,
            "zone", tostring(topEvidence.zoneId))

        _QueueNpcLiveUpdate(npcId)

        return promoted > 0 or duplicates > 0
    end

    -- Check against static DB + learner-promoted override entries.
    -- After a previous promotion, QueryNPCSingle returns the override data,
    -- so learner-promoted spawns would incorrectly "match static" and block
    -- re-promotion. We must exclude overrides we wrote ourselves.
    local staticNPC = nil
    if QuestieDB and QuestieDB.QueryNPCSingle then
        staticNPC = QuestieDB.QueryNPCSingle(npcId, "spawns")
    end

    local staticSpawnList = staticNPC
    local staticSpawnsForZone = staticSpawnList and staticSpawnList[topEvidence.zoneId]

    -- Collect spawns already promoted by the learner for this zone
    local learnerOverrides = QuestieDB.npcDataOverrides
        and QuestieDB.npcDataOverrides[npcId]
        and QuestieDB.npcDataOverrides[npcId][7]
        and QuestieDB.npcDataOverrides[npcId][7][topEvidence.zoneId]
    local learnerOverrideSet = {}
    if learnerOverrides then
        for _, entry in ipairs(learnerOverrides) do
            if entry and entry[1] and entry[2] then
                local lx = floor(entry[1] * 100 + 0.5) / 100
                local ly = floor(entry[2] * 100 + 0.5) / 100
                learnerOverrideSet[lx .. "|" .. ly] = true
            end
        end
    end

    -- Check if top spawn matches any static spawn in the same zone,
    -- excluding learner-promoted overrides (those should always be updatable)
    local matchesStatic = false
    if staticSpawnsForZone then
        for _, coord in ipairs(staticSpawnsForZone) do
            local sx = floor(coord[1] * 100 + 0.5) / 100
            local sy = floor(coord[2] * 100 + 0.5) / 100
            -- Skip learner-promoted entries — they are not "static"
            if not learnerOverrideSet[sx .. "|" .. sy] then
                if abs(sx - topEvidence.x) < 0.01 and abs(sy - topEvidence.y) < 0.01 then
                    matchesStatic = true
                    break
                end
            end
        end
    end

    if matchesStatic then
        Questie:Debug(Questie.DEBUG_INFO,
            "[QuestieLearner] _MergeSpawnEvidence: npcId", npcId,
            "top spawn matches static DB — no override needed")
        return false
    end

    Questie:Debug(Questie.DEBUG_INFO,
        "[QuestieLearner] _MergeSpawnEvidence promoting npcId", npcId,
        "zone", tostring(topEvidence.zoneId),
        "x", tostring(topEvidence.x),
        "y", tostring(topEvidence.y),
        "protected", tostring(IsAscensionProtected("NPC", npcId, 7)))

    -- Insert as new spawn (InsertIfNewBucket deduplicates).
    -- Only create zone table entry if insert succeeds — an empty zone override
    -- {[3431] = {}} makes _MergeOverride's IsEmptyTable check fall through to
    -- rawdata, bypassing learner data entirely (field is non-nil but empty).
    local spawned = false
    if topEvidence.x and topEvidence.y then
        if not QuestieDB.npcDataOverrides[npcId] then
            QuestieDB.npcDataOverrides[npcId] = {}
        end
        if not QuestieDB.npcDataOverrides[npcId][7] then
            QuestieDB.npcDataOverrides[npcId][7] = {}
        end
        if not QuestieDB.npcDataOverrides[npcId][7][topEvidence.zoneId] then
            QuestieDB.npcDataOverrides[npcId][7][topEvidence.zoneId] = {}
        end
        spawned = InsertIfNewBucket(QuestieDB.npcDataOverrides[npcId][7][topEvidence.zoneId],
            topEvidence.x, topEvidence.y, GetCoordGridForZone(topEvidence.zoneId))
    end

    Questie:Debug(Questie.DEBUG_INFO,
        "[QuestieLearner] _MergeSpawnEvidence: npcId", npcId,
        "overrode static DB — learned spawn (" .. tostring(topEvidence.x) .. "," .. tostring(topEvidence.y) .. ")",
        "zone " .. topEvidence.zoneId .. " at " .. floor(topPct + 0.5) .. "% confidence",
        spawned and "SPAM" or "IGNORED_DUPLICATE")

    -- Clear/rebuild cache through the same coalesced path used by kill learning.
    _QueueNpcLiveUpdate(npcId)

    return true
end

------------------------------------------------------------------------
-- Quest learning
------------------------------------------------------------------------

-- Captures all fields accessible from the WoW API.
-- Quest data array indices follow the Questie wiki spec exactly:
--  [1]  name           [2]  starters (npc/obj/item arrays)  [3]  finishers
--  [4]  requiredLevel  [5]  questLevel  [6]  infoText (objectives text block)
--  [7]  requiredMoney  [8]  zoneOrSort  [12] requiredRaces   [13] requiredClasses
--  [17] details text   [18] finishText  [19] completedText
function QuestieLearner:LearnQuest(questId, data)
    if not self:IsEnabled() then
        Questie:Debug(Questie.DEBUG_INFO, "[QuestieLearner] LearnQuest blocked: learner not enabled")
        return
    end
    questId = tonumber(questId)
    if not questId or questId <= 0 then return end
    if not Questie.dbLearner.global.settings.learnQuests then
        Questie:Debug(Questie.DEBUG_INFO, "[QuestieLearner] LearnQuest blocked: learnQuests=", tostring(Questie.dbLearner.global.settings.learnQuests))
        return
    end
    if not questId or questId <= 0 then return end

    local existing = Questie.dbLearner.global.quests[questId]
    local isNew = existing == nil
    if not existing then
        existing = {}
        Questie.dbLearner.global.quests[questId] = existing
    end

    existing.ls = time() -- Update last seen

    for k, v in pairs(data) do
        if v ~= nil and v ~= "" and v ~= 0 and existing[k] == nil then
            existing[k] = v
        end
    end

    existing.mc = (existing.mc or 0) + 1

    -- Live injection into questDataOverrides so GetQuest works without reload
    if self:IsLearnerLiveEnabled() and QuestieDB and QuestieDB.questDataOverrides then
        local ovr = QuestieDB.questDataOverrides[questId]
        if not ovr then
            QuestieDB.questDataOverrides[questId] = existing
        else
            for k, v in pairs(existing) do
                if ovr[k] == nil and not IsAscensionProtected("QUEST", questId, k) then ovr[k] = v end
            end
        end
        if QuestieDB.private and QuestieDB.private.questCache then
            QuestieDB.private.questCache[questId] = nil
        end
    end

    if isNew then
        Questie:Debug(Questie.DEBUG_LEARNER, "[QuestieLearner] New quest learned:", questId, existing[1] or "?")
        CrossLinkAfterQuest(questId)
    end
    _Learner:BroadcastIfCommsAvailable("QUEST", questId, existing)
end

-- Records the NPC/object that starts or finishes a quest (array index [2] or [3])
function QuestieLearner:LearnQuestGiver(questId, entityId, entityType, isStart)
    if not self:IsEnabled() then return end
    if not Questie.dbLearner.global.settings.learnQuests then return end
    questId, entityId = tonumber(questId), tonumber(entityId)
    if not questId or questId <= 0 or not entityId or entityId <= 0 then return end

    local existing = Questie.dbLearner.global.quests[questId]
    if not existing then
        existing = {}
        Questie.dbLearner.global.quests[questId] = existing
    end

    -- Starters/finishers: { [1]={npcIds}, [2]={objIds}, [3]={itemIds} }
    local field = isStart and 2 or 3
    existing[field] = existing[field] or {}
    -- entityType: 1=npc, 2=obj, 3=item
    local typeSlot = entityType or 1
    existing[field][typeSlot] = existing[field][typeSlot] or {}
    local list = existing[field][typeSlot]
    for _, id in ipairs(list) do
        if id == entityId then return end
    end
    table.insert(list, entityId)

    -- Live injection into questDataOverrides so starters/finishers take effect without reload
    if self:IsLearnerLiveEnabled() and QuestieDB and QuestieDB.questDataOverrides and not IsAscensionProtected("QUEST", questId, field) then
        local ovr = QuestieDB.questDataOverrides[questId] or {}
        QuestieDB.questDataOverrides[questId] = ovr
        ovr[field] = ovr[field] or {}
        ovr[field][typeSlot] = ovr[field][typeSlot] or {}
        local ovrList = ovr[field][typeSlot]
        local found = false
        for _, id in ipairs(ovrList) do
            if id == entityId then found = true; break end
        end
        if not found then table.insert(ovrList, entityId) end
        if QuestieDB.private and QuestieDB.private.questCache then
            QuestieDB.private.questCache[questId] = nil
        end
    end

    -- Cross-link both directions for all entity types
    CrossLinkAfterQuestGiver(questId, entityId, typeSlot, isStart)
end

------------------------------------------------------------------------
-- Quest objective NPC learning (kill objectives)
------------------------------------------------------------------------

-- Adds npcId as a creatureObjective for questId ([10][1] in questKeys schema).
-- If the NPC already exists in the base DB the spawn data is already there;
-- we only need the quest to reference it so tooltips/map-pins get registered.
function QuestieLearner:LearnQuestObjectiveNPC(questId, npcId, objText, objectiveIndex)
    if not self:IsEnabled() then return end
    if not Questie.dbLearner.global.settings.learnQuests then return end
    questId, npcId = tonumber(questId), tonumber(npcId)
    objectiveIndex = tonumber(objectiveIndex)
    if not questId or questId <= 0 or not npcId or npcId <= 0 then return end

    -- 1. Persist to SavedVariables
    local existing = Questie.dbLearner.global.quests[questId] or {}
    Questie.dbLearner.global.quests[questId] = existing
    existing[10] = existing[10] or {}
    existing[10][1] = existing[10][1] or {}  -- creatureObjective slot
    local alreadyInSV = false
    for _, entry in ipairs(existing[10][1]) do
        if entry[1] == npcId then alreadyInSV = true; break end
    end
    if not alreadyInSV then
        table.insert(existing[10][1], { npcId, objText or "" })
    end

    -- 1.1 Persist exact objective index mapping
    if objectiveIndex then
        existing.objIndex = existing.objIndex or {}
        local entry = existing.objIndex[objectiveIndex]
        if not entry then
            existing.objIndex[objectiveIndex] = { type = "monster", id = npcId, text = objText or "" }
        elseif entry.id ~= npcId then
            -- Handle Kill Credit (multiple NPCs for one objective)
            if type(entry.id) == "number" then
                entry.id = { entry.id, npcId }
                entry.type = "killcredit"
            else
                local found = false
                for _, id in ipairs(entry.id) do
                    if id == npcId then found = true; break end
                end
                if not found then table.insert(entry.id, npcId) end
            end
        end
    end

    -- 2. Apply to live questDataOverrides immediately (no reload needed)
    if self:IsLearnerLiveEnabled() and QuestieDB and QuestieDB.questDataOverrides and not IsAscensionProtected("QUEST", questId, 10) then
        local ovr = QuestieDB.questDataOverrides[questId] or {}
        QuestieDB.questDataOverrides[questId] = ovr
        ovr[10] = ovr[10] or {}
        ovr[10][1] = ovr[10][1] or {}
        local alreadyPresent = false
        for _, entry in ipairs(ovr[10][1]) do
            if entry[1] == npcId then alreadyPresent = true; break end
        end
        if not alreadyPresent then
            table.insert(ovr[10][1], { npcId, objText or "" })
        end

        -- Update live objIndex override
        if objectiveIndex then
            ovr.objIndex = ovr.objIndex or {}
            ovr.objIndex[objectiveIndex] = existing.objIndex[objectiveIndex]
        end
        if QuestieDB.private and QuestieDB.private.questCache then
            QuestieDB.private.questCache[questId] = nil
        end
    end

    -- 3. Re-process the quest so PopulateObjective registers tooltips & map pins
    if self:IsLearnerLiveEnabled() then
        _RefreshActiveQuestPins({ [questId] = true })
    end

    -- 3. Register with tooltip system immediately. Preserve the objective icon so
    -- nameplates can render the correct learned slay/loot/talk marker.
    local QuestieTooltips = QuestieLoader:ImportModule("QuestieTooltips")
    if self:IsLearnerLiveEnabled() and QuestieTooltips and QuestieTooltips.RegisterObjectiveTooltip and not HasAscensionQuestObjectiveData(questId) then
        local objectiveIcon
        local QuestLogCache = QuestieLoader:ImportModule("QuestLogCache")
        local objectives = QuestLogCache and QuestLogCache.GetQuestObjectives and QuestLogCache.GetQuestObjectives(questId)
        if objectives and objText then
            for _, obj in next, objectives do
                if obj.text and (obj.text == objText or string.find(obj.text, objText, 1, true) or string.find(objText, obj.text, 1, true)) then
                    objectiveIcon = obj.Icon
                    break
                end
            end
        end

        QuestieTooltips:RegisterObjectiveTooltip(questId, "m_" .. npcId, {
            Index = 0,
            Description = objText or "Learned Objective",
            Icon = objectiveIcon,
            Update = function() end
        })
    end

    Questie:Debug(Questie.DEBUG_LEARNER,
        "[QuestieLearner] Quest", questId, "objective NPC learned:", npcId, objText)
end

-- Adds objectId as an objectObjective for questId ([10][2] in questKeys schema).
function QuestieLearner:LearnQuestObjectiveObject(questId, objectId, objText, objectiveIndex)
    if not self:IsEnabled() then return end
    if not Questie.dbLearner.global.settings.learnQuests then return end
    questId, objectId = tonumber(questId), tonumber(objectId)
    objectiveIndex = tonumber(objectiveIndex)
    if not questId or questId <= 0 or not objectId or objectId <= 0 then return end

    local existing = Questie.dbLearner.global.quests[questId] or {}
    Questie.dbLearner.global.quests[questId] = existing
    existing[10] = existing[10] or {}
    existing[10][2] = existing[10][2] or {}
    local alreadyInSV = false
    for _, entry in ipairs(existing[10][2]) do
        if entry[1] == objectId then alreadyInSV = true; break end
    end
    if not alreadyInSV then
        table.insert(existing[10][2], { objectId, objText or "" })
    end

    local recent = _Learner.recentObjects and _Learner.recentObjects[objectId]
    if recent then
        self:LearnObject(objectId, recent.name or objText, recent.x, recent.y, recent.zoneId, true)
    else
        self:LearnObject(objectId, objText, nil, nil, GetZoneId(), true)
    end

    if objectiveIndex then
        existing.objIndex = existing.objIndex or {}
        local entry = existing.objIndex[objectiveIndex]
        if not entry then
            existing.objIndex[objectiveIndex] = { type = "object", id = objectId, text = objText or "" }
        end
    end

    if self:IsLearnerLiveEnabled() and QuestieDB and QuestieDB.questDataOverrides and not IsAscensionProtected("QUEST", questId, 10) then
        local ovr = QuestieDB.questDataOverrides[questId] or {}
        QuestieDB.questDataOverrides[questId] = ovr
        ovr[10] = ovr[10] or {}
        ovr[10][2] = ovr[10][2] or {}
        local alreadyPresent = false
        for _, entry in ipairs(ovr[10][2]) do
            if entry[1] == objectId then alreadyPresent = true; break end
        end
        if not alreadyPresent then
            table.insert(ovr[10][2], { objectId, objText or "" })
        end
        if objectiveIndex then
            ovr.objIndex = ovr.objIndex or {}
            ovr.objIndex[objectiveIndex] = existing.objIndex[objectiveIndex]
        end
        if QuestieDB.private and QuestieDB.private.questCache then
            QuestieDB.private.questCache[questId] = nil
        end
    end

    if self:IsLearnerLiveEnabled() then
        _RefreshActiveQuestPins({ [questId] = true })
    end

    local QuestieTooltips = QuestieLoader:ImportModule("QuestieTooltips")
    if self:IsLearnerLiveEnabled() and QuestieTooltips and QuestieTooltips.RegisterObjectiveTooltip and not HasAscensionQuestObjectiveData(questId) then
        QuestieTooltips:RegisterObjectiveTooltip(questId, "o_" .. objectId, {
            Index = 0,
            Description = objText or "Learned Objective",
            Update = function() end
        })
    end

    Questie:Debug(Questie.DEBUG_LEARNER,
        "[QuestieLearner] Quest", questId, "objective OBJECT learned:", objectId, objText)
end

------------------------------------------------------------------------
-- Item learning
------------------------------------------------------------------------

local function IsQuestRelevantItem(itemId, itemClass)
    local learned = Questie and Questie.dbLearner and Questie.dbLearner.global
    if not learned or not learned.quests then
        return false
    end

    if itemClass == 12 then
        return true
    end

    for _, qData in pairs(learned.quests) do
        if qData[11] == itemId then
            return true
        end
        if qData[10] and qData[10][3] then
            for _, entry in ipairs(qData[10][3]) do
                local entryId = type(entry) == "table" and entry[1] or entry
                if entryId == itemId then
                    return true
                end
            end
        end
        if qData[2] and qData[2][3] then
            for _, entry in ipairs(qData[2][3]) do
                local entryId = type(entry) == "table" and entry[1] or entry
                if entryId == itemId then
                    return true
                end
            end
        end
    end

    return false
end

local function HasQuestReferences(itemId)
    local learned = Questie and Questie.dbLearner and Questie.dbLearner.global
    if not learned or not learned.quests then
        return false
    end

    local itemData = learned.items and learned.items[itemId]
    if itemData and itemData.questRelevant then
        return true
    end

    for _, qData in pairs(learned.quests) do
        if qData[11] == itemId then
            return true
        end
        if qData[10] and qData[10][3] then
            for _, entry in ipairs(qData[10][3]) do
                if entry[1] == itemId then
                    return true
                end
            end
        end
        if qData[2] and qData[2][3] then
            for _, entry in ipairs(qData[2][3]) do
                local entryId = type(entry) == "table" and entry[1] or entry
                if entryId == itemId then
                    return true
                end
            end
        end
    end

    return false
end

local function HasQuestObjectReferences(objectId)
    local learned = Questie and Questie.dbLearner and Questie.dbLearner.global
    if not learned then
        return false
    end

    local objectData = learned.objects and learned.objects[objectId]
    if objectData and objectData.questRelevant then
        return true
    end

    if not learned.quests then
        return false
    end

    for _, qData in pairs(learned.quests) do
        if qData[2] and qData[2][2] then
            for _, entry in ipairs(qData[2][2]) do
                local entryId = type(entry) == "table" and entry[1] or entry
                if entryId == objectId then
                    return true
                end
            end
        end
        if qData[3] and qData[3][2] then
            for _, entry in ipairs(qData[3][2]) do
                local entryId = type(entry) == "table" and entry[1] or entry
                if entryId == objectId then
                    return true
                end
            end
        end
        if qData[10] and qData[10][2] then
            for _, entry in ipairs(qData[10][2]) do
                local entryId = type(entry) == "table" and entry[1] or entry
                if entryId == objectId then
                    return true
                end
            end
        end
    end

    return false
end

HasQuestNpcGiverReferences = function(npcId)
    local learned = Questie and Questie.dbLearner and Questie.dbLearner.global
    if not learned or not learned.quests then
        return false
    end

    for _, qData in pairs(learned.quests) do
        if qData[2] and qData[2][1] then
            for _, entry in ipairs(qData[2][1]) do
                local entryId = type(entry) == "table" and entry[1] or entry
                if entryId == npcId then
                    return true
                end
            end
        end
        if qData[3] and qData[3][1] then
            for _, entry in ipairs(qData[3][1]) do
                local entryId = type(entry) == "table" and entry[1] or entry
                if entryId == npcId then
                    return true
                end
            end
        end
    end

    return false
end

HasQuestObjectGiverReferences = function(objectId)
    local learned = Questie and Questie.dbLearner and Questie.dbLearner.global
    if not learned or not learned.quests then
        return false
    end

    for _, qData in pairs(learned.quests) do
        if qData[2] and qData[2][2] then
            for _, entry in ipairs(qData[2][2]) do
                local entryId = type(entry) == "table" and entry[1] or entry
                if entryId == objectId then
                    return true
                end
            end
        end
        if qData[3] and qData[3][2] then
            for _, entry in ipairs(qData[3][2]) do
                local entryId = type(entry) == "table" and entry[1] or entry
                if entryId == objectId then
                    return true
                end
            end
        end
    end

    return false
end

HasQuestNpcReferences = function(npcId)
    local learned = Questie and Questie.dbLearner and Questie.dbLearner.global
    if not learned or not learned.quests then
        return false
    end

    for _, qData in pairs(learned.quests) do
        if qData[2] and qData[2][1] then
            for _, entry in ipairs(qData[2][1]) do
                local entryId = type(entry) == "table" and entry[1] or entry
                if entryId == npcId then
                    return true
                end
            end
        end
        if qData[3] and qData[3][1] then
            for _, entry in ipairs(qData[3][1]) do
                local entryId = type(entry) == "table" and entry[1] or entry
                if entryId == npcId then
                    return true
                end
            end
        end
        if qData[10] and qData[10][1] then
            for _, entry in ipairs(qData[10][1]) do
                local entryId = type(entry) == "table" and entry[1] or entry
                if entryId == npcId then
                    return true
                end
            end
        end
    end

    return false
end

function QuestieLearner:LearnItem(itemId, name, itemLevel, requiredLevel, itemClass, itemSubClass)
    if not self:IsEnabled() then return end
    if not Questie.dbLearner.global.settings.learnItems then return end
    itemId = tonumber(itemId)
    if not itemId or itemId <= 0 then return end
    if not IsQuestRelevantItem(itemId, itemClass) then
        return false
    end

    local existing = Questie.dbLearner.global.items[itemId]
    local isNew = existing == nil
    if not existing then
        existing = {}
        Questie.dbLearner.global.items[itemId] = existing
    end

    if itemClass == 12 or HasQuestReferences(itemId) then
        existing.questRelevant = true
    end

    if name         and not existing[1]  then existing[1]  = name end
    if itemLevel    and itemLevel > 0    and not existing[9]  then existing[9]  = itemLevel end
    if requiredLevel and requiredLevel > 0 and not existing[10] then existing[10] = requiredLevel end
    if itemSubClass and not existing[13] then existing[13] = itemSubClass end
 
    existing.ls = time() -- Update last seen
    existing.mc = (existing.mc or 0) + 1

    -- Live injection into itemDataOverrides so QueryItemSingle works without reload
    if self:IsLearnerLiveEnabled() and QuestieDB and QuestieDB.itemDataOverrides then
        local ovr = QuestieDB.itemDataOverrides[itemId]
        if not ovr then
            QuestieDB.itemDataOverrides[itemId] = existing
        else
            for k, v in pairs(existing) do
                if ovr[k] == nil and not IsAscensionProtected("ITEM", itemId, k) then ovr[k] = v end
            end
        end
        if QuestieDB.private and QuestieDB.private.itemCache then
            QuestieDB.private.itemCache[itemId] = nil
        end
    end

    if isNew then
        Questie:Debug(Questie.DEBUG_LEARNER, "[QuestieLearner] New item learned:", itemId, name or "?")
        CrossLinkAfterItem(itemId)
    end
    _Learner:BroadcastIfCommsAvailable("ITEM", itemId, existing)
    return true
end

function QuestieLearner:LearnItemDrop(itemId, npcId)
    if not self:IsEnabled() then return end
    if not Questie.dbLearner.global.settings.learnItems then return end
    itemId, npcId = tonumber(itemId), tonumber(npcId)
    if not itemId or itemId <= 0 or not npcId or npcId <= 0 then return end

    local existing = Questie.dbLearner.global.items[itemId]
    if not existing then
        existing = {}
        Questie.dbLearner.global.items[itemId] = existing
    end

    existing.ls = time() -- Update last seen

    existing[2] = existing[2] or {}
    for _, id in ipairs(existing[2]) do
        if id == npcId then return end
    end
    table.insert(existing[2], npcId)

    -- Live injection: sync drop list to itemDataOverrides
    if self:IsLearnerLiveEnabled() and QuestieDB and QuestieDB.itemDataOverrides and not IsAscensionProtected("ITEM", itemId, 2) then
        local ovr = QuestieDB.itemDataOverrides[itemId] or {}
        QuestieDB.itemDataOverrides[itemId] = ovr
        ovr[2] = ovr[2] or {}
        local found = false
        for _, id in ipairs(ovr[2]) do
            if id == npcId then found = true; break end
        end
        if not found then table.insert(ovr[2], npcId) end
        if QuestieDB.private and QuestieDB.private.itemCache then
            QuestieDB.private.itemCache[itemId] = nil
        end
    end

    -- New drop relationship: re-run item cross-link to chain drop NPC → quest objectives
    CrossLinkAfterItem(itemId)
end

------------------------------------------------------------------------
-- Object learning
------------------------------------------------------------------------

function QuestieLearner:LearnObject(objectId, name, spawnX, spawnY, spawnZoneId, questRelevant)
    if not self:IsEnabled() then return false end
    if not Questie.dbLearner.global.settings.learnObjects then return false end
    objectId = tonumber(objectId)
    if not objectId or objectId <= 0 then return false end

    if not (questRelevant or HasQuestObjectReferences(objectId)) then
        return false
    end

    local zoneId = NormalizeSpawnZoneKey(spawnZoneId or GetZoneId())
    local x, y   = spawnX, spawnY
    if not x or not y then
        x, y = GetPlayerCoords()
    end

    local existing = Questie.dbLearner.global.objects[objectId]
    local isNew = existing == nil
    if not existing then
        existing = {}
        Questie.dbLearner.global.objects[objectId] = existing
    end

    existing.questRelevant = true

    if name   and not existing[1] then existing[1] = name end
    if zoneId and zoneId > 0 and not existing[5] then existing[5] = zoneId end

    if x and y and zoneId and zoneId > 0 then
        existing[4] = existing[4] or {}
        existing[4][zoneId] = existing[4][zoneId] or {}
        InsertIfNewBucket(existing[4][zoneId], x, y)
    end
 
    existing.ls = time() -- Update last seen
    existing.mc = (existing.mc or 0) + 1

    -- Live injection into objectDataOverrides so QueryObjectSingle works without reload.
    -- Same three-mode semantics as the NPC path.
    if self:IsLearnerLiveEnabled() and QuestieDB and QuestieDB.objectDataOverrides then
        local ovr = QuestieDB.objectDataOverrides[objectId]
        local allowQuestGiverSpawns = HasQuestObjectGiverReferences and HasQuestObjectGiverReferences(objectId)
        if not ovr then
            -- Learner: use learner data exclusively. Auto/static: strip learner
            -- spawns for AscensionDB-curated objects unless the learner
            -- explicitly tied this entity to a starter/finisher arrow.
            if AscensionOwnsObjectSpawns(objectId) and not allowQuestGiverSpawns then
                QuestieDB.objectDataOverrides[objectId] = DeepCopy(CopyWithoutField(existing, 4))
            else
                QuestieDB.objectDataOverrides[objectId] = existing
            end
        else
            for k, v in pairs(existing) do
                if ovr[k] == nil and not IsAscensionProtected("OBJECT", objectId, k) then ovr[k] = v end
            end
            -- Merge spawn coords: learner mode bypasses (IsAscensionProtected=false),
            -- auto/static protects curated spawns. allowSpawnMerge bypass removed.
            if existing[4] and (allowQuestGiverSpawns or not IsAscensionProtected("OBJECT", objectId, 4)) then
                ovr[4] = ovr[4] or {}
                for zid, coords in pairs(existing[4]) do
                    ovr[4][zid] = ovr[4][zid] or {}
                    for _, coord in ipairs(coords) do
                        InsertIfNewBucket(ovr[4][zid], coord[1], coord[2])
                    end
                end
            end
        end
        -- Clear compiled DB cache so GetObject rebuilds with the new override data.
        if QuestieDB.private and QuestieDB.private.objectCache then
            QuestieDB.private.objectCache[objectId] = nil
        end
    end

    if isNew then
        Questie:Debug(Questie.DEBUG_LEARNER, "[QuestieLearner] New object learned:", objectId, name or "?")
        CrossLinkAfterObject(objectId)
    end
    _Learner:BroadcastIfCommsAvailable("OBJECT", objectId, existing)
    return true
end

------------------------------------------------------------------------
-- InjectLearnedData — pushes learnedData into QuestieDB overrides
------------------------------------------------------------------------

function QuestieLearner:Sanitize(data)
    if not data or type(data) ~= "table" then return end

    -- De-duplicate coordinates if any
    -- NPCs: key 7, Objects: key 4
    for _, coordKey in ipairs({7, 4}) do
        if data[coordKey] and type(data[coordKey]) == "table" then
            for zoneId, coords in pairs(data[coordKey]) do
                local unique = {}
                -- Use the SAME per-zone grid the coords were stored with. The flat
                -- COORD_GRID (2.0) is too coarse for tightly-packed zones like Sunstrider
                -- Isle, whose grid is 0.5 — sanitizing at 2.0 collapsed distinct learned
                -- spawns into fewer pins on every InjectLearnedData.
                local grid = GetCoordGridForZone(zoneId)
                for _, c in ipairs(coords) do
                    local bx, by = floor(c[1] / grid) * grid, floor(c[2] / grid) * grid
                    local key = bx .. "," .. by
                    if not unique[key] then
                        unique[key] = c
                    end
                end
                local newList = {}
                for _, c in pairs(unique) do table.insert(newList, c) end
                data[coordKey][zoneId] = newList
            end
        end
    end

    -- Trim name/text strings
    if data[1] and type(data[1]) == "string" then
        data[1] = string_trim(data[1])
    end

    return data
end

function QuestieLearner:InjectLearnedData()
    if not EnsureLearnedData() then return end
    if not self:IsEnabled() then
        QuestieLearner.data = Questie.dbLearner.global
        Questie:Debug(Questie.DEBUG_INFO, "[QuestieLearner] InjectLearnedData skipped because learner is disabled")
        return
    end

    local mode = self:GetDataSourceMode()
    if mode == "static" or mode == "none" then
        QuestieLearner.data = Questie.dbLearner.global
        Questie:Debug(Questie.DEBUG_INFO, "[QuestieLearner] InjectLearnedData skipped because data source mode is", mode)
        return
    end

    local learned = Questie.dbLearner.global
    -- Normalize malformed saved variables before any migration or injection.
    -- This prevents old learner rows from carrying numeric spawn fields
    -- into the suppression path and crashing the quest objective filter.
    local sanitizedEntries = 0
    if QuestieDB and QuestieDB.private and QuestieDB.private.NormalizeLearnerSpawnEntry then
        for _, data in pairs(learned.npcs) do
            if QuestieDB.private.NormalizeLearnerSpawnEntry(data, 7, 4) then
                sanitizedEntries = sanitizedEntries + 1
            end
        end
        for _, data in pairs(learned.objects) do
            if QuestieDB.private.NormalizeLearnerSpawnEntry(data, 4, 7) then
                sanitizedEntries = sanitizedEntries + 1
            end
        end
        if sanitizedEntries > 0 then
            Questie:Debug(Questie.DEBUG_INFO, "[QuestieLearner] Sanitized", sanitizedEntries, "malformed learned spawn entries")
        end
    end

    -- Migrate old-format NPC data ([4]=spawns, [5]=zoneId) to new format ([7]=spawns, [9]=zoneId)
    -- Always merge [4] into [7], even when [7] already has partial data from a recent session.
    for npcId, data in pairs(learned.npcs) do
        if type(data[4]) == "table" then
            if data[7] == nil then
                -- Simple move: no [7] exists yet
                data[7] = data[4]
            else
                -- Merge: [7] has partial data, consolidate [4] coordinates into it
                for zoneId, coords in pairs(data[4]) do
                    data[7][zoneId] = data[7][zoneId] or {}
                    for _, coord in ipairs(coords) do
                        InsertIfNewBucket(data[7][zoneId], coord[1], coord[2])
                    end
                end
            end
            data[4] = nil
        end
        if type(data[5]) == "number" and data[9] == nil then
            data[9] = data[5]
            data[5] = nil
        end
    end

    -- Merge character-specific learned NPC data into global pool
    if Questie.db and Questie.db.char and Questie.db.char.npcs then
        for npcId, data in pairs(Questie.db.char.npcs) do
            local globalData = learned.npcs[npcId]
            if not globalData then
                learned.npcs[npcId] = data
            else
                -- Merge spawns: char data may be old ([4]) or new ([7]) format
                local charSpawns = data[7] or data[4]
                local globalSpawns = globalData[7] or globalData[4]
                if charSpawns then
                    if not globalSpawns then
                        globalData[7] = {}
                        globalSpawns = globalData[7]
                    end
                    for zoneId, coords in pairs(charSpawns) do
                        globalSpawns[zoneId] = globalSpawns[zoneId] or {}
                        for _, coord in ipairs(coords) do
                            InsertIfNewBucket(globalSpawns[zoneId], coord[1], coord[2])
                        end
                    end
                end
                -- Adopt zoneId if missing
                if not globalData[9] and data[9] then globalData[9] = data[9] end
                if not globalData[5] and data[5] then globalData[5] = data[5] end
            end
        end
        Questie.db.char.npcs = nil
    end

    local npcCount, questCount, itemCount, objectCount = 0, 0, 0, 0

    -- Snapshot each NPC's spawn ([7]) keys in their NATIVE uiMapId space BEFORE the
    -- uiMapId->areaId migration below rewrites them. The pin renderer/override layer
    -- expects native uiMapId keys (e.g. Sunstrider 1241), exactly as the live
    -- _MergeSpawnEvidence kill path stores them. We must NOT convert these keys to/from
    -- areaId on restore: uiMapId 1241 resolves to the Eversong PARENT areaId 3430, which
    -- maps to the Eversong map 1941 — that would place Sunstrider pins on the wrong map
    -- (the NE-corner bug). Instead we keep the native key and let HBD
    -- ResolveZone()/isSameZoneSpace handle Eversong<->Sunstrider cross-map visibility.
    local nativeNpcSpawns = {}
    for npcId, data in pairs(learned.npcs) do
        if type(data[7]) == "table" and next(data[7]) then
            local snap = {}
            for zoneId, coords in pairs(data[7]) do
                if type(coords) == "table" then
                    local zsnap = {}
                    for _, coord in ipairs(coords) do
                        if type(coord) == "table" and coord[1] and coord[2] then
                            zsnap[table.getn(zsnap) + 1] = { coord[1], coord[2], coord[3] }
                        end
                    end
                    if table.getn(zsnap) > 0 then snap[zoneId] = zsnap end
                end
            end
            if next(snap) then nativeNpcSpawns[tonumber(npcId) or npcId] = snap end
        end
    end

    -- Migration: normalize legacy areaId spawn keys to the canonical uiMapId render key.
    -- The pin pipeline (DrawWorldIcon / HBD) keys spawns by uiMapId (Sunstrider 1241,
    -- Eversong 1941). Some old learner rows stored coords under the AREA id (3431/3430)
    -- instead, so convert those forward to the uiMapId via NormalizeSpawnZoneKey.
    --
    -- CRITICAL: keys that are ALREADY uiMapIds (1241, 1941) must be left untouched. The
    -- previous version of this code did the reverse — it ran GetAreaIdByUiMapId(1241),
    -- which returns the Eversong PARENT areaId 3430, and moved Sunstrider coords there
    -- (rendering them on the wrong map / NE corner) while InsertIfNewBucket silently
    -- deduped distinct coords down. That corrupted the saved learner data on every
    -- InjectLearnedData. Never convert a uiMapId to an areaId here.
    local zonesFixed = 0
    for npcId, data in pairs(learned.npcs) do
        if data[7] then
            local zonesToMigrate = {}
            for zoneKey, coords in pairs(data[7]) do
                -- Any spawn under the Eversong PARENT areaId 3430 is mis-stored Sunstrider
                -- data: legitimate Eversong coords are keyed by uiMapId 1941, never 3430 (3430
                -- only appears via the old uiMapId->areaId bug, which mangled Sunstrider's
                -- 1241). Move it to Sunstrider's uiMapId 1241.
                if zoneKey == 3430 then
                    zonesToMigrate[zoneKey] = 1241
                else
                    local normalized = NormalizeSpawnZoneKey(zoneKey)
                    if normalized and normalized ~= zoneKey then
                        zonesToMigrate[zoneKey] = normalized
                    end
                end
            end
            for oldKey, newKey in pairs(zonesToMigrate) do
                local coords = data[7][oldKey]
                if coords then
                    data[7][newKey] = data[7][newKey] or {}
                    for _, coord in ipairs(coords) do
                        InsertIfNewBucket(data[7][newKey], coord[1], coord[2])
                    end
                    data[7][oldKey] = nil
                    zonesFixed = zonesFixed + 1
                end
            end
        end
    end
    -- Same migration for object spawn data (field 4) — areaId -> uiMapId, never the reverse.
    for objId, data in pairs(learned.objects) do
        if data[4] then
            local zonesToMigrate = {}
            for zoneKey, coords in pairs(data[4]) do
                -- Same rule as NPCs: spawns under Eversong parent areaId 3430 are mis-stored
                -- Sunstrider data (e.g. object 180516 "Shrine of Dath'Remar") -> uiMapId 1241.
                if zoneKey == 3430 then
                    zonesToMigrate[zoneKey] = 1241
                else
                    local normalized = NormalizeSpawnZoneKey(zoneKey)
                    if normalized and normalized ~= zoneKey then
                        zonesToMigrate[zoneKey] = normalized
                    end
                end
            end
            for oldKey, newKey in pairs(zonesToMigrate) do
                local coords = data[4][oldKey]
                if coords then
                    data[4][newKey] = data[4][newKey] or {}
                    for _, coord in ipairs(coords) do
                        InsertIfNewBucket(data[4][newKey], coord[1], coord[2])
                    end
                    data[4][oldKey] = nil
                    zonesFixed = zonesFixed + 1
                end
            end
        end
    end
    if zonesFixed > 0 then
        Questie:Debug(Questie.DEBUG_INFO, "[QuestieLearner] Migrated", zonesFixed, "legacy areaId spawn zone keys to uiMapId")
    end

    -- Normalize the [9] (NPC) / [5] (Object) home-zone field to the canonical uiMapId,
    -- matching the spawn keys and how LearnNPC/LearnObject now store it. Legacy areaIds
    -- (e.g. 3431) become uiMapIds (1241); values that are already uiMapIds are left alone.
    -- (The previous version forced these to the Eversong parent areaId 3430, which broke
    -- IsSunstriderNativeZone detection for Sunstrider rows.)
    local fieldsFixed = 0
    for npcId, data in pairs(learned.npcs) do
        if type(data[9]) == "number" then
            local normalized = (data[9] == 3430) and 1241 or NormalizeSpawnZoneKey(data[9])
            if normalized and normalized ~= data[9] then
                Questie:Debug(Questie.DEBUG_INFO, "[QuestieLearner] NPC", npcId, "zone field [9]", data[9], "->", normalized)
                data[9] = normalized
                fieldsFixed = fieldsFixed + 1
            end
        end
    end
    for objId, data in pairs(learned.objects) do
        if type(data[5]) == "number" then
            local normalized = (data[5] == 3430) and 1241 or NormalizeSpawnZoneKey(data[5])
            if normalized and normalized ~= data[5] then
                Questie:Debug(Questie.DEBUG_INFO, "[QuestieLearner] Object", objId, "zone field [5]", data[5], "->", normalized)
                data[5] = normalized
                fieldsFixed = fieldsFixed + 1
            end
        end
    end
    if fieldsFixed > 0 then
        Questie:Debug(Questie.DEBUG_INFO, "[QuestieLearner] Normalized", fieldsFixed, "home-zone fields to uiMapId")
    end

    -- Purge player-spawned totems from learned NPCs (they are not real world spawns)
    -- Also purge NPCs with entirely empty spawn data (stale learner artifacts)
    local purgedNpcs = 0
    local PLAYER_SPAWNED_NPCS = {
        [2523] = true,    -- Searing Totem
        [2630] = true,    -- Earthbind Totem
        [10183] = true,   -- Moonflare Totem
        [1103907] = true, -- Healing Stream Totem III
        [1107398] = true, -- Stoneclaw Totem V
    }
    for npcId, data in pairs(learned.npcs) do
        if PLAYER_SPAWNED_NPCS[npcId] then
            learned.npcs[npcId] = nil
            purgedNpcs = purgedNpcs + 1
            Questie:Debug(Questie.DEBUG_INFO, "[QuestieLearner] Purged player-spawned NPC", npcId, data[1] or "?")
        elseif IsCritterNpc(npcId) then
            -- Critters are never quest-relevant; drop any that were recorded before
            -- critter filtering existed.
            learned.npcs[npcId] = nil
            purgedNpcs = purgedNpcs + 1
            Questie:Debug(Questie.DEBUG_INFO, "[QuestieLearner] Purged critter NPC", npcId, data[1] or "?")
        elseif data[7] then
            -- Check for empty spawn table (no coords at all = stale learner artifact).
            -- Only purge if the NPC has no other useful state — keep entries that
            -- still have a name, home zone, recorded kills, or quest references,
            -- so a kill recorded with no position (e.g. party-kill position
            -- attribution, or pre-record normalization) doesn't drop the whole row.
            local hasCoords = false
            for _zoneKey, coords in pairs(data[7]) do
                if type(coords) == "table" and #coords > 0 then
                    hasCoords = true
                    break
                end
            end
            if not hasCoords then
                local hasName = type(data[1]) == "string" and data[1] ~= ""
                local hasZone = type(data[9]) == "number"
                local hasKills = (tonumber(data.mc) or 0) > 0
                local hasQuests = type(data[10]) == "table" and next(data[10]) ~= nil
                if not hasName and not hasZone and not hasKills and not hasQuests then
                    learned.npcs[npcId] = nil
                    purgedNpcs = purgedNpcs + 1
                    Questie:Debug(Questie.DEBUG_INFO, "[QuestieLearner] Purged NPC with empty spawns and no other state", npcId, "?")
                else
                    -- Drop the empty [7] table so it doesn't trip future checks
                    data[7] = nil
                end
            end
        end
    end
    if purgedNpcs > 0 then
        Questie:Debug(Questie.DEBUG_INFO, "[QuestieLearner] Purged", purgedNpcs, "invalid NPCs from learned data")
    end

    -- Keep fallback questgiver/turn-in spawn evidence intact so learner-only
    -- mode can still render ? / ! quest icons without depending on static DB
    -- coordinates. The explicit/learned spawn paths are already isolated by
    -- spawnSource and the real kill/object evidence now carries its own tag.

    -- Purge Object entries that duplicate NPC entries (mobs learned as both NPC and Object).
    -- NPC data is richer (has names, quest IDs), so keep the NPC version and remove the Object.
    local dupObjectsRemoved = 0
    for objId, _ in pairs(learned.objects) do
        if learned.npcs[objId] then
            learned.objects[objId] = nil
            dupObjectsRemoved = dupObjectsRemoved + 1
            Questie:Debug(Questie.DEBUG_INFO, "[QuestieLearner] Removed duplicate Object", objId, "(NPC version exists)")
        end
    end
    if dupObjectsRemoved > 0 then
        Questie:Debug(Questie.DEBUG_INFO, "[QuestieLearner] Removed", dupObjectsRemoved, "Object entries that duplicate NPC entries")
    end

    -- 1. NPCs
    local npcIdsToFix = {}
    local npcNameIndexNeedsRebuild = false
    for npcId, data in pairs(learned.npcs) do
        local nid = tonumber(npcId)
        if type(npcId) == "string" and nid then
            npcIdsToFix[npcId] = nid
        end
        self:Sanitize(data)
        if not QuestieDB.npcDataOverrides[nid or npcId] then
            -- Spawn evidence is promoted through _MergeSpawnEvidence, where
            -- AscensionDB ownership is known. Injecting [7] verbatim here runs too
            -- early and can pollute curated plugin spawn tables.
            -- REGRESSION NOTE (was bug 7ce0cdc): stripping [7] here is ONLY safe
            -- because the guarded restore block BELOW re-merges the saved spawns
            -- under their NATIVE uiMapId keys (from the pre-migration snapshot
            -- nativeNpcSpawns). Do NOT delete that block, do NOT restore from the
            -- post-migration data[7] keys, do NOT convert keys via areaId (uiMapId
            -- 1241 -> areaId 3430 -> Eversong map 1941 misplaces Sunstrider pins to
            -- the NE corner), and do NOT "simplify" to defer all spawns to
            -- _MergeSpawnEvidence — that promoter only runs on LIVE kills, so
            -- prior-session spawns would never return on /reload and learner quests
            -- (e.g. 8325 -> Mana Wyrm 15274) lose pins.
            QuestieDB.npcDataOverrides[nid or npcId] = CopyWithoutField(data, 7)
            npcCount = npcCount + 1
            if data[1] then npcNameIndexNeedsRebuild = true end
        else
            local existing = QuestieDB.npcDataOverrides[nid or npcId]
            -- Adopt other fields if missing
            for k, v in pairs(data) do
                if k ~= "mc" and k ~= 7 and existing[k] == nil and not IsAscensionProtected("NPC", nid or npcId, k) then
                    existing[k] = v
                    if k == 1 then npcNameIndexNeedsRebuild = true end
                end
            end
        end

        -- Restore persisted learner spawns ([7]) into the queryable override layer.
        -- The branch above intentionally strips [7] to avoid clobbering curated
        -- plugin coords, deferring to _MergeSpawnEvidence. But _MergeSpawnEvidence
        -- only re-promotes from LIVE kill evidence, so spawns learned in a prior
        -- session never came back on /reload, and a freshly accepted quest had no
        -- pins until the mob was re-killed (e.g. quest 8325 -> Mana Wyrm 15274 on
        -- Sunstrider). Restore from the NATIVE-uiMapId snapshot captured before the
        -- migration above (do NOT read the post-migration data[7] keys, and do NOT
        -- convert them — that is what put Sunstrider pins on the Eversong map). This
        -- keys the override exactly like the live kill path, so pins render on the
        -- correct map and HBD isSameZoneSpace shows them on Eversong too. Gated by
        -- IsAscensionProtected so curated AscensionDB coords are never overwritten:
        -- in learner mode the check is always false (learner data fully restores); in
        -- auto mode only non-curated NPCs are restored. Deep-merged via InsertIfNewBucket.
        local realNpcId = nid or npcId
        local nativeSpawns = nativeNpcSpawns[realNpcId]
        -- Use the mode-independent ownership check: AscensionDB-curated NPC spawns
        -- (e.g. Sunstrider Mana Wyrm) must never be overlaid with learner coords, even
        -- in learner mode where IsAscensionProtected would return false.
        if nativeSpawns and not AscensionOwnsNpcSpawns(realNpcId) then
            local ovr = QuestieDB.npcDataOverrides[realNpcId]
            ovr[7] = ovr[7] or {}
            for zoneId, coords in pairs(nativeSpawns) do
                if type(coords) == "table" then
                    ovr[7][zoneId] = ovr[7][zoneId] or {}
                    local grid = GetCoordGridForZone(zoneId)
                    for _, coord in ipairs(coords) do
                        if type(coord) == "table" and coord[1] and coord[2] then
                            InsertIfNewBucket(ovr[7][zoneId], coord[1], coord[2], grid)
                        end
                    end
                end
            end
        end
    end
    for old, new in pairs(npcIdsToFix) do
        learned.npcs[new] = learned.npcs[old]
        learned.npcs[old] = nil
    end

    if Questie.db and Questie.db.profile and Questie.db.profile.debugEnabled then
        -- Diagnostic: log how many NPCs were injected with spawn overrides
        local spawnOverrideCount = 0
        for nid, ovr in pairs(QuestieDB.npcDataOverrides) do
            if ovr[7] and next(ovr[7]) then
                spawnOverrideCount = spawnOverrideCount + 1
            end
        end
        Questie:Debug(Questie.DEBUG_CRITICAL, "[QuestieLearner] InjectLearnedData: injected", npcCount, "NPCs (", spawnOverrideCount, "with spawn overrides)")
    end
    if npcNameIndexNeedsRebuild then
        _MarkNpcNameIndexDirty()
    end

    -- Purge garbage quest entries: quests with no name [1] and only mc/ls metadata.
    -- These are Ascension internal tracking artifacts (hash-like IDs) with no real quest data.
    -- Also purge quest 788 ("Mottled Boar slain") which is an objective text, not a quest name.
    local purgedQuests = 0
    local OBJECTIVE_TEXT_QUEST_IDS = {
        [788] = true, -- "Mottled Boar slain" — objective text, not a quest
    }
    for questId, data in pairs(learned.quests) do
        local hasRealData = false
        -- Check if quest has any meaningful data beyond mc/ls metadata
        if type(data[1]) == "string" and data[1] ~= "" then
            hasRealData = true
        end
        -- Also check for objective data, level, zone, etc.
        if not hasRealData then
            for k, v in pairs(data) do
                if k ~= "mc" and k ~= "ls" then
                    hasRealData = true
                    break
                end
            end
        end
        local qid = tonumber(questId)
        if not hasRealData or (qid and OBJECTIVE_TEXT_QUEST_IDS[qid]) then
            local reason = not hasRealData and "garbage" or "objective-text"
            Questie:Debug(Questie.DEBUG_INFO, "[QuestieLearner] Purged", reason, "quest", questId, data[1] or "?")
            learned.quests[questId] = nil
            purgedQuests = purgedQuests + 1
        end
    end
    if purgedQuests > 0 then
        Questie:Debug(Questie.DEBUG_INFO, "[QuestieLearner] Purged", purgedQuests, "invalid quests (garbage/objective-text)")
    end

    -- Infer sortKey [17] from zone data [3] for quests that have a name but no sortKey.
    -- Field [3] contains zone/area info (e.g. {{470}} for Ghostlands, {{414}} for Zul'Drak).
    -- The sortKey should be the areaId from [3] so the quest appears in the correct zone in the UI.
    local sortKeysInferred = 0
    for questId, data in pairs(learned.quests) do
        if data[1] and not data[17] and data[3] then
            -- [3] can be a table of tables: {{414}} or nested {{414, ...}, ...}
            -- Extract the first numeric areaId from it
            local sortKey = nil
            if type(data[3]) == "table" then
                -- Walk into nested tables to find the first numeric value
                local function findFirstNumber(t)
                    if type(t) ~= "table" then return nil end
                    for i = 1, #t do
                        if type(t[i]) == "number" then
                            return t[i]
                        elseif type(t[i]) == "table" then
                            local result = findFirstNumber(t[i])
                            if result then return result end
                        end
                    end
                    return nil
                end
                sortKey = findFirstNumber(data[3])
            elseif type(data[3]) == "number" then
                sortKey = data[3]
            end
            if sortKey then
                data[17] = sortKey
                sortKeysInferred = sortKeysInferred + 1
                Questie:Debug(Questie.DEBUG_INFO, "[QuestieLearner] Inferred sortKey", sortKey, "for quest", questId, data[1])
            end
        end
    end
    if sortKeysInferred > 0 then
        Questie:Debug(Questie.DEBUG_INFO, "[QuestieLearner] Inferred sortKey for", sortKeysInferred, "quests from zone data")
    end

    -- 2. Quests
    local questIdsToFix = {}
    for questId, data in pairs(learned.quests) do
        local qid = tonumber(questId)
        if type(questId) == "string" and qid then
            questIdsToFix[questId] = qid
        end
        self:Sanitize(data)
        -- Legacy cleanup for malformed objective data
        if data[10] ~= nil then
            local ok = type(data[10]) == "table"
            if ok then
                for _, v in pairs(data[10]) do
                    if type(v) ~= "table" then ok = false; break end
                end
            end
            if not ok then data[10] = nil end
        end
        if data[8] ~= nil and type(data[8]) ~= "table" then
            data[8] = nil
        end

        if not QuestieDB.questDataOverrides[qid or questId] then
            QuestieDB.questDataOverrides[qid or questId] = data
            questCount = questCount + 1
        else
            local existing = QuestieDB.questDataOverrides[qid or questId]
            for k, v in pairs(data) do
                if k ~= "mc" then
                    if k == 10 then
                        -- Special merge: add learned creatureObjective entries to [10][1]
                        if not IsAscensionProtected("QUEST", qid or questId, 10) then
                            existing[10] = existing[10] or {}
                            existing[10][1] = existing[10][1] or {}
                            if type(v[1]) == "table" then
                                for _, entry in ipairs(v[1]) do
                                    local found = false
                                    for _, ex in ipairs(existing[10][1]) do
                                        if ex[1] == entry[1] then found = true; break end
                                    end
                                    if not found then
                                        tinsert(existing[10][1], entry)
                                    end
                                end
                            end
                        end
                    elseif existing[k] == nil and not IsAscensionProtected("QUEST", qid or questId, k) then
                        existing[k] = v
                    end
                end
            end
        end
    end
    for old, new in pairs(questIdsToFix) do
        learned.quests[new] = learned.quests[old]
        learned.quests[old] = nil
    end

    -- 3. Items
    local itemIdsToFix = {}
    for itemId, data in pairs(learned.items) do
        local iid = tonumber(itemId)
        if type(itemId) == "string" and iid then
            itemIdsToFix[itemId] = iid
        end
        if HasQuestReferences(iid or itemId) then
            if not QuestieDB.itemDataOverrides[iid or itemId] then
                QuestieDB.itemDataOverrides[iid or itemId] = data
                itemCount = itemCount + 1
            end
        end
    end
    for old, new in pairs(itemIdsToFix) do
        learned.items[new] = learned.items[old]
        learned.items[old] = nil
    end

    -- 4. Objects
    local objectIdsToFix = {}
    for objectId, data in pairs(learned.objects) do
        local oid = tonumber(objectId)
        if type(objectId) == "string" and oid then
            objectIdsToFix[objectId] = oid
        end
        self:Sanitize(data)
        if HasQuestObjectReferences(oid or objectId) and not QuestieDB.objectDataOverrides[oid or objectId] then
            QuestieDB.objectDataOverrides[oid or objectId] = data
            objectCount = objectCount + 1
        else
            local existing = QuestieDB.objectDataOverrides[oid or objectId]
            if existing and data[4] and not IsAscensionProtected("OBJECT", oid or objectId, 4) then
                existing[4] = existing[4] or {}
                for zoneId, coords in pairs(data[4]) do
                    existing[4][zoneId] = existing[4][zoneId] or {}
                    for _, coord in ipairs(coords) do
                        InsertIfNewBucket(existing[4][zoneId], coord[1], coord[2])
                    end
                end
            end
            -- Adopt other fields
            if existing then
                for k, v in pairs(data) do
                    if k ~= "mc" and k ~= 4 and existing[k] == nil and not IsAscensionProtected("OBJECT", oid or objectId, k) then
                        existing[k] = v
                    end
                end
            end
        end
    end
    for old, new in pairs(objectIdsToFix) do
        learned.objects[new] = learned.objects[old]
        learned.objects[old] = nil
    end

    if npcCount > 0 or questCount > 0 or itemCount > 0 or objectCount > 0 then
        Questie:Debug(Questie.DEBUG_INFO, "[QuestieLearner] Injected learned data:",
            npcCount, "NPCs,", questCount, "quests,", itemCount, "items,", objectCount, "objects")
    end
end

------------------------------------------------------------------------
-- Stats / Export helpers
------------------------------------------------------------------------

function QuestieLearner:GetStats()
    if not EnsureLearnedData() then return 0, 0, 0, 0 end
    local learned = Questie.dbLearner.global
    local n, q, i, o = 0, 0, 0, 0
    for _ in pairs(learned.npcs)    do n = n + 1 end
    for _ in pairs(learned.quests)  do q = q + 1 end
    for _ in pairs(learned.items)   do i = i + 1 end
    for _ in pairs(learned.objects) do o = o + 1 end
    return n, q, i, o
end

function QuestieLearner:ClearAllData()
    if not EnsureLearnedData() then return end
    local learned = Questie.dbLearner.global
    local settings = learned.settings or {}

    for key in pairs(learned) do
        if key ~= "settings" then
            learned[key] = nil
        end
    end

    learned.settings = settings
    learned.npcs    = {}
    learned.quests  = {}
    learned.items   = {}
    learned.objects = {}

    self:ApplyDataSourceMode()
    NotifyLearnerOptionsChanged()
    Questie:Print("Cleared all learned data.")
end

function QuestieLearner:SerializeTable(t)
    if type(t) ~= "table" then
        if type(t) == "string" then return string.format("%q", t) end
        return tostring(t)
    end
    local parts = {}
    local isArray = #t > 0
    for k, v in pairs(t) do
        local key = isArray and "" or ("[" .. (type(k) == "string" and string.format("%q", k) or tostring(k)) .. "]=")
        table.insert(parts, key .. self:SerializeTable(v))
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

function QuestieLearner:ExportData()
    if not EnsureLearnedData() then return "" end
    local learned = Questie.dbLearner.global
    local lines = {}
    table.insert(lines, "-- QuestieLearner Export")
    local n, q, i, o = self:GetStats()
    table.insert(lines, "-- NPCs: " .. n .. "  Quests: " .. q .. "  Items: " .. i .. "  Objects: " .. o)
    table.insert(lines, "")
    table.insert(lines, "QuestieLearnerExport = {")
    table.insert(lines, "  npcs    = " .. self:SerializeTable(learned.npcs) .. ",")
    table.insert(lines, "  quests  = " .. self:SerializeTable(learned.quests) .. ",")
    table.insert(lines, "  items   = " .. self:SerializeTable(learned.items) .. ",")
    table.insert(lines, "  objects = " .. self:SerializeTable(learned.objects) .. ",")
    table.insert(lines, "}")
    return table.concat(lines, "\n")
end

------------------------------------------------------------------------
-- GUID parsing
------------------------------------------------------------------------

local HEX_PREFIXES = {
    ["F130"] = "Creature",
    ["F131"] = "Vehicle",
    ["F140"] = "GameObject",
    ["F110"] = "Creature",
    ["F111"] = "Creature",
}

local CREATURE_HEX_PREFIXES = { ["F130"]=true, ["F131"]=true, ["F110"]=true, ["F111"]=true }

local function _GetDashGuidField(guid, index)
    if not guid or type(guid) ~= "string" or index <= 0 then return nil end
    local field = 1
    local startPos = 1
    while true do
        local sepStart, sepEnd = string.find(guid, "-", startPos, true)
        if not sepStart then
            if field == index then
                return string.sub(guid, startPos)
            end
            return nil
        end
        if field == index then
            return string.sub(guid, startPos, sepStart - 1)
        end
        field = field + 1
        startPos = sepEnd + 1
    end
end

local function GetIdAndTypeFromGUID(guid)
    if not guid then return nil, nil end
    -- Modern dash-separated GUID (e.g. "Creature-0-3726-0-189-5638296-...")
    local unitType = _GetDashGuidField(guid, 1)
    local parsedId = _GetDashGuidField(guid, 6)
    local id = tonumber(parsedId)
    if id and id > 0 and unitType then
        return id, unitType
    end
    -- Legacy hex GUID
    if string.sub(guid, 1, 2) == "0x" and string.len(guid) >= 18 then
        local prefix = string.upper(string.sub(guid, 3, 6))
        local t = HEX_PREFIXES[prefix]
        if t then
            local low32 = tonumber(string.sub(guid, 11, 18), 16)
            if low32 then
                local nid = math.mod(low32, 8388608)
                if nid > 0 then return nid, t end
            end
        end
    end
    return nil, nil
end

-- Forward declarations for GUID parsing functions used by event handlers above.
-- The full implementations are at lines 1567 and 1604.
local GetNpcIdFromGUID = function(guid)
    if not guid or type(guid) ~= "string" then return nil end
    local strId = guid:match("Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)")
    if strId then return tonumber(strId) end
    if guid:match("^0x") then
        local hex = guid:sub(3)
        local prefix = hex:sub(1, 4)
        local isCreature = (
            prefix == "F130" or prefix == "F131" or
            prefix == "F110" or prefix == "F111" or
            prefix == "F150" or prefix == "F151" or
            (prefix:sub(1,1) == "F" and prefix ~= "F140" and prefix ~= "F141")
        )
        if not isCreature then return nil end
        if #hex >= 10 then
            local id = tonumber(hex:sub(5, 10), 16)
            if id and id > 0 then return id end
        end
        if #hex >= 8 then
            local id = tonumber(hex:sub(5, 8), 16)
            if id and id > 0 then return id end
        end
    end
    return nil
end

local GetObjectIdFromGUID = function(guid)
    if not guid or type(guid) ~= "string" then return nil end
    local strId = guid:match("GameObject%-%d+%-%d+%-%d+%-%d+%-(%d+)")
    if strId then return tonumber(strId) end
    if guid:match("^0x") then
        local hex = guid:sub(3)
        if #hex >= 10 then
            local id = tonumber(hex:sub(5, 10), 16)
            if id and id > 0 then return id end
        end
        if #hex >= 8 then
            local id = tonumber(hex:sub(5, 8), 16)
            if id and id > 0 then return id end
        end
    end
    return nil
end

-- Public wrappers so other modules (e.g. tooltips) can reuse the learner's robust GUID
-- parsing. These handle modern dash GUIDs AND legacy 0x hex GUIDs (and GameObject GUIDs),
-- unlike a naive strsplit("-", guid) which returns nothing for hex/object GUIDs — the cause
-- of NPC/Object IDs failing to show on some tooltips.
function QuestieLearner:GetIdAndTypeFromGUID(guid) return GetIdAndTypeFromGUID(guid) end
function QuestieLearner:GetObjectIdFromGUID(guid) return GetObjectIdFromGUID(guid) end
function QuestieLearner:GetNpcIdFromGUID(guid) return GetNpcIdFromGUID(guid) end

local function TraceLearnerEntity(source, guid, unitType, entityId, name)
    if not Questie or not Questie.Debug then return end
    local prefix = "n/a"
    if type(guid) == "string" and guid:sub(1, 2) == "0x" then
        prefix = string.upper(guid:sub(3, 6))
    end
    Questie:Debug(
        Questie.DEBUG_DEVELOP,
        "[QuestieLearner:ObjectTrace]",
        source,
        "guid=",
        tostring(guid),
        "prefix=",
        tostring(prefix),
        "unitType=",
        tostring(unitType),
        "id=",
        tostring(entityId),
        "name=",
        tostring(name)
    )
end

local function ResolveObjectName(objectId)
    if not objectId or objectId <= 0 then return nil end
    local name = QuestieDB and QuestieDB.QueryObjectSingle and QuestieDB.QueryObjectSingle(objectId, "name")
    if name and name ~= "" then return name end
    if l10n and l10n.objectNameLookup then
        for localizedName, ids in pairs(l10n.objectNameLookup) do
            if ids then
                for _, id in ipairs(ids) do
                    if id == objectId then
                        return localizedName
                    end
                end
            end
        end
    end
    return nil
end

------------------------------------------------------------------------
-- Event handlers
------------------------------------------------------------------------

-- Checks whether an NPC (by npcFlags bitmask) should be learned on mouseover.
-- Only quest givers and turn-in NPCs are relevant for the learner.
local function NpcFlagsHasQuestGiver(flags)
    if not flags then return false end
    -- bitwise AND for Lua 5.1 (no bit library guaranteed)
    return math.mod(math.floor(flags / NPC_FLAG_QUESTGIVER), 2) == 1
end

function QuestieLearner:OnMouseoverUnit()
    if not UnitExists("mouseover") or not UnitIsVisible("mouseover") then return end
    if UnitIsPlayer("mouseover") then return end

    local guid = UnitGUID("mouseover")
    if not guid then return end
    if guid == _Learner._lastMouseoverGuid then return end
    _Learner._lastMouseoverGuid = guid

    local name = UnitName("mouseover")
    local entityId, unitType = self:ResolveNpcIdFromGuidAndName(guid, name)
    TraceLearnerEntity("mouseover", guid, unitType, entityId, name)

    if not entityId or entityId <= 0 then return end
    if unitType == "GameObject" then
        self:LearnObject(entityId, name)
        return
    end
    if unitType ~= "Creature" and unitType ~= "Vehicle" then return end

    -- Flag (and purge) critters the moment we have a unit token for them, so Ascension's
    -- custom critters are excluded going forward and any already-recorded critter is removed.
    _NoteUnitCreatureType("mouseover", entityId)
    if IsCritterNpc(entityId) then return end

    -- Only learn this NPC if it carries the questgiver flag OR if it is already
    -- known in the database as a starter/finisher (so we can update its coords).
    local npcFlags = UnitNPCFlags and UnitNPCFlags("mouseover") or 0
    local isQuestGiver = NpcFlagsHasQuestGiver(npcFlags)

    if not isQuestGiver then
        -- Silently check raw table — do NOT call GetNPC which logs CRITICAL for every miss
        local rawNpc = QuestieDB and QuestieDB.npcData and QuestieDB.npcData[entityId]
        if rawNpc and (rawNpc[10] or rawNpc[11]) then
            -- known quest starter (key 10) or quest ender (key 11)
            isQuestGiver = true
        end
    end

    if not isQuestGiver then return end

    local level = UnitLevel("mouseover")
    local zoneText = GetRealZoneText()
    local areaId = _Learner.zoneCache[zoneText]
    if not areaId and l10n and l10n.GetAreaIdByLocalName then
        areaId = l10n:GetAreaIdByLocalName(zoneText)
        if areaId then
            _Learner.zoneCache[zoneText] = areaId
        end
    end
    local subName = UnitCreatureFamily and UnitCreatureFamily("mouseover") or nil
    local reaction = UnitReaction("mouseover", "player")

    local factionString = nil
    if reaction then
        if reaction >= 5 then
            factionString = UnitFactionGroup("player") == "Alliance" and "A" or "H"
        elseif reaction >= 4 then
            factionString = "AH"
        end
    end

    _Learner.guidNpcCache = _Learner.guidNpcCache or {}
    _Learner.guidNpcCache[guid] = { npcId = npcId, name = name, ts = time() }

    -- Pass areaId as spawnZoneId so LearnNPC stores spawn data under the
    -- correct areaId (3430 for Sunstrider/Eversong) rather than falling back
    -- to GetZoneId() which may return the same value but via a different path.
    -- GetPlayerCoords() fallback in LearnNPC will provide the coordinates.
    self:LearnNPC(entityId, name, level, subName, npcFlags, factionString, nil, nil, areaId)
end

function QuestieLearner:OnTargetChanged()
    if not UnitExists("target") or not UnitIsVisible("target") then return end
    if UnitIsPlayer("target") then return end

    local guid = UnitGUID("target")
    if not guid then return end
    if guid == _Learner._lastTargetGuid then return end
    _Learner._lastTargetGuid = guid

    local name = UnitName("target")
    local entityId, unitType = self:ResolveNpcIdFromGuidAndName(guid, name)
    TraceLearnerEntity("target", guid, unitType, entityId, name)

    if not entityId or entityId <= 0 then return end
    if unitType == "GameObject" then
        self:LearnObject(entityId, name)
        return
    end
    if unitType ~= "Creature" and unitType ~= "Vehicle" then return end

    -- Flag (and purge) critters as soon as we target one.
    _NoteUnitCreatureType("target", entityId)
    if IsCritterNpc(entityId) then return end

    local level = UnitLevel("target")

    _Learner.guidNpcCache = _Learner.guidNpcCache or {}
    _Learner.guidNpcCache[guid] = { npcId = entityId, name = name, ts = time() }

    -- Learn this NPC's spawn if it is a quest giver/turn-in NPC (mirrors OnMouseoverUnit).
    -- Targeting a turn-in NPC should record its location so the finisher '?' can draw, even
    -- when UPDATE_MOUSEOVER_UNIT didn't fire for it (e.g. it was click- or tab-targeted).
    local npcFlags = UnitNPCFlags and UnitNPCFlags("target") or 0
    local isQuestGiver = NpcFlagsHasQuestGiver(npcFlags)
    if not isQuestGiver then
        local rawNpc = QuestieDB and QuestieDB.npcData and QuestieDB.npcData[entityId]
        if rawNpc and (rawNpc[10] or rawNpc[11]) then -- known quest starter (10) or ender (11)
            isQuestGiver = true
        end
    end
    if isQuestGiver then
        local subName = UnitCreatureFamily and UnitCreatureFamily("target") or nil
        -- nil coords -> LearnNPC falls back to the player's position (we're at the NPC).
        self:LearnNPC(entityId, name, level, subName, npcFlags, nil, nil, nil, nil)
    end
end

-- Collects all available quest data from the quest detail/offer screen (before accepting)
function QuestieLearner:OnQuestDetail()
    local questId = GetQuestID and GetQuestID()
    if not questId or questId <= 0 then return end

    local data = {}
    data[1] = GetTitleText and GetTitleText() or nil
    -- requiredLevel [4], questLevel [5], requiredRaces [6], requiredClasses [7],
    -- and objectivesText [8] are all filled in by OnQuestAccepted from the quest log.
    -- OnQuestDetail should NOT write to those fields here — LearnQuest only writes
    -- nil values, so an early write would permanently block the correct value.

    -- [17] zoneOrSort: current zone areaId (OnQuestAccepted may overwrite with
    -- its own zoneId, which is fine — accepted is the more accurate context).
    local zoneId = GetZoneId()
    if zoneId and zoneId > 0 then
        data[17] = zoneId
    end

    self:LearnQuest(questId, data)

    -- Identify the quest giver NPC or object
    local npcGuid = UnitGUID("npc")
    if npcGuid then
        local entityId, unitType = self:ResolveNpcIdFromGuidAndName(npcGuid, UnitName("npc"))
        TraceLearnerEntity("quest_detail", npcGuid, unitType, entityId, UnitName("npc"))
        if entityId and entityId > 0 then
            local entityName = UnitName("npc")
            if unitType == "GameObject" then
                self:LearnQuestGiver(questId, entityId, 2, true)
                self:LearnObject(entityId, entityName, nil, nil, zoneId, true)
            elseif unitType == "Creature" or unitType == "Vehicle" then
                self:LearnQuestGiver(questId, entityId, 1, true)
                local npcFlags = UnitNPCFlags and UnitNPCFlags("npc") or 2
                self:LearnNPC(entityId, entityName, nil, nil, npcFlags, nil, nil, nil, zoneId)
            end
        end
    end
end

function QuestieLearner:OnQuestComplete()
    local questId = GetQuestID and GetQuestID()
    if not questId or questId <= 0 then return end

    _Learner.lastQuestComplete = {
        id = questId,
        ts = time(),
        zoneId = GetZoneId(),
    }

    -- Get current zone for quest giver spawn data
    local zoneId = GetZoneId()

    -- Capture completion/finish text
    local data = {}
    if GetRewardText then
        data[18] = GetRewardText()
    end
    self:LearnQuest(questId, data)

    -- Identify the quest turn-in NPC or object. Prefer the "npc" gossip unit, but fall back
    -- to "target" since the player is targeting the turn-in NPC and the gossip unit isn't
    -- always populated on this client.
    local unit = (UnitGUID("npc") and "npc") or (UnitGUID("target") and "target") or nil
    local npcGuid = unit and UnitGUID(unit)
    if npcGuid then
        local entityId, unitType = self:ResolveNpcIdFromGuidAndName(npcGuid, UnitName(unit))
        TraceLearnerEntity("quest_complete", npcGuid, unitType, entityId, UnitName(unit))
        if entityId and entityId > 0 then
            local entityName = UnitName(unit)
            if unitType == "GameObject" then
                self:LearnQuestGiver(questId, entityId, 2, false)
                self:LearnObject(entityId, entityName, nil, nil, zoneId, true)
            elseif unitType == "Creature" or unitType == "Vehicle" then
                self:LearnQuestGiver(questId, entityId, 1, false)
                local npcFlags = UnitNPCFlags and UnitNPCFlags(unit) or 2
                self:LearnNPC(entityId, entityName, nil, nil, npcFlags, nil, nil, nil, zoneId)
            end
        end
    end
end

-- Helper to find an NPC ID by name (case-insensitive exact match)
-- Used for proactive objective mapping when a quest is first accepted.
function QuestieLearner:GetNPCIdByName(npcName)
    if not npcName or npcName == "" then return nil end
    local lowerName = string.lower(npcName)

    local index = _EnsureNpcNameIndex()
    local overrideId = index.override[lowerName]
    if overrideId then return overrideId end
    return index.base[lowerName]
end

function QuestieLearner:ResolveNpcIdFromGuidAndName(guid, npcName)
    local entityId, unitType = GetIdAndTypeFromGUID(guid)
    if not npcName or npcName == "" then
        return entityId, unitType
    end

    local namedId = self:GetNPCIdByName(npcName)
    if not namedId or namedId <= 0 then
        return entityId, unitType
    end

    if entityId and entityId > 0 and entityId ~= namedId then
        local parsedNpc = QuestieDB and QuestieDB.GetNPC and QuestieDB:GetNPC(entityId)
        local parsedName = parsedNpc and parsedNpc.name
        if not parsedName or string.lower(parsedName) ~= string.lower(npcName) then
            return namedId, unitType
        end
    elseif not entityId or entityId <= 0 then
        return namedId, unitType
    end

    return entityId, unitType
end

local function ResolveAcceptedQuestId(firstArg, secondArg)
    local maxLog = GetNumQuestLogEntries and GetNumQuestLogEntries() or 25

    local function resolveFromLogIndex(logIndex)
        if not logIndex or type(logIndex) ~= "number" or logIndex <= 0 or logIndex > maxLog then
            return nil
        end

        local resolvedId = QuestieCompat.GetQuestIDFromLogIndex and QuestieCompat.GetQuestIDFromLogIndex(logIndex)
        if resolvedId and resolvedId > 0 then
            return resolvedId
        end
    end

    local function resolveFromQuestId(questId)
        if not questId or type(questId) ~= "number" or questId <= 0 then
            return nil
        end

        if QuestieCompat.GetQuestLogIndexByID and QuestieCompat.GetQuestLogIndexByID(questId) then
            return questId
        end
    end

    if secondArg and type(secondArg) == "number" and secondArg > 0 then
        local resolvedId = resolveFromLogIndex(secondArg) or resolveFromQuestId(secondArg)
        if resolvedId then
            return resolvedId
        end
    end

    if firstArg and type(firstArg) == "number" and firstArg > 0 then
        local resolvedId = resolveFromLogIndex(firstArg) or resolveFromQuestId(firstArg)
        if resolvedId then
            return resolvedId
        end
    end

    local selectedIndex = QuestieCompat.GetQuestLogSelection and QuestieCompat.GetQuestLogSelection()
    if selectedIndex and selectedIndex > 0 then
        return resolveFromLogIndex(selectedIndex)
    end

    return nil
end

local function ResolveTurnedInQuestId(rawQuestId)
    if rawQuestId and type(rawQuestId) == "number" and rawQuestId > 0 then
        if QuestieCompat.GetQuestLogIndexByID and QuestieCompat.GetQuestLogIndexByID(rawQuestId) then
            return rawQuestId
        end
        if _Learner.lastQuestComplete and _Learner.lastQuestComplete.id == rawQuestId then
            return rawQuestId
        end
    end

    local last = _Learner.lastQuestComplete
    if last and last.id and last.ts and (time() - last.ts) <= 10 then
        return last.id
    end

    return nil
end

-- Fires when a quest is accepted.
function QuestieLearner:OnQuestAccepted(firstArg, secondArg)
    Questie:Debug(Questie.DEBUG_INFO, "[QuestieLearner] OnQuestAccepted raw args: first=" .. tostring(firstArg) .. " second=" .. tostring(secondArg))
    local questId = ResolveAcceptedQuestId(firstArg, secondArg)

    Questie:Debug(Questie.DEBUG_INFO, "[QuestieLearner] OnQuestAccepted id=" .. tostring(questId))
    if not questId or questId <= 0 then return end

    -- Build data table from quest log (scan for matching entry).
    -- Only store fields that match the questKeys schema.
    -- Do NOT store objectives (key 10) as raw text — the DB compiler expects structured
    -- {creatureId, text} tuples; plain strings crash pairs() in GetQuest.
    --
    -- DO NOT capture requiredLevel [4], requiredRaces [6], or requiredClasses [7]
    -- from the quest log. Those represent the quest's actual requirements, not
    -- the player's. A quest shown to a Human is automatically acceptable to a
    -- Human, but it may also be acceptable to Orcs — we cannot know from the
    -- log alone. Capturing the player's race/class bit as those fields would
    -- corrupt data for any other character on the same account that loads the
    -- same SavedVariables (IsDoable would blacklist the quest for them).
    -- Similarly, requiredLevel is not exposed by GetQuestLogLeaderBoard on 3.3.5.
    local data = {}
    local logIdx = 0
    for i = 1, GetNumQuestLogEntries() do
        local title, level, suggestedGroup, isHeader, _, _, _, id = QuestieCompat.GetQuestLogTitle(i)
        if not isHeader and id == questId then
            data[1] = title
            -- [5] questLevel: level returned by GetQuestLogTitle IS the quest's own level
            data[5] = level and level > 0 and level or nil
            logIdx = i
            break
        end
    end

    -- [17] zoneOrSort: areaId from current zone name. This is the correct
    -- field for zone storage (was previously incorrectly written as [8] which
    -- is objectivesText, and as [17] with the quest description text).
    local zoneText = GetRealZoneText()
    if zoneText and zoneText ~= "" and l10n and l10n.GetAreaIdByLocalName then
        local areaId = l10n:GetAreaIdByLocalName(zoneText)
        if areaId and areaId > 0 then
            data[17] = areaId
        end
    end

    self:LearnQuest(questId, data)

    -- Proactively map objectives based on quest log text
    if logIdx == 0 then
        for i = 1, GetNumQuestLogEntries() do
            local _, _, _, isHeader, _, _, _, id = QuestieCompat.GetQuestLogTitle(i)
            if not isHeader and id == questId then
                logIdx = i
                break
            end
        end
    end

    if logIdx > 0 then
        local numObj = GetNumQuestLeaderBoards and GetNumQuestLeaderBoards(logIdx) or 0
        for j = 1, numObj do
            local objText, objType, finished = GetQuestLogLeaderBoard(j, logIdx)
            if objText and not finished and (objType == "monster" or objType == "killcredit" or objType == "object") then
                local targetName = objText:match("^%d+/%d+%s+(.+)%s*") or objText:match("^(.+):%s*%d+/%d+")
                if not targetName then
                    targetName = objText:gsub("%d+/%d+", ""):gsub("%d+", ""):gsub("[:!?,.%(%)]", ""):gsub("^%s+", ""):gsub("%s+$", "")
                end

                if targetName and targetName ~= "" then
                    local npcId = nil
                    local objectId = nil
                    -- For monster/killcredit objectives, try ID-based lookup first using quest objectives data.
                    -- This catches accept-time pins before the first kill event for quests like 8325,
                    -- where the quest log text may not normalize cleanly to the NPC name.
                    if objType == "killcredit" or objType == "monster" then
                        local quest = QuestieDB and QuestieDB.GetQuest and QuestieDB.GetQuest(questId)
                        if quest and quest.ObjectiveData and quest.ObjectiveData[j] then
                            local objData = quest.ObjectiveData[j]
                            local candidateIds = objData.IdList
                            if not candidateIds and objData.Id and objData.Id > 0 then
                                candidateIds = { objData.Id }
                            end
                            if candidateIds then
                                for _, possibleId in ipairs(candidateIds) do
                                    if possibleId and possibleId > 0 then
                                        local npc = QuestieDB:GetNPC(possibleId)
                                        if npc and npc.name and string.lower(npc.name) == string.lower(targetName) then
                                            npcId = possibleId
                                            break
                                        end
                                    end
                                end
                                -- Fallback: try first valid ID in the list even if name doesn't match
                                if not npcId then
                                    for _, possibleId in ipairs(candidateIds) do
                                        if possibleId and possibleId > 0 then
                                            local npc = QuestieDB:GetNPC(possibleId)
                                            if npc then
                                                npcId = possibleId
                                                break
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    elseif objType == "object" then
                        local now = time()
                        local bestObject = nil
                        for _, obj in pairs(_Learner.recentObjects or {}) do
                            if obj and obj.name and obj.name ~= "" and (now - (obj.ts or 0)) <= 10 then
                                local objName = string.lower(obj.name)
                                local text = string.lower(objText)
                                local target = string.lower(targetName)
                                local match = objName == target
                                    or string.find(text, objName, 1, true)
                                    or string.find(objName, text, 1, true)
                                if match and (not bestObject or (obj.ts or 0) > (bestObject.ts or 0)) then
                                    bestObject = obj
                                end
                            end
                        end
                        if bestObject and bestObject.objectId then
                            objectId = bestObject.objectId
                        end
                    end
                    -- Fallback to name-based lookup
                    if not npcId and not objectId then
                        npcId = self:GetNPCIdByName(targetName)
                    end
                    if npcId then
                        Questie:Debug(Questie.DEBUG_INFO, "[QuestieLearner] Proactively mapped objective", j, "to NPC", npcId, "(" .. targetName .. ")")
                        self:LearnQuestObjectiveNPC(questId, npcId, objText, j)
                    elseif objectId then
                        Questie:Debug(Questie.DEBUG_INFO, "[QuestieLearner] Proactively mapped objective", j, "to OBJECT", objectId, "(" .. targetName .. ")")
                        self:LearnQuestObjectiveObject(questId, objectId, objText, j)
                    end
                end
            end
        end
    end

    -- In learner mode, seed objective pins directly from the SavedVariables payload.
    -- This bypasses quest-log text sync timing and ensures quests like 8325 spawn pins
    -- immediately on accept when the objective mapping already exists in QuestieLearnerDB.
    if GetDataSourceMode() == "learner" then
        local learnedQuest = Questie and Questie.dbLearner and Questie.dbLearner.global and Questie.dbLearner.global.quests and Questie.dbLearner.global.quests[questId]
        if learnedQuest and learnedQuest.objIndex then
            local objIndex, entry = next(learnedQuest.objIndex)
            while objIndex do
                if entry and entry.id then
                    local entryId = entry.id
                    if type(entryId) == "table" then
                        entryId = entryId[1]
                    end
                    if entryId and entryId > 0 then
                        if entry.type == "object" then
                            self:LearnQuestObjectiveObject(questId, entryId, entry.text or entry.Text or "", objIndex)
                        else
                            self:LearnQuestObjectiveNPC(questId, entryId, entry.text or entry.Text or "", objIndex)
                        end
                    end
                end
                objIndex, entry = next(learnedQuest.objIndex, objIndex)
            end
        end
    end

    -- Associate the quest giver: prefer live UnitGUID("npc"), fall back to last gossip entity
    -- (for Objectives Board quests, GOSSIP_CLOSED fires before QUEST_ACCEPTED so "npc" is nil)
    local npcGuid = UnitGUID("npc")
    local giverEntity = nil

    if npcGuid then
        local entityId, unitType = self:ResolveNpcIdFromGuidAndName(npcGuid, UnitName("npc"))
        if entityId and entityId > 0 then
            giverEntity = { id = entityId, name = UnitName("npc"), unitType = unitType }
        end
    end
    if not giverEntity and _Learner._lastGossipEntity then
        giverEntity = _Learner._lastGossipEntity
    end
    if giverEntity then
        if giverEntity.unitType == "GameObject" then
            self:LearnQuestGiver(questId, giverEntity.id, 2, true)
            self:LearnObject(giverEntity.id, giverEntity.name, nil, nil, GetZoneId(), true)
        elseif giverEntity.unitType == "Creature" or giverEntity.unitType == "Vehicle" then
            self:LearnQuestGiver(questId, giverEntity.id, 1, true)
            local npcFlags = (npcGuid and UnitNPCFlags and UnitNPCFlags("npc")) or 1
            self:LearnNPC(giverEntity.id, giverEntity.name, nil, nil, npcFlags, nil, nil, nil, GetZoneId())
        end
    end
end

-- Fires when any quest is turned in (covers auto-complete quests that skip the QUEST_COMPLETE dialog)
function QuestieLearner:OnQuestTurnedIn(questId, xpReward, moneyReward)
    if not self:IsEnabled() then return end
    if not Questie.dbLearner.global.settings.learnQuests then return end
    questId = ResolveTurnedInQuestId(tonumber(questId))
    if not questId or questId <= 0 then return end

    local data = {}
    -- Capture the turn-in NPC/object. The "npc" gossip unit can already be cleared by the
    -- time QUEST_TURNED_IN fires, so fall back to "target" (the player almost always still
    -- has the turn-in NPC targeted). This is what records the finisher's spawn location.
    local unit = (UnitGUID("npc") and "npc") or (UnitGUID("target") and "target") or nil
    local npcGuid = unit and UnitGUID(unit)
    if npcGuid then
        local entityId, unitType = self:ResolveNpcIdFromGuidAndName(npcGuid, UnitName(unit))
        if entityId and entityId > 0 then
            local entityName = UnitName(unit)
            if unitType == "GameObject" then
                self:LearnQuestGiver(questId, entityId, 2, false)
                self:LearnObject(entityId, entityName, nil, nil, GetZoneId(), true)
            elseif unitType == "Creature" or unitType == "Vehicle" then
                self:LearnQuestGiver(questId, entityId, 1, false)
                local npcFlags = UnitNPCFlags and UnitNPCFlags(unit) or 2
                self:LearnNPC(entityId, entityName, nil, nil, npcFlags, nil, nil, nil, GetZoneId())
            end
        end
    end
    self:LearnQuest(questId, data)
end

-- Loot handler with async GetItemInfo retry
function QuestieLearner:OnLootOpened()
    if not self:IsEnabled() then return end
    if not Questie.dbLearner.global.settings.learnItems then return end

    local targetGuid = UnitGUID("target")
    local targetId, targetType = nil, nil
    local npcId = nil
    local objectId = nil
    if targetGuid then
        targetId, targetType = self:ResolveNpcIdFromGuidAndName(targetGuid, UnitName("target"))
        TraceLearnerEntity("loot_target", targetGuid, targetType, targetId, UnitName("target"))
        if targetType == "Creature" or targetType == "Vehicle" then
            npcId = targetId
        else
            npcId = GetNpcIdFromGUID(targetGuid)
        end
    end

    local numItems = GetNumLootItems()
    for i = 1, numItems do
        local _, lootName, _, _, lootQuality = GetLootSlotInfo(i)
        if lootName then
            local objectId = nil
            if GetLootSourceInfo then
                local sources = { GetLootSourceInfo(i) }
                local sourceCount = table.getn(sources)
                for j = 1, sourceCount, 2 do
                    local sourceGuid = sources[j]
                    local sourceQty = sources[j + 1]
                    Questie:Debug(
                        Questie.DEBUG_DEVELOP,
                        "[QuestieLearner:LootSourceTrace]",
                        "slot=",
                        i,
                        "sourceIndex=",
                        j,
                        "guid=",
                        tostring(sourceGuid),
                        "qty=",
                        tostring(sourceQty),
                        "lootName=",
                        tostring(lootName)
                    )
                    TraceLearnerEntity("loot_source", sourceGuid, nil, sourceQty, lootName)
                    if type(sourceGuid) == "string" then
                        local sourceId, sourceType = GetIdAndTypeFromGUID(sourceGuid)
                        if (sourceType == "Creature" or sourceType == "Vehicle") and sourceId and sourceId > 0 then
                            npcId = sourceId
                        elseif sourceType == "GameObject" and sourceId and sourceId > 0 then
                            objectId = sourceId
                        end
                    end
                end
            end
            local link = GetLootSlotLink(i)
            if link then
                local itemId = tonumber(string.match(link, "item:(%d+)"))
                if itemId and itemId > 0 then
                    local itemName, _, _, itemLevel, requiredLevel, _, _, _, _, _, _, itemClassId, itemSubClassId = GetItemInfo(link)
                    if itemName then
                        local learnedItem = self:LearnItem(itemId, itemName, itemLevel, requiredLevel, itemClassId, itemSubClassId)
                        if learnedItem and npcId then self:LearnItemDrop(itemId, npcId) end
                        if learnedItem and objectId then
                            self:LearnObject(objectId, nil, nil, nil, GetZoneId(), true)
                        end
                    else
                        -- GetItemInfo returned nil; queue for retry (class check happens on retry)
                        table.insert(_Learner.pendingItemLinks, { link = link, itemId = itemId, npcId = npcId, objectId = objectId })
                    end
                end
            end
        end
    end
end

function QuestieLearner:OnGameObjectUsed(objectId)
    if not self:IsEnabled() then return end
    if not Questie.dbLearner.global.settings.learnObjects then return end
    objectId = tonumber(objectId)
    if not objectId or objectId <= 0 then return end

    local objectName = ResolveObjectName(objectId)
    local x, y = GetPlayerCoords()
    local zoneId = GetZoneId()
    Questie:Debug(
        Questie.DEBUG_DEVELOP,
        "[QuestieLearner:GameObjectUsedTrace]",
        "id=",
        tostring(objectId),
        "name=",
        tostring(objectName)
    )
    TraceLearnerEntity("gameobject_used", nil, "GameObject", objectId, objectName)
    if HasQuestObjectReferences(objectId) then
        self:LearnObject(objectId, objectName, x, y, zoneId, true)
    end
    _Learner.recentObjects[objectId] = {
        objectId = objectId,
        name = objectName,
        ts = time(),
        zoneId = zoneId,
        x = x,
        y = y,
    }
end

function QuestieLearner:OnGossipShow()
    local npcGuid = UnitGUID("npc")
    if not npcGuid then return end

    local id, unitType = self:ResolveNpcIdFromGuidAndName(npcGuid, UnitName("npc"))
    if not id or id <= 0 then return end

    local name = UnitName("npc")
    TraceLearnerEntity("gossip", npcGuid, unitType, id, name)
    -- Cache the last gossip entity so OnQuestAccepted can associate it after GOSSIP_CLOSED
    _Learner._lastGossipEntity = { id = id, name = name, unitType = unitType, guid = npcGuid }

    if unitType == "GameObject" then
        self:LearnObject(id, name)
    elseif unitType == "Creature" or unitType == "Vehicle" then
        local npcFlags = UnitNPCFlags and UnitNPCFlags("npc") or 1
        self:LearnNPC(id, name, nil, nil, npcFlags, nil, nil, nil, GetZoneId())
    end
end

function QuestieLearner:LearnSpellCast(spellId, spellName, dstGUID, dstName)
    if not spellId or not spellName then return end

    local npcId = dstGUID and self:ResolveNpcIdFromGuidAndName(dstGUID, dstName)
    local objId = dstGUID and GetObjectIdFromGUID(dstGUID)

    -- Check if this spell is a quest objective
    for i = 1, GetNumQuestLogEntries() do
        local _, _, _, isHeader, _, _, _, questId = QuestieCompat.GetQuestLogTitle(i)
        if not isHeader and questId and questId > 0 then
            local quest = QuestLogCache.GetQuest(questId)
            if quest and quest.objectives then
                for _, obj in pairs(quest.objectives) do
                    -- If the objective is a spell or requires this spell
                    if obj.type == "spell" and obj.text and obj.text:find(spellName, 1, true) then
                        -- Questie:Debug(Questie.DEBUG_LEARNER, "[QuestieLearner] Learning spell cast:", spellId, spellName, "on", dstName or "nil")
                        -- Questie:Debug(Questie.DEBUG_LEARNER, "[QuestieLearner] Found spell objective match for quest", questId)
                        local data = { [10] = { [1] = {} } }
                        if npcId then
                            tinsert(data[10][1], { npcId, spellName })
                        elseif objId then
                            -- Store object as target if applicable
                            tinsert(data[10][1], { -objId, spellName })
                        end
                        self:LearnQuest(questId, data)
                    end
                end
            end
        end
    end
end

-- Resolves pending item info once the client has cached it
function QuestieLearner:OnGetItemInfoReceived(itemId)
    if not _Learner.pendingItemLinks then return end
    local remaining = {}
    for _, entry in ipairs(_Learner.pendingItemLinks) do
        if entry.itemId == itemId then
            local itemName, _, _, itemLevel, requiredLevel, _, _, _, _, _, _, itemClassId, itemSubClassId = GetItemInfo(entry.link)
            if itemName then
                local learnedItem = self:LearnItem(itemId, itemName, itemLevel, requiredLevel, itemClassId, itemSubClassId)
                if learnedItem and entry.npcId then self:LearnItemDrop(itemId, entry.npcId) end
                if learnedItem and entry.objectId then
                    self:LearnObject(entry.objectId, nil, nil, nil, GetZoneId(), true)
                end
            else
                table.insert(remaining, entry) -- still not cached, keep
            end
        else
            table.insert(remaining, entry)
        end
    end
    _Learner.pendingItemLinks = remaining
end

------------------------------------------------------------------------
-- Cache recent kills: guid → {npcId, name, x, y, zoneId, ts}
_Learner.recentKills = _Learner.recentKills or {}
_Learner.recentObjects = _Learner.recentObjects or {}
-- Previous objective counts for active quests: questId → {[idx] = count}
_Learner.prevObjCounts = _Learner.prevObjCounts or {}

function QuestieLearner:OnCombatLogEvent(timestamp, eventType, srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags, spellId, spellName)
    -- Guard: if combat log was unavailable or disabled, bail fast
    if _Learner.combatLogDisabled then return end

    -- arg1..arg10 are captured by the frame handler before calling this function.
    -- On 3.3.5a these are populated by the client engine.
    -- If timestamp was not passed (direct test call), try CombatLogGetCurrentEventInfo.
    local path
    if not timestamp then
        -- Modern path (WoW 3.3.5+): use API, skip arg globals
        if CombatLogGetCurrentEventInfo then
            local t1, t2, t3, t4, t5, t6, t7, t8, t9, t10 = CombatLogGetCurrentEventInfo()
            if t1 then
                timestamp, eventType, srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags, spellId, spellName = t1, t2, t3, t4, t5, t6, t7, t8, t9, t10
                path = "modern"
            end
        end
        -- Legacy path (3.3.5a / test): use arg1..arg10 from caller vararg
        -- On 3.3.5a the client delivers combat log fields via arg globals in the handler.
        -- When OnCombatLogEvent is called directly in test with full args, timestamp
        -- is non-nil so this branch never fires.
        if not timestamp and arg1 then
            timestamp   = arg1
            eventType   = arg2
            srcGUID     = arg3
            srcName     = arg4
            srcFlags    = arg5
            dstGUID     = arg6
            dstName     = arg7
            dstFlags    = arg8
            spellId     = arg9
            spellName   = arg10
            path = "legacy"
        elseif not timestamp then
            path = "none"
        end
    else
        -- Args passed by frame handler — 3.3.5a client path
        path = "client-arg"
    end

    -- Permanent minimal log: combat-log path, event, and target
    -- Questie:Debug(Questie.DEBUG_LEARNER, "[QuestieLearner] combat-log path=", path, " event=", eventType, " dstGUID=", dstGUID, " dstName=", dstName)

    -- Vanilla: neither modern API nor legacy args available — throttle warning, do NOT disable permanently
    if not timestamp then
        -- Only log once per 60 seconds to avoid spam during combat log silence
        local now = GetTime and GetTime() or 0
        if not _Learner.combatLogSilentUntil or (now - _Learner.combatLogSilentUntil) > 60 then
            _Learner.combatLogSilentUntil = now
            Questie:Debug(Questie.DEBUG_INFO, "[QuestieLearner] COMBAT_LOG_EVENT_UNFILTERED fired but no args available "
                .. "(CombatLogGetCurrentEventInfo=" .. tostring(CombatLogGetCurrentEventInfo ~= nil) .. ", arg1=" .. tostring(arg1) .. ") "
                .. "— combat-log kill learning skipped this event (not disabled)")
        end
        return
    end

    -- Player/group engagement tracking. Quest-progress correlation (OnQuestLogUpdate)
    -- must never attribute a *nearby* player's kill to our own objectives. We record
    -- which mobs we — or our pet/party/raid — actually damaged, so a kill is only
    -- "credited" to us if it was a PARTY_KILL or we recently engaged that GUID.
    -- This runs before the kill-event filter so damage events are captured too.
    if dstGUID and srcGUID then
        local mine = false
        local playerGUID = UnitGUID and UnitGUID("player")
        if playerGUID and srcGUID == playerGUID then
            mine = true
        elseif UnitGUID and srcGUID == UnitGUID("pet") then
            mine = true
        elseif srcFlags and bit and bit.band then
            -- Affiliation bits (mine/party/raid) flag damage from our group.
            local ours = 0
            if COMBATLOG_OBJECT_AFFILIATION_MINE  then ours = ours + COMBATLOG_OBJECT_AFFILIATION_MINE  end
            if COMBATLOG_OBJECT_AFFILIATION_PARTY then ours = ours + COMBATLOG_OBJECT_AFFILIATION_PARTY end
            if COMBATLOG_OBJECT_AFFILIATION_RAID  then ours = ours + COMBATLOG_OBJECT_AFFILIATION_RAID  end
            if ours ~= 0 and bit.band(srcFlags, ours) ~= 0 then
                mine = true
            end
        end
        if mine then
            _Learner.playerEngaged = _Learner.playerEngaged or {}
            _Learner.playerEngaged[dstGUID] = time()
        end
    end

    if eventType == "SPELL_CAST_SUCCESS" then
        if srcGUID == UnitGUID("player") then
            self:LearnSpellCast(spellId, spellName, dstGUID, dstName)
        end
        return
    end

    if eventType ~= "PARTY_KILL" and eventType ~= "UNIT_DIED" then return end
    if not dstGUID then return end

    -- Dedupe: if this GUID was processed within the last 5 seconds, skip.
    -- PARTY_KILL and UNIT_DIED can both fire for the same kill; we only need one.
    local now = time()
    local last = _Learner.killDebounce and _Learner.killDebounce[dstGUID]
    local lastTs = type(last) == "table" and last.ts or last
    local lastEventType = type(last) == "table" and last.eventType or nil
    if lastTs and (now - lastTs) < 5 then
        -- UNIT_DIED can arrive before PARTY_KILL for our own kill. Never let the
        -- bystander-safe cache path suppress the authoritative local kill event.
        if eventType ~= "PARTY_KILL" or lastEventType == "PARTY_KILL" then
            -- Questie:Debug(Questie.DEBUG_LEARNER, "[QuestieLearner] kill dedupe suppressed duplicate event=", eventType, " dstGUID=", dstGUID)
            return
        end
    end
    _Learner.killDebounce = _Learner.killDebounce or {}
    _Learner.killDebounce[dstGUID] = { ts = now, eventType = eventType }
    -- Prune entries older than 10 seconds to keep the table bounded
    for g, entry in pairs(_Learner.killDebounce) do
        local ts = type(entry) == "table" and entry.ts or entry
        if (now - ts) > 10 then
            _Learner.killDebounce[g] = nil
        end
    end
    -- Prune stale engagement entries (mobs we damaged but never finished).
    if _Learner.playerEngaged then
        for g, ts in pairs(_Learner.playerEngaged) do
            if (now - ts) > 60 then
                _Learner.playerEngaged[g] = nil
            end
        end
    end

    local npcId = self:ResolveNpcIdFromGuidAndName(dstGUID, dstName)
    local name = dstName

    -- Fallback chain for mob name: combat-log dstName → cached target/mouseover → current target unit
    if not name or name == "" then
        if _Learner.guidNpcCache then
            local cached = _Learner.guidNpcCache[dstGUID]
            if cached and cached.name and cached.name ~= "" then
                name = cached.name
            end
        end
    end
    if not name or name == "" then
        if UnitGUID("target") == dstGUID then
            name = UnitName("target")
        end
    end

    if not npcId and _Learner.guidNpcCache then
        local cached = _Learner.guidNpcCache[dstGUID]
        if cached then
            npcId = cached.npcId
        end
    end

    if not npcId or npcId <= 0 then return end

    -- If we have the dead unit as our current target, note its creature type so critters
    -- get flagged/purged; then skip recording any critter kill entirely.
    if UnitGUID and UnitGUID("target") == dstGUID then
        _NoteUnitCreatureType("target", npcId)
    end
    if IsCritterNpc(npcId) then return end

    -- Determine whether this kill is "credited" to us (our own/party kill we engaged)
    -- BEFORE using it to decide whether to record our position. This MUST come first:
    -- previously `credited` was read while still nil (defined further below), so the
    -- position-capture block never ran and kills never recorded any spawn coordinates —
    -- every killed NPC stayed spawnSource="fallback" with no [7] and drew no learner pins.
    local engagedTs = _Learner.playerEngaged and _Learner.playerEngaged[dstGUID]
    local credited = (eventType == "PARTY_KILL")
        or (engagedTs ~= nil and (now - engagedTs) <= 60)

    -- Only record YOUR position for the spawn. GetCurrentPlayerPosition()
    -- returns the local player's coords, not the killer's — so for
    -- party/raid kills where someone else landed the killing blow we
    -- must not pollute the learner's spawn map with our own location.
    local _mapId, px, py = nil, nil, nil
    if credited then
        _mapId, px, py = QuestieCompat.GetCurrentPlayerPosition()
        if px and py and px > 0 and py > 0 then
            px = floor(px * 10000) / 100
            py = floor(py * 10000) / 100
        else
            px, py = nil, nil
            -- A credited kill yielded no usable position (e.g. loading screen, or the
            -- world map is open showing another zone so GetPlayerMapPosition reads 0,0).
            -- This coordinate is silently skipped — make that visible (throttled) so a
            -- systematic capture failure is diagnosable instead of looking like
            -- "learner pins randomly missing" weeks later.
            _Learner.droppedKillCoords = (_Learner.droppedKillCoords or 0) + 1
            local nowTs = time()
            if (not _Learner.lastDroppedCoordWarn) or (nowTs - _Learner.lastDroppedCoordWarn) >= 60 then
                _Learner.lastDroppedCoordWarn = nowTs
                Questie:Debug(Questie.DEBUG_LEARNER, "[QuestieLearner] Credited kill had no usable position; coords skipped.",
                    "npcId:", npcId, "total skipped this session:", _Learner.droppedKillCoords)
            end
        end
    end
    -- Key the spawn under the SAME map space the coordinates were captured in. The
    -- coords from GetCurrentPlayerPosition() are valid in the _mapId it returns
    -- (Sunstrider parent/child correction included); deriving the key separately via
    -- GetZoneId()'s zone-name lookup can disagree with the coordinate space on
    -- subzones, storing pins on the wrong map. Only when no position was captured
    -- (px,py nil — nothing coordinate-keyed is stored) fall back to GetZoneId().
    local zoneId
    if px and py and _mapId and _mapId > 0 then
        zoneId = NormalizeSpawnZoneKey(_mapId)
    else
        zoneId = GetZoneId()
    end
    local zoneText = GetRealZoneText and GetRealZoneText() or ""
    _Learner.recentKills[dstGUID] = {
        npcId   = npcId,
        name    = name or "",
        x       = px,
        y       = py,
        zoneId  = zoneId,
        zone    = zoneText,
        ts      = time(),
        credited = credited,
    }

    if dstName and dstName ~= "" then
        -- Questie:Debug(Questie.DEBUG_LEARNER, "[QuestieLearner] Kill cached for correlation:", npcId, dstName, "@", tostring(px), tostring(py), "zone", tostring(zoneId))
    end

    -- Only record a SPAWN for kills we can actually position: our own / credited kills with
    -- a captured player position (px,py). Bystander kills — other players killing nearby mobs
    -- we never engaged — have no usable position; recording them would store OUR location as
    -- the mob's spawn and inflate the kill count (the "recording nearby player kills as my
    -- own" bug). For those we skip the spawn entirely; the NPC's name/quest data is still
    -- learned via mouseover/target. LearnNPC must NOT be called with nil px,py here, because
    -- its GetPlayerCoords fallback would re-introduce exactly that pollution.
    if px and py then
        local npcWasKnown = Questie.dbLearner.global.npcs[npcId] ~= nil
        self:LearnNPC(npcId, name, nil, nil, nil, nil, px, py, zoneId)
        if not npcWasKnown then
            Questie:Debug(Questie.DEBUG_LEARNER, "[QuestieLearner] Combat-log learned NPC:", eventType, npcId, name or "?")
        end

        -- Phase 2: store per-GUID spawn evidence for weighted merge
        self:_StoreGuidSpawnEvidence(npcId, dstGUID, zoneId, px, py)
    end
    local guidSpawnsAfterStore = Questie.dbLearner.global.npcs[npcId]
        and Questie.dbLearner.global.npcs[npcId][8]
    if guidSpawnsAfterStore then
        local guidCount = 0
        for _ in pairs(guidSpawnsAfterStore) do guidCount = guidCount + 1 end
        -- Questie:Debug(Questie.DEBUG_LEARNER,
            -- "[QuestieLearner] GUID spawn evidence stored:",
            -- npcId, dstName or name or "?",
            -- "guidCount", guidCount,
            -- "zone", tostring(zoneId),
            -- "x", tostring(px),
            -- "y", tostring(py))
    else
        -- Questie:Debug(Questie.DEBUG_LEARNER,
            -- "[QuestieLearner] GUID spawn evidence missing after store:",
            -- npcId, dstName or name or "?",
            -- "zone", tostring(zoneId),
            -- "x", tostring(px),
            -- "y", tostring(py))
    end

    -- Phase 3: weighted merge when evidence count is sufficient. The merger
    -- itself requires at least three evidence points, so avoid doing its scan
    -- on every early kill while the candidate still cannot be promoted.
    local guidSpawns = Questie.dbLearner.global.npcs[npcId]
        and Questie.dbLearner.global.npcs[npcId][8]
    if guidSpawns then
        local count = 0
        for _ in pairs(guidSpawns) do count = count + 1 end
        if self:IsLearnerLiveEnabled() and count >= 3 then
            _MergeSpawnEvidence(npcId)
        end
    end

    -- TTL cleanup: drop entries older than 10 minutes
    local now = time()
    for g, entry in pairs(_Learner.recentKills) do
        if (now - (entry.ts or 0)) > 600 then
            _Learner.recentKills[g] = nil
        end
    end
end

-- Periodic cleanup for guidNpcCache to prevent unbounded growth
function QuestieLearner:PruneGuidNpcCache()
    if not _Learner.guidNpcCache then return end
    local now = time()
    local count = 0
    -- Prune entries older than 2 hours. This is used for combat log correlation
    -- and doesn't need to persist indefinitely.
    for guid, entry in pairs(_Learner.guidNpcCache) do
        if entry.ts and (now - entry.ts) > 7200 then
            _Learner.guidNpcCache[guid] = nil
            count = count + 1
        end
    end
    if count > 0 then
        Questie:Debug(Questie.DEBUG_INFO, "[QuestieLearner] Pruned", count, "entries from guidNpcCache")
    end
end

--- Collect coord keys from a spawn table into a sequential array.
--- Uses a two-pass pattern so deletion always happens after traversal.
---@param spawnTable table  The [zoneId] sub-table containing learned coords
---@return table, number    Array of keys to remove, count of keys
--- Prune wildly outlying learned spawn coords for a single NPC+zone entry.
--- Only operates on QuestieLearner learned data (dbLearner.global.npcs / .objects).
--- Never deletes static DB or AscensionDB spawns.
--- Requires at least 4 learned points before evaluating.
--- Prunes in a second pass after identification to avoid mid-iteration deletions.
---@param spawnTable table   The [zoneId] sub-table containing learned coords
---@param zoneId number     The zone being evaluated
---@param threshold number Max percent-distance from cluster median before pruning (default 15)
---@return boolean          True if any points were removed
local function _PruneSpawnOutliers(spawnTable, zoneId, threshold)
    threshold = threshold or 15
    if not spawnTable then return false end

    -- Pass 1: collect all points into a flat array
    local learnedPoints = {}
    local n = 0
    local coordKey, coord = next(spawnTable)
    while coordKey do
        if type(coord) == "table" and coord[1] and coord[2] then
            n = n + 1
            learnedPoints[n] = { coord[1], coord[2] }
        end
        coordKey, coord = next(spawnTable, coordKey)
    end

    if n < 4 then return false end

    -- Compute median x and y via insertion sort (Lua 5.0-safe)
    local sortedX = {}
    local sortedY = {}
    for i = 1, n do
        sortedX[i] = learnedPoints[i][1]
        sortedY[i] = learnedPoints[i][2]
    end
    for i = 2, n do
        local key = sortedX[i]
        local j = i - 1
        while j >= 1 and sortedX[j] > key do
            sortedX[j + 1] = sortedX[j]
            j = j - 1
        end
        sortedX[j + 1] = key
    end
    for i = 2, n do
        local key = sortedY[i]
        local j = i - 1
        while j >= 1 and sortedY[j] > key do
            sortedY[j + 1] = sortedY[j]
            j = j - 1
        end
        sortedY[j + 1] = key
    end
    local medianX = sortedX[floor(n / 2) + 1]
    local medianY = sortedY[floor(n / 2) + 1]

    -- Compute mean absolute deviation from median for each axis
    local devX, devY = 0, 0
    for i = 1, n do
        devX = devX + abs(learnedPoints[i][1] - medianX)
        devY = devY + abs(learnedPoints[i][2] - medianY)
    end
    devX = devX / n
    devY = devY / n

    -- Dynamic axis threshold: 3x mean absolute deviation, floored to threshold
    local pruneX = devX * 3
    local pruneY = devY * 3
    if pruneX < threshold then pruneX = threshold end
    if pruneY < threshold then pruneY = threshold end

    -- Pass 2: identify outlier keys (collect before deleting)
    local toRemove = {}
    local rmCount = 0
    coordKey, coord = next(spawnTable)
    while coordKey do
        if type(coord) == "table" and coord[1] and coord[2] then
            local dx = abs(coord[1] - medianX)
            local dy = abs(coord[2] - medianY)
            if dx > pruneX or dy > pruneY then
                rmCount = rmCount + 1
                toRemove[rmCount] = coordKey
            end
        end
        coordKey, coord = next(spawnTable, coordKey)
    end

    table.sort(toRemove, function(a, b)
        if type(a) == "number" and type(b) == "number" then
            return a > b
        end
        return tostring(a) > tostring(b)
    end)

    -- Pass 3: delete in second pass (no mid-iteration table mutation).
    -- Numeric spawn arrays must be compacted so ipairs/# keep seeing later rows.
    local removed = 0
    for i = 1, rmCount do
        local key = toRemove[i]
        if type(key) == "number" then
            table.remove(spawnTable, key)
        else
            spawnTable[key] = nil
        end
        removed = removed + 1
    end

    if removed > 0 then
        Questie:Debug(Questie.DEBUG_LEARNER, "[QuestieLearner] Pruned", removed, "outlier spawns in zone", zoneId)
    end
    return removed > 0
end

--- Prune outlier learned spawn data for all NPCs and objects.
--- Only touches dbLearner.global.npcs and dbLearner.global.objects (learned data).
--- Guards static data: if a static DB entry exists for the same NPC+zone, use its
--- centroid as the anchor and prune learned entries that deviate > threshold from it.
--- If no static anchor exists, use a learned-median cluster.
--- After pruning, re-injects cleaned data into live overrides so subsequent map/arrow
--- consumers see the corrected pins immediately.
--- Runs on learner import/save/cleanup — NOT on every map draw.
---@param threshold number Max percent-distance from anchor before pruning (default 15)
---@return boolean         True if any data was changed
function QuestieLearner:PruneLearnedSpawnOutliers(threshold)
    threshold = threshold or 15

    local global = Questie.dbLearner and Questie.dbLearner.global
    if not global then return false end

    local anyChanged = false

    -- ── NPCs ──────────────────────────────────────────────────────────────
    local npcs = global.npcs
    if npcs then
        local npcId = next(npcs)
        while npcId do
            local entry = npcs[npcId]
            local spawns = entry and entry[7]
            if spawns then
                local zoneId = next(spawns)
                while zoneId do
                    local zoneSpawns = spawns[zoneId]
                    if zoneSpawns then
                        local changed = false

                        -- Check if static DB has anchors for this NPC+zone
                        local staticSpawns = nil
                        if QuestieDB and QuestieDB.QueryNPC then
                            staticSpawns = QuestieDB.QueryNPCSingle and QuestieDB.QueryNPCSingle(npcId, "spawns") or nil
                        end

                        if staticSpawns and staticSpawns[zoneId] then
                            -- Static anchor path: build centroid from static spawns
                            local sc = staticSpawns[zoneId]
                            local si, staticCoord = next(sc)
                            local sn = 0
                            local sumX, sumY = 0, 0
                            while si do
                                if type(staticCoord) == "table" and staticCoord[1] and staticCoord[2] then
                                    sn = sn + 1
                                    sumX = sumX + staticCoord[1]
                                    sumY = sumY + staticCoord[2]
                                end
                                si, staticCoord = next(sc, si)
                            end

                            if sn > 0 then
                                local anchorX = sumX / sn
                                local anchorY = sumY / sn

                                -- Collect outlier keys first, delete second
                                local toRemove = {}
                                local rmCount = 0
                                local coordKey, coord = next(zoneSpawns)
                                while coordKey do
                                    if type(coord) == "table" and coord[1] and coord[2] then
                                        local dx = abs(coord[1] - anchorX)
                                        local dy = abs(coord[2] - anchorY)
                                        if dx > threshold or dy > threshold then
                                            rmCount = rmCount + 1
                                            toRemove[rmCount] = coordKey
                                        end
                                    end
                                    coordKey, coord = next(zoneSpawns, coordKey)
                                end
                                table.sort(toRemove, function(a, b)
                                    if type(a) == "number" and type(b) == "number" then
                                        return a > b
                                    end
                                    return tostring(a) > tostring(b)
                                end)
                                for i = 1, rmCount do
                                    local key = toRemove[i]
                                    if type(key) == "number" then
                                        table.remove(zoneSpawns, key)
                                    else
                                        zoneSpawns[key] = nil
                                    end
                                    changed = true
                                end
                                if changed then
                                    Questie:Debug(Questie.DEBUG_INFO,
                                        "[QuestieLearner] Pruned", rmCount,
                                        "learned NPC", npcId, "zone", zoneId,
                                        "(deviated from static anchor)")
                                end
                            end
                        else
                            -- Learned-only path: use median cluster
                            changed = _PruneSpawnOutliers(zoneSpawns, zoneId, threshold)
                        end

                        if changed then anyChanged = true end
                    end
                    zoneId = next(spawns, zoneId)
                end
            end
            npcId = next(npcs, npcId)
        end
    end

    -- ── Objects ─────────────────────────────────────────────────────────────
    -- Learned objects store spawns in [4], not [7]
    local objects = global.objects
    if objects then
        local objectId = next(objects)
        while objectId do
            local entry = objects[objectId]
            local spawns = entry and entry[4]
            if spawns then
                local zoneId = next(spawns)
                while zoneId do
                    local zoneSpawns = spawns[zoneId]
                    if zoneSpawns then
                        if _PruneSpawnOutliers(zoneSpawns, zoneId, threshold) then
                            anyChanged = true
                        end
                    end
                    zoneId = next(spawns, zoneId)
                end
            end
            objectId = next(objects, objectId)
        end
    end

    -- Re-inject cleaned data into live overrides so subsequent reads are consistent
    if anyChanged then
        self:InjectLearnedData()
        Questie:Debug(Questie.DEBUG_INFO, "[QuestieLearner] Re-injected learned data after outlier pruning")
    end

    return anyChanged
end

-- Clear objective tracking for a specific quest
function QuestieLearner:ClearQuestObjectiveTracking(questId)
    if not questId then return end
    if _Learner.prevObjCounts and _Learner.prevObjCounts[questId] then
        _Learner.prevObjCounts[questId] = nil
        Questie:Debug(Questie.DEBUG_INFO, "[QuestieLearner] Cleared prevObjCounts for quest", questId)
    end
end

-- Fired when quest objectives update — correlate with recent kills to learn objective NPCs
function QuestieLearner:OnQuestLogUpdate()
    local numEntries = GetNumQuestLogEntries()
    for i = 1, numEntries do
        local _, _, _, isHeader, _, _, _, questId = QuestieCompat.GetQuestLogTitle(i)
        if not isHeader and questId and questId > 0 then
            local numObj = GetNumQuestLeaderBoards and GetNumQuestLeaderBoards(i) or 0
            -- Questie:Debug(Questie.DEBUG_LEARNER, "[QuestieLearner] OnQuestLogUpdate scanning quest", questId, "logIdx", i, "numObj", numObj)
            _Learner.prevObjCounts[questId] = _Learner.prevObjCounts[questId] or {}
            for j = 1, numObj do
                local objText, objType, finished = GetQuestLogLeaderBoard(j, i)
                -- Accept "monster", "item", or nil/unknown types — custom server quests
                -- may report a different type string. Skip only finished objectives.
                if not finished and objText then
                    -- Parse "Kill Felboar: 3/40" or "Felboar slain 3/40" → count = 3
                    local count = tonumber(objText:match(":?%s*(%d+)%s*/"))
                    local prev  = _Learner.prevObjCounts[questId][j]

                    -- Questie:Debug(Questie.DEBUG_LEARNER,
                        -- "[QuestieLearner] OnQuestLogUpdate quest", questId,
                        -- "obj", j, "type:", tostring(objType),
                        -- "count:", tostring(count), "prev:", tostring(prev),
                        -- "text:", tostring(objText))

                    -- Seed on first sight; only correlate on confirmed increase
                    if prev == nil then
                        _Learner.prevObjCounts[questId][j] = count or 0
                    elseif count and count > prev then
                        local now = time()
                        local bestGuid, bestKill = nil, nil
                        for guid, kill in pairs(_Learner.recentKills) do
                            -- Only correlate kills credited to us; bystander kills
                            -- (nearby players) must never be learned as our objective.
                            if kill.credited and (now - kill.ts) <= 10 then
                                if not bestKill or kill.ts > bestKill.ts then
                                    bestGuid, bestKill = guid, kill
                                end
                            end
                        end
                        if bestKill and bestKill.npcId then
                            local cleanText = objText:match("^(.-)%s*:") or (bestKill.name or "")
                            Questie:Debug(Questie.DEBUG_LEARNER,
                                "[QuestieLearner] Quest", questId, "obj", j,
                                "progressed — learning kill NPC:", bestKill.npcId, bestKill.name)
                            -- Pass exact kill coordinates so spawn list reflects NPC location, not player location
                            self:LearnNPC(bestKill.npcId, bestKill.name, nil, nil, nil, nil, bestKill.x, bestKill.y, bestKill.zoneId)
                            self:LearnQuestObjectiveNPC(questId, bestKill.npcId, cleanText, j)
                            _Learner.recentKills[bestGuid] = nil
                        end
                        _Learner.prevObjCounts[questId][j] = count
                    end
                end
            end
        end
    end
end

------------------------------------------------------------------------
-- Real-time tooltip for learned spawns
-- Hooks into GameTooltip to show "Learned spawn: (x, y) from N kills"
-- when hovering over an NPC that has been learned.
------------------------------------------------------------------------

local _tooltipHookRegistered = false
local _learnerTooltipFrame = nil

local function _CountLearnedNpcSpawns(entry)
    if not entry or not entry[7] then
        return 0
    end

    local total = 0
    for _, zoneSpawns in next, entry[7] do
        if type(zoneSpawns) == "table" then
            total = total + table.getn(zoneSpawns)
        end
    end
    return total
end

-- Replicates ElvUI's "Transparent" tooltip style so the secondary learner
-- frame matches the look of the standard GameTooltip whether or not ElvUI
-- is installed. If ElvUI IS installed, defer to its Tooltip:SetStyle (the
-- user's configured colors/fonts override our defaults).
local function _ApplyElvUIStyleTooltip(frame)
    if not frame or not frame.GetName then return end
    if ElvUI and ElvUI.GetModule then
        local ok, TT = pcall(ElvUI.GetModule, ElvUI, "Tooltip")
        if ok and TT and TT.SetStyle then
            pcall(TT.SetStyle, TT, frame)
            return
        end
    end
    -- Without ElvUI: apply the exact ElvUI "Transparent" template via the shared skinner
    -- (WHITE8X8 texture, 1-physical-pixel edge, backdropfadecolor + black border).
    if not frame.SetBackdrop then return end
    local QuestieTooltips = QuestieLoader:ImportModule("QuestieTooltips")
    if QuestieTooltips and QuestieTooltips.ApplyElvUISkin then
        QuestieTooltips:ApplyElvUISkin(frame)
    end

    -- Apply the same font ElvUI uses by default. FontTemplate isn't available
    -- without ElvUI, so set font + shadow directly.
    local fontName, fontSize = "Fonts\\FRIZQT__.TTF", 12
    local tooltipName = frame:GetName()
    if tooltipName then
        for i = 1, frame:NumLines() or 10 do
            local left = _G[tooltipName .. "TextLeft" .. i]
            local right = _G[tooltipName .. "TextRight" .. i]
            for _, region in next, {left, right} do
                if region and region.SetFont then
                    region:SetFont(fontName, fontSize, "")
                end
            end
        end
    end
end

local function _GetLearnerTooltipFrame()
    if _learnerTooltipFrame then
        -- ElvUI may have loaded after this frame was first created; re-apply
        -- the skin in that case so the secondary frame stays consistent.
        if not _learnerTooltipFrame.__questieStyled then
            _ApplyElvUIStyleTooltip(_learnerTooltipFrame)
            _learnerTooltipFrame:HookScript("OnShow", function(self)
                _ApplyElvUIStyleTooltip(self)
            end)
            _learnerTooltipFrame.__questieStyled = true
        end
        return _learnerTooltipFrame
    end

    local frame = CreateFrame("GameTooltip", "QuestieLearnerTooltip", UIParent, "GameTooltipTemplate")
    frame:SetFrameStrata("TOOLTIP")
    frame:SetClampedToScreen(true)
    frame:SetOwner(UIParent, "ANCHOR_NONE")
    -- Apply the ElvUI tooltip look now (works with or without ElvUI) and
    -- re-apply on every show so style changes / new addons don't drift.
    _ApplyElvUIStyleTooltip(frame)
    frame:HookScript("OnShow", function(self)
        _ApplyElvUIStyleTooltip(self)
    end)
    frame.__questieStyled = true
    _learnerTooltipFrame = frame
    return _learnerTooltipFrame
end

local function _HideLearnerTooltipFrame()
    if _learnerTooltipFrame then
        _learnerTooltipFrame:Hide()
    end
end

local function _ShowLearnerTooltipFrame(sourceTooltip, lines)
    local tooltip = _GetLearnerTooltipFrame()
    tooltip:ClearLines()
    tooltip:SetOwner(UIParent, "ANCHOR_NONE")
    for _, line in next, lines do
        tooltip:AddLine(line)
    end
    local QuestieTooltips = QuestieLoader:ImportModule("QuestieTooltips")
    if QuestieTooltips and QuestieTooltips.ResizeTooltip then
        QuestieTooltips:ResizeTooltip(tooltip)
    end
    local anchor = sourceTooltip or GameTooltip
    tooltip:ClearAllPoints()
    tooltip:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    tooltip:Show()
end

--- Adds a "Learned spawn: (x, y) from N kills" line to the tooltip
--- for the NPC represented by the given unit token.
--- Called by the GameTooltip OnTooltipSetUnit hook.
---@param unitToken string WoW unit token (e.g. "mouseover")
local function _AddLearnedSpawnTooltipLine(unitToken)
    if not Questie or not Questie.dbLearner then
        _HideLearnerTooltipFrame()
        return
    end
    if not QuestieLearner:CanShowLearnerTooltips() then
        _HideLearnerTooltipFrame()
        return
    end
    if not Questie.db.profile or Questie.db.profile.learnerTooltips == false then
        _HideLearnerTooltipFrame()
        return
    end
    local guid = UnitGUID(unitToken)
    if not guid then
        _HideLearnerTooltipFrame()
        return
    end

    local npcId, guidType = GetIdAndTypeFromGUID(guid)
    if guidType ~= "Creature" and guidType ~= "Vehicle" then
        _HideLearnerTooltipFrame()
        return
    end
    if not npcId then
        _HideLearnerTooltipFrame()
        return
    end

    local entry = Questie.dbLearner.global.npcs[npcId]
    if not entry or not entry[7] then
        _HideLearnerTooltipFrame()
        return
    end

    -- Find the first zone with spawn data
    local spawnsByZone = entry[7]
    local zoneId = next(spawnsByZone)
    if not zoneId then
        _HideLearnerTooltipFrame()
        return
    end

    local zoneSpawns = spawnsByZone[zoneId]
    if not zoneSpawns or #zoneSpawns == 0 then
        _HideLearnerTooltipFrame()
        return
    end

    -- Use the first recorded coordinate
    local x = zoneSpawns[1][1]
    local y = zoneSpawns[1][2]
    local kills = entry.mc or 0

    local formattedX = ("%.1f"):format(x)
    local formattedY = ("%.1f"):format(y)
    local lines = {}
    if Questie.db.profile.learnerTooltipShowSpawn ~= false then
        local text = ("(%s, %s)"):format(formattedX, formattedY)
        if Questie.db.profile.learnerTooltipShowConfidence ~= false then
            text = text .. (" from %d kill%s"):format(kills, kills == 1 and "" or "s")
        end
        lines[#lines + 1] = {"Learned spawn", text}
    end

    if Questie.db.profile.learnerTooltipShowTotalSpawns ~= false then
        lines[#lines + 1] = {"Total spawns learned", tostring(_CountLearnedNpcSpawns(entry))}
    end

    if #lines == 0 then
        _HideLearnerTooltipFrame()
        return
    end

    if Questie.db.profile.learnerTooltipUseSecondary == true then
        local rendered = {}
        -- Spacer before learner section
        rendered[#rendered + 1] = " "
        for _, pair in ipairs(lines) do
            rendered[#rendered + 1] = pair[1] .. ": " .. pair[2]
        end
        -- Data-source attribution belongs ONLY in this secondary frame, and only when the
        -- source option is enabled. It is never added to the main tooltip; when the secondary
        -- learner tooltip is disabled it does not appear at all.
        local QuestieTooltips = QuestieLoader:ImportModule("QuestieTooltips")
        local sourceLine = QuestieTooltips and QuestieTooltips.GetDataSourceLine
            and QuestieTooltips:GetDataSourceLine("m_" .. npcId)
        if sourceLine then
            rendered[#rendered + 1] = sourceLine
        end
        -- Spacer after learner section
        rendered[#rendered + 1] = " "
        _ShowLearnerTooltipFrame(GameTooltip, rendered)
    else
        -- Learner spawn/kill data is never added to the main tooltip. When the secondary
        -- learner tooltip is disabled, it is not shown anywhere (the toggle gates it).
        _HideLearnerTooltipFrame()
    end
end

--- Registers the GameTooltip OnTooltipSetUnit hook once.
--- Safe to call multiple times; guard prevents double-hook.
local function _RegisterLearnedSpawnTooltipHook()
    if _tooltipHookRegistered then return end
    _tooltipHookRegistered = true
    GameTooltip:HookScript("OnTooltipSetUnit", function()
        -- HookScript handlers do not reliably receive the frame as an argument on 3.3.5a.
        local _, unitToken = GameTooltip:GetUnit()
        if unitToken then
            _AddLearnedSpawnTooltipLine(unitToken)
        end
    end)
    GameTooltip:HookScript("OnHide", function()
        _HideLearnerTooltipFrame()
    end)
end

------------------------------------------------------------------------
-- Event registration
------------------------------------------------------------------------

function QuestieLearner:RegisterEvents()
    local frame = CreateFrame("Frame", "QuestieLearnerFrame")

    frame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
    frame:RegisterEvent("PLAYER_TARGET_CHANGED")
    frame:RegisterEvent("QUEST_DETAIL")
    frame:RegisterEvent("QUEST_COMPLETE")
    frame:RegisterEvent("QUEST_TURNED_IN")
    frame:RegisterEvent("QUEST_ACCEPTED")
    frame:RegisterEvent("LOOT_OPENED")
    frame:RegisterEvent("GOSSIP_SHOW")
    frame:RegisterEvent("GAMEOBJECT_USED")
    frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    frame:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
    frame:RegisterEvent("QUEST_REMOVED")

    frame:SetScript("OnEvent", function(_, event, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10)
        if event == "UPDATE_MOUSEOVER_UNIT" then
            self:OnMouseoverUnit()
        elseif event == "PLAYER_TARGET_CHANGED" then
            self:OnTargetChanged()
        elseif event == "QUEST_DETAIL" then
            self:OnQuestDetail()
        elseif event == "QUEST_COMPLETE" then
            self:OnQuestComplete()
        elseif event == "QUEST_TURNED_IN" then
            self:OnQuestTurnedIn(arg1, arg2, arg3)
        elseif event == "QUEST_ACCEPTED" then
            self:OnQuestAccepted(arg1, arg2)
        elseif event == "LOOT_OPENED" then
            self:OnLootOpened()
        elseif event == "GOSSIP_SHOW" then
            self:OnGossipShow()
        elseif event == "GAMEOBJECT_USED" then
            self:OnGameObjectUsed(arg1)
        elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
            -- arg1..arg10 must be captured HERE before any secondary call wipes them (3.3.5 behavior)
            -- arg1=timestamp, arg2=eventType, arg3=srcGUID, arg4=srcName, arg5=srcFlags,
            -- arg6=dstGUID, arg7=dstName, arg8=dstFlags, arg9=spellId, arg10=spellName
            self:OnCombatLogEvent(arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10)
        elseif event == "GET_ITEM_INFO_RECEIVED" then
            self:OnGetItemInfoReceived(arg1)
        elseif event == "UNIT_QUEST_LOG_CHANGED" then
            self:OnQuestLogUpdate()
        elseif event == "QUEST_REMOVED" or event == "QUEST_TURNED_IN" then
            self:ClearQuestObjectiveTracking(arg1)
        end
    end)

    Questie:Debug(Questie.DEBUG_INFO, "[QuestieLearner] Events registered")
end

------------------------------------------------------------------------
-- Initialize
------------------------------------------------------------------------

function QuestieLearner:Initialize()
    EnsureLearnedData()
    QuestieLearner.data = Questie.dbLearner.global
    self:RegisterEvents()
    self:ApplyDataSourceMode()
    _RegisterLearnedSpawnTooltipHook()

    local QuestieLearnerComms = QuestieLoader:ImportModule("QuestieLearnerComms")
    if QuestieLearnerComms and QuestieLearnerComms.Initialize then
        QuestieLearnerComms:Initialize()
    end

    -- Start periodic cleanup ticker (every 30 mins)
    QuestieCompat.C_Timer.NewTicker(1800, function()
        self:PruneGuidNpcCache()
    end)

    -- Run outlier pruning once at startup after data is loaded and DB is ready
    self:PruneLearnedSpawnOutliers()

    -- Scan existing quests in log after initialization (deferred to ensure DB is ready)
    QuestieCompat.C_Timer.After(1, function()
        self:ScanExistingQuestLog()
    end)

    Questie:Debug(Questie.DEBUG_INFO, "[QuestieLearner] Initialized")
end

function QuestieLearner:ScanExistingQuestLog()
    if not self:IsEnabled() then return end
    if not Questie.dbLearner.global.settings.learnQuests then return end
    if not GetNumQuestLogEntries then return end

    Questie:Debug(Questie.DEBUG_INFO, "[QuestieLearner] Scanning existing quest log...")
    local count = 0

    for i = 1, GetNumQuestLogEntries() do
        local title, level, _, isHeader, _, _, _, questId = QuestieCompat.GetQuestLogTitle(i)
        if not isHeader and questId and questId > 0 then
            -- Check if this quest needs objective mapping
            local existingData = Questie.dbLearner.global.quests[questId]
            local needsMapping = not existingData or not existingData.objIndex or not next(existingData.objIndex)

            if needsMapping then
                -- Use the existing OnQuestAccepted logic by manually triggering objective mapping
                local logIdx = i
                local numObj = GetNumQuestLeaderBoards and GetNumQuestLeaderBoards(logIdx) or 0
                for j = 1, numObj do
                    local objText, objType, finished = GetQuestLogLeaderBoard(j, logIdx)
                    if objText and not finished and (objType == "monster" or objType == "killcredit") then
                        local targetName = objText:match("^%d+/%d+%s+(.+)%s*") or objText:match("^(.+):%s*%d+/%d+")
                        if not targetName then
                            targetName = objText:gsub("%d+/%d+", ""):gsub("%d+", ""):gsub("[:!?,.%(%)]", ""):gsub("^%s+", ""):gsub("%s+$", "")
                        end

                        if targetName and targetName ~= "" then
                            local npcId = nil
                            -- For killcredit, try ID-based lookup first
                            if objType == "killcredit" then
                                local quest = QuestieDB and QuestieDB.GetQuest and QuestieDB.GetQuest(questId)
                                if quest and quest.ObjectiveData and quest.ObjectiveData[j] then
                                    local objData = quest.ObjectiveData[j]
                                    if objData.IdList then
                                        for _, possibleId in ipairs(objData.IdList) do
                                            if possibleId and possibleId > 0 then
                                                local npc = QuestieDB:GetNPC(possibleId)
                                                if npc and npc.name and string.lower(npc.name) == string.lower(targetName) then
                                                    npcId = possibleId
                                                    break
                                                end
                                            end
                                        end
                                        -- Fallback: try first valid ID in the list
                                        if not npcId then
                                            for _, possibleId in ipairs(objData.IdList) do
                                                if possibleId and possibleId > 0 then
                                                    local npc = QuestieDB:GetNPC(possibleId)
                                                    if npc then
                                                        npcId = possibleId
                                                        break
                                                    end
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                            -- Fallback to name-based lookup
                            if not npcId then
                                npcId = self:GetNPCIdByName(targetName)
                            end
                            if npcId then
                                Questie:Debug(Questie.DEBUG_INFO, "[QuestieLearner] Scanned existing quest", questId, "objective", j, "to NPC", npcId, "(" .. targetName .. ")")
                                self:LearnQuestObjectiveNPC(questId, npcId, objText, j)
                                count = count + 1
                            end
                        end
                    end
                end
            end
        end
    end

    if count > 0 then
        self:InjectLearnedData()
        Questie:Debug(Questie.DEBUG_INFO, "[QuestieLearner] Scanned existing quest log, mapped", count, "objectives")
    end
end

------------------------------------------------------------------------
-- Network bridge
------------------------------------------------------------------------

--- Validates learned spawn data from external sources (comms, import).
--- Returns true if the data is safe to merge; false to reject silently.
--- Checks: data is a table, spawns[zoneId] keys are numeric, coordinates
--- in each zone are numbers within 0-100 range.
---@param data table The learned entity data table (e.g. NPC entry)
---@return boolean True if valid, false if malformed
-- Validates a single coordinate table (zoneId -> { {x,y}, ... }). Absent is OK.
local function _ValidateCoordTable(spawns)
    if spawns == nil then return true end
    if type(spawns) ~= "table" then return false end
    for zoneId, zoneSpawns in pairs(spawns) do
        if type(zoneId) ~= "number" then return false end
        if type(zoneSpawns) ~= "table" then return false end
        for _, coord in ipairs(zoneSpawns) do
            if type(coord) ~= "table" then return false end
            local x, y = coord[1], coord[2]
            if type(x) ~= "number" or type(y) ~= "number" then return false end
            if x < 0 or x > 100 or y < 0 or y > 100 then return false end
        end
    end
    return true
end

local function _ValidateLearnedSpawnData(data)
    if type(data) ~= "table" then return false end
    -- NPC spawns live in key [7], object spawns in key [4]. Validate whichever is present
    -- so malformed object coordinates are rejected too (the old check only covered [7]).
    if not _ValidateCoordTable(data[7]) then return false end
    if not _ValidateCoordTable(data[4]) then return false end
    return true
end

function _Learner:BroadcastIfCommsAvailable(typ, id, data)
    if Questie and Questie.db and Questie.db.profile and Questie.db.profile.learnerBroadcast == false then
        return
    end
    if GetLearnerSetting("learnerCommsIntensity", "normal") == "off" then
        return
    end

    local QuestieLearnerComms = QuestieLoader:ImportModule("QuestieLearnerComms")
    if not (QuestieLearnerComms and QuestieLearnerComms.BroadcastLearnedData) then
        return
    end

    _Learner.pendingBroadcasts = _Learner.pendingBroadcasts or {}
    local key = typ .. ":" .. tostring(id)
    local op = (data.mc and data.mc > 1) and "UPDATE" or "NEW"
    local existingPending = _Learner.pendingBroadcasts[key]
    _Learner.pendingBroadcasts[key] = {
        typ = typ,
        id = id,
        data = data,
        -- Preserve the first-discovery signal while still sending the latest
        -- coalesced payload for the entity.
        op = (existingPending and existingPending.op == "NEW") and "NEW" or op,
    }

    if _Learner.pendingBroadcastTimer then return end

    local timer = QuestieCompat and QuestieCompat.C_Timer
    local function FlushBroadcasts()
        local pending = _Learner.pendingBroadcasts
        _Learner.pendingBroadcasts = {}
        _Learner.pendingBroadcastTimer = nil

        local comms = QuestieLoader:ImportModule("QuestieLearnerComms")
        if not (comms and comms.BroadcastLearnedData) then return end

        for _, entry in pairs(pending) do
            comms:BroadcastLearnedData(entry.op, entry.typ, entry.id, entry.data)
        end
    end

    if timer and timer.After then
        _Learner.pendingBroadcastTimer = true
        local delay = 2
        local intensity = GetLearnerSetting("learnerCommsIntensity", "normal")
        if intensity == "low" then
            delay = 4
        elseif intensity == "fast" then
            delay = 1
        end
        timer.After(delay, FlushBroadcasts)
    else
        FlushBroadcasts()
    end
end

local function _QueueIncomingNetworkMerge(typ, id, data, op)
    _Learner.pendingNetworkMerges = _Learner.pendingNetworkMerges or {}
    local key = typ .. ":" .. tostring(id)
    _Learner.pendingNetworkMerges[key] = {
        typ = typ,
        id = id,
        data = data,
        op = op,
    }

    if _Learner.pendingNetworkMergeTimer then return end

    local timer = QuestieCompat and QuestieCompat.C_Timer
    local function FlushNetworkMerges()
        local pending = _Learner.pendingNetworkMerges
        _Learner.pendingNetworkMerges = {}
        _Learner.pendingNetworkMergeTimer = nil

        local anyChanged = false
        for _, entry in pairs(pending) do
            -- Isolate each entry: a single malformed broadcast must not abort the flush
            -- and lose the rest of the batch (or break the live update loop).
            local ok, changed = pcall(QuestieLearner._ApplyIncomingNetworkMerge, QuestieLearner,
                entry.typ, entry.id, entry.data, entry.op)
            if ok then
                anyChanged = anyChanged or changed
            else
                Questie:Debug(Questie.DEBUG_INFO, "[QuestieLearner] Skipped malformed network merge",
                    tostring(entry.typ), tostring(entry.id), "-", tostring(changed))
            end
        end

        if anyChanged then
            pcall(QuestieLearner.InjectLearnedData, QuestieLearner)
            QuestieLearner.data = Questie.dbLearner.global
        end
    end

    if timer and timer.After then
        _Learner.pendingNetworkMergeTimer = true
        timer.After(GetLearnerSetting("liveNpcUpdateDelay", 0.75), FlushNetworkMerges)
    else
        FlushNetworkMerges()
    end
end

-- Receives validated, decoded data from QuestieLearnerComms or QuestieLearnerExport:MergeImport
function QuestieLearner:HandleNetworkData(typ, id, d, op)
    if not self:IsEnabled() then return end
    if not EnsureLearnedData() then return end
    if not typ or not id or not d then return end

    _QueueIncomingNetworkMerge(typ, id, d, op)
end

function QuestieLearner:_ApplyIncomingNetworkMerge(typ, id, d, op)
    if not typ or not id or not d then return false end

    local store
    if typ == "NPC" then
        if not Questie.dbLearner.global.settings.learnNpcs then return false end
        store = Questie.dbLearner.global.npcs
    elseif typ == "QUEST" then
        if not Questie.dbLearner.global.settings.learnQuests then return false end
        store = Questie.dbLearner.global.quests
    elseif typ == "ITEM" then
        if not Questie.dbLearner.global.settings.learnItems then return false end
        if not ((type(d) == "table" and d.questRelevant) or HasQuestReferences(id)) then
            return false
        end
        store = Questie.dbLearner.global.items
    elseif typ == "OBJECT" then
        if not Questie.dbLearner.global.settings.learnObjects then return false end
        if not ((type(d) == "table" and d.questRelevant) or HasQuestObjectReferences(id)) then
            return false
        end
        store = Questie.dbLearner.global.objects
    else
        return false
    end

    -- Validate external data before merging to prevent crash on malformed input
    if not _ValidateLearnedSpawnData(d) then
        Questie:Debug(Questie.DEBUG_INFO, "[QuestieLearner] Rejected malformed network data", typ, id)
        return false
    end

    local existing = store[id]
    if not existing then
        store[id] = d
        store[id].mc = 1
        if typ == "NPC" and type(d[1]) == "string" and d[1] ~= "" then
            _MarkNpcNameIndexDirty()
        end
        return true
    end

    local changed = false
    -- Merge: adopt non-nil fields we don't have locally
    for k, v in pairs(d) do
        if k ~= "mc" and existing[k] == nil then
            existing[k] = v
            changed = true
            if typ == "NPC" and k == 1 and type(v) == "string" and v ~= "" then
                _MarkNpcNameIndexDirty()
            end
        end
    end

    -- Merge coordinates
    local coordKey = (typ == "NPC") and 7 or (typ == "OBJECT" and 4 or nil)
    if coordKey and type(d[coordKey]) == "table" then
        existing[coordKey] = existing[coordKey] or {}
        local grid = GetCustomGridPrecision()
        for zoneId, coords in pairs(d[coordKey]) do
            -- Defensive: skip malformed zone keys / coord lists rather than erroring.
            if type(zoneId) == "number" and type(coords) == "table" then
                existing[coordKey][zoneId] = existing[coordKey][zoneId] or {}
                for _, coord in ipairs(coords) do
                    if type(coord) == "table" and type(coord[1]) == "number" and type(coord[2]) == "number" then
                        if InsertIfNewBucket(existing[coordKey][zoneId], coord[1], coord[2], grid) then
                            changed = true
                        end
                    end
                end
            end
        end
    end

    -- Merge item drop list
    if typ == "ITEM" and type(d[2]) == "table" then
        existing[2] = existing[2] or {}
        for _, npcId in ipairs(d[2]) do
            if type(npcId) == "number" then
                local found = false
                for _, existId in ipairs(existing[2]) do
                    if existId == npcId then found = true; break end
                end
                if not found then
                    table.insert(existing[2], npcId)
                    changed = true
                end
            end
        end
    end

    if changed or (op == "NEW" or op == "UPDATE") then
        existing.ls = time() -- Refresh timestamp on network confirmation
        existing.mc = (existing.mc or 0) + 1
        return true
    end

    return false
end

return QuestieLearner
