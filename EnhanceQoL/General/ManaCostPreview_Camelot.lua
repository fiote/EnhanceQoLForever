local _, addon = ...
local M = { colorDefault = { 1, 1, 1, 0.6 }, manaAtlas = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Mana" }
addon.ManaCostPreview = M
local MANA = Enum.PowerType.Mana
local live = {}
local events, activeCastID, castCost
local nextStrata = {
	BACKGROUND = "LOW",
	LOW = "MEDIUM",
	MEDIUM = "HIGH",
	HIGH = "DIALOG",
	DIALOG = "FULLSCREEN",
	FULLSCREEN = "FULLSCREEN_DIALOG",
	FULLSCREEN_DIALOG = "TOOLTIP",
}

local function isSecret(value) return issecretvalue and issecretvalue(value) end

function M.SyncLayers(bar)
	local state = bar._rbManaCostPreviewState
	if not state then return end
	local strata = bar:GetFrameStrata()
	local raised = nextStrata[strata] or strata
	local level = bar:GetFrameLevel()
	local text = state.text
	if text then
		local textStrata = bar._rbManaCostPreviewActive and raised or strata
		if text:GetFrameStrata() ~= textStrata then text:SetFrameStrata(textStrata) end
	end
	local overlay = bar._rbManaCostPreview
	if not overlay then return end
	local clip = overlay:GetParent()
	if clip:GetFrameStrata() ~= raised then clip:SetFrameStrata(raised) end
	if clip:GetFrameLevel() ~= level then clip:SetFrameLevel(level) end
	if overlay:GetFrameStrata() ~= raised then overlay:SetFrameStrata(raised) end
	local overlayLevel = math.min(level + 1, 65535)
	if overlay:GetFrameLevel() ~= overlayLevel then overlay:SetFrameLevel(overlayLevel) end
end

local function layout(bar, state)
	local overlay, geometry = bar._rbManaCostPreview, bar._rbManaCostGeometry
	local inner = state.inner
	overlay:GetParent():ClearAllPoints()
	overlay:GetParent():SetAllPoints(inner)
	geometry:ClearAllPoints()
	geometry:SetAllPoints(inner)
	geometry:SetOrientation(state.vertical and "VERTICAL" or "HORIZONTAL")
	geometry:SetReverseFill(state.reverse == true)
	local point = state.vertical and (state.reverse and "BOTTOMLEFT" or "TOPLEFT") or (state.reverse and "TOPLEFT" or "TOPRIGHT")
	overlay:ClearAllPoints()
	overlay:SetPoint(point, geometry:GetStatusBarTexture(), point)
	overlay:SetOrientation(state.vertical and "VERTICAL" or "HORIZONTAL")
	overlay:SetReverseFill(not state.reverse)
	overlay:SetSize(inner:GetSize())

	local tint = overlay:GetStatusBarTexture()
	local selected = state.cfg.texture
	local atlas, texture
	if selected == "DEFAULT" then
		atlas = M.manaAtlas
	elseif not selected or selected == "MATCH" then
		atlas, texture = state.atlas, state.asset
	else
		texture = selected
	end
	texture = atlas or texture or "Interface\\Buttons\\WHITE8x8"
	if overlay._rbPreviewTexture ~= texture then
		if atlas then tint:SetAtlas(atlas) else tint:SetTexture(texture) end
		overlay._rbPreviewTexture = texture
	end
	local color = type(state.cfg.color) == "table" and state.cfg.color or M.colorDefault
	tint:SetVertexColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 0.6)
end

local function hide(bar)
	if not bar._rbManaCostPreviewActive then return end
	bar._rbManaCostPreviewActive = nil
	bar._rbManaCostPreview:Hide()
	bar._rbManaCostGeometry:Hide()
	M.SyncLayers(bar)
end

