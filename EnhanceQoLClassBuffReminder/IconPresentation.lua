local addon = _G.EnhanceQoL
local Reminder = addon.ClassBuffReminder
local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL")
local Glow = addon.Glow
local GLOW_KEY = "CLASS_BUFF_REMINDER"
local M = {
	separate = "classBuffReminderExpiringGlow",
	style = "classBuffReminderExpiringGlowStyle",
	color = "classBuffReminderExpiringGlowColor",
	time = "classBuffReminderShowTimeLeft",
	count = "classBuffReminderShowItemCount",
	keybind = "classBuffReminderShowKeybinds",
	defaultColor = { r = 1, g = 0.5, b = 0, a = 1 },
}
local KEYBIND_TEXT = "classBuffReminderKeybindText"
local KEYBIND_ANCHORS = {
	{ value = "TOPLEFT", label = L["Top Left"], justify = "LEFT", x = 2, y = -2 },
	{ value = "TOP", label = L["Top"], justify = "CENTER", x = 0, y = -2 },
	{ value = "TOPRIGHT", label = L["Top Right"], justify = "RIGHT", x = -2, y = -2 },
	{ value = "LEFT", label = L["Left"], justify = "LEFT", x = 2, y = 0 },
	{ value = "CENTER", label = L["Center"], justify = "CENTER", x = 0, y = 0 },
	{ value = "RIGHT", label = L["Right"], justify = "RIGHT", x = -2, y = 0 },
	{ value = "BOTTOMLEFT", label = L["Bottom Left"], justify = "LEFT", x = 2, y = 2 },
	{ value = "BOTTOM", label = L["Bottom"], justify = "CENTER", x = 0, y = 2 },
	{ value = "BOTTOMRIGHT", label = L["Bottom Right"], justify = "RIGHT", x = -2, y = 2 },
}
local DEFAULT_KEYBIND_ANCHOR = "BOTTOMLEFT"
local keybindAnchorByPoint = {}
for _, anchor in ipairs(KEYBIND_ANCHORS) do keybindAnchorByPoint[anchor.value] = anchor end
local KEYBIND_EVENTS = {
	ACTIONBAR_PAGE_CHANGED = true, ACTIONBAR_SLOT_CHANGED = true, UPDATE_BINDINGS = true,
	UPDATE_BONUS_ACTIONBAR = true, UPDATE_OVERRIDE_ACTIONBAR = true, UPDATE_VEHICLE_ACTIONBAR = true,
	UPDATE_POSSESS_BAR = true, UPDATE_MACROS = true, GAME_PAD_ACTIVE_CHANGED = true,
}
local KEYBIND_INVALIDATION_EVENTS = {
	PLAYER_ENTERING_WORLD = true, SPELLS_CHANGED = true, UPDATE_SHAPESHIFT_FORM = true,
	PLAYER_SPECIALIZATION_CHANGED = true, ACTIVE_TALENT_GROUP_CHANGED = true,
}
local ACTION_BARS = {
	{ "ActionButton", "ACTIONBUTTON", "MainActionBar" },
	{ "MultiBarBottomLeftButton", "MULTIACTIONBAR1BUTTON", "MultiBarBottomLeft" },
	{ "MultiBarBottomRightButton", "MULTIACTIONBAR2BUTTON", "MultiBarBottomRight" },
	{ "MultiBarRightButton", "MULTIACTIONBAR3BUTTON", "MultiBarRight" },
	{ "MultiBarLeftButton", "MULTIACTIONBAR4BUTTON", "MultiBarLeft" },
	{ "MultiBar5Button", "MULTIACTIONBAR5BUTTON", "MultiBar5" },
	{ "MultiBar6Button", "MULTIACTIONBAR6BUTTON", "MultiBar6" },
	{ "MultiBar7Button", "MULTIACTIONBAR7BUTTON", "MultiBar7" },
}

function Reminder:GetIconRowDimensions(frame, iconSize, iconGap, scale)
	local size = math.max(14, iconSize * scale)
	local gap = math.max(0, iconGap * scale)
	local pixelUtil = addon.PixelUtil
	if not self:GetGrowthFromCenter() or not pixelUtil then
		return math.floor(size + 0.5), math.floor(gap + 0.5)
	end

	local onePixel = pixelUtil.OnePixel(frame)
	local gapPixels = pixelUtil.Round(gap / onePixel)
	-- An even step keeps icon edges at the same fractional pixel position
	-- when a centered row switches between an odd and even icon count.
	local stepPairs = math.max(math.floor(gapPixels / 2) + 1, pixelUtil.Round((size + gap) / (2 * onePixel)))
	return (stepPairs * 2 - gapPixels) * onePixel, gapPixels * onePixel
