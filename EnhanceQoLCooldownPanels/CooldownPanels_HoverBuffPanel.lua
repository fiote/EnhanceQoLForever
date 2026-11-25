local addon = _G.EnhanceQoL
local CooldownPanels = addon.Aura.CooldownPanels
local Helper = CooldownPanels.helper
local AuraCompat = addon.AuraCompat
local PixelUtil = addon.PixelUtil
local HoverBuffPanel = {}
CooldownPanels.HoverBuffPanel = HoverBuffPanel

local RESTRICTED_LAYOUT = "DisableUntrustedLayoutScriptsTemplate"
local ICON = 136116
local PADDING = 6
local DEFAULT_GAP = 5
local OPEN_DIRECTIONS = {
	DOWN = { from = "BOTTOMLEFT", edge = "TOPLEFT", x = 0, y = -1 },
	UP = { from = "TOPLEFT", edge = "BOTTOMLEFT", x = 0, y = 1 },
	RIGHT = { from = "TOPRIGHT", edge = "TOPLEFT", x = 1, y = 0 },
	LEFT = { from = "TOPLEFT", edge = "TOPRIGHT", x = -1, y = 0 },
}
local AUTO_DIRECTIONS = { "DOWN", "UP", "RIGHT", "LEFT" }
local SLOT_HEIGHT = 21
local ENTRY_ICON_SIZE = { min = 8, max = 64, default = 18 }
local LABEL_CELL_WIDTH = 114
local LIMIT = CooldownPanels.HoverBuffCount.maxEntries
local SLIDE_DISTANCE = 10
local OPEN_DURATION, CLOSE_DURATION = 0.20, 0.14
local VALID_ANIMATIONS = { NONE = true, FADE = true, SLIDE = true, REVEAL = true }

HoverBuffPanel.maxEntries = LIMIT
HoverBuffPanel.borderLimit = 64
HoverBuffPanel.entryIconSize = ENTRY_ICON_SIZE

function HoverBuffPanel:IsAvailable()
	return AuraCompat and AuraCompat.HasAuraContainerSupport and AuraCompat:HasAuraContainerSupport() == true
end

function HoverBuffPanel:IsEnabled(layout)
	return layout and layout.layoutMode == "HOVER_BUFF" and self:IsAvailable()
end

function HoverBuffPanel:CanAddEntry(panel)
	local count = 0
	for _ in pairs(panel.entries or {}) do
		count = count + 1
		if count >= LIMIT then return false end
	end
	return true
end

local function textValue(value)
	if type(value) == "string" then return (value:gsub("[\r\n]", " ")) end
	return ""
end

local function iconValue(value, fallback)
	local id = tonumber(value)
	if id and id > 0 and id <= 2147483647 then return math.floor(id) end
	return fallback
end

local function snap(value, pixel)
	return PixelUtil.Round(value / pixel) * pixel
end

local function makeTexture(frame)
	local texture = PixelUtil.ApplyTexturePixelSnapping(frame:CreateTexture(nil, "ARTWORK"))
	texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	return texture
end

local function makeText(frame, template)
	local text = frame:CreateFontString(nil, "OVERLAY", template)
	text:SetJustifyH("LEFT")
	text:SetWordWrap(false)
	return text
end

local WHITE = "Interface\\Buttons\\WHITE8x8"
local FALLBACK = {
	count = { 1, 1, 1, 1 },
	border = { 0.53, 0.46, 0.51, 1 },
	launcherBorder = { 0.84, 0.67, 0.31, 1 },
	background = { 0.16, 0.125, 0.17, 0.97 },
	launcherBackground = { 0.11, 0.10, 0.09, 0.98 },
	iconBorder = { 0.47, 0.39, 0.25, 1 },
	text = { 1, 0.82, 0.41, 1 },
	missingText = { 0.60, 0.55, 0.62, 1 },
	swipe = { 0, 0, 0, 0.65 },
}
FALLBACK.titleText = FALLBACK.text
HoverBuffPanel.styleColors = FALLBACK

local function color(style, field, fallback)
	local rgba = Helper.NormalizeColor(style[field .. "Color"], fallback)
	local r, g, b, a = rgba[1], rgba[2], rgba[3], rgba[4]
	if style[field .. "ClassColor"] then
		local _, token = UnitClass("player")
		local colors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
		local class = token and colors and colors[token]
		if class then r, g, b = class.r, class.g, class.b end
	end
	return r, g, b, a
end

local function resolveMedia(kind, value)
	if type(value) ~= "string" or value == "" then return nil end
	local hash = addon.functions.GetLSMMediaHash(kind)
	return hash[value] or (value:find("[/\\]") and value or nil)
end

