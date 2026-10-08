---@class QuestieArrowAssets
local QuestieArrowAssets = QuestieLoader:CreateModule("QuestieArrowAssets")

---@type QuestieLib
local QuestieLib = QuestieLoader:ImportModule("QuestieLib")

QuestieArrowAssets.styles = {
    ["arrow1"] = {
        label = "Arrow 1",
        texture = "Icons\\Arrows\\Arrow1.tga",
        preview = "Icons\\Arrows\\Arrow1_preview.tga",
        mode = "image",
        displayWidth = 71,
        displayHeight = 96,
        visualBottomInset = 0,
        textureCoordLeft = 0.195312,
        textureCoordRight = 0.808594,
        textureCoordTop = 0.093750,
        textureCoordBottom = 0.917969,
    },
    ["arrow2"] = {
        label = "Arrow 2",
        texture = "Icons\\Arrows\\Arrow2.tga",
        preview = "Icons\\Arrows\\Arrow2_preview.tga",
        mode = "image",
        displayWidth = 96,
        displayHeight = 92,
        visualBottomInset = 0,
        textureCoordLeft = 0.082031,
        textureCoordRight = 0.917969,
        textureCoordTop = 0.101562,
        textureCoordBottom = 0.898438,
    },
    ["arrow3"] = {
        label = "Arrow 3",
        texture = "Icons\\Arrows\\Arrow3.tga",
        preview = "Icons\\Arrows\\Arrow3_preview.tga",
        mode = "image",
        displayWidth = 66,
        displayHeight = 96,
        visualBottomInset = 0,
        textureCoordLeft = 0.218750,
        textureCoordRight = 0.781250,
        textureCoordTop = 0.093750,
        textureCoordBottom = 0.917969,
    },
    ["arrow4"] = {
        label = "Arrow 4",
        texture = "Icons\\Arrows\\Arrow4.tga",
        preview = "Icons\\Arrows\\Arrow4_preview.tga",
        mode = "image",
        displayWidth = 68,
        displayHeight = 96,
        visualBottomInset = 0,
        textureCoordLeft = 0.347656,
        textureCoordRight = 0.648438,
        textureCoordTop = 0.289062,
        textureCoordBottom = 0.714844,
    },
    ["arrow5"] = {
        label = "Arrow 5",
        texture = "Icons\\Arrows\\Arrow5.tga",
        preview = "Icons\\Arrows\\Arrow5_preview.tga",
        mode = "image",
        displayWidth = 72,
        displayHeight = 96,
        visualBottomInset = 0,
        textureCoordLeft = 0,
        textureCoordRight = 1,
        textureCoordTop = 0,
        textureCoordBottom = 1,
    },
    ["hordearrow"] = {
        label = "Horde Arrow",
        texture = "Icons\\Arrows\\HordeArrow.tga",
        preview = "Icons\\Arrows\\HordeArrow_preview.tga",
        mode = "image",
        displayWidth = 120,
        displayHeight = 96,
        visualBottomInset = 0,
        textureCoordLeft = 0.078125,
        textureCoordRight = 0.917969,
        textureCoordTop = 0.078125,
        textureCoordBottom = 0.917969,
    },
    ["alliancearrow"] = {
        label = "Alliance Arrow",
        texture = "Icons\\Arrows\\AllianceArrow.tga",
        preview = "Icons\\Arrows\\AllianceArrow_preview.tga",
        mode = "image",
        displayWidth = 177,
        displayHeight = 96,
        visualBottomInset = 0,
        textureCoordLeft = 0.078125,
        textureCoordRight = 0.917969,
        textureCoordTop = 0.078125,
        textureCoordBottom = 0.917969,
    },
    ["arrowold"] = {
        label = "Arrow Old",
        texture = "Icons\\Arrows\\arrowold.tga",
        preview = "Icons\\Arrows\\arrowold_preview.tga",
        mode = "sheet",
        displayWidth = 56,
        displayHeight = 42,
        visualBottomInset = 0,
        textureCoordLeft = 0.001953,
        textureCoordRight = 0.982422,
        textureCoordTop = 0.005859,
        textureCoordBottom = 0.984375,
    },
}

QuestieArrowAssets.order = {
    "arrow1",
    "arrow2",
    "arrow3",
    "arrow4",
    "arrow5",
    "hordearrow",
    "alliancearrow",
    "arrowold",
}

function QuestieArrowAssets:GetStyleData(key)
    return self.styles[key]
end

function QuestieArrowAssets:GetStyleOptions()
    local values = {}
    local addonPath = (QuestieLib and QuestieLib.AddonPath) or ""
    for _, key in ipairs(self.order) do
        local style = self.styles[key]
        if style then
            values[key] = string.format('|T%s:32:32:0:0|t    %s', addonPath .. style.preview, style.label)
        end
    end
    return values
end

function QuestieArrowAssets:GetStyleOrder()
    return self.order
end

function QuestieArrowAssets:GetStyles()
    return self.styles
end
