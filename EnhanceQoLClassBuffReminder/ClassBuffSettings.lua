local addon = _G.EnhanceQoL
local Reminder = addon.ClassBuffReminder
local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL")
local app = addon.ConfigApp
local section = Reminder.settingsSection
local pageID = app and app.legacySections and app.legacySections[section]
local groupID = addon.ConfigCurrentGroupBySection and addon.ConfigCurrentGroupBySection[section]
if not (pageID and groupID and app:GetPage(pageID)) then return end
local groupTitle = (addon.ConfigGroupTitleBySection and addon.ConfigGroupTitleBySection[section]) or L["Class Buff Reminder"]

local CLASS_ID = "ClassBuffReminderClass"
local TABLE_ID = "ClassBuffReminderClassTable"
local classes, options, order = {}, {}, {}
local classic = Reminder.classicBuffs ~= nil
-- Classic class IDs have gaps; the class count is not the highest class ID.
for id = 1, math.max(13, GetNumClasses and GetNumClasses() or 0) do
	local name, token = GetClassInfo(id)
	if token and not (classic and (token == "DEATHKNIGHT" or token == "MONK" or token == "EVOKER")) then
		classes[#classes + 1] = { name = name, token = token }
	end
end
table.sort(classes, function(a, b) return a.name < b.name end)
for _, class in ipairs(classes) do
	local icon = ""
	local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class.token]
	if coords then
		icon = ("|TInterface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES:16:16:0:0:256:256:%d:%d:%d:%d|t "):format(
			math.floor(coords[1] * 256 + 0.5), math.floor(coords[2] * 256 + 0.5), math.floor(coords[3] * 256 + 0.5), math.floor(coords[4] * 256 + 0.5)
		)
	end
	options[class.token] = icon .. class.name
	order[#order + 1] = class.token
end
local selectedClass = Reminder:GetClassToken()
if not options[selectedClass] then selectedClass = order[1] end

local CONTENT_SHORT_LABELS = {
	openWorld = "W", scenario = "S", partyFollower = "FD", partyNormal = "N",
	partyHeroic = "H", partyMythic = "M", partyMythicPlus = "M+",
	raidLfr = "LFR", raidNormal = "RN", raidHeroic = "RH", raidMythic = "RM",
}

local function renderTable(parent)
	local rows = Reminder:GetClassBuffRows(selectedClass)
	local handle = { frames = {}, checks = {}, contentChecks = {}, combatChecks = {}, outOfCombatChecks = {} }
	local content = Reminder:GetTrackingContentOptions()
	local showCombat = selectedClass == "WARRIOR"
	local showOutOfCombat = Reminder.supportsOutOfCombatBuffs == true
	local columnSpacing = #content <= 5 and 52 or 38
	local outOfCombatRight = -12 - (showCombat and columnSpacing or 0)
	local contentRight = outOfCombatRight - (showOutOfCombat and columnSpacing or 0)
	local enabledOffset = contentRight - #content * columnSpacing
	local typeOffset = enabledOffset - columnSpacing + 22
	-- Capture the rendered class so callbacks cannot write to a different selection.
	local class = selectedClass
	local function frame(kind, owner)
		local result = CreateFrame(kind or "Frame", nil, owner or parent, kind == "CheckButton" and "UICheckButtonTemplate" or nil)
		handle.frames[#handle.frames + 1] = result
		return result
	end
	local header = frame()
	header:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
	header:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
	header:SetHeight(28)
	local function text(owner, label, left, right, align)
		local labelFrame = owner:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		if left >= 0 then labelFrame:SetPoint("LEFT", owner, "LEFT", left, 0) else labelFrame:SetWidth(right - left) end
		labelFrame:SetPoint("RIGHT", owner, "RIGHT", right, 0)
		labelFrame:SetJustifyH(align or "LEFT")
		labelFrame:SetWordWrap(false)
		labelFrame:SetText(label)
		return labelFrame
	end
	text(header, L["ClassBuffReminderSectionClassBuffs"], 8, typeOffset - 76)
	text(header, _G.TYPE, typeOffset - 68, typeOffset, "CENTER")
	local enabledHeader = text(header, L["ClassBuffReminderTrackerMatrixEnabledShort"], enabledOffset - 24, enabledOffset, "CENTER")
	enabledHeader:SetWidth(24)
	for index, option in ipairs(content) do
		local cell = frame(nil, header)
		cell:SetSize(24, 28)
		cell:SetPoint("RIGHT", header, "RIGHT", contentRight - (#content - index) * columnSpacing, 0)
		local label = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		label:SetAllPoints()
		label:SetText(CONTENT_SHORT_LABELS[option.value] or option.text)
		cell:EnableMouse(true)
		cell:SetScript("OnEnter", function(owner)
			if not GameTooltip then return end
			GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
			GameTooltip:AddLine(option.text, 1, 1, 1)
			GameTooltip:AddLine(L["ClassBuffReminderTrackingContentDesc"], 1, 1, 1, true)
			GameTooltip:Show()
		end)
		cell:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	end
	if showCombat then
		local cell = frame(nil, header)
		cell:SetSize(24, 28)
		cell:SetPoint("RIGHT", header, "RIGHT", -12, 0)
		local label = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		label:SetAllPoints()
		label:SetText("C")
		cell:EnableMouse(true)
		cell:SetScript("OnEnter", function(owner)
			if not GameTooltip then return end
			GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
			GameTooltip:AddLine(L["unitframeVisibility_showCombat"], 1, 1, 1)
			GameTooltip:Show()
		end)
		cell:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	end
	if showOutOfCombat then
		local cell = frame(nil, header)
		cell:SetSize(24, 28)
		cell:SetPoint("RIGHT", header, "RIGHT", outOfCombatRight, 0)
		local label = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		label:SetAllPoints()
		label:SetText("OOC")
		cell:EnableMouse(true)
		cell:SetScript("OnEnter", function(owner)
			if not GameTooltip then return end
			GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
			GameTooltip:AddLine(L["ClassBuffReminderOnlyOutOfCombat"], 1, 1, 1)
			GameTooltip:Show()
		end)
		cell:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	end
	for index, row in ipairs(rows) do
		local line = frame()
		line:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -28 - (index - 1) * 30)
		line:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -28 - (index - 1) * 30)
		line:SetHeight(30)
		if index % 2 == 0 then
			local background = line:CreateTexture(nil, "BACKGROUND")
			background:SetAllPoints()
			background:SetColorTexture(1, 1, 1, 0.035)
		end
		local icon = line:CreateTexture(nil, "ARTWORK")
		icon:SetSize(22, 22)
		icon:SetPoint("LEFT", line, "LEFT", 8, 0)
		icon:SetTexture(row.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
		text(line, row.label, 38, typeOffset - (row.custom and 104 or 76))
		if row.custom then
			local remove = frame("Button", line)
			remove:SetSize(22, 22)
			remove:SetPoint("RIGHT", line, "RIGHT", typeOffset - 76, 0)
			local label = remove:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			label:SetAllPoints()
			label:SetText("X")
			remove:SetScript("OnClick", function()
				if not Reminder:IsEnabled() then return end
				Reminder:RemoveCustomBuffDefinition(class, row.id)
				local config = addon.ConfigCenterFrame
				local state = config and config._LibSettingsDesignerState
				if state and state.RenderContent then state:RenderContent() end
			end)
		end
		local scope = text(line, row.kind, typeOffset - 68, typeOffset, "CENTER")
		scope:SetWidth(68)
		local check = frame("CheckButton", line)
		check:SetSize(24, 24)
		check:SetPoint("RIGHT", line, "RIGHT", enabledOffset, 0)
		check:SetChecked(Reminder:IsClassBuffRowEnabled(row, class))
		check:SetScript("OnClick", function(self)
			if not Reminder:IsEnabled() then return end
			Reminder:SetClassBuffRowEnabled(row, class, self:GetChecked() == true)
			-- Update only this table; keep the current dropdown and scroll position intact.
			handle:Refresh()
		end)
		line:EnableMouse(true)
		line:SetScript("OnEnter", function(owner)
			if not GameTooltip then return end
			GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
			if row.id then GameTooltip:SetSpellByID(row.id) else GameTooltip:AddLine(row.label, 1, 1, 1) end
			if row.custom then Reminder:AddCustomBuffTooltipLines(GameTooltip, row.id, class) end
			GameTooltip:Show()
		end)
		line:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
		handle.checks[#handle.checks + 1] = { widget = check, row = row }
		if Reminder:CanConfigureClassBuffCombatOnly(row, class) then
			local combatCheck = frame("CheckButton", line)
			combatCheck:SetSize(24, 24)
			combatCheck:SetPoint("RIGHT", line, "RIGHT", -12, 0)
			combatCheck:SetScript("OnClick", function(self)
				if not Reminder:IsEnabled() or not Reminder:IsClassBuffRowEnabled(row, class) then return end
				Reminder:SetClassBuffCombatOnly(row, class, self:GetChecked() == true)
				handle:Refresh()
			end)
			combatCheck:SetScript("OnEnter", function(owner)
				if not GameTooltip then return end
				GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
				GameTooltip:AddLine(L["unitframeVisibility_showCombat"], 1, 1, 1)
				GameTooltip:Show()
			end)
			combatCheck:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
			handle.combatChecks[#handle.combatChecks + 1] = { widget = combatCheck, row = row }
		end
		if showOutOfCombat and not row.trackerKey then
			local outOfCombatCheck = frame("CheckButton", line)
			outOfCombatCheck:SetSize(24, 24)
			outOfCombatCheck:SetPoint("RIGHT", line, "RIGHT", outOfCombatRight, 0)
			outOfCombatCheck:SetScript("OnClick", function(self)
				if not Reminder:IsEnabled() or not Reminder:IsClassBuffRowEnabled(row, class) then return end
				Reminder:SetClassBuffOutOfCombatOnly(row, self:GetChecked() == true)
				handle:Refresh()
			end)
			outOfCombatCheck:SetScript("OnEnter", function(owner)
				if not GameTooltip then return end
				GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
				GameTooltip:AddLine(L["ClassBuffReminderOnlyOutOfCombat"], 1, 1, 1)
				GameTooltip:Show()
			end)
			outOfCombatCheck:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
			handle.outOfCombatChecks[#handle.outOfCombatChecks + 1] = { widget = outOfCombatCheck, row = row }
		end
		for index, option in ipairs(content) do
			local contentCheck = frame("CheckButton", line)
			contentCheck.unsupportedContent = not classic and option.value == "partyMythicPlus" and (row.trackerKey == "classBuffReminderTrackFlasks" or row.trackerKey == "classBuffReminderTrackFood")
			contentCheck:SetMotionScriptsWhileDisabled(true)
			contentCheck:SetSize(24, 24)
			contentCheck:SetPoint("RIGHT", line, "RIGHT", contentRight - (#content - index) * columnSpacing, 0)
			contentCheck:SetScript("OnClick", function(self)
				if self.unsupportedContent or not Reminder:IsEnabled() or not Reminder:IsClassBuffRowEnabled(row, class) then return end
				local selection = Reminder:GetClassBuffRowContent(row, class)
				selection[option.value] = self:GetChecked() == true or nil
				Reminder:SetClassBuffRowContent(row, class, selection)
				handle:Refresh()
			end)
			contentCheck:SetScript("OnEnter", function(owner)
				if not GameTooltip then return end
				GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
				GameTooltip:AddLine(row.label, 1, 1, 1)
				GameTooltip:AddLine(owner.unsupportedContent and L["ClassBuffReminderTrackerMatrixMythicPlusUnavailable"] or option.text, 1, 1, 1)
				GameTooltip:Show()
			end)
			contentCheck:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
			handle.contentChecks[#handle.contentChecks + 1] = { widget = contentCheck, row = row, content = option.value }
		end
	end
	function handle:Refresh()
		for _, check in ipairs(self.checks) do
			check.widget:SetChecked(Reminder:IsClassBuffRowEnabled(check.row, class))
			check.widget:SetEnabled(Reminder:IsEnabled())
		end
		for _, check in ipairs(self.combatChecks) do
			check.widget:SetChecked(Reminder:IsClassBuffCombatOnly(check.row.spellIds[1]))
			check.widget:SetEnabled(Reminder:IsEnabled() and Reminder:IsClassBuffRowEnabled(check.row, class))
		end
		for _, check in ipairs(self.outOfCombatChecks) do
			check.widget:SetChecked(Reminder:IsClassBuffOutOfCombatOnly(check.row.spellIds[1]))
			check.widget:SetEnabled(Reminder:IsEnabled() and Reminder:IsClassBuffRowEnabled(check.row, class))
		end
		for _, check in ipairs(self.contentChecks) do
			local enabled = Reminder:IsEnabled() and Reminder:IsClassBuffRowEnabled(check.row, class) and not check.widget.unsupportedContent
			check.widget:SetChecked(Reminder:GetClassBuffRowContent(check.row, class)[check.content] == true)
			check.widget:SetEnabled(enabled)
			check.widget:SetAlpha(enabled and 1 or 0.35)
		end
	end
	function handle:Release()
		for _, widget in ipairs(self.frames) do
			widget:SetScript("OnEnter", nil)
			widget:SetScript("OnLeave", nil)
			if widget:GetObjectType() == "CheckButton" or widget:GetObjectType() == "Button" then widget:SetScript("OnClick", nil) end
			widget:Hide()
			widget:SetParent(nil)
		end
		wipe(self.frames)
		wipe(self.checks)
		wipe(self.contentChecks)
		wipe(self.combatChecks)
		wipe(self.outOfCombatChecks)
	end
	handle:Refresh()
	return handle
end

local controlOrder = (addon.ConfigControlOrder or 0) + 10
app:RegisterControl(pageID, {
	id = CLASS_ID,
	type = "dropdown",
	label = _G.CLASS,
	description = L["ClassBuffReminderClassTableDesc"],
	groupID = groupID,
	groupTitle = groupTitle,
	list = options,
	orderList = order,
	getValue = function() return selectedClass end,
	setValue = function(value) if options[value] then selectedClass = value end end,
	refreshOnChange = true,
	trackCustomized = false,
	order = controlOrder,
	newTagID = CLASS_ID,
})
app:RegisterControl(pageID, {
	id = TABLE_ID,
	type = "custom",
	label = L["ClassBuffReminderClassTable"],
	description = L["ClassBuffReminderClassTableDesc"],
	hideHeader = true,
	groupID = groupID,
	groupTitle = groupTitle,
	getHeight = function() return 56 + #Reminder:GetClassBuffRows(selectedClass) * 30 end,
	render = function(parent) return renderTable(parent) end,
	refresh = function(handle) if handle and handle.Refresh then handle:Refresh() end end,
	release = function(handle) if handle and handle.Release then handle:Release() end end,
	order = controlOrder + 2,
	newTagID = Reminder.supportsOutOfCombatBuffs and "ClassBuffReminderClassContentOOC" or "ClassBuffReminderClassContent",
})

local function refreshCustomRows()
	local config = addon.ConfigCenterFrame
	local state = config and config._LibSettingsDesignerState
	if config and config:IsShown() and state and state.RenderContent then state:RenderContent() end
end

function Reminder:OpenCustomBuffPopup(class)
	if not self:IsEnabled() then return end
	local popup = self.customBuffPopup
	if not popup then
		popup = CreateFrame("Frame", "EQOLCustomBuffReminderPopup", UIParent, "BackdropTemplate")
		self.customBuffPopup = popup
		popup:SetSize(540, 410)
		popup:SetPoint("CENTER")
		popup:SetFrameStrata("FULLSCREEN_DIALOG")
		popup:SetClampedToScreen(true)
		popup:EnableMouse(true)
		popup:SetMovable(true)
		popup:RegisterForDrag("LeftButton")
		popup:SetScript("OnDragStart", popup.StartMoving)
		popup:SetScript("OnDragStop", popup.StopMovingOrSizing)
		popup:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
		popup:SetBackdropColor(0.035, 0.04, 0.05, 1)
		popup:SetBackdropBorderColor(0.3, 0.34, 0.4, 1)
		table.insert(UISpecialFrames, "EQOLCustomBuffReminderPopup")
		local function label(text, y, font)
			local result = popup:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
			result:SetPoint("TOPLEFT", popup, "TOPLEFT", 24, y)
			result:SetWidth(492)
			result:SetJustifyH("LEFT")
			result:SetText(text)
			return result
		end
		popup.title = label("", -22, "GameFontNormalLarge")
		local guide = label(L["ClassBuffReminderCustomGuide"], -58)
		guide:SetHeight(90)
		guide:SetJustifyV("TOP")
		label("1. " .. L["ClassBuffReminderCustomSpells"] .. " *", -154, "GameFontNormal")
		label("2. " .. L["ClassBuffReminderCustomAuras"], -224, "GameFontNormal")
		local function input(y, numeric)
			local edit = CreateFrame("EditBox", nil, popup, "InputBoxTemplate")
			edit:SetSize(480, 28)
			edit:SetPoint("TOPLEFT", popup, "TOPLEFT", 30, y)
			edit:SetAutoFocus(false)
			edit:SetNumeric(numeric)
			edit:SetScript("OnEscapePressed", function() popup:Hide() end)
			return edit
		end
		popup.spell = input(-180, true)
		popup.auras = input(-250, false)
		local hint = label(L["ClassBuffReminderCustomAurasDesc"], -286)
		hint:SetHeight(42)
		hint:SetJustifyV("TOP")
		popup.error = label("", -334)
		popup.error:SetTextColor(1, 0.3, 0.3)
		popup.error:SetHeight(30)
		local close = CreateFrame("Button", nil, popup, "UIPanelCloseButton")
		close:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -4, -4)
		close:SetScript("OnClick", function() popup:Hide() end)
		popup.save = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
		popup.save:SetSize(260, 26)
		popup.save:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -24, 20)
		popup.save:SetText(L["ClassBuffReminderCustomAdd"])
		popup.save:SetScript("OnClick", function()
			if not Reminder:IsEnabled() then return end
			if Reminder:SetCustomBuffDefinition(popup.class, popup.spell:GetText(), popup.auras:GetText()) then
				popup:Hide()
				refreshCustomRows()
			else
				popup.error:SetText(L["ClassBuffReminderCustomSpellsInvalid"])
			end
		end)
		local cancel = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
		cancel:SetSize(120, 26)
		cancel:SetPoint("BOTTOMLEFT", popup, "BOTTOMLEFT", 24, 20)
		cancel:SetText(_G.CANCEL)
		cancel:SetScript("OnClick", function() popup:Hide() end)
		popup.spell:SetScript("OnTextChanged", function(edit, userInput)
			popup.error:SetText("")
			local id = tonumber(edit:GetText())
			popup.save:SetEnabled(Reminder:IsEnabled() and id ~= nil and id > 0)
			if userInput then
				local definition = Reminder:GetCustomBuffDefinition(popup.class, id)
				if definition then popup.auras:SetText(table.concat(definition.auraIds, ", ")) end
			end
		end)
		popup.spell:SetScript("OnTabPressed", function() popup.auras:SetFocus() end)
		popup.spell:SetScript("OnEnterPressed", function() popup.auras:SetFocus() end)
		popup.auras:SetScript("OnTabPressed", function() popup.spell:SetFocus() end)
		popup.auras:SetScript("OnEnterPressed", function() popup.save:Click() end)
		popup:SetScript("OnHide", function()
			popup.spell:ClearFocus()
			popup.auras:ClearFocus()
		end)
	end
	popup.class = class or self:GetClassToken()
	popup.title:SetText(L["ClassBuffReminderCustomOpen"] .. " - " .. (options[popup.class] or popup.class))
	popup.spell:SetText("")
	popup.auras:SetText("")
	popup.error:SetText("")
	popup.save:SetEnabled(false)
	popup:Show()
	popup:Raise()
	popup.spell:SetFocus()
	return popup
end

app:RegisterControl(pageID, {
	id = "ClassBuffReminderCustomAdd", type = "button",
	label = L["ClassBuffReminderCustomOpen"],
	buttonText = L["ClassBuffReminderCustomOpen"],
	description = L["ClassBuffReminderCustomGuide"],
	groupID = groupID, groupTitle = groupTitle,
	onClick = function() Reminder:OpenCustomBuffPopup(selectedClass) end,
	isEnabled = function() return Reminder:IsEnabled() end,
	trackCustomized = false, order = controlOrder + 1,
	newTagID = "ClassBuffReminderCustomAdd",
})
