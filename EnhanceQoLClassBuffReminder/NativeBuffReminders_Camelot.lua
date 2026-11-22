local addon = _G.EnhanceQoL
local Reminder = addon.ClassBuffReminder
local M = {}

-- Ordered definitions contain public configuration only. Presence is evaluated
-- by native aura groups, never by the definition resolver or the layout loop.
Reminder.nativeBuffReminderDefinitions = {}

function M.PersonalBlessing(self)
	local data = self.foreverBuffs
	local selection = self:GetForeverBlessingSelection()
	local fixed = selection ~= "AUTO" and data.blessings[selection]
	if fixed then return self:GetInteractionSpellId(fixed), fixed end
	local playstyle, class = self:GetForeverUnitPlaystyle("player")
	if playstyle == "TANK" then playstyle = (class == "PALADIN" or class == "SHAMAN") and "TANK_MANA" or "TANK_MELEE" end
	if playstyle == "UNKNOWN" and class == "PALADIN" then playstyle = "PALADIN_UNKNOWN" end
	for _, key in ipairs(data.blessingProfiles[playstyle] or {}) do
		local spellId = self:GetInteractionSpellId(data.blessings[key])
		if spellId then return spellId, data.blessingAuras[playstyle] end
	end
	for _, key in ipairs(data.blessingOrder) do
		local spellId = self:GetInteractionSpellId(data.blessings[key])
		if spellId then return spellId, self.foreverBlessingSpellIds end
	end
end

