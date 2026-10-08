-------------------------
--Import modules.
-------------------------
---@type QuestieOptions
local QuestieOptions = QuestieLoader:ImportModule("QuestieOptions")
---@type QuestieOptionsDefaults
local QuestieOptionsDefaults = QuestieLoader:ImportModule("QuestieOptionsDefaults")
---@type QuestieOptionsUtils
local QuestieOptionsUtils = QuestieLoader:ImportModule("QuestieOptionsUtils")
---@type QuestieArrow
local QuestieArrow = QuestieLoader:ImportModule("QuestieArrow")
---@type QuestieTracker
local QuestieTracker = QuestieLoader:ImportModule("QuestieTracker")

---@type l10n
local l10n = QuestieLoader:ImportModule("l10n")

local SharedMedia = LibStub and LibStub("LibSharedMedia-3.0", true)
local AceConfigRegistry = LibStub and LibStub("AceConfigRegistry-3.0", true)
local optionsDefaults = QuestieOptionsDefaults:Load()

local function RefreshOptions()
    if AceConfigRegistry and AceConfigRegistry.NotifyChange then
        AceConfigRegistry:NotifyChange("Questie")
    end
end

-- Build expanded font list from SharedMedia + common WoW fonts
local function GetExpandedFontList()
    local fonts = {}
    -- Add SharedMedia fonts if available (HashTable returns nil if media type not registered yet)
    if SharedMedia and SharedMedia.HashTable then
        local lsmFonts = SharedMedia:HashTable("font")
        if lsmFonts then
            for name, _ in pairs(lsmFonts) do
                fonts[name] = name
            end
        end
    end
    -- Add common WoW fonts not typically in SharedMedia
    local wowFonts = {
        ["Friz Quadrata TT"] = true,
        ["Friz Quadrata"] = true,
        ["Arial Narrow"] = true,
        ["Arial"] = true,
        ["Skull"] = true,
        ["Number Font"] = true,
        ["GameFontHighlight"] = true,
        ["GameFontNormal"] = true,
        ["GameFontBold"] = true,
        ["GameFontLarge"] = true,
        ["GameFontNormalSmall"] = true,
        ["ChatFontNormal"] = true,
        ["QuestFont"] = true,
        ["QuestFont_Large"] = true,
        ["DialogNormal"] = true,
    }
    for name, _ in pairs(wowFonts) do
        fonts[name] = name
    end
    return fonts
end

QuestieOptions.tabs.arrow = {}

