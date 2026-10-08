---@class QuestieTooltips
local QuestieTooltips = QuestieLoader:CreateModule("QuestieTooltips");
local _QuestieTooltips = QuestieTooltips.private
-------------------------
--Import modules.
-------------------------
---@type QuestieComms
local QuestieComms = QuestieLoader:ImportModule("QuestieComms");
---@type QuestieLib
local QuestieLib = QuestieLoader:ImportModule("QuestieLib");
---@type QuestiePlayer
local QuestiePlayer = QuestieLoader:ImportModule("QuestiePlayer");
---@type QuestieDB
local QuestieDB = QuestieLoader:ImportModule("QuestieDB");
---@type l10n
local l10n = QuestieLoader:ImportModule("l10n")

--- COMPATIBILITY ---
local UnitInParty = QuestieCompat.UnitInParty
local IsInGroup = QuestieCompat.IsInGroup
local GetClassColor = QuestieCompat.GetClassColor

local tinsert = table.insert
QuestieTooltips.lastGametooltip = ""
QuestieTooltips.lastGametooltipCount = -1;
QuestieTooltips.lastGametooltipType = "";
QuestieTooltips.lastFrameName = "";

QuestieTooltips.lookupByKey = {
    --["u_Grell"] = {questid, {"Line 1", "Line 2"}}
}
QuestieTooltips.lookupKeysByQuestId = {
    --["questId"] = {"u_Grell", ... }
}

local MAX_GROUP_MEMBER_COUNT = 6
-- Throttle: limit the OnUpdate object-tooltip check to 10 times per second.
-- Without this, the callback fires every frame (60–144 Hz) and hammers GetText()
-- + CountTooltip() even when the tooltip hasn't changed.
local _tooltipUpdateInterval = 0.10
local _tooltipLastUpdate = 0
local _tooltipLastText = ""

local _InitObjectiveTexts

local function _LearnerTooltipsEnabled()
    return not (Questie.db and Questie.db.profile) or Questie.db.profile.learnerTooltips ~= false
end

local function _ResizeTooltipToFit(tooltip)
    if not tooltip or not tooltip.GetName then
        return
    end

    local tooltipName = tooltip:GetName()
    if not tooltipName then
        return
    end

    local maxWidth = 0
    for i = 1, tooltip:NumLines() do
        local left = _G[tooltipName .. "TextLeft" .. i]
        local right = _G[tooltipName .. "TextRight" .. i]
        if left and left:GetText() then
            maxWidth = math.max(maxWidth, left:GetStringWidth() or 0)
        end
        if right and right:GetText() then
            maxWidth = math.max(maxWidth, right:GetStringWidth() or 0)
        end
    end

    if maxWidth <= 0 then
        return
    end

    maxWidth = maxWidth + 24
    local currentWidth = tooltip.GetWidth and tooltip:GetWidth() or 0
    if currentWidth < maxWidth then
        if tooltip.SetMinimumWidth then
            tooltip:SetMinimumWidth(maxWidth)
        end
        tooltip:SetWidth(maxWidth)
    end
end

function QuestieTooltips:ResizeTooltip(tooltip)
    if not (Questie.db and Questie.db.profile) or Questie.db.profile.learnerTooltipAutoResize == false then
        return
    end
    _ResizeTooltipToFit(tooltip)
end

local function _GetQuestObjectiveSummary(questId)
    if not QuestieDB or not QuestieDB.GetQuest then
        return nil
    end

    local quest = QuestieDB:GetQuest(questId)
    if not quest or not quest.ObjectiveData then
        return nil
    end

    local summary = {}
    for _, objective in ipairs(quest.ObjectiveData) do
        local text = objective and (objective.Text or objective.Description)
        if type(text) == "string" and text ~= "" then
            tinsert(summary, text)
        end
    end

    if table.getn(summary) == 0 then
        return nil
    end

    return summary
end

