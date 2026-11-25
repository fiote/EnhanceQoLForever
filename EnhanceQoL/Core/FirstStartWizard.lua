local addonName, addon = ...
local L = LibStub("AceLocale-3.0"):GetLocale(addonName)

local wizard, startup, parkedFrame, returnToSettings
local world, shade, makeWorld
local liveSample, ownsEditMode, restoreDialog
local liveSamples = {}
local LESSON_LEVEL = 500
local WIDTH, CARD_WIDTH, CARD_GAP = 560, 252, 12
local ART = "Interface\\AddOns\\EnhanceQoL\\Assets\\NewSettings\\"
local HELP_ICON = "Interface\\common\\help-i"
local groups = {
	{
		label = "FirstStepsPractice",
		topics = {
			{ id = "frames", label = "Unit Frames", description = "FirstStepsTopicFrames", icon = "UnitFrames", setting = "ufEnablePlayer" },
			{ id = "resource", label = "Resource Bars", description = "FirstStepsTopicResource", icon = "BarsResources", setting = "enableResourceFrame" },
			{ id = "meter", label = "damageMeterTitle", description = "FirstStepsMeterIntro", icon = "DamageMeterProfile", setting = "damageMeterEnabled" },
			{ id = "cooldown", label = "Cooldown Panels", description = "FirstStepsTopicCooldown", icon = "CastbarsCooldowns", setting = "cooldownpanels.editorMacroHint" },
		},
	},
	{
		label = "Settings",
		topics = {
			{ id = "plates", label = "Nameplates", description = "nameplateQuestProgress", icon = "NameplatesNames", setting = "nameplateQuestProgress" },
		},
	},
}

local function getSetting(topic)
	local app = addon.ConfigApp
	local control = app and app.controlsByID[topic.setting]
	if control and app:IsControlVisible(control) then return control end
end

local function fill(frame, layer, inset, r, g, b, a)
	local texture = frame:CreateTexture(nil, layer)
	texture:SetPoint("TOPLEFT", inset, -inset)
	texture:SetPoint("BOTTOMRIGHT", -inset, inset)
	texture:SetColorTexture(r, g, b, a or 1)
	return texture
end

local function setLabel(button, label)
	button:SetText(label)
	button:SetWidth(math.max(72, button:GetTextWidth() + 24))
end

local function makeButton(parent, callback, primary)
	local button = CreateFrame("Button", nil, parent)
	button:SetHeight(29)
	if primary then
		fill(button, "BACKGROUND", 0, 0.31, 0.72, 0.62)
		fill(button, "BORDER", 1, 0.08, 0.34, 0.29)
	else
		fill(button, "BACKGROUND", 0, 0.26, 0.34, 0.36)
		fill(button, "BORDER", 1, 0.12, 0.16, 0.18)
	end
	button:SetHighlightTexture(fill(button, "HIGHLIGHT", 1, 0.42, 0.81, 0.71, 0.18))
	button:SetPushedTexture(fill(button, "ARTWORK", 1, 0, 0, 0.28))
	local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	label:SetPoint("CENTER")
	button:SetFontString(label)
	button:SetPushedTextOffset(0, -1)
	button:SetScript("OnClick", callback)
	return button
end

local function textAt(parent, font, x, y, width)
	local label = parent:CreateFontString(nil, "OVERLAY", font)
	label:SetPoint("TOPLEFT", x, -y)
	label:SetWidth(width)
	label:SetJustifyH("LEFT")
	return label
end

local meterResultsTopic = { id = "meter", setting = "damageMeterEnabled" }
local meterEditTopic = { id = "meterEdit", setting = "damageMeterEnabled" }
local hints = {
	meterEdit = {
		{ event = "select", sample = true, text = "FirstStepsLiveSelect" },
		{ event = "width", setting = 1, text = "FirstStepsLiveWidth" },
		{ event = "rowHeight", setting = 2, label = "damageMeterRowHeight" },
		{ event = "fight" },
	},
	meter = {
		{ event = "details", text = "FirstStepsTopicMeter" },
		{ event = "totals", text = "FirstStepsHintBreakdown" },
	},
	frames = {
		{ event = "select", sample = true, text = "FirstStepsLiveSelect" },
		{ event = "name", setting = 1, label = "Show name" },
		{ event = "power", setting = 2, text = "FirstStepsLivePower" },
		{ event = "width", setting = 3, text = "FirstStepsLiveWidth" },
		{ event = "drag", sample = true, text = "FirstStepsLiveMove" },
	},
	resource = {
		{ event = "select", sample = true, text = "FirstStepsLiveSelect" },
		{ event = "first", setting = 1, text = "FirstStepsLiveWidth" },
		{ event = "second", setting = 2, text = "FirstStepsLiveHeight" },
		{ event = "drag", sample = true, text = "FirstStepsLiveMove" },
	},

}