local function show(bar, state, cost)
	if not bar._rbManaCostPreview then
		local clip = CreateFrame("Frame", nil, bar)
		clip:SetClipsChildren(true)
		clip:EnableMouse(false)
		local overlay = CreateFrame("StatusBar", nil, clip)
		overlay:EnableMouse(false)
		overlay:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
		local tint = overlay:GetStatusBarTexture()
		tint:SetDesaturated(true)
		tint:SetBlendMode("ADD")
		tint:SetSnapToPixelGrid(false)
		tint:SetTexelSnappingBias(0)
		local geometry = CreateFrame("StatusBar", nil, bar)
		geometry:EnableMouse(false)
		geometry:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
		geometry:SetStatusBarColor(1, 1, 1, 0)
		geometry:GetStatusBarTexture():SetSnapToPixelGrid(false)
		geometry:GetStatusBarTexture():SetTexelSnappingBias(0)
		bar._rbManaCostPreview = overlay
		bar._rbManaCostGeometry = geometry
		state.inner:HookScript("OnSizeChanged", function(_, width, height) overlay:SetSize(width, height) end)
	end
	layout(bar, state)
	local _, maxValue = bar:GetMinMaxValues()
	local geometry = bar._rbManaCostGeometry
	geometry:SetMinMaxValues(0, maxValue)
	geometry:SetValue(bar:GetValue())
	geometry:Show()
	bar._rbManaCostPreview:SetMinMaxValues(0, state.sample and 1 or maxValue)
	bar._rbManaCostPreview:SetValue(cost)
	bar._rbManaCostPreviewActive = true
	M.SyncLayers(bar)
	bar._rbManaCostPreview:Show()
end

function M.UpdateValue(bar, value, interpolation)
	if not bar._rbManaCostPreviewActive then return end
	if interpolation then
		bar._rbManaCostGeometry:SetValue(value, interpolation)
	else
		bar._rbManaCostGeometry:SetValue(value)
	end
end

local function getCost(spellID)
	if not isSecret(spellID) and spellID == nil then return end
	local costs = C_Spell.GetSpellPowerCost(spellID)
	if isSecret(costs) or not costs then return end
	for _, info in ipairs(costs) do
		if not isSecret(info) and not isSecret(info.type) and info.type == MANA then
			local aura = info.requiredAuraID
			local active = info.hasRequiredAura
			local needsAura = not isSecret(aura) and aura and aura ~= 0
			if not (needsAura and not isSecret(active) and active == false) then
				local cost = info.cost
				if isSecret(cost) or cost and cost > 0 then return cost end
				return
			end
		end
	end
end

local function updateCast(spellID, castBarID)
	activeCastID, castCost = castBarID, getCost(spellID)
	for bar, state in pairs(live) do
		if isSecret(castCost) or castCost then show(bar, state, castCost) else hide(bar) end
	end
end

local function onEvent(_, event, _, powerToken, spellID, castBarID, interruptedID)
	if event == "UNIT_MAXPOWER" then
		if powerToken ~= "MANA" then return end
		local maximum = UnitPowerMax("player", MANA)
		for bar in pairs(live) do
			if bar._rbManaCostPreviewActive then
				bar._rbManaCostGeometry:SetMinMaxValues(0, maximum)
				bar._rbManaCostPreview:SetMinMaxValues(0, maximum)
			end
		end
		return
	end
	if event == "UNIT_SPELLCAST_START" then updateCast(spellID, castBarID); return end
	if event == "UNIT_SPELLCAST_INTERRUPTED" then castBarID = interruptedID end
	if activeCastID and castBarID then
		if activeCastID ~= castBarID then return end
	elseif (isSecret(castCost) or castCost) and event ~= "PLAYER_DEAD" and event ~= "PLAYER_ENTERING_WORLD" then
		local currentSpell, currentCastID = select(9, UnitCastingInfo("player"))
		if activeCastID and currentCastID then
			if activeCastID == currentCastID then return end
		elseif isSecret(currentSpell) or currentSpell ~= nil then
			return
		end
	end
	activeCastID, castCost = nil, nil
	for bar in pairs(live) do hide(bar) end
end

