local addon = _G.EnhanceQoL
local CP = addon.Aura.CooldownPanels
local Picker = CP.AddEntryPicker
local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL")
local Setup = {}
CP.EntrySetup = Setup

-- Keep drafts outside SavedVariables until the user confirms the selection.
function Setup:Refresh()
	local internal = addon.EditModeLib.internal
	if internal and internal.RefreshSettingValues then internal:RefreshSettingValues() end
end

function Setup:IsAura(row) return row.kind == "CDM_AURA" or row.kind == "PRESET" end

function Setup:CanBar(row) return row.kind ~= "SLOT" and row.kind ~= "STANCE" end

function Setup:GetDisplay(draft, panel)
	if CP.helper.IsFixedLayout(panel.layout) then return draft.display == "BAR" and "BAR" or "BUTTON" end
	return CP.helper.IsBarLayout(panel.layout) and "BAR" or "BUTTON"
end

function Setup:GetOptions(draft)
	local kind = draft.row.kind
	if kind == "PRESET" then kind = "CDM_AURA"
	elseif kind == "INTERNAL" or kind == "RACIAL" then kind = "SPELL"
	elseif kind == "TOTEMS_ALL" then kind = "TOTEM" end
	return CP.QuickSetups:GetOptions({ type = kind, displayMode = draft.display, slotID = draft.row.value,
		macroID = draft.row.value, macroName = draft.row.name })
end

function Setup:Close(back)
	addon.EditModeLib:HideStandaloneSettingsDialog(self.host)
	self.draft = nil
	if back and CP:GetPanel(self.sourcePanelId) then Picker:Open(self.sourcePanelId) end
end

function Setup:Fail(message)
	UIErrorsFrame:AddMessage(message or L["CooldownPanelPickerAddFailed"], 1, 0.3, 0.3)
	return false
end

function Setup:Commit()
	local draft = self.draft
	if not draft or InCombatLockdown() then return false end
	local panelId = self.sourcePanelId
	local panel = CP:GetPanel(panelId)
	if not panel then return self:Fail() end
	local display = self:GetDisplay(draft, panel)
	if display == "BAR" and not self:CanBar(draft.row) then return self:Fail() end
	local overlays = CP.ActionButtonOverlays
	local anchored = display == "BUTTON" and self:IsAura(draft.row) and draft.anchor ~= nil
	if anchored and (not overlays:IsButtonName(draft.anchor) or not _G[draft.anchor]) then return self:Fail() end
	Picker.targetId = panelId
	local previous = {}
	for id in pairs(panel.entries or {}) do previous[id] = true end
	if not self.add(Picker, draft.row) then return self:Fail() end
	local selectedId
	for _, id in ipairs(panel.order or {}) do
		local entry = panel.entries[id]
		if entry and not previous[id] then
			selectedId = selectedId or id
			entry.displayMode = display
			entry.actionButtonAnchor = anchored and draft.anchor or nil
			if display == "BAR" then
				entry.barMode = "COOLDOWN"
				CP.Bars.ApplyNewBarStyleDefaults(entry)
			elseif anchored then
				entry.actionButtonMatchSize, entry.actionButtonAutoLayer = true, true
				entry.iconOffsetX, entry.iconOffsetY = 0, 0
				entry.iconSizeUseGlobal = false
			end
			for _, option in ipairs(CP.QuickSetups:GetOptions(entry)) do
				if option.id == draft.preset then option.apply(panelId, id, false); break end
			end
			CP:RefreshEntryStyleMutation(panelId, id, entry, false)
		end
	end
	self:Close(false)
	CP:SelectPanel(panelId)
	if CP.runtime and CP.runtime.editor then CP.runtime.editor.selectedEntryId = selectedId end
	CP:RefreshEditor()
	Picker:Open(panelId)
	return true
end