--- Accurate data-source attribution for a unit/object/item hover tooltip.
--- Derives provenance from the entity id (never from the global mode): AscensionDB
--- curated override, learner record, or base "Questie DB", plus a Comms overlay when
--- comms holds data for this key. Returns nil when the source can't be determined or the
--- option is off, so a wrong/guessed label is never shown.
---@param key string @"m_<npcId>" | "o_<objectId>" | "i_<itemId>"
local function _GetTooltipSourceLine(key)
    if not Questie.db.profile.enableTooltipsSource then return nil end
    -- Source attribution is shown only inside the secondary learner tooltip; never when
    -- that option is disabled (the only caller is the secondary frame, but gate here too).
    if Questie.db.profile.learnerTooltipUseSecondary ~= true then return nil end
    if not key then return nil end
    local prefix = key:sub(1, 2)
    local id = tonumber(key:sub(3))
    local entityType = (prefix == "o_" and "OBJECT") or (prefix == "i_" and "ITEM") or "NPC"

    local parts = {}
    local src = id and QuestieDB.GetPinDataSource(entityType, id) or nil
    if src then tinsert(parts, src) end
    if QuestieComms and QuestieComms.data and QuestieComms.data.KeyExists and QuestieComms.data:KeyExists(key) then
        tinsert(parts, "Comms")
    end
    if table.getn(parts) == 0 then return nil end
    return "|cFF808080Source: " .. table.concat(parts, " + ") .. "|r"
end

---@param questId number
---@param key string monster: m_, items: i_, objects: o_ + string name of the objective
---@param objective table
function QuestieTooltips:RegisterObjectiveTooltip(questId, key, objective)
    if not QuestieTooltips.lookupByKey[key] then
        QuestieTooltips.lookupByKey[key] = {};
    end
    if not QuestieTooltips.lookupKeysByQuestId[questId] then
        QuestieTooltips.lookupKeysByQuestId[questId] = {}
    end
    local tooltip = {
        questId = questId,
        objective = objective,
    };
    QuestieTooltips.lookupByKey[key][tostring(questId) .. " " .. objective.Index] = tooltip
    tinsert(QuestieTooltips.lookupKeysByQuestId[questId], key)
end

---@param questId number
---@param name string The name of the object or NPC the tooltip should show on
---@param starterId number The ID of the object or NPC the tooltip should show on
---@param key string @Either m_<npcId> or o_<objectId>
function QuestieTooltips:RegisterQuestStartTooltip(questId, name, starterId, key)
    if not name then
        return
    end
    if not QuestieTooltips.lookupByKey[key] then
        QuestieTooltips.lookupByKey[key] = {};
    end
    if not QuestieTooltips.lookupKeysByQuestId[questId] then
        QuestieTooltips.lookupKeysByQuestId[questId] = {}
    end
    local tooltip = {
        questId = questId,
        name = name,
        starterId = starterId,
    };
    QuestieTooltips.lookupByKey[key][tostring(questId) .. " " .. name .. " " .. starterId] = tooltip
    tinsert(QuestieTooltips.lookupKeysByQuestId[questId], key)
end

---@param questId number
function QuestieTooltips:RemoveQuest(questId)
    if (not QuestieTooltips.lookupKeysByQuestId[questId]) then
        -- Tooltip has already been removed
        return
    end

    -- Remove tooltip related keys from quest table so that
    -- it can be readded/registered by other quest functions.
    local quest = QuestieDB.GetQuest(questId)

    if quest then
        for _, objective in next, quest.Objectives do
            objective.AlreadySpawned = {}
            objective.hasRegisteredTooltips = false
            objective.registeredItemTooltips = false
        end

        for _, objective in next, quest.SpecialObjectives do
            objective.AlreadySpawned = {}
            objective.hasRegisteredTooltips = false
            objective.registeredItemTooltips = false
        end
    end

    Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestieTooltips:RemoveQuest]", questId)

    for _, key in next, QuestieTooltips.lookupKeysByQuestId[questId] or {} do
        --Count to see if we should remove the main object
        local totalCount = 0
        local totalRemoved = 0
        for _, tooltipData in next, QuestieTooltips.lookupByKey[key] or {} do
            --Remove specific quest
            if (tooltipData.questId == questId and tooltipData.objective) then
                QuestieTooltips.lookupByKey[key][tostring(tooltipData.questId) .. " " .. tooltipData.objective.Index] = nil
                totalRemoved = totalRemoved + 1
            elseif (tooltipData.questId == questId and tooltipData.name) then
                QuestieTooltips.lookupByKey[key][tostring(tooltipData.questId) .. " " .. tooltipData.name .. " " .. tooltipData.starterId] = nil
                totalRemoved = totalRemoved + 1
            end
            totalCount = totalCount + 1
        end
        if (totalCount == totalRemoved) then
            QuestieTooltips.lookupByKey[key] = nil
        end
    end

    QuestieTooltips.lookupKeysByQuestId[questId] = nil