local function applySurface(frame, style, field, fallback)
	local r, g, b, a = color(style, field, fallback)
	if not frame.hoverBackground then
		frame.hoverBackground = PixelUtil.ApplyTexturePixelSnapping(frame:CreateTexture(nil, "BACKGROUND"))
		frame.hoverBackground:SetAllPoints()
	end
	local texture = resolveMedia("background", style[field .. "Texture"]) or WHITE
	frame.hoverBackground:SetTexture(texture)
	frame.hoverBackground:SetVertexColor(r, g, b, a)
	frame.hoverBackground:SetShown(style[field .. "Enabled"] ~= false)
end

local function applyBorder(frame, anchor, style, field, defaultEnabled, fallback, shortestSide)
	if not frame then return end
	local limit = HoverBuffPanel.borderLimit
	local pixel = PixelUtil.OnePixel(anchor)
	local offset = PixelUtil.Snap(Helper.ClampInt(style[field .. "Offset"], -limit, limit, 0), anchor)
	offset = math.max(offset, -math.max(0, math.floor(shortestSide / (2 * pixel) - 1)) * pixel)
	local maxSize = math.max(1, math.floor((shortestSide + 2 * offset) / (2 * pixel)))
	local size = Helper.ClampInt(style[field .. "Size"], 1, math.min(limit, maxSize), 1)
	local enabled = style[field .. "Enabled"]
	if enabled == nil then enabled = defaultEnabled end
	local r, g, b, a = color(style, field, fallback)
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", anchor, "TOPLEFT", -offset, offset)
	frame:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", offset, -offset)
	addon.functions.SetSafeBorder(frame, enabled, resolveMedia("border", style[field .. "Texture"]) or WHITE, size, r, g, b, a, {
		stateKey = "_eqolHoverBuffBorder",
		defaultTexture = WHITE,
		drawLayer = "OVERLAY",
		pixelPerfect = true,
	})
end

local function applyFont(text, font, size, outline)
	local defaultSize = text.hoverFont and text.hoverFont[2] or 12
	outline = outline or addon.functions.GetGlobalFontStyleConfigKey()
	addon.functions.ApplyFontString(text, font, Helper.ClampInt(size, 6, 28, defaultSize), outline)
end

local function makeBorder(parent)
	return CreateFrame("Frame", nil, parent, RESTRICTED_LAYOUT)
end

local function makeSlotVisual(parent, anchor, missing)
	local frame = CreateFrame("Frame", nil, parent, RESTRICTED_LAYOUT)
	frame:SetAllPoints(anchor)
	local icon = makeTexture(frame)
	icon:SetDesaturated(missing)
	local empty
	if missing then
		icon:SetVertexColor(0.66, 0.62, 0.68)
		empty = PixelUtil.ApplyTexturePixelSnapping(frame:CreateTexture(nil, "ARTWORK"))
		empty:SetAllPoints(icon)
		empty:SetColorTexture(0.045, 0.035, 0.052, 0.94)
	end
	local label = makeText(frame, "GameFontNormalSmall")
	label.hoverFont = { label:GetFont() }
	return { frame = frame, icon = icon, empty = empty, label = label, border = makeBorder(frame) }
end

local function applySlotGeometry(visual, size, height, pixel)
	local icon, label = visual.icon, visual.label
	local inset = snap(4, pixel)
	icon:ClearAllPoints()
	icon:SetPoint("TOPLEFT", visual.frame, "TOPLEFT", inset, -snap((height - size) / 2, pixel))
	icon:SetSize(size, size)
	label:ClearAllPoints()
	label:SetPoint("LEFT", icon, "RIGHT", snap(6, pixel), 0)
	label:SetPoint("RIGHT", visual.frame, "RIGHT", -inset, 0)
end

local function releaseSlot(slot)
	if slot.swipeSource then AuraCompat:DisableAuraContainer(slot.swipeSource) end
	slot.swipeSignature = nil
	if slot.gate then slot.gate:Release() end
	slot.signature = nil
	slot.frame:Hide()
end

local function makeSlot(parent)
	local slot = { frame = CreateFrame("Frame", nil, parent, RESTRICTED_LAYOUT) }
	slot.presentClip = CreateFrame("Frame", nil, slot.frame, RESTRICTED_LAYOUT)
	slot.presentClip:SetClipsChildren(true)
	slot.present = makeSlotVisual(slot.presentClip, slot.frame, false)
	return slot
end

