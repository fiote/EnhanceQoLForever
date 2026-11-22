local addon = _G.EnhanceQoL or select(2, ...)
local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL")
local M = { limit = 255 }
addon.DrinkMacroCustom = M

function M.ActiveContext()
	local name, token, classID = UnitClass("player")
	local active
	if addon.functions.GetForeverPrimaryTalentGroup then
		active = addon.functions.GetForeverPrimaryTalentGroup()
	elseif addon.functions.GetPrimaryTalentTreeID then
		active = addon.functions.GetPrimaryTalentTreeID(false)
	else
		local api = C_SpecializationInfo
		local index = api and api.GetSpecialization and api.GetSpecialization()
		active = index and api.GetSpecializationInfo(index)
	end
	return token, active, name, classID
end

function M.Specs(classID)
	local specs = {}
	if addon.functions.GetForeverTalentGroups then
		for _, info in ipairs(addon.functions.GetForeverTalentGroups(classID)) do
			specs[#specs + 1] = { id = info.groupID, name = info.displayName, icon = info.icon }
		end
	elseif addon.functions.GetPrimaryTalentTreeID then
		-- Classic talent-tab queries describe the current player's class only.
		if classID == select(3, UnitClass("player")) then
			for index = 1, GetNumTalentTabs(false, false) do
				local id, label, icon = GetTalentTabInfo(index, false, false)
				specs[#specs + 1] = { id = id, name = label, icon = icon }
			end
		end
	else
		local api = C_SpecializationInfo
		local count = api and api.GetNumSpecializationsForClassID and api.GetNumSpecializationsForClassID(classID) or 0
		for i = 1, count do
			local id, label, _, icon = GetSpecializationInfoForClassID(classID, i)
			specs[#specs + 1] = { id = id, name = label, icon = icon }
		end
	end
	return specs
end

function M.Context()
	local token, active, name, classID = M.ActiveContext()
	return token, active, name, M.Specs(classID)
end

function M.BuildScopes()
	local playerClass, _, playerName, playerID = M.ActiveContext()
	local classes, seen = {}, {}
	for id = 1, math.max(13, GetNumClasses and GetNumClasses() or 0) do
		local name, token = GetClassInfo(id)
		if token then
			local specs = M.Specs(id)
			local supported = not addon.functions.GetForeverTalentGroups or #specs > 0
			if addon.TBC and addon.TBC.playerRoleByTalentTree then supported = addon.TBC.playerRoleByTalentTree[token] ~= nil end
			if supported or token == playerClass then
				classes[#classes + 1] = { key = token, label = name, specs = specs }
				seen[token] = true
			end
		end
	end
	if not seen[playerClass] then classes[#classes + 1] = { key = playerClass, label = playerName, specs = M.Specs(playerID) } end
	table.sort(classes, function(a, b) return a.label < b.label end)
	local scopes = { { key = "global", label = L["drinkCustomGlobal"] } }
	for _, class in ipairs(classes) do
		class.class = class.key
		class.iconLabel = addon.EntryPicker.GetClassMenuLabel(class.key, class.label)
		scopes[#scopes + 1] = class
		for _, spec in ipairs(class.specs) do
			if spec.id and spec.name then
				local icon = spec.icon and ("|T" .. spec.icon .. ":16:16:0:0:64:64:4:60:4:60|t ") or ""
				scopes[#scopes + 1] = { key = M.SpecKey(class.key, spec.id), class = class.key, label = spec.name, iconLabel = icon .. spec.name, isSpec = true }
			end
		end
	end
	return scopes
end

function M.IsCustomized(key)
	local frame = M.frame
	if frame and frame.scope == key and frame.dirty then
		if key ~= "global" then return frame.own:GetChecked() == true end
		return M.Normalize(frame.before:GetText()) ~= "" or M.Normalize(frame.after:GetText()) ~= ""
	end
	local rule = addon.db and addon.db.drinkMacroCustom and addon.db.drinkMacroCustom[key]
	if key ~= "global" then return type(rule) == "table" end
	return type(rule) == "table" and (M.Normalize(rule.before) ~= "" or M.Normalize(rule.after) ~= "") or false
end

function M.ScopeLabel(entry, includeSpecs)
	local customized = M.IsCustomized(entry.key)
	if includeSpecs and entry.class then
		for _, spec in ipairs(M.frame.scopes) do
			if spec.isSpec and spec.class == entry.class and M.IsCustomized(spec.key) then customized = true; break end
		end
	end
	return (entry.iconLabel or entry.label) .. (customized and " |TInterface\\Buttons\\UI-CheckBox-Check:16:16|t" or "")
end

function M.UpdateScopeLabel()
	local frame = M.frame
	local entry = frame.scopeEntries[frame.scope]
	if not entry then return end
	local label = M.ScopeLabel(entry)
	if entry.isSpec then label = frame.scopeEntries[entry.class].iconLabel .. " / " .. label end
	frame.scopePicker:OverrideText(label)
end

function M.BuildScopeMenu(root)
	local frame, menus = M.frame, {}
	root:SetScrollMode(360)
	for _, entry in ipairs(frame.scopes) do
		local menu = root
		if entry.isSpec then
			menu = menus[entry.class]
		elseif entry.class then
			menu = root:CreateButton(M.ScopeLabel(entry, true))
			menus[entry.class] = menu
		end
		menu:CreateRadio(M.ScopeLabel(entry), function() return frame.scope == entry.key end, function() M.SelectScope(entry.key) end)
		if entry.class and not entry.isSpec then menu:CreateDivider() end
	end
end

function M.SpecKey(class, spec) return class .. ":" .. tostring(spec) end

function M.GetRule(class, spec, db)
	db = db or (addon.db and addon.db.drinkMacroCustom) or {}
	local key = spec and M.SpecKey(class, spec)
	if key and db[key] then return db[key], key end
	if db[class] then return db[class], class end
	return db.global or {}, "global"
end

function M.Normalize(text)
	return (text or ""):gsub("\r\n", "\n"):gsub("\r", "\n"):match("^%s*(.-)%s*$")
end

function M.Compose(base, rule)
	local header, actions = base:match("^([^\n]+)\n?(.*)$")
	local parts = { header or "#showtooltip" }
	for _, value in ipairs({ M.Normalize(rule.before), actions or "", M.Normalize(rule.after) }) do
		if value ~= "" then parts[#parts + 1] = value end
	end
	return table.concat(parts, "\n")
end

function M.Apply(base)
	M.base = base
	if M.frame and M.frame:IsShown() then M.UpdatePreview() end
	if not (addon.db and addon.db.drinkMacroCustom) then return base end
	local class, spec = M.ActiveContext()
	local body = M.Compose(base, M.GetRule(class, spec))
	-- Never allow the client to truncate a generated action or a custom command.
	if #body > M.limit then return base end
	return body
end

function M.Refresh()
	if addon.functions.updateAvailableDrinks then addon.functions.updateAvailableDrinks(false) end
end

function M.Label(parent, text, x, y, width, template)
	local label = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
	label:SetPoint("TOPLEFT", x, y)
	label:SetWidth(width)
	label:SetJustifyH("LEFT")
	label:SetJustifyV("TOP")
	label:SetText(text)
	return label
end

function M.Button(parent, text, width, callback)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetSize(width, 26)
	button:SetText(text)
	button:SetScript("OnClick", callback)
	return button
end

function M.TextBox(parent, x, y, width, height, readOnly)
	local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	panel:SetPoint("TOPLEFT", x, y)
	panel:SetSize(width, height)
	panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	panel:SetBackdropColor(0.035, 0.045, 0.055, 1)
	panel:SetBackdropBorderColor(0.23, 0.28, 0.33, 1)
	local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 12, -10)
	scroll:SetPoint("BOTTOMRIGHT", -28, 10)
	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetJustifyH("LEFT")
	edit:SetJustifyV("TOP")
	edit:SetAutoFocus(false)
	edit:SetFontObject("ChatFontNormal")
	edit:SetWidth(width - 44)
	edit:SetHeight(height - 20)
	edit:SetMaxBytes(1024)
	edit:SetScript("OnEscapePressed", edit.ClearFocus)
	if readOnly then
		edit:SetScript("OnChar", function() edit:SetText(edit.value or "") end)
		edit:SetScript("OnTextChanged", function(self, user) if user then self:SetText(self.value or "") end end)
	end
	scroll:SetScrollChild(edit)
	edit.panel = panel
	return edit
end

function M.DraftRule()
	local frame = M.frame
	if frame.scope ~= "global" and not frame.own:GetChecked() then
		local class = frame.ruleClass or frame.class
		if frame.scope == class then return ((addon.db.drinkMacroCustom or {}).global or {}) end
		return M.GetRule(class, nil)
	end
	return { before = frame.before:GetText(), after = frame.after:GetText() }
end

function M.UpdatePreview()
	local frame = M.frame
	if not frame or frame.loading then return end
	M.UpdateScopeLabel()
	local body = M.Compose(M.base or "#showtooltip", M.DraftRule())
	frame.preview.value = body
	frame.preview:SetText(body)
	local tooLong = #body > M.limit
	frame.count:SetText(string.format(L["drinkCustomLength"], #body, M.limit))
	frame.count:SetTextColor(tooLong and 1 or 0.55, tooLong and 0.3 or 0.82, tooLong and 0.3 or 0.75)
	local combat = InCombatLockdown and InCombatLockdown()
	frame.save:SetEnabled(not tooLong and not combat)
	frame.status:SetText(combat and L["drinkCustomCombat"] or tooLong and L["drinkCustomTooLong"] or frame.dirty and L["drinkCustomUnsaved"] or L["drinkCustomSaved"])
end

function M.GetEditorRule(key, class)
	local stored = addon.db.drinkMacroCustom or {}
	if stored[key] then return stored[key] end
	if key == "global" then return {} end
	if key == class then return stored.global or {} end
	return M.GetRule(class, nil)
end

function M.LoadScope(key)
	local frame = M.frame
	frame.loading = true
	frame.scope = key
	frame.ruleClass = frame.scopeEntries[key] and frame.scopeEntries[key].class or frame.class
	local stored = addon.db.drinkMacroCustom or {}
	local rule = stored[key]
	frame.own:SetChecked(key == "global" or rule ~= nil)
	frame.own:SetEnabled(key ~= "global")
	rule = M.GetEditorRule(key, frame.ruleClass)
	frame.before:SetText(rule.before or "")
	frame.after:SetText(rule.after or "")
	local editable = key == "global" or stored[key] ~= nil
	for _, edit in ipairs({ frame.before, frame.after }) do
		edit:EnableMouse(editable)
		edit:EnableKeyboard(editable)
		edit:SetAlpha(editable and 1 or 0.45)
	end
	frame.addBefore:SetEnabled(editable)
	frame.addAfter:SetEnabled(editable)
	frame.dirty, frame.loading = false, false
	M.UpdateScopeLabel()
	frame.inherit:SetText(key == "global" and L["drinkCustomGlobalHint"] or L["drinkCustomInheritHint"])
	M.UpdatePreview()
end

function M.Save()
	local frame = M.frame
	if InCombatLockdown and InCombatLockdown() then return false end
	local rule = M.DraftRule()
	if #M.Compose(M.base or "#showtooltip", rule) > M.limit then return false end
	addon.db.drinkMacroCustom = addon.db.drinkMacroCustom or {}
	if frame.scope == "global" or frame.own:GetChecked() then
		addon.db.drinkMacroCustom[frame.scope] = { before = M.Normalize(rule.before), after = M.Normalize(rule.after) }
	else
		addon.db.drinkMacroCustom[frame.scope] = nil
	end
	M.Refresh()
	frame.dirty = false
	M.UpdatePreview()
	return true
end

function M.SelectScope(key)
	if key == M.frame.scope then return end
	if M.frame.dirty then
		StaticPopup_Show("EQOL_DRINK_CUSTOM_DISCARD", nil, nil, key)
	else
		M.LoadScope(key)
	end
end

function M.Pick(position)
	if not M.picker then
		M.picker = addon.EntryPicker:Create("DrinkMacro", {
			sourceKinds = { "SPELL", "ITEM" }, titleFormat = L["drinkCustomPickerTitle"],
			categories = {
				{ id = "ALL", label = _G.ALL },
				{ id = "SPELLS", label = addon.EntryPicker.GetTypeLabel("SPELL") },
				{ id = "ITEMS", label = addon.EntryPicker.GetTypeLabel("ITEM") },
				{ id = "ID", label = L["CooldownPanelPickerByID"] },
			},
		})
		function M.picker:GetTarget() return M.frame and M.frame:IsShown() and { name = L["drinkCustomTitle"] } end
		function M.picker:IsAdded(row) return row.overrides and row.overrides.trackPassiveSpell == true end
		function M.picker:TryAdd(row)
			local edit = M.frame[self.targetId]
			if not edit or not M.frame.own:GetChecked() then return false end
			local command
			if row.kind == "ITEM" then command = "/use item:" .. row.value
			else
				local name = C_Spell.GetSpellName(row.value)
				if not name then return false end
				command = "/cast " .. name
			end
			local text = M.Normalize(edit:GetText())
			edit:SetText(text == "" and command or text .. "\n" .. command)
			M.frame.dirty = true
			M.UpdatePreview()
			return true
		end
	end
	M.picker:Open(position)
end

function M.CreateEditor()
	local frame = CreateFrame("Frame", "EQOLDrinkMacroEditor", UIParent, "BackdropTemplate")
	M.frame = frame
	frame.scopes, frame.scopeEntries = {}, {}
	frame:Hide()
	frame:SetSize(920, 620)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	frame:SetBackdropColor(0.065, 0.08, 0.095, 1)
	frame:SetBackdropBorderColor(0.28, 0.4, 0.44, 1)
	M.Label(frame, L["drinkCustomTitle"], 24, -20, 820, "GameFontNormalLarge")
	M.Label(frame, L["drinkCustomIntro"], 24, -52, 865)
	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -5, -5)
	close:SetScript("OnClick", function() frame:Hide() end)
	M.Label(frame, L["drinkCustomScope"], 24, -96, 210, "GameFontNormal")
	frame.scopePicker = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
	frame.scopePicker:SetPoint("TOPLEFT", 240, -89)
	frame.scopePicker:SetWidth(400)
	frame.scopePicker:SetupMenu(function(_, root) M.BuildScopeMenu(root) end)
	frame.own = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
	frame.own:SetPoint("TOPLEFT", 20, -128)
	M.Label(frame, L["drinkCustomOwn"], 56, -137, 820)
	frame.inherit = M.Label(frame, "", 24, -171, 865)
	frame.own:SetScript("OnClick", function(self)
		local editable = self:GetChecked()
		for _, edit in ipairs({ frame.before, frame.after }) do
			edit:EnableMouse(editable)
			edit:EnableKeyboard(editable)
			edit:SetAlpha(editable and 1 or 0.45)
		end
		frame.addBefore:SetEnabled(editable)
		frame.addAfter:SetEnabled(editable)
		frame.dirty = true
		M.UpdatePreview()
	end)
	M.Label(frame, L["drinkCustomBefore"], 24, -217, 255, "GameFontNormal")
	frame.addBefore = M.Button(frame, L["drinkCustomAdd"], 175, function() M.Pick("before") end)
	frame.addBefore:SetPoint("TOPLEFT", 297, -207)
	frame.before = M.TextBox(frame, 24, -242, 448, 116)
	M.Label(frame, L["drinkCustomAfter"], 24, -380, 255, "GameFontNormal")
	frame.addAfter = M.Button(frame, L["drinkCustomAdd"], 175, function() M.Pick("after") end)
	frame.addAfter:SetPoint("TOPLEFT", 297, -370)
	frame.after = M.TextBox(frame, 24, -405, 448, 116)
	M.Label(frame, L["drinkCustomPreview"], 496, -217, 398, "GameFontNormal")
	frame.preview = M.TextBox(frame, 496, -242, 400, 279, true)
	frame.count = M.Label(frame, "", 496, -534, 400)
	M.Label(frame, L["drinkCustomSyntax"], 24, -534, 448)
	frame.status = M.Label(frame, "", 24, -580, 590)
	frame.status:SetTextColor(0.72, 0.77, 0.8)
	frame.cancel = M.Button(frame, _G.CANCEL, 115, function() frame:Hide() end)
	frame.cancel:SetPoint("BOTTOMRIGHT", -149, 18)
	frame.save = M.Button(frame, _G.SAVE, 115, M.Save)
	frame.save:SetPoint("BOTTOMRIGHT", -24, 18)
	for _, edit in ipairs({ frame.before, frame.after }) do
		edit:SetScript("OnTextChanged", function(_, user)
			if frame.loading or not user then return end
			frame.dirty = true
			M.UpdatePreview()
		end)
	end
	frame:SetScript("OnHide", function()
		frame.before:ClearFocus()
		frame.after:ClearFocus()
		if M.picker and M.picker.frame then M.picker.frame:Hide() end
	end)
	table.insert(UISpecialFrames, "EQOLDrinkMacroEditor")
	StaticPopupDialogs.EQOL_DRINK_CUSTOM_DISCARD = {
		text = L["drinkCustomDiscard"], button1 = _G.DISCARD or _G.ACCEPT, button2 = _G.CANCEL,
		timeout = 0, whileDead = true, hideOnEscape = true,
		OnAccept = function(_, key) if frame:IsShown() then M.LoadScope(key) end end,
	}
	return frame
end

function M.Open()
	if not addon.db then return end
	M.Refresh()
	local frame = M.frame or M.CreateEditor()
	if frame:IsShown() then frame:Raise(); return end
	local class, spec = M.ActiveContext()
	frame.class = class
	frame.scopes = M.BuildScopes()
	frame.scopeEntries = {}
	for _, entry in ipairs(frame.scopes) do frame.scopeEntries[entry.key] = entry end
	frame.scopePicker:GenerateMenu()
	local _, key = M.GetRule(class, spec)
	M.LoadScope(key)
	frame:SetScale(math.min(1, UIParent:GetWidth() / 960, UIParent:GetHeight() / 660))
	frame:Show()
	frame:Raise()
end

function M.RegisterSettings(category, section)
	addon.functions.SettingsCreateButton(category, {
		var = "drinkMacroCustomEditor", text = L["drinkCustomTitle"], desc = L["drinkCustomIntro"],
		newTagID = "drinkMacroCustomEditor", parentSection = section,
		func = M.Open, parentCheck = function() return addon.db and addon.db.drinkMacroEnabled == true end,
	})
end

M.events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_SPECIALIZATION_CHANGED", "PLAYER_TALENT_UPDATE", "ACTIVE_TALENT_GROUP_CHANGED", "TRAIT_CONFIG_UPDATED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
	M.events:RegisterEvent(event)
end
M.events:SetScript("OnEvent", function()
	-- Defer until the client context cache and talent state have been refreshed.
	if M.pending then return end
	M.pending = true
	C_Timer.After(0, function()
		M.pending = nil
		M.Refresh()
		if M.frame and M.frame:IsShown() then M.UpdatePreview() end
	end)
end)
