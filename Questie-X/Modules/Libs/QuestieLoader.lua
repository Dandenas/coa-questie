-- Shim for Lua 5.2+ (Retail) where table.getn was removed.
-- We cannot use the '#' length operator directly because Lua 5.0
-- will trigger a compile-time syntax error parsing the file.
-- Using loadstring bypasses the 5.0 compiler and safely injects the # operator in 5.2+.
if not table.getn then
    local loadFunc = loadstring or load
    if loadFunc then
        table.getn = loadFunc("return function(t) return #t end")()
    end
end

-- Shim for Lua 5.1+ (Ascension/Ebonhold/Retail) where math.mod was renamed/removed.
-- We cannot use the '%' modulo operator directly because Lua 5.0
-- will trigger a compile-time syntax error parsing the file.
if not math.mod then
    local loadFunc = loadstring or load
    if loadFunc then
        math.mod = loadFunc("return function(a, b) return a % b end")()
    end
end

-- Shim for Lua 5.0 where the bit library may be missing.
-- Questie uses band/bor/bxor/lshift/rshift in core runtime code, so we provide
-- a pure-Lua fallback when the host does not expose one.
if not bit or not bit.band or not bit.bor or not bit.bxor or not bit.lshift or not bit.rshift then
    local bitlib = bit or {}
    local U32 = 4294967296
    local U32_MAX = 4294967295
    local floor = math.floor
    local mod = math.mod or function(a, b)
        return a - floor(a / b) * b
    end

    local function normalizeU32(n)
        n = tonumber(n) or 0
        n = floor(n)
        if n < 0 then
            n = U32 + mod(n, U32)
        elseif n >= U32 then
            n = mod(n, U32)
        end
        return n
    end

    local function bitAt(n, mask)
        return mod(floor(n / mask), 2)
    end

    local function band32(a, b)
        a = normalizeU32(a)
        b = normalizeU32(b)
        local result = 0
        local mask = 1
        for _ = 1, 32 do
            if bitAt(a, mask) == 1 and bitAt(b, mask) == 1 then
                result = result + mask
            end
            mask = mask * 2
        end
        return normalizeU32(result)
    end

    local function bor32(a, b)
        a = normalizeU32(a)
        b = normalizeU32(b)
        local result = 0
        local mask = 1
        for _ = 1, 32 do
            if bitAt(a, mask) == 1 or bitAt(b, mask) == 1 then
                result = result + mask
            end
            mask = mask * 2
        end
        return normalizeU32(result)
    end

    local function bxor32(a, b)
        a = normalizeU32(a)
        b = normalizeU32(b)
        local result = 0
        local mask = 1
        for _ = 1, 32 do
            if bitAt(a, mask) ~= bitAt(b, mask) then
                result = result + mask
            end
            mask = mask * 2
        end
        return normalizeU32(result)
    end

    local function lshift32(a, disp)
        a = normalizeU32(a)
        disp = tonumber(disp) or 0
        if disp <= 0 then
            return normalizeU32(math.floor(a / (2 ^ (-disp))))
        elseif disp >= 32 then
            return 0
        end
        return normalizeU32(a * (2 ^ disp))
    end

    local function rshift32(a, disp)
        a = normalizeU32(a)
        disp = tonumber(disp) or 0
        if disp <= 0 then
            return normalizeU32(a * (2 ^ (-disp)))
        elseif disp >= 32 then
            return 0
        end
        return normalizeU32(floor(a / (2 ^ disp)))
    end

    local function bnot32(a)
        return normalizeU32(U32_MAX - normalizeU32(a))
    end

    bitlib.band = bitlib.band or band32
    bitlib.bor = bitlib.bor or bor32
    bitlib.bxor = bitlib.bxor or bxor32
    bitlib.lshift = bitlib.lshift or lshift32
    bitlib.rshift = bitlib.rshift or rshift32
    bitlib.bnot = bitlib.bnot or bnot32
    bit = bitlib
    _G.bit = bitlib
end

-- Shim for Lua 5.0 where string.match is missing.
-- Supports up to 5 captures (sufficient for all Questie uses).
if not string.match then
    string.match = function(str, pattern, init)
        if not str then return nil end
        local start_idx, end_idx, capture1, capture2, capture3, capture4, capture5 = string.find(str, pattern, init)
        if start_idx then
            if capture1 then
                return capture1, capture2, capture3, capture4, capture5
            else
                return string.sub(str, start_idx, end_idx)
            end
        end
        return nil
    end
end

-- Shim for Lua 5.0 where string.gmatch is called string.gfind.
if not string.gmatch then
    string.gmatch = string.gfind
end

