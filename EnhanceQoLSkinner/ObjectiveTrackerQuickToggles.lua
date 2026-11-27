local addon = _G.EnhanceQoL
local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL")

local NPC_NAMES_SETTING = "PROXY_NPC_NAMES"
local QUEST_NPCS, ALL_NPCS = 1, 4
local npcModeLabels = {
	[1] = "NPC_NAMES_DROPDOWN_TRACKED",
	[2] = "NPC_NAMES_DROPDOWN_HOSTILE",
	[3] = "NPC_NAMES_DROPDOWN_INTERACTIVE",
	[4] = "NPC_NAMES_DROPDOWN_ALL",
	[5] = "NPC_NAMES_DROPDOWN_NONE",
}
local BUTTON_SIZE, BUTTON_GAP = 17, 3
local row, ticker

local function GetAddonSetting(key)
	local elements = addon.SettingsLayout and addon.SettingsLayout.elements
	return elements and elements[key] and elements[key].setting
end

local function ReadNumber(value)
	if issecretvalue and issecretvalue(value) then return nil end
	if type(value) == "number" then return value end
end

local function IsVisible(frame)
	local visible = frame and frame:IsVisible()
	return not (issecretvalue and issecretvalue(visible)) and visible == true
end

local function GetNPCNames()
	local mode = Settings and Settings.GetValue and ReadNumber(Settings.GetValue(NPC_NAMES_SETTING))
	if mode and npcModeLabels[mode] then return mode end
end

local function ToggleNPCNames(mode)
	local private = addon.functions.GetPrivateDB()
	if mode == QUEST_NPCS then
		local previous = private.questTrackerPreviousNPCNames
		Settings.SetValue(NPC_NAMES_SETTING, previous ~= QUEST_NPCS and npcModeLabels[previous] and previous or ALL_NPCS)
		if GetNPCNames() ~= QUEST_NPCS then private.questTrackerPreviousNPCNames = nil end
	else
		Settings.SetValue(NPC_NAMES_SETTING, QUEST_NPCS)
		if GetNPCNames() == QUEST_NPCS then private.questTrackerPreviousNPCNames = mode end
	end
end

local function SettingToggle(key, atlas, texture, isAvailable)
	return {
		atlas = atlas,
		texture = texture,
		label = function() return L[key] end,
		get = function()
			local setting = GetAddonSetting(key)
			if setting and (not isAvailable or isAvailable()) then return setting:GetValue() == true end
		end,
		toggle = function(enabled) GetAddonSetting(key):SetValue(not enabled) end,
	}
end

local toggles = {
	SettingToggle("questTrackerZoneFilter", "worldmap-icon-locateplayer", "Interface\\Icons\\INV_Misc_Map_01"),
	{
		atlas = "QuestNormal",
		texture = "Interface\\GossipFrame\\AvailableQuestIcon",
		label = function() return _G.SHOW_NPC_NAMES end,
		get = GetNPCNames,
		isActive = function(mode) return mode == QUEST_NPCS end,
		status = function(mode) return _G[npcModeLabels[mode]] end,
		toggle = ToggleNPCNames,
	},
	SettingToggle("showInGameNavigation", "Waypoint-MapPin-Tracked", "Interface\\Icons\\INV_Misc_Compass_01", addon.functions.IsNavigationWaypointAvailable),
}

local function ShowTooltip(button)
	local toggle = button.toggle
	local value = toggle.get()
	if value == nil then return end
	GameTooltip:SetOwner(button, "ANCHOR_BOTTOM")
	GameTooltip:SetText(toggle.label())
	GameTooltip:AddLine(toggle.status and toggle.status(value) or (value and _G.TEXT_ON_TARGET_ON_LABEL or L["Off"]), 1, 1, 1)
	GameTooltip:Show()
end

local UpdateRow