local function bindSwipe(slot, aura, r, g, b, a)
	local layer = CreateFrame("Frame", nil, aura, RESTRICTED_LAYOUT)
	layer:SetAllPoints(aura)
	local cooldown = CreateFrame("Cooldown", nil, layer, "CooldownFrameTemplate")
	cooldown:SetAllPoints(layer)
	cooldown:SetHideCountdownNumbers(true)
	if cooldown.SetUseAuraDisplayTime then cooldown:SetUseAuraDisplayTime(true) end
	cooldown:SetDrawSwipe(true)
	cooldown:SetDrawEdge(false)
	cooldown:SetDrawBling(false)
	cooldown:SetReverse(true)
	-- Binding marks the cooldown's state secret. Configure the swipe first.
	cooldown:SetSwipeColor(r, g, b, a)
	aura:SetDurationCooldown(cooldown)
	if slot.swipeLayer then slot.swipeLayer:Hide() end
	slot.swipeLayer = layer
end

local function configureSwipe(slot, config, style)
	local signature = style.swipeEnabled == true and config.signature or nil
	if not signature then
		if slot.swipeSignature then AuraCompat:DisableAuraContainer(slot.swipeSource) end
		slot.swipeSignature = nil
		return
	end
	local r, g, b, a = color(style, "swipe", FALLBACK.swipe)
	local tint = table.concat({ r, g, b, a }, ":")
	slot.requestedSwipeTint = tint
	if slot.swipeTimer and slot.pendingSwipeTint ~= tint then
		slot.swipeTimer:Cancel()
		slot.swipeTimer = nil
	end
	if signature ~= slot.swipeSignature then
		slot.swipeSignature = nil
		local source = slot.swipeSource
		if not source then
			source = AuraCompat:CreateAuraContainer(slot.present.frame, nil, AuraCompat.defaultContainerTemplate .. "," .. RESTRICTED_LAYOUT)
			if not source then return end
			source:SetAllPoints(slot.present.frame)
			slot.swipeSource = source
		end
		local filters = { includeSpellIDs = config.includeSpellIDs }
		if not slot.swipeButton then
			local anchor = CreateFrame("Frame", nil, slot.present.frame, RESTRICTED_LAYOUT)
			anchor:SetAllPoints(slot.present.icon)
			slot.swipeButton = AuraCompat:RegisterAuraSlot(source, "hover-swipe", config.filterString, {
				anchorFrame = anchor,
				candidateFilters = filters,
				initializeFrame = function(aura)
					aura:EnableMouse(false)
					bindSwipe(slot, aura, r, g, b, a)
					slot.swipeTint = tint
				end,
			})
			if not slot.swipeButton then return end
		elseif not AuraCompat:UpdateAuraSlot(source, "hover-swipe", { filterString = config.filterString, candidateFilters = filters }) then
			AuraCompat:DisableAuraContainer(source)
			return
		end
		if not AuraCompat:RefreshAuraContainer(source, config.unit) then
			AuraCompat:DisableAuraContainer(source)
			return
		end
		slot.swipeSignature = signature
	end
	if slot.swipeTint ~= tint and not slot.swipeTimer then
		-- Rebind after the picker settles instead of creating a cooldown for every slider tick.
		slot.pendingSwipeTint = tint
		slot.swipeTimer = C_Timer.NewTimer(0.2, function()
			slot.swipeTimer = nil
			if not slot.swipeSignature or slot.requestedSwipeTint ~= tint then return end
			bindSwipe(slot, slot.swipeButton, r, g, b, a)
			slot.swipeTint = tint
		end)
	end
end

local function configureSlot(slot, config, width, height, iconSize, pixel, display, style, borderOutset)
	local filters = { includeSpellIDs = config.includeSpellIDs }
	local signature = table.concat({ config.signature, width, height, iconSize, pixel, display, borderOutset }, ":")
	if slot.signature ~= signature then
		slot.frame:Hide()
		local options = {
			width = width,
			height = height,
			paddingLeft = borderOutset, paddingRight = borderOutset,
			paddingTop = borderOutset, paddingBottom = borderOutset,
			unit = config.unit,
			filterString = config.filterString,
			candidateFilters = filters,
			frameLevel = slot.frame:GetFrameLevel(),
		}
		if not slot.gate then
			options.enabled = false
			slot.gate = AuraCompat:CreateInverseAuraClip(slot.frame, slot.frame, options)
			if not slot.gate then return false end
			slot.missing = makeSlotVisual(slot.gate.content, slot.frame, true)
		elseif not slot.gate:Configure(options) then
			releaseSlot(slot)
			return false
		end
		-- Both clips follow the same native width change. The inverse clip starts
		-- over the slot; the active clip starts one slot-width to its left.
		-- Only the clips move. Both sets of visuals stay anchored to the slot.
		slot.presentClip:ClearAllPoints()
		local clipWidth = width + 2 * borderOutset
		slot.presentClip:SetSize(clipWidth, height + 2 * borderOutset)
		slot.presentClip:SetPoint("TOPLEFT", slot.gate.clip, "TOPLEFT", -clipWidth, 0)
		if not slot.gate:SetEnabled(true) then
			releaseSlot(slot)
			return false
		end
		applySlotGeometry(slot.present, iconSize, height, pixel)
		applySlotGeometry(slot.missing, iconSize, height, pixel)
		slot.presentClip:SetShown(display ~= "MISSING")
		slot.missing.frame:SetShown(display ~= "ACTIVE")
		slot.signature = signature
	end
	local empty = style.emptySlot ~= "DESATURATED"
	slot.present.icon:SetTexture(config.icon)
	slot.missing.icon:SetTexture(config.icon)
	slot.missing.icon:SetShown(not empty)
	slot.missing.empty:SetShown(empty)
	for _, visual in ipairs({ slot.present, slot.missing }) do
		visual.label:SetText(config.label)
		applyFont(visual.label, style.font, style.fontSize, style.fontStyle)
		applyBorder(visual.border, visual.icon, style, "iconBorder", false, FALLBACK.iconBorder, iconSize)
	end
	slot.present.label:SetTextColor(color(style, "text", FALLBACK.text))
	slot.missing.label:SetTextColor(color(style, "missingText", FALLBACK.missingText))
	configureSwipe(slot, config, style)
	slot.frame:Show()
	return true