-- Shim for Lua 5.0 / older clients where string.trim is not available.
-- Supports trimming either whitespace or a custom set of leading/trailing chars.
if not string.trim then
    local defaultTrimChars = {
        [" "] = true,
        ["\t"] = true,
        ["\r"] = true,
        ["\n"] = true,
    }

    local function buildTrimSet(chars)
        local set = {}
        if not chars or chars == "" then
            for ch in pairs(defaultTrimChars) do
                set[ch] = true
            end
            return set
        end
        for i = 1, string.len(chars) do
            set[string.sub(chars, i, i)] = true
        end
        return set
    end

    string.trim = function(text, chars)
        if text == nil then return nil end
        text = tostring(text)
        local trimSet = buildTrimSet(chars)
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

-- Shim for Lua 5.0 where select() was not yet implemented.
-- Fix #7: The original used a `while n > 0` loop that never decremented n,
-- making the loop body run exactly once before returning.  Use a plain
-- sequential block instead so the intent is obvious.
if not select then
    select = function(index, ...)
        if arg then -- Lua 5.0 Native Variadic Table
            if index == "#" then
                return arg.n
            end
            index = tonumber(index) or 1
            return unpack(arg, index, arg.n)
        end
    end
end

-- Shim for Lua 5.0 where strsplit is missing.
if not strsplit then
    strsplit = function(separator, text, max)
        if text == nil then
            return nil
        end
        if separator == "" then
            return text
        end

        local results = {}
        local resultCount = 0
        local startPos = 1
        local maxSplits = tonumber(max)

        while true do
            if maxSplits and resultCount >= (maxSplits - 1) then
                resultCount = resultCount + 1
                results[resultCount] = string.sub(text, startPos)
                break
            end

            local sepStart, sepEnd = string.find(text, separator, startPos, true)
            if not sepStart then
                resultCount = resultCount + 1
                results[resultCount] = string.sub(text, startPos)
                break
            end

            resultCount = resultCount + 1
            results[resultCount] = string.sub(text, startPos, sepStart - 1)
            startPos = sepEnd + 1
        end

        return unpack(results, 1, resultCount)
    end
end

-- The only public class except for Questie
---@class QuestieLoader
QuestieLoader = QuestieLoader or {}

local addonName = ...
QuestieLoader.addonName = addonName or "Questie"

local modules = (QuestieLoader._modules) or {}

QuestieLoader._modules = modules -- store reference so modules can be iterated for profiling

---@generic T
---@param name `T` @Module name
---@return T|{ private: table } @Module reference
function QuestieLoader:CreateModule(name)
    -- Fix #12: Error on double-registration so aliasing bugs are caught early.
    if modules[name] and modules[name]._defined then
        -- Print a debug message rather than hard-error so it doesn't break live servers
        -- even if another file accidentally calls CreateModule twice.
        return modules[name]
    end
    if not modules[name] then
        modules[name] = { private = {} }
    end
    modules[name]._defined = true
    return modules[name]
end

---@generic T
---@param name `T` @Module name
---@return T|{ private: table } @Module reference
function QuestieLoader:ImportModule(name)
    if not modules[name] then
        modules[name] = { private = {} }
    end
    return modules[name]
end

function QuestieLoader:PopulateGlobals() -- called when debugging is enabled
    for name, module in pairs(modules) do
        if _G[name] == nil then
            _G[name] = module
        elseif _G[name] ~= module then
            -- Use a safe print fallback if Questie is not yet initialized or does not have Debug
            local msg = "[QuestieLoader] WARNING: Global collision detected for '" .. tostring(name) .. "'. Skipping population to avoid taining the global namespace."
            if Questie and Questie.Debug then
                Questie:Debug(1, msg)
            else
                print("|cFFFF0000" .. msg .. "|r")
            end
        end
    end
end

-- Initialize Questie object early to avoid nil errors during loading
local Questie = QuestieLoader:CreateModule("Questie")
_G.Questie = Questie

-- Initial stubs for Debug and Colorize so early calls don't crash
Questie.DEBUG_CRITICAL = 1
Questie.DEBUG_ELEVATED = 2
Questie.DEBUG_INFO = 4
Questie.DEBUG_DEVELOP = 8
Questie.DEBUG_SPAM = 16
Questie.DEBUG_LEARNER = 32
Questie.DEBUG_COMMS = 64

function Questie:Debug(level, ...)
    -- Initial stub: just print to chat if it's a critical message
    -- This will be replaced by the real Questie:Debug in Questie.lua
    if level == Questie.DEBUG_CRITICAL then
        print("|cFFFFFF00[Questie-X Pre-Init Debug]|r", ...)
    end
end

function Questie:Colorize(str, color)
    -- Initial stub: just return the string without color or with basic color
    return str
end
