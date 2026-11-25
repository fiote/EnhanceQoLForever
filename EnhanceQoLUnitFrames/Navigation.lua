local parentAddonName = "EnhanceQoL"
local _, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL")
local UF = addon.Aura and addon.Aura.UF
if not UF then return end
UF.ui = UF.ui or {}

local statusGapDialog
local statusGapWatcher, pendingStatusGapRefresh

local function refreshStatusGap(preview)
	if InCombatLockdown() then
		pendingStatusGapRefresh = preview.refresh
		statusGapWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
	else
		preview.refresh()
	end
end

local function finishStatusGapPreview(preview, apply, skipRefresh)
	if not preview or UF.statusGapPreview ~= preview then return end
	UF.FinishLegacyStatusGapPreview(preview, apply and not InCombatLockdown())
	statusGapWatcher:UnregisterEvent("PLAYER_REGEN_DISABLED")
	if not skipRefresh then refreshStatusGap(preview) end
end

function UF.ui.CancelLegacyStatusGapPreview(skipRefresh)
	local preview = UF.statusGapPreview
	if not preview then return end
	finishStatusGapPreview(preview, false, skipRefresh)
	if statusGapDialog then statusGapDialog:Hide() end
end

local function setStatusGapDialogSelection(dialog, modern)
	dialog.oldStyle.radio:SetChecked(not modern)
	dialog.newStyle.radio:SetChecked(modern)
	dialog.apply:SetEnabled(modern)
end

local function positionStatusGapDialog(dialog, unit)
	local reference = _G[UF.GetAnchorFrameName(unit)]
	local midpointX, midpointY = UIParent:GetWidth() / 2, UIParent:GetHeight() / 2
	local halfWidth, halfHeight = dialog:GetWidth() / 2, dialog:GetHeight() / 2
	local y = midpointY
	if reference and reference:IsVisible() then
		local left, bottom, width, height = reference:GetRect()
		if left and bottom and width and height then
			local scale = reference:GetEffectiveScale() / UIParent:GetEffectiveScale()
			local right, top = (left + width) * scale, (bottom + height) * scale
			left, bottom = left * scale, bottom * scale
			if left < midpointX + halfWidth and right > midpointX - halfWidth and bottom < midpointY + halfHeight and top > midpointY - halfHeight then
				local above, below = top + halfHeight + 12, bottom - halfHeight - 12
				local fitsAbove = above + halfHeight <= midpointY * 2 - 12
				local fitsBelow = below - halfHeight >= 12
				if fitsAbove and (not fitsBelow or above - midpointY <= midpointY - below) then
					y = above
				elseif fitsBelow then
					y = below
				end
			end
		end
	end
	dialog:ClearAllPoints()
	dialog:SetPoint("CENTER", UIParent, "CENTER", 0, y - midpointY)
end