end

-- This code is related to QuestieComms, here we fetch all the tooltip data that exist in QuestieCommsData
-- It uses a similar system like here with i_ID etc as keys.
local function _FetchTooltipsForGroupMembers(key, tooltipData)
    local anotherPlayer = false;
    if QuestieComms and QuestieComms.data:KeyExists(key) then
        ---@tooltipData @tooltipData[questId][playerName][objectiveIndex].text
        local tooltipDataExternal = QuestieComms.data:GetTooltip(key);
        for questId, playerList in next, tooltipDataExternal do
            if (not tooltipData[questId]) then
                tooltipData[questId] = {
                    title = QuestieLib:GetColoredQuestName(questId, Questie.db.profile.enableTooltipsQuestLevel, true, true)
                }
            end
            for playerName, _ in next, playerList do
                local playerInfo = QuestiePlayer:GetPartyMemberByName(playerName);
                if playerInfo or QuestieComms.remotePlayerEnabled[playerName] then
                    anotherPlayer = true
                    break
                end
            end
            if anotherPlayer then
                break
            end
        end
    end

    if QuestieComms.data:KeyExists(key) and anotherPlayer then
        ---@tooltipData @tooltipData[questId][playerName][objectiveIndex].text
        local tooltipDataExternal = QuestieComms.data:GetTooltip(key);
        for questId, playerList in next, tooltipDataExternal do
            if (not tooltipData[questId]) then
                tooltipData[questId] = {
                    title = QuestieLib:GetColoredQuestName(questId, Questie.db.profile.enableTooltipsQuestLevel, true, true)
                }
            end
            for playerName, objectives in next, playerList do
                local playerInfo = QuestiePlayer:GetPartyMemberByName(playerName);
                if playerInfo or QuestieComms.remotePlayerEnabled[playerName] then
                    anotherPlayer = true;
                    for objectiveIndex, objective in next, objectives do
                        if (not objective) then
                            objective = {}
                        end

                        tooltipData[questId].objectivesText = _InitObjectiveTexts(tooltipData[questId].objectivesText, objectiveIndex, playerName)

                        local text;
                        local color = QuestieLib:GetRGBForObjective(objective)

                        if objective.required then
                            text = "   " .. color .. tostring(objective.fulfilled) .. "/" .. tostring(objective.required) .. " " .. objective.text;
                        else
                            text = "   " .. color .. objective.text;
                        end

                        tooltipData[questId].objectivesText[objectiveIndex][playerName] = { ["color"] = color, ["text"] = text };
                    end
                end
            end
        end
    end
    return anotherPlayer
end

local function _GetLearnerTooltipLines(key)
    -- key format: "m_<npcId>" for NPCs, "o_<objectId>" for objects, "i_<itemId>" for items
    local id = tonumber(key:sub(3))
    if not id then return nil end

    local QuestieLearner = QuestieLoader:ImportModule("QuestieLearner")
    if not QuestieLearner
        or not QuestieLearner.CanShowLearnerTooltips
        or not QuestieLearner:CanShowLearnerTooltips()
    then
        return nil
    end

    local learnedNpc = QuestieLearner.data and QuestieLearner.data.npcs and QuestieLearner.data.npcs[id]
    if not learnedNpc then return nil end

    local lines = {}
    local guidSpawns = learnedNpc[8]
    local spawnList = learnedNpc[7]

    -- Count total distinct spawn points
    local totalSpawns = 0
    if spawnList then
        for _ in pairs(spawnList) do totalSpawns = totalSpawns + 1 end
    end

    -- Find the most-visited spawn (highest count in guidSpawns)
    local bestX, bestY, bestCount = nil, nil, 0
    if guidSpawns then
        for uid, entry in pairs(guidSpawns) do
            local c = tonumber(entry.count) or 1
            if c > bestCount then
                bestCount = c
                bestX = entry.x
                bestY = entry.y
            end
        end
    end

    if bestX and bestY then
        tinsert(lines, string.format("  |cFF808080Learned spawn|r (|cFFFFFFFF%.1f, %.1f|r) |cFF808080from %d kills|r", bestX, bestY, bestCount))
    end

    if totalSpawns > 0 then
        tinsert(lines, string.format("  |cFF808080Total spawns learned|r |cFFFFFFFF%d|r", totalSpawns))
    end

    local mc = tonumber(learnedNpc.mc) or 0
    if mc > 0 then
        tinsert(lines, string.format("  |cFF808080Total kills recorded|r |cFFFFFFFF%d|r", mc))
    end

    if #lines > 0 then
        return lines
    end
    return nil
