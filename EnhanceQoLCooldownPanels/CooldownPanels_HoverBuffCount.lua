local addon = _G.EnhanceQoL
local CooldownPanels = addon and addon.Aura and addon.Aura.CooldownPanels
if not CooldownPanels then return end

local Count = { maxEntries = 32 }
CooldownPanels.HoverBuffCount = Count
local AuraCompat = addon.AuraCompat
local layoutTemplate = "DisableUntrustedLayoutScriptsTemplate"
local groupKeyPrefix = "hover-buff-count-"

local function initButton(button)
	button:SetSize(1, 1)
	button:EnableMouse(false)
end

local function configureSource(state, bucket, step)
	local source = state.source
	if not AuraCompat:ConfigureAuraContainerLayout(source, {
		axis = _G.AnchorUtil.FlowLayoutAxis.Vertical,
		anchorPoint = "TOPLEFT",
		horizontalGrowthDirection = 1,
		verticalGrowthDirection = -1,
		padding = { left = 0, right = 0, top = 1, bottom = 0 },
		maximumLineSize = #bucket * step + 2,
	}) then return false end
	local layout = { elementWidth = 1, elementHeight = step, elementSpacing = 0, lineSpacing = 0, groupSpacing = 0, groupLineSpacing = 0 }
	for i, config in ipairs(bucket) do
		local groupKey = groupKeyPrefix .. i
		if not AuraCompat:RegisterAuraGroup(source, groupKey, config.filterString, {
			maxFrameCount = 1,
			candidateFilters = { includeSpellIDs = config.includeSpellIDs },
			layout = layout,
			initializeFrame = initButton,
		}) then return false end
		if i > state.enabledGroups and i <= state.registeredGroups then source:SetAuraGroupEnabled(groupKey, true) end
		state.registeredGroups = math.max(state.registeredGroups, i)
		state.enabledGroups = math.max(state.enabledGroups, i)
	end
	for i = #bucket + 1, state.enabledGroups do
		source:SetAuraGroupEnabled(groupKeyPrefix .. i, false)
	end
	state.enabledGroups = #bucket
	return AuraCompat:RefreshAuraContainer(source, bucket[1].unit)
end

local function getState(anchor)
	local state = anchor._eqolHoverBuffCount
	if state then return state end
	local clip = CreateFrame("Frame", nil, anchor, layoutTemplate)
	clip:SetClipsChildren(true)
	clip:EnableMouse(false)
	clip:Hide()
	local track = CreateFrame("Frame", nil, clip, layoutTemplate)
	track:EnableMouse(false)
	state = { clip = clip, track = track, sources = {}, labels = {} }
	anchor._eqolHoverBuffCount = state
	return state
end

function Count:Release(anchor)
	local state = anchor and anchor._eqolHoverBuffCount
	if not (state and state.active) then return end
	state.active, state.signature = nil, nil
	state.clip:Hide()
	state.track:ClearAllPoints()
	for i = 1, state.sourceCount do
		local source = state.sources[i].source
		AuraCompat:DisableAuraContainer(source)
		source:ClearAllPoints()
	end
	state.sourceCount = 0
end

function Count:Refresh(anchor)
	local state = anchor and anchor._eqolHoverBuffCount
	if not (state and state.active) then return false end
	for i = 1, state.sourceCount do
		if not AuraCompat:RefreshAuraContainer(state.sources[i].source) then
			self:Release(anchor)
			return false
		end
	end
	return true
end