function M.Definitions(self)
	local definitions = {}
	for _, definition in ipairs(self.nativeBuffReminderDefinitions) do definitions[#definitions + 1] = definition end
	local class = self:GetClassToken()
	if self.classBuffGroupProviders[class] then
		definitions[#definitions + 1] = { key = "GROUP_SELF_" .. class, class = class, providerClass = class }
	end
	for _, category in ipairs(self.classicBuffs and self.classicBuffs[class] or {}) do
		-- Group-family auras are checked on player here; group counts remain
		-- owned by the unrestricted responsibility path. Enchants are separate.
		if not category.weapon and class ~= "PALADIN" then
			definitions[#definitions + 1] = {
				key = "CLASS_" .. category.spellIds[1], class = class, spellIds = category.spellIds,
				category = category,
			}
		end
	end
	if class == "PALADIN" and self.GetForeverBlessingSelection then
		local spellId, auraIds = M.PersonalBlessing(self)
		if spellId then definitions[#definitions + 1] = { key = "PERSONAL_BLESSING", class = class, displaySpellId = spellId, auraIds = auraIds } end
	end
	if class == "PALADIN" and self.IsForeverProtectionPaladin and self:IsForeverProtectionPaladin() then
		definitions[#definitions + 1] = { key = "RIGHTEOUS_FURY", class = class, spellIds = self.foreverBuffs.righteousFurySpellIds }
	end
	for _, id in ipairs(self.GetCustomBuffSpellIds and self:GetCustomBuffSpellIds() or {}) do
		local custom = self:GetCustomBuffDefinition(class, id)
		definitions[#definitions + 1] = { key = "CUSTOM_" .. id, class = class, displaySpellId = id, auraIds = custom.auraIds }
	end
	-- Existing non-aura reminders join the same row, without a secret condition.
	-- Their normal eligibility and interaction filters have already been applied.
	for i, entry in ipairs(self.GetSupplementalMissingEntries and self:GetSupplementalMissingEntries() or {}) do
		definitions[#definitions + 1] = { key = "SUPPLEMENTAL_" .. (entry.sourceKind or entry.spellId or i), class = class,
			displaySpellId = entry.spellId or 1, auraIds = {}, ordinaryEntry = entry }
	end
	local camping = self.foreverCamping
	if camping and not (InCombatLockdown and InCombatLockdown()) then
		if addon.db[camping.food] == true and addon.Aura and addon.Aura.ForeverWellFedSpellIDs then
			definitions[#definitions + 1] = { key = "FOREVER_FOOD", class = class, displaySpellId = 1248406, auraIds = addon.Aura.ForeverWellFedSpellIDs, ordinaryEntry = camping.FoodEntry() }
		end
		if addon.db[camping.camp] == true then
			definitions[#definitions + 1] = { key = "FOREVER_CAMP", class = class, displaySpellId = camping.campBuff, auraIds = { camping.campBuff } }
		end
	end
	return definitions
end

function M.Release(state)
	if state.gate and state.gate.enabled then state.gate:Release() end
	if state.host then state.host:Hide() end
	for _, name in ipairs({ "measure", "advance" }) do
		local source = state[name]
		if source then addon.AuraCompat:DisableAuraContainer(source) end
	end
	state.layoutSignature = nil
	for _, cached in pairs(state.glows or {}) do
		cached.glow:Hide()
		for _, animation in ipairs(cached.glow._eqolAnimationGroups or {}) do animation:Stop() end
		cached.signature = nil
	end
end

function M.CanEvaluate(self)
	if self.editModeActive or not addon.db or addon.db.classBuffReminderEnabled ~= true then return false end
	if self:CanReadAuraData() then return false end
	if self:IsReminderEvaluationBlockedByCombat() or not self:IsGroupModeAllowed() then return false end
	if UnitOnTaxi and UnitOnTaxi("player") then return false end
	if not UnitExists("player") or not UnitIsConnected("player") or UnitIsDeadOrGhost("player") then return false end
	if self:IsHideInRestedAreaEnabled() and self:IsPlayerInRestedArea() then return false end
	return true
end

function M.GetSpell(self, definition)
	if definition.class ~= self:GetClassToken() then return nil end
	local provider = definition.providerClass and self.classBuffGroupProviders[definition.providerClass]
	local ids = definition.spellIds or (provider and provider.spellIds)
	ids = ids and self:GetEnabledReminderSpellIds(ids)
	local category = definition.category
	local spellId
	if category and category.mageMagic then
		spellId = self:GetSelectedMageMagicSpell(self:GetMageMagicCandidates(ids))
	elseif category and category.alternativeKey then
		spellId = self:GetSelectedClassicAlternative(category.alternativeKey, self:GetClassicAlternativeCandidates(ids))
	else
		spellId = definition.displaySpellId or (ids and self:GetInteractionSpellId(ids))
	end
	if not spellId or self:IsSpellReminderDisabled(spellId) then return nil end
	if definition.combatOnly and not self:IsClassBuffCombatOnly(spellId) then return nil end
	return spellId, definition.auraIds or ids
end

local template = "DisableUntrustedLayoutScriptsTemplate"

function M.PublicNumber(value)
	if issecretvalue and issecretvalue(value) then return nil end
	return type(value) == "number" and value or nil
end

function M.Text(self, state, definition, scale, size)
	local visual = state.visual
	local itemText, itemSize = self:UpdateReminderItemCountText(visual, definition.ordinaryEntry, { width = size, layoutRestricted = true })
	local text = visual.countText
	if not text then
		-- Match the ordinary X/Y text's parent and draw layer. Item quantities
		-- keep their separate text overlay, as in the ordinary renderer.
		text = visual:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		text:SetJustifyH("CENTER")
		text:SetShadowOffset(1, -1)
		text:SetShadowColor(0, 0, 0, 1)
		visual.countText = text
	end
	local entry = definition.ordinaryEntry
	local missing, total = M.PublicNumber(entry and entry.countMissing), M.PublicNumber(entry and entry.countTotal)
	local value = entry and entry.shortText
	if issecretvalue and issecretvalue(value) then value = nil end
	if missing and total and total > 0 then
		value = string.format("%d/%d", math.max(0, math.floor(missing + 0.5)), math.max(0, math.floor(total + 0.5)))
	elseif type(value) ~= "string" then
		-- This static label describes only the player. Native clipping decides
		-- whether it is visible; it must never imply a group-wide missing count.
		value = (definition.providerClass or (definition.category and definition.category.group) or definition.key == "PERSONAL_BLESSING") and "1/1" or ""
	end
	local fontSize, outline, r, g, b, a, offsetX, offsetY = self:GetIconCountTextStyle()
	fontSize = math.max(8, math.floor(fontSize * scale + 0.5))
	offsetX, offsetY = math.floor(offsetX * scale + 0.5), math.floor(offsetY * scale + 0.5)
	local flags = outline == "NONE" and "" or (outline == "THICKOUTLINE" and "THICKOUTLINE" or (outline == "MONOCHROME_OUTLINE" and "OUTLINE,MONOCHROME" or "OUTLINE"))
	text:SetFont((addon.variables and addon.variables.defaultFont) or STANDARD_TEXT_FONT, fontSize, flags)
	text:SetTextColor(r, g, b, a)
	text:ClearAllPoints()
	text:SetPoint("CENTER", visual, "CENTER", offsetX, offsetY)
	text:SetWidth(size + 2)
	text:SetText(value)
	-- Bounds derive only from public text and settings. Never measure a region
	-- whose position follows restricted aura geometry.
	local itemX = tonumber(addon.db.classBuffReminderItemCountTextOffsetX) or 0
	local itemY = tonumber(addon.db.classBuffReminderItemCountTextOffsetY) or 0
	return math.max(#value * fontSize + math.abs(offsetX) + math.abs(offsetY), #itemText * itemSize + math.abs(itemX) + math.abs(itemY))
end

-- These sources supply an advance of one public step while an aura is missing,
-- and zero while present. No native dimensions or visibility are read by Lua.
function M.LayoutSources(state, parent, ids, step)
	local compat = addon.AuraCompat
	local signature = tostring(step) .. ":" .. table.concat(ids, ",")
	if state.layoutSignature == signature then return true end
	local filters = { includeSpellIDs = {} }
	for _, id in ipairs(ids) do filters.includeSpellIDs[id] = true end
	for _, key in ipairs({ "measure", "advance" }) do
		local source = state[key]
		if not source then
			source = compat:CreateAuraContainer(parent, nil, compat.defaultContainerTemplate .. "," .. template)
			if not source then return false end
			state[key] = source
		end
		compat:DisableAuraContainer(source)
		source:SetAlpha(0)
		if not compat:ConfigureAuraContainerLayout(source, {
			axis = _G.AnchorUtil.FlowLayoutAxis.Horizontal, anchorPoint = "TOPLEFT",
			horizontalGrowthDirection = 1, verticalGrowthDirection = -1,
			padding = { left = 0, right = 0, top = 0, bottom = 0 }, maximumLineSize = step + 2,
		}) then return false end
		if not compat:RegisterAuraGroup(source, "missing-advance", "HELPFUL", {
			maxFrameCount = 1, candidateFilters = filters,
			layout = { elementWidth = step + 1, elementHeight = step + 1, elementSpacing = 0, lineSpacing = 0, groupSpacing = 0, groupLineSpacing = 0 },
			initializeFrame = function(button) button:SetSize(1, 1) button:EnableMouse(false) end,
		}) then return false end
		if not compat:RefreshAuraContainer(source, "player") then return false end
	end
	state.layoutSignature = signature
	return true
end

function M.Glow(self, state, size)
	local enabled = addon.db.classBuffReminderGlow
	if enabled == nil then enabled = self.defaults.glow end
	local style, shape = self:GetGlowStyle(), self:GetIconShape()
	local key = style .. ":" .. shape
	for otherKey, other in pairs(state.glows or {}) do
		if not enabled or otherKey ~= key then
			other.glow:Hide()
			for _, animation in ipairs(other.glow._eqolAnimationGroups or {}) do animation:Stop() end
			other.signature = nil
		end
	end
	if not enabled then return end
	local r, g, b, a = self:GetGlowColor()
	local inset = self:GetGlowInset()
	local signature = table.concat({ size, inset, r, g, b, a }, ":")
	state.glows = state.glows or {}
	local cached = state.glows[key]
	local compat = addon.AuraCompat
	if not cached or cached.signature ~= signature then
		local options = { style = style, shape = shape, color = { r, g, b, a }, inset = inset,
			width = size, height = size, layoutRestricted = true, frameLevelOffset = 15 }
		if cached then
			compat:UpdateRestrictedAuraGlow(cached.glow, state.visual, options)
		else
			local glow = compat:CreateRestrictedAuraGlow(state.visual, state.visual, options)
			if not glow then return end
			cached = { glow = glow }
			state.glows[key] = cached
		end
		cached.signature = signature
	end
	cached.glow:Show()
end

function M.UpdateEntry(self, state, definition, spellId, ids, root, size, step)
	local compat = addon.AuraCompat
	if not M.LayoutSources(state, root, ids, step) then M.Release(state) return false end
	local host = state.host
	if not host then
		host = CreateFrame("Frame", nil, root, template)
		host:EnableMouse(false)
		state.host = host
	end
	host:SetSize(size, size)
	local spellSet = {}
	for _, id in ipairs(ids) do spellSet[id] = true end
	-- Cover the full configured glow envelope, including positive glow inset.
	local padding = size + math.abs(self:GetGlowInset())
	local initialPadding = math.max(padding, state.clipPadding or 0)
	local options = {
		width = size, height = size, unit = "player", filterString = "HELPFUL",
		paddingLeft = initialPadding, paddingRight = initialPadding, paddingTop = initialPadding, paddingBottom = initialPadding,
		candidateFilters = { includeSpellIDs = spellSet }, enabled = true,
		frameStrata = root:GetFrameStrata(), frameLevel = root:GetFrameLevel() + 1,
	}
	local gate = state.gate
	if not gate then
		gate = compat:CreateInverseAuraClip(host, host, options)
		if not gate then M.Release(state) return false end
		state.gate = gate
		local visual = CreateFrame("Frame", nil, gate.content, template)
		visual:SetAllPoints(gate.content)
		visual.icon = visual:CreateTexture(nil, "ARTWORK")
		visual.icon:SetAllPoints(visual)
		state.visual = visual
	elseif not gate:Configure(options) then
		M.Release(state)
		return false
	end
	state.visual.icon:SetTexture((definition.ordinaryEntry and definition.ordinaryEntry.icon) or C_Spell.GetSpellTexture(spellId))
	self:ApplyReminderFoodTint(state.visual.icon, definition.ordinaryEntry)
	self:ApplyIconShape(state.visual, state.visual.icon)
	local textPadding = M.Text(self, state, definition, addon.db.classBuffReminderScale or self.defaults.scale, size)
	local fullPadding = math.max(padding, textPadding)
	options.paddingLeft, options.paddingRight, options.paddingTop, options.paddingBottom = fullPadding, fullPadding, fullPadding, fullPadding
	if not gate:Configure(options) then M.Release(state) return false end
	state.clipPadding = fullPadding
	M.Glow(self, state, size)
	host:Show()
	return true
end

function M.Layout(self, entries, root, size, step)
	local direction = self:GetGrowthDirection()
	local vertical = direction == "UP" or direction == "DOWN"
	local previous, edge = root, "CENTER"
	-- Measure backwards from a fixed public origin. Its midpoint supplies half
	-- the total missing-only advance through native anchors, not arithmetic.
	for _, state in ipairs(entries) do
		state.measure:ClearAllPoints()
		if vertical then state.measure:SetPoint("BOTTOM", previous, edge, 0, -step - 1)
		else state.measure:SetPoint("LEFT", previous, edge, -step - 1, 0) end
		previous, edge = state.measure, vertical and "TOP" or "RIGHT"
	end
	local bounds = self.nativeBuffReminderBounds
	if not bounds then
		bounds = CreateFrame("Frame", nil, root, template)
		self.nativeBuffReminderBounds = bounds
	end
	bounds:ClearAllPoints()
	if vertical then
		bounds:SetWidth(1)
		bounds:SetPoint("BOTTOM", previous, edge)
		bounds:SetPoint("TOP", root, "CENTER", 0, 1)
	else
		bounds:SetHeight(1)
		bounds:SetPoint("LEFT", previous, edge)
		bounds:SetPoint("RIGHT", root, "CENTER", 1, 0)
	end
	local centered = self:GetGrowthFromCenter()
	local reverse = direction == "LEFT" or direction == "DOWN"
	local anchor = centered and bounds or (reverse and previous or root)
	local point = centered and "CENTER" or (reverse and edge or "CENTER")
	local offset = centered and ((step - 1) / 2) or (reverse and step or 0)
	for _, state in ipairs(entries) do
		state.host:ClearAllPoints()
		state.host:SetPoint("CENTER", anchor, point, vertical and 0 or offset, vertical and offset or 0)
		state.advance:ClearAllPoints()
		if vertical then state.advance:SetPoint("TOP", state.host, "CENTER", 0, step + 1)
		else state.advance:SetPoint("RIGHT", state.host, "CENTER", step + 1, 0) end
		anchor, point, offset = state.advance, vertical and "BOTTOM" or "LEFT", 0
	end

	-- The first host stays at the start of the compacted row. The final advance
	-- ends one step past the last missing icon, even when trailing buffs are present.
	if reverse then
		local inset = size / 2 - step
		self.nativeBuffReminderPetAnchor = { vertical and "TOP" or "RIGHT", entries[1].host, "CENTER", vertical and 0 or inset, vertical and inset or 0 }
	else
		self.nativeBuffReminderPetAnchor = { vertical and "BOTTOM" or "LEFT", anchor, point, vertical and 0 or -size / 2, vertical and -size / 2 or 0 }
	end
end

function M.ClearPetAnchor(self)
	if not self.nativeBuffReminderPetAnchor then return end
	self.nativeBuffReminderPetAnchor = nil
	self:PositionPetHealthReminder()
end

function M.ReleaseAll(self)
	M.ClearPetAnchor(self)
	for _, state in pairs(self.nativeBuffReminderStates or {}) do M.Release(state) end
end

function M.Update(self)
	if not M.CanEvaluate(self) then M.ReleaseAll(self) return end
	local frame = self:EnsureFrame()
	self:ApplyVisualSettings()
	local root = self.nativeBuffReminderRoot
	if not root then
		root = CreateFrame("Frame", nil, UIParent)
		root:EnableMouse(false)
		root:SetSize(1, 1)
		self.nativeBuffReminderRoot = root
	end
	root:SetFrameStrata(frame:GetFrameStrata())
	root:SetAlpha(frame:GetAlpha())
	root:ClearAllPoints()
	root:SetPoint("CENTER", frame, "CENTER")
	local size = frame.iconHolder._eqolVisualSize or 64
	local step = frame._eqolClassBuffReminderIconStep
	self.nativeBuffReminderStates = self.nativeBuffReminderStates or {}
	local states, active, entries = self.nativeBuffReminderStates, {}, {}
	for _, definition in ipairs(M.Definitions(self)) do
		local spellId, ids = M.GetSpell(self, definition)
		if spellId then
			local state = states[definition.key] or {}
			states[definition.key] = state
			active[definition.key] = true
			if M.UpdateEntry(self, state, definition, spellId, ids, root, size, step) then entries[#entries + 1] = state end
		end
	end
	if #entries > 0 then
		M.Layout(self, entries, root, size, step)
		self:PositionPetHealthReminder()
		-- The native row also carries public supplemental icons. Retire their
		-- duplicate ordinary presentation without reading native visibility.
		self:StopAllGlowTargetsImmediate()
		frame:Hide()
	else
		M.ClearPetAnchor(self)
	end
	for key, state in pairs(states) do
		if not active[key] then M.Release(state) end
	end
end

local updateDisplay = Reminder.UpdateDisplay
function Reminder:UpdateDisplay()
	updateDisplay(self)
	M.Update(self)
end

local unregisterEvents = Reminder.UnregisterEvents
function Reminder:UnregisterEvents()
	M.ReleaseAll(self)
	unregisterEvents(self)
end
