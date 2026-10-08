-------------------------
--Import modules.
-------------------------
---@type Questie
local Questie = QuestieLoader:ImportModule("Questie");
---@type QuestieQuest
local QuestieQuest = QuestieLoader:ImportModule("QuestieQuest");
---@type QuestieOptions
local QuestieOptions = QuestieLoader:ImportModule("QuestieOptions");
---@type QuestieOptionsDefaults
local QuestieOptionsDefaults = QuestieLoader:ImportModule("QuestieOptionsDefaults");
---@type QuestieOptionsUtils
local QuestieOptionsUtils = QuestieLoader:ImportModule("QuestieOptionsUtils");
---@type QuestieTracker
local QuestieTracker = QuestieLoader:ImportModule("QuestieTracker");
---@type IsleOfQuelDanas
local IsleOfQuelDanas = QuestieLoader:ImportModule("IsleOfQuelDanas");
---@type l10n
local l10n = QuestieLoader:ImportModule("l10n")
---@type QuestieCompat
local QuestieCompat = QuestieLoader:ImportModule("QuestieCompat")
---@type QuestieDB
local QuestieDB = QuestieLoader:ImportModule("QuestieDB")

QuestieOptions.tabs.advanced = {}
local optionsDefaults = QuestieOptionsDefaults:Load()
local _GetLanguages

local function GetLearnerSettings()
    Questie.dbLearner = Questie.dbLearner or {}
    Questie.dbLearner.global = Questie.dbLearner.global or {}
    Questie.dbLearner.global.settings = Questie.dbLearner.global.settings or {}
    local settings = Questie.dbLearner.global.settings
    if settings.performanceMode == nil then
        settings.performanceMode = "balanced"
    end
    if settings.pinRefreshDelay == nil then
        settings.pinRefreshDelay = 0.75
    end
    if settings.pinRefreshMode == nil then
        settings.pinRefreshMode = "batched"
    end
    if settings.pinRefreshMaxWait == nil then
        settings.pinRefreshMaxWait = 5.0
    end
    if settings.liveNpcUpdateDelay == nil then
        settings.liveNpcUpdateDelay = 0.75
    end
    if settings.learnerCommsIntensity == nil then
        settings.learnerCommsIntensity = "normal"
    end
    if settings.minConfidencePins == nil then
        settings.minConfidencePins = 1
    end
    if settings.spawnDedupRadius == nil then
        settings.spawnDedupRadius = 4.0
    end
    return settings
end

local function ApplyLearnerPerformancePreset(mode)
    local settings = GetLearnerSettings()
    settings.performanceMode = mode

    if mode == "realtime" then
        settings.pinRefreshDelay = 0.1
        settings.pinRefreshMode = "immediate"
        settings.pinRefreshMaxWait = 2.0
        settings.liveNpcUpdateDelay = 0.25
        settings.learnerCommsIntensity = "fast"
        settings.minConfidencePins = 1
    elseif mode == "low" then
        settings.pinRefreshDelay = 2.0
        settings.pinRefreshMode = "batched"
        settings.pinRefreshMaxWait = 10.0
        settings.liveNpcUpdateDelay = 2.0
        settings.learnerCommsIntensity = "low"
        settings.minConfidencePins = 3
    elseif mode == "balanced" then
        settings.pinRefreshDelay = 0.75
        settings.pinRefreshMode = "batched"
        settings.pinRefreshMaxWait = 5.0
        settings.liveNpcUpdateDelay = 0.75
        settings.learnerCommsIntensity = "normal"
        settings.minConfidencePins = 1
    end

    if mode == "realtime" or mode == "balanced" or mode == "low" then
        Questie.db.profile.learnerBroadcast = true
    end
end

local function RefreshLearnerRuntime()
    local QuestieLearner = QuestieLoader:ImportModule("QuestieLearner")
    if QuestieLearner and QuestieLearner.RefreshLiveState then
        QuestieLearner:RefreshLiveState()
    end
end