local function createStatusGapDialog()
	local dialog = CreateFrame("Frame", "EQOLUnitFrameStatusGapDialog", UIParent, "BasicFrameTemplateWithInset")
	dialog:SetWidth(420)
	dialog:SetFrameStrata("FULLSCREEN_DIALOG")
	dialog:SetClampedToScreen(true)
	dialog:EnableMouse(true)
	dialog:SetMovable(true)
	dialog.DragHandle = CreateFrame("Frame", nil, dialog)
	dialog.DragHandle:SetPoint("TOPLEFT", 6, -3)
	dialog.DragHandle:SetPoint("TOPRIGHT", -30, -3)
	dialog.DragHandle:SetHeight(21)
	dialog.DragHandle:EnableMouse(true)
	dialog.DragHandle:RegisterForDrag("LeftButton")
	dialog.DragHandle:SetScript("OnDragStart", function() dialog:StartMoving() end)
	dialog.DragHandle:SetScript("OnDragStop", function() dialog:StopMovingOrSizing() end)
	dialog:SetScript("OnHide", function(self)
		local preview = self.preview
		self.preview = nil
		finishStatusGapPreview(preview, false)
	end)
	table.insert(UISpecialFrames, dialog:GetName())

	local function styleRow(label, description, modern)
		local row = CreateFrame("Button", nil, dialog)
		local radio = CreateFrame("CheckButton", nil, row, "UIRadioButtonTemplate")
		radio:SetSize(20, 20)
		radio:SetPoint("TOPLEFT")
		radio:EnableMouse(false)
		row.radio = radio

		local title = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		title:SetPoint("LEFT", radio, "RIGHT", 4, 0)
		title:SetText(label)
		local detail = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		detail:SetPoint("TOPLEFT", row, "TOPLEFT", 24, -22)
		detail:SetWidth(348)
		detail:SetJustifyH("LEFT")
		detail:SetText(description)
		row:SetHeight(22 + detail:GetStringHeight())
		row:SetHighlightTexture([[Interface\QuestFrame\UI-QuestTitleHighlight]], "ADD")
		row:SetScript("OnClick", function()
			local preview = dialog.preview
			if not InCombatLockdown() and UF.SetLegacyStatusGapPreviewStyle(preview, modern) then
				setStatusGapDialogSelection(dialog, modern)
				preview.refresh()
			end
		end)
		return row
	end

	dialog.oldStyle = styleRow(L["UFLegacyStatusGapOld"], L["UFLegacyStatusGapOldDesc"], false)
	dialog.oldStyle:SetPoint("TOPLEFT", 24, -38)
	dialog.oldStyle:SetPoint("TOPRIGHT", -24, -38)
	dialog.newStyle = styleRow(L["UFLegacyStatusGapNew"], L["UFLegacyStatusGapNewDesc"], true)
	dialog.newStyle:SetPoint("TOPLEFT", dialog.oldStyle, "BOTTOMLEFT", 0, -14)
	dialog.newStyle:SetPoint("TOPRIGHT", dialog.oldStyle, "BOTTOMRIGHT", 0, -14)
	local warning = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	warning:SetPoint("TOPLEFT", dialog.newStyle, "BOTTOMLEFT", 24, -14)
	warning:SetWidth(348)
	warning:SetJustifyH("LEFT")
	warning:SetText(L["UFLegacyStatusGapDesc"])

	local cancel = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
	cancel:SetSize(112, 24)
	cancel:SetPoint("BOTTOMRIGHT", -24, 18)
	cancel:SetText(CANCEL)
	cancel:SetScript("OnClick", function() dialog:Hide() end)
	dialog.cancel = cancel
	local apply = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
	apply:SetSize(210, 24)
	apply:SetPoint("RIGHT", cancel, "LEFT", -8, 0)
	apply:SetText(L["UFLegacyStatusGapApply"])
	apply:SetScript("OnClick", function()
		local preview = dialog.preview
		if not (preview and preview.positions) or InCombatLockdown() then return end
		finishStatusGapPreview(preview, true)
		dialog:Hide()
	end)
	dialog.apply = apply
	dialog:SetHeight(122 + dialog.oldStyle:GetHeight() + dialog.newStyle:GetHeight() + warning:GetStringHeight())
	dialog:Hide()
	return dialog
end

local function showLegacyStatusGapPreview(unit, refresh)
	if InCombatLockdown() then return end
	if not statusGapWatcher then
		statusGapWatcher = CreateFrame("Frame")
		statusGapWatcher:SetScript("OnEvent", function(self, event)
			if event == "PLAYER_REGEN_DISABLED" then
				UF.ui.CancelLegacyStatusGapPreview()
			else
				self:UnregisterEvent("PLAYER_REGEN_ENABLED")
				local update = pendingStatusGapRefresh
				pendingStatusGapRefresh = nil
				if update then update() end
			end
		end)
		local lib = addon.EditModeLib
		if lib and lib.RegisterCallback then
			lib:RegisterCallback("context", function(_, reason) UF.ui.CancelLegacyStatusGapPreview(reason == "uf-profile") end)
			lib:RegisterCallback("layout", function() UF.ui.CancelLegacyStatusGapPreview() end)
			lib:RegisterCallback("exit", function() UF.ui.CancelLegacyStatusGapPreview() end)
		end
	end

	local preview = UF.BeginLegacyStatusGapPreview(unit)
	if not preview then return end
	preview.refresh = refresh
	statusGapDialog = statusGapDialog or createStatusGapDialog()
	statusGapDialog.preview = preview
	local frameInfo = UF.DYNAMIC_ANCHOR_DEFINITIONS[preview.unit]
	statusGapDialog.TitleText:SetText(frameInfo and frameInfo.label() or L["UFLegacySettings"])
	setStatusGapDialogSelection(statusGapDialog, false)
	statusGapWatcher:RegisterEvent("PLAYER_REGEN_DISABLED")
	positionStatusGapDialog(statusGapDialog, preview.unit)
	statusGapDialog:Show()
end

