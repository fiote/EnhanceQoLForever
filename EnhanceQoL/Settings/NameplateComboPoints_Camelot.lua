local _, addon = ...
if not (addon.variables.isForever and not addon.variables.isTBC) then return end
local class = addon.variables.unitClass or select(2, UnitClass("player"))
if class ~= "ROGUE" and class ~= "DRUID" then return end

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL")
local M = { active = {}, frames = setmetatable({}, { __mode = "k" }), revision = 0 }
addon.NameplateComboPoints = M
M.defaults = { nameplateComboPoints = false, nameplateComboPointsAnchor = "TOP", nameplateComboPointsScale = 1, nameplateComboPointsSpacing = 4, nameplateComboPointsX = 0, nameplateComboPointsY = 12 }
M.visuals = {
	ROGUE = { template = "EQOLTargetComboRogueTemplate", active = "BGActive", inactive = "BGInactive", icon = "IconUncharged", slash = "SlashFBUncharged", effects = { "BGGlow", "FXUncharged", "FrameGlow" } },
	DRUID = { template = "EQOLTargetComboDruidTemplate", active = "BG_Active", inactive = "BG_Inactive", icon = "Point_Icon", slash = "FB_Slash", effects = { "BG_Glow", "Point_Deplete", "FX_RingGlow", "Smoke" } },
}

function M.Option(key)
	local value = addon.db and addon.db[key]
	if value == nil then return M.defaults[key] end
	return value
end

function M.ResetPoint(point, full)
	local visual = M.visual
	point.activateAnim:Stop()
	point.deactivateAnim:Stop()
	point[visual.active]:SetAlpha(full and 1 or 0)
	point[visual.inactive]:SetAlpha(full and 0 or 1)
	point[visual.icon]:SetAlpha(full and 1 or 0)
	point[visual.slash]:SetAlpha(0)
	for _, key in ipairs(visual.effects) do point[key]:SetAlpha(0) end
	point.full = full
end

function M.Hide(state)
	if not state then return end
	state.row:Hide()
	state.points = nil
	for _, point in ipairs(state.icons) do M.ResetPoint(point, false) end
end

function M.Layout(plate, state)
	local unitFrame = plate.UnitFrame
	local bar = unitFrame and (unitFrame.healthBar or (unitFrame.HealthBarsContainer and unitFrame.HealthBarsContainer.healthBar)) or plate
	local scale = math.max(0.25, math.min(3, tonumber(M.Option("nameplateComboPointsScale")) or 1))
	local spacing = math.max(0, math.min(20, tonumber(M.Option("nameplateComboPointsSpacing")) or 4))
	local bottom = M.Option("nameplateComboPointsAnchor") == "BOTTOM"
	state.row:ClearAllPoints()
	state.row:SetScale(scale)
	state.row:SetSize(100 + 4 * spacing, 20)
	state.row:SetPoint(bottom and "TOP" or "BOTTOM", bar, bottom and "BOTTOM" or "TOP", (tonumber(M.Option("nameplateComboPointsX")) or 0) / scale, (tonumber(M.Option("nameplateComboPointsY")) or 12) / scale)
	state.row:SetFrameLevel((unitFrame or plate):GetFrameLevel() + 8)
	for i, point in ipairs(state.icons) do
		point:ClearAllPoints()
		point:SetPoint("LEFT", state.row, "LEFT", (i - 1) * (20 + spacing), 0)
	end
	state.revision = M.revision
	state.bar = bar
end

function M.Ensure(plate)
	local state = M.frames[plate]
	if state then return state end
	local row = CreateFrame("Frame", nil, plate)
	row:EnableMouse(false)
	row:Hide()
	state = { row = row, icons = {} }
	M.frames[plate] = state
	for i = 1, 5 do
		local point = CreateFrame("Frame", nil, row, M.visual.template)
		point:EnableMouse(false)
		point.activateAnim:SetScript("OnFinished", function() M.ResetPoint(point, point.full) end)
		point.deactivateAnim:SetScript("OnFinished", function() M.ResetPoint(point, point.full) end)
		M.ResetPoint(point, false)
		state.icons[i] = point
	end
	return state
end

function M.Update(unit, plate)
	if plate == true then plate = C_NamePlate.GetNamePlateForUnit(unit) end
	if not plate or (plate.IsForbidden and plate:IsForbidden()) then return end
	M.active[unit] = plate
	local state = M.frames[plate]
	local enemy = UnitCanAttack("player", unit)
	if (issecretvalue and issecretvalue(enemy)) or not enemy then M.Hide(state); return end
	local points = 0
	if M.preview then
		points = 3
	elseif M.class == "ROGUE" or (M.class == "DRUID" and UnitPowerType("player") == Enum.PowerType.Energy) then
		points = GetComboPoints("player", unit)
		if issecretvalue and issecretvalue(points) then M.Hide(state); return end
	end
	if points <= 0 then
		if state and state.points ~= nil then M.Hide(state) end
		return
	end
	state = state or M.Ensure(plate)
	local unitFrame = plate.UnitFrame
	local bar = unitFrame and (unitFrame.healthBar or (unitFrame.HealthBarsContainer and unitFrame.HealthBarsContainer.healthBar)) or plate
	if state.revision ~= M.revision or state.bar ~= bar then M.Layout(plate, state) end
	if state.points ~= points then
		local animate = state.points ~= nil and not M.preview
		for i, point in ipairs(state.icons) do
			local full = i <= points
			if point.full ~= full then
				M.ResetPoint(point, full)
				if animate then
					if full then point[M.visual.slash]:SetAlpha(1); point.activateAnim:Play()
					else point.deactivateAnim:Play() end
				end
			end
		end
		state.points = points
	end
	state.row:Show()