local function hideGuide(guide)
	guide:SetScript("OnUpdate", nil)
	guide.x, guide.y = nil, nil
	guide.target = nil
	guide:Hide()
end

local function placeGuide(f, x, y)
	local g = f.guide
	g.x, g.y = x, y
	g.marker:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x, y)
	g.bubble:SetPoint(
		"BOTTOMLEFT",
		f,
		"BOTTOMLEFT",
		math.max(10, math.min(f:GetWidth() - g.bubble:GetWidth() - 10, x + g.bubbleDX)),
		math.max(8, math.min(f:GetHeight() - g.bubble:GetHeight() - 8, y + g.bubbleDY))
	)
end

local function liveSettingRow(index)
	local dialog = addon.EditModeLib.internal.dialog
	if not (dialog:IsVisible() and dialog.context and dialog.context.frame == liveSample) then return end
	local nav = dialog.Navigation
	local setting = liveSample.lessonSettings[index]
	local entry = setting and nav and nav.model and nav.model.byData[setting]
	if not entry then return dialog end
	local row = nav.view.rows[setting]
	if row and row:IsVisible() then
		local upper, lower = nav.scroll:GetTop(), nav.scroll:GetBottom()
		local rowTop, rowBottom = row:GetTop(), row:GetBottom()
		if upper and lower and rowTop and rowBottom and rowTop <= upper and rowBottom >= lower then return row.Slider or row.Button end
		return nav.scroll, L["FirstStepsHintTry"]:format(setting.name)
	end
	for _, button in ipairs(nav.listButtons) do
		if button:IsVisible() and button.tab and button.tab.category == entry.tab.category then
			return button, L["FirstStepsHintTry"]:format(entry.tab.category.name)
		end
	end
	for _, button in ipairs(nav.tabButtons) do
		if button:IsVisible() and button.tab == entry.tab then
			return button, L["FirstStepsHintTry"]:format(entry.tab.label)
		end
	end
	return nav.back, L["FirstStepsHintTry"]:format(BACK or L["UFNavBack"])
end

local function refreshGuide(f)
	local g, state = f.guide, f.demo
	if not state then
		hideGuide(g)
		return
	end
	local step = hints[state.topic.id][state.guideStep]
	local canOpenSettings = not step and getSetting(state.topic) ~= nil
	f.settingsButton:SetShown(canOpenSettings)
	f.fightButton:SetShown(step and step.event == "fight" or false)
	local target, message
	if not step then
		target = canOpenSettings and f.settingsButton or f.backButton
		message = L[canOpenSettings and "FirstStepsHintSettings" or "FirstStepsLiveDone"]
	elseif step.event == "fight" then
		target, message = f.fightButton, L["FirstStepsHintTry"]:format(f.fightButton:GetText())
	elseif state.topic.id == "meter" then
		target = step.event == "details" and f.meter.rows[1] or f.meter.returnButton
		message = L[step.text]
	elseif step.sample then
		target, message = liveSample, L[step.text]
	elseif step.setting then
		target, message = liveSettingRow(step.setting)
		if target then
			message = message or (step.label and L["FirstStepsHintTry"]:format(L[step.label]) or L[step.text])
		else
			message = L["FirstStepsLiveSelect"]
		end
		target = target or liveSample
	end
	local left, bottom, width, height = target:GetRect()
	local fLeft, fBottom = f:GetRect()
	if not left or not fLeft or not target:IsVisible() then
		g:SetScript("OnUpdate", function() refreshGuide(f) end)
		g:Show()
		return
	end

	local scale = target:GetEffectiveScale() / f:GetEffectiveScale()
	left, bottom = left * scale - fLeft, bottom * scale - fBottom
	width, height = width * scale, height * scale
	local x = left + width + 5
	if x + g.marker:GetWidth() > f:GetWidth() - 8 then x = left - g.marker:GetWidth() - 5 end
	local y = bottom + (height - g.marker:GetHeight()) / 2
	local bubble = g.bubble
	bubble.label:SetText(message)
	bubble:SetHeight(bubble.label:GetStringHeight() + 18)
	g.bubbleDX = left - x
	g.bubbleDY = bottom + height + 9 - y
	if state.topic.id == "meter" and step then
		g.bubbleDY = f.meter:GetTop() - fBottom + 12 - y
	elseif bottom + height + 9 + bubble:GetHeight() > f:GetHeight() - 8 then
		g.bubbleDY = bottom - 9 - bubble:GetHeight() - y
	end
	g.focus:ClearAllPoints()
	g.focus:SetPoint("TOPLEFT", target, "TOPLEFT", -2, 2)
	g.focus:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 2, -2)
	g.target = target
	g:Show()
	local fromX, fromY = g.x, g.y
	if not fromX then
		fromX = f.infoButton:GetLeft() - fLeft
		fromY = f.infoButton:GetBottom() - fBottom
		placeGuide(f, fromX, fromY)
	end
	if math.abs(x - fromX) + math.abs(y - fromY) < 1 then
		placeGuide(f, x, y)
		g.marker:EnableMouse(true)
		g:SetScript("OnUpdate", nil)
		return
	end
	local elapsed = 0
	g.marker:EnableMouse(false)
	g:SetScript("OnUpdate", function(self, delta)
		elapsed = elapsed + delta
		local t = math.min(1, elapsed / 0.32)
		local ease = t * t * (3 - 2 * t)
		placeGuide(f, fromX + (x - fromX) * ease, fromY + (y - fromY) * ease)
		if t == 1 then
			g.marker:EnableMouse(true)
			self:SetScript("OnUpdate", nil)
		end
	end)
