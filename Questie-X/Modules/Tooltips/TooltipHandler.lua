---@type QuestieTooltips
local QuestieTooltips = QuestieLoader:ImportModule("QuestieTooltips");
local _QuestieTooltips = QuestieTooltips.private

---@type l10n
local l10n = QuestieLoader:ImportModule("l10n")

---@type QuestieDB
local QuestieDB = QuestieLoader:ImportModule("QuestieDB")
---@type QuestiePlayer
local QuestiePlayer = QuestieLoader:ImportModule("QuestiePlayer")
---@type QuestieLib
local QuestieLib = QuestieLoader:ImportModule("QuestieLib")

--- COMPATIBILITY ---
local UnitGUID = QuestieCompat.UnitGUID

local lastGuid

-- True if the tooltip already shows a left-column line beginning with `label`. Used so the
-- ID lines can be (re)added on EVERY tooltip render without ever duplicating within a single
-- tooltip. The id lines must be re-added every render because WoW clears and re-fires
-- OnTooltipSetItem/OnTooltipSetUnit for the same item/unit, and the old "only when the id
-- changed" gate skipped re-adding the line on the rebuilt tooltip — so the ID vanished.
-- Defined here (before the Add*DataToTooltip functions) so all of them can see it.
local function _TooltipHasLeftLine(tooltip, label)
    local frameName = tooltip and tooltip.GetName and tooltip:GetName()
    if not frameName then return false end
    local numLines = tooltip:NumLines()
    for i = 1, (numLines or 0) do
        local fontString = _G[frameName .. "TextLeft" .. i]
        local text = fontString and fontString:GetText()
        if text and string.find(text, label, 1, true) == 1 then
            return true
        end
    end
    return false
end

-- ============================================================
-- NPCs that DROP an item which STARTS a quest (quest-starter drops)
-- Shows in tooltip like:
--   (yellow quest icon) Drops quest item !
--   (item icon) [ItemLink (quality colored)] [ID: <QuestId> (light blue)]
-- Works with Questie-335 compiled databases (binary + pointers).
-- ============================================================

local QUEST_START_LINE = "|TInterface\\GossipFrame\\AvailableQuestIcon:18:18:0:0|t |cFFFFD200Drops a quest !|r"
local QUEST_ID_COLOR = "|cFF80C8FF" -- light blue
local RESET_COLOR = "|r"

local _npcQuestStarterDrops = nil
local _npcQuestStarterDropsBuilt = false

-- ============================================================
-- Quest state cache (so we don't scan the log for every tooltip)
-- Hide lines if:
--   - quest is in quest log
--   - quest is flagged completed (turned in)
-- ============================================================

local _questInLogCache = {}
local _questInLogCacheBuilt = false

local function _WipeTable(t)
    if wipe then
        wipe(t)
    else
        for k in next, t do
            t[k] = nil
        end
    end
end

local function _RebuildQuestInLogCache()
    _WipeTable(_questInLogCache)
    _questInLogCacheBuilt = true

    if not GetNumQuestLogEntries or not GetQuestLogTitle then
        return
    end

    local n = GetNumQuestLogEntries()
    for i = 1, n do
        -- WotLK: title, level, suggestedGroup, isHeader, isCollapsed, isComplete, frequency, questID
        local _, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(i)
        if not isHeader and questID then
            questID = tonumber(questID)
            if questID then
                _questInLogCache[questID] = true
            end
        end
    end
end

local function _QuestInLog(questId)
    if not questId then return false end
    if not _questInLogCacheBuilt then
        _RebuildQuestInLogCache()
    end
    return _questInLogCache[questId] == true
end

-- Invalidate cache on quest log changes
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("QUEST_LOG_UPDATE")
    f:RegisterEvent("QUEST_ACCEPTED")
    f:RegisterEvent("QUEST_REMOVED")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", function()
        _questInLogCacheBuilt = false
    end)
end

local function _GetItemPointers()
    -- QuestieDB exposes these after DB init:
    --   QuestieDB.ItemPointers = QuestieDB.QueryItem.pointers
    if QuestieDB and type(QuestieDB.ItemPointers) == "table" then
        return QuestieDB.ItemPointers
    end
    if QuestieDB and QuestieDB.QueryItem and type(QuestieDB.QueryItem.pointers) == "table" then
        return QuestieDB.QueryItem.pointers
    end
    return nil
end