end

local function now() return GetTime() end
local function packSlots(...) return { ... }, select("#", ...) end
local function plainNumber(value)
	if issecretvalue and issecretvalue(value) then return nil end
	return type(value) == "number" and value or nil
end
local function plainString(value)
	if issecretvalue and issecretvalue(value) then return nil end
	return type(value) == "string" and value or nil
end
local function defaultEnabled(key) return key == M.time or key == M.count end
local function enabled(key)
	local value = addon.db and addon.db[key]
	if value == nil then return defaultEnabled(key) end
	return value == true
end

local function effectiveSpellId(spellId)
	if not spellId then return nil end
	return (C_Spell and C_Spell.GetOverrideSpell and plainNumber(C_Spell.GetOverrideSpell(spellId))) or spellId
end

local function getMacroCastSpell(macroId)
	if not (GetMacroBody and C_Spell and C_Spell.GetSpellInfo) then return nil end
	local body = plainString(GetMacroBody(macroId))
	if not body then return nil end
	local castSpell
	for rawLine in body:gmatch("[^\r\n]+") do
		local line = rawLine:match("^%s*(.-)%s*$")
		if line ~= "" and line:sub(1, 1) ~= "#" then
			if castSpell then return nil end
			local command, spell = line:match("^(%S+)%s+([^%[%];]+)$")
			command = command and command:lower()
			if not command or (command ~= "/cast" and command ~= _G.SLASH_CAST1 and command ~= _G.SLASH_CAST2) then return nil end
			local info = C_Spell.GetSpellInfo(spell)
			if issecretvalue and issecretvalue(info) then return nil end
			castSpell = info and plainNumber(info.spellID)
			if not castSpell then return nil end
		end
	end
	return castSpell
end

local function getButtonKey(command)
	local first, second = GetBindingKey(command)
	first, second = plainString(first), plainString(second)
	if not GetBindingAction then return first or second end
	if first and plainString(GetBindingAction(first, true)) == command then return first end
	if second and plainString(GetBindingAction(second, true)) == command then return second end
end

local function buildSpellKeybindLookup()
	local spells, macros = {}, {}
	if not (GetActionInfo and GetBindingKey and GetBindingText) then return spells end
	for _, bar in ipairs(ACTION_BARS) do
		for index = 1, NUM_ACTIONBAR_BUTTONS or 12 do
			local name = bar[1] .. index
			local button = _G[name]
			if bar[1] == "ActionButton" and _G.GetActionButtonForID then
				button = _G.GetActionButtonForID(index)
				if button then name = button:GetName() or name end
			end
			local visible = button and button:IsVisible()
			if issecretvalue and issecretvalue(visible) then visible = nil end
			local slot = visible and (plainNumber(button.action) or plainNumber(button:GetAttribute("action")))
			if slot and slot > 0 then
				local kind, id = GetActionInfo(slot)
				kind, id = plainString(kind), plainNumber(id)
				if id and (kind == "spell" or kind == "macro") then
					local key = getButtonKey(plainString(button.bindingAction) or plainString(button.commandName) or bar[2] .. index)
						or getButtonKey("CLICK " .. name .. ":LeftButton")
					if key then
						local spellId = effectiveSpellId(kind == "spell" and id or getMacroCastSpell(id))
						local lookup = kind == "spell" and spells or macros
						if spellId and not lookup[spellId] then
							local binding = plainString(GetBindingText(key, 1))
							if binding and binding ~= "" then
								local labels = addon.ActionBarLabels
								if labels and labels.ShortenHotkeyText and not binding:find("|", 1, true) then binding = labels.ShortenHotkeyText(binding) end
								lookup[spellId] = binding
							end
						end
					end
				end
			end
		end
	end
	for id, binding in pairs(macros) do
		if not spells[id] then spells[id] = binding end
	end
	return spells
end

local function onActionBarVisibilityChanged()
	if Reminder.eventsRegistered and Reminder.reminderKeybindEventsActive then
		Reminder.reminderSpellKeybinds = nil
		Reminder:RequestUpdate(false, 0, true)
	end
end

local function hookActionBarVisibility()
	Reminder.reminderKeybindBarHooks = Reminder.reminderKeybindBarHooks or {}
	local function hook(frame)
		if not (frame and frame.HookScript) or Reminder.reminderKeybindBarHooks[frame] then return end
		frame:HookScript("OnShow", onActionBarVisibilityChanged)
		frame:HookScript("OnHide", onActionBarVisibilityChanged)
		Reminder.reminderKeybindBarHooks[frame] = true
	end
	hook(_G.MainMenuBar)
	for _, bar in ipairs(ACTION_BARS) do hook(_G[bar[3]]) end
end