end

-- Merge power/target/nameplate event bursts into a single pass; no polling.
function M.Schedule()
	if M.pending then return end
	M.pending = true
	C_Timer.After(0, function()
		M.pending = nil
		if not M.watching then return end
		if M.Option("nameplateComboPoints") ~= true then M.Refresh(); return end
		for unit, plate in pairs(M.active) do M.Update(unit, plate) end
	end)
end

function M.StopPreview()
	M.preview = false
	if M.previewTimer then M.previewTimer:Cancel(); M.previewTimer = nil end
end

function M.Refresh()
	M.class = addon.variables.unitClass or select(2, UnitClass("player"))
	M.visual = M.visuals[M.class] or M.visuals.ROGUE
	if M.Option("nameplateComboPoints") ~= true then M.StopPreview() end
	local enabled = M.Option("nameplateComboPoints") == true and M.visuals[M.class] ~= nil
	M.revision = M.revision + 1
	if M.watching ~= enabled then
		M.watcher:UnregisterAllEvents()
		-- The saved profile is assigned after settings registration.
		M.watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
		if enabled then
			for _, event in ipairs({ "PLAYER_TARGET_CHANGED", "COMBO_TARGET_CHANGED", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UPDATE_SHAPESHIFT_FORM", "PLAYER_REGEN_DISABLED" }) do M.watcher:RegisterEvent(event) end
			M.watcher:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
			M.watcher:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
		end
		M.watching = enabled
	end
	for _, state in pairs(M.frames) do M.Hide(state) end
	wipe(M.active)
	if enabled then
		for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
			if not (plate.IsForbidden and plate:IsForbidden()) then
				local unit = plate.GetUnit and plate:GetUnit() or plate.namePlateUnitToken
				if not (issecretvalue and issecretvalue(unit)) and type(unit) == "string" then M.active[unit] = plate end
			end
		end
		M.Schedule()
	end
end

function M.SetPreview(value)
	M.StopPreview()
	if value == true and M.Option("nameplateComboPoints") == true and M.visuals[class] and not InCombatLockdown() then
		M.preview = true
		M.previewTimer = C_Timer.NewTimer(120, function() M.StopPreview(); M.Refresh() end)
	end
	M.Refresh()
end

function M.RegisterSettings(category, section)
	for key, value in pairs(M.defaults) do addon.functions.InitDBValue(key, value) end
	addon.functions.SettingsCreateHeadline(category, L["nameplateComboPoints"], { parentSection = section, groupID = "nameplateComboPoints", order = 26 })
	local function option(key, label)
		return {
			var = key, text = label, newTagID = key, parentSection = section,
			default = M.defaults[key],
			get = function() return M.Option(key) end,
			set = function(value) addon.db[key] = value; M.Refresh() end,
			parentCheck = function() return M.Option("nameplateComboPoints") == true end,
		}
	end
	local toggle = option("nameplateComboPoints", L["nameplateComboPoints"])
	toggle.desc, toggle.parentCheck, toggle.func = L["nameplateComboPointsDesc"], nil, toggle.set
	addon.functions.SettingsCreateCheckbox(category, toggle)
	addon.functions.SettingsCreateCheckbox(category, {
		id = "nameplateComboPointsPreview", var = "nameplateComboPointsPreview", key = false, storage = false,
		text = L["nameplateComboPointsPreview"], desc = L["nameplateComboPointsPreviewDesc"], newTagID = "nameplateComboPointsPreview",
		parentSection = section, default = false, trackCustomized = false,
		get = function() return M.preview == true end, set = M.SetPreview, func = M.SetPreview,
		parentCheck = function() return M.Option("nameplateComboPoints") == true and not InCombatLockdown() end,
	})
	local anchor = option("nameplateComboPointsAnchor", L["Position"])
	anchor.list, anchor.order = { TOP = L["Top"], BOTTOM = L["Bottom"] }, { "TOP", "BOTTOM" }
	addon.functions.SettingsCreateDropdown(category, anchor)
	for _, entry in ipairs({
		{ "nameplateComboPointsScale", "Scale", 0.25, 3, 0.05 },
		{ "nameplateComboPointsSpacing", "Spacing", 0, 20, 1 },
		{ "nameplateComboPointsX", "Offset X", -200, 200, 1 },
		{ "nameplateComboPointsY", "Offset Y", -200, 200, 1 },
	}) do
		local data = option(entry[1], L[entry[2]])
		data.min, data.max, data.step = entry[3], entry[4], entry[5]
		addon.functions.SettingsCreateSlider(category, data)
	end
	M.Refresh()
end

M.watcher = CreateFrame("Frame")
M.watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
M.watcher:SetScript("OnEvent", function(_, event, unit, powerToken)
	if event == "PLAYER_ENTERING_WORLD" then M.StopPreview(); M.Refresh(); return end
	if not M.watching then return end
	if M.Option("nameplateComboPoints") ~= true then M.Refresh(); return end
	if event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT" then
		if unit ~= "player" or powerToken ~= "COMBO_POINTS" then return end
	elseif event == "NAME_PLATE_UNIT_ADDED" then
		M.active[unit] = true
	elseif event == "NAME_PLATE_UNIT_REMOVED" then
		local plate = M.active[unit]
		if plate and plate ~= true then M.Hide(M.frames[plate]) end
		M.active[unit] = nil
		return
	elseif event == "PLAYER_REGEN_DISABLED" then
		if M.preview then M.StopPreview(); M.Refresh() end
		return
	end
	M.Schedule()
end)