-- Check if player already has the quest (in log or turned in)
local function _PlayerHasQuest(questId)
    questId = tonumber(questId)
    if not questId then return false end

    -- 1) Active in log
    if _QuestInLog(questId) then
        return true
    end

    -- 2) Turned in / completed
    if IsQuestFlaggedCompleted and IsQuestFlaggedCompleted(questId) and not QuestiePlayer.currentQuestlog[questId] then
        return true
    end

    -- Optional fallback (some cores implement this reliably)
    if GetQuestLogIndexByID then
        local idx = GetQuestLogIndexByID(questId)
        if idx and idx > 0 then
            return true
        end
    end

    return false
end

local function _TryBuildNpcQuestStarterDrops()
    if _npcQuestStarterDropsBuilt and _npcQuestStarterDrops then
        return true
    end

    -- DB not ready yet? Try again later.
    if not QuestieDB or type(QuestieDB.QueryItemSingle) ~= "function" then
        return false
    end

    local pointers = _GetItemPointers()
    if type(pointers) ~= "table" then
        return false
    end

    _npcQuestStarterDrops = {}

    -- Helper function to process an item and add it to the lookup table
    local function processItem(itemId)
        local questId = QuestieDB.QueryItemSingle(itemId, "startQuest")
        if questId and questId ~= 0 then
            local npcDrops = QuestieDB.QueryItemSingle(itemId, "npcDrops")
            if npcDrops and type(npcDrops) == "table" then
                local itemName = QuestieDB.QueryItemSingle(itemId, "name")
                for _, npcId in next, npcDrops do
                    local list = _npcQuestStarterDrops[npcId]
                    if not list then
                        list = {}
                        _npcQuestStarterDrops[npcId] = list
                    end
                    list[table.getn(list) + 1] = { itemId = itemId, questId = tonumber(questId), name = itemName }
                end
            end
        end
    end

    -- Iterate all items from compiled database
    for itemId, _ in next, pointers do
        processItem(itemId)
    end

    -- Also iterate Ascension override items (they don't have pointers)
    if QuestieDB.itemDataOverrides and type(QuestieDB.itemDataOverrides) == "table" then
        for itemId, _ in next, QuestieDB.itemDataOverrides do
            processItem(itemId)
        end
    end

    _npcQuestStarterDropsBuilt = true
    return true
end

local function _TooltipHasQuestStarterLine(tooltip)
    local n = tooltip:NumLines()
    local base = tooltip:GetName() .. "TextLeft"
    for i = 1, n do
        local left = _G[base .. i]
        if left then
            local t = left:GetText()
            if t and t:find("Drops quest item", 1, true) then
                return true
            end
        end
    end
    return false
end

local function _AddQuestStarterDropsToTooltip(npcId)
    if not _TryBuildNpcQuestStarterDrops() then return end
    if not _npcQuestStarterDrops then return end

    local drops = _npcQuestStarterDrops[npcId]
    if not drops or table.getn(drops) == 0 then return end

    if _TooltipHasQuestStarterLine(GameTooltip) then
        return
    end

    -- Filter drops to only show items where player doesn't have the quest yet
    local filteredDrops = {}
    local dropsCount = table.getn(drops)
    for i = 1, dropsCount do
        local info = drops[i]
        if info.questId and (not _PlayerHasQuest(info.questId)) then
            filteredDrops[table.getn(filteredDrops) + 1] = info
        end
    end

    if table.getn(filteredDrops) == 0 then
        return
    end

    GameTooltip:AddLine(QUEST_START_LINE)

    local filteredCount = table.getn(filteredDrops)
    for i = 1, filteredCount do
        local info = filteredDrops[i]
        local itemId = info.itemId
        local questId = info.questId

        -- Item link with correct quality color when cached by client
        local itemLink = select(2, GetItemInfo(itemId))
        if not itemLink then
            local itemName = info.name
            if not itemName or itemName == "" then
                itemName = "Item " .. tostring(itemId)
            end
            itemLink = ("|Hitem:%d:::::::::|h[%s]|h"):format(itemId, itemName)
        end

        local icon = GetItemIcon and GetItemIcon(itemId)
        local qid = ("%s[ID: %d]%s"):format(QUEST_ID_COLOR, questId, RESET_COLOR)

        if icon then
            GameTooltip:AddLine(("|T%s:14:14:0:0|t %s %s"):format(icon, itemLink, qid))
        else
            GameTooltip:AddLine(("%s %s"):format(itemLink, qid))
        end
    end
end

-- Collapses STACKED Ascension quest-progress lines for the same objective.
-- The Ascension server appends a new progress line on every objective update instead of
-- replacing the previous one, so a tooltip can pile up "0/8", "1/8", "2/8", "3/8" for one
-- objective (#9). This keeps only the most-progressed line of each stack.
--
-- It is SAFE to run unconditionally (unlike the full strip below): it only hides a line
-- when the SAME tooltip holds another progress line with the same objective text AND the
-- same denominator. Other addons — and Questie's own single-line objectives — never produce
-- two such duplicates, so their tooltip lines are never touched.
function _QuestieTooltips:DedupeAscensionProgressLines(tooltip, numLines)
    local frameName = tooltip:GetName()
    if not frameName then return end

    local groups = {}
    for i = 2, numLines do
        local fontString = _G[frameName .. "TextLeft" .. i]
        local text = fontString and fontString:GetText()
        if text then
            local clean = string.gsub(text, "|[cC]%x%x%x%x%x%x%x%x", "")
            clean = string.gsub(clean, "|[rR]", "")
            clean = string.match(clean, "^%s*(.-)%s*$") or clean
            -- Strip an optional leading bullet/dash so "- 2/8 ..." matches "2/8 ...".
            local body = string.match(clean, "^%-%s*(.+)$") or clean
            local current, total, label = string.match(body, "^(%d+)%s*/%s*(%d+)%s*(.-)$")
            if current and total then
                local key = (label or "") .. "@@" .. total
                local group = groups[key]
                if not group then
                    groups[key] = { indices = { i }, bestIndex = i, bestCurrent = tonumber(current) }
                else
                    table.insert(group.indices, i)
                    if tonumber(current) >= group.bestCurrent then
                        group.bestCurrent = tonumber(current)
                        group.bestIndex = i
                    end
                end
            end
        end
    end

    for _, group in pairs(groups) do
        if table.getn(group.indices) > 1 then
            for _, idx in ipairs(group.indices) do
                if idx ~= group.bestIndex then
                    local fontString = _G[frameName .. "TextLeft" .. idx]
                    if fontString then
                        fontString:SetText("")
                        fontString:Hide()
                    end
                end
            end
        end
    end
end

function _QuestieTooltips:HideAscensionQuestLines(tooltip)
    if not Questie.db.profile.enableTooltips then return end
    local numLines = tooltip:NumLines()
    if not numLines or numLines < 1 then return end

    -- Always collapse stacked duplicate progress lines for the same objective. This is the
    -- safe, targeted fix for the "0/8 1/8 2/8 ..." pile-up and never touches other addons.
    _QuestieTooltips:DedupeAscensionProgressLines(tooltip, numLines)

    -- Opt-in only. The full strip removes EVERY line matching a quest-objective pattern
    -- ("N/M", "[N] ...") to hide all of Ascension's server-injected quest progress. It runs
    -- on every tooltip, so by default it must NOT touch them — otherwise it clobbers other
    -- tooltip addons' lines that happen to look like "N/M" (durability, stack counts, etc.).
    -- Users who want all Ascension quest-spam gone can enable it explicitly. (#16)
    if not Questie.db.profile.hideAscensionTooltipQuestLines then return end

    for i = 2, numLines do
        local fontString = _G[tooltip:GetName() .. "TextLeft" .. i]
        if fontString then
            local text = fontString:GetText()
            if text then
                local cleanText = string.gsub(text, "|[cC]%x%x%x%x%x%x%x%x", "")
                cleanText = string.gsub(cleanText, "|[rR]", "")
                cleanText = string.match(cleanText, "^%s*(.-)%s*$") or cleanText

                -- Hide ONLY the Ascension-injected objective progress lines themselves
                -- (e.g. "0/8 Arcane Wraith slain", "[1] ...", "- 0/2 ...").
                --
                -- We intentionally do NOT hide the lines that follow. The previous
                -- behavior set a "questBlockActive" flag and then wiped every later
                -- non-indented line until it hit an indented one — which also removed
                -- Questie's own "Item ID"/"NPC ID"/"Object ID" lines and any other
                -- addon's tooltip additions (e.g. an item-count overlay), because those
                -- are appended at the BOTTOM of the tooltip, after the objective block.
                -- Matching each objective line individually removes the Ascension spam
                -- without touching anything else on the tooltip.
                if string.match(cleanText, "^%[%d+.-%]") or string.match(cleanText, "^%d+/%d+") or string.match(cleanText, "^%-.-%d+/%d+") then
                    fontString:SetText("")
                    fontString:Hide()
                end
            end
        end
    end
end

function _QuestieTooltips:AddUnitDataToTooltip()
    if (self.IsForbidden and self:IsForbidden()) or (not Questie.db.profile.enableTooltips) then
        return
    end

    _QuestieTooltips:HideAscensionQuestLines(self)

    local name, unitToken = self:GetUnit();
    if not unitToken then return end
    local guid = UnitGUID(unitToken);
    if (not guid) then
        guid = UnitGUID("mouseover");
    end

    local guidType, _, _, _, _, npcId, _ = strsplit("-", guid or "");

    -- Robust fallback for GUIDs strsplit("-") can't parse — legacy 0x hex GUIDs (and any
    -- malformed/short modern GUID). The learner's GetIdAndTypeFromGUID handles both formats,
    -- so reuse it; without this the NPC ID line silently failed to write on those units.
    if (not tonumber(npcId)) and guid then
        local QuestieLearner = QuestieLoader:ImportModule("QuestieLearner")
        if QuestieLearner and QuestieLearner.GetIdAndTypeFromGUID then
            local fallbackId, fallbackType = QuestieLearner:GetIdAndTypeFromGUID(guid)
            if fallbackId then
                npcId = tostring(fallbackId)
                if (not guidType) or guidType == "" then guidType = fallbackType end
            end
        end
    end

    -- NPC ID is (re)added on EVERY render so it survives WoW's tooltip rebuilds, not only the
    -- first hover of a new unit. Deduped per tooltip so it never doubles up.
    if name and (guidType == "Creature" or guidType == "Vehicle") and npcId and tonumber(npcId)
            and Questie.db.profile.enableTooltipsNPCID == true
            and not _TooltipHasLeftLine(self, "NPC ID") then
        GameTooltip:AddDoubleLine("NPC ID", "|cFFFFFFFF" .. npcId .. "|r")
    end

    if name and (guidType == "Creature" or guidType == "Vehicle") and (
            name ~= QuestieTooltips.lastGametooltipUnit or
            (not QuestieTooltips.lastGametooltipCount) or
            _QuestieTooltips:CountTooltip() < QuestieTooltips.lastGametooltipCount or
            QuestieTooltips.lastGametooltipType ~= "monster" or
            lastGuid ~= guid
        ) then
        QuestieTooltips.lastGametooltipUnit = name

        -- Suppress System A's inline learner lines here: QuestieLearner's OnTooltipSetUnit
        -- hook already renders learner spawn/kill data for the hovered unit (into the main
        -- tooltip, or the separate secondary learner frame when that option is enabled).
        local tooltipData = QuestieTooltips:GetTooltip("m_" .. npcId, true);

        -- NPC ID line is added above (every render, deduped); only the objective lines remain here.
        if tooltipData then
            for _, v in next, tooltipData do
                GameTooltip:AddLine(v)
            end
        end

        -- Data-source attribution is rendered by QuestieLearner's secondary tooltip frame
        -- (only when the secondary learner tooltip is enabled), never inline in the main
        -- tooltip — see _AddLearnedSpawnTooltipLine.

        local npcNum = tonumber(npcId)
        if npcNum then
            _AddQuestStarterDropsToTooltip(npcNum)
        end

        if QuestieTooltips.ResizeTooltip then
            QuestieTooltips:ResizeTooltip(self)
        end
        QuestieTooltips.lastGametooltipCount = _QuestieTooltips:CountTooltip()
    end
    lastGuid = guid;
    QuestieTooltips.lastGametooltipType = "monster";
end

-- =======================
-- Rest of original file
-- =======================


local lastItemId = 0;
function _QuestieTooltips:AddItemDataToTooltip()
    if (self.IsForbidden and self:IsForbidden()) or (not Questie.db.profile.enableTooltips) then
        return
    end

    _QuestieTooltips:HideAscensionQuestLines(self)

    local name, link = self:GetItem()
    local itemId
    if link then
        itemId = select(3,
            string.match(link,
                "|?c?f?f?(%x*)|?H?([^:]*):?(%d+):?(%d*):?(%d*):?(%d*):?(%d*):?(%d*):?(%-?%d*):?(%-?%d*):?(%d*):?(%d*):?(%-?%d*)|?h?%[?([^%[%]]*)%]?|?h?|?r?"))
    end

    -- Item ID is (re)added on EVERY render so it survives WoW's tooltip rebuilds, not just the
    -- first hover of a new item. Deduped per tooltip so it never doubles up.
    if name and itemId and Questie.db.profile.enableTooltipsItemID == true
            and not _TooltipHasLeftLine(self, "Item ID") then
        self:AddDoubleLine("Item ID", "|cFFFFFFFF" .. itemId .. "|r")
    end

    if name and itemId and (lastItemId ~= itemId) then
        QuestieTooltips.lastGametooltipItem = name
        local tooltipData = QuestieTooltips:GetTooltip("i_" .. (itemId or 0));
        -- If the item starts a quest (the player must right-click/use it,
        -- or talk to an NPC while it's in their bag), surface that so the
        -- player can see which quest the item unlocks without first
        -- having to look it up. We never knew the item's startQuest
        -- until runtime, so this is read directly from the static DB /
        -- Ascension override table.
        local startQuestId = QuestieDB and QuestieDB.QueryItemSingle
            and tonumber(QuestieDB.QueryItemSingle(itemId, "startQuest") or 0) or 0
        if startQuestId and startQuestId > 0 and (not _PlayerHasQuest(startQuestId)) then
            local questTitle = QuestieLib and QuestieLib.GetColoredQuestName
                and QuestieLib:GetColoredQuestName(startQuestId, Questie.db.profile.enableTooltipsQuestLevel, true, true)
                or nil
            if questTitle and questTitle ~= "" then
                self:AddDoubleLine(QUEST_START_LINE, questTitle)
            end
        end
        if tooltipData then
            for _, v in next, tooltipData do
                self:AddLine(v)
            end
        end
        QuestieTooltips.lastGametooltipCount = _QuestieTooltips:CountTooltip()
    end
    lastItemId = itemId;
    QuestieTooltips.lastGametooltipType = "item";
    QuestieTooltips.lastFrameName = self:GetName();
end

function _QuestieTooltips:AddObjectDataToTooltip(name)
    if (not Questie.db.profile.enableTooltips) then
        return
    end
    
    _QuestieTooltips:HideAscensionQuestLines(GameTooltip)
    
    if name then
        local titleAdded = false
        local lookup = l10n.objectNameLookup[name] or {}
        local count = table.getn(lookup)

        if Questie.db.profile.enableTooltipsObjectID == true and not _TooltipHasLeftLine(GameTooltip, "Object ID") then
            if count == 1 then
                GameTooltip:AddDoubleLine("Object ID", "|cFFFFFFFF" .. lookup[1] .. "|r")
            elseif count > 1 then
                GameTooltip:AddDoubleLine("Object ID", "|cFFFFFFFF" .. lookup[1] .. " (" .. count .. ")|r")
            else
                -- Name not in the object lookup ("problematic"). Fall back to the object's
                -- GUID via the learner's robust GameObject-GUID parser, so the ID still shows.
                local QuestieLearner = QuestieLoader:ImportModule("QuestieLearner")
                local objGuid = UnitGUID and UnitGUID("mouseover")
                local objId = objGuid and QuestieLearner and QuestieLearner.GetObjectIdFromGUID
                    and QuestieLearner:GetObjectIdFromGUID(objGuid)
                if objId then
                    GameTooltip:AddDoubleLine("Object ID", "|cFFFFFFFF" .. objId .. "|r")
                end
            end
        end

        local alreadyAddedObjectiveLines = {}
        for _, gameObjectId in next, lookup do
            local tooltipData = QuestieTooltips:GetTooltip("o_" .. gameObjectId);

            if type(gameObjectId) == "number" and tooltipData then
                if (not titleAdded) then
                    GameTooltip:AddLine(tooltipData[1])
                    titleAdded = true
                end

                if tooltipData[2] then
                    -- Quest has objectives
                    for index, line in next, tooltipData do
                        if index > 1 and (not alreadyAddedObjectiveLines[line]) then -- skip the first entry, it's the title
                            local _, _, acquired, needed = string.find(line, "(%d+)/(%d+)")
                            -- We need "tonumber", because acquired can contain parts of the color string
                            if acquired and tonumber(acquired) == tonumber(needed) then
                                -- We don't want to show completed objectives on game objects
                                break;
                            end
                            alreadyAddedObjectiveLines[line] = true
                            GameTooltip:AddLine(line)
                        end
                    end
                end
            end
        end
        if QuestieTooltips.ResizeTooltip then
            QuestieTooltips:ResizeTooltip(GameTooltip)
        end
        GameTooltip:Show()
    end
    QuestieTooltips.lastGametooltipType = "object";
end

function _QuestieTooltips:CountTooltip()
    local tooltipCount = 0
    for i = 1, GameTooltip:NumLines() do
        local frame = _G["GameTooltipTextLeft" .. i]
        if frame and frame:GetText() then
            tooltipCount = tooltipCount + 1
        else
            return tooltipCount
        end
    end
    return tooltipCount
end