function QuestieOptions.tabs.advanced:Initialize()
    -- This needs to be called inside of the Init process for l10n to be fully loaded
    StaticPopupDialogs["QUESTIE_LANG_CHANGED_RELOAD"] = {
        button1 = l10n('Reload UI'),
        button2 = l10n('Cancel'),
        OnAccept = function()
            ReloadUI()
        end,
        text = l10n('The database needs to be updated to change language. Press reload to apply the new language'),
        OnShow = function(self)
            self:SetFrameStrata("TOOLTIP")
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3
    }

    return {
        name = function() return l10n('Advanced'); end,
        type = "group",
        order = 7,
        args = {
            map_options = {
                type = "header",
                order = 1,
                name = function() return l10n('Advanced Settings'); end,
            },
            enableIconLimit = {
                type = "toggle",
                order = 1.1,
                name = function() return l10n('Enable Icon Limit'); end,
                desc = function() return l10n('Enable the limit of icons drawn per type.'); end,
                width = "full",
                get = function (info) return QuestieOptions:GetProfileValue(info); end,
                set = function (info, value)
                    QuestieOptions:SetProfileValue(info, value)
                    QuestieOptionsUtils:Delay(0.05, QuestieQuest.SmoothReset, l10n('Setting icon limit value to %s : Redrawing!', value))
                end,
            },
            iconLimit = {
                type = "range",
                order = 1.2,
                name = function() return l10n('Icon Limit'); end,
                desc = function() return l10n('Limits the amount of icons drawn per type. ( Default: %s )', optionsDefaults.profile.iconLimit); end,
                width = 1.5,
                min = 10,
                max = 500,
                step = 10,
                disabled = function() return (not Questie.db.profile.enableIconLimit); end,
                get = function(info) return QuestieOptions:GetProfileValue(info); end,
                set = function (info, value)
                    QuestieOptions:SetProfileValue(info, value)
                    QuestieOptionsUtils:Delay(0.05, QuestieQuest.SmoothReset, l10n('Setting icon limit value to %s : Redrawing!', value))
                end,
            },
            iconSpacer = {
                type = "description",
                order = 1.3,
                name = "",
                desc = "",
                image = "",
                imageWidth = 0.3,
                width = 0.3,
                func = function() end,
            },
            clusterLevelHotzone = {
                type = "range",
                order = 1.4,
                name = function() return l10n('Objective icon cluster amount'); end,
                desc = function() return l10n('How much objective icons should cluster.'); end,
                width = 1.5,
                disabled = function() return (not Questie.db.profile.enabled); end,
                min = 1,
                max = 300,
                step = 1,
                get = function(info) return QuestieOptions:GetProfileValue(info); end,
                set = function(info, value)
                    QuestieOptionsUtils:Delay(0.05, QuestieOptions.ClusterRedraw, l10n('Setting clustering value, clusterLevelHotzone set to %s : Redrawing!', value))
                    QuestieOptions:SetProfileValue(info, value)
                    QuestieOptionsUtils.DetermineTheme()
                end,
            },
            clusterDensityAggressiveness = {
                type = "range",
                order = 1.41,
                name = function() return l10n('Dense pin clustering aggressiveness'); end,
                desc = function() return l10n('How aggressively crowded kill objectives are consolidated into fewer pins. 0 shows every pin; higher values tighten clustering where many pins share a zone. Coincident pins are always deduplicated.'); end,
                width = 1.5,
                disabled = function() return (not Questie.db.profile.enabled); end,
                min = 0,
                max = 100,
                step = 5,
                get = function(info) return QuestieOptions:GetProfileValue(info); end,
                set = function(info, value)
                    QuestieOptions:SetProfileValue(info, value)
                    QuestieOptionsUtils:Delay(0.05, QuestieOptions.ClusterRedraw, l10n('Setting dense pin clustering aggressiveness to %s : Redrawing!', value))
                end,
            },
            quelDanasSpacer1 = QuestieOptionsUtils:Spacer(1.45, (not Questie.IsTBC)),
            npcrules_group = {
                type = "group",
                order = 1.5,
                inline = true,
                width = 0.5,
                hidden = (not Questie.IsTBC),
                name = function() return l10n("Quel'Danas Settings"); end,
                disabled = function() return not Questie.db.profile.autoaccept end,
                args = {
                    isleOfQuelDanasPhase = {
                        type = "select",
                        order = 1.3,
                        width = 1.5,
                        values = IsleOfQuelDanas.localizedPhaseNames,
                        style = 'dropdown',
                        name = function() return l10n("Isle of Quel'Danas Phase") end,
                        desc = function() return l10n("Select the phase fitting your realm progress on the Isle of Quel'Danas"); end,
                        disabled = function() return (not Questie.IsWotlk) end,
                        get = function() return Questie.db.profile.isleOfQuelDanasPhase; end,
                        set = function(_, key)
                            Questie.db.profile.isleOfQuelDanasPhase = key
                            QuestieQuest:SmoothReset()
                        end,
                    },
                    quelDanasSpacer2 = {
                        type = "description",
                        order = 1.4,
                        name = "",
                        desc = "",
                        image = "",
                        imageWidth = 0.2,
                        width = 0.2,
                        func = function() end,
                    },
                    isleOfQuelDanasPhaseReminder = {
                        type = "toggle",
                        order = 1.5,
                        name = function() return l10n('Disable Phase reminder'); end,
                        desc = function() return l10n("Enable or disable the reminder on login to set the Isle of Quel'Danas phase"); end,
                        disabled = function() return (not Questie.IsWotlk) end,
                        width = 1,
                        get = function() return Questie.db.profile.isIsleOfQuelDanasPhaseReminderDisabled; end,
                        set = function(_, value)
                            Questie.db.profile.isIsleOfQuelDanasPhaseReminderDisabled = value
                        end,
                    },
                },
            },

            learnerPerformanceSpacer = QuestieOptionsUtils:Spacer(1.9),
            learnerPerformanceHeader = {
                type = "header",
                order = 2,
                name = function() return l10n('QuestieLearner Performance'); end,
            },
            learnerPerformanceMode = {
                type = "select",
                order = 2.1,
                values = {
                    realtime = l10n("Realtime"),
                    balanced = l10n("Balanced"),
                    low = l10n("Low Impact"),
                    manual = l10n("Manual"),
                },
                style = "dropdown",
                name = function() return l10n('Performance Mode'); end,
                desc = function() return l10n('Controls how aggressively QuestieLearner updates learned pins, live data, and learner comms. Low Impact is recommended for heavy activity zones or low-end computers.'); end,
                get = function() return GetLearnerSettings().performanceMode or "balanced" end,
                set = function(_, value)
                    ApplyLearnerPerformancePreset(value)
                    RefreshLearnerRuntime()
                end,
            },
            learnerPinRefreshMode = {
                type = "select",
                order = 2.2,
                values = {
                    immediate = l10n("Immediate"),
                    batched = l10n("Batched"),
                    manual = l10n("Manual / Reload"),
                },
                style = "dropdown",
                name = function() return l10n('Pin Refresh Behavior'); end,
                desc = function() return l10n('Controls when learned pins refresh after QuestieLearner records new data. Manual / Reload records data but avoids live pin redraws until reload or another Questie refresh.'); end,
                get = function() return GetLearnerSettings().pinRefreshMode or "batched" end,
                set = function(_, value)
                    local settings = GetLearnerSettings()
                    settings.pinRefreshMode = value
                    settings.performanceMode = "manual"
                    RefreshLearnerRuntime()
                end,
            },
            learnerPinRefreshDelay = {
                type = "range",
                order = 2.3,
                name = function() return l10n('Pin Refresh Delay'); end,
                desc = function() return l10n('Seconds to wait before refreshing learned quest pins after learner activity. Higher values reduce stutter during kill or loot bursts.'); end,
                min = 0.1,
                max = 5,
                step = 0.1,
                width = 1.5,
                get = function() return GetLearnerSettings().pinRefreshDelay or 0.5 end,
                set = function(_, value)
                    local settings = GetLearnerSettings()
                    settings.pinRefreshDelay = value
                    settings.performanceMode = "manual"
                    RefreshLearnerRuntime()
                end,
            },
            learnerPinRefreshMaxWait = {
                type = "range",
                order = 2.35,
                name = function() return l10n('Pin Refresh Max Wait'); end,
                desc = function() return l10n('Maximum seconds learned pins will wait during continuous activity (e.g. nearby players killing mobs) before a forced refresh. The refresh delay resets on each kill, so pins only redraw once things go quiet or this cap is hit. Set to 0 to never force a refresh while activity continues.'); end,
                min = 0,
                max = 30,
                step = 0.5,
                width = 1.5,
                get = function() return GetLearnerSettings().pinRefreshMaxWait or 5.0 end,
                set = function(_, value)
                    local settings = GetLearnerSettings()
                    settings.pinRefreshMaxWait = value
                    settings.performanceMode = "manual"
                    RefreshLearnerRuntime()
                end,
            },
            learnerLiveNpcUpdateDelay = {
                type = "range",
                order = 2.4,
                name = function() return l10n('Live NPC Update Delay'); end,
                desc = function() return l10n('Seconds to batch learned NPC live database updates. Higher values reduce work during combat and crowded zones.'); end,
                min = 0.25,
                max = 5,
                step = 0.25,
                width = 1.5,
                get = function() return GetLearnerSettings().liveNpcUpdateDelay or 0.5 end,
                set = function(_, value)
                    local settings = GetLearnerSettings()
                    settings.liveNpcUpdateDelay = value
                    settings.performanceMode = "manual"
                    RefreshLearnerRuntime()
                end,
            },
            learnerMinConfidencePins = {
                type = "range",
                order = 2.5,
                name = function() return l10n('Minimum Kills Before Learned Pins'); end,
                desc = function() return l10n('How many matching NPC sightings are needed before QuestieLearner shows learned pins. Higher values reduce one-off pin churn.'); end,
                min = 1,
                max = 10,
                step = 1,
                width = 1.5,
                get = function() return GetLearnerSettings().minConfidencePins or 1 end,
                set = function(_, value)
                    local settings = GetLearnerSettings()
                    settings.minConfidencePins = value
                    settings.performanceMode = "manual"
                    RefreshLearnerRuntime()
                end,
            },
            learnerSpawnDedupRadius = {
                type = "range",
                order = 2.55,
                name = function() return l10n('Spawn Pin Dedup Radius'); end,
                desc = function() return l10n('How close two learned kill positions must be (in map %) to merge into a single pin. Higher values show fewer, tighter pins per spawn; 0 shows every distinct position.'); end,
                min = 0,
                max = 15,
                step = 0.5,
                width = 1.5,
                get = function() return GetLearnerSettings().spawnDedupRadius or 4.0 end,
                set = function(_, value)
                    GetLearnerSettings().spawnDedupRadius = value
                    -- Spawn tables are cached per NPC; clear so the new radius is
                    -- applied on the redraw instead of serving stale merged coords.
                    if QuestieDB and QuestieDB.ClearModeCaches then
                        QuestieDB:ClearModeCaches()
                    end
                    QuestieOptions:ClusterRedraw()
                end,
            },
            learnerCommsIntensity = {
                type = "select",
                order = 2.6,
                values = {
                    off = l10n("Off"),
                    low = l10n("Low"),
                    normal = l10n("Normal"),
                    fast = l10n("Fast"),
                },
                style = "dropdown",
                name = function() return l10n('Learner Comms Intensity'); end,
                desc = function() return l10n('Controls how much learner data Questie processes and sends through learner comms. Lower values reduce CPU and chat-channel work.'); end,
                get = function() return GetLearnerSettings().learnerCommsIntensity or "normal" end,
                set = function(_, value)
                    local settings = GetLearnerSettings()
                    settings.learnerCommsIntensity = value
                    settings.performanceMode = "manual"
                    if value == "off" then
                        Questie.db.profile.learnerBroadcast = false
                    elseif Questie.db.profile.learnerBroadcast == false then
                        Questie.db.profile.learnerBroadcast = true
                    end
                    RefreshLearnerRuntime()
                end,
            },

            arrowPerformanceSpacer = QuestieOptionsUtils:Spacer(2.69),
            arrowPerformanceHeader = {
                type = "header",
                order = 2.7,
                name = function() return l10n('QuestieArrow Performance'); end,
            },
            arrowUpdateThrottle = {
                type = "range",
                order = 2.71,
                width = 1.5,
                name = function() return l10n('Arrow Movement Update Interval'); end,
                desc = function() return l10n('Seconds between arrow rotation and distance updates. Higher values reduce CPU usage but make the arrow feel less smooth.'); end,
                min = 0.03,
                max = 0.5,
                step = 0.01,
                get = function() return Questie.db.profile.arrowUpdateThrottle or optionsDefaults.profile.arrowUpdateThrottle end,
                set = function(_, value)
                    Questie.db.profile.arrowUpdateThrottle = value
                    local QuestieArrow = QuestieLoader:ImportModule("QuestieArrow")
                    if QuestieArrow and QuestieArrow.Refresh then
                        QuestieArrow:Refresh()
                    end
                end,
            },
            arrowRecalcInterval = {
                type = "range",
                order = 2.72,
                width = 1.5,
                name = function() return l10n('Target Scan Interval'); end,
                desc = function() return l10n('Seconds between full nearest-objective scans. Higher values reduce HBD and ZoneDB work in large quest logs.'); end,
                min = 0.5,
                max = 10,
                step = 0.5,
                get = function() return Questie.db.profile.arrowRecalcInterval or optionsDefaults.profile.arrowRecalcInterval end,
                set = function(_, value)
                    Questie.db.profile.arrowRecalcInterval = value
                    local QuestieArrow = QuestieLoader:ImportModule("QuestieArrow")
                    if QuestieArrow and QuestieArrow.Refresh then
                        QuestieArrow:Refresh()
                    end
                end,
            },
            arrowTrackerRefreshThrottle = {
                type = "range",
                order = 2.73,
                width = 1.5,
                name = function() return l10n('Tracker Refresh Throttle'); end,
                desc = function() return l10n('Minimum seconds between arrow refreshes triggered by tracker updates. Higher values reduce refresh bursts during quest progress changes.'); end,
                min = 0.25,
                max = 5,
                step = 0.25,
                get = function() return Questie.db.profile.arrowTrackerRefreshThrottle or optionsDefaults.profile.arrowTrackerRefreshThrottle end,
                set = function(_, value)
                    Questie.db.profile.arrowTrackerRefreshThrottle = value
                    local QuestieArrow = QuestieLoader:ImportModule("QuestieArrow")
                    if QuestieArrow and QuestieArrow.Refresh then
                        QuestieArrow:Refresh()
                    end
                end,
            },

            questieCommsPerformanceSpacer = QuestieOptionsUtils:Spacer(2.79),
            questieCommsPerformanceHeader = {
                type = "header",
                order = 2.8,
                name = function() return l10n('QuestieComms Performance'); end,
            },
            questieCommsEnabled = {
                type = "toggle",
                order = 2.805,
                name = function() return l10n('Enable QuestieComms'); end,
                desc = function() return l10n('Enable Questie group quest-progress communication. Disabling this stops outgoing QuestieComms and ignores incoming QuestieComms immediately.'); end,
                width = 1.5,
                get = function() return Questie.db.profile.questieCommsEnabled ~= false end,
                set = function(_, value)
                    Questie.db.profile.questieCommsEnabled = value
                    local QuestieComms = QuestieLoader:ImportModule("QuestieComms")
                    if QuestieComms and QuestieComms.ResetAll then
                        QuestieComms:ResetAll()
                    end
                end,
            },
            questieCommsQuestListPacketSize = {
                type = "range",
                order = 2.81,
                name = function() return l10n('Quest List Packet Size'); end,
                desc = function() return l10n('Maximum serialized payload size per full quest-list block. Lower values create smaller packets but may send more blocks.'); end,
                min = 100,
                max = 500,
                step = 25,
                width = 1.5,
                disabled = function() return Questie.db.profile.questieCommsEnabled == false end,
                get = function() return Questie.db.profile.questieCommsQuestListPacketSize or optionsDefaults.profile.questieCommsQuestListPacketSize end,
                set = function(_, value)
                    Questie.db.profile.questieCommsQuestListPacketSize = value
                end,
            },
            questieCommsQuestListInitialJitter = {
                type = "range",
                order = 2.82,
                name = function() return l10n('Quest List Initial Jitter'); end,
                desc = function() return l10n('Maximum random delay before responding with a full quest list. Higher values spread group responses out to reduce bursts.'); end,
                min = 0,
                max = 10,
                step = 0.5,
                width = 1.5,
                disabled = function() return Questie.db.profile.questieCommsEnabled == false end,
                get = function() return Questie.db.profile.questieCommsQuestListInitialJitter or optionsDefaults.profile.questieCommsQuestListInitialJitter end,
                set = function(_, value)
                    Questie.db.profile.questieCommsQuestListInitialJitter = value
                end,
            },
            questieCommsQuestListBlockInterval = {
                type = "range",
                order = 2.83,
                name = function() return l10n('Quest List Block Interval'); end,
                desc = function() return l10n('Seconds between full quest-list blocks. Higher values reduce comms bursts on slower systems and crowded groups.'); end,
                min = 0.5,
                max = 10,
                step = 0.5,
                width = 1.5,
                disabled = function() return Questie.db.profile.questieCommsEnabled == false end,
                get = function() return Questie.db.profile.questieCommsQuestListBlockInterval or optionsDefaults.profile.questieCommsQuestListBlockInterval end,
                set = function(_, value)
                    Questie.db.profile.questieCommsQuestListBlockInterval = value
                end,
            },

            Spacer_A = QuestieOptionsUtils:Spacer(2.9),
            locale_header = {
                type = "header",
                order = 3,
                name = function() return l10n('Localization Settings'); end,
            },
            locale_dropdown = {
                type = "select",
                order = 3.1,
                values = _GetLanguages(),
                style = 'dropdown',
                name = function() return l10n('Select UI Locale'); end,
                get = function()
                    if not Questie.db.global.questieLocaleDiff then
                        return 'auto'
                    else
                        return l10n:GetUILocale();
                    end
                end,
                set = function(_, lang)
                    local previousLocale = Questie.db.global.questieLocale
                    if lang == 'auto' then
                        local clientLocale = GetLocale()
                        if QUESTIE_LOCALES_OVERRIDE ~= nil then
                            clientLocale = QUESTIE_LOCALES_OVERRIDE.locale
                        end
                        l10n:SetUILocale(clientLocale)
                        Questie.db.global.questieLocale = clientLocale
                        Questie.db.global.questieLocaleDiff = false
                    else
                        l10n:SetUILocale(lang);
                        Questie.db.global.questieLocale = lang;
                        Questie.db.global.questieLocaleDiff = true;
                    end

                    if previousLocale ~= Questie.db.global.questieLocale then
                        if Questie.IsSoD then
                            Questie.db.global.sod.dbIsCompiled = nil -- recompile db with new lang if locale changed
                        else
                            Questie.db.global.dbIsCompiled = nil -- recompile db with new lang if locale changed
                        end
                        StaticPopup_Show("QUESTIE_LANG_CHANGED_RELOAD")
                    end
                end,
            },
            Spacer_C = QuestieOptionsUtils:Spacer(3.9),
            reset_header = {
                type = "header",
                order = 4,
                name = function() return l10n('Reset Questie'); end,
            },
            Spacer_D = QuestieOptionsUtils:Spacer(22),
            reset_text = {
                type = "description",
                order = 4.1,
                name = function() return l10n('Hitting this button will reset all of the Questie configuration settings back to their default values. (Excluding Localization)'); end,
                fontSize = "medium",
            },
            questieReset = {
                type = "execute",
                order = 4.2,
                name = function() return l10n('Reset Questie'); end,
                desc = function() return l10n('Reset Questie to the default values for all settings.'); end,
                func = function (_, _)
                    -- update all values to default
                    for k,v in pairs(optionsDefaults.profile) do
                       Questie.db.profile[k] = v
                    end

                    -- only toggle questie if it's off (must be called before resetting the value)
                    if (not Questie.db.profile.enabled) then
                        Questie.db.profile.enabled = true
                        --QuestieQuest:ToggleNotes(true);
                    end

                    Questie.db.profile.enabled = optionsDefaults.profile.enabled;
                    Questie.db.profile.lowLevelStyle = optionsDefaults.profile.lowLevelStyle;

                    Questie.db.profile.migrationVersion = nil

                    Questie.db.profile.minimap.hide = optionsDefaults.profile.minimap.hide;

                    if Questie.IsSoD then
                        Questie.db.global.sod.dbIsCompiled = false
                    else
                        Questie.db.global.dbIsCompiled = false
                    end

                    Questie.db.char.hidden = nil
                    Questie.db.char.hiddenDailies = optionsDefaults.char.hiddenDailies;

                    ReloadUI()

                end,
            },
            Spacer_E = QuestieOptionsUtils:Spacer(4.3),
            recompileDatabase = {
                type = "execute",
                order = 4.4,
                name = function() return l10n('Recompile Database'); end,
                desc = function() return l10n('Forces a recompile of the Questie database. This will also reload the UI.'); end,
                func = function (_, _)
                    if Questie.IsSoD then
                        Questie.db.global.sod.dbIsCompiled = false
                    else
                        Questie.db.global.dbIsCompiled = false
                    end
                    ReloadUI()
                end,
            },
            Spacer_F = QuestieOptionsUtils:Spacer(4.5),
            openProfiler = {
                type = "execute",
                order = 4.6,
                name = function() return l10n('Open Profiler'); end,
                desc = function() return l10n('Open the Questie profiler, this is useful for tracking down the source of lag / frame spikes.'); end,
                func = function (_, _)
                    QuestieLoader:ImportModule("Profiler"):Start()
                end,
            },
            Spacer_G = QuestieOptionsUtils:Spacer(4.7),
            github_text = {
                type = "description",
                order = 4.8,
                name = function() return Questie:Colorize(l10n('Questie-X is under active development and being maintained by Xurkon. Please check my GitHub for the latest build or to report issues. (( https://github.com/Xurkon/Questie-X ))'), '87CEEB'); end,
                fontSize = "medium",
            },
            HeaderDev = {
                type = "header",
                order = 5,
                name = l10n('Developer Options'),
            },
            bugWorkarounds = {
                type = "toggle",
                order = 5.01,
                name = function() return l10n('Enable bug workarounds'); end,
                desc = function() return l10n('When enabled, Questie will hotfix vanilla UI bugs.'); end,
                width = "full",
                get = function() return Questie.db.profile.bugWorkarounds; end,
                set = function (_, value)
                    Questie.db.profile.bugWorkarounds = value
                end
            },
            showItemIDs = {
                type = "toggle",
                order = 5.02,
                name = function() return l10n('Show Item IDs'); end,
                desc = function() return l10n('When this is checked, the ID of items will shown in tooltips.'); end,
                disabled = function() return (not Questie.db.profile.enableTooltips); end,
                width = "full",
                get = function() return Questie.db.profile.enableTooltipsItemID; end,
                set = function (_, value)
                    Questie.db.profile.enableTooltipsItemID = value
                end
            },
            showNPCIDs = {
                type = "toggle",
                order = 5.03,
                name = function() return l10n('Show NPC IDs'); end,
                desc = function() return l10n('When this is checked, the ID of NPCs will be shown in tooltips.'); end,
                disabled = function() return (not Questie.db.profile.enableTooltips); end,
                width = "full",
                get = function() return Questie.db.profile.enableTooltipsNPCID; end,
                set = function (_, value)
                    Questie.db.profile.enableTooltipsNPCID = value
                end
            },
            showObjectIDs = {
                type = "toggle",
                order = 5.04,
                name = function() return l10n('Show Object IDs'); end,
                desc = function() return l10n('When this is checked, the ID of objects will be shown in tooltips. These are guesses and only show the first matching ID in the QuestieDB.'); end,
                disabled = function() return (not Questie.db.profile.enableTooltips); end,
                width = "full",
                get = function() return Questie.db.profile.enableTooltipsObjectID; end,
                set = function (_, value)
                    Questie.db.profile.enableTooltipsObjectID = value
                end
            },
            showQuestIDs = {
                type = "toggle",
                order = 5.05,
                name = function() return l10n('Show Quest IDs'); end,
                desc = function() return l10n('When this is checked, the ID of quests will show in tooltips and the tracker.'); end,
                disabled = function() return (not Questie.db.profile.enableTooltips); end,
                width = "full",
                get = function() return Questie.db.profile.enableTooltipsQuestID; end,
                set = function (_, value)
                    Questie.db.profile.enableTooltipsQuestID = value
                    QuestieTracker:Update()
                end
            },
            debugEnabled = {
                type = "toggle",
                order = 5.06,
                name = function() return l10n('Enable Debug'); end,
                desc = function() return l10n('Enable or disable debug functionality.'); end,
                width = "full",
                get = function () return Questie.db.profile.debugEnabled; end,
                set = function (_, value)
                    Questie.db.profile.debugEnabled = value
                    if Questie.db.profile.debugEnabled then
                        QuestieLoader:PopulateGlobals()
                    end
                end,
            },
            skipValidation = {
                type = "toggle",
                order = 5.07,
                name = function() return l10n('Skip Validation'); end,
                desc = function() return l10n('Skip database validation upon recompile. Validation is only present with debug enabled in the first place.'); end,
                width = "full",
                disabled = function() return not Questie.db.profile.debugEnabled; end,
                get = function () return Questie.db.profile.skipValidation; end,
                set = function (_, value)
                    Questie.db.profile.skipValidation = value
                end,
            },
            debugEnabledPrint = {
                type = "toggle",
                order = 5.08,
                disabled = function() return not Questie.db.profile.debugEnabled; end,
                name = function() return l10n('Enable Debug').."-PRINT" end,
                desc = function() return l10n('Enable or disable debug functionality.').."-PRINT" end,
                width = "full",
                get = function () return Questie.db.profile.debugEnabledPrint; end,
                set = function (_, value)
                    Questie.db.profile.debugEnabledPrint = value
                end,
            },
            debugLevel = {
                type = "multiselect",
                values = {
                    [0] = "DEBUG_CRITICAL",
                    [1] = "DEBUG_ELEVATED",
                    [2] = "DEBUG_INFO",
                    [3] = "DEBUG_DEVELOP",
                    [4] = "DEBUG_SPAM",
                    [5] = "DEBUG_LEARNER",
                    [6] = "DEBUG_COMMS",
                },
                order = 5.09,
                name = function() return l10n('Debug level to print'); end,
                width = "normal",
                disabled = function() return not (Questie.db.profile.debugEnabledPrint and Questie.db.profile.debugEnabled); end,
                get = function(_, key)
                    --Questie:Debug(Questie.DEBUG_SPAM, "Debug Key:", key, math.pow(2, key), state.option.values[key])
                    --Questie:Debug(Questie.DEBUG_SPAM, "Debug Level:", Questie.db.profile.debugLevel, bit.band(Questie.db.profile.debugLevel, math.pow(2, key)))
                    return bit.band(Questie.db.profile.debugLevel, math.pow(2, key)) > 0
                end,
                set = function (_, value)
                    local currentValue = Questie.db.profile.debugLevel
                    local flag = math.pow(2, value)
                    --Questie:Debug(Questie.DEBUG_SPAM, "Setting Debug:", currentValue, flag, bit.band(currentValue, flag)>0)
                    -- When current debug level is active, remove it
                    if (bit.band(currentValue, flag) > 0) then
                        Questie.db.profile.debugLevel = bit.bxor(flag, currentValue)
                    -- When current debug level is inactive, add it
                    else
                        Questie.db.profile.debugLevel = bit.bor(flag, currentValue)
                    end
                end,
            },
            debugMessageThrottle = {
                type = "range",
                order = 5.10,
                name = function() return l10n('Debug message throttle'); end,
                desc = function() return l10n('Minimum seconds between debug lines. Higher values reduce spam while keeping fatal output separate.') end,
                width = "full",
                min = 0,
                max = 1,
                step = 0.05,
                disabled = function() return not (Questie.db.profile.debugEnabledPrint and Questie.db.profile.debugEnabled); end,
                get = function() return Questie.db.profile.debugMessageThrottle or 0 end,
                set = function(_, value)
                    Questie.db.profile.debugMessageThrottle = value
                end,
            },
            compat_header = {
                type = "header",
                order = 6,
                name = "3.3.5 Compatibility Settings",
                hidden = function() return not (Questie.IsWotlk or (QuestieCompat and QuestieCompat.Is335)) end,
            },
            useWotlkMapData = {
                type = "toggle",
                order = 6.1,
                name = "Use WotLK map data",
                desc = "Use WotLK map data for exploration and coordinates.",
                width = 1.65,
                hidden = function() return not (Questie.IsWotlk or (QuestieCompat and QuestieCompat.Is335)) end,
                get = function(info) return QuestieOptions:GetProfileValue(info); end,
                set = function(info, value)
                    QuestieOptions:SetProfileValue(info, value)
                    StaticPopup_Show("QUESTIE_RELOAD")
                end,
            },
            initDelay = {
                type = "range",
                order = 6.2,
                name = "Init rate delay",
                desc = "Adjust the initialization rate delay (seconds) for slower systems.",
                width = 1.65,
                min = 0.01,
                max = 0.5,
                step = 0.01,
                hidden = function() return not (Questie.IsWotlk or (QuestieCompat and QuestieCompat.Is335)) or not Questie.db.profile.debugEnabled end,
                get = function(info) return Questie.db.profile.initDelay or 0.05; end,
                set = function(info, value)
                    Questie.db.profile.initDelay = value
                end,
            },
            resetDailyQuests = {
                type = "toggle",
                order = 6.3,
                name = "Reset Daily Quests",
                desc = "Force a daily quest reset check.",
                width = 1.65,
                hidden = function() return not (Questie.IsWotlk or (QuestieCompat and QuestieCompat.Is335)) end,
                get = function(info) return QuestieOptions:GetProfileValue(info); end,
                set = function(info, value)
                    QuestieOptions:SetProfileValue(info, value)
                    Questie.db.profile.dailyResetTime = nil
                    StaticPopup_Show("QUESTIE_RELOAD")
                end,
            },
            weeklyResetDay = {
                type = "select",
                order = 6.4,
                values = {
                    [1] = "Sunday",
                    [2] = "Monday",
                    [3] = "Tuesday",
                    [4] = "Wednesday",
                    [5] = "Thursday",
                    [6] = "Friday",
                    [7] = "Saturday",
                },
                style = 'dropdown',
                name = "Weekly Reset Day",
                disabled = function() return not Questie.db.profile.resetDailyQuests end,
                hidden = function() return not (Questie.IsWotlk or (QuestieCompat and QuestieCompat.Is335)) end,
                get = function(info) return QuestieOptions:GetProfileValue(info) or 3; end,
                set = function(info, value)
                    QuestieOptions:SetProfileValue(info, value)
                end,
            },

        },
    }
end

_GetLanguages = function()
    local languages = {
        ['auto'] = l10n('Automatic'),
        ['enUS'] = 'English',
        ['esES'] = 'Español',
        ['esMX'] = 'Español (América Latina)',
        ['ptBR'] = 'Português',
        ['frFR'] = 'Français',
        ['deDE'] = 'Deutsch',
        ['ruRU'] = 'Русский',
        ['zhCN'] = '简体中文',
        ['zhTW'] = '正體中文',
        ['koKR'] = '한국어',
    }
    if QUESTIE_LOCALES_OVERRIDE ~= nil then
        languages[QUESTIE_LOCALES_OVERRIDE.locale] = QUESTIE_LOCALES_OVERRIDE.localeName
    end
    return languages
end
