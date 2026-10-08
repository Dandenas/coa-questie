---@class QuestieLearnerExport
local QuestieLearnerExport = QuestieLoader:CreateModule("QuestieLearnerExport")

---@type QuestieLearner
local QuestieLearner = QuestieLoader:ImportModule("QuestieLearner")
---@type QuestieServer
local QuestieServer = QuestieLoader:ImportModule("QuestieServer")

local LibDeflate    = LibStub("LibDeflate")
local AceSerializer = LibStub("AceSerializer-3.0")

local FORMAT_PREFIX  = "QxLD"
local FORMAT_VERSION = 1
local FORMAT_SEP     = "!"
local MAX_IMPORT_LEN = 524288  -- 512 KB hard cap on raw decoded payload

local _Export = QuestieLearnerExport.private or {}
QuestieLearnerExport.private = _Export

-- Cached last export string and stats for the UI to read without re-computing
QuestieLearnerExport.lastExportString = nil
QuestieLearnerExport.lastExportStats  = nil

-- Cached last import validation result
QuestieLearnerExport.lastImportStats  = nil
QuestieLearnerExport.lastImportData   = nil

-----------------------------------------------------------------------
-- Internal helpers
-----------------------------------------------------------------------

local function CountTable(t)
    if not t then return 0 end
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local function GetServerKey()
    if QuestieServer then
        if Questie.IsAscension  then return "Ascension" end
        if Questie.IsEbonhold   then return "Ebonhold"  end
        if Questie.IsEra        then return "Era"       end
        if Questie.Is335        then return "WotLK"     end
    end
    local realm = GetRealmName and GetRealmName() or "unknown"
    return realm ~= "" and realm or "unknown"
end

function QuestieLearnerExport:GetExportTable(serverKey)
    local ld = Questie.dbLearner and Questie.dbLearner.global
    if not ld then return nil end
    if ld[serverKey] then return ld[serverKey] end
    -- Fallback: flat (pre-bucket) layout still in use
    if ld.npcs or ld.quests then return ld end
    return nil
end

-- Returns the learnedData sub-table for the current server, or nil
local function GetServerBucket(serverKey)
    return QuestieLearnerExport:GetExportTable(serverKey)
end

-- Builds a lightweight stats summary table from a bucket
local function BuildStats(bucket)
    if not bucket then return { npcs = 0, quests = 0, items = 0, objects = 0, total = 0 } end
    local s = {
        npcs    = CountTable(bucket.npcs),
        quests  = CountTable(bucket.quests),
        items   = CountTable(bucket.items),
        objects = CountTable(bucket.objects),
    }
    s.total = s.npcs + s.quests + s.items + s.objects
    return s
end

-----------------------------------------------------------------------
-- Export
-----------------------------------------------------------------------

--- Shared serialize + deflate + encode step. Wrapped defensively so any
--- malformed sub-entry surfaces as a clean error rather than a Lua error.
---@param serverKey string
---@param data table  the bucket (npcs/quests/items/objects) to encode
---@param stats table
---@return string|nil, table|string
function QuestieLearnerExport:_Encode(serverKey, data, stats)
    local payload = {
        v      = FORMAT_VERSION,
        server = serverKey,
        ts     = time and time() or 0,
        data   = data,
    }

    local ok, serialized = pcall(AceSerializer.Serialize, AceSerializer, payload)
    if not ok or type(serialized) ~= "string" then
        return nil, "Serialization failed: " .. tostring(serialized)
    end

    local compressed = LibDeflate:CompressDeflate(serialized, { level = 9 })
    if not compressed then
        return nil, "Compression failed."
    end

    local encoded = LibDeflate:EncodeForPrint(compressed)
    if not encoded then
        return nil, "Encoding failed."
    end

    local result = FORMAT_PREFIX .. ":" .. FORMAT_VERSION .. FORMAT_SEP .. encoded

    self.lastExportString = result
    self.lastExportStats  = stats

    Questie:Debug(Questie.DEBUG_DEVELOP, "[LearnerExport] Encoded", stats.total,
        "entries for", serverKey, "len:", string.len(result))

    return result, stats
end