function Reminder:RefreshReminderKeybindEvents()
	self.reminderSpellKeybinds = nil
	if not self.eventsRegistered then return end
	local active = enabled(M.keybind)
	if (self.reminderKeybindEventsActive == true) == active then return end
	self.reminderKeybindEventsActive = active
	if active then hookActionBarVisibility() end
	local eventUtils = _G.C_EventUtils
	for event in pairs(KEYBIND_EVENTS) do
		if not (eventUtils and eventUtils.IsEventValid) or eventUtils.IsEventValid(event) then
			if active then self.eventFrame:RegisterEvent(event) else self.eventFrame:UnregisterEvent(event) end
		end
	end
end

function Reminder:HandleReminderKeybindEvent(event)
	if not self.reminderKeybindEventsActive then return false end
	if KEYBIND_EVENTS[event] then
		self.reminderSpellKeybinds = nil
		-- Action button paging and binding handlers must run before reading their slots.
		self:RequestUpdate(false, 0, true)
		return true
	end
	if KEYBIND_INVALIDATION_EVENTS[event] then self.reminderSpellKeybinds = nil end
	if event == "PLAYER_ENTERING_WORLD" then hookActionBarVisibility() end
	return false
end

function Reminder:GetReminderEntryKeybindSpell(entry)
	if not entry or entry.itemId or entry.actionCallback or entry.actionPetSlot or entry.actionInventorySlot then return nil end
	return plainNumber(entry.actionSpellId)
end
local function latest(a, b)
	b = plainNumber(b)
	if b and (not a or b > a) then return b end
	return a
end
local function warningExpiration(expiration, threshold)
	expiration = plainNumber(expiration)
	if not expiration or expiration == math.huge then return nil end
	local remaining = expiration - now()
	if remaining > 0 and remaining <= threshold then return expiration end
end

function Reminder:GetWeaponWarningExpiration(milliseconds)
	milliseconds = plainNumber(milliseconds)
	if milliseconds and milliseconds > 0 then return now() + milliseconds / 1000 end
end

function Reminder:MakeSharedBuffWarningEntry(spellIds, spellId, label, missing, total)
	local entry = self:MakeSpellInteractionEntry(spellIds, spellId, label, missing, total)
	entry.warningCache = self:GetGroupBuffStateCache(spellIds, false)
	return entry
end

-- A unit may have several equivalent auras. The longest valid one provides coverage.
local function stateExpiration(state)
	local expiration
	for _, value in pairs(state and state.expirationByInstance or {}) do expiration = latest(expiration, value) end
	return expiration
end

local function groupExpiration(states, statuses, threshold)
	local earliest
	for unit, state in pairs(states or {}) do
		if not statuses or statuses[unit] == 1 then
			local expiration = warningExpiration(stateExpiration(state), threshold)
			-- An actually missing or unreadable buff takes priority over expiring buffs.
			if not expiration then return nil end
			if not earliest or expiration < earliest then earliest = expiration end
		end
	end
	-- Status entries without a corresponding aura state must not be called expiring.
	for unit, status in pairs(statuses or {}) do
		if status == 1 and not states[unit] then return nil end
	end
	return earliest
end

local function snapshotExpiration(snapshot, query)
	if not snapshot or snapshot.restricted or not snapshot.supported then return nil end
	local expiration
	for _, ids in ipairs({ query.spellIds or {}, query.extraSpellIds or {} }) do
		for _, id in ipairs(ids) do
			if snapshot.spellIds[id] then expiration = latest(expiration, snapshot.spellIdExpirations[id] or math.huge) end
		end
	end
	for _, name in ipairs(query.names or {}) do
		if snapshot.names[name] then expiration = latest(expiration, snapshot.nameExpirations[name] or math.huge) end
	end
	if query.icon and snapshot.icons[query.icon] then expiration = latest(expiration, snapshot.iconExpirations[query.icon] or math.huge) end
	return expiration
end

function Reminder:GetSnapshotWarningExpiration(snapshot, query)
	return warningExpiration(snapshotExpiration(snapshot, query), self:GetExpirationWarningSeconds(query.category))
end