end

---@param key string
---@param suppressLearnerLines boolean? When true, omit the inline learner spawn/kill
--- lines from System A. Used by the NPC unit-hover tooltip, where the learner data is
--- already rendered by QuestieLearner's OnTooltipSetUnit hook (main tooltip when the
--- secondary learner tooltip is off, or the separate secondary frame when it is on).
--- Map-pin and object tooltips leave this nil so they keep showing learner lines.
function QuestieTooltips:GetTooltip(key, suppressLearnerLines)
    Questie:Debug(Questie.DEBUG_SPAM, "[QuestieTooltips:GetTooltip]", key)
    if (not key) then
        return nil
    end

    if (QuestiePlayer.numberOfGroupMembers or 0) > MAX_GROUP_MEMBER_COUNT then
        return nil -- temporary disable tooltips in raids, we should make a proper fix
    end

    --Do not remove! This is the datastrucutre for tooltipData!
    --[[tooltipdata[questId] = {
        title = coloredTitle,
        objectivesText = {
            [objectiveIndex] = {
                [playerName] = {
                    [color] = color,
                    [text] = text
                }
            }
        }
    }]]
    --
    local tooltipData = {}
    local tooltipLines = {}

    if (not QuestieTooltips.lookupByKey[key]) then
        local QuestieLearner = QuestieLoader:ImportModule("QuestieLearner")
        local QuestLogCache = QuestieLoader:ImportModule("QuestLogCache")
        local mode = QuestieLearner and QuestieLearner.GetDataSourceMode and QuestieLearner:GetDataSourceMode() or "auto"
        if QuestieLearner and QuestieLearner.data and mode ~= "static" and mode ~= "none" then
             -- Try to find in learned NPCs or objects
             local id = tonumber(key:sub(3))
             if id then
if key:sub(1,2) == "m_" then
                    local learnedNpc = QuestieLearner.data.npcs[id]
                    -- npc[10] from _AddToArray is an array of questIds, not {questId -> objList}
                    if learnedNpc and learnedNpc[10] then
                        for _, questId in ipairs(learnedNpc[10]) do
                            local qData = QuestieLearner.data.quests[questId]
                            -- Only correlate live objective progress for quests the player
                            -- is currently on. A just-turned-in/abandoned quest is no longer in
                            -- QuestLogCache, so calling GetQuestObjectives for it would log a
                            -- debugstack and return {} (harmless but noisy in DEVELOP mode).
                            if qData and qData[10] and QuestiePlayer.currentQuestlog and QuestiePlayer.currentQuestlog[questId] then
                                for slotIdx = 1, #qData[10] do
                                    local objSlot = qData[10][slotIdx]
                                    if objSlot then
                                        for oIndex = 1, #objSlot do
                                            local objEntry = objSlot[oIndex]
                                            if objEntry and objEntry[2] then
                                                local objText = objEntry[2]
                                                local needed, collected
                                                local objectives = QuestLogCache.GetQuestObjectives(questId)
                                                if objectives then
                                                    for _, obj in next, objectives do
                                                        if obj.text and objText and (obj.text == objText or string.find(obj.text, objText, 1, true) or string.find(objText, obj.text, 1, true)) then
                                                            needed = obj.numRequired
                                                            collected = obj.numFulfilled
                                                            break
                                                        end
                                                    end
                                                end
                                                QuestieTooltips:RegisterObjectiveTooltip(questId, key, {
                                                    Index = 0,
                                                    Description = objText,
                                                    Needed = needed,
                                                    Collected = collected,
                                                    Update = function(self)
                                                        local objs = QuestLogCache.GetQuestObjectives(questId)
                                                        if objs then
                                                            for _, o in next, objs do
                                                                if o.text and self.Description and (o.text == self.Description or string.find(o.text, self.Description, 1, true) or string.find(self.Description, o.text, 1, true)) then
                                                                    self.Needed = o.numRequired
                                                                    self.Collected = o.numFulfilled
                                                                    break
                                                                end
                                                            end
                                                        end
                                                    end
                                                })
                                            end
                                        end
                                    end
                                end
                            end
                        end
                        if learnedNpc.mc and _LearnerTooltipsEnabled() and Questie.db.profile.learnerTooltipShowConfidence ~= false then
                            tinsert(tooltipLines, "|cFF5EBAF3(Learned - Confidence: " .. tostring(learnedNpc.mc) .. ")|r")
                        end
                    end