end

local function animate(state, progress)
	local options = state.animation
	local viewport = state.viewport
	local direction = OPEN_DIRECTIONS[state.direction]
	local margin, pixel = state.borderMargin, state.pixel
	local width, height = state.visibleWidth + 2 * margin, state.visibleHeight + 2 * margin
	local eased = progress * progress * (3 - 2 * progress)
	state.progress = progress
	if options == "REVEAL" then
		if direction.x == 0 then
			height = math.max(pixel, snap(height * eased, pixel))
		else
			width = math.max(pixel, snap(width * eased, pixel))
		end
		viewport:SetAlpha(math.min(1, eased * 2))
	else
		viewport:SetAlpha(options == "NONE" and 1 or eased)
	end
	viewport:SetSize(width, height)

	local shift = options == "SLIDE" and snap(SLIDE_DISTANCE * (1 - eased), pixel) or 0
	local x = (direction.x < 0 and -margin or margin) - direction.x * shift
	local y = (direction.y > 0 and margin or -margin) - direction.y * shift
	local edge = direction.edge
	if state.bodyPoint ~= edge or state.bodyX ~= x or state.bodyY ~= y then
		state.bodyPoint, state.bodyX, state.bodyY = edge, x, y
		state.body:ClearAllPoints()
		state.body:SetPoint(edge, viewport, edge, x, y)
	end
end

local function finishTransition(state, target)
	state.viewport:SetScript("OnUpdate", nil)
	animate(state, target)
	if target == 0 then
		state.bridge:Hide()
		state.hitbox:Hide()
		state.viewport:Hide()
	end
end

local function transition(state, open, immediate)
	state.target = open and 1 or 0
	if state.target == 1 then
		state.viewport:Show()
		state.hitbox:Show()
		state.bridge:SetShown(state.gap > 0)
	end
	if immediate or state.animation == "NONE" or state.target == state.progress then
		finishTransition(state, state.target)
		return
	end
	state.viewport:SetScript("OnUpdate", state.onUpdate)
end

local function setScrollOffsets(state, x, y)
	state.scrollX = math.max(0, math.min(snap(x, state.pixel), state.width - state.visibleWidth))
	state.scrollY = math.max(0, math.min(snap(y, state.pixel), state.height - state.visibleHeight))
	state.scroll:SetHorizontalScroll(state.scrollX)
	state.scroll:SetVerticalScroll(state.scrollY)
end

local function getLauncherRect(launcher)
	local restricted = launcher.IsAnchoringRestricted and launcher:IsAnchoringRestricted()
	if AuraCompat:IsSecretValue(restricted) or restricted then return end
	local left, bottom, width, height = launcher:GetRect()
	for _, value in ipairs({ left, bottom, width, height }) do
		if AuraCompat:IsSecretValue(value) or type(value) ~= "number" then return end
	end
	if left and bottom and width and height then return left, bottom, left + width, bottom + height end
end

local function resolveDirection(preferred, rooms, width, height)
	if OPEN_DIRECTIONS[preferred] then return preferred end
	for _, key in ipairs(AUTO_DIRECTIONS) do
		local required = OPEN_DIRECTIONS[key].x == 0 and height or width
		if rooms[key] >= required then return key end
	end
	-- The taller vertical side keeps the full column layout and can scroll.
	return rooms.UP > rooms.DOWN and "UP" or "DOWN"
end