--- Serializes + deflates + encodes the learned data for the given server key.
--- Returns the export string and a stats table, or nil + error message.
---@param serverKey string|nil  defaults to current server
---@return string|nil, table|string
function QuestieLearnerExport:Export(serverKey)
    serverKey = serverKey or GetServerKey()
    local bucket = GetServerBucket(serverKey)
    if not bucket then
        return nil, "No learned data found for server: " .. tostring(serverKey)
    end

    local stats = BuildStats(bucket)
    if stats.total == 0 then
        return nil, "Nothing to export — learned data is empty."
    end

    return self:_Encode(serverKey, bucket, stats)
end

--- Exports only the learned entries that pertain to a single zone (areaId).
--- Includes NPCs/objects that spawn in the zone, plus items dropped by those
--- NPCs and quests started/finished by those NPCs/objects, so the bundle stays
--- referentially consistent.
---@param zoneId number  areaId (defaults to the player's current zone)
---@param serverKey string|nil
---@return string|nil, table|string
function QuestieLearnerExport:ExportZone(zoneId, serverKey)
    serverKey = serverKey or GetServerKey()

    if not zoneId then
        local QuestiePlayer = QuestieLoader:ImportModule("QuestiePlayer")
        if QuestiePlayer and QuestiePlayer.GetCurrentZoneId then
            zoneId = QuestiePlayer:GetCurrentZoneId()
        end
    end
    if type(zoneId) ~= "number" or zoneId <= 0 then
        return nil, "Could not determine your current zone. Stand in a known zone and try again."
    end

    local bucket = GetServerBucket(serverKey)
    if not bucket then
        return nil, "No learned data found for server: " .. tostring(serverKey)
    end

    local out = { npcs = {}, quests = {}, items = {}, objects = {} }
    local npcSet, objSet = {}, {}

    local function ZoneHasCoords(spawns)
        if type(spawns) ~= "table" then return false end
        local zoneCoords = spawns[zoneId]
        return type(zoneCoords) == "table" and next(zoneCoords) ~= nil
    end

    -- NPCs spawning in the zone (NPC spawns live at key [7])
    for id, d in pairs(bucket.npcs or {}) do
        if type(d) == "table" and ZoneHasCoords(d[7]) then
            out.npcs[id] = d
            npcSet[id] = true
        end
    end

    -- Objects spawning in the zone (object spawns live at key [4])
    for id, d in pairs(bucket.objects or {}) do
        if type(d) == "table" and ZoneHasCoords(d[4]) then
            out.objects[id] = d
            objSet[id] = true
        end
    end

    -- Items dropped by an included NPC (item [2] = dropNpcs array)
    for id, d in pairs(bucket.items or {}) do
        if type(d) == "table" and type(d[2]) == "table" then
            for _, npcId in ipairs(d[2]) do
                if npcSet[npcId] then
                    out.items[id] = d
                    break  -- one match is enough
                end
            end
        end
    end

    -- Quests started/finished by an included NPC or object
    -- (quest [2]=startedBy{npcIds,objIds,...}, [3]=finishedBy{npcIds,objIds})
    local function AnyIn(list, set)
        if type(list) ~= "table" then return false end
        for _, v in ipairs(list) do
            if set[v] then return true end
        end
        return false
    end
    for id, d in pairs(bucket.quests or {}) do
        if type(d) == "table" then
            local started, finished = d[2], d[3]
            if (type(started) == "table" and (AnyIn(started[1], npcSet) or AnyIn(started[2], objSet)))
            or (type(finished) == "table" and (AnyIn(finished[1], npcSet) or AnyIn(finished[2], objSet))) then
                out.quests[id] = d
            end
        end
    end

    local stats = BuildStats(out)
    stats.zone = zoneId
    if stats.total == 0 then
        return nil, "Nothing learned in this zone yet."
    end

    return self:_Encode(serverKey, out, stats)
end

--- Exports ALL server buckets merged into one payload.
---@return string|nil, table|string
function QuestieLearnerExport:ExportAll()
    local ld = Questie.dbLearner and Questie.dbLearner.global
    if not ld then return nil, "No learned data." end

    local merged = { npcs = {}, quests = {}, items = {}, objects = {} }
    local function MergeBucket(b)
        if not b then return end
        for id, v in pairs(b.npcs    or {}) do merged.npcs[id]    = v end
        for id, v in pairs(b.quests  or {}) do merged.quests[id]  = v end
        for id, v in pairs(b.items   or {}) do merged.items[id]   = v end
        for id, v in pairs(b.objects or {}) do merged.objects[id] = v end
    end

    -- Flat layout
    if ld.npcs or ld.quests then
        MergeBucket(ld)
    else
        for _, bucket in pairs(ld) do
            if type(bucket) == "table" and bucket.npcs then
                MergeBucket(bucket)
            end
        end
    end

    local stats = BuildStats(merged)
    if stats.total == 0 then return nil, "Nothing to export." end

    return self:_Encode("all", merged, stats)
end

-----------------------------------------------------------------------
-- Import / Validate
-----------------------------------------------------------------------

--- Validates an import string and returns the decoded payload table,
--- or nil + error string. Does NOT merge — call MergeImport() after confirming.
---@param importStr string
---@return table|nil, string|table
function QuestieLearnerExport:ValidateImport(importStr)
    self.lastImportData  = nil
    self.lastImportStats = nil

    if not importStr or importStr == "" then
        return nil, "Empty import string."
    end

    -- Strip whitespace
    importStr = importStr:gsub("%s+", "")

    -- Check prefix (e.g. "QxLD:"). NOTE: the previous check `not str:sub(...) == x` parsed as
    -- `(not str:sub(...)) == x` which is always false, so invalid strings were never rejected.
    if importStr:sub(1, #FORMAT_PREFIX + 1) ~= (FORMAT_PREFIX .. ":") then
        return nil, "Not a Questie-X export string (missing " .. FORMAT_PREFIX .. " prefix)."
    end

    local sepPos = importStr:find(FORMAT_SEP, 1, true)
    if not sepPos then
        return nil, "Malformed string — missing separator."
    end

    local encoded = importStr:sub(sepPos + 1)
    if string.len(encoded) > MAX_IMPORT_LEN then
        return nil, "Import string too large (max 512 KB)."
    end

    local compressed = LibDeflate:DecodeForPrint(encoded)
    if not compressed then
        return nil, "Decode failed — string may be corrupted."
    end

    local serialized = LibDeflate:DecompressDeflate(compressed)
    if not serialized then
        return nil, "Decompression failed — string may be corrupted."
    end

    local ok, payload = AceSerializer:Deserialize(serialized)
    if not ok or type(payload) ~= "table" then
        return nil, "Deserialization failed — data is malformed."
    end

    if payload.v ~= FORMAT_VERSION then
        return nil, "Unsupported format version: " .. tostring(payload.v)
    end

    local bucket = payload.data
    if type(bucket) ~= "table" then
        return nil, "Payload missing data table."
    end
    if type(bucket.npcs)    ~= "table" or
       type(bucket.quests)  ~= "table" or
       type(bucket.items)   ~= "table" or
       type(bucket.objects) ~= "table" then
        return nil, "Payload data is missing required sub-tables (npcs/quests/items/objects)."
    end

    local stats = BuildStats(bucket)
    -- Guard against pathological payloads (e.g. a hand-crafted string with millions
    -- of entries) that could stall the client during the synchronous merge.
    if stats.total > 200000 then
        return nil, "Import rejected — too many entries (" .. stats.total .. ")."
    end
    stats.server = payload.server or "unknown"
    stats.ts     = payload.ts or 0

    self.lastImportData  = payload
    self.lastImportStats = stats

    Questie:Debug(Questie.DEBUG_DEVELOP, "[LearnerExport] ValidateImport OK:",
        stats.total, "entries from", stats.server)

    return payload, stats
end

--- Merges previously validated import data into learnedData.
--- Must call ValidateImport() first.
---@return boolean, string
function QuestieLearnerExport:MergeImport()
    if not self.lastImportData then
        return false, "No validated import data. Run ValidateImport() first."
    end

    local payload = self.lastImportData
    local bucket  = payload.data

    -- Ensure the learner stores exist before merging so a fresh/empty profile can still
    -- accept an import (and so per-type merges never index a nil table).
    local g = Questie.dbLearner and Questie.dbLearner.global
    if not g then
        return false, "Learner data is not initialized."
    end
    g.npcs    = g.npcs    or {}
    g.quests  = g.quests  or {}
    g.items   = g.items   or {}
    g.objects = g.objects or {}
    g.settings = g.settings or {}

    local merged   = 0
    local skipped  = 0
    local rejected = 0

    -- Count actual spawn coordinates ([7] for NPCs, [4] for objects) so we can report how
    -- many *pins* the import really added — not just how many entries. This tells the user
    -- whether the source data carried coordinates at all (a sparse export merges entries but
    -- adds 0 coords, which means there is nothing new to draw on the map).
    local function CountSpawnCoords(store, coordKey)
        local n = 0
        if type(store) ~= "table" then return 0 end
        for _, d in pairs(store) do
            if type(d) == "table" and type(d[coordKey]) == "table" then
                for _, zoneCoords in pairs(d[coordKey]) do
                    if type(zoneCoords) == "table" then
                        for _ in ipairs(zoneCoords) do n = n + 1 end
                    end
                end
            end
        end
        return n
    end
    local coordsBefore = CountSpawnCoords(g.npcs, 7) + CountSpawnCoords(g.objects, 4)

    -- Apply each entry SYNCHRONOUSLY and DEFENSIVELY so importing data merged from several
    -- different players is safe:
    --  * each entry is validated for key/coordinate structure inside
    --    _ApplyIncomingNetworkMerge (via _ValidateLearnedSpawnData) and only adopts fields
    --    the local store is missing — it never overwrites good local data;
    --  * a single malformed entry (corrupt coords, wrong types) is caught by pcall and
    --    skipped/counted instead of aborting the whole import or corrupting the store;
    --  * we merge synchronously (not via the async comms queue) so InjectLearnedData below
    --    sees the merged data and the returned counts are accurate.
    local function MergeType(typ, src)
        if type(src) ~= "table" then return end
        for id, d in pairs(src) do
            local nid = tonumber(id) or id
            if type(nid) == "number" and nid > 0 and type(d) == "table" then
                local ok, applied = pcall(QuestieLearner._ApplyIncomingNetworkMerge, QuestieLearner, typ, nid, d)
                if ok and applied then
                    merged = merged + 1
                elseif ok then
                    skipped = skipped + 1
                else
                    rejected = rejected + 1
                end
            else
                rejected = rejected + 1
            end
        end
    end

    MergeType("NPC",    bucket.npcs)
    MergeType("QUEST",  bucket.quests)
    MergeType("ITEM",   bucket.items)
    MergeType("OBJECT", bucket.objects)

    self.lastImportData  = nil
    self.lastImportStats = nil

    local coordsAfter = CountSpawnCoords(g.npcs, 7) + CountSpawnCoords(g.objects, 4)
    local coordsAdded = coordsAfter - coordsBefore
    if coordsAdded < 0 then coordsAdded = 0 end

    -- Push merged data into QuestieDB overrides immediately (no reload required for override data)
    if QuestieLearner and QuestieLearner.InjectLearnedData then
        pcall(QuestieLearner.InjectLearnedData, QuestieLearner)
    end

    -- Redraw the map/minimap/tooltips so freshly imported spawns appear live
    -- (without a /reload). SmoothReset clears and recalculates all notes.
    local QuestieQuest = QuestieLoader:ImportModule("QuestieQuest")
    if QuestieQuest and QuestieQuest.SmoothReset then
        pcall(QuestieQuest.SmoothReset, QuestieQuest)
    end

    local msg = string.format("Import complete: merged %d, skipped %d already-known%s. Added %d new spawn coordinate%s.",
        merged, skipped,
        rejected > 0 and (", rejected " .. rejected .. " malformed") or "",
        coordsAdded, coordsAdded == 1 and "" or "s")
    Questie:Debug(Questie.DEBUG_DEVELOP, "[LearnerExport]", msg)
    return true, msg
end

-----------------------------------------------------------------------
-- Cleanup / Prune
-----------------------------------------------------------------------

--- Returns a count of entries that would be pruned (dry run).
---@return table  { npcs=N, quests=N, items=N, objects=N, total=N, reasons={} }
function QuestieLearnerExport:DryRunPrune()
    return _Export:RunPrune(true)
end

--- Runs the actual prune and returns counts of removed entries.
---@return table
function QuestieLearnerExport:Prune()
    return _Export:RunPrune(false)
end

local QuestieDB  -- lazily imported to avoid circular dep

function _Export:RunPrune(dryRun)
    if not QuestieDB then QuestieDB = QuestieLoader:ImportModule("QuestieDB") end
 
    local serverKey = GetServerKey()
    local bucket    = GetServerBucket(serverKey)
 
    local result = { npcs = 0, quests = 0, items = 0, objects = 0, total = 0, reasons = {} }
    if not bucket then return result end
 
    local settings = (Questie.dbLearner and Questie.dbLearner.global and Questie.dbLearner.global.settings) or {}
    local thresholdDays = settings.staleThreshold or 90
    local thresholdSeconds = thresholdDays * 86400
    local minConfidence = settings.minConfidencePins or 2
    local pruneVerified = settings.pruneVerified
    local now = time()
 
    local function ShouldPruneNPC(id, entry)
        if CountTable(entry) == 0 then return "empty entry" end
        local isVerified = (entry.mc or 0) >= minConfidence
        if (not isVerified) and (now - (entry.ls or 0)) > thresholdSeconds then
            return "unconfirmed and stale (> " .. thresholdDays .. " days)"
        end
        if pruneVerified or not isVerified then
            if (entry.mc or 0) < 2 and not entry[7] then return "unverified with no coords" end
        end
        return nil
    end
 
    local function ShouldPruneQuest(id, entry)
        if CountTable(entry) == 0 then return "empty entry" end
        local isVerified = (entry.mc or 0) >= minConfidence
        if (not isVerified) and (now - (entry.ls or 0)) > thresholdSeconds then
            return "unconfirmed and stale (> " .. thresholdDays .. " days)"
        end
        if pruneVerified or not isVerified then
            if QuestieDB and QuestieDB.GetQuest then
                local dbEntry = QuestieDB.GetQuest(id)
                if dbEntry and (entry.mc or 0) < 2 then
                    return "fully covered by official DB, mc < 2"
                end
            end
        end
        return nil
    end
 
    local function ShouldPruneItem(id, entry)
        if CountTable(entry) == 0 then return "empty entry" end
        local isVerified = (entry.mc or 0) >= minConfidence
        if (not isVerified) and (now - (entry.ls or 0)) > thresholdSeconds then
            return "unconfirmed and stale (> " .. thresholdDays .. " days)"
        end
        if pruneVerified or not isVerified then
            if (entry.mc or 0) < 1 then return "zero match count" end
        end
        return nil
    end
 
    local function ShouldPruneObject(id, entry)
        if CountTable(entry) == 0 then return "empty entry" end
        local isVerified = (entry.mc or 0) >= minConfidence
        if (not isVerified) and (now - (entry.ls or 0)) > thresholdSeconds then
            return "unconfirmed and stale (> " .. thresholdDays .. " days)"
        end
        if pruneVerified or not isVerified then
            if (entry.mc or 0) < 2 and not entry[4] then return "unverified with no coords" end
        end
        return nil
    end
 
    local function PruneStore(store, checkFn, typeName)
        if not store then return end
        for id, entry in pairs(store) do
            local reason = checkFn(id, entry)
            if reason then
                result[typeName] = result[typeName] + 1
                result.total     = result.total + 1
                table.insert(result.reasons, typeName .. ":" .. tostring(id) .. " — " .. reason)
                if not dryRun then
                    store[id] = nil
                end
                Questie:Debug(Questie.DEBUG_DEVELOP, "[LearnerExport] Prune",
                    dryRun and "(dry)" or "", typeName, id, reason)
            end
        end
    end
 
    PruneStore(bucket.npcs,    ShouldPruneNPC,    "npcs")
    PruneStore(bucket.quests,  ShouldPruneQuest,  "quests")
    PruneStore(bucket.items,   ShouldPruneItem,   "items")
    PruneStore(bucket.objects, ShouldPruneObject, "objects")
 
    return result
end