elseif key:sub(1,2) == "o_" then
                    local learnedObj = QuestieLearner.data.objects[id]
                    -- obj[2] from _AddToArray is an array of questIds (questStarts), not {questId -> objList}
                    if learnedObj and learnedObj[2] then
                        for _, questId in ipairs(learnedObj[2]) do
                            local qData = QuestieLearner.data.quests[questId]
                            -- Only correlate live objective progress for quests the player
                            -- is currently on. A just-turned-in/abandoned quest is no longer in
                            -- QuestLogCache, so calling GetQuestObjectives for it would log a
                            -- debugstack and return {} (harmless but noisy in DEVELOP mode).
                            if qData and qData[10] and QuestiePlayer.currentQuestlog and QuestiePlayer.currentQuestlog[questId] then
                                for slotIdx = 1, #qData[10] do
                                    local objSlot = qData[10][slotIdx]
                                    if objSlot then
                                        for oIndex = 1, #objSlot do
                                            local objEntry = objSlot[oIndex]
                                            if objEntry and objEntry[2] then
                                                local objText = objEntry[2]
                                                local needed, collected
                                                local objectives = QuestLogCache.GetQuestObjectives(questId)
                                                if objectives then
                                                    for _, obj in next, objectives do
                                                        if obj.text and objText and (obj.text == objText or string.find(obj.text, objText, 1, true) or string.find(objText, obj.text, 1, true)) then
                                                            needed = obj.numRequired
                                                            collected = obj.numFulfilled
                                                            break
                                                        end
                                                    end
                                                end
                                                QuestieTooltips:RegisterObjectiveTooltip(questId, key, {
                                                    Index = 0,
                                                    Description = objText,
                                                    Needed = needed,
                                                    Collected = collected,
                                                    Update = function(self)
                                                        local objs = QuestLogCache.GetQuestObjectives(questId)
                                                        if objs then
                                                            for _, o in next, objs do
                                                                if o.text and self.Description and (o.text == self.Description or string.find(o.text, self.Description, 1, true) or string.find(self.Description, o.text, 1, true)) then
                                                                    self.Needed = o.numRequired
                                                                    self.Collected = o.numFulfilled
                                                                    break
                                                                end
                                                            end
                                                        end
                                                    end
                                                })
                                            end
                                        end
                                    end
                                end
                            end
                        end
                        if learnedObj.mc and _LearnerTooltipsEnabled() and Questie.db.profile.learnerTooltipShowConfidence ~= false then
                            tinsert(tooltipLines, "|cFF5EBAF3(Learned - Confidence: " .. tostring(learnedObj.mc) .. ")|r")
                        end
                    end
                end
             end
        end
    end

    if QuestieTooltips.lookupByKey[key] then
        local playerName = UnitName("player")
        local hasObjectiveEntries = false
        for _, tooltip in next, QuestieTooltips.lookupByKey[key] do
            if not tooltip.name then
                hasObjectiveEntries = true
                break
            end
        end

        for k, tooltip in next, QuestieTooltips.lookupByKey[key] do
            if tooltip.name then
                if Questie.db.profile.showQuestsInNpcTooltip then
                    local questString = QuestieLib:GetColoredQuestName(tooltip.questId, Questie.db.profile.enableTooltipsQuestLevel, true, true)
                    tinsert(tooltipLines, questString)
                    if not hasObjectiveEntries then
                        local objectiveSummary = _GetQuestObjectiveSummary(tooltip.questId)
                        if objectiveSummary then
                            for _, objectiveText in ipairs(objectiveSummary) do
                                tinsert(tooltipLines, "   |cFFcbcbcb" .. objectiveText .. "|r")
                            end
                        end
                    end
                end
            else
                local objective = tooltip.objective
                if objective and not (objective.IsSourceItem or objective.IsRequiredSourceItem) and objective.Update then
                    -- Tooltip was registered for a sourceItem or requiredSourceItem and not a real "objective"
                    objective:Update()
                end

                local questId = tooltip.questId
                local objectiveIndex = objective.Index;
                if (not tooltipData[questId]) then
                    tooltipData[questId] = {
                        title = QuestieLib:GetColoredQuestName(questId, Questie.db.profile.enableTooltipsQuestLevel, true, true)
                    }
                end

                if not QuestiePlayer.currentQuestlog[questId] then
                    -- TODO: Is this still required?
                    QuestieTooltips.lookupByKey[key][k] = nil
                else
                    tooltipData[questId].objectivesText = _InitObjectiveTexts(tooltipData[questId].objectivesText, objectiveIndex, playerName)

                    -- Try to get the name of the NPC/Object from the spawnList if possible
                    local creatureName
                    local idFromKey = tonumber(key:sub(3))
                    if idFromKey and objective.spawnList and objective.spawnList[idFromKey] then
                        creatureName = objective.spawnList[idFromKey].Name
                    end

                    local text;
                    local color = QuestieLib:GetRGBForObjective(objective)

                    if objective.Type == "spell" and objective.spawnList[idFromKey] and objective.spawnList[idFromKey].ItemId then
                        text = "   " .. color .. tostring(QuestieDB.QueryItemSingle(objective.spawnList[idFromKey].ItemId, "name"));
                    elseif objective.Needed then
                        text = "   " .. color .. tostring(objective.Collected) .. "/" .. tostring(objective.Needed) .. " " .. tostring(objective.Description);
                    else
                        text = "   " .. color .. tostring(objective.Description);
                    end

                    -- If we found a creature name, prepend it to the text
                    if creatureName then
                        text = "   |cFFDDDDDD" .. creatureName .. "|r\n   " .. text
                    end

                    tooltipData[questId].objectivesText[objectiveIndex][playerName] = { ["color"] = color, ["text"] = text };
                end
            end
        end
    end

    local anotherPlayer = false
    if IsInGroup() then
        anotherPlayer = _FetchTooltipsForGroupMembers(key, tooltipData)
    end

    local playerName = UnitName("player")

    for questId, questData in next, tooltipData do
        local hasObjective = false
        local tempObjectives = {}
        for _, playerList in next, questData.objectivesText or {} do
            for objectivePlayerName, objectiveInfo in next, playerList do
                local playerInfo = QuestiePlayer:GetPartyMemberByName(objectivePlayerName)
                local playerColor
                local playerType = ""
                if playerInfo then
                    playerColor = "|c" .. playerInfo.colorHex
                elseif QuestieComms.remotePlayerEnabled[objectivePlayerName] and QuestieComms.remoteQuestLogs[questId] and QuestieComms.remoteQuestLogs[questId][objectivePlayerName] and (not Questie.db.profile.onlyPartyShared or UnitInParty(objectivePlayerName)) then
                    playerColor = QuestieComms.remotePlayerClasses[playerName]
                    if playerColor then
                        playerColor = Questie:GetClassColor(playerColor)
                        playerType = " (" .. l10n("Nearby") .. ")"
                    end
                end
                if objectivePlayerName == playerName and anotherPlayer then -- why did we have this case
                    local _, classFilename = UnitClass("player");
                    local _, _, _, argbHex = GetClassColor(classFilename)
                    objectiveInfo.text = objectiveInfo.text .. " (|c" .. argbHex .. objectivePlayerName .. "|r" .. objectiveInfo.color .. ")|r"
                elseif playerColor and objectivePlayerName ~= playerName then
                    objectiveInfo.text = objectiveInfo.text .. " (" .. playerColor .. objectivePlayerName .. "|r" .. objectiveInfo.color .. ")|r" .. playerType
                end
                -- We want the player to be on top.
                if objectivePlayerName == playerName then
                    tinsert(tempObjectives, 1, objectiveInfo.text);
                    hasObjective = true
                elseif playerColor then
                    tinsert(tempObjectives, objectiveInfo.text);
                    hasObjective = true
                end
            end
        end
        if hasObjective then
            tinsert(tooltipLines, questData.title);
            for _, text in next, tempObjectives do
                tinsert(tooltipLines, text);
            end
        end
    end

    -- Append learner spawn data when the learner has recorded this NPC.
    -- Skipped for the NPC unit-hover tooltip (suppressLearnerLines): QuestieLearner's
    -- OnTooltipSetUnit hook owns that display and routes it to the main tooltip or the
    -- separate secondary learner frame, so adding it here too would duplicate it (and,
    -- with the secondary frame enabled, leak the lines back into the main tooltip).
    if not suppressLearnerLines then
        local learnerLines = _GetLearnerTooltipLines(key)
        if learnerLines then
            for _, line in ipairs(learnerLines) do
                tinsert(tooltipLines, line)
            end
        end
    end

    return tooltipLines
