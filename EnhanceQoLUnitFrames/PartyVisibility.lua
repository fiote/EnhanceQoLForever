local _, addon = ...
addon = _G.EnhanceQoL or addon
local UF = addon.Aura.UF
local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL")
local Visibility = {}
UF.PartyVisibility = Visibility

local function strength(cfg)
	return math.max(0, math.min(1, tonumber(cfg.visibilityFadeStrength) or 1))
end

function Visibility.CreateParent(parent)
	if not Visibility.parent then
		local frame = CreateFrame("Frame", "EQOLUFPartyVisibility", parent)
		frame:SetSize(1, 1)
		frame:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT")
		Visibility.parent = frame
		Visibility.state = { frame = frame }
	end
	return Visibility.parent
end

function Visibility.Apply(header, cfg, inEdit)
	local frame = Visibility.parent
	if not frame or (InCombatLockdown and InCombatLockdown()) then return end
	local functions = addon.functions
	local config = not inEdit and cfg.enabled and not header._eqolForceShow and functions.NormalizeUnitFrameVisibilityConfig(nil, cfg.visibility, { skipSave = true, ignoreOverride = true }) or nil
	local manual = config and functions.VisibilityConfigUsesManualEvaluation(config)
	if manual then
		UF.ClearEqolVisibilityDriver(Visibility.state, true)
		local hoverFrames = {}
		UF.GroupFrames.ForEachVisualChild(header, function(child) hoverFrames[#hoverFrames + 1] = child end)
		functions.ApplyFrameVisibilityConfig(frame:GetName(), {
			unitToken = "player",
			hoverFrames = hoverFrames,
			getInactiveAlpha = function() return 1 - strength(cfg) end,
		}, config, { noStateDriver = true })
		Visibility.manualActive = true
	else
		if Visibility.manualActive then
			functions.ApplyFrameVisibilityConfig(frame:GetName(), { unitToken = "player" }, nil, { noStateDriver = true })
			Visibility.manualActive = nil
		end
		local alpha = 1 - strength(cfg)
		local inactive = alpha <= 0 and "hide" or (alpha >= 1 and "show" or "fade")
		local expression = config and functions.BuildUnitFrameDriverExpression(config, { inactiveState = inactive })
		if expression then UF.ApplyEqolVisibilityDriver(Visibility.state, expression, alpha) else UF.ClearEqolVisibilityDriver(Visibility.state, true) end
	end
end

function Visibility.ApplyLayout(cfg, data)
	if data.visibility ~= nil then cfg.visibility = CopyTable(data.visibility) end
	if data.visibilityFadeStrength ~= nil then cfg.visibilityFadeStrength = strength(data) end
end

function Visibility.ConfigureSettings(settings, kind, editModeId, getCfg)
	if kind ~= "party" then return end
	local types = addon.EditModeLib.SettingType
	local options = UF.ui and UF.ui.getVisibilityRuleOptions and UF.ui.getVisibilityRuleOptions("player") or {}
	local function get()
		return addon.functions.NormalizeUnitFrameVisibilityConfig(nil, getCfg(kind).visibility, { skipSave = true, ignoreOverride = true }) or {}
	end
	local function save(field, value)
		getCfg(kind)[field] = value
		if addon.EditMode and addon.EditMode.SetValue then addon.EditMode:SetValue(editModeId, field, value, nil, true) end
		UF.GroupFrames:ApplyHeaderAttributes(kind)
	end
	local function set(selection)
		local selected = {}
		for _, option in ipairs(options) do
			if selection and selection[option.value] then selected[option.value] = true end
		end
		addon.functions.NormalizeVisibilityTargetRules(selected)
		save("visibility", selected)
	end
	local rows = {
		{
			name = L["Show when"], kind = types.MultiDropdown, field = "visibility", navigationField = "visibility", parentId = "frame",
			height = 200, hideSummary = true, refreshOnSelect = false, values = options,
			get = get, set = function(_, selection) set(selection) end,
			isSelected = function(_, key) return get()[key] == true end,
			setSelected = function(_, key, enabled)
				local selection = get()
				if key == "ALWAYS_HIDDEN" and enabled then selection = { ALWAYS_HIDDEN = true }
				elseif enabled then selection[key], selection.ALWAYS_HIDDEN = true, nil
				else selection[key] = nil end
				addon.functions.NormalizeVisibilityTargetRules(selection, key)
				set(selection)
			end,
			navigationReset = function() set({}) end,
		},
		{
			name = L["Fade amount"], kind = types.Slider, field = "visibilityFadeStrength", navigationField = "visibilityFadeStrength", parentId = "frame",
			minValue = 0, maxValue = 100, valueStep = 1, allowInput = true, default = 100,
			get = function() return math.floor(strength(getCfg(kind)) * 100 + 0.5) end,
			set = function(_, value) save("visibilityFadeStrength", math.max(0, math.min(100, tonumber(value) or 100)) / 100) end,
			formatter = function(value) return tostring(value) .. "%" end,
			navigationReset = function() save("visibilityFadeStrength", 1) end,
		},
	}
	for index, data in ipairs(settings) do
		if data.id == "frame" then
			for offset, row in ipairs(rows) do table.insert(settings, index + offset, row) end
			break
		end
	end
end