function UF.ui.AppendLegacyStatusGapSettings(list, unit, getConfig, refresh)
	local function isAvailable()
		local cfg = getConfig(unit)
		return not cfg.statusGapMigrated and (cfg.legacyStatusGap == true or (cfg.legacyStatusGap == nil and unit ~= "pet"))
	end
	list[#list + 1] = { name = L["UFLegacySettings"], kind = UF.ui.settingType.Collapsible, id = "legacySettings", isShown = isAvailable, defaultCollapsed = true }
	list[#list + 1] = {
		name = L["UFLegacyStatusGap"],
		kind = UF.ui.settingType.Action,
		parentId = "legacySettings",
		navigationField = "legacyStatusGap",
		navigationResetExcluded = true,
		get = function() end,
		set = function() end,
		onClick = function() if isAvailable() then showLegacyStatusGapPreview(unit, refresh) end end,
	}
end

function UF.ui.BuildSettingsNavigation()
	local castSections = {
		[L["Bar style"]] = { "castStyle", L["Bar style"] },
		[L["Background"]] = { "castStyle", L["Bar style"] },
		[L["Border"]] = { "castStyle", L["Bar style"] },
		[L["Icon"]] = { "castIcon", L["Icon"] },
		[L["Icon border"]] = { "castIcon", L["Icon"] },
		[L["Text"]] = { "castText", L["Text"] },
		[L["Name"]] = { "castText", L["Text"] },
		[L["Duration"]] = { "castDuration", L["Duration"] },
		[L["Interrupt feedback"]] = { "castFeedback", L["Interrupt feedback"] },
	}
	return {
		categories = {
			{ id = "frame", name = L["Frame"], groups = { "frame", "layout", "border", "highlight", "stance", "rangeFade", "utility" } },
			{ id = "portrait", name = L["Portrait"], groups = { "portrait" } },
			{ id = "health", name = L["Health"], groups = { "health", "healthText", "incomingHeal", "absorb", "healAbsorb", "npcColors" } },
			{ id = "power", name = L["Power"], groups = { "power", "powerText", "secondaryPower", "secondaryPowerText", "secondaryPowerStaggerColors" } },
			{ id = "text", name = L["UFNavNameStatus"], groups = { "name", "level", "statusText" } },
			{ id = "indicators", name = L["UFNavIndicators"], groups = { "unitStatus", "dispelTint", "raidicon", "combatFeedback" } },
			{ id = "auras", name = L["Auras"], groups = { "buffs", "debuffs" } },
			{ id = "cast", name = L["Castbar"], groups = { "cast" } },
			{ id = "classResource", name = L["ClassResource"], groups = { "classResource" } },
			{ id = "totemFrame", name = L["Totem Frame"], groups = { "totemFrame" } },
			{ id = "dataBar", name = L["UFDataBar"], groups = { "dataBar" } },
			{ id = "legacySettings", name = L["UFLegacySettings"], groups = { "legacySettings" } },
		},
		tabNames = {
			legacySettings = L["UFLegacySettings"],
			frame = L["General"], utility = L["Copy settings"], health = L["Bar"], healthText = L["Text"], power = L["Bar"], powerText = L["Text"],
		},
		splitGroups = {
			portrait = function(data, section)
				local field = data.navigationField or ""
				if data.navigationTab == "portraitCast" then return "portraitCast", L["Castbar"] end
				if field:match("^portraitDecorationLevel") then return "portraitLevel", L["Level"] end
				if field == "portraitCastIcon" or field == "portraitCastRing" or field == "portraitCastPreview" or field:match("^portrait%.castRing") then return "portraitCast", L["Castbar"] end
				if field == "portraitClassificationBorder" or field:match("^portraitDecoration") or field:match("^portrait%.decoration") then return "portraitDecoration", L["UFPortraitDecorations"] end
				if data.navigationTab == "portraitPosition" or section == L["Position"] then return "portraitPosition", L["Position"] end
				if section == L["Border"] or section == L["Separator"] then return "portraitBorder", L["Border"] end
				return "portraitGeneral", L["General"]
			end,
			totemFrame = function(data)
				if data.navigationTab == "totemIcon" then return "totemIcon", L["Icon"] end
				if data.navigationTab == "totemDuration" then return "totemDuration", L["Duration"] end
				if data.navigationTab == "totemName" then return "totemName", L["Name"] end
				return "totemGeneral", L["General"]
			end,
			cast = function(_, section)
				local tab = castSections[section]
				if tab then return tab[1], tab[2] end
				return "castBar", L["Bar"]
			end,
			dataBar = function(data)
				if data.navigationTab == "dataBarText" then return "dataBarText", L["Text"] end
				return "dataBarBar", L["Bar"]
			end,
			name = function(data)
				if data.navigationTab == "targetTargetName" then return "targetTargetName", L["UFToTFrame"] end
				return "name", _G.NAME or L["Name"]
			end,
			statusText = function(_, section)
				if section == L["Group number"] then return "groupNumber", L["Group number"] end
				return "statusText", L["Status text"]
			end,
		},
		visibilityHint = function(data)
			local hints = UF.ui.navigationHints
			return data.navigationHint or (hints and data.isShown and hints[data.isShown])
		end,
		reset = function(tab, applyDefaults)
			if UF.ui.RunSettingsReset then return UF.ui.RunSettingsReset(applyDefaults, tab) end
			local wasResetting = UF.ui.navigationResetting
			UF.ui.navigationResetting = true
			local ok, err = pcall(applyDefaults, tab)
			UF.ui.navigationResetting = wasResetting
			if not ok then error(err) end
		end,
	}
end