end

--- Public accessor for the data-source attribution line. Called by the render layer
--- (TooltipHandler) rather than appended inside GetTooltip so it never interferes with
--- the quest-title de-duplication that consumes GetTooltip's result.
---@param key string @"m_<npcId>" | "o_<objectId>" | "i_<itemId>"
function QuestieTooltips:GetDataSourceLine(key)
    return _GetTooltipSourceLine(key)
end

_InitObjectiveTexts = function(objectivesText, objectiveIndex, playerName)
    if (not objectivesText) then
        objectivesText = {}
    end
    if (not objectivesText[objectiveIndex]) then
        objectivesText[objectiveIndex] = {}
    end
    if (not objectivesText[objectiveIndex][playerName]) then
        objectivesText[objectiveIndex][playerName] = {}
    end
    return objectivesText
end

-- Apply ElvUI's "Transparent" tooltip template (flat dark background + a true 1px border)
-- so Questie's tooltips match the ElvUI style even when ElvUI is not installed. This copies
-- ElvUI/Core/Toolkit.lua SetTemplate: the exact blank texture (E.media.blankTex =
-- Interface\Buttons\WHITE8X8) for both bg and edge, edgeSize = E.mult (ONE physical pixel),
-- backdrop = E.media.backdropfadecolor {0.06,0.06,0.06} @ colorAlpha 0.8, border =
-- E.media.bordercolor {0,0,0}. Using E.mult instead of a 1-unit edge is what keeps the
-- border thin and even (a 1-unit edge renders several pixels thick at the user's UI scale).
local _ELV_FLAT = "Interface\\Buttons\\WHITE8X8" -- E.media.blankTex

-- ElvUI's E.mult: the size, in UI units, of one physical screen pixel. ElvUI scales UIParent
-- so 1 unit == 1px; without ElvUI we derive the same value: (768 / screenHeight) / uiScale.
local function _PixelMult()
    local scale = UIParent:GetScale()
    if (not scale) or scale <= 0 then scale = 1 end
    local res = GetCVar and GetCVar("gxResolution")
    local screenHeight = res and tonumber(string.match(res, "%d+x(%d+)"))
    if (not screenHeight) or screenHeight <= 0 then
        screenHeight = (GetScreenHeight and GetScreenHeight() * scale) or 768
    end
    local mult = (768 / screenHeight) / scale
    if (not mult) or mult <= 0 then mult = 1 end
    return mult
end

function QuestieTooltips:ApplyElvUISkin(frame)
    if not frame or not frame.SetBackdrop then return end
    local mult = _PixelMult()
    frame:SetBackdrop({
        bgFile = _ELV_FLAT,
        edgeFile = _ELV_FLAT,
        tile = false,
        tileSize = 0,
        edgeSize = mult,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    frame:SetBackdropColor(0.06, 0.06, 0.06, 0.8) -- backdropfadecolor @ colorAlpha
    frame:SetBackdropBorderColor(0, 0, 0, 1)      -- bordercolor (black)
end

local function _ApplyElvUIStyle(frame)
    QuestieTooltips:ApplyElvUISkin(frame)
end

-- Skins the standard tooltip frames Questie writes into. No-op when ElvUI is loaded (it
-- skins them itself) or when the option is disabled.
function QuestieTooltips:SkinDefaultTooltips()
    if (not Questie.db) or (not Questie.db.profile) or Questie.db.profile.elvuiStyleTooltips == false then return end
    if IsAddOnLoaded("ElvUI") then return end
    for _, name in ipairs({ "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2", "WorldMapTooltip" }) do
        local frame = _G[name]
        if frame then
            _ApplyElvUIStyle(frame)
            -- The default UI re-applies its template backdrop (e.g. item-quality borders) on
            -- some shows; re-assert our flat look on show so it doesn't revert.
            if not frame.__questieElvHook then
                frame.__questieElvHook = true
                frame:HookScript("OnShow", function(self)
                    if Questie.db.profile.elvuiStyleTooltips ~= false and not IsAddOnLoaded("ElvUI") then
                        _ApplyElvUIStyle(self)
                    end
                end)
            end
        end
    end
end

function QuestieTooltips:Initialize()
    -- For the clicked item frame.
    ItemRefTooltip:HookScript("OnTooltipSetItem", _QuestieTooltips.AddItemDataToTooltip)
    ItemRefTooltip:HookScript("OnHide", function(self)
        if (not self.IsForbidden) or (not self:IsForbidden()) then -- do we need this here also
            QuestieTooltips.lastGametooltip = ""
            QuestieTooltips.lastItemRefTooltip = ""
            QuestieTooltips.lastGametooltipItem = nil
            QuestieTooltips.lastGametooltipUnit = nil
            QuestieTooltips.lastGametooltipCount = 0
            QuestieTooltips.lastFrameName = "";
        end
    end)

    -- For the hover frame.
    GameTooltip:HookScript("OnTooltipSetUnit", function(self)
        if QuestiePlayer.numberOfGroupMembers > MAX_GROUP_MEMBER_COUNT then
            -- When in a raid, we want as little code running as possible
            return
        end

        _QuestieTooltips.AddUnitDataToTooltip(self)
    end)
    GameTooltip:HookScript("OnTooltipSetItem", _QuestieTooltips.AddItemDataToTooltip)
    GameTooltip:HookScript("OnShow", function(self)
        if QuestiePlayer.numberOfGroupMembers > MAX_GROUP_MEMBER_COUNT then
            -- When in a raid, we want as little code running as possible
            return
        end

        if (not self.IsForbidden) or (not self:IsForbidden()) then -- do we need this here also
            QuestieTooltips.lastGametooltipItem = nil
            QuestieTooltips.lastGametooltipUnit = nil
            QuestieTooltips.lastGametooltipCount = 0
            QuestieTooltips.lastFrameName = "";
        end
    end)
    GameTooltip:HookScript("OnHide", function(self)
        if QuestiePlayer.numberOfGroupMembers > MAX_GROUP_MEMBER_COUNT then
            -- When in a raid, we want as little code running as possible
            return
        end

        if (not self.IsForbidden) or (not self:IsForbidden()) then -- do we need this here also
            QuestieTooltips.lastGametooltip = ""
            QuestieTooltips.lastItemRefTooltip = ""
            QuestieTooltips.lastGametooltipItem = nil
            QuestieTooltips.lastGametooltipUnit = nil
            QuestieTooltips.lastGametooltipCount = 0
        end
    end)

    -- Fired whenever the cursor hovers something with a tooltip. And then on every frame.
    -- Throttled to _tooltipUpdateInterval (100ms) to avoid per-frame C API pressure.
    GameTooltip:HookScript("OnUpdate", function(self)
        if QuestiePlayer.numberOfGroupMembers > MAX_GROUP_MEMBER_COUNT then
            return
        end

        local now = GetTime()
        if now - _tooltipLastUpdate < _tooltipUpdateInterval then return end
        _tooltipLastUpdate = now

        if (not self.IsForbidden) or (not self:IsForbidden()) then
            -- Only fires for non-unit, non-item, non-spell tooltips (i.e. object/world tooltips)
            local uName, unit = self:GetUnit()
            local iName, link = self:GetItem()
            local sName, spell = self:GetSpell()
            if (uName == nil and unit == nil and iName == nil and link == nil and sName == nil and spell == nil) and (not self.ShownAsMapIcon) then
                local currentText = GameTooltipTextLeft1:GetText()
                if currentText ~= _tooltipLastText
                    or (not QuestieTooltips.lastGametooltipCount)
                    or _QuestieTooltips:CountTooltip() < QuestieTooltips.lastGametooltipCount
                    or QuestieTooltips.lastGametooltipType ~= "object" then
                    _QuestieTooltips:AddObjectDataToTooltip(currentText)
                    QuestieTooltips.lastGametooltipCount = _QuestieTooltips:CountTooltip()
                    _tooltipLastText = currentText
                end
                QuestieTooltips.lastGametooltip = currentText
            end
        end
    end)

    QuestieTooltips:SkinDefaultTooltips()
end

return QuestieTooltips