local function CreateRow()
	-- Keep the overlay out of the tracker's frame hierarchy and anchor graph.
	local frame = CreateFrame("Frame", nil, UIParent)
	frame:SetSize(1, BUTTON_SIZE)
	frame:Hide()
	frame.buttons = {}
	for index, toggle in ipairs(toggles) do
		local button = CreateFrame("Button", nil, frame)
		button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
		button.toggle = toggle
		local background = button:CreateTexture(nil, "BACKGROUND")
		background:SetAllPoints()
		background:SetColorTexture(0.12, 0.08, 0.04, 0.8)
		local highlight = button:CreateTexture(nil, "HIGHLIGHT")
		highlight:SetAllPoints()
		highlight:SetColorTexture(1, 0.76, 0.28, 0.22)
		local icon = button:CreateTexture(nil, "ARTWORK")
		icon:SetPoint("CENTER")
		icon:SetSize(BUTTON_SIZE - 3, BUTTON_SIZE - 3)
		if C_Texture.GetAtlasInfo(toggle.atlas) then
			icon:SetAtlas(toggle.atlas)
		else
			icon:SetTexture(toggle.texture)
		end
		button.icon = icon
		button:SetScript("OnEnter", ShowTooltip)
		button:SetScript("OnLeave", function(self)
			if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
		end)
		button:SetScript("OnHide", button:GetScript("OnLeave"))
		button:SetScript("OnClick", function(self)
			if InCombatLockdown() or not self:IsEnabled() then return end
			local value = toggle.get()
			if value == nil then return end
			toggle.toggle(value)
			UpdateRow()
			if GameTooltip:IsOwned(self) then ShowTooltip(self) end
		end)
		frame.buttons[index] = button
	end
	frame:RegisterEvent("PLAYER_REGEN_DISABLED")
	frame:RegisterEvent("PLAYER_REGEN_ENABLED")
	frame:SetScript("OnEvent", function(_, event)
		if ticker then UpdateRow(event) end
	end)
	return frame
end

UpdateRow = function(event)
	-- Combat lockdown can start after the PLAYER_REGEN_DISABLED handlers return.
	local inCombat = event == "PLAYER_REGEN_DISABLED" or InCombatLockdown() == true
	if row.inCombat ~= inCombat then
		for _, button in ipairs(row.buttons) do
			button:SetEnabled(not inCombat)
		end
		row.inCombat = inCombat
	end

	local tracker = _G.ObjectiveTrackerFrame
	local header = tracker and tracker.Header
	if not header or header:IsForbidden() or not IsVisible(header) or tracker:IsCollapsed() then return row:Hide() end
	if _G.EditModeManagerFrame and _G.EditModeManagerFrame:IsEditModeActive() then return row:Hide() end

	local text = header.Text
	local rightButton = IsVisible(header.FilterButton) and header.FilterButton or header.MinimizeButton
	if not IsVisible(rightButton) or not IsVisible(text) then return row:Hide() end
	local alpha = ReadNumber(header:GetEffectiveAlpha())
	local textLeft = ReadNumber(text:GetLeft())
	local textWidth = ReadNumber(text:GetStringWidth())
	local right = ReadNumber(rightButton:GetLeft())
	local _, buttonY = rightButton:GetCenter()
	local y = ReadNumber(buttonY)
	local scale = ReadNumber(header:GetEffectiveScale())
	local uiScale = ReadNumber(UIParent:GetEffectiveScale())
	if not (alpha and alpha > 0 and textLeft and textWidth and right and y and scale and uiScale) then return row:Hide() end

	local count = 0
	for _, button in ipairs(row.buttons) do
		local toggle = button.toggle
		local value = toggle.get()
		button:SetShown(value ~= nil)
		if value ~= nil then
			local active = toggle.isActive and toggle.isActive(value) or value == true
			if button.active ~= active then
				button.icon:SetDesaturated(not active)
				button.icon:SetAlpha(active and 1 or 0.58)
				button.active = active
			end
			if button.index ~= count then
				button:SetPoint("LEFT", row, "LEFT", count * (BUTTON_SIZE + BUTTON_GAP), 0)
				button.index = count
			end
			count = count + 1
		end
	end

	local width = count * (BUTTON_SIZE + BUTTON_GAP) - BUTTON_GAP
	local x = right - BUTTON_GAP - width
	if count == 0 or x < textLeft + textWidth + BUTTON_GAP then return row:Hide() end
	if row:GetWidth() ~= width then row:SetWidth(width) end
	if row:GetScale() ~= scale / uiScale then row:SetScale(scale / uiScale) end
	if row.x ~= x or row.y ~= y then
		row:SetPoint("LEFT", UIParent, "BOTTOMLEFT", x, y)
		row.x, row.y = x, y
	end
	local level, strata = ReadNumber(header:GetFrameLevel()), header:GetFrameStrata()
	if not (issecretvalue and issecretvalue(strata)) and row:GetFrameStrata() ~= strata then row:SetFrameStrata(strata) end
	if level and row:GetFrameLevel() ~= level + 2 then row:SetFrameLevel(level + 2) end
	local rowAlpha = inCombat and alpha * 0.55 or alpha
	if row:GetAlpha() ~= rowAlpha then row:SetAlpha(rowAlpha) end
	row:Show()
end

function addon.Skinner.functions.RefreshObjectiveTrackerQuickToggles()
	if addon.db.questTrackerQuickToggles then
		row = row or CreateRow()
		-- The tracker can move or change visibility without an addon event.
		ticker = ticker or C_Timer.NewTicker(0.15, UpdateRow)
		UpdateRow()
	elseif ticker then
		ticker:Cancel()
		ticker = nil
		row:Hide()
	end
end
