local addon = _G.EnhanceQoL
local L = addon.L
local M = {}
addon.Bags.SortMode = M

function M.RefreshSettings()
	for _, name in ipairs({ "RequestLayoutUpdate", "RequestBankLayoutUpdate" }) do
		local refresh = addon.Bags.functions[name]
		if refresh then refresh(true, true) end
	end
	if addon.RefreshSettingsFrame then addon.RefreshSettingsFrame("layout") end
end

function M.Label(mode, global)
	for _, option in ipairs(addon.GetCategorySortModeOptions(global)) do
		if option.value == (mode or "default") then return option.label end
	end
	return ""
end

function M.OpenMenu(owner, mode, global, title, onSelect)
	if not MenuUtil or not MenuUtil.CreateContextMenu then return end
	local base, reverse = addon.SplitCategorySortMode(mode or "default")
	MenuUtil.CreateContextMenu(owner, function(_, root)
		if title then root:CreateTitle(title) end
		local direction
		for _, option in ipairs(addon.GetCategorySortModeOptions(global, true)) do
			root:CreateRadio(option.label, function() return base == option.value end, function()
				local selected = option.value
				if selected ~= "default" and reverse then selected = selected .. "Reverse" end
				base, reverse = addon.SplitCategorySortMode(selected)
				if direction and direction.SetEnabled then direction:SetEnabled(base ~= "default") end
				onSelect(selected)
			end)
		end
		root:CreateDivider()
		direction = root:CreateCheckbox(L["bagCategorySortReverse"], function() return reverse end, function()
			if base ~= "default" then
				reverse = not reverse
				onSelect(reverse and base .. "Reverse" or base)
			end
		end)
		if direction and direction.SetEnabled then direction:SetEnabled(base ~= "default") end
	end)
end

function M.Menu(owner, categoryID)
	local mode = addon.GetGlobalCategorySortMode()
	local title = L["settingsGlobalCategorySortLabel"]
	if categoryID then
		for _, definition in ipairs(addon.GetCategorySectionDefinitions()) do
			if definition.id == categoryID then mode = definition.sortMode or "default"; title = definition.label; break end
		end
	end
	M.OpenMenu(owner, mode, not categoryID, title, function(selected)
		local changed
		if categoryID then changed = addon.SetCustomCategorySortMode(categoryID, selected)
		else changed = addon.SetGlobalCategorySortMode(selected) end
		if changed then M.RefreshSettings(); M.Refresh(M.frame) end
	end)
end

function M.Stop()
	M.active = false
	if M.panel then M.panel:Hide() end
	if M.button then M.button.Icon:SetVertexColor(0.78, 0.67, 0.43) end
	if addon.Bags.Toolbar then addon.Bags.Toolbar.RefreshAll() end
end

function M.Refresh(frame)
	if not frame or not frame.SortModeButton then return end
	local settings = addon.GetSettings()
	local available = settings.sortModeButton == true and settings.showCategories == true and not addon.GetOneBagMode()
	frame.SortModeButton:SetShown(available)
	if not available then M.Stop() end
	if M.panel then M.panel.Global:SetText(L["settingsGlobalCategorySortLabel"] .. ": " .. M.Label(addon.GetGlobalCategorySortMode(), true)) end
	if addon.Bags.Toolbar then addon.Bags.Toolbar.RefreshAll() end
end

function M.CreateButton(frame)
	M.frame = frame
	local button = CreateFrame("Button", nil, frame)
	button:SetSize(18, 18)
	button:SetHitRectInsets(-3, -3, -3, -3)
	button.Icon = CreateFrame("Frame", nil, button)
	button.Icon:SetAllPoints()
	button.Icon.parts = {}
	-- Compact up/down arrows keep the sorting control distinct from settings.
	for _, spec in ipairs({
		{ -4, 0, 2, 12, 0 }, { -5.5, 4.5, 6, 2, 45 }, { -2.5, 4.5, 6, 2, -45 },
		{ 4, 0, 2, 12, 0 }, { 2.5, -4.5, 6, 2, -45 }, { 5.5, -4.5, 6, 2, 45 },
	}) do
		local part = button.Icon:CreateTexture(nil, "ARTWORK")
		part:SetTexture("Interface\\Buttons\\WHITE8x8")
		part:SetSize(spec[3], spec[4])
		part:SetPoint("CENTER", button.Icon, "CENTER", spec[1], spec[2])
		part:SetRotation(math.rad(spec[5]))
		button.Icon.parts[#button.Icon.parts + 1] = part
	end
	button.Icon.SetVertexColor = function(self, r, g, b)
		for _, part in ipairs(self.parts) do part:SetVertexColor(r, g, b) end
	end
	button.Icon:SetVertexColor(0.78, 0.67, 0.43)
	button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(L["bagSortMode"])
		GameTooltip:AddLine(L["bagSortModeHint"], 1, 1, 1, true)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	button:SetScript("OnClick", function()
		if M.active then M.Stop(); return end
		M.active = true
		button.Icon:SetVertexColor(1, 0.82, 0)
		M.panel:Show()
		M.Refresh(frame)
	end)
	button:Hide()
	M.button = button
	local panel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	panel:SetSize(330, 102)
	panel:SetPoint("BOTTOMRIGHT", button, "TOPRIGHT", 0, 8)
	panel:SetClampedToScreen(true)
	panel:SetFrameStrata("DIALOG")
	panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	panel:SetBackdropColor(0.075, 0.055, 0.035, 0.98)
	panel:SetBackdropBorderColor(0.55, 0.43, 0.24, 1)
	panel:EnableMouse(true)
	local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	hint:SetPoint("TOPLEFT", 12, -10)
	hint:SetPoint("RIGHT", panel, "RIGHT", -12, 0)
	hint:SetJustifyH("LEFT")
	hint:SetText(L["bagSortModeHint"])
	hint:SetTextColor(0.83, 0.76, 0.61)
	local global = addon.Bags.SettingsNavigation.CreateButton("Button", nil, panel)
	global:GetNormalTexture():SetVertexColor(0.19, 0.14, 0.08, 1)
	global:GetHighlightTexture():SetVertexColor(0.55, 0.39, 0.16, 0.45)
	global:GetPushedTexture():SetVertexColor(0.12, 0.085, 0.04, 1)
	global:SetNormalFontObject(GameFontNormalSmall)
	global:SetHighlightFontObject(GameFontHighlightSmall)
	global:SetHeight(26)
	global:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -10)
	global:SetPoint("RIGHT", panel, "RIGHT", -12, 0)
	global:SetScript("OnClick", function(self) M.Menu(self) end)
	panel.Global = global
	panel:SetScript("OnShow", function() panel:SetHeight(36 + hint:GetStringHeight() + global:GetHeight()) end)
	panel:Hide()
	M.panel = panel
	frame:HookScript("OnHide", M.Stop)
	return button
end

function M.HandleCategoryClick(header)
	if not M.active then return false end
	for _, definition in ipairs(addon.GetCategorySectionDefinitions()) do
		if definition.id == header.categoryID then
			M.Menu(header, definition.id)
			break
		end
	end
	return true
end