local function placeDrawer(state)
	local launcher = state.launcher
	local screenWidth, screenHeight = UIParent:GetSize()
	local margin, gap, pixel = state.borderMargin, state.gap, state.pixel
	local left, bottom, right, top = getLauncherRect(launcher)
	local rooms
	if left then
		rooms = { LEFT = left - gap, RIGHT = screenWidth - right - gap, DOWN = bottom - gap, UP = screenHeight - top - gap }
	else
		rooms = { LEFT = screenWidth / 2, RIGHT = screenWidth / 2, DOWN = screenHeight / 2, UP = screenHeight / 2 }
	end
	state.direction = resolveDirection(state.preferredDirection, rooms, state.width, state.height)
	local direction = OPEN_DIRECTIONS[state.direction]
	local vertical = direction.x == 0
	local room = rooms[state.direction]
	local minSize = SLOT_HEIGHT + 2 * PADDING
	local width = math.min(state.width, snap(math.max(minSize, vertical and screenWidth or room), pixel))
	local height = math.min(state.height, snap(math.max(minSize, vertical and room or screenHeight), pixel))
	local viewWidth, viewHeight = width + 2 * margin, height + 2 * margin
	local x, y = direction.x * gap, direction.y * gap
	if left then
		if vertical then
			x = math.max(0, math.min(right - width, screenWidth - width)) - left
		else
			y = math.max(height, math.min(top, screenHeight)) - top
		end
	end

	-- The viewport includes the border; keep the content anchored at the configured gap.
	local viewportX = snap(x, pixel) + (direction.x < 0 and margin or -margin)
	local viewportY = snap(y, pixel) + (direction.y > 0 and -margin or margin)
	state.visibleWidth, state.visibleHeight = width, height
	state.body:SetSize(width, height)
	applyBorder(state.panelBorder, state.body, state.style, "border", true, FALLBACK.border, math.min(width, height))
	for _, frame in ipairs({ state.viewport, state.hitbox }) do
		frame:ClearAllPoints()
		frame:SetPoint(direction.edge, launcher, direction.from, viewportX, viewportY)
	end
	state.hitbox:SetSize(viewWidth, viewHeight)
	state.bridge:ClearAllPoints()
	state.bridge:SetPoint(direction.edge, launcher, direction.from)
	state.bridge:SetSize(vertical and state.launcherSize or math.max(pixel, gap), vertical and math.max(pixel, gap) or state.launcherSize)
	state.bridge:SetShown(state.target == 1 and gap > 0)
	state.hitbox:EnableMouseWheel(width < state.width or height < state.height)
	setScrollOffsets(state, state.scrollX, state.scrollY)
	animate(state, state.progress)
end

local function isHovering(frame)
	local over = addon.functions.MouseIsOver(frame)
	return not AuraCompat:IsSecretValue(over) and over
end

local function requestClose(state)
	state.closeToken = state.closeToken + 1
	local token = state.closeToken
	C_Timer.After(0.09, function()
		if state.closeToken ~= token or not state.active or state.preview then return end
		if isHovering(state.launcher) or isHovering(state.hitbox) or (state.bridge:IsShown() and isHovering(state.bridge)) then return end
		transition(state, false)
	end)
end

local function enableHover(frame, enabled)
	frame:EnableMouseMotion(enabled)
	if frame.SetMouseClickEnabled then frame:SetMouseClickEnabled(false) end
end