function QuestieOptions.tabs.arrow:Initialize()
    return {
        name = function() return l10n('Arrow') end,
        type = "group",
        order = 2.5,
        args = {
            arrow_header = {
                type = "header",
                order = 1,
                name = function() return l10n('Arrow Options') end,
            },
            arrowEnabled = {
                type = "toggle",
                order = 2,
                width = 1.5,
                name = function() return l10n("Enable Arrow") end,
                desc = function() return l10n("Show the Questie arrow and auto-track the nearest objective or turn-in location.") end,
                get = function() return Questie.db.profile.arrowEnabled ~= false end,
                set = function(_, value)
                    Questie.db.profile.arrowEnabled = value
                    if QuestieArrow and QuestieArrow.Refresh then
                        if not value and QuestieArrow.ClearTarget then
                            QuestieArrow:ClearTarget()
                        end
                        QuestieArrow:Refresh()
                    end
                end,
            },
            arrow_spacer_1 = QuestieOptionsUtils:Spacer(3),
            arrowStyle = {
                type = "select",
                order = 3.1,
                width = 1.5,
                values = function()
                    if QuestieArrow and QuestieArrow.GetArrowStyleOptions then
                        return QuestieArrow:GetArrowStyleOptions()
                    end
                    return {
                        arrow1 = "Arrow 1",
                    }
                end,
                sorting = function()
                    if QuestieArrow and QuestieArrow.GetArrowStyleOrder then
                        return QuestieArrow:GetArrowStyleOrder()
                    end
                    return { "arrow1", "custom" }
                end,
                style = 'dropdown',
                name = function() return l10n("Arrow Style") end,
                desc = function()
                    return l10n("Choose which arrow artwork Questie uses. Sprite sheets animate through directional frames; regular images rotate as a single texture.")
                end,
                get = function() return Questie.db.profile.arrowStyle or optionsDefaults.profile.arrowStyle end,
                set = function(_, value)
                    Questie.db.profile.arrowStyle = value
                    if QuestieArrow and QuestieArrow.UpdateSettings then
                        QuestieArrow:UpdateSettings()
                    elseif QuestieArrow and QuestieArrow.Refresh then
                        QuestieArrow:Refresh()
                    end
                    RefreshOptions()
                end,
            },
            arrowCustomTexture = {
                type = "input",
                order = 3.2,
                width = 1.8,
                hidden = function()
                    return Questie.db.profile.arrowStyle ~= "custom"
                end,
                name = function() return l10n("Custom Arrow File") end,
                desc = function()
                    return l10n("Enter the filename of a .tga file placed in Icons\\Arrows. Only the file name is used, not the full path.")
                end,
                get = function()
                    return Questie.db.profile.arrowCustomTexture or ""
                end,
                set = function(_, value)
                    Questie.db.profile.arrowCustomTexture = value
                    if QuestieArrow and QuestieArrow.UpdateSettings then
                        QuestieArrow:UpdateSettings()
                    end
                    RefreshOptions()
                end,
            },
            arrowCustomIsSheet = {
                type = "toggle",
                order = 3.3,
                width = 1.4,
                hidden = function()
                    return Questie.db.profile.arrowStyle ~= "custom"
                end,
                name = function() return l10n("Custom Is Sprite Sheet") end,
                desc = function()
                    return l10n("Enable this only if your custom TGA is a directional sprite sheet.")
                end,
                get = function()
                    return Questie.db.profile.arrowCustomIsSheet == true
                end,
                set = function(_, value)
                    Questie.db.profile.arrowCustomIsSheet = value
                    if QuestieArrow and QuestieArrow.UpdateSettings then
                        QuestieArrow:UpdateSettings()
                    end
                    RefreshOptions()
                end,
            },
            arrow_scale = {
                type = "range",
                order = 4,
                width = 1.5,
                name = function() return l10n("Arrow Scale") end,
                desc = function() return l10n("Change the size of the arrow") end,
                min = 0.5,
                max = 4.0,
                step = 0.05,
                get = function() return Questie.db.profile.arrowScale or 1 end,
                set = function(_, value)
                    Questie.db.profile.arrowScale = value
                    if QuestieArrow and QuestieArrow.UpdateSettings then
                        QuestieArrow:UpdateSettings()
                    end
                end,
            },
            arrowLocked = {
                type = "toggle",
                order = 4.1,
                width = 1.7,
                name = function() return l10n("Lock Arrow Position") end,
                desc = function() return l10n("Prevent the arrow frame from being moved independently.") end,
                get = function() return Questie.db.profile.arrowLocked == true end,
                set = function(_, value)
                    Questie.db.profile.arrowLocked = value
                end,
            },
            arrowObjectiveLocked = {
                type = "toggle",
                order = 4.2,
                width = 1.9,
                name = function() return l10n("Lock Objective Position") end,
                desc = function() return l10n("Prevent the objective text block from being moved independently.") end,
                get = function() return Questie.db.profile.arrowObjectiveLocked == true end,
                set = function(_, value)
                    Questie.db.profile.arrowObjectiveLocked = value
                end,
            },
            arrowObjectiveAttached = {
                type = "toggle",
                order = 4.3,
                width = 1.9,
                name = function() return l10n("Attach Objective To Arrow") end,
                desc = function() return l10n("Keep the objective block anchored to the arrow instead of moving it separately.") end,
                get = function() return Questie.db.profile.arrowObjectiveAttached == true end,
                set = function(_, value)
                    Questie.db.profile.arrowObjectiveAttached = value
                    if QuestieArrow then
                        if value and QuestieArrow.AttachObjectiveToArrow then
                            QuestieArrow:AttachObjectiveToArrow()
                        elseif not value and QuestieArrow.DetachObjectiveFromArrow then
                            QuestieArrow:DetachObjectiveFromArrow()
                        end
                    end
                    RefreshOptions()
                end,
            },
            arrowObjectiveGap = {
                type = "range",
                order = 4.4,
                width = 1.8,
                name = function() return l10n("Attached Gap") end,
                desc = function() return l10n("Control the spacing between the arrow and the attached objective block.") end,
                min = 0,
                max = 40,
                step = 1,
                get = function() return Questie.db.profile.arrowObjectiveGap or 10 end,
                set = function(_, value)
                    Questie.db.profile.arrowObjectiveGap = value
                    if QuestieArrow and QuestieArrow.SetObjectiveGap then
                        QuestieArrow:SetObjectiveGap(value)
                    elseif QuestieArrow and QuestieArrow.Refresh then
                        QuestieArrow:Refresh()
                    end
                end,
            },
            arrow_alpha = {
                type = "range",
                order = 5,
                width = 1.5,
                name = function() return l10n("Arrow Transparency") end,
                desc = function() return l10n("Change the transparency of the arrow") end,
                min = 0.1,
                max = 1.0,
                step = 0.05,
                get = function() return Questie.db.profile.arrowAlpha or 1.0 end,
                set = function(_, value)
                    Questie.db.profile.arrowAlpha = value
                    if QuestieArrow and QuestieArrow.UpdateSettings then
                        QuestieArrow:UpdateSettings()
                    end
                end,
            },
            arrowObjectiveAlpha = {
                type = "range",
                order = 5.1,
                width = 1.5,
                name = function() return l10n("Objective Transparency") end,
                desc = function() return l10n("Change the transparency of the objective text block") end,
                min = 0.1,
                max = 1.0,
                step = 0.05,
                get = function() return Questie.db.profile.arrowObjectiveAlpha or 1.0 end,
                set = function(_, value)
                    Questie.db.profile.arrowObjectiveAlpha = value
                    if QuestieArrow and QuestieArrow.Refresh then
                        QuestieArrow:Refresh()
                    end
                end,
            },
            arrowDistanceUnit = {
                type = "select",
                order = 5.2,
                width = 1.5,
                name = function() return l10n("Distance Units") end,
                desc = function() return l10n("Choose the unit used for the distance label.") end,
                values = function()
                    return {
                        yards = "Yards",
                        meters = "Meters",
                        feet = "Feet",
                    }
                end,
                get = function() return Questie.db.profile.arrowDistanceUnit or "yards" end,
                set = function(_, value)
                    Questie.db.profile.arrowDistanceUnit = value
                    if QuestieArrow and QuestieArrow.Refresh then
                        QuestieArrow:Refresh()
                    end
                end,
            },
            arrow_spacer_2 = QuestieOptionsUtils:Spacer(6),
            arrowFont = {
                type = "select",
                dialogControl = 'LSM30_Font',
                order = 7,
                values = function() return GetExpandedFontList() end,
                style = 'dropdown',
                name = function() return l10n("Arrow Font") end,
                desc = function() return l10n("The font used for the arrow distance and title text.") end,
                get = function() return Questie.db.profile.arrowFont or "Friz Quadrata TT" end,
                set = function(_, value)
                    Questie.db.profile.arrowFont = value
                    if QuestieArrow and QuestieArrow.UpdateFont then
                        QuestieArrow:UpdateFont()
                    end
                end,
            },
            arrowFontSize = {
                type = "range",
                order = 8,
                name = function() return l10n("Arrow Font Size") end,
                desc = function() return l10n("The font size used for the arrow distance and title text.") end,
                width = "double",
                min = 8,
                max = 30,
                step = 1,
                get = function() return Questie.db.profile.arrowFontSize or 10 end,
                set = function(_, value)
                    Questie.db.profile.arrowFontSize = value
                    if QuestieArrow and QuestieArrow.UpdateFont then
                        QuestieArrow:UpdateFont()
                    end
                end,
            },
            arrow_spacer_3 = QuestieOptionsUtils:Spacer(8.5),
            autoTrackQuests = {
                type = "toggle",
                order = 9,
                width = 1.5,
                name = function() return l10n("Auto-track Quests") end,
                desc = function() return l10n("Automatically track all quests in your quest log. If disabled, only manually tracked quests will show on the arrow.") end,
                get = function() return Questie.db.profile.autoTrackQuests end,
                set = function(_, value)
                    Questie.db.profile.autoTrackQuests = value
                    if QuestieTracker and QuestieTracker.Update then
                        QuestieTracker:Update()
                    end
                    if QuestieArrow and QuestieArrow.Refresh then
                        QuestieArrow:Refresh()
                    end
                end,
            },
            arrow_spacer_4 = QuestieOptionsUtils:Spacer(9.5),
            resetArrowPosition = {
                type = "execute",
                order = 10,
                width = 1.0,
                name = function() return l10n("Reset Arrow Position") end,
                desc = function() return l10n("Reset the arrow position to the center of the screen") end,
                func = function()
                    Questie.db.profile.arrowPosition = nil
                    if QuestieArrow and QuestieArrow.ResetPosition then
                        QuestieArrow:ResetPosition()
                    end
                end,
            },
            resetObjectivePosition = {
                type = "execute",
                order = 10.1,
                width = 1.3,
                name = function() return l10n("Reset Objective Position") end,
                desc = function() return l10n("Reset the objective text block position to its default") end,
                func = function()
                    Questie.db.profile.arrowObjectivePosition = nil
                    if QuestieArrow and QuestieArrow.ResetObjectivePosition then
                        QuestieArrow:ResetObjectivePosition()
                    end
                end,
            },
            resetAndAttachObjective = {
                type = "execute",
                order = 10.2,
                width = 1.6,
                name = function() return l10n("Reset & Reattach") end,
                desc = function() return l10n("Reset both arrow layouts and reattach the objective block to the arrow.") end,
                func = function()
                    Questie.db.profile.arrowPosition = nil
                    Questie.db.profile.arrowObjectivePosition = nil
                    Questie.db.profile.arrowObjectiveAttached = true
                    if QuestieArrow and QuestieArrow.ResetAndAttachObjective then
                        QuestieArrow:ResetAndAttachObjective()
                    end
                    RefreshOptions()
                end,
            },
            arrow_spacer_5 = QuestieOptionsUtils:Spacer(11),
            debugArrow = {
                type = "toggle",
                order = 12,
                width = 1.5,
                name = function() return l10n("Debug Arrow") end,
                desc = function() return l10n("Show debug information about the arrow target in chat") end,
                get = function() return Questie.db.profile.debugArrow end,
                set = function(_, value)
                    Questie.db.profile.debugArrow = value
                end,
            },
            printArrowTarget = {
                type = "execute",
                order = 13,
                width = 1.0,
                name = function() return l10n("Print Current Target") end,
                desc = function() return l10n("Print the current arrow target coordinates to chat") end,
                func = function()
                    if QuestieArrow and QuestieArrow.PrintTargetCoords then
                        QuestieArrow:PrintTargetCoords()
                    end
                end,
            },
            debugPrintArrow = {
                type = "execute",
                order = 13.5,
                width = 1.0,
                name = function() return l10n("Debug Print Arrow State") end,
                desc = function() return l10n("Print detailed debug info about arrow state to chat") end,
                func = function()
                    if QuestieArrow and QuestieArrow.DebugPrint then
                        QuestieArrow:DebugPrint()
                    end
                end,
            },
            clearArrowTarget = {
                type = "execute",
                order = 14,
                width = 1.0,
                name = function() return l10n("Clear Target") end,
                desc = function() return l10n("Clear the current arrow target and resume auto-tracking") end,
                func = function()
                    if QuestieArrow and QuestieArrow.ClearTarget then
                        QuestieArrow:ClearTarget()
                        QuestieArrow:Refresh()
                    end
                end,
            },
        },
    }
end