function Reminder:WithWarningAuraUnits(entry, units, spellIds, names)
	entry.warningAuraQuery = { units = {}, spellIds = spellIds, names = names }
	for _, unit in ipairs(units) do entry.warningAuraQuery.units[#entry.warningAuraQuery.units + 1] = unit end
	return entry
end

function Reminder:GetAuraQueryWarningExpiration(query)
	if not query.units then return self:GetSnapshotWarningExpiration(self:GetPlayerAuraPresenceSnapshot(), query) end
	if not (C_UnitAuras and C_UnitAuras.GetAuraSlots and C_UnitAuras.GetAuraDataBySlot) then return nil end
	local spellSet, nameSet = {}, {}
	for _, id in ipairs(query.spellIds or {}) do spellSet[id] = true end
	for _, name in ipairs(query.names or {}) do nameSet[name] = true end
	local expiration
	for _, unit in ipairs(query.units) do
		local continuation
		for _ = 1, 100 do
			local slots, slotCount = packSlots(C_UnitAuras.GetAuraSlots(unit, "HELPFUL", nil, continuation))
			continuation = slots[1]
			if issecretvalue and issecretvalue(continuation) then return nil end
			for i = 2, slotCount do
				local slot = plainNumber(slots[i])
				local aura = slot and C_UnitAuras.GetAuraDataBySlot(unit, slot)
				if aura and not (issecretvalue and issecretvalue(aura)) then
					local id = plainNumber(aura.spellId)
					local name = aura.name
					if issecretvalue and issecretvalue(name) then name = nil end
					if (id and spellSet[id]) or (name and nameSet[name]) then expiration = latest(expiration, self.GetAuraExpirationTime(aura)) end
				end
			end
			if continuation == nil then break end
		end
	end
	return warningExpiration(expiration, self:GetExpirationWarningSeconds(query.category))
end

function Reminder:GetEntryWarningExpiration(entry)
	if type(entry) ~= "table" or not self:CanReadAuraData() then return nil end
	local category = entry.warningCategory or (entry.selectionPoisonCategory and "POISONS") or "CLASS_BUFFS"
	local threshold = self:GetExpirationWarningSeconds(category)
	if entry.warningStates then return groupExpiration(entry.warningStates, nil, threshold) end
	if entry.warningCache then return groupExpiration(entry.warningCache.unitStates, entry.warningCache.unitStatus, threshold) end
	if entry.warningProvider then
		local state = self.groupMissingState
		if state and state.providerRef == entry.warningProvider then return groupExpiration(self.unitAuraStates or {}, state.unitStatus, threshold) end
		return nil
	end
	if entry.actionInventorySlot then
		if not entry.warningCategory then threshold = self:GetExpirationWarningSeconds("WEAPON_BUFFS") end
		return warningExpiration(entry.warningExpiration, threshold)
	end
	if entry.warningAuraQuery then return self:GetAuraQueryWarningExpiration(entry.warningAuraQuery) end
	if entry.countTotal or entry.targetCandidates or entry.actionCallback or entry.actionPetSlot or entry.sourceKind == "HEALTHSTONE" then return nil end
	if not entry.spellId then return nil end
	local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(entry.spellId)
	local name = info and info.name
	if issecretvalue and issecretvalue(name) then name = nil end
	return self:GetSnapshotWarningExpiration(self:GetPlayerAuraPresenceSnapshot(), {
		spellIds = entry.warningSpellIds or { entry.spellId }, names = name and { name } or nil, category = category,
	})
end

function Reminder:CancelIconPresentationTimer()
	if self.iconPresentationTimer then self.iconPresentationTimer:Cancel() end
	self.iconPresentationTimer = nil
end

local function formatTime(seconds)
	seconds = math.ceil(seconds)
	if seconds >= 3600 then return string.format("%d:%02d:%02d", math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60) end
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function textStyleValue(prefix, field, default)
	local value = addon.db and addon.db[prefix .. field]
	if value == nil then return default end
	return value
end

local function textStyleNumber(prefix, field, default, minimum, maximum)
	local value = tonumber(textStyleValue(prefix, field, default)) or default
	return math.max(minimum, math.min(maximum, value))
end

local function textFontOptions()
	local options = {
		{ value = "DEFAULT", label = _G.DEFAULT },
		{ value = addon.functions.GetGlobalFontConfigKey(), label = addon.functions.GetGlobalFontConfigLabel() },
	}
	local media = addon.functions and addon.functions.GetLSMMediaOptions and addon.functions.GetLSMMediaOptions("font") or {}
	for _, option in ipairs(media) do options[#options + 1] = option end
	return options
end

local function textOutline(prefix)
	return addon.functions.GetFontFlagsForStyle(textStyleValue(prefix, "Outline", addon.functions.GetGlobalFontStyleConfigKey()), "OUTLINE")
end

local function ensureOverlayText(target, key, options)
	local overlay = target._eqolReminderTextOverlay
	if not overlay then
		overlay = CreateFrame("Frame", nil, target, options and options.layoutRestricted and "DisableUntrustedLayoutScriptsTemplate" or nil)
		overlay:SetAllPoints(target)
		overlay:EnableMouse(false)
		target._eqolReminderTextOverlay = overlay
	end
	-- Keep text above the glow and both backdrop borders.
	local level = (target:GetFrameLevel() or 0) + 20
	local iconBorder = target.border
	if iconBorder then level = math.max(level, iconBorder:GetFrameLevel() + 1) end
	local border = Reminder.frame and Reminder.frame.border
	if border then level = math.max(level, border:GetFrameLevel() + 1) end
	overlay:SetFrameStrata(target:GetFrameStrata())
	overlay:SetFrameLevel(level)
	local text = target[key]
	if not text then
		text = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		text:SetShadowOffset(1, -1)
		text:SetShadowColor(0, 0, 0, 1)
		target[key] = text
	end
	return text
end

local function ensureText(target, key, point, options)
	local text = ensureOverlayText(target, key, options)
	local isKeybind = key == "_eqolReminderKeybindText"
	local prefix = isKeybind and KEYBIND_TEXT or (key == "_eqolReminderTimeText" and "classBuffReminderTimeText" or "classBuffReminderItemCountText")
	local width = (options and options.width) or target:GetWidth() or 40
	local size = textStyleNumber(prefix, "Size", 0, 0, 64)
	if size == 0 then
		size = isKeybind and math.max(7, math.min(14, width * 0.22)) or math.max(8, math.min(18, width * 0.28))
	end
	local fallback = (addon.variables and addon.variables.defaultFont) or STANDARD_TEXT_FONT
	local fontKey = textStyleValue(prefix, "Font", addon.functions.GetGlobalFontConfigKey())
	local font = fallback
	if fontKey ~= "DEFAULT" then font = addon.functions.ResolveFontFace(fontKey, addon.functions.GetGlobalDefaultFontFace()) end
	local outline = textOutline(prefix)
	if text._eqolFont ~= font or text._eqolSize ~= size or text._eqolOutline ~= outline then
		if text:SetFont(font, size, outline) == false then text:SetFont(fallback, size, outline) end
		text._eqolFont, text._eqolSize, text._eqolOutline = font, size, outline
	end
	addon.functions.ApplyFontStyleShadow(text, textStyleValue(prefix, "Outline", addon.functions.GetGlobalFontStyleConfigKey()), "OUTLINE")
	text:ClearAllPoints()
	local color = textStyleValue(prefix, "Color", {})
	local offsetX = textStyleNumber(prefix, "OffsetX", 0, -100, 100)
	local offsetY = textStyleNumber(prefix, "OffsetY", 0, -100, 100)
	if isKeybind then
		local anchor = keybindAnchorByPoint[textStyleValue(prefix, "Anchor", DEFAULT_KEYBIND_ANCHOR)] or keybindAnchorByPoint[DEFAULT_KEYBIND_ANCHOR]
		text:SetPoint(anchor.value, target, anchor.value, anchor.x + offsetX, anchor.y + offsetY)
		text:SetJustifyH(anchor.justify)
		text:SetWidth(math.max(1, width - 4))
		text:SetWordWrap(false)
		if textStyleValue(prefix, "UseClassColor", false) then
			local class = Reminder:GetClassToken()
			color = (class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]) or color
		end
	else
		text:SetPoint(point, target, point,
			(point == "BOTTOMRIGHT" and -2 or 0) + offsetX, (point == "TOP" and -2 or 2) + offsetY)
	end
	text:SetTextColor(color.r or 1, color.g or 1, color.b or 1, color.a or 1)
	return text, offsetX, offsetY
end

function Reminder:UpdateReminderKeybindText(target, spellId, options)
	local value
	if enabled(M.keybind) then
		if self.editModeActive then
			value = "1"
		elseif spellId then
			self.reminderSpellKeybinds = self.reminderSpellKeybinds or buildSpellKeybindLookup()
			value = self.reminderSpellKeybinds[effectiveSpellId(spellId)]
		end
	end
	if value then
		local text, offsetX, offsetY = ensureText(target, "_eqolReminderKeybindText", nil, options)
		text:SetText(value)
		return text._eqolSize, math.max(math.abs(offsetX), math.abs(offsetY))
	elseif target._eqolReminderKeybindText then
		target._eqolReminderKeybindText:SetText("")
	end
end

function Reminder:UpdateReminderItemCountText(target, entry, options)
	if enabled(M.count) and entry and entry.itemId and C_Item and C_Item.GetItemCount then
		local count = plainNumber(C_Item.GetItemCount(entry.itemId, false, false))
		local value = count and tostring(count) or ""
		local text = ensureText(target, "_eqolReminderItemText", "BOTTOMRIGHT", options)
		text:SetText(value)
		return value, text._eqolSize
	elseif target._eqolReminderItemText then
		target._eqolReminderItemText:SetText("")
	end
	return "", 0
end

function Reminder:ApplyReminderFoodTint(icon, entry)
	if not icon then return end
	local missing = not self.editModeActive and entry and entry.noFood == true
	icon:SetVertexColor(1, missing and 0.2 or 1, missing and 0.2 or 1)
end

function Reminder:UpdateReminderIconPresentation(displaySpellId)
	self:CancelIconPresentationTimer()
	if not self.frame or not self.frame:IsShown() then return end
	local targets = self:GetGlowTargets() or {}
	local needsExpiration = enabled(M.time) or enabled(M.separate)
	local showKeybind = enabled(M.keybind)
	for _, target in ipairs(targets) do
		local entry = target._eqolReminderInteractionEntry
		local holder = target == self.frame.iconHolder
		self:ApplyReminderFoodTint(holder and self.frame.icon or target.icon, entry)
		local spellId = showKeybind and self:GetReminderEntryKeybindSpell(entry)
		-- The summary can show the provider's icon while its click action targets
		-- a different missing buff. Only label the spell represented by the icon.
		if holder and spellId and (not displaySpellId or effectiveSpellId(entry.spellId) ~= effectiveSpellId(displaySpellId)) then spellId = nil end
		self:UpdateReminderKeybindText(target, spellId)
		if self.editModeActive then
			target._eqolReminderProgressExpiration = nil
			target._eqolReminderWarningExpiration = needsExpiration and now() + 90 or nil
			if enabled(M.time) then ensureText(target, "_eqolReminderTimeText", "TOP"):SetText("1:30")
			elseif target._eqolReminderTimeText then target._eqolReminderTimeText:SetText("") end
			if enabled(M.count) then ensureText(target, "_eqolReminderItemText", "BOTTOMRIGHT"):SetText("20")
			elseif target._eqolReminderItemText then target._eqolReminderItemText:SetText("") end
		else
			target._eqolReminderWarningExpiration = needsExpiration and self:GetEntryWarningExpiration(entry) or nil
			target._eqolReminderProgressExpiration = entry and plainNumber(entry.progressExpiration) or nil
			if entry and entry.itemId and entry.icon and target == self.frame.iconHolder and (needsExpiration or enabled(M.count)) then
				self.frame.icon:SetTexture(entry.icon)
			end
			self:UpdateReminderItemCountText(target, entry)
		end
	end
	if not self.editModeActive then self:TickReminderIconPresentation() end
end

function Reminder:TickReminderIconPresentation()
	self.iconPresentationTimer = nil
	if not self.frame or not self.frame:IsShown() then return end
	local delay
	local expired = false
	for _, target in ipairs(self:GetGlowTargets() or {}) do
		local progress = target._eqolReminderProgressExpiration
		local expiration = progress or target._eqolReminderWarningExpiration
		local remaining = expiration and expiration - now()
		if remaining and remaining > 0 then
			if progress or enabled(M.time) then
				ensureText(target, "_eqolReminderTimeText", "TOP"):SetText(formatTime(remaining))
			elseif target._eqolReminderTimeText then
				target._eqolReminderTimeText:SetText("")
			end
			local nextDelay = (progress or enabled(M.time)) and math.min(1, remaining) or remaining
			if not delay or nextDelay < delay then delay = nextDelay end
		else
			if target._eqolReminderTimeText then target._eqolReminderTimeText:SetText("") end
			if expiration then
				target._eqolReminderWarningExpiration = nil
				target._eqolReminderProgressExpiration = nil
				expired = true
			end
		end
	end
	if expired then
		self:MarkAuraStatesDirty()
		self:InvalidateSelfProviderStatus()
		self:RequestUpdate(true)
		return
	end
	if delay and C_Timer and C_Timer.NewTimer then
		self.iconPresentationTimer = C_Timer.NewTimer(math.max(0.05, delay), function() Reminder:TickReminderIconPresentation() end)
	end
end

function Reminder:GetExpiringGlowColor()
	local color = addon.db and addon.db[M.color]
	if type(color) ~= "table" then color = M.defaultColor end
	return color.r or 1, color.g or 0.5, color.b or 0, color.a or 1
end

function Reminder:GetExpiringGlowStyle()
	return self.NormalizeGlowStyleForIconShape(addon.db and addon.db[M.style] or "PULSING", self:GetIconShape())
end

function Reminder:QueueGlowRefresh()
	if self.glowRefreshPending then return end
	self.glowRefreshPending = true
	RunNextFrame(function()
		self.glowRefreshPending = false
		if not Glow or not self.glowShown then return end
		for target, config in pairs(self.glowTargets or {}) do Glow.Refresh(target, GLOW_KEY, config.style, config) end
	end)
end

function Reminder:SetGlowShown(show)
	if not Glow then return end
	self.glowTargets = self.glowTargets or {}
	local nextTargets = {}
	local refresh = false
	if show then
		local style, inset, shape = self:GetGlowStyle(), self:GetGlowInset(), self:GetIconShape()
		local r, g, b, a = self:GetGlowColor()
		for _, target in ipairs(self:GetGlowTargets() or {}) do
			local targetStyle, cr, cg, cb, ca = style, r, g, b, a
			local showExpiring = target._eqolReminderWarningExpiration
			if self.editModeActive then showExpiring = self.editModeGlowPreviewExpiring == true end
			if enabled(M.separate) and showExpiring then
				targetStyle = self:GetExpiringGlowStyle()
				cr, cg, cb, ca = self:GetExpiringGlowColor()
			end
			local previous = self.glowTargets[target]
			local config = { style = targetStyle, inset = inset, shape = shape, color = { cr, cg, cb, ca }, hostFrameLevelOffset = 8, frameLevel = 8 }
			nextTargets[target] = config
			if not previous or previous.style ~= targetStyle or previous.inset ~= inset or previous.shape ~= shape
				or previous.color[1] ~= cr or previous.color[2] ~= cg or previous.color[3] ~= cb or previous.color[4] ~= ca then
				if previous then Glow.Stop(target, GLOW_KEY, true) end
				Glow.Start(target, GLOW_KEY, targetStyle, config)
				refresh = true
			end
		end
	end
	for target in pairs(self.glowTargets) do
		if not nextTargets[target] then Glow.Stop(target, GLOW_KEY, true) end
	end
	self.glowTargets = nextTargets
	self.glowShown = next(nextTargets) ~= nil
	if refresh then self:QueueGlowRefresh() end
end

function Reminder:SetGlowPreviewForSetting(key)
	if not self.editModeActive then return end
	if key == M.separate or key == M.style or key == M.color then
		self.editModeGlowPreviewExpiring = enabled(M.separate)
	elseif key == "classBuffReminderGlow" or key == "classBuffReminderGlowStyle" or key == "classBuffReminderGlowInset"
		or key == "classBuffReminderGlowColor" or key == "classBuffReminderGlowUseClassColor" then
		self.editModeGlowPreviewExpiring = nil
	end
end

function Reminder:SetIconPresentationSetting(key, value)
	if not addon.db then return end
	addon.db[key] = value
	if key == M.keybind then self:RefreshReminderKeybindEvents() end
	self:SetGlowPreviewForSetting(key)
	self:StopAllGlowTargetsImmediate()
	self:RequestUpdate(true)
end

local function styleOptions()
	local options = {}
	for _, option in ipairs(Reminder.GetGlowStyleOptions(Reminder:GetIconShape())) do
		options[#options + 1] = { value = option.value, label = L[option.labelKey] or option.fallback }
	end
	return options
end

function Reminder:RegisterIconPresentationSettings(cat, section)
	for _, control in ipairs({
		{ key = M.separate, label = "ClassBuffReminderExpiringGlow" },
		{ key = M.time, label = "ClassBuffReminderShowTimeLeft" },
		{ key = M.count, label = "ClassBuffReminderShowItemCount" },
		{ key = M.keybind, label = "ClassBuffReminderShowKeybinds" },
	}) do
		local key = control.key
		addon.functions.SettingsCreateCheckbox(cat, {
			var = key, text = L[control.label], desc = L[control.label .. "Desc"], default = defaultEnabled(key),
			get = function() return enabled(key) end,
			func = function(value) self:SetIconPresentationSetting(key, value == true) end,
			parentSection = section, newTagID = control.label,
		})
	end
	addon.functions.SettingsCreateDropdown(cat, {
		var = M.style, text = L["ClassBuffReminderExpiringGlowStyle"], default = "PULSING",
		get = function() return self:GetExpiringGlowStyle() end,
		func = function(value) self:SetIconPresentationSetting(M.style, self.NormalizeGlowStyleForIconShape(value, self:GetIconShape())) end,
		optionfunc = styleOptions, isEnabled = function() return enabled(M.separate) end,
		parentSection = section, newTagID = "ClassBuffReminderExpiringGlowStyle",
	})
	addon.functions.SettingsCreateColorPicker(cat, {
		var = M.color, text = L["ClassBuffReminderExpiringGlowColor"], default = M.defaultColor, hasOpacity = true,
		getColor = function() return self:GetExpiringGlowColor() end,
		setColor = function(_, r, g, b, a) self:SetIconPresentationSetting(M.color, { r = r, g = g, b = b, a = a or 1 }) end,
		isEnabled = function() return enabled(M.separate) end,
		parentSection = section, newTagID = "ClassBuffReminderExpiringGlowColor",
	})
end

local function appendPresentationTab(settings, SettingType, id, name, toggle)
	local fields = {}
	settings[#settings + 1] = {
		name = name, kind = SettingType.Collapsible, id = id, defaultCollapsed = true,
		navigationReset = function()
			if not addon.db then return end
			for _, field in ipairs(fields) do addon.db[field] = nil end
			Reminder:SetIconPresentationSetting(toggle, nil)
		end,
	}
	local function append(data, field, default)
		data.parentId, data.navigationField, data.default = id, field, default
		data.isEnabled = data.isEnabled or function() return enabled(toggle) end
		data.get = data.get or function() return textStyleValue(field, "", default) end
		data.set = data.set or function(_, value) Reminder:SetIconPresentationSetting(field, value) end
		fields[#fields + 1] = field
		settings[#settings + 1] = data
	end
	return append
end

local function appendPresentationToggle(append, SettingType, toggle, label)
	append({
		name = L[label], tooltip = L[label .. "Desc"], kind = SettingType.Checkbox,
		isEnabled = function() return true end, get = function() return enabled(toggle) end,
	}, toggle, defaultEnabled(toggle))
end

local function appendTextTab(settings, SettingType, id, name, prefix, toggle, label)
	local append = appendPresentationTab(settings, SettingType, id, name, toggle)
	appendPresentationToggle(append, SettingType, toggle, label)
	if toggle == M.keybind then
		append({ name = L["Anchor"], kind = SettingType.Dropdown, values = KEYBIND_ANCHORS }, prefix .. "Anchor", DEFAULT_KEYBIND_ANCHOR)
	end
	append({ name = L["Font"], kind = SettingType.Dropdown, values = textFontOptions }, prefix .. "Font", "__EQOL_GLOBAL_FONT__")
	append({ name = _G.FONT_SIZE, kind = SettingType.Slider, minValue = 0, maxValue = 64, valueStep = 1,
		get = function() return textStyleNumber(prefix, "Size", 0, 0, 64) end,
		formatter = function(value) return value == 0 and _G.DEFAULT or tostring(value) end }, prefix .. "Size", 0)
	append({ name = L["Font outline"], kind = SettingType.Dropdown,
		values = function() return addon.functions.GetFontStyleOptionList(true) end }, prefix .. "Outline", "__EQOL_GLOBAL_FONT_STYLE__")
	local color = { name = L[toggle == M.keybind and "Custom color" or "Color"], kind = SettingType.Color, hasOpacity = true }
	if toggle == M.keybind then
		append({ name = L["Use class color"], kind = SettingType.Checkbox }, prefix .. "UseClassColor", false)
		color.isEnabled = function() return enabled(toggle) and not textStyleValue(prefix, "UseClassColor", false) end
	end
	append(color, prefix .. "Color", { r = 1, g = 1, b = 1, a = 1 })
	for _, axis in ipairs({ "X", "Y" }) do
		local field = "Offset" .. axis
		append({ name = L["Offset " .. axis], kind = SettingType.Slider, minValue = -100, maxValue = 100, valueStep = 1,
			get = function() return textStyleNumber(prefix, field, 0, -100, 100) end }, prefix .. field, 0)
	end
end

function Reminder:BuildIconPresentationEditModeSettings(SettingType)
	local settings = {}
	appendTextTab(settings, SettingType, "iconTime", L["mythicPlusTimerTimeLeft"], "classBuffReminderTimeText", M.time, "ClassBuffReminderShowTimeLeft")
	appendTextTab(settings, SettingType, "iconStacks", L["Stacks"], "classBuffReminderItemCountText", M.count, "ClassBuffReminderShowItemCount")
	appendTextTab(settings, SettingType, "iconKeybinds", L["CooldownPanelKeybindsHeader"], KEYBIND_TEXT, M.keybind, "ClassBuffReminderShowKeybinds")

	local append = appendPresentationTab(settings, SettingType, "iconExpiryGlow", L["Glow"], M.separate)
	appendPresentationToggle(append, SettingType, M.separate, "ClassBuffReminderExpiringGlow")
	append({
		name = L["ClassBuffReminderExpiringGlowStyle"], kind = SettingType.Dropdown,
		get = function() return self:GetExpiringGlowStyle() end, values = styleOptions,
		set = function(_, value) self:SetIconPresentationSetting(M.style, self.NormalizeGlowStyleForIconShape(value, self:GetIconShape())) end,
	}, M.style, "PULSING")
	append({
		name = L["ClassBuffReminderExpiringGlowColor"], kind = SettingType.Color,
		get = function() local r, g, b, a = self:GetExpiringGlowColor(); return { r = r, g = g, b = b, a = a } end,
	}, M.color, M.defaultColor)
	return settings
end