function Count:Configure(anchor, configs, options)
	if not anchor then return false end
	local total = math.min(#configs, self.maxEntries)
	if total == 0 or not (AuraCompat and _G.AnchorUtil and _G.AnchorUtil.FlowLayoutAxis and _G.AnchorUtil.FlowLayoutAxis.Vertical
		and AuraCompat:HasAuraContainerSupport()) then
		self:Release(anchor)
		return false
	end
	options = options or {}
	local font = options.font or (addon.variables and addon.variables.defaultFont) or STANDARD_TEXT_FONT
	local size = options.fontSize or 12
	local flags = options.fontFlags or "OUTLINE"
	local point = options.point or "BOTTOMRIGHT"
	local relativePoint = options.relativePoint or point
	local x, y = options.x or -1, options.y or 1
	local pixelUtil = addon.PixelUtil
	local pixel = pixelUtil and pixelUtil.OnePixel(anchor) or 1
	if pixelUtil then x, y = pixelUtil.Snap(x, anchor), pixelUtil.Snap(y, anchor) end
	local color = options.color or {}
	local r, g, b, a = color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1
	local level = anchor:GetFrameLevel()
	local strata = anchor:GetFrameStrata()
	local preview = options.previewCount
	if preview ~= nil then preview = math.max(0, math.min(total, math.floor(preview))) end

	local signatureParts = { font, size, flags, point, relativePoint, x, y, pixel, r, g, b, a, level, strata, total, preview or "LIVE" }
	if preview == nil then
		for i = 1, total do
			local config = configs[i]
			local spellIDs = {}
			for spellID, enabled in pairs(config.includeSpellIDs) do
				if enabled then spellIDs[#spellIDs + 1] = spellID end
			end
			if #spellIDs == 0 then
				self:Release(anchor)
				return false
			end
			table.sort(spellIDs)
			signatureParts[#signatureParts + 1] = config.unit .. ":" .. config.filterString .. ":" .. table.concat(spellIDs, ",")
		end
	end
	local signature = table.concat(signatureParts, "\0")
	local state = getState(anchor)
	if state.signature == signature then return true end
	self:Release(anchor)
	state.active, state.sourceCount = true, 0

	local height = size + 6
	local width = (#tostring(total) * 2 + 1) * size + 4
	if pixelUtil then
		-- An even pixel count also keeps the centered label on the raster.
		local pair = pixel * 2
		width = math.max(1, pixelUtil.Round(width / pair)) * pair
		height = math.max(1, pixelUtil.Round(height / pair)) * pair
	end
	-- Leave a full row of separation so pixel rounding cannot reveal a neighboring label.
	local step = height * 2
	local clip, track = state.clip, state.track
	clip:SetSize(width, height)
	clip:ClearAllPoints()
	clip:SetPoint(point, anchor, relativePoint, x, y)
	clip:SetFrameStrata(strata)
	clip:SetFrameLevel(level + 2)
	track:SetSize(width, height)
	track:SetFrameStrata(strata)
	track:SetFrameLevel(level + 3)

	local previous, edge = clip, "BOTTOMLEFT"
	if preview == nil then
		local byUnit, buckets = {}, {}
		for i = 1, total do
			local config = configs[i]
			local bucket = byUnit[config.unit]
			if not bucket then
				bucket = {}
				byUnit[config.unit] = bucket
				buckets[#buckets + 1] = bucket
			end
			bucket[#bucket + 1] = config
		end
		-- Each unit's native flow adds one full step per matching group and one
		-- unit of padding, even for an empty flow. Chain the units minus padding.
		for i, bucket in ipairs(buckets) do
			local sourceState = state.sources[i]
			if not sourceState then
				local source = AuraCompat:CreateAuraContainer(anchor, nil, AuraCompat.defaultContainerTemplate .. "," .. layoutTemplate)
				if not (source and type(source.SetAuraGroupEnabled) == "function") then
					self:Release(anchor)
					return false
				end
				source:SetAlpha(0)
				source:EnableMouse(false)
				sourceState = { source = source, enabledGroups = 0, registeredGroups = 0 }
				state.sources[i] = sourceState
			end
			local source = sourceState.source
			state.sourceCount = i
			source:SetPoint("BOTTOMLEFT", previous, edge, 0, -1)
			if not configureSource(sourceState, bucket, step) then
				self:Release(anchor)
				return false
			end
			previous, edge = source, "TOPLEFT"
		end
	end
	track:SetPoint("BOTTOMLEFT", previous, edge, 0, (preview or 0) * step)

	local rowEdge, labelX = "BOTTOM", 0
	local inset = 2 * pixel
	if point:find("LEFT", 1, true) then
		rowEdge, labelX = "BOTTOMLEFT", inset
	elseif point:find("RIGHT", 1, true) then
		rowEdge, labelX = "BOTTOMRIGHT", -inset
	end
	local labelY = height / 2
	if point:find("TOP", 1, true) then
		labelY = height - inset
	elseif point:find("BOTTOM", 1, true) then
		labelY = inset
	end

	-- The native track exposes one row. Align that row's text to the selected edge.
	-- No aura presence or geometry crosses into Lua.
	for value = 0, total do
		local label = state.labels[value + 1]
		if not label then
			label = track:CreateFontString(nil, "OVERLAY")
			state.labels[value + 1] = label
		end
		if not label:SetFont(font, size, flags) then label:SetFont(STANDARD_TEXT_FONT, size, flags) end
		label:SetTextColor(r, g, b, a)
		label:SetText(value .. "/" .. total)
		label:ClearAllPoints()
		label:SetPoint(point, track, rowEdge, labelX, labelY - value * step)
		label:Show()
	end
	for i = total + 2, #state.labels do state.labels[i]:Hide() end
	clip:Show()
	state.signature = signature
	return true
end
