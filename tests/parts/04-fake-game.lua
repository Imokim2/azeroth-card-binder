-- Load the actual UI and event handlers against small game API stand-ins.
local methods = {
    SetSize = function(self, width, height) self.width, self.height = width, height end,
    GetWidth = function(self) return self.width end,
    GetHeight = function(self) return self.height end,
    SetPoint = function(self, ...) self.point = { ... } end,
    SetFrameStrata = ignore, SetClampedToScreen = ignore,
    SetMovable = ignore, EnableMouse = ignore,
    SetBackdrop = function(self) equal(self.template, "BackdropTemplate") end,
    SetBackdropColor = ignore,
    SetBackdropBorderColor = ignore, SetHeight = ignore, RegisterForDrag = ignore,
    SetHighlightTexture = ignore, SetNormalTexture = ignore, RegisterForClicks = ignore,
    SetFontString = ignore, SetScale = function(self, scale) self.scale = scale end,
    SetTextInsets = ignore, EnableMouseWheel = ignore,
    SetJustifyH = ignore, SetTextColor = ignore, SetAllPoints = ignore, SetTexCoord = ignore,
    SetWidth = ignore, SetAutoFocus = ignore, SetMaxLetters = ignore, SetFocus = ignore,
    SetTexture = function(self, texture)
        if self.rejectTexture then return false end
        self.texture = texture
        return true
    end,
    SetDesaturated = function(self, desaturated) self.desaturated = desaturated end,
    SetAlpha = function(self, alpha) self.alpha = alpha end, SetMultiLine = ignore,
    SetFontObject = ignore, SetScrollChild = ignore, SetVerticalScroll = ignore, HighlightText = ignore,
    ClearFocus = ignore, SetClipsChildren = ignore,
    SetColorTexture = function(self) self.colorTexture = true end, SetFont = ignore, SetBlendMode = ignore,
    SetVertexColor = function(self, r, g, b) self.vertex = { r, g, b } end,
    SetFrameLevel = function(self, level) self.level = level end,
    GetFrameLevel = function(self) return self.level or 1 end, SetMaxLines = ignore,
    SetChecked = function(self, value) self.checked = value end, GetChecked = function(self) return self.checked end,
    SetWordWrap = ignore, SetStatusBarTexture = ignore, SetMinMaxValues = function(self, low, high) self.low, self.high = low, high end,
    SetValue = function(self, value) self.value = value end, SetStatusBarColor = ignore, StartMoving = ignore, StopMovingOrSizing = ignore, GetCenter = function() return 600, 20 end, GetTop = function(self) return self.top end, GetBottom = function() return 20 end, SetRotation = ignore, SetShadowOffset = ignore, SetSpacing = ignore, SetShadowColor = ignore, GetStringWidth = function() return 6 end, SetJustifyV = ignore, ClearAllPoints = ignore,
    SetKeepModelOnHide = function(self, keep) self.keepModel = keep end,
    ClearModel = function(self) self.creature, self.fileID, self.frozen = nil, nil, nil end,
    SetCreature = function(self, creature) self.creature = creature end,
    SetModel = function(self, file) self.fileID = file end,
    GetModelFileID = function(self) return self.fileID end,
    SetDesaturation = function(self, strength) self.desaturation = strength end,
    SetModelAlpha = function(self, alpha) self.modelAlpha = alpha end,
    SetPortraitZoom = function(self, zoom) self.portraitZoom = zoom end,
    SetCamDistanceScale = ignore, SetFacing = function(self, facing) self.facing = facing end, SetPosition = ignore, SetPaused = ignore,
    HasAnimation = function(self, animation) return self.supportedAnimation == animation end,
    FreezeAnimation = function(self, animation, variation, frame) self.frozen = { animation, variation, frame } end,
    Show = function(self) self.shown = true end,
    Hide = function(self) self.shown = false end,
    SetShown = function(self, shown) self.shown = shown end,
    IsShown = function(self) return self.shown end,
    IsMouseOver = function(self) return self.mouseOver ~= false end,
    GetEffectiveScale = function(self) return self.scale or 1 end,
    SetText = function(self, text) self.text = text end,
    GetText = function(self) return self.text or "" end,
    SetEnabled = function(self, enabled) equal(type(enabled), "boolean"); self.enabled = enabled end,
    SetScript = function(self, name, handler) self[name] = handler end,
    RegisterEvent = function(self, event)
        assert(not event:match("^COMBAT_LOG"))
        self[event] = true
    end,
    UnregisterEvent = function(self, event) self[event] = nil end,
}
local eventFrame, widgets = nil, {}
function CreateFrame(kind, name, parent, template)
    local frame = setmetatable({ parent = parent, template = template }, { __index = methods })
    if not eventFrame then eventFrame = frame end
    if name then _G[name] = frame end
    widgets[#widgets + 1] = frame
    return frame
end
methods.CreateFontString = function(self) return CreateFrame("FontString", nil, self) end
methods.CreateTexture = function(self) return CreateFrame("Texture", nil, self) end
methods.RegisterUnitEvent = methods.RegisterEvent
UISpecialFrames, SlashCmdList = {}, {}
UIParent = setmetatable({ width = 1200, height = 900 }, { __index = methods })
Minimap = setmetatable({
    width = 140, height = 140,
    GetCenter = function() return 100, 100 end,
    GetEffectiveScale = function() return 0.8 end,
}, { __index = methods })
local cursorX, shiftDown, leftDown = 80, false, false
function GetCursorPosition() return cursorX, 140 end
function IsShiftKeyDown() return shiftDown end
function IsMouseButtonDown(button) return button == "LeftButton" and leftDown end

local chatFilters, chatCallbacks = {}, {}
local draft, activeChat
ChatFrameUtil = {
    AddMessageEventFilter = function(event, callback) chatFilters[event] = callback end,
    OpenChat = function(message) draft = message end,
    GetActiveWindow = function() return activeChat end,
}
EventRegistry = {
    RegisterCallback = function(_, event, callback, owner)
        chatCallbacks[event] = function(...) callback(owner, ...) end
    end,
}

local secret = setmetatable({}, { __tostring = function() error("secret value used") end })
function issecretvalue(value) return value == secret end
local clock, slots, rolls, draw, instance = 10, {}, 0, 1, 0
local shinyDraw = 2 -- 1 would make the next find shiny
local target, dead, rank, playerDead, combat, locked
local timers = {}
C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
C_Spell = { GetSpellName = function(id) return (id == 2575 or id == 2576) and "Mining" or nil end }
C_ChatInfo = {
    RegisterAddonMessagePrefix = ignore, IsAddonMessagePrefixRegistered = function() return true end,
    AreOutgoingAddonChatMessagesRestricted = function() return false end,
    InChatMessagingLockdown = function() return locked or false end,
}
function GetBuildInfo() return "1.60.1", "70862", "Nov 4 2026", 16001 end
function GetTime() return clock end
function GetNumLootItems() return #slots end
function GetLootSourceInfo(index)
    if slots[index] == false then error("unavailable") end
    return unpack(slots[index])
end
function GetInstanceInfo() return "Map", "party", 1, "", 5, false, false, instance end
function UnitGUID(unit) if unit == "target" then return target end end
function UnitIsDeadOrGhost(unit)
    if unit == "player" then return playerDead or false end
    return dead
end
function UnitClassification() return rank end
function UnitFullName() return "Alice", "Realm Name" end
function GetNormalizedRealmName() return "RealmName" end
function IsInInstance() return instance ~= 0 end
function InCombatLockdown() return combat or false end
function time() return 111 end

local realPrint, realRandom = print, math.random
print = function(message)
    if not message:find("|cffe8bc6b", 1, true) then realPrint(message) end
end
math.random = function(min, max)
    if max == ACB.shinyOdds then return shinyDraw end
    if max == 10000 then rolls = rolls + 1 return draw end
    return realRandom(min, max)
end
AzerothCardBinderDB = { counts = { invalid = -1 }, diagnostics = true }
hintCallbacks = {}
TooltipDataProcessor = { AddTooltipPostCall = function(_, callback) hintCallbacks[#hintCallbacks + 1] = callback end }
Enum = { TooltipDataType = { Unit = 1, Object = 2 } }
loadAddon("CardModels.lua")
loadAddon("CardArt.lua")
loadAddon("Cards.lua")
loadAddon("Toast.lua")
loadAddon("Hints.lua")
loadAddon("ZoneBar.lua")
loadAddon("Settings.lua")
loadAddon("Social.lua")
loadAddon("FolioUi.lua")
loadAddon("FolioIndex.lua")
loadAddon("Folio.lua")
loadAddon("UiKit.lua")
loadAddon("SettingsView.lua")
loadAddon("Binder.lua")
loadAddon("Minimap.lua")
loadAddon("SavedData.lua")
loadAddon("Slash.lua")
loadAddon("Forever.lua")

local function emit(event, ...)
    assert(eventFrame[event], "event not registered: " .. event)
    eventFrame:OnEvent(event, ...)
end

local function openLoot(...)
    slots = { ... }
    emit("LOOT_READY", false)
    emit("LOOT_OPENED", false, false)
end

local function cast(event, token, spell, unit)
    emit("UNIT_SPELLCAST_" .. event, unit or "player", token, spell)
end