end

local function guideAction(f, event)
	local state = f.demo
	local step = state and hints[state.topic.id][state.guideStep]
	if not step or step.event ~= event then return end
	state.guideStep = state.guideStep + 1
	refreshGuide(f)
end

local function showPage(intro)
	local f = wizard
	f.startButton:SetShown(intro)
	f.title:SetText(L[intro and "FirstStepsTitle" or "FirstStepsTopicsTitle"])
	f.body:SetText(intro and (L["FirstStepsWelcomeBody"] .. "\n\n" .. L["FirstStepsDefaults"]) or L["FirstStepsTopicsBody"])
	local height = 134 + f.title:GetStringHeight() + f.body:GetStringHeight()
	if intro then
		for _, heading in ipairs(f.headings) do heading:Hide() end
		for _, card in pairs(f.cards) do card:Hide() end
	else
		height = height + f:LayoutTopics()
	end
	f:SetHeight(height)
	f:SetScale(math.min(1, (UIParent:GetWidth() - 12) / WIDTH, (UIParent:GetHeight() - 12) / height))
	f:Show()
end

local function resumeTopics()
	C_Timer.After(0, function()
		if parkedFrame or (world and world.demo) then return end
		if InCombatLockdown() then
			wizard:RegisterEvent("PLAYER_REGEN_ENABLED")
		else
			showPage(false)
		end
	end)
end

local function positionLessonSample(frame, dialog, afterDrag)
	local screenWidth = UIParent:GetWidth()
	local dialogWidth = dialog:GetWidth() * dialog:GetEffectiveScale() / UIParent:GetEffectiveScale()
	local gap = 38
	local margin = math.max(16, (screenWidth - dialogWidth - gap - 700) / 2)
	local available = math.max(1, screenWidth - dialogWidth - gap - 2 * margin)
	local scale = math.min(1, available / frame:GetWidth())
	local y = 0
	if afterDrag then
		local right = frame:GetRight() * frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
		if right <= UIParent:GetRight() - dialogWidth - gap - margin then return end
		local _, centerY = frame:GetCenter()
		local _, parentY = UIParent:GetCenter()
		y = centerY * frame:GetEffectiveScale() / UIParent:GetEffectiveScale() - parentY
	end
	frame:SetScale(scale)
	frame:ClearAllPoints()
	frame:SetPoint("RIGHT", UIParent, "RIGHT", -(dialogWidth + gap + margin) / scale, y / scale)
	if restoreDialog then
		dialog:SetPoint("RIGHT", UIParent, "RIGHT", -margin * UIParent:GetEffectiveScale() / dialog:GetEffectiveScale(), 0)
	end
end

local function showLessonDialog(dialog)
	if restoreDialog then return end
	local strata, level, movable = dialog:GetFrameStrata(), dialog:GetFrameLevel(), dialog:IsMovable()
	local points = {}
	for index = 1, dialog:GetNumPoints() do points[index] = { dialog:GetPoint(index) } end
	restoreDialog = function()
		dialog:SetFrameStrata(strata)
		dialog:SetFrameLevel(level)
		dialog:SetMovable(movable)
		dialog:ClearAllPoints()
		for _, point in ipairs(points) do dialog:SetPoint(unpack(point)) end
		restoreDialog = nil
	end
	dialog:SetFrameStrata("TOOLTIP")
	dialog:SetFrameLevel(LESSON_LEVEL + 10)
	dialog:SetMovable(false)
	dialog:ClearAllPoints()
	positionLessonSample(liveSample, dialog)