local function updateEvents()
	if not next(live) then
		if events then events:UnregisterAllEvents() end
		activeCastID, castCost = nil, nil
		return
	end
	if not events then
		events = CreateFrame("Frame")
		events:SetScript("OnEvent", onEvent)
	end
	for _, event in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_MAXPOWER" }) do
		events:RegisterUnitEvent(event, "player")
	end
	events:RegisterEvent("PLAYER_DEAD")
	events:RegisterEvent("PLAYER_ENTERING_WORLD")
	updateCast(select(9, UnitCastingInfo("player")))
end

function M.Disable(bar)
	if not bar then return end
	hide(bar)
	if live[bar] then
		live[bar] = nil
		if not next(live) then updateEvents() end
	end
	bar._rbManaCostPreviewState = nil
end

function M.Configure(bar, cfg, state)
	if not bar then return end
	if type(cfg) ~= "table" or cfg.enabled ~= true then M.Disable(bar); return end
	state.cfg = cfg
	state.inner = state.inner or bar
	bar._rbManaCostPreviewState = state
	if state.sample then
		if live[bar] then
			live[bar] = nil
			if not next(live) then updateEvents() end
		end
		show(bar, state, 0.25)
	else
		local first = not next(live)
		live[bar] = state
		if first then
			updateEvents()
		elseif isSecret(castCost) or castCost then
			show(bar, state, castCost)
		else
			hide(bar)
		end
	end
end

function M.AddSettings(list, settingType, options)
	local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL")
	local function get(field, fallback)
		local cfg = options.read()
		if type(cfg) == "table" and cfg[field] ~= nil then return cfg[field] end
		return fallback
	end
	local function set(field, value)
		local cfg = options.write()
		if not cfg then return end
		cfg[field] = value
		options.refresh()
	end
	local function enabled() return options.enabled() and get("enabled", false) == true end
	local function add(field, data)
		data.parentId = options.parentId
		data.field = options.prefix .. field
		data.navigationField = data.field
		data.navigationDefaultVerified = true
		data.isShown = options.shown
		list[#list + 1] = data
	end
	add("Enabled", {
		name = L["manaCostPreview"], kind = settingType.Checkbox, default = false,
		get = function() return get("enabled", false) end,
		set = function(_, value)
			set("enabled", value == true)
			if options.refreshSettings then options.refreshSettings() end
		end,
		isEnabled = options.enabled,
	})
	local function selectTexture(_, value) set("texture", value) end
	add("Texture", {
		name = L["manaCostPreviewTexture"], kind = settingType.Dropdown, default = "MATCH", height = 180,
		get = function() return get("texture", "MATCH") end, set = selectTexture, isEnabled = enabled,
		generator = function(_, root)
			local function choice(key, label)
				root:CreateRadio(label, function() return get("texture", "MATCH") == key end,
					function() selectTexture(nil, key) end)
			end
			choice("MATCH", L["manaCostPreviewMatchTexture"])
			choice("DEFAULT", _G.DEFAULT)
			choice("Interface\\Buttons\\WHITE8x8", L["Solid"])
			local names = addon.functions.GetLSMMediaNames("statusbar") or {}
			local hash = addon.functions.GetLSMMediaHash("statusbar") or {}
			local seen = { ["Interface\\Buttons\\WHITE8x8"] = true }
			for _, name in ipairs(names) do
				local path = hash[name]
				if type(path) == "string" and path ~= "" and not seen[path] then
					seen[path] = true
					choice(path, name)
				end
			end
		end,
	})
	local function getColor()
		local c = get("color", M.colorDefault)
		if type(c) ~= "table" then c = M.colorDefault end
		return { r = c[1] or 1, g = c[2] or 1, b = c[3] or 1, a = c[4] or 0.6 }
	end
	local function setColor(_, value)
		set("color", { value.r or value[1] or 1, value.g or value[2] or 1, value.b or value[3] or 1, value.a or value[4] or 0.6 })
	end
	add("Color", {
		name = L["manaCostPreviewColor"], kind = settingType.Color, default = { r = 1, g = 1, b = 1, a = 0.6 },
		get = getColor, set = setColor, colorGet = getColor, colorSet = setColor, hasOpacity = true, isEnabled = enabled,
	})
end