local function makeState(frame)
	local state = { slots = {}, progress = 0, target = 0, closeToken = 0, scrollX = 0, scrollY = 0 }
	state.launcher = CreateFrame("Frame", nil, frame)
	state.launcher:SetAllPoints(frame)
	state.launcher.border = makeBorder(state.launcher)
	enableHover(state.launcher, true)
	state.launcher.icon = makeTexture(state.launcher)
	state.launcher.title = makeText(state.launcher, "GameFontNormal")
	state.launcher.title:SetPoint("LEFT", state.launcher, "RIGHT", 6, 0)
	state.launcher.title:SetWidth(160)
	state.launcher.title.hoverFont = { state.launcher.title:GetFont() }
	state.measureLabel = makeText(state.launcher, "GameFontNormalSmall")
	state.measureLabel.hoverFont = { state.measureLabel:GetFont() }
	state.measureLabel:Hide()

	state.viewport = CreateFrame("Frame", nil, frame)
	state.viewport:SetClipsChildren(true)
	state.viewport:Hide()
	state.body = CreateFrame("Frame", nil, state.viewport)
	state.panelBorder = makeBorder(state.body)
	local scroll = CreateFrame("ScrollFrame", nil, state.body)
	scroll:SetAllPoints()
	state.scroll = scroll
	state.grid = CreateFrame("Frame", nil, scroll)
	scroll:SetScrollChild(state.grid)
	state.hitbox = CreateFrame("Frame", nil, frame)
	state.hitbox:Hide()
	enableHover(state.hitbox, true)
	state.bridge = CreateFrame("Frame", nil, frame)
	state.bridge:Hide()
	enableHover(state.bridge, true)
	state.hitbox:SetScript("OnMouseWheel", function(_, delta)
		local offset = delta * SLOT_HEIGHT
		if state.width > state.visibleWidth and (state.height == state.visibleHeight or IsShiftKeyDown()) then
			setScrollOffsets(state, state.scrollX - offset, state.scrollY)
		else
			setScrollOffsets(state, state.scrollX, state.scrollY - offset)
		end
	end)

	local function enter()
		state.closeToken = state.closeToken + 1
		if state.active and state.target == 0 and frame:GetAlpha() > 0 then
			if state.progress == 0 then placeDrawer(state) end
			transition(state, true)
		end
	end
	local function leave() requestClose(state) end
	state.launcher:SetScript("OnEnter", enter)
	state.launcher:SetScript("OnLeave", leave)
	state.hitbox:SetScript("OnEnter", enter)
	state.hitbox:SetScript("OnLeave", leave)
	state.bridge:SetScript("OnEnter", enter)
	state.bridge:SetScript("OnLeave", leave)
	state.onUpdate = function(_, elapsed)
		local opening = state.target == 1
		local step = elapsed / (opening and OPEN_DURATION or CLOSE_DURATION)
		local progress = opening and math.min(1, state.progress + step) or math.max(0, state.progress - step)
		if progress == state.target then
			finishTransition(state, progress)
		else
			animate(state, progress)
		end
	end
	frame:HookScript("OnHide", function()
		state.closeToken = state.closeToken + 1
		if state.active and state.visibleHeight then transition(state, false, true) end
	end)

	return state
end

function HoverBuffPanel:ApplySize(frame, layout)
	local size = PixelUtil.Snap(Helper.ClampInt(layout.iconSize, 12, 128, Helper.PANEL_LAYOUT_DEFAULTS.iconSize), frame)
	if frame._eqolCalculatedPanelWidth ~= size or not frame._eqolHoverBuffSizeApplied then
		frame:SetSize(size, size)
		frame._eqolHoverBuffSizeApplied = true
	end
	frame._eqolCalculatedPanelWidth = size
	return size
end

