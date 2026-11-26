local parentAddonName = "EnhanceQoL"
local addon = _G[parentAddonName]
if not addon then error(parentAddonName .. " is not loaded") end
local L = LibStub("AceLocale-3.0"):GetLocale(parentAddonName)
local Panels = addon.Aura.CooldownPanels
local Helper = Panels.helper
local Navigation = {}
Panels.Navigation = Navigation

local function fields(text)
	local result = {}
	for field in text:gmatch("%S+") do result[#result + 1] = field end
	return result
end
local scopes = {
	Display = fields("requiredTalentSpellID specFilter classFilter foreverUseSpecFilter foreverTalentFilter stanceFilter equipmentSetFilter"),
	Layout = fields("barPanelOrientation barPanelWidth barPanelHeight panelWidthMode panelWidth panelWidthSource panelWidthElement spacing direction wrapCount wrapDirection growthPoint radialRadius radialRotation radialArcDegrees strata rowSizes"),
	Icon = fields("actionButtonAnchor actionButtonMatchSize actionButtonAutoLayer actionButtonStrata actionButtonFrameLevel actionButtonLevelOffset barPanelIconSize iconSize iconSizeSeparate iconWidth iconHeight iconOffsetX iconOffsetY iconSizeUseGlobal showIconTexture showIconTextureUseGlobal hideIcon iconShape iconZoom showCraftingQuality showCraftingQualityUseGlobal craftingQualityScale"),
	Border = fields("iconBorderEnabled iconBorderTexture iconBorderSize iconBorderOffset iconBorderColor"),
	Visibility = fields("showTooltips tooltipUseEditModePosition hideOnCooldown showOnCooldown cdmAuraAlwaysShowMode cdmAuraMissingOnlyMyOwn cdmAuraAlwaysShowUseGlobal cooldownVisibilityUseGlobal hideBorderOnCooldown hideBorderOffCooldown visibility hideInVehicle hideInPetBattle hideInClientScene opacityOutOfCombat opacityInCombat heroSpecID heroSpecFilter heroSpecEnabled"),
	Availability = fields("rangeOverlayEnabled rangeOverlayColor noDesaturation noDesaturationUseGlobal checkPower checkPowerUseGlobal powerTintColor hideWhenNoResource hideWhenNoResourceUseGlobal"),
	CooldownText = fields("showCooldownText showCooldownTextUseGlobal cooldownTextUseGlobal cooldownTextFont cooldownTextSize cooldownTextStyle cooldownTextColor cooldownTextX cooldownTextY"),
	StaticText = fields("staticText staticTextShowOnCooldown staticTextUseGlobal staticTextFont staticTextSize staticTextStyle staticTextColor staticTextAnchor staticTextX staticTextY"),
	Stacks = fields("showItemCount showItemUses showStacks showStacksUseGlobal stackStyleUseGlobal stackAnchor stackX stackY stackFont stackFontSize stackFontStyle stackColor"),
	Charges = fields("showCharges showChargesUseGlobal chargesStyleUseGlobal chargesAnchor chargesX chargesY chargesFont chargesFontSize chargesFontStyle chargesColor chargesHideWhenZero"),
	Keybinds = fields("keybindsEnabled keybindsIgnoreItems keybindAnchor keybindX keybindY keybindFont keybindFontStyle keybindFontSize"),
	CooldownSwipe = fields("cooldownVisualsUseGlobal showChargesCooldown hideChargeCooldownText cooldownDrawEdge cooldownDrawBling cooldownDrawSwipe cooldownSwipeColor cooldownGcdDrawEdge cooldownGcdDrawBling cooldownGcdDrawSwipe"),
	Glow = fields("glowReady glowReadyUseGlobal glowUseGlobal readyGlowCheckPower readyGlowCheckPowerUseGlobal readyGlowStyle readyGlowInset readyGlowColor readyGlowUseClassColor glowUseClassColor glowStyle glowInset glowColor glowDuration readyGlowDuration hideGlowOutOfCombat interruptGlow glowOtherAura glowOtherAuraColor glowPixelCount glowPixelSpeed glowPixelThickness glowPixelBorder procGlowEnabled procGlowUseGlobal procGlowStyle procGlowInset procGlowColor pandemicGlow pandemicGlowStyle pandemicGlowInset pandemicGlowColor auraDurationThresholdShowEnabled auraDurationThresholdGlowEnabled auraDurationThresholdAsSeconds auraDurationThresholdMaxDuration auraDurationThresholdValue auraDurationThresholdGlowStyle auraDurationThresholdGlowColor"),
	AuraBehavior = fields("cdmAuraOverlayEnabled cdmAuraOverlayColor activationOverlayDrawSwipe activationOverlayDrawEdge activationOverlayReverse activationOverlayDesaturate activationOverlayOnly activationOverlayGlow activationOverlayGlowColor"),
	Activation = fields("cdmAuraOverlayEnabledUseGlobal cdmAuraOverlayEnabled cdmAuraOverlayUnit cdmAuraOverlayTargetPlayerOnly cdmAuraOverlaySpellIDs cdmAuraOverlayHideIcon autoCooldownDurationEnabled customCooldownDurationEnabled customCooldownDurationOnCooldownEnabled customCooldownDurationOnCooldownMultipleStacks customCooldownDuration customCooldownDurationTalentEnabled customCooldownDurationTalentSpellID customCooldownDurationTalentDuration activationOverlayBehaviorUseGlobal activationOverlayColor activationOverlayDrawSwipe activationOverlayDrawEdge activationOverlayReverse activationOverlayDesaturate activationOverlayOnly activationOverlayGlow customCooldownDurationGlowStyle customCooldownDurationGlowThreshold activationOverlayGlowColor"),
	StateTexture = fields("stateTextureInput stateTextureShowWithoutProc stateTextureDouble stateTextureMirror stateTextureMirrorSecond stateTextureMirrorVertical stateTextureMirrorVerticalSecond stateTextureScale stateTextureWidth stateTextureHeight stateTextureAngle stateTextureSpacingX stateTextureSpacingY"),
	Sound = fields("soundReady soundReadyFile auraAppliedSound auraAppliedSoundFile auraApplicationsIncreasedSound auraApplicationsIncreasedSoundFile auraRemovedSound auraRemovedSoundFile"),
}
local glowTabs = {
	Proc = { name = L["CooldownPanelProcGlow"], fields = fields("procGlowEnabled procGlowUseGlobal procGlowStyle procGlowInset procGlowColor") },
	Pandemic = { name = L["CooldownPanelGlowPandemic"], fields = fields("pandemicGlow pandemicGlowStyle pandemicGlowInset pandemicGlowColor") },
	Threshold = { name = L["CooldownPanelAuraDurationThreshold"], fields = fields("auraDurationThresholdShowEnabled auraDurationThresholdGlowEnabled auraDurationThresholdAsSeconds auraDurationThresholdMaxDuration auraDurationThresholdValue auraDurationThresholdGlowStyle auraDurationThresholdGlowColor") },
}
for suffix, spec in pairs(glowTabs) do
	scopes["Glow" .. suffix] = spec.fields
	for _, field in ipairs(spec.fields) do
		for index = #scopes.Glow, 1, -1 do if scopes.Glow[index] == field then table.remove(scopes.Glow, index) end end
	end
end
local barScopes = {
	Layout = fields("barWidth barHeight barOrientation barOffsetX barOffsetY barPanelOrientation barPanelWidth barPanelHeight barPanelOffsetX barPanelOffsetY"),
	Fill = fields("fillSparkEnabled fillSparkUseClassColor fillSparkColor fillSparkWidth fillSparkHeight fillSparkOffsetX fillSparkOffsetY barTexture barBackgroundTexture barColor barBackgroundColor barProcGlowColor"),
	Icon = fields("barShowIcon barIconSize barIconAnchorToBar barIconPosition barIconOffsetX barIconOffsetY"),
	Border = fields("barBorderEnabled barBorderSize barBorderOffset barBorderTexture barBorderColor"),
	Label = fields("barShowLabel barLabelAnchor barLabelOffsetX barLabelOffsetY barLabelFont barLabelStyle barLabelSize barLabelColor"),
	ValueText = fields("barValueAnchor barValueOffsetX barValueOffsetY barValueFont barValueStyle barValueSize barValueColor"),
	Charges = fields("barChargesSegmented barChargesGap barSegmentDirection barSegmentReverse barShowValueText barShowChargeDuration barDurationTextProfile"),
	Cooldown = fields("barShowValueText barDurationTextProfile barFillMode barReverseFill showStacks"),
	Stacks = fields("showStacks barShowStackText barStackMax barStackTalentMaxEnabled barStackTalentSpellID barStackTalentMax barStackMaxColorEnabled barStackMaxColor barStacksSegmented barStackSeparatedOffset barStackDividerColor barStackDividerThickness barStackAnchor barStackFont barStackStyle barStackSize barStackColor barStackOffsetX barStackOffsetY"),
	DurationColors = fields("barDurationColorEnabled barDurationThresholdAsSeconds barDurationThresholdMaxDuration barDurationThresholdGlowEnabled barDurationThresholdGlowIndex barDurationThresholdGlowStyle barDurationThresholdGlowColor"),
	Visibility = fields("alwaysShow cdmAuraAlwaysShowUseGlobal cdmAuraAlwaysShowMode cdmAuraMissingOnlyMyOwn cooldownVisibilityUseGlobal hideOnCooldown showOnCooldown"),
}
for index = 1, 3 do
	for _, suffix in ipairs({ "Enabled", "Value", "Color" }) do
		barScopes.Stacks[#barScopes.Stacks + 1] = "barStackThreshold" .. index .. suffix
		barScopes.DurationColors[#barScopes.DurationColors + 1] = "barDurationThreshold" .. index .. suffix
	end
end
local function copy(value)
	if type(value) ~= "table" then return value end
	local result = {}
	for key, child in pairs(value) do result[key] = copy(child) end
	return result
end
local function category(id, name, groups) return { id = id, name = name, groups = groups } end
local function setHint(data, target)
	if not target or data == target then return end
	data.navigationHint = function()
		if target.isShown and not target.isShown() and target.navigationHint then return target.navigationHint() end
		return target.name, nil, target.parentId
	end
end
local function shorten(data)
	local names = {
		[L["Icon X"]] = L["Offset X"], [L["Icon Y"]] = L["Offset Y"],
		[L["Cooldown text font"]] = L["Font"], [L["Cooldown text size"]] = (_G.FONT_SIZE or L["Size"]),
		[L["Cooldown text outline"]] = L["Font outline"], [L["Cooldown text color"]] = L["Color"],
		[L["Cooldown text offset X"]] = L["Offset X"], [L["Cooldown text offset Y"]] = L["Offset Y"],
		[L["CooldownPanelCountAnchor"]] = L["Anchor"], [L["CooldownPanelCountOffsetX"]] = L["Offset X"], [L["CooldownPanelCountOffsetY"]] = L["Offset Y"],
		[L["CooldownPanelChargesAnchor"]] = L["Anchor"], [L["CooldownPanelChargesOffsetX"]] = L["Offset X"], [L["CooldownPanelChargesOffsetY"]] = L["Offset Y"],
		[L["CooldownPanelKeybindsAnchor"]] = L["Anchor"], [L["CooldownPanelKeybindsOffsetX"]] = L["Offset X"], [L["CooldownPanelKeybindsOffsetY"]] = L["Offset Y"],
		[L["Text X Offset"]] = L["Offset X"], [L["Text Y Offset"]] = L["Offset Y"],
		[L["CooldownPanelFontStyle"]] = L["Font outline"],
	}
	if data.parentId and data.parentId:find("Border", 1, true) then
		names[L["Border texture"]], names[L["Border size"]], names[L["Border offset"]] = L["Texture"], L["Size"], L["Offset"]
	end
	if data.parentId == "cooldownPanelAuraBehavior" or data.parentId == "cooldownPanelStandaloneActivation" then
		names[L["CooldownPanelActivationOverlayDrawEdge"]] = L["CooldownPanelShowEdge"]
		names[L["CooldownPanelActivationOverlayDrawSwipe"]] = L["CooldownPanelShowSwipe"]
		names[L["CooldownPanelActivationOverlayColor"]] = L["CooldownPanelSwipeColor"]
		names[L["CooldownPanelActivationOverlayGlowColor"]] = L["Glow color"]
	end
	data.name = names[data.name] or data.name
end

local function refresh(kind, panelId, rebuildIndex)
	local panel = Panels:GetPanel(panelId)
	if panel and Helper.InvalidateFixedLayoutCache then Helper.InvalidateFixedLayoutCache(panel) end
	if panel and Panels.BumpFixedGroupEffectiveLayoutVersion then Panels.BumpFixedGroupEffectiveLayoutVersion(panel) end
	if rebuildIndex and Panels.RebuildSpellIndex then Panels:RebuildSpellIndex()
	else
		if Panels.UpdateEventRegistration then Panels:UpdateEventRegistration() end
		if Panels.RebuildPowerIndex then Panels:RebuildPowerIndex() end
	end
	Panels:RefreshPanel(panelId)
	Panels:RefreshEditor()
	if kind == "fixed" then Panels:RefreshLayoutFixedGroupStandaloneMenu()
	elseif kind == "panel" then Panels:RefreshLayoutPanelStandaloneMenu() end
end

local hoverPanelGroup = "cooldownPanelHoverBuff"
local hoverEntryGroup = "cooldownPanelStandaloneHoverBuff"
local hoverStyleTabs = {
	border = "cooldownPanelHoverBorder", background = "cooldownPanelHoverBackground", iconBorder = "cooldownPanelHoverIconBorder",
	launcherBackground = "cooldownPanelHoverLauncherBackground",
	swipe = "cooldownPanelHoverSwipe", font = "cooldownPanelHoverFont", titleFont = "cooldownPanelHoverTitleFont", count = "cooldownPanelHoverCount",
}
local hoverPanelGroups = {
	cooldownPanelGeneral = { panelName = true, enabled = true, specFilter = true, foreverUseSpecFilter = true, foreverTalentFilter = true },
	cooldownPanelLayout = { layoutMode = true, strata = true },
	cooldownPanelIcon = { iconSize = true },
	cooldownPanelVisibility = {
		visibility = true, hideInVehicle = true, hideInPetBattle = true, hideInClientScene = true,
		opacityOutOfCombat = true, opacityInCombat = true,
	},
}
local hoverPanelWholeGroups = { cooldownPanelAnchor = true, cooldownPanelCopySettings = true }
local hoverPanelDefaults = {
	hoverBuffCount = true,
	hoverBuffPerRow = 2,
	hoverBuffSpacing = 4,
	hoverBuffGap = 5,
	hoverBuffDirection = "AUTO",
	hoverBuffAnimation = "REVEAL",
	hoverBuffDisplay = "BOTH",
}
local hoverPanelFields = {
	"hoverBuffPerRow", "hoverBuffEntryIconSize", "hoverBuffSpacing", "hoverBuffGap", "hoverBuffDirection", "hoverBuffAnimation", "hoverBuffDisplay",
}

local function refreshHoverBuffPanel(panelId, refreshEditor)
	Panels:RefreshPanelForCurrentEditContext(panelId, refreshEditor)
	if refreshEditor and Panels.BlizzardEditor and Panels.BlizzardEditor.RefreshPanel then Panels.BlizzardEditor:RefreshPanel(panelId) end
end

local hoverStyleSplitsByTab = {}
local hoverStyleSplitsByField = {}
local function defineHoverStyleSplit(marker, fields, firstTab, secondTab)
	local split = { marker = marker, fields = fields }
	hoverStyleSplitsByTab[firstTab], hoverStyleSplitsByTab[secondTab] = split, split
	for independent, shared in pairs(fields) do
		hoverStyleSplitsByField[independent], hoverStyleSplitsByField[shared] = split, split
	end
end
defineHoverStyleSplit("launcherBackgroundSeparated", {
	launcherBackgroundEnabled = "backgroundEnabled", launcherBackgroundColor = "backgroundColor",
	launcherBackgroundClassColor = "backgroundClassColor", launcherBackgroundTexture = "backgroundTexture",
}, hoverStyleTabs.background, hoverStyleTabs.launcherBackground)
defineHoverStyleSplit("titleStyleSeparated", {
	titleFont = "font", titleFontSize = "fontSize", titleFontStyle = "fontStyle",
	titleTextColor = "textColor", titleTextClassColor = "textClassColor",
}, hoverStyleTabs.font, hoverStyleTabs.titleFont)

local function splitHoverStyle(style, split)
	if not split or style[split.marker] then return end
	-- Keep both visuals as configured until one is edited or reset.
	for independent, shared in pairs(split.fields) do style[independent] = style[shared] end
	style[split.marker] = true
end

local hoverLayoutStyleAfter = { rowSpacing = "hoverBuffSpacing", emptySlot = "hoverBuffDisplay" }

local function addHoverBuffStyleSettings(append, addTab, get, set, kinds, hover)
	local colors = hover.styleColors
	local function read(field, fallback)
		local style = get("hoverBuffStyle")
		if type(style) ~= "table" then return fallback end
		local split = hoverStyleSplitsByField[field]
		if split and not style[split.marker] then field = split.fields[field] or field end
		local value = style[field]
		if value == nil then return fallback end
		return value
	end
	local function change(field, value)
		local source = get("hoverBuffStyle")
		local style = type(source) == "table" and Helper.CopyTableShallow(source) or {}
		splitHoverStyle(style, hoverStyleSplitsByField[field])
		style[field] = value
		set("hoverBuffStyle", style)
	end
	local tab, enabledField, enabledDefault, prerequisite
	local function control(field, descriptor)
		local disabled = descriptor.disabled
		local dependency, default, required = enabledField, enabledDefault, prerequisite
		descriptor.disabled = function()
			return (required and not required()) or (dependency and field ~= dependency and not read(dependency, default)) or (disabled and disabled())
		end
		if tab then tab.hoverStyleFields[#tab.hoverStyleFields + 1] = descriptor.hoverStyleStorageField or field end
		append(descriptor, "hoverBuffStyle." .. field, tab and tab.id or hoverPanelGroup, hoverLayoutStyleAfter[field])
	end
	local function section(field, name, default)
		tab = addTab(hoverStyleTabs[field], name)
		tab.hoverStyleFields = {}
		enabledField, enabledDefault = default ~= nil and field .. "Enabled" or nil, default
	end
	local function checkbox(field, name, default)
		control(field, { name = name, kind = kinds.Checkbox,
			get = function() return read(field, default) end,
			set = function(_, value) change(field, value == true) end })
	end
	local function slider(field, name, low, high, fallback)
		control(field, { name = name, kind = kinds.Slider, minValue = low, maxValue = high, valueStep = 1, allowInput = true,
			get = function()
				local default = type(fallback) == "function" and fallback() or fallback
				return Helper.ClampInt(read(field), low, high, default)
			end,
			set = function(_, value) change(field, Helper.ClampInt(value, low, high, low)) end })
	end
	local function color(field, name)
		local fallback = colors and colors[field] or { 1, 1, 1, 1 }
		local colorField = field .. "Color"
		local function current() return Helper.NormalizeColor(read(colorField), fallback) end
		control(colorField, { name = name, kind = kinds.Color, hasOpacity = true,
			disabled = function() return read(field .. "ClassColor", false) end,
			get = function()
				local rgba = current()
				return { r = rgba[1], g = rgba[2], b = rgba[3], a = rgba[4] }
			end,
			set = function(_, value)
				change(colorField, Helper.NormalizeColor(value, fallback))
			end })
		control(field .. "Alpha", { name = L["Alpha"], hoverStyleStorageField = colorField, kind = kinds.Slider, minValue = 0, maxValue = 100, valueStep = 1, allowInput = true,
			get = function() return math.floor(current()[4] * 100 + 0.5) end,
			set = function(_, value)
				local rgba = current()
				rgba[4] = Helper.ClampInt(value, 0, 100, math.floor(fallback[4] * 100 + 0.5)) / 100
				change(colorField, rgba)
			end,
			formatter = function(value) return tostring(value) .. "%" end })
	end
	local function dropdown(field, name, options, fallback)
		local function current() return read(field, fallback) end
		control(field, { name = name, kind = kinds.Dropdown, get = current,
			set = function(_, value) change(field, value) end,
			generator = function(_, menu)
				for _, option in ipairs(options()) do
					local value, label = option.value, option.label
					menu:CreateRadio(label, function() return current() == value end, function() change(field, value) end)
				end
			end })
	end
	local function texture(field, name, media)
		dropdown(field, name, function()
			local options = { { label = _G.DEFAULT } }
			local names = addon.functions.GetLSMMediaNames(media)
			for _, label in ipairs(names) do options[#options + 1] = { value = label, label = label } end
			return options
		end)
	end
	local function border(field, title, defaultEnabled)
		section(field, title, defaultEnabled)
		checkbox(field .. "Enabled", L["Enabled"], defaultEnabled)
		color(field, L["Color"])
		checkbox(field .. "ClassColor", L["Use class color"], false)
		texture(field .. "Texture", L["Border texture"], "border")
		slider(field .. "Size", L["Size"], 1, hover.borderLimit, 1)
		slider(field .. "Offset", L["Offset"], -hover.borderLimit, hover.borderLimit, 0)
	end
	local function background(field, title)
		section(field, title, true)
		checkbox(field .. "Enabled", L["Enabled"], true)
		color(field, L["Background color"])
		checkbox(field .. "ClassColor", L["Use class color"], false)
		texture(field .. "Texture", L["Background texture"], "background")
	end

	slider("rowSpacing", L["Vertical spacing"], 0, 32, function() return get("hoverBuffSpacing", 4) end)
	dropdown("emptySlot", L["CooldownPanelHoverBuffMissingStyle"], function()
		return {
			{ value = "DESATURATED", label = L["Desaturate icon"] },
			{ value = "EMPTY", label = L["CooldownPanelHoverBuffEmptySlot"] },
		}
	end, "EMPTY")
	border("border", L["Border"], true)
	background("background", L["CooldownPanelHoverBuffPanelBackground"])
	background("launcherBackground", L["CooldownPanelHoverBuffLauncherBackground"])
	border("iconBorder", L["Icon border"], false)
	section("swipe", L["Cooldown"], false)
	checkbox("swipeEnabled", L["Draw cooldown swipe"], false)
	color("swipe", L["Color"])
	section("font", L["CooldownPanelHoverBuffEntryLabels"])
	local function fontSettings(field, sizeField, outlineField, sizeMax)
		dropdown(field, L["Font"], function() return Helper.GetFontOptions(STANDARD_TEXT_FONT) end,
			addon.functions.GetGlobalFontConfigKey and addon.functions.GetGlobalFontConfigKey() or "__EQOL_GLOBAL_FONT__")
		slider(sizeField, _G.FONT_SIZE or L["Size"], 6, sizeMax, 12)
		dropdown(outlineField, L["Font outline"], function() return Helper.FontStyleOptions end,
			addon.functions.GetGlobalFontStyleConfigKey and addon.functions.GetGlobalFontStyleConfigKey() or "__EQOL_GLOBAL_FONT_STYLE__")
	end
	fontSettings("font", "fontSize", "fontStyle", 28)
	color("text", L["Text color"])
	checkbox("textClassColor", L["Use class color"], false)

	section("titleFont", L["CooldownPanelHoverBuffTitle"])
	fontSettings("titleFont", "titleFontSize", "titleFontStyle", 28)
	color("titleText", L["Text color"])
	checkbox("titleTextClassColor", L["Use class color"], false)

	section("count", L["CooldownPanelCountersHeader"])
	local function countEnabled() return get("hoverBuffCount", true) ~= false end
	append({
		name = L["CooldownPanelHoverBuffCount"], kind = kinds.Checkbox,
		get = countEnabled,
		set = function(_, value) set("hoverBuffCount", value == true) end,
	}, "hoverBuffCount", tab.id)
	prerequisite = countEnabled
	dropdown("countAnchor", L["Anchor"], function() return Helper.AnchorOptions end, "BOTTOMRIGHT")
	slider("countX", L["Offset X"], -64, 64, -1)
	slider("countY", L["Offset Y"], -64, 64, 1)
	fontSettings("countFont", "countFontSize", "countFontStyle", 40)
	color("count", L["Text color"])
	checkbox("countClassColor", L["Use class color"], false)
end

function Navigation.AddHoverBuffSettings(settings, kind, panelId, entryId)
	local hover = Panels.HoverBuffPanel
	if not hover or not hover:IsAvailable() or (kind ~= "panel" and kind ~= "entry") then return end
	local types = addon.EditModeLib.SettingType
	if kind == "panel" then
		local hasPanelGeneral
		for _, data in ipairs(settings) do
			if data.kind == types.Collapsible and data.id == "cooldownPanelGeneral" then hasPanelGeneral = true; break end
		end
		if not hasPanelGeneral then return end
	end
	local function getPanel() return Panels:GetPanel(panelId) end
	local function isEnabled()
		local panel = getPanel()
		return panel and hover:IsEnabled(panel.layout)
	end
	local function getConfig()
		local panel = getPanel()
		if not panel then return end
		if kind == "panel" then return panel.layout end
		local entry = panel.entries and panel.entries[entryId]
		return entry
	end
	if kind == "entry" and not (isEnabled() and getConfig()) then return end
	local groupId = kind == "panel" and hoverPanelGroup or hoverEntryGroup
	local modeName = L["CooldownPanelHoverBuffMode"]
	local function get(field, fallback)
		local config = getConfig()
		local value = config and config[field]
		if value == nil then return fallback end
		return value
	end
	local function set(field, value)
		if InCombatLockdown() then return end
		local config = getConfig()
		if not config or config[field] == value then return end
		config[field] = value
		refreshHoverBuffPanel(panelId, kind == "entry")
	end
	local function hideInMode(data)
		local wasShown = data.isShown
		data.isShown = function(...) return not isEnabled() and (not wasShown or wasShown(...)) end
		data._eqolHoverBuffModeDependent = isEnabled
	end
	for _, data in ipairs(settings) do
		local id = data.kind == types.Collapsible and data.id or data.parentId
		if kind == "entry" and (id == "cooldownPanelStandaloneDisplay" and data.name == L["CooldownPanelCDMAuraOverlaySpellIDs"]) then
			data.parentId = groupId
		elseif kind == "entry" then
			local entry = getConfig()
			if entry and entry.type == "CDM_AURA" and id ~= "cooldownPanelStandaloneDisplay" then hideInMode(data) end
		elseif id and not hoverPanelWholeGroups[id] then
			local enabledFields = hoverPanelGroups[id]
			local field = data.navigationField or data.field
			local general = id == "cooldownPanelGeneral" and (data.name == L["CooldownPanelPanelName"] or data.name == L["Enabled"] or data.name == _G.CLASS
				or data.name == L["CooldownPanelSpecFilter"])
			if not enabledFields or (data.kind ~= types.Collapsible and not enabledFields[field] and not general) then
				hideInMode(data)
			elseif field == "iconSize" then
				local shown, disabled = data.isShown, data.disabled
				data.isShown = function(...) return isEnabled() or not shown or shown(...) end
				data.disabled = function(...) return not isEnabled() and disabled and disabled(...) end
				local refreshBarSetting = data._eqolRefreshBarPanelSetting
				if refreshBarSetting then
					data._eqolRefreshBarPanelSetting = function()
						refreshBarSetting()
						if isEnabled() then data.navigationSearchExcluded = nil end
					end
					data._eqolRefreshBarPanelSetting()
				end
			end
		end
	end
	local function addTab(id, name)
		local tab = { kind = types.Collapsible, id = id, name = name, isShown = isEnabled }
		if kind == "panel" then
			tab.navigationHint = function() return L["CooldownPanelLayoutMode"], nil, "cooldownPanelLayout" end
		end
		settings[#settings + 1] = tab
		return tab
	end
	addTab(groupId, modeName)
	local function append(data, field, parent, afterField)
		data.parentId, data.navigationField = parent or groupId, field
		if kind == "panel" then
			data.isShown = isEnabled
			data.navigationHint = function() return L["CooldownPanelLayoutMode"], nil, "cooldownPanelLayout" end
		end
		if afterField then
			for index = #settings, 1, -1 do
				if settings[index].navigationField == afterField then
					table.insert(settings, index + 1, data)
					return
				end
			end
		end
		settings[#settings + 1] = data
	end
	local function textInput(name, field, maxChars, parent, disabled)
		append({
			name = name, kind = types.Input, maxChars = maxChars, inputWidth = 165, disabled = disabled,
			get = function() return get(field, "") end,
			set = function(_, value)
				local text = (value or ""):match("^%s*(.-)%s*$")
				set(field, text ~= "" and text or nil)
			end,
		}, field, parent)
	end
	local function iconInput(field, parent)
		append({
			name = L["CooldownPanelHoverBuffIcon"], kind = types.Input, maxChars = 10, inputWidth = 165,
			get = function()
				local value = get(field)
				return value and tostring(value) or ""
			end,
			set = function(_, value)
				local text = (value or ""):match("^%s*(.-)%s*$")
				local number = text:match("^%d+$") and tonumber(text)
				if text == "" then set(field, nil)
				elseif number and number >= 1 and number <= 2147483647 and number == math.floor(number) then set(field, number) end
			end,
		}, field, parent)
	end
	if kind == "entry" then
		local function showName() return get("hoverBuffShowLabel", true) ~= false end
		append({
			name = L["Show name"], kind = types.Checkbox,
			get = showName,
			set = function(_, value) set("hoverBuffShowLabel", value == true) end,
		}, "hoverBuffShowLabel")
		textInput(L["QuickCastCustomLabel"], "hoverBuffLabel", 64, nil, function() return not showName() end)
		iconInput("hoverBuffIcon")
		return
	end
	iconInput("hoverBuffIcon", "cooldownPanelIcon")
	textInput(L["CooldownPanelHoverBuffTitle"], "hoverBuffTitle", 64, hoverStyleTabs.titleFont)
	append({
		name = L["CooldownPanelHoverBuffPerRow"], kind = types.Slider, minValue = 1, maxValue = 12, valueStep = 1, allowInput = true,
		get = function() return Helper.ClampInt(get("hoverBuffPerRow"), 1, 12, hoverPanelDefaults.hoverBuffPerRow) end,
		set = function(_, value) set("hoverBuffPerRow", Helper.ClampInt(value, 1, 12, hoverPanelDefaults.hoverBuffPerRow)) end,
	}, "hoverBuffPerRow")
	local iconSize = hover.entryIconSize
	local function normalizeIconSize(value) return Helper.ClampInt(value, iconSize.min, iconSize.max, iconSize.default) end
	append({
		name = L["CooldownPanelHoverBuffEntryIconSize"], kind = types.Slider, minValue = iconSize.min, maxValue = iconSize.max, valueStep = 1, allowInput = true,
		get = function() return normalizeIconSize(get("hoverBuffEntryIconSize")) end,
		set = function(_, value) set("hoverBuffEntryIconSize", normalizeIconSize(value)) end,
	}, "hoverBuffEntryIconSize")
	append({
		name = L["Horizontal spacing"], kind = types.Slider, minValue = 0, maxValue = 18, valueStep = 1, allowInput = true,
		get = function() return Helper.ClampInt(get("hoverBuffSpacing"), 0, 18, hoverPanelDefaults.hoverBuffSpacing) end,
		set = function(_, value) set("hoverBuffSpacing", Helper.ClampInt(value, 0, 18, hoverPanelDefaults.hoverBuffSpacing)) end,
	}, "hoverBuffSpacing")
	local function dropdown(name, field, options)
		local function getValue()
			local value = get(field, hoverPanelDefaults[field])
			for _, option in ipairs(options) do if option[1] == value then return value end end
			return hoverPanelDefaults[field]
		end
		append({
			name = name, kind = types.Dropdown, get = getValue,
			set = function(_, value) set(field, value) end,
			generator = function(_, menu)
				for _, option in ipairs(options) do
					local value, label = option[1], option[2]
					menu:CreateRadio(label, function() return getValue() == value end, function() set(field, value) end)
				end
			end,
		}, field)
	end
	append({
		name = L["CooldownPanelHoverBuffGap"], kind = types.Slider, minValue = 0, maxValue = 128, valueStep = 1, allowInput = true,
		get = function() return Helper.ClampInt(get("hoverBuffGap"), 0, 128, hoverPanelDefaults.hoverBuffGap) end,
		set = function(_, value) set("hoverBuffGap", Helper.ClampInt(value, 0, 128, hoverPanelDefaults.hoverBuffGap)) end,
	}, "hoverBuffGap")
	dropdown(L["CooldownPanelHoverBuffDirection"], "hoverBuffDirection", {
		{ "AUTO", L["Auto"] }, { "UP", L["Up"] }, { "DOWN", L["Down"] }, { "LEFT", L["Left"] }, { "RIGHT", L["Right"] },
	})
	dropdown(L["CooldownPanelHoverBuffAnimation"], "hoverBuffAnimation", {
		{ "NONE", _G.NONE or L["Off"] },
		{ "FADE", L["CooldownPanelHoverBuffAnimationFade"] },
		{ "SLIDE", L["CooldownPanelHoverBuffAnimationSlide"] },
		{ "REVEAL", L["CooldownPanelHoverBuffAnimationReveal"] },
	})
	dropdown(L["CooldownPanelHoverBuffDisplay"], "hoverBuffDisplay", {
		{ "BOTH", L["CooldownPanelHoverBuffDisplayBoth"] },
		{ "MISSING", L["CooldownPanelCDMAuraAlwaysShowModeMissing"] },
		{ "ACTIVE", L["CooldownPanelCDMAuraAlwaysShowModeHide"] },
	})
	addHoverBuffStyleSettings(append, addTab, get, set, types, hover)
end

function Navigation.CustomDurationTalentSettings(panelId, entryId)
	local types = addon.EditModeLib.SettingType
	local parentId = "cooldownPanelStandaloneActivation"
	local function entry()
		local panel = Panels:GetPanel(panelId)
		return panel and panel.entries and panel.entries[entryId]
	end
	local function shown()
		local current = entry()
		return current and Panels:SupportsEntryCustomCooldownDuration(current, current.type)
	end
	local function disabled()
		local current = entry()
		return not (current and (current.customCooldownDurationEnabled == true or current.customCooldownDurationOnCooldownEnabled == true))
	end
	local function ruleDisabled() return disabled() or not (entry() and entry().customCooldownDurationTalentEnabled == true) end
	local function set(field, value)
		if InCombatLockdown() then return end
		local current = entry()
		if not current or current[field] == value then return end
		current[field] = value
		if Panels.ClearEntryCustomCooldownDuration then Panels:ClearEntryCustomCooldownDuration(panelId, entryId, true) end
		Panels:RefreshPanel(panelId)
		Panels:RefreshEditor()
		Panels:RefreshLayoutEntryStandaloneMenu(true)
	end
	return {
		{ name = L["CooldownPanelCustomDurationTalentEnabled"], tooltip = L["CooldownPanelCustomDurationTalentTooltip"],
			kind = types.Checkbox, parentId = parentId, navigationField = "customCooldownDurationTalentEnabled",
			isShown = shown, disabled = disabled,
			get = function() return entry() and entry().customCooldownDurationTalentEnabled == true or false end,
			set = function(_, value)
				local current = entry()
				if not InCombatLockdown() and value == true and current and not ((tonumber(current.customCooldownDurationTalentDuration) or 0) > 0) then
					current.customCooldownDurationTalentDuration = Helper.ClampNumber(current.customCooldownDuration, 1, Helper.CUSTOM_COOLDOWN_DURATION_MAX or 300, 1)
				end
				set("customCooldownDurationTalentEnabled", value == true)
			end },
		{ name = L["Talent spell ID"], kind = types.Input, parentId = parentId, navigationField = "customCooldownDurationTalentSpellID",
			inputWidth = 120, numeric = true, maxChars = 10, isShown = shown, disabled = ruleDisabled,
			get = function() return entry() and entry().customCooldownDurationTalentSpellID or 0 end,
			set = function(_, value) set("customCooldownDurationTalentSpellID", Helper.ClampInt(value, 0, 2147483647, 0)) end },
		{ name = L["CooldownPanelCustomDurationTalentSeconds"], kind = types.Slider, parentId = parentId, navigationField = "customCooldownDurationTalentDuration",
			minValue = 1, maxValue = Helper.CUSTOM_COOLDOWN_DURATION_MAX or 300, valueStep = 1, allowInput = true,
			isShown = shown, disabled = ruleDisabled,
			get = function() return Helper.ClampNumber(entry() and entry().customCooldownDurationTalentDuration, 1, Helper.CUSTOM_COOLDOWN_DURATION_MAX or 300, 1) end,
			set = function(_, value) set("customCooldownDurationTalentDuration", Helper.ClampNumber(value, 1, Helper.CUSTOM_COOLDOWN_DURATION_MAX or 300, 1)) end },
	}
end

function Navigation.StructureSettings(settings, kind, panelId, entryId)
	if settings._eqolStructured then return end
	settings._eqolStructured = true
	local types = addon.EditModeLib.SettingType
	local rebuilt, sections, sectionTitles = {}, {}, {}
	local current
	local function divider(name, parentId)
		local rows = {}
		local data = { name = name, kind = types.Divider, parentId = parentId, navigationSearchExcluded = true,
			isShown = function()
				for _, row in ipairs(rows) do if not row.isShown or row.isShown() then return true end end
				return false
			end }
		rebuilt[#rebuilt + 1] = data
		sections[parentId] = rows
	end
	for _, data in ipairs(settings) do
		local parent = data.parentId
		local title
		if parent == "cooldownPanelStandaloneActivation" then
			if data.name == L["CooldownPanelOverwriteGlobalDefault"] then title = L["Auras"]
			elseif data.name == L["CooldownPanelAutoDuration"] then title = L["Duration"]
			elseif data.name == L["CooldownPanelOverwritePanelActivationBehavior"] then title = L["QuickCastCopyAppearance"]
			elseif data.name == L["CooldownPanelActivationOverlayDesaturate"] then title = L["Behavior"]
			elseif data.name == L["CooldownPanelActivationOverlayDrawEdge"] then title = L["CooldownPanelActivationSwipeHeader"]
			elseif data.name == L["CooldownPanelActivationOverlayGlow"] then title = L["Glow"] end
		elseif parent == "cooldownPanelAuraBehavior" then
			if data.name == L["CooldownPanelCDMAuraOverlayPanel"] then title = L["Behavior"]
			elseif data.name == L["CooldownPanelActivationOverlayDrawEdge"] then title = L["CooldownPanelActivationSwipeHeader"]
			elseif data.name == L["CooldownPanelActivationOverlayGlow"] then title = L["Glow"] end
		elseif parent == "cooldownPanelStandaloneCooldownSwipe" or parent == "cooldownPanelCooldownSwipe" then
			if data.name == L["CooldownPanelShowChargesCooldown"] then title = L["Charges"]
			elseif data.name == L["CooldownPanelShowEdge"] or data.name == L["CooldownPanelDrawEdge"] then title = L["Cooldown"]
			elseif data.name == L["CooldownPanelShowEdgeGcd"] or data.name == L["CooldownPanelDrawEdgeGcd"] then title = L["CooldownPanelGlobalCooldownHeader"] end
		elseif parent == "cooldownPanelVisibility" then
			if data.name == L["CooldownPanelShowTooltips"] then title = L["CooldownPanelShowTooltips"]
			elseif data.name == L["CooldownPanelHideOnCooldown"] then title = L["Cooldown"]
			elseif data.name == L["Show when"] then title = L["CooldownPanelVisibilityRulesHeader"]
			elseif data.name == L["CooldownPanelOpacityOutOfCombat"] then title = L["CooldownPanelOpacityHeader"] end
		elseif parent == "cooldownPanelLayout" then
			if data.name == L["CooldownPanelWidthMode"] then title = L["Size"]
			elseif data.name == L["Spacing"] or data.name == "Spacing" then title = L["Layout"]
			elseif data.name == L["CooldownPanelRadialRadius"] then title = L["CooldownPanelLayoutModeRadial"] end
		elseif parent == "cooldownPanelAvailability" or parent == "cooldownPanelStandaloneAvailability" then
			if data.name == L["CooldownPanelRangeIndicator"] then title = L["CooldownPanelRangeIndicator"]
			elseif data.name == L["CooldownPanelRequireEnoughResource"] then title = L["CooldownPanelRequireEnoughResource"] end
		elseif parent == "cooldownPanelStandaloneVisibility" then
			if data.name == L["CooldownPanelSpecFilter"] then title = L["CooldownPanelSpecFilter"]
			elseif data.name == L["CooldownPanelOverwriteGlobalDefault"] then title = L["Cooldown"] end
		elseif parent == "cooldownPanelStandaloneDisplay" then
			if data.name == L["CooldownPanelTrackTalentChoiceSeparately"] then title = L["CooldownPanelTrackingHeader"]
			elseif data.name == L["CooldownPanelCDMAuraOverlayUnit"] then title = L["Auras"]
			elseif data.name == L["CooldownPanelShowItemCount"] then title = L["CooldownPanelCountersHeader"] end
		elseif parent and (parent == "cooldownPanelStandaloneIcon" or parent == "cooldownPanelIcon") then
			if data.name == L["CooldownPanelOverwriteGlobalSize"] or data.name == L["CooldownPanelUseCustomIconSize"] or data.name == L["Icon size"] or data.name == "Icon size" then title = L["Size"]
			elseif data.name == L["CooldownPanelShowIconTexture"] then title = L["QuickCastCopyAppearance"]
			elseif data.name == L["Icon X"] then title = L["Position"] end
		elseif parent and (parent:find("CooldownText", 1, true) or parent:find("StaticText", 1, true) or parent:find("Stacks", 1, true) or parent:find("Charges", 1, true)) and not parent:find("Bar", 1, true) then
			if data.name == L["Font"] or data.name == L["Cooldown text font"] then title = L["QuickCastCopyAppearance"]
			elseif data.name == L["Anchor"] or data.name == L["Cooldown text offset X"] or data.name == L["CooldownPanelCountAnchor"] or data.name == L["CooldownPanelChargesAnchor"] then title = L["Position"] end
		end
		if title and sectionTitles[parent] ~= title then
			divider(title, parent)
			sectionTitles[parent] = title
		end
		current = parent and sections[parent]
		if current then current[#current + 1] = data end
		rebuilt[#rebuilt + 1] = data
		if kind == "entry" and parent == "cooldownPanelStandaloneActivation" and data.name == L["CooldownPanelCustomDurationSeconds"] then
			for _, row in ipairs(Navigation.CustomDurationTalentSettings(panelId, entryId)) do
				rebuilt[#rebuilt + 1] = row
				if current then current[#current + 1] = row end
			end
		end
	end
	for index, data in ipairs(rebuilt) do settings[index] = data end
	Navigation.AddHoverBuffSettings(settings, kind, panelId, entryId)
end

function Navigation.Build(settings, kind, panelId, entryId, groupId)
	Navigation.StructureSettings(settings, kind, panelId, entryId)
	local types = addon.EditModeLib.SettingType
	local headers, controls = {}, {}
	local borderStarted = false
	local addedHeaders = {}
	for _, data in ipairs(settings) do
		if data.kind == types.Collapsible then headers[data.id] = data else
			if data.parentId == "cooldownPanelIcon" and data.navigationField ~= "hoverBuffIcon" then
				if data.name == L["CooldownPanelIconBorder"] then borderStarted = true end
				if borderStarted then data.parentId = "cooldownPanelBorder" end
			end
			if (data.parentId == "cooldownPanelGlow" or data.parentId == "cooldownPanelStandaloneGlow") and glowTabs[data.navigationGroup] then
				local spec = glowTabs[data.navigationGroup]
				local id = data.parentId .. data.navigationGroup
				data.parentId = id
				addedHeaders[id] = { id = id, name = spec.name, kind = types.Collapsible }
			end
			shorten(data)
			local id = data.parentId or "__general"
			controls[id] = controls[id] or {}
			if data.name then controls[id][data.name] = data end
		end
	end
	for id, header in pairs(addedHeaders) do
		if not headers[id] then
			header.isShown = function()
				for _, data in pairs(controls[id] or {}) do if not data.isShown or data.isShown() then return true end end
				return false
			end
			local source
			for _, data in pairs(controls[id] or {}) do
				if data._eqolHoverBuffModeDependent then source = data; break end
			end
			header._eqolHoverBuffModeDependent = source and source._eqolHoverBuffModeDependent or nil
			settings[#settings + 1], headers[id] = header, header
		end
	end
	if controls.cooldownPanelBorder and not headers.cooldownPanelBorder then
		local header = { kind = types.Collapsible, id = "cooldownPanelBorder", name = L["Border"] }
		local source = controls.cooldownPanelBorder[L["CooldownPanelIconBorder"]]
		if source and source._eqolHoverBuffModeDependent then
			header._eqolHoverBuffModeDependent = source._eqolHoverBuffModeDependent
			header.isShown = function() return not header._eqolHoverBuffModeDependent() end
		end
		settings[#settings + 1], headers[header.id] = header, header
	end
	local bars = Panels.Bars
	local barIds = bars and { [bars.STANDALONE_STACKS_SECTION_ID] = "Stacks", [bars.STANDALONE_DURATION_COLORS_SECTION_ID] = "DurationColors" } or {}
	for id, header in pairs(headers) do
		local suffix = id:gsub("^cooldownPanelStandalone", ""):gsub("^cooldownPanel", "")
		local barSuffix = barIds[id] or id:match("^eqolCooldownPanelStandaloneBar(.+)$")
		local resetFields = barSuffix and barScopes[barSuffix] or scopes[suffix]
		-- Tracking identity, layout mode and slot assignments are deliberately not reset.
		if id == hoverPanelGroup or id == hoverEntryGroup or header.hoverStyleFields then
			header.navigationReset = function()
				if InCombatLockdown() then return end
				local panel = Panels:GetPanel(panelId)
				if not panel then return end
				if kind == "panel" then
					if header.hoverStyleFields then
						if id == hoverStyleTabs.count then panel.layout.hoverBuffCount = nil end
						if id == hoverStyleTabs.titleFont then panel.layout.hoverBuffTitle = nil end
						local style = panel.layout.hoverBuffStyle
						if type(style) == "table" then
							splitHoverStyle(style, hoverStyleSplitsByTab[id])
							for _, field in ipairs(header.hoverStyleFields) do style[field] = nil end
						end
					else
						for _, field in ipairs(hoverPanelFields) do panel.layout[field] = hoverPanelDefaults[field] end
						local style = panel.layout.hoverBuffStyle
						if type(style) == "table" then style.rowSpacing, style.emptySlot = nil, nil end
					end
				else
					local entry = panel.entries and panel.entries[entryId]
					if not entry then return end
					entry.hoverBuffLabel, entry.hoverBuffIcon, entry.hoverBuffShowLabel = nil, nil, nil
				end
				refreshHoverBuffPanel(panelId, true)
			end
		elseif kind == "panel" and suffix == "Anchor" then
			header.navigationReset = function()
				if InCombatLockdown() then return end
				local panel = Panels:GetPanel(panelId)
				if not panel then return end
				local defaults = Helper.CreatePanel(nil)
				panel.anchor, panel.dynamicAnchor = copy(defaults.anchor), nil
				panel.point, panel.x, panel.y = defaults.point, defaults.x, defaults.y
				if Panels.MarkRelativeFrameEntriesDirty then Panels.MarkRelativeFrameEntriesDirty() end
				if addon.DynamicAnchors then addon.DynamicAnchors:RefreshRaidSizeConsumerTracking() end
				if Panels.UpdateCursorAnchorState then Panels:UpdateCursorAnchorState() end
				refresh(kind, panelId)
			end
		elseif kind == "panel" and suffix == "General" then
			header.navigationReset = function()
				if InCombatLockdown() then return end
				local panel = Panels:GetPanel(panelId)
				if not panel then return end
				local defaults = Helper.CreatePanel(nil)
				panel.enabled, panel.specFilter = defaults.enabled, nil
				panel.foreverTalentFilter = nil
				panel.foreverUseSpecFilter = nil
				if not (Panels.HoverBuffPanel and Panels.HoverBuffPanel:IsEnabled(panel.layout)) then
					panel.layout.durationTextProfile = defaults.layout.durationTextProfile
					panel.barDurationTextProfile = defaults.layout.durationTextProfile
				end
				refresh(kind, panelId, true)
			end
		elseif kind == "panel" and barSuffix and resetFields then
			header.navigationReset = function()
				if InCombatLockdown() then return end
				local panel = Panels:GetPanel(panelId)
				if not panel or not panel.layout then return end
				local target = panel.layout.barStyle
				if type(target) ~= "table" then return end
				for _, field in ipairs(resetFields) do
					-- Shared slot geometry remains in the panel's Layout/Icon tabs.
					if field ~= "barWidth" and field ~= "barHeight" and field ~= "barOrientation"
						and field ~= "barOffsetX" and field ~= "barOffsetY" and field ~= "barIconSize" then
						target[field] = nil
					end
				end
				if barSuffix == "Icon" then
					panel.layout.barPanelIconSize = bars and bars.DEFAULTS.barIconSize or 18
					panel.layout.showCraftingQuality = Helper.PANEL_LAYOUT_DEFAULTS.showCraftingQuality
					panel.layout.craftingQualityScale = Helper.PANEL_LAYOUT_DEFAULTS.craftingQualityScale
				end
				if Helper.InvalidateBarPanelStyle then Helper.InvalidateBarPanelStyle(panel.layout) end
				refresh(kind, panelId, barSuffix == "Charges" or barSuffix == "Stacks")
			end
		elseif resetFields then
			header.navigationReset = function()
				if InCombatLockdown() then return end
				local panel = Panels:GetPanel(panelId)
				if not panel then return end
				local target, defaults
				if kind == "panel" then
					target, defaults = panel.layout, Helper.CreatePanel(nil).layout
				else
					-- Detaching one style tab must preserve the inherited appearance of every other tab.
					if barSuffix and barSuffix ~= "Layout" and bars and bars.PrepareEntryStyleOverride then bars.PrepareEntryStyleOverride(panelId, entryId, barSuffix) end
					target = panel.entries and panel.entries[entryId]
					if not target then return end
					defaults = copy(Helper.ENTRY_DEFAULTS)
					if bars then
						for key, value in pairs(bars.DEFAULTS) do if defaults[key] == nil then defaults[key] = value end end
						if bars.COLORS then defaults.barColor = bars.COLORS[target.barMode] or bars.COLORS.COOLDOWN end
						-- New bars inherit their panel's duration format until explicitly overridden.
						defaults.barDurationTextProfile = nil
					end
					if target.type == "CDM_AURA" then defaults.alwaysShow = false end
					if target.type == "ITEM" then defaults.showItemCount = true end
					if target.type == "STANCE" then defaults.showCooldownText, defaults.showCooldownTextUseGlobal = false, false end
				end
				if not target then return end
				local fieldsToReset = resetFields
				if kind == "entry" and barSuffix == "Layout" and Helper.IsBarLayout(panel.layout) then
					fieldsToReset = { "barPanelOrientation", "barPanelWidth", "barPanelHeight", "barPanelOffsetX", "barPanelOffsetY" }
				end
				local hoverFields = kind == "panel" and Panels.HoverBuffPanel and Panels.HoverBuffPanel:IsEnabled(panel.layout) and hoverPanelGroups[id]
				for _, field in ipairs(fieldsToReset) do
					if not hoverFields or hoverFields[field] then target[field] = copy(defaults[field]) end
				end
				if hoverFields and suffix == "Icon" then target.hoverBuffIcon = nil end
				if kind == "panel" and suffix == "CooldownText" then target.auraOverlayTextSize = defaults.auraOverlayTextSize end
				if kind == "entry" and suffix == "Activation" and Panels.ClearEntryCustomCooldownDuration then Panels:ClearEntryCustomCooldownDuration(panelId, entryId, true) end
				if kind == "entry" and (suffix == "Visibility" or suffix == "Display") and Helper.UpdatePanelEntrySpecFilterState then Helper.UpdatePanelEntrySpecFilterState(panel) end
				if suffix == "Glow" and Panels.ClearReadyGlowEntryState then
					if kind == "entry" then Panels.ClearReadyGlowEntryState(panelId, entryId, true)
					else for id in pairs(panel.entries or {}) do Panels.ClearReadyGlowEntryState(panelId, id, true) end end
				end
				if suffix == "Keybinds" and Helper.Keybinds and Helper.Keybinds.MarkPanelsDirty then Helper.Keybinds.MarkPanelsDirty() end
				if kind == "panel" and suffix == "StaticText" then
					for _, entry in pairs(panel.entries or {}) do
						for _, field in ipairs(resetFields) do if field ~= "staticText" and field ~= "staticTextShowOnCooldown" then entry[field] = copy(defaults[field]) end end
					end
				end
				if kind == "entry" and bars and bars.HandleEntryStylePaste then
					bars.HandleEntryStylePaste(panelId, entryId, target, bars.IsBarDisplayModeValue(target.displayMode))
				end
				refresh(kind, panelId, suffix == "Activation" or suffix == "AuraBehavior" or suffix == "Sound" or suffix == "Charges" or suffix == "Stacks" or suffix == "Visibility" or suffix == "Display" or suffix == "Glow")
			end
		elseif kind == "fixed" and id ~= "cooldownPanelStandaloneFixedGroupGeneral" then
			header.navigationReset = function()
				if InCombatLockdown() then return end
				local panel = Panels:GetPanel(panelId)
				local group = panel and Panels.GetFixedGroupById(panel, groupId)
				if not group then return end
				local overrides = group.layoutOverrides or {}
				if id == "cooldownPanelStandaloneFixedGroupLayout" then
					group.dynamicStartPoint, group.dynamicDirection, overrides.spacing = "TOPLEFT", nil, nil
				elseif id == "cooldownPanelStandaloneFixedGroupIcon" then
					group.iconSize, group.iconSizeSeparate, group.iconWidth, group.iconHeight = nil, false, nil, nil
					overrides.iconOffsetX, overrides.iconOffsetY = nil, nil
				elseif id == "cooldownPanelStandaloneFixedGroupGlow" then
					for _, field in ipairs(scopes.Glow) do overrides[field] = nil end
					for _, spec in pairs(glowTabs) do for _, field in ipairs(spec.fields) do overrides[field] = nil end end
				end
				if Panels.SyncEntryFixedGroupState then
					for _, entry in pairs(panel.entries or {}) do
						if entry.fixedGroupId == group.id then Panels:SyncEntryFixedGroupState(panel, entry) end
					end
				end
				refresh(kind, panelId)
			end
		else header.navigationReset = nil end
	end
	-- Hints are attached only to controls whose visibility can be changed here.
	for _, data in ipairs(settings) do
		local group = controls[data.parentId or data.id] or {}
		if data.isShown then
			local parentId = data.parentId or data.id or ""
			if parentId == "cooldownPanelAnchor" then setHint(data, group[L["Enable Dynamic Anchoring"]])
			elseif parentId == "cooldownPanelLayout" then setHint(data, group[L["CooldownPanelLayoutMode"]])
			elseif (parentId == "cooldownPanelIcon" or parentId == "cooldownPanelStandaloneIcon")
				and (data.name == L["Icon size"] or data.name == "Icon size" or data.name == L["CooldownPanelIconWidth"] or data.name == L["CooldownPanelIconHeight"] or data.name == L["CooldownPanelSeparateIconSize"]) then
				data.navigationHint = function()
					local override = group[L["CooldownPanelUseCustomIconSize"]] or group[L["CooldownPanelOverwriteGlobalSize"]]
					local target = override and override.get and not override.get() and override or group[L["CooldownPanelSeparateIconSize"]]
					if target and target ~= data then return target.name, nil, target.parentId end
				end
			elseif parentId == "cooldownPanelBorder" then setHint(data, group[L["CooldownPanelIconBorder"]])
			elseif parentId == "cooldownPanelStandaloneStateTexture" then
				if data.name == L["CooldownPanelStateTextureMirrorSecond"] or data.name == L["CooldownPanelStateTextureMirrorVerticalSecond"] or data.name == L["CooldownPanelStateTextureSpacingX"] or data.name == L["CooldownPanelStateTextureSpacingY"] then
					setHint(data, group[L["CooldownPanelStateTextureDouble"]])
				end
			elseif parentId == "cooldownPanelStandaloneGlowThreshold" then
				setHint(data, group[L["CooldownPanelBarDurationThresholdGlowEnabled"]])
			elseif parentId == "cooldownPanelStandaloneActivation" and data.name == L["CooldownPanelCustomDurationSeconds"] then
				setHint(data, group[L["CooldownPanelCustomDuration"]])
			elseif parentId == "cooldownPanelGlow" or parentId == "cooldownPanelStandaloneGlow" or parentId == "cooldownPanelStandaloneFixedGroupGlow" then
				if data.name == L["CooldownPanelPixelGlowLines"] or data.name == L["CooldownPanelPixelGlowSpeed"] or data.name == L["CooldownPanelPixelGlowBorder"] or data.name == L["CooldownPanelGlowThickness"] then
					setHint(data, group[L["Glow style"]])
				end
			elseif parentId == "eqolCooldownPanelStandaloneBarIcon" then setHint(data, group[L["Show icon"]])
			elseif parentId == "eqolCooldownPanelStandaloneBarLabel" then setHint(data, group[L["CooldownPanelBarShowLabel"]])
			elseif parentId == "eqolCooldownPanelStandaloneBarValueText" then
				data.navigationHint = function()
					local panel = Panels:GetPanel(panelId)
					if kind == "panel" then
						local values = controls.eqolCooldownPanelStandaloneBarCooldown or controls.eqolCooldownPanelStandaloneBarCharges or {}
						local target = values[L["CooldownPanelBarShowValueText"]]
						if target then return target.name, nil, target.parentId end
						return
					end
					local entry = panel and panel.entries and panel.entries[entryId]
					local mode = entry and entry.barMode or (bars and bars.DEFAULTS.barMode)
					local display = controls.eqolCooldownPanelStandaloneBar or {}
					local values = controls[mode == "CHARGES" and "eqolCooldownPanelStandaloneBarCharges" or "eqolCooldownPanelStandaloneBarCooldown"] or {}
					local target = (mode == "CHARGES" or mode == "COOLDOWN") and values[L["CooldownPanelBarShowValueText"]] or display[L["Mode"]]
					if bars and bars.ShouldShowBarValueTextSettings(entry) then target = display[L["Mode"]] end
					if target then return target.name, nil, target.parentId end
				end
			elseif bars and parentId == bars.STANDALONE_DURATION_COLORS_SECTION_ID then
				local panel = Panels:GetPanel(panelId)
				local entry = panel and panel.entries and panel.entries[entryId]
				if kind == "panel" then
					setHint(data, group[L["CooldownPanelBarDurationColorsEnabled"]])
				elseif bars.IsNativeAuraBarEntry and not bars.IsNativeAuraBarEntry(entry) then
					data.navigationHint, data.navigationSearchExcluded = nil, true
				else setHint(data, controls.eqolCooldownPanelStandaloneBar and controls.eqolCooldownPanelStandaloneBar[L["Mode"]]) end
			elseif parentId == "eqolCooldownPanelStandaloneBar" and data.name == L["CooldownPanelCDMAuraOverlayOnlyMyDebuffs"] then
				setHint(data, group[L["CooldownPanelCDMAuraOverlayUnit"]])
			elseif kind ~= "panel" and parentId:find("eqolCooldownPanelStandaloneBar", 1, true) and parentId ~= "eqolCooldownPanelStandaloneBar" and parentId ~= "eqolCooldownPanelStandaloneBarVisibility" then
				local display = controls.eqolCooldownPanelStandaloneBar or {}
				setHint(data, display[L["Mode"]])
			end
		end
		if data._eqolHoverBuffModeDependent and kind == "panel" and (not data._eqolHoverBuffModeHint or data.navigationHint ~= data._eqolHoverBuffModeHint) then
			local originalHint = data.navigationHint
			data._eqolHoverBuffModeHint = function()
				if data._eqolHoverBuffModeDependent() then return L["CooldownPanelLayoutMode"], nil, "cooldownPanelLayout" end
				if originalHint then return originalHint() end
			end
			data.navigationHint = data._eqolHoverBuffModeHint
		end
	end
	local categories
	if kind == "panel" then categories = {
		category("general", L["General"], { "cooldownPanelGeneral", "cooldownPanelCopySettings" }),
		category("layout", L["Layout"], { "cooldownPanelLayout", hoverPanelGroup, "cooldownPanelAnchor", "eqolCooldownBarGroups" }),
		category("bar", L["Bar"], { "eqolCooldownPanelStandaloneBar", "eqolCooldownPanelStandaloneBarLayout", "eqolCooldownPanelStandaloneBarFill", "eqolCooldownPanelStandaloneBarBorder", "eqolCooldownPanelStandaloneBarIcon" }),
		category("icon", L["Icon"], { "cooldownPanelIcon", "cooldownPanelBorder", hoverStyleTabs.iconBorder, hoverStyleTabs.count }),
		category("appearance", L["QuickCastCopyAppearance"], { hoverStyleTabs.border, hoverStyleTabs.background, hoverStyleTabs.launcherBackground }),
		category("visibility", L["Visibility"], { "cooldownPanelVisibility", "cooldownPanelAvailability" }),
		category("text", L["Text"], { "cooldownPanelCooldownText", "cooldownPanelStaticText", "cooldownPanelStacks", "cooldownPanelCharges", "cooldownPanelKeybinds", "eqolCooldownPanelStandaloneBarLabel", "eqolCooldownPanelStandaloneBarValueText", hoverStyleTabs.font, hoverStyleTabs.titleFont }),
		category("behavior", L["Behavior"], { "eqolCooldownPanelStandaloneBarCooldown", "eqolCooldownPanelStandaloneBarCharges", bars and bars.STANDALONE_STACKS_SECTION_ID or "" }),
		category("effects", L["Effects"], { "cooldownPanelCooldownSwipe", "cooldownPanelAuraBehavior", hoverStyleTabs.swipe }),
		category("glow", L["Glow"], { "cooldownPanelGlow", "cooldownPanelGlowProc", "cooldownPanelGlowPandemic", "cooldownPanelGlowThreshold" }),
	} elseif kind == "fixed" then categories = {
		category("general", L["General"], { "cooldownPanelStandaloneFixedGroupGeneral", "cooldownPanelStandaloneFixedGroupLayout" }),
		category("appearance", L["QuickCastCopyAppearance"], { "cooldownPanelStandaloneFixedGroupIcon", "cooldownPanelStandaloneFixedGroupGlow" }),
	} else categories = {
		category("general", L["General"], { hoverEntryGroup, "cooldownPanelStandaloneDisplay", "cooldownPanelStandaloneVisibility", "cooldownPanelStandaloneAvailability", "eqolCooldownPanelStandaloneBarVisibility" }),
		category("bar", L["Bar"], { "eqolCooldownPanelStandaloneBar", "eqolCooldownPanelStandaloneBarLayout", "eqolCooldownPanelStandaloneBarFill", "eqolCooldownPanelStandaloneBarBorder", "eqolCooldownPanelStandaloneBarIcon" }),
		category("icon", L["Icon"], { "cooldownPanelStandaloneIcon", "cooldownPanelStandaloneStateTexture" }),
		category("text", L["Text"], { "cooldownPanelStandaloneCooldownText", "cooldownPanelStandaloneStaticText", "cooldownPanelStandaloneStacks", "cooldownPanelStandaloneCharges", "eqolCooldownPanelStandaloneBarLabel", "eqolCooldownPanelStandaloneBarValueText" }),
		category("behavior", L["Behavior"], { "eqolCooldownPanelStandaloneBarCooldown", "eqolCooldownPanelStandaloneBarCharges", bars and bars.STANDALONE_STACKS_SECTION_ID or "" }),
		category("effects", L["Effects"], { "cooldownPanelStandaloneCooldownSwipe", "cooldownPanelStandaloneActivation", bars and bars.STANDALONE_DURATION_COLORS_SECTION_ID or "", "cooldownPanelStandaloneSound" }),
		category("glow", L["Glow"], { "cooldownPanelStandaloneGlow", "cooldownPanelStandaloneGlowProc", "cooldownPanelStandaloneGlowPandemic", "cooldownPanelStandaloneGlowThreshold" }),
	} end
	return { categories = categories, stateKey = kind == "entry" and "cooldownPanels:entries" or nil, scopeKey = "cooldownPanels:" .. kind .. ":" .. tostring(panelId) .. ":" .. tostring(entryId or groupId or ""),
		canReset = function(tab) return tab.header.navigationReset ~= nil end }
end