function Setup:Choose(row)
	if InCombatLockdown() then return false end
	self.sourcePanelId = Picker.targetId
	local panel = CP:GetPanel(self.sourcePanelId)
	if not panel then return false end
	self.draft = { row = row, display = CP.helper.IsBarLayout(panel.layout) and "BAR" or "BUTTON", preset = "DEFAULT" }
	local draft = self.draft
	local types = addon.EditModeLib.SettingType
	self.host = self.host or CreateFrame("Frame", nil, UIParent)
	local function set(field, value)
		if self.draft ~= draft or InCombatLockdown() then return end
		draft[field] = value
		if field == "display" then draft.preset = "DEFAULT"; draft.anchor = nil end
		Setup:Refresh()
	end
	local settings = {
		{ name = row.name, kind = types.Divider },
		{ name = L["CooldownPanelSetupDisplay"], kind = types.Dropdown, navigationField = "setupDisplay", height = 120,
			isShown = function() return CP.helper.IsFixedLayout(panel.layout) and Setup:CanBar(row) end,
			get = function() return draft.display end, set = function(_, value) set("display", value) end,
			values = { { value = "BUTTON", text = L["Icon"] }, { value = "BAR", text = L["Bar"] } } },
		{ name = L["CooldownPanelSetupTemplate"], kind = types.Dropdown, navigationField = "setupTemplate", height = 280,
			get = function() return draft.preset end, set = function(_, value) set("preset", value) end,
			generator = function(_, root)
				root:CreateRadio(_G.DEFAULT, function() return draft.preset == "DEFAULT" end, function() set("preset", "DEFAULT") end)
				local groups = {}
				for _, option in ipairs(Setup:GetOptions(draft)) do
					local parent = root
					if option.group then
						groups[option.group] = groups[option.group] or root:CreateButton(option.group)
						parent = groups[option.group]
					end
					parent:CreateRadio(option.text, function() return draft.preset == option.id end, function() set("preset", option.id) end)
				end
			end },
		{ name = L["CooldownPanelActionButtonAnchor"], kind = types.Dropdown, navigationField = "setupAnchor", height = 260,
			isShown = function() return draft.display == "BUTTON" and Setup:IsAura(row) end,
			get = function() return draft.anchor or "NONE" end,
			set = function(_, value) set("anchor", value ~= "NONE" and value or nil) end,
			generator = function(_, root)
				CP.ActionButtonOverlays:GenerateButtonMenu(root, function() return draft.anchor end, function(value) set("anchor", value) end)
			end },
	}
	local dialog = addon.EditModeLib:ShowStandaloneSettingsDialog(self.host, {
		title = L["CooldownPanelSetupTitle"], settings = settings,
		showReset = false, showSettingsReset = false, settingsMaxHeight = 360,
		point = "CENTER", relativePoint = "CENTER", relativeTo = UIParent, x = 0, y = 0,
		buttons = {
			{ text = _G.ADD, click = function() Setup:Commit() end },
			{ text = _G.CANCEL, click = function() Setup:Close(true) end },
		},
		onHide = function() Setup.draft = nil end,
	})
	if not dialog then self.draft = nil; return false end
	Picker.selectingSetup = false
	Picker.frame:Hide()
	return true
end

Setup.add = Picker.Add
function Picker:Add(row)
	if self.selectingSetup then return Setup:Choose(row) end
	return Setup.add(self, row)
end
Setup.addByID = Picker.AddByID
function Picker:AddByID()
	if not self.selectingSetup then return Setup.addByID(self) end
	if not self:CanEdit() then return false end
	local id = tonumber(self.frame.idInput:GetText())
	if not id or id <= 0 or id ~= math.floor(id) then self.frame.status:SetText(L["CooldownPanelPickerInvalidID"]); return false end
	local kind = self.idType or "SPELL"
	local name = kind == "ITEM" and C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
		or kind ~= "ITEM" and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
	return Setup:Choose({ kind = kind, value = id, name = name or tostring(id) })
end
Setup.isAdded = Picker.IsAdded
function Picker:IsAdded(row)
	if self.selectingSetup then return false end
	return Setup.isAdded(self, row)
end
function Picker:GetButtonText() return self.selectingSetup and L["CooldownPanelSetupChoose"] or _G.ADD end

Setup.open = Picker.Open
function Picker:Open(panelId)
	self.selectingSetup = self.setupEnabled == true
	local frame = Setup.open(self, panelId)
	if not frame then return nil end
	if not frame.setupButton then
		frame.setupButton = self:CreateButton(frame, L["CooldownPanelSetupMode"], 148, 24)
		frame.setupButton:SetPoint("BOTTOMLEFT", 15, 10)
		frame.status:ClearAllPoints()
		frame.status:SetPoint("LEFT", frame.setupButton, "RIGHT", 12, 0)
		frame.status:SetPoint("RIGHT", frame.close, "LEFT", -12, 0)
		frame.setupButton:SetScript("OnClick", function()
			if not Picker:CanEdit() then return end
			Picker.setupEnabled = not Picker.setupEnabled
			Picker.selectingSetup = Picker.setupEnabled
			frame.setupButton:SetSelected(Picker.setupEnabled)
			frame.idAdd:SetText(Picker:GetButtonText())
			frame.status:SetText(Picker.setupEnabled and L["CooldownPanelSetupHint"] or "")
			Picker:Refresh()
		end)
	end
	frame.setupButton:SetSelected(self.setupEnabled)
	frame.idAdd:SetText(self:GetButtonText())
	if self.setupEnabled then frame.status:SetText(L["CooldownPanelSetupHint"]) end
	return frame
end