local function getConfigs(panel, preview)
	local configs = {}
	local native = CooldownPanels.AuraContainers
	for _, entryId in ipairs(panel.order or {}) do
		local entry = panel.entries[entryId]
		if entry and (preview or CooldownPanels.EntryAllowsRuntimeFilters(entry)) then
			local label = textValue(entry.hoverBuffLabel)
			if entry.hoverBuffShowLabel == false then
				label = ""
			elseif label == "" then
				label = textValue(CooldownPanels:GetEntryName(entry))
			end
			local config = {
				entryId = entryId,
				customIcon = iconValue(entry.hoverBuffIcon),
				icon = iconValue(entry.hoverBuffIcon, CooldownPanels:GetEntryIcon(entry) or ICON),
				label = label,
			}
			if native and entry.type == "CDM_AURA" then
				local ids, signature = native:GetHoverBuffSpellData(entry)
				local unit = Helper.NormalizeAuraUnit(entry.auraUnit)
				if ids and next(ids) and not Helper.IsAuraGroupUnit(unit) then
					config.unit = unit
					config.filterString = native:ResolveEntryFilterString(entry, panel.layout, unit, unit)
					config.includeSpellIDs, config.signature = ids, signature .. ":" .. unit .. ":" .. config.filterString
				end
			end
			configs[#configs + 1] = config
			if #configs == LIMIT then break end
		end
	end
	return configs
end

local function configureOrdinarySlot(slot, config, width, height, iconSize, pixel, style, borderOutset)
	if slot.signature then releaseSlot(slot) end
	slot.presentClip:ClearAllPoints()
	slot.presentClip:SetPoint("TOPLEFT", slot.frame, "TOPLEFT", -borderOutset, borderOutset)
	slot.presentClip:SetSize(width + 2 * borderOutset, height + 2 * borderOutset)
	slot.presentClip:Show()
	applySlotGeometry(slot.present, iconSize, height, pixel)
	slot.present.icon:SetAlpha(0)
	slot.present.label:SetText(config.label)
	applyFont(slot.present.label, style.font, style.fontSize, style.fontStyle)
	slot.present.label:SetTextColor(color(style, "text", FALLBACK.text))
	applyBorder(slot.present.border, slot.present.icon, style, "iconBorder", false, FALLBACK.iconBorder, iconSize)
	slot.frame:Show()
end

function HoverBuffPanel:MountEntryIcon(state, icon, entryId)
	local slot = state.ordinarySlots[entryId]
	if not slot then return end
	local host = slot.present.frame
	local anchor = icon.slotAnchor
	if anchor:GetParent() ~= host then anchor:SetParent(host) end
	anchor:ClearAllPoints()
	anchor:SetAllPoints(slot.present.icon)
	if icon:GetParent() ~= host then icon:SetParent(host) end
	icon:ClearAllPoints()
	icon:SetAllPoints(anchor)
	self:ApplyEntryStyle(state, icon, entryId)
end

function HoverBuffPanel:ApplyEntryStyle(state, icon, entryId)
	local slot = state.ordinarySlots[entryId]
	if not slot then return end
	if slot.customIcon then icon.texture:SetTexture(slot.customIcon) end
	local style = state.style
	if style.swipeEnabled ~= nil then icon.cooldown:SetDrawSwipe(style.swipeEnabled) end
	if style.swipeColor then icon.cooldown:SetSwipeColor(color(style, "swipe", FALLBACK.swipe)) end
end

function HoverBuffPanel:RestoreEntryIcons(frame)
	for _, icon in ipairs(frame.icons) do
		if icon:GetParent() ~= frame then icon:SetParent(frame) end
		if icon.slotAnchor:GetParent() ~= frame then icon.slotAnchor:SetParent(frame) end
	end
end

function HoverBuffPanel:Configure(frame, panel, preview)
	local layout = panel.layout
	local style = type(layout.hoverBuffStyle) == "table" and layout.hoverBuffStyle or {}
	local configs = getConfigs(panel, preview)
	if #configs == 0 and not preview then self:Deactivate(frame) return 0 end
	local state = frame._eqolHoverBuffPanel
	if not state then
		state = makeState(frame)
		frame._eqolHoverBuffPanel = state
	end
	local wasPreview = state.preview
	state.active, state.preview = true, preview
	state.style = style
	state.ordinarySlots = state.ordinarySlots or {}
	wipe(state.ordinarySlots)
	local auraConfigs = {}
	local pixel = PixelUtil.OnePixel(frame)
	state.pixel = pixel
	state.gap = snap(Helper.ClampInt(layout.hoverBuffGap, 0, 128, DEFAULT_GAP), pixel)
	state.preferredDirection = layout.hoverBuffDirection
	state.launcherSize = frame._eqolCalculatedPanelWidth or Helper.PANEL_LAYOUT_DEFAULTS.iconSize
	state.borderMargin = style.borderEnabled ~= false and snap(math.max(0, Helper.ClampInt(style.borderOffset, 0, self.borderLimit, 0)), pixel) or 0
	state.animation = VALID_ANIMATIONS[layout.hoverBuffAnimation] and layout.hoverBuffAnimation or "REVEAL"
	PixelUtil.SetInside(state.launcher.icon, state.launcher, 2, 2)
	state.launcher.icon:SetTexture(iconValue(layout.hoverBuffIcon, ICON))
	state.launcher.title:SetText(textValue(layout.hoverBuffTitle))
	enableHover(state.launcher, true)
	if state.launcher.SetMouseClickEnabled then state.launcher:SetMouseClickEnabled(true) end
	state.launcher:Show()
	if style.titleStyleSeparated then
		applyFont(state.launcher.title, style.titleFont, style.titleFontSize, style.titleFontStyle)
		state.launcher.title:SetTextColor(color(style, "titleText", FALLBACK.titleText))
	else
		applyFont(state.launcher.title, style.font, style.fontSize, style.fontStyle)
		state.launcher.title:SetTextColor(color(style, "text", FALLBACK.text))
	end
	applySurface(state.launcher, style, style.launcherBackgroundSeparated and "launcherBackground" or "background", FALLBACK.launcherBackground)
	applySurface(state.body, style, "background", FALLBACK.background)
	applyBorder(state.launcher.border, state.launcher, style, "border", true, FALLBACK.launcherBorder, state.launcherSize)
	state.viewport:SetFrameLevel(frame:GetFrameLevel() + 8)
	state.hitbox:SetFrameLevel(frame:GetFrameLevel() + 20)
	state.launcher:SetFrameLevel(frame:GetFrameLevel() + 1)

	local columns = math.min(math.max(1, #configs), Helper.ClampInt(layout.hoverBuffPerRow, 1, 12, 2))
	local configuredSpacing = Helper.ClampInt(layout.hoverBuffSpacing, 0, 18, 4)
	local spacing = snap(configuredSpacing, pixel)
	local rowSpacing = snap(Helper.ClampInt(style.rowSpacing, 0, 32, configuredSpacing), pixel)
	local padding = snap(PADDING, pixel)
	local display = layout.hoverBuffDisplay
	local fontSize = style.fontSize and Helper.ClampInt(style.fontSize, 6, 28, 12)
	local borderOutset = style.iconBorderEnabled and snap(Helper.ClampInt(style.iconBorderOffset, 0, self.borderLimit, 0), pixel) or 0
	local configuredIconSize = Helper.ClampInt(layout.hoverBuffEntryIconSize, ENTRY_ICON_SIZE.min, ENTRY_ICON_SIZE.max, ENTRY_ICON_SIZE.default)
	local iconSize = snap(configuredIconSize, pixel)
	local slotHeight = math.max(snap(SLOT_HEIGHT, pixel), snap(fontSize and fontSize + 6 or 0, pixel),
		snap(configuredIconSize + SLOT_HEIGHT - ENTRY_ICON_SIZE.default, pixel))
	local labelWidth = 0
	local measureLabel = state.measureLabel
	applyFont(measureLabel, style.font, style.fontSize, style.fontStyle)
	for _, config in ipairs(configs) do
		if config.label ~= "" then
			measureLabel:SetText(config.label)
			local width = measureLabel.GetUnboundedStringWidth and measureLabel:GetUnboundedStringWidth() or measureLabel:GetStringWidth()
			labelWidth = math.max(labelWidth, width or 0)
		end
	end
	local cellWidth = snap(configuredIconSize + 8, pixel)
	if labelWidth > 0 then
		local textWidth = math.ceil((labelWidth + 2 * pixel) / pixel) * pixel
		cellWidth = math.max(snap(LABEL_CELL_WIDTH, pixel), cellWidth + snap(6, pixel) + textWidth)
	end
	for index, config in ipairs(configs) do
		local slot = state.slots[index]
		if not slot then
			slot = makeSlot(state.grid)
			state.slots[index] = slot
		end
		slot.frame:ClearAllPoints()
		slot.frame:SetPoint("TOPLEFT", state.grid, "TOPLEFT",
			padding + ((index - 1) % columns) * (cellWidth + spacing),
			-padding - math.floor((index - 1) / columns) * (slotHeight + rowSpacing))
		slot.frame:SetSize(cellWidth, slotHeight)
		if config.includeSpellIDs then
			slot.present.icon:SetAlpha(1)
			configureSlot(slot, config, cellWidth, slotHeight, iconSize, pixel, display or "BOTH", style, borderOutset)
			auraConfigs[#auraConfigs + 1] = config
		else
			configureOrdinarySlot(slot, config, cellWidth, slotHeight, iconSize, pixel, style, borderOutset)
			slot.customIcon = config.customIcon
			state.ordinarySlots[config.entryId] = slot
		end
	end
	for i = #configs + 1, #state.slots do
		if state.slots[i].frame:IsShown() then releaseSlot(state.slots[i]) end
	end

	local rows = math.max(1, math.ceil(#configs / columns))
	state.width = padding * 2 + columns * cellWidth + (columns - 1) * spacing
	state.height = padding * 2 + rows * slotHeight + (rows - 1) * rowSpacing
	state.grid:SetSize(state.width, state.height)

	local count = CooldownPanels.HoverBuffCount
	if count then
		if layout.hoverBuffCount ~= false then
			count:Configure(state.launcher, auraConfigs, {
				font = Helper.ResolveFontPath(style.countFont or addon.functions.GetGlobalFontConfigKey()),
				fontSize = Helper.ClampInt(style.countFontSize, 6, 40, 12),
				fontFlags = Helper.NormalizeFontStyle(style.countFontStyle or addon.functions.GetGlobalFontStyleConfigKey()),
				point = Helper.NormalizeAnchor(style.countAnchor, "BOTTOMRIGHT"),
				x = Helper.ClampInt(style.countX, -64, 64, -1),
				y = Helper.ClampInt(style.countY, -64, 64, 1),
				color = { color(style, "count", FALLBACK.count) },
			})
		else
			count:Release(state.launcher)
		end
	end

	if preview or state.viewport:IsShown() then placeDrawer(state) end
	if preview then
		transition(state, true, true)
	elseif wasPreview then
		transition(state, isHovering(state.launcher), true)
	end
	return #configs
end

function HoverBuffPanel:Deactivate(frame)
	local state = frame and frame._eqolHoverBuffPanel
	if not state or not state.active then return end
	state.active, state.preview = false, nil
	state.closeToken = state.closeToken + 1
	if state.visibleHeight then transition(state, false, true) end
	state.launcher:Hide()
	for _, slot in ipairs(state.slots) do
		if slot.frame:IsShown() then releaseSlot(slot) end
	end
	if CooldownPanels.HoverBuffCount then CooldownPanels.HoverBuffCount:Release(state.launcher) end
end
