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
				Reminder:RemoveCustomBuffDefinition(class, row.itemId or row.id, row.itemId ~= nil)
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
			if row.itemId then
				GameTooltip:SetItemByID(row.itemId)
			elseif row.id then
				GameTooltip:SetSpellByID(row.id)
			else
				GameTooltip:AddLine(row.label, 1, 1, 1)
			end
			if row.custom then Reminder:AddCustomBuffTooltipLines(GameTooltip, row.itemId or row.id, class, row.itemId ~= nil) end
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
		if showOutOfCombat and not row.trackerKey and not row.itemId then
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
local soloKey = "classBuffReminderShowSolo"
local consumablesKey = "classBuffReminderKeybindConsumables"
app:RegisterControl(pageID, {
	id = soloKey,
	key = soloKey,
	type = "toggle",
	label = L["ClassBuffReminderShowSolo"],
	groupID = groupID,
	groupTitle = groupTitle,
	order = controlOrder - 3,
	default = Reminder.defaults.showSolo,
	isEnabled = function() return Reminder:IsEnabled() end,
	setValue = function(value)
		addon.db[soloKey] = value == true
		Reminder:OnSettingChanged()
	end,
})

app:RegisterControl(pageID, {
	id = consumablesKey,
	key = consumablesKey,
	type = "toggle",
	label = L["ClassBuffReminderKeybindConsumables"],
	description = L["ClassBuffReminderKeybindConsumablesDesc"],
	groupID = groupID,
	groupTitle = groupTitle,
	order = controlOrder - 2,
	default = false,
	newTagID = "ClassBuffReminderKeybindConsumables",
	isEnabled = function() return Reminder:IsEnabled() end,
	getValue = function() return addon.db[consumablesKey] == true end,
	setValue = function(value)
		addon.db[consumablesKey] = value == true
		Reminder:OnSettingChanged()
	end,
})