end

local function discardExercise(closeEditMode)
	if not (world and world.demo) then return end
	local live = world.demo.live
	local close = closeEditMode and ownsEditMode
	world.demo, ownsEditMode = nil, nil
	if live then
		addon.EditModeLib:HideSettingsDialog(liveSample)
		if restoreDialog then restoreDialog() end
		liveSample:Hide()
	end
	if world.meter then world.meter:Hide() end
	hideGuide(world.guide)
	world:Hide()
	shade:Hide()
	if close and EditModeManagerFrame and EditModeManagerFrame:IsShown() then
		if HideUIPanel then HideUIPanel(EditModeManagerFrame) else EditModeManagerFrame:Hide() end
	end
end

local function finishExercise()
	discardExercise(true)
	resumeTopics()
end

local function parkForFrame(frame)
	parkedFrame = frame
	if not frame._eqolFirstStepsHooked then
		frame._eqolFirstStepsHooked = true
		frame:HookScript("OnHide", function(self)
			if parkedFrame ~= self or self:IsShown() then return end
			parkedFrame = nil
			if shade then shade:Hide() end
			resumeTopics()
		end)
	end
	wizard:Hide()
end

local function openTopicSettings(topic)
	local setting = getSetting(topic)
	if not setting or InCombatLockdown() then return end
	discardExercise(true)
	if addon.functions.OpenConfigCenter(setting.pageID, setting.id) then
		parkForFrame(addon.ConfigCenterFrame)
	else
		showPage(false)
	end
end

local function createLiveSample(lib, topic, feature)
	local resource = topic.id == "resource"
	local meter = topic.id == "meterEdit"
	-- The selection library moves and edits this temporary frame without creating profile data.
	local frame = meter and feature:CreateFirstStartPreview(UIParent) or CreateFrame("Frame", resource and "EnhanceQoLFirstStartResourceSample" or "EnhanceQoLFirstStartLiveSample", UIParent)
	frame:Hide()
	frame:SetFrameStrata("TOOLTIP")
	frame:SetFrameLevel(LESSON_LEVEL + 5)
	frame:SetClampedToScreen(true)
	frame.editModeName = L[meter and "damageMeterTitle" or resource and "AutoEnableMain" or "UFPlayerFrame"]
	if resource then
		local bar = CreateFrame("StatusBar", nil, frame)
		bar:SetAllPoints()
		bar:SetMinMaxValues(0, 100)
		bar:SetValue(70)
		fill(bar, "BACKGROUND", 0, 0.08, 0.11, 0.12)
		local label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		label:SetPoint("CENTER")
		feature.StyleFirstStartManaPreview(bar, label)
	elseif not meter then
		frame.preview = addon.Aura.UFHelper.CreateFirstStartPlayerPreview(frame)
	end

	lib:AddFrame(frame, function()
		if world.demo and world.demo.live and liveSample == frame then
			if restoreDialog then positionLessonSample(frame, lib.internal.dialog, true) end
			guideAction(world, "drag")
			refreshGuide(world)
		end
	end, { showReset = false, showSettingsReset = false, overlayColor = { 0.85, 0.66, 0.26 } })
	local dialog = lib.internal.dialog
	local selection = lib.selectionRegistry[frame]
	local function onSelect()
		if not (liveSample == frame and world.demo and world.demo.live and dialog.context and dialog.context.frame == frame) then return end
		showLessonDialog(dialog)
		selection.labelHidden = true
		if selection.Label then selection.Label:SetAlpha(0) end
		if selection.Text then selection.Text:SetAlpha(0) end
		local nav = dialog.Navigation
		if nav and world.demo.guideStep == 1 and (nav.tabId or nav.search:GetText() ~= "") then
			nav.returnQuery = nil
			nav:SetSearchText("")
			nav:Back()
		end
		if nav and not nav.firstStartGuideHooked then
			nav.firstStartGuideHooked = true
			local function onNavigation()
				if world.demo and world.demo.live and nav.enabled and nav.hostFrame == liveSample then refreshGuide(world) end
			end
			hooksecurefunc(nav, "Render", onNavigation)
			nav.scroll:HookScript("OnVerticalScroll", function()
				if not nav.rendering then onNavigation() end
			end)
		end
		guideAction(world, "select")
		refreshGuide(world)
	end
	dialog:HookScript("OnShow", onSelect)
	selection:SetFrameStrata("TOOLTIP")
	selection:SetFrameLevel(LESSON_LEVEL + 8)
	selection:EnableMouse(true)
	selection:HookScript("OnMouseDown", onSelect)
	dialog:HookScript("OnHide", function()
		if liveSample ~= frame then return end
		if restoreDialog then restoreDialog() end
		if world.demo and world.demo.live then refreshGuide(world) end
	end)
	lib:RegisterCallback("exit", function()
		if not (world.demo and world.demo.live) then return end
		discardExercise(false)
		resumeTopics()
	end)
	return frame