app:RegisterControl(pageID, {
	id = "ClassBuffReminderAdvancedSettings",
	type = "button",
	label = L["ClassBuffReminderAdvancedSettings"],
	description = L["ClassBuffReminderEditModeHint"],
	buttonText = L["configCenterConfigure"],
	groupID = groupID,
	groupTitle = groupTitle,
	order = controlOrder - 1,
	newTagID = "ClassBuffReminderAdvancedSettings",
	isEnabled = function() return Reminder:IsEnabled() end,
	onClick = function()
		if not Reminder:IsEnabled() then return end
		if InCombatLockdown and InCombatLockdown() then
			if UIErrorsFrame and ERR_NOT_IN_COMBAT then UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT, 1, 0, 0) end
			return
		end
		local editMode = addon.EditMode
		local entry = editMode and editMode.frames.classBuffReminder
		local lib = addon.EditModeLib
		if not (entry and entry.preparedSettings and lib) or lib:IsInEditMode() then return end
		local registration = entry.navigationRegistration
		local navigation = registration.settingsNavigation
		if navigation == nil then navigation = addon.EditModeNavigationProfiles.Get(entry.id, registration) end
		local dialog = lib:ShowStandaloneSettingsDialog(entry.frame, {
			title = entry.title,
			settings = entry.preparedSettings,
			settingsNavigation = navigation,
			buttons = {},
			showReset = false,
			point = "CENTER",
		})
		if dialog then addon.functions.HideConfigCenterUntilFrameHidden(dialog) end
	end,
})

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
		popup:SetSize(540, 440)
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
		local function radio(name, text, x, isItem)
			local option = CreateFrame("Button", "$parent" .. name, popup, "BackdropTemplate")
			option:SetSize(158, 36)
			option:SetPoint("TOPLEFT", popup, "TOPLEFT", x, -55)
			option:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
			local highlight = option:CreateTexture(nil, "HIGHLIGHT")
			highlight:SetAllPoints()
			highlight:SetColorTexture(1, 1, 1, 0.08)
			local button = CreateFrame("CheckButton", "$parentRadio", option, "UIRadioButtonTemplate")
			button:SetPoint("LEFT", option, "LEFT", 12, 0)
			button.text:SetText(text)
			button.option = option
			local function selectOption()
				if popup.actionType ~= isItem then popup:SetActionType(isItem) end
				button:SetChecked(true)
				popup.spell:SetFocus()
			end
			option:SetScript("OnClick", selectOption)
			button:SetScript("OnClick", selectOption)
			return button
		end
		local function setSelected(button, selected)
			button:SetChecked(selected)
			if selected then
				button.option:SetBackdropColor(0.22, 0.16, 0.07, 1)
				button.option:SetBackdropBorderColor(0.84, 0.64, 0.25, 1)
				button.text:SetFontObject(GameFontNormalLarge)
			else
				button.option:SetBackdropColor(0.08, 0.095, 0.11, 1)
				button.option:SetBackdropBorderColor(0.31, 0.36, 0.42, 1)
				button.text:SetFontObject(GameFontHighlightLarge)
			end
		end
		popup.spellRadio = radio("Spell", L["Spell"], 24, false)
		popup.itemRadio = radio("Item", L["Item"], 190, true)
		popup.weaponRadio = radio("Weapon", L["ClassBuffReminderWeaponBuff"], 356, "weapon")
		local guide = label("", -104)
		guide:SetHeight(74)
		guide:SetJustifyV("TOP")
		local actionLabel = label("", -184, "GameFontNormal")
		local auraLabel = label("", -254, "GameFontNormal")
		local function input(y, numeric)
			local edit = CreateFrame("EditBox", nil, popup, "InputBoxTemplate")
			edit:SetSize(480, 28)
			edit:SetPoint("TOPLEFT", popup, "TOPLEFT", 30, y)
			edit:SetAutoFocus(false)
			edit:SetNumeric(numeric)
			edit:SetScript("OnEscapePressed", function() popup:Hide() end)
			return edit
		end
		popup.spell = input(-210, true)
		popup.auras = input(-280, false)
		local hint = label(L["ClassBuffReminderCustomAurasDesc"], -316)
		hint:SetHeight(42)
		hint:SetJustifyV("TOP")
		popup.slotButtons = {}
		function popup:SetWeaponSlots(definition)
			self.weaponSlots = {}
			for slot, button in pairs(self.slotButtons) do
				local selected = Reminder:CustomWeaponSlotSelected(definition, slot)
				self.weaponSlots[slot] = selected or nil
				button:SetChecked(selected)
			end
		end
		for slot = 16, 18 do
			if Reminder:SupportsCustomWeaponSlot(slot) then
				local button = CreateFrame("CheckButton", nil, popup, "UICheckButtonTemplate")
				button:SetPoint("TOPLEFT", popup, "TOPLEFT", 24 + (slot - 16) * 166, -324)
				button.Text:SetText(Reminder:GetCustomWeaponSlotLabel(slot))
				button:SetScript("OnClick", function()
					popup.weaponSlots[slot] = button:GetChecked() or nil
					popup:UpdateSaveButton()
				end)
				popup.slotButtons[slot] = button
			end
		end
		local presets = Reminder.foreverBuffs and Reminder.foreverBuffs.customWeaponEnchants
		local picker
		if presets then
			picker = CreateFrame("DropdownButton", nil, popup, "WowStyle1DropdownTemplate")
			picker:SetPoint("TOPLEFT", popup, "TOPLEFT", 24, -145)
			picker:SetWidth(492)
			picker:SetDefaultText(L["ClassBuffReminderWeaponBuff"])
			picker:SetupMenu(function(_, root)
				root:SetScrollMode(320)
				local options = {}
				for id, preset in pairs(presets) do
					local name = C_Item.GetItemNameByID(id) or preset.name
					options[#options + 1] = { id = id, name = name }
				end
				table.sort(options, function(a, b)
					if a.name == b.name then return a.id < b.id end
					return a.name < b.name
				end)
				for _, option in ipairs(options) do
					local id = option.id
					local icon = Reminder.GetItemIcon(id) or 134400
					local label = ("|T%s:16:16|t %s (%d)"):format(icon, option.name, id)
					local button = root:CreateButton(label, function()
						popup.spell:SetText(tostring(id))
						popup:LoadAction(id)
						popup:UpdateSaveButton()
					end)
					button:SetTooltip(function(tooltip) tooltip:SetItemByID(id) end)
				end
			end)
		end
		popup.error = label("", -364)
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
			if Reminder:SetCustomBuffDefinition(popup.class, popup.spell:GetText(), popup.auras:GetText(), popup.isItem, popup.actionType == "weapon" and popup.weaponSlots or nil) then
				popup:Hide()
				refreshCustomRows()
			else
				popup.error:SetText(L[popup.actionType == "weapon" and "ClassBuffReminderCustomWeaponGuide" or popup.isItem and "ClassBuffReminderCustomItemsInvalid" or "ClassBuffReminderCustomSpellsInvalid"])
			end
		end)
		local cancel = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
		cancel:SetSize(120, 26)
		cancel:SetPoint("BOTTOMLEFT", popup, "BOTTOMLEFT", 24, 20)
		cancel:SetText(_G.CANCEL)
		cancel:SetScript("OnClick", function() popup:Hide() end)
		function popup:UpdateSaveButton()
			local id = tonumber(self.spell:GetText())
			local hasSlot = self.actionType ~= "weapon" or next(self.weaponSlots) ~= nil
			self.save:SetEnabled(Reminder:IsEnabled() and id ~= nil and id > 0 and hasSlot)
		end
		function popup:LoadAction(id)
			local definition = Reminder:GetCustomBuffDefinition(self.class, id, self.isItem)
			if self.actionType == "weapon" then
				if definition and definition.enchantId then
					self:SetWeaponSlots(definition)
					self.auras:SetText(tostring(definition.enchantId))
				else
					local preset = presets and presets[id]
					local enchant = preset and preset.enchantId or (id == 20744 and 2623)
					self.auras:SetText(enchant and tostring(enchant) or "")
				end
			else
				self.auras:SetText(definition and definition.auraIds and table.concat(definition.auraIds, ", ") or "")
			end
		end
		popup.spell:SetScript("OnTextChanged", function(edit, userInput)
			popup.error:SetText("")
			if userInput then popup:LoadAction(tonumber(edit:GetText())) end
			popup:UpdateSaveButton()
		end)
		function popup:SetActionType(actionType)
			local weapon = actionType == "weapon"
			local isItem = actionType == true or weapon
			self.actionType = actionType
			self.isItem = isItem
			self:SetWeaponSlots({ weaponSlot = 16 })
			if picker then picker:SetShown(weapon) end
			for _, button in pairs(self.slotButtons) do button:SetShown(weapon) end
			setSelected(self.weaponRadio, weapon)
			setSelected(self.spellRadio, not isItem)
			setSelected(self.itemRadio, actionType == true)
			guide:SetText(L[weapon and "ClassBuffReminderCustomWeaponGuide" or isItem and "ClassBuffReminderCustomItemsGuide" or "ClassBuffReminderCustomGuide"])
			actionLabel:SetText("1. " .. L[isItem and "ClassBuffReminderCustomItems" or "ClassBuffReminderCustomSpells"] .. " *")
			auraLabel:SetText("2. " .. L[weapon and "Temp. EnchantID" or "ClassBuffReminderCustomAuras"] .. (isItem and " *" or ""))
			hint:SetShown(not isItem)
			self.spell:SetText("")
			self.auras:SetText("")
			self.error:SetText("")
			self.save:SetEnabled(false)
		end
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
	popup:SetActionType(false)
	popup:Show()
	popup:Raise()
	popup.spell:SetFocus()
	return popup
end

app:RegisterControl(pageID, {
	id = "ClassBuffReminderCustomAdd", type = "button",
	label = L["ClassBuffReminderCustomOpen"],
	buttonText = L["ClassBuffReminderCustomOpen"],
	groupID = groupID, groupTitle = groupTitle,
	onClick = function() Reminder:OpenCustomBuffPopup(selectedClass) end,
	isEnabled = function() return Reminder:IsEnabled() end,
	trackCustomized = false, order = controlOrder + 1,
	newTagID = "ClassBuffReminderCustomAdd",
})