end

local function copyMenuData(value)
	if type(value) == "table" then
		local copy = {}
		for key, item in pairs(value) do
			if type(key) == "number" or type(key) == "string" then copy[key] = copyMenuData(item) end
		end
		return copy
	end
	if type(value) == "string" or type(value) == "number" or type(value) == "boolean" then return value end
end

local function buildLessonMenu(settings, bindings)
	local selected = {}
	local preview = {}
	local types = addon.EditModeLib.SettingType
	for _, data in ipairs(settings) do
		-- Keep the real menu structure but never forward a profile callback to the exercise.
		local row = copyMenuData(data)
		if row.kind == types.Dropdown or row.kind == types.SoundDropdown or row.kind == types.DropdownColor then row.values = row.values or {} end
		local binding = bindings[data.parentId] and (bindings[data.parentId][data.field or data.name] or bindings[data.parentId][data.navigationField])
		row.get = function() return row.default end
		row.set = function() end
		row.isEnabled = function() return false end
		row.navigationResetExcluded = true
		if binding then
			row.get = binding.get
			row.set = binding.set
			row.isEnabled = nil
			selected[binding.index] = row
		end
		preview[#preview + 1] = row
	end
	return preview, selected
end

local function lessonBinding(index, event, get, set)
	return {
		index = index,
		get = get,
		set = function(_, value)
			set(value)
			guideAction(world, event)
		end,
	}
end

local function showExercise(topic)
	if not world then world = makeWorld() end
	world.demo = { topic = topic, guideStep = 1, live = topic.id ~= "meter" }
	world.settingsButton:Hide()
	shade:Show()
	world:Show()
	wizard:Hide()
end

local function openLiveExample(topic)
	local lib = addon.EditModeLib
	local alreadyOpen = EditModeManagerFrame and EditModeManagerFrame:IsShown()
	local resource = topic.id == "resource"
	local meter = topic.id == "meterEdit"
	local feature = meter and addon.DamageMeter or addon.Aura and addon.Aura[resource and "ResourceBars" or "UF"]
	if InCombatLockdown() or not lib or not feature or not addon.functions.OpenEditMode() then
		if UIErrorsFrame then UIErrorsFrame:AddMessage(L["FirstStepsLiveUnavailable"], 1, 0.4, 0.2) end
		return
	end
	if not lib:IsInEditMode() then return end
	if not world then world = makeWorld() end
	local frame = liveSamples[topic.id]
	if not frame then
		frame = createLiveSample(lib, topic, feature)
		liveSamples[topic.id] = frame
	end
	liveSample = frame
	frame:SetScale(1)
	local settings, navigation, bindings
	if meter then
		frame:ResetEditPreview()
		settings = feature:BuildWindowSettings(1)
		navigation = addon.EditModeNavigationProfiles.Get("EQOL_DamageMeter1", { settings = settings })
		local function binding(index, field)
			return lessonBinding(index, field, function() return frame:GetPreviewValue(field) end, function(value)
				frame:SetPreviewValue(field, value)
				positionLessonSample(frame, lib.internal.dialog)
			end)
		end
		bindings = { damageMeterLayout1 = { width = binding(1, "width") }, damageMeterBar1 = { rowHeight = binding(2, "rowHeight") } }
	elseif resource then
		frame:SetSize(feature.DEFAULT_POWER_WIDTH, feature.DEFAULT_POWER_HEIGHT)
		settings, navigation = feature.BuildFirstStartSettings(frame)
		bindings = {
			frame = {
				width = lessonBinding(1, "first", function() return frame:GetWidth() end, function(value)
					frame:SetWidth(value)
					positionLessonSample(frame, lib.internal.dialog)
				end),
				height = lessonBinding(2, "second", function() return frame:GetHeight() end, function(value) frame:SetHeight(value) end),
			},
		}
	else
		local cfg = CopyTable(feature.defaults.player)
		local function render() feature.RenderFirstStartPlayerPreview(frame.preview, cfg) end
		render()
		settings, navigation = feature.BuildFirstStartPlayerSettings()
		bindings = {
			name = { [L["Show name"]] = lessonBinding(1, "name", function() return cfg.status.enabled ~= false end, function(value) cfg.status.enabled = value; render() end) },
			power = { [L["Show power bar"]] = lessonBinding(2, "power", function() return cfg.power.enabled ~= false end, function(value) cfg.power.enabled = value; render() end) },
			frame = { [L["UFWidth"]] = lessonBinding(3, "width", function() return cfg.width end, function(value)
					cfg.width = value
					render()
					positionLessonSample(frame, lib.internal.dialog)
				end) },
		}
	end
	positionLessonSample(frame, lib.internal.dialog)
	frame.settings, frame.lessonSettings = buildLessonMenu(settings, bindings)
	-- A practice click should move the edge by several visible pixels.
	if meter then frame.lessonSettings[1].valueStep = 5 end
	navigation.canReset = false
	navigation.reset = nil
	navigation.visibilityHint = nil
	lib:AddFrameSettings(frame, frame.settings)
	lib:SetFrameSettingsNavigation(frame, navigation)

	ownsEditMode = not alreadyOpen
	showExercise(topic)
	frame:Show()
	local selection = lib.selectionRegistry[frame]
	selection.labelHidden = false
	selection.systemBaseName = L["FirstStepsLiveTitle"]
	if selection.Label then selection.Label:SetAlpha(1) end
	if selection.Text then selection.Text:SetAlpha(1) end
	selection:ShowHighlighted()
	refreshGuide(world)
end

local function openMeterResults()
	if InCombatLockdown() or not addon.DamageMeter or not addon.DamageMeter.CreateFirstStartPreview then return end
	local width, height = liveSample:GetPreviewValue("width"), liveSample:GetPreviewValue("rowHeight")
	discardExercise(true)
	showExercise(meterResultsTopic)
	if not world.meter then
		world.meter = addon.DamageMeter:CreateFirstStartPreview(world, function(event) guideAction(world, event) end)
	end
	world.meter:ResetPreview(width, height)
	world.meter:Show()
	refreshGuide(world)
end

local function openCooldownTour()
	if InCombatLockdown() then return end
	local panels = addon.Aura and addon.Aura.CooldownPanels
	local frame = panels and panels.OpenBlizzardEditor and panels:OpenBlizzardEditor()
	if not frame then return end
	parkForFrame(frame)
	if frame.editorGuide then frame.editorGuide:Go(1) end
end

local function layoutTopics(f)
	local offset = 0
	for i, group in ipairs(groups) do
		local heading = f.headings[i]
		heading:ClearAllPoints()
		heading:SetPoint("TOPLEFT", f.body, "BOTTOMLEFT", 0, -17 - offset)
		heading:Show()
		offset = offset + heading:GetStringHeight() + 9
		for first = 1, #group.topics, 2 do
			local height = 70
			local last = math.min(first + 1, #group.topics)
			for index = first, last do
				local card = f.cards[group.topics[index].id]
				height = math.max(height, 44 + card.description:GetStringHeight())
			end
			for index = first, last do
				local topic = group.topics[index]
				local card = f.cards[topic.id]
				card:SetPoint("TOPLEFT", f.body, "BOTTOMLEFT", (index - first) * (CARD_WIDTH + CARD_GAP), -17 - offset)
				card:SetHeight(height)
				card:SetEnabled(getSetting(topic) ~= nil)
				card:SetAlpha(card:IsEnabled() and 1 or 0.55)
				card:Show()
			end
			offset = offset + height + 8
		end
		offset = offset + 4
	end
	return offset
end

local function makeCard(f, topic)
	local action = topic.id == "cooldown" and openCooldownTour or function()
		if topic.id == "meter" then
			openLiveExample(meterEditTopic)
		elseif topic.id == "frames" or topic.id == "resource" then
			openLiveExample(topic)
		else
			openTopicSettings(topic)
		end
	end
	local card = makeButton(f, action)
	card:SetSize(CARD_WIDTH, 70)
	local icon = card:CreateTexture(nil, "ARTWORK")
	icon:SetSize(26, 26)
	icon:SetPoint("TOPLEFT", 11, -7)
	icon:SetTexture(ART .. topic.icon .. ".tga")
	local title = card:GetFontString()
	title:ClearAllPoints()
	title:SetPoint("TOPLEFT", 45, -8)
	title:SetSize(CARD_WIDTH - 54, 25)
	title:SetJustifyH("LEFT")
	card:SetText(L[topic.label])
	card.description = textAt(card, "GameFontHighlightSmall", 11, 36, CARD_WIDTH - 22)
	card.description:SetText(L[topic.description])
	return card
end

local function makeGuide(f)
	local function showHint()
		refreshGuide(f)
	end
	f.infoButton = CreateFrame("Button", nil, f)
	f.infoButton:SetSize(28, 28)
	f.infoButton:SetPoint("TOPRIGHT", -27, -80)
	f.infoButton:SetNormalTexture(HELP_ICON)
	f.infoButton:SetScript("OnClick", showHint)
	f.infoButton:SetScript("OnEnter", function(button)
		GameTooltip:SetOwner(button, "ANCHOR_BOTTOMLEFT")
		GameTooltip:SetText(L["FirstStepsHintToggle"])
		GameTooltip:Show()
	end)
	f.infoButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

	local guide = CreateFrame("Frame", nil, f)
	guide:SetAllPoints()
	guide:SetFrameStrata("TOOLTIP")
	guide:SetFrameLevel(LESSON_LEVEL + 20)
	guide:EnableMouse(false)
	guide:Hide()
	guide.marker = CreateFrame("Button", nil, guide)
	guide.marker:SetSize(26, 26)
	guide.marker:SetNormalTexture(HELP_ICON)
	guide.marker:SetScript("OnClick", showHint)

	local focus = CreateFrame("Frame", nil, guide)
	focus:EnableMouse(false)
	for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
		local edge = focus:CreateTexture(nil, "OVERLAY")
		edge:SetColorTexture(1, 0.78, 0.28, 0.95)
		if side == "TOP" or side == "BOTTOM" then
			edge:SetPoint(side .. "LEFT")
			edge:SetPoint(side .. "RIGHT")
			edge:SetHeight(1)
		else
			edge:SetPoint("TOP" .. side)
			edge:SetPoint("BOTTOM" .. side)
			edge:SetWidth(1)
		end
	end
	guide.focus = focus

	local bubble = CreateFrame("Frame", nil, guide)
	bubble:SetWidth(224)
	bubble:EnableMouse(false)
	fill(bubble, "BACKGROUND", 0, 0.87, 0.64, 0.24)
	fill(bubble, "BORDER", 1, 0.12, 0.09, 0.05, 0.99)
	bubble.label = textAt(bubble, "GameFontHighlight", 10, 9, 204)
	guide.bubble = bubble
	return guide
end

makeWorld = function()
	shade = CreateFrame("Frame", nil, UIParent)
	shade:SetAllPoints()
	shade:SetFrameStrata("TOOLTIP")
	shade:SetFrameLevel(LESSON_LEVEL)
	shade:EnableMouse(true)
	fill(shade, "BACKGROUND", 0, 0.015, 0.018, 0.022, 0.76)
	shade:Hide()
	shade:RegisterEvent("PLAYER_REGEN_DISABLED")
	shade:SetScript("OnEvent", function(self)
		if not self:IsShown() then return end
		discardExercise(false)
		resumeTopics()
	end)

	local f = CreateFrame("Frame", "EnhanceQoLFirstStartWorld", UIParent)
	f:SetAllPoints()
	f:SetFrameStrata("TOOLTIP")
	f:SetFrameLevel(LESSON_LEVEL + 2)
	f:Hide()
	f:SetScript("OnHide", function(self)
		if self.demo and not self:IsShown() then finishExercise() end
	end)
	f.backButton = makeButton(f, finishExercise)
	setLabel(f.backButton, L["FirstStepsBackToTopics"])
	f.backButton:SetPoint("BOTTOM", f, "BOTTOM", 0, 34)
	f.settingsButton = makeButton(f, function() openTopicSettings(f.demo.topic) end, true)
	setLabel(f.settingsButton, L["FirstStepsDemoSettings"])
	f.settingsButton:SetPoint("LEFT", f.backButton, "RIGHT", 12, 0)
	f.fightButton = makeButton(f, openMeterResults, true)
	setLabel(f.fightButton, L["FirstStepsMeterFight"])
	f.fightButton:SetPoint("LEFT", f.backButton, "RIGHT", 12, 0)
	f.fightButton:Hide()
	f.guide = makeGuide(f)
	tinsert(UISpecialFrames, f:GetName())
	return f
end

local function enlargeGuideFont(label, minimum, increase)
	local font, size, flags = label:GetFont()
	label:SetFont(font, math.max(minimum, size + increase), flags)
	label:SetTextHeight(math.max(minimum, size + increase))
end

local function createWizard()
	local f = CreateFrame("Frame", "EnhanceQoLFirstStartWizard", UIParent)
	f:Hide()
	f:SetSize(WIDTH, 300)
	f:SetPoint("CENTER")
	f:SetClampedToScreen(true)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:EnableMouse(true)
	fill(f, "BACKGROUND", 0, 0.29, 0.35, 0.36)
	fill(f, "BORDER", 1, 0.055, 0.073, 0.083, 0.98)

	local icon = f:CreateTexture(nil, "ARTWORK")
	icon:SetSize(30, 30)
	icon:SetPoint("TOPLEFT", 20, -8)
	icon:SetTexture("Interface\\AddOns\\EnhanceQoL\\Icons\\Icon.tga")
	local header = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	header:SetPoint("LEFT", icon, "RIGHT", 10, 0)
	header:SetText(addonName)
	header:SetTextColor(1, 0.92, 0.76)
	header:SetShadowColor(0, 0, 0, 0.95)
	header:SetShadowOffset(1, -1)
	local line = f:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(0.20, 0.40, 0.37)
	line:SetPoint("TOPLEFT", 22, -40)
	line:SetPoint("TOPRIGHT", -22, -40)
	line:SetHeight(1)
	f.title = textAt(f, "GameFontNormalLarge", 22, 55, WIDTH - 44)
	enlargeGuideFont(f.title, 21, 4)
	f.body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	enlargeGuideFont(f.body, 16, 3)
	f.body:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -10)
	f.body:SetWidth(WIDTH - 44)
	f.body:SetJustifyH("LEFT")
	f.body:SetSpacing(4)
	f.LayoutTopics = layoutTopics

	f.headings, f.cards = {}, {}
	for i, group in ipairs(groups) do
		local heading = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		heading:SetText(L[group.label])
		heading:SetTextColor(0.56, 0.88, 0.78)
		f.headings[i] = heading
		for _, topic in ipairs(group.topics) do f.cards[topic.id] = makeCard(f, topic) end
	end
	local rule = f:CreateTexture(nil, "ARTWORK")
	rule:SetColorTexture(0.20, 0.25, 0.26)
	rule:SetPoint("BOTTOMLEFT", 1, 56)
	rule:SetPoint("BOTTOMRIGHT", -1, 56)
	rule:SetHeight(1)
	f.startButton = makeButton(f, function() showPage(false) end, true)
	enlargeGuideFont(f.startButton:GetFontString(), 14, 2)
	f.startButton:SetHeight(33)
	setLabel(f.startButton, L["FirstStepsStart"])
	f.startButton:SetPoint("BOTTOMRIGHT", -20, 15)
	f.skipButton = makeButton(f, function() f:Hide() end)
	enlargeGuideFont(f.skipButton:GetFontString(), 14, 2)
	f.skipButton:SetHeight(33)
	setLabel(f.skipButton, L["FirstStepsSkip"])
	f.skipButton:SetPoint("BOTTOMLEFT", 20, 15)
	f:SetScript("OnHide", function(self)
		if self:IsShown() then return end
		if parkedFrame or (world and world.demo) then return end
		local settings = returnToSettings
		returnToSettings = nil
		if settings then settings:Show() end
	end)
	f:SetScript("OnEvent", function(self)
		self:UnregisterEvent("PLAYER_REGEN_ENABLED")
		showPage(false)
	end)
	tinsert(UISpecialFrames, f:GetName())
	return f
end

function addon.functions.OpenFirstStartWizard()
	parkedFrame = nil
	discardExercise(true)
	if shade then shade:Hide() end
	local settings = addon.ConfigCenterFrame
	if settings and settings:IsShown() then
		returnToSettings = settings
		settings:Hide()
	end
	if not wizard then wizard = createWizard() end
	wizard:UnregisterEvent("PLAYER_REGEN_ENABLED")
	showPage(true)
	if EnhanceQoLDB then EnhanceQoLDB.firstStartGuidePending = nil end
	return wizard
end

function addon.functions.QueueFirstStartWizard(fresh)
	if fresh then EnhanceQoLDB.firstStartGuidePending = true end
	if not EnhanceQoLDB.firstStartGuidePending then return end
	if not startup then startup = CreateFrame("Frame") end
	startup:RegisterEvent("PLAYER_ENTERING_WORLD")
	startup:SetScript("OnEvent", function(self)
		self:UnregisterAllEvents()
		if not EnhanceQoLDB.firstStartGuidePending then return end
		if InCombatLockdown() then
			self:RegisterEvent("PLAYER_REGEN_ENABLED")
		else
			addon.functions.OpenFirstStartWizard()
		end
	end)
end
