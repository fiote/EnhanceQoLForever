local _, addon = ...
addon = _G.EnhanceQoL or addon
addon.Aura = addon.Aura or {}

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL")
local Navigation = {}
addon.Aura.GroupFrameNavigation = Navigation

function Navigation.AppendPartyFrameStrataSetting(settings, editModeId, getCfg)
	local frames = addon.Aura.UF.GroupFrames
	settings[#settings + 1] = {
		name = L["Frame strata"] or "Frame strata",
		kind = addon.EditModeLib.SettingType.Dropdown,
		field = "frameStrata",
		parentId = "frame",
		default = "",
		values = frames._FRAME_STRATA_OPTIONS_WITH_DEFAULT,
		get = function() return frames.NormalizeFrameStrataToken(getCfg("party").frameStrata) or "" end,
		set = function(_, value)
			local cfg = getCfg("party")
			if not cfg then return end
			cfg.frameStrata = frames.NormalizeFrameStrataToken(value)
			if addon.EditMode and addon.EditMode.SetValue then addon.EditMode:SetValue(editModeId, "frameStrata", cfg.frameStrata or "", nil, true) end
			frames:ApplyHeaderAttributes("party")
		end,
	}
end

local function isBarTextField(field, prefix)
	if type(field) ~= "string" or field:sub(1, #prefix) ~= prefix then return false end
	local suffix = field:sub(#prefix + 1)
	return suffix:match("^Text%u") ~= nil
		or suffix:match("^Font") ~= nil
		or suffix:match("^Delimiter") ~= nil
		or suffix:match("^Left[XY]$") ~= nil
		or suffix:match("^Center[XY]$") ~= nil
		or suffix:match("^Right[XY]$") ~= nil
		or suffix == "HidePercent"
		or suffix == "RoundPercent"
		or suffix == "ShortNumbers"
		or suffix == "NameMaxChars"
		or suffix == "NameFirstWord"
end

local function barTextSplit(id)
	return function(data)
		local field = data.navigationField or data.field or ""
		if id == "health" then
			if field:match("^healthBackdrop") or field:match("^healthDeadBackdrop") then return "healthBackdrop", L["Background"] end
			if field:match("^healthGradient") or field == "healthColor" or field == "healthUseCustomColor" or field == "healthClassColor" then return "healthColors", L["Colors"] end
		end
		if isBarTextField(data.navigationField or data.field, id) then return id .. "Text", L["Text"] end
		return id, L["Bar"]
	end
end

function Navigation.Build(kind)
	return {
		categories = {
			{ id = "frame", name = L["Frame"], groups = { "frame", "layout", "border", "partyGroupBorder" } },
			{ id = "portrait", name = L["Portrait"], groups = { "portrait", "portraitDecoration", "portraitLevel", "portraitCast", "petPortrait" } },
			{ id = "highlight", name = L["Highlight"], groups = { "hoverHighlight", "aggroHighlight", "targetHighlight", "rangeFade" } },
			{ id = "health", name = L["Health"], groups = { "health", "incomingheal", "absorb", "healabsorb" } },
			{ id = "power", name = L["Power"], groups = { "power" } },
			{ id = "text", name = L["UFNavNameStatus"], groups = { "text", "level", "statustext" } },
			{ id = "dataBar", name = L["UFDataBar"], groups = { "dataBar" } },
			{ id = "auras", name = L["Auras"], groups = { "buffs", "debuffs", "externals" } },
			{ id = "indicators", name = L["UFNavIndicators"], groups = { "groupicons", "statusicons", "roleicons", "raidmarker", "dispeltint" } },
			{ id = "group", name = L["Group"], groups = { "party", "raid" } },
			{ id = "pets", name = L["UFPartyPetFrames"], groups = { "partyPets", "petBuffs", "petDebuffs", "petExternals" } },
			{ id = "raidBlocks", name = L["UFRaidBlocks"], groups = { "raidBlocks", "raidBlock1", "raidBlock2", "raidBlock3", "raidBlock4", "raidBlock5", "raidBlock6", "raidBlock7", "raidBlock8" } },
			{ id = "other", name = L["Other"], groups = { "utility" } },
		},
		tabNames = { frame = L["General"], partyPets = L["General"], text = _G.NAME or L["Name"], utility = _G.SETTINGS or L["Settings"] },
		splitGroups = {
			portrait = function(data)
				local field = data.navigationField or data.field or ""
				if data.navigationTab == "portraitBorder" or field:match("^portraitBorder") or field:match("^portraitDetachedBorder") or field:match("^portraitSeparator") then
					return "portraitBorder", L["Border"]
				end
				if data.navigationTab == "portraitPosition" or field == "portraitSide" or field:match("^portraitDetached") then
					return "portraitPosition", L["Position"]
				end
				return "portraitGeneral", L["General"]
			end,
			health = barTextSplit("health"),
			power = barTextSplit("power"),
			dataBar = barTextSplit("dataBar"),
			statustext = function(data)
				local field = data.navigationField or data.field or ""
				if kind ~= "party" and (field:match("^groupNumber") or field == "statusTextShowGroup" or field == "statusTextGroupFormat") then return "groupNumber", L["Group number"] end
				return "statustext", L["Status text"]
			end,
		},
		canReset = function(tab)
			for _, data in ipairs(tab.settings) do
				if not data.navigationSearchExcluded and not data.navigationResetExcluded and data.kind ~= addon.EditModeLib.SettingType.Divider
					and data.kind ~= addon.EditModeLib.SettingType.Label and not data.navigationDefaultVerified and not data.navigationReset then return false end
			end
			return true
		end,
		reset = function(tab, apply)
			local uf = addon.Aura.UF
			local blocks = uf and uf.RaidBlocks
			if blocks and tab.sourceGroup and tab.sourceGroup:match("^raidBlock") then return blocks.RunSettingsReset(apply) end
			local frames = uf and uf.GroupFrames
			if tab.sourceGroup ~= "portrait" or not frames or not kind then return apply() end
			local previous = frames._portraitSettingsResetKind
			frames._portraitSettingsResetKind = kind
			local ok, err = pcall(apply)
			frames._portraitSettingsResetKind = previous
			if previous ~= kind then frames:ApplyHeaderAttributes(kind) end
			if not ok then error(err, 0) end
		end,
		visibilityHint = function(data) return data.navigationHint end,
	}
end

function Navigation.AppendPartyPetPortraitSettings(settings, editModeId, getCfg, refreshSettings)
	local frames = addon.Aura.UF.GroupFrames
	local helper = addon.Aura.UF.GroupFramesHelper
	local types = addon.EditModeLib.SettingType
	local section = "petPortrait"
	local function save(field, value)
		local cfg = getCfg("party")
		if not cfg then return end
		cfg.petFrames = cfg.petFrames or {}
		local position = field and cfg.petFrames.portrait or nil
		position = type(position) == "table" and position or {}
		if field then position[field] = value end
		cfg.petFrames.portrait = position
		if addon.EditMode and addon.EditMode.SetValue then
			addon.EditMode:SetValue(editModeId, "partyPetPortrait", CopyTable(position), nil, true)
		end
		frames:ApplyHeaderAttributes("party")
		if field == nil or field == "enabled" or field == "detached" or field == "side" then refreshSettings() end
	end
	local function isAvailable()
		local cfg = getCfg("party")
		return cfg and cfg.petFrames and cfg.petFrames.enabled == true
	end
	local function isPortraitEnabled() return frames.ResolveGroupPortraitConfig(getCfg("party"), "party", true) end
	local function isDetached() return frames.ResolveGroupPortraitDetachedConfig(getCfg("party"), "party", true) end
	local function getSide()
		local cfg = getCfg("party")
		local portrait = cfg and cfg.petFrames and cfg.petFrames.portrait
		local side = type(portrait) == "table" and portrait.side or nil
		return helper.PARTY_PET_PORTRAIT_ANCHORS[side] and side or ""
	end
	settings[#settings + 1] = {
		name = L["UFPartyPetPortrait"], kind = types.Collapsible, id = section, defaultCollapsed = true,
		navigationReset = function() save() end,
	}
	settings[#settings + 1] = {
		name = L["Enable portrait"], kind = types.Checkbox, field = "partyPetPortraitEnabled", parentId = section,
		default = false, isEnabled = isAvailable, get = isPortraitEnabled,
		set = function(_, value) save("enabled", value == true) end,
	}
	settings[#settings + 1] = {
		name = L["UFPortraitDetached"], kind = types.Checkbox, field = "partyPetPortraitDetached", parentId = section,
		default = false, isEnabled = function() return isAvailable() and isPortraitEnabled() end, get = isDetached,
		set = function(_, value) save("detached", value == true) end,
	}
	settings[#settings + 1] = {
		name = L["Side"], kind = types.Dropdown, field = "partyPetPortraitSide", parentId = section, default = "",
		values = {
			{ value = "", label = L["Default"] },
			{ value = "LEFT", label = L["Left"] },
			{ value = "RIGHT", label = L["Right"] },
			{ value = "TOP", label = L["Top"] },
			{ value = "BOTTOM", label = L["Bottom"] },
		},
		isEnabled = function() return isAvailable() and isPortraitEnabled() end,
		get = getSide,
		set = function(_, value) save("side", helper.PARTY_PET_PORTRAIT_ANCHORS[value] and value or nil) end,
	}
	settings[#settings + 1] = {
		name = L["Scale"], kind = types.Slider, allowInput = true, field = "partyPetPortraitScale", parentId = section,
		minValue = 0.5, maxValue = 2, valueStep = 0.05, default = 1,
		formatter = function(value) return string.format("%.2f", value) end,
		isEnabled = function() return isAvailable() and isPortraitEnabled() end,
		get = function() return helper.GetPartyPetPortraitScale(getCfg("party")) end,
		set = function(_, value) save("scale", helper.ClampNumber(value, 0.5, 2, 1)) end,
	}
	for index, axis in ipairs({ "X", "Y" }) do
		settings[#settings + 1] = {
			name = L["Offset " .. axis], kind = types.Slider, allowInput = true,
			field = "partyPetPortraitOffset" .. axis, parentId = section, minValue = -1000, maxValue = 1000, valueStep = 1, default = 0,
			isEnabled = function() return isAvailable() and isPortraitEnabled() and isDetached() end,
			get = function()
				local cfg = getCfg("party")
				if not cfg then return 0 end
				local _, x, y, size = frames.ResolveGroupPortraitDetachedConfig(cfg, "party", true)
				local value = y
				if index == 1 then value = x end
				if value ~= nil then return value end
				local pet = cfg.petFrames or {}
				local w = math.max(10, (tonumber(cfg.width) or 100) - (tonumber(pet.widthOffset) or 0))
				local h = math.max(10, (tonumber(cfg.height) or 24) - (tonumber(pet.heightOffset) or 0))
				return (select(index, frames.GetDefaultDetachedPortraitOffset(cfg, "party", w, h, (size or h) * helper.GetPartyPetPortraitScale(cfg))))
			end,
			set = function(_, value)
				local field = getSide() ~= "" and ("side" .. axis) or axis:lower()
				save(field, helper.ClampNumber(value, -1000, 1000, 0))
			end,
		}
	end
end

function Navigation.AppendPortraitSettings(settings, kind, editModeId, getCfg, refreshSettings, borderOptions)
	local frames = addon.Aura.UF.GroupFrames
	local helper = addon.Aura.UF.GroupFramesHelper
	local types = addon.EditModeLib.SettingType
	local defaultStyle = helper.GROUP_PORTRAIT_DECORATION_STYLE
	local styles = {
		{ value = "AUTO", label = L["UFPortraitFrameAuto"] },
		{ value = "GOLD", label = L["UFPortraitFrameGold"] },
		{ value = "GOLD_RING", label = L["UFPortraitFrameGoldRing"], roundOnly = true },
		{ value = "SILVER", label = L["UFPortraitFrameSilver"] },
		{ value = "BRONZE", label = L["UFPortraitFrameBronze"] },
		{ value = "GOLD_WINGED", label = L["UFPortraitFrameGoldWinged"] },
		{ value = "SILVER_WINGED", label = L["UFPortraitFrameSilverWinged"] },
		{ value = "BRONZE_WINGED", label = L["UFPortraitFrameBronzeWinged"] },
	}
	local getAtlasInfo = C_Texture and C_Texture.GetAtlasInfo
	local hasDelves = getAtlasInfo and getAtlasInfo("delves-companion-portrait-frame") ~= nil
	if getAtlasInfo and getAtlasInfo("ChallengeMode-SpikeyStar") then
		styles[#styles + 1] = { value = "SPIKEY_STAR", label = L["UFPortraitFrameSpikeyStar"], roundOnly = true }
	end
	if hasDelves then
		styles[#styles + 1] = { value = "DELVES", label = L["UFPortraitFrameDelves"], roundOnly = true }
	end
	local function getPortrait()
		local cfg = getCfg(kind)
		return cfg and cfg.portrait or {}
	end
	local function isPortraitEnabled() return (frames.ResolveGroupPortraitConfig(getCfg(kind), kind)) end
	local function getShape() return select(6, frames.ResolveGroupPortraitConfig(getCfg(kind), kind)) end
	local function isRoundPortrait() return getShape() == "ROUND" end
	local function isDecorationEnabled() return getPortrait().classificationBorder == true end
	local function refresh()
		frames:ApplyHeaderAttributes(kind)
		refreshSettings()
	end
	local section, rows
	local function storeValue(cfg, row, key, value, nested)
		cfg.portrait = cfg.portrait or {}
		local storage = cfg.portrait
		if nested then
			storage[nested] = storage[nested] or {}
			storage = storage[nested]
		end
		if type(value) == "table" then value = CopyTable(value) end
		storage[key] = value
		local editMode = addon.EditMode
		if editMode and editMode.SetValue then editMode:SetValue(editModeId, row.field, value, nil, true) end
	end
	local function portraitHint() return L["Enable portrait"], nil, "portraitGeneral" end
	local function startSection(id, name)
		local entries = {}
		section, rows = id, entries
		settings[#settings + 1] = {
			name = name, kind = types.Collapsible, id = id, defaultCollapsed = true,
			isShown = isPortraitEnabled, navigationHint = portraitHint,
			navigationReset = function()
				local cfg = getCfg(kind)
				if not cfg then return end
				for _, entry in ipairs(entries) do storeValue(cfg, entry.row, entry.key, entry.row.default, entry.nested) end
				refresh()
			end,
		}
	end
	local function append(row, key, default, normalize, refreshControls, nested)
		row.parentId = section
		row.default = default
		row.get = function()
			local storage = getPortrait()
			if nested then storage = storage[nested] or {} end
			local value = storage[key]
			if value == nil then return default end
			return value
		end
		row.set = function(_, value)
			local cfg = getCfg(kind)
			if not cfg then return end
			if normalize then value = normalize(value) end
			if value == nil then return end
			storeValue(cfg, row, key, value, nested)
			frames:ApplyHeaderAttributes(kind)
			if refreshControls then refreshSettings() end
		end
		if rows then rows[#rows + 1] = { row = row, key = key, nested = nested } end
		settings[#settings + 1] = row
		return row
	end
	local function toBool(value) return value == true end
	local function addSlider(spec, enabled, nested, tab)
		return append({
			name = spec.name, kind = types.Slider, allowInput = true, field = spec.field or ("portrait." .. spec.key), navigationTab = tab,
			minValue = spec.min, maxValue = spec.max, valueStep = spec.step or 1, isEnabled = enabled,
		}, spec.key, spec.default, function(value) return math.max(spec.min, math.min(spec.max, tonumber(value) or spec.default)) end, nil, nested)
	end
	local function addLayer(key, enabled, tab)
		local row = addSlider({ name = L["UFPortraitLayer"], key = key, min = -1, max = 20, default = -1 }, enabled, nil, tab)
		row.formatter = function(value) return value < 0 and L["Default"] or tostring(value) end
		row.tooltip = L["UFPortraitLayerDesc"]
	end
	local function addColor(name, key, field, default, enabled, nested, tab)
		local function rgba(color)
			return { r = color.r or color[1], g = color.g or color[2], b = color.b or color[3], a = color.a or color[4] or 1 }
		end
		local row = append({
			name = name, kind = types.Color, field = field, navigationTab = tab, hasOpacity = true, isEnabled = enabled,
		}, key, default, function(color)
			if not color then return end
			color = rgba(color)
			return { color.r, color.g, color.b, color.a }
		end, nil, nested)
		local get = row.get
		row.get = function() return rgba(get()) end
	end
	startSection("portraitDecoration", L["UFPortraitDecorations"])
	append({ name = L["UFPortraitFrame"], kind = types.Checkbox, field = "portraitClassificationBorder" }, "classificationBorder", false, toBool, true)
	local function normalizeStyle(value)
		for _, style in ipairs(styles) do
			if style.value == value and (not style.roundOnly or isRoundPortrait()) then return value end
		end
	end
	append({
		name = L["UFPortraitFrameStyle"], kind = types.Dropdown, field = "portraitDecorationStyle", values = styles, isEnabled = isDecorationEnabled,
		generator = function(_, root, data)
			local isRound = isRoundPortrait()
			for _, style in ipairs(styles) do
				local radio = root:CreateRadio(style.label, function() return data.get() == style.value end, function() data.set(nil, style.value) end)
				if style.roundOnly and not isRound then radio:SetEnabled(false) end
			end
		end,
	}, "decorationStyle", defaultStyle, normalizeStyle, true)
	append({
		name = L["UFPortraitFrameMirror"], kind = types.Checkbox, field = "portraitDecorationMirror", isEnabled = isDecorationEnabled,
		isShown = function()
			local style = getPortrait().decorationStyle
			return style ~= "GOLD_RING" and style ~= "SPIKEY_STAR" and style ~= "DELVES"
		end,
		navigationHint = function() return L["UFPortraitFrameStyle"], nil, "portraitDecoration" end,
	}, "decorationMirror", false, toBool)
	addLayer("decorationLayer", isDecorationEnabled)
	for _, spec in ipairs({
		{ name = L["Scale"], key = "decorationScale", field = "portraitDecorationScale", min = 0.5, max = 2, step = 0.05, default = 1 },
		{ name = L["Offset X"], key = "decorationOffsetX", field = "portraitDecorationOffsetX", min = -128, max = 128, step = 1, default = 0 },
		{ name = L["Offset Y"], key = "decorationOffsetY", field = "portraitDecorationOffsetY", min = -128, max = 128, step = 1, default = 0 },
	}) do
		local row = addSlider(spec, isDecorationEnabled)
		if spec.key == "decorationScale" then row.formatter = function(value) return string.format("%.2f", value) end end
	end

	startSection("portraitLevel", L["Level"])
	local function showLevel() return getPortrait().decorationLevel == true end
	append({ name = L["UFPortraitFrameLevel"], kind = types.Checkbox, field = "portraitDecorationLevel" }, "decorationLevel", false, toBool)
	append({
		name = L["Font"], kind = types.Dropdown, field = "portraitDecorationLevelFont",
		generator = frames.DropdownRadioGenerator(frames.FontOptionsWithDefault), isEnabled = showLevel,
	}, "decorationLevelFont", frames.GlobalFontConfigKey())
	local outlineDefault = "__EQOL_GLOBAL_FONT_STYLE__"
	append({
		name = L["Font outline"], kind = types.Dropdown, field = "portraitDecorationLevelOutline", values = helper.outlineOptions, isEnabled = showLevel,
	}, "decorationLevelOutline", outlineDefault, function(value)
		return addon.functions.NormalizeFontStyleChoice and addon.functions.NormalizeFontStyleChoice(value, outlineDefault, true) or value or outlineDefault
	end)
	local fontSize = addSlider({ name = _G.FONT_SIZE or L["Size"], key = "decorationLevelFontSize", field = "portraitDecorationLevelFontSize", min = 0, max = 40, default = 0 }, showLevel)
	fontSize.formatter = function(value) return value == 0 and L["Default"] or tostring(value) end
	append({
		name = L["Use class color"], kind = types.Checkbox, field = "portraitDecorationLevelUseClassColor", isEnabled = showLevel,
	}, "decorationLevelUseClassColor", false, toBool)
	addColor(L["Color"], "decorationLevelColor", "portraitDecorationLevelColor", { 1, 0.82, 0, 1 }, function()
		return showLevel() and getPortrait().decorationLevelUseClassColor ~= true
	end)

	local function addDivider(name)
		settings[#settings + 1] = { name = name, kind = types.Divider, parentId = section }
	end
	startSection("portraitCast", L["Castbar"])
	local hasCastRing = not addon.variables.isTBC
	if hasCastRing then addDivider(L["Icon"]) end
	append({ name = L["UFPortraitCastIcon"], kind = types.Checkbox, field = "portraitCastIcon" }, "castIcon", false, toBool)
	if hasCastRing then
		local function supportsCastRing()
			local shape = getShape()
			return shape == "ROUND" or shape == "SQUARE" or shape == "STAR" or shape == "HEXAGON"
		end
		local function isPreviewing() return helper.IsGroupPortraitCastPreviewEnabled and helper.IsGroupPortraitCastPreviewEnabled(kind) or false end
		local function isCastRingEnabled() return supportsCastRing() and (getPortrait().castRing == true or isPreviewing()) end
		addDivider(L["Castbar"])
		append({ name = L["UFPortraitCastRing"], kind = types.Checkbox, field = "portraitCastRing", isEnabled = supportsCastRing }, "castRing", false, toBool)
		settings[#settings + 1] = {
			name = L["UFPortraitCastPreview"], kind = types.Checkbox, field = "portraitCastPreview", parentId = section,
			tooltip = L["UFPortraitCastPreviewDesc"], navigationResetExcluded = true, isEnabled = supportsCastRing,
			get = isPreviewing,
			set = function(_, value)
				helper.SetGroupPortraitCastPreview(kind, value == true, function() frames:RefreshGroupPortraits(kind) end)
				refreshSettings()
			end,
		}
		local textures = frames.DropdownRadioGenerator(helper.TextureOptions)
		addDivider(L["Bar style"])
		append({
			name = L["Texture"], kind = types.Dropdown, field = "portrait.castRingTexture", generator = textures, isEnabled = isCastRingEnabled,
		}, "castRingTexture", "SOLID")
		append({
			name = L["Use class color"], kind = types.Checkbox, field = "portrait.castRingUseClassColor", isEnabled = isCastRingEnabled,
		}, "castRingUseClassColor", false, toBool)
		addColor(L["Color"], "castRingColor", "portrait.castRingColor", { 1, 0.8, 0.2, 1 }, function()
			return isCastRingEnabled() and getPortrait().castRingUseClassColor ~= true
		end)
		addDivider(L["Background"])
		append({
			name = L["Background texture"], kind = types.Dropdown, field = "portrait.castRingBackgroundTexture", generator = textures, isEnabled = isCastRingEnabled,
		}, "castRingBackgroundTexture", "SOLID")
		addColor(L["Background color"], "castRingBackgroundColor", "portrait.castRingBackgroundColor", { 0.08, 0.06, 0.02, 0.7 }, isCastRingEnabled)
		addDivider(L["Layout"])
		addLayer("castRingLayer", isCastRingEnabled)
		local radial = Enum and Enum.StatusBarRenderMode and Enum.StatusBarRenderMode.Radial ~= nil
		for _, spec in ipairs({
			{ name = L["UFPortraitCastRingGap"], key = "castRingGap", min = -16, max = 80, default = 4 },
			{ name = L["Thickness"], key = "castRingThickness", min = 1, max = 32, default = 4 },
			{ name = L["UFPortraitCastRingArc"], key = "castRingArc", min = 30, max = 360, step = 5, default = 360 },
			{ name = L["UFPortraitCastRingRotation"], key = "castRingRotation", min = 0, max = 355, step = 5, default = 0 },
		}) do
			if radial or spec.key == "castRingGap" then
				local row = addSlider(spec, isCastRingEnabled)
				if spec.key == "castRingArc" then row.tooltip = L["UFPortraitCastRingArcDesc"] end
				row.isShown = function()
					local portrait = getPortrait()
					return not (hasDelves and portrait.classificationBorder == true and portrait.decorationStyle == "DELVES" and isRoundPortrait())
				end
				row.navigationHint = function() return L["UFPortraitFrameStyle"], nil, "portraitDecoration" end
			end
		end
	end

	section, rows = "portrait", nil
	local borderTab = "portraitBorder"
	local function usesCustomBorder()
		local border = getPortrait().border
		return border and border.inherit == false or false
	end
	local function isDetached() return (frames.ResolveGroupPortraitDetachedConfig(getCfg(kind), kind)) end
	local function canShowBorder() return isPortraitEnabled() and (isDetached() or usesCustomBorder()) end
	local function isBorderShown()
		local portrait = getPortrait()
		if portrait.detachedBorderEnabled ~= nil then return portrait.detachedBorderEnabled == true end
		local _, _, _, borderWithFrame = frames.ResolveGroupPortraitConfig(getCfg(kind), kind)
		return usesCustomBorder() or (isDetached() and borderWithFrame)
	end
	local function hasCustomBorder() return isPortraitEnabled() and usesCustomBorder() and isBorderShown() end
	local function resetInheritance(row, key, nested)
		row.navigationReset = function()
			local cfg = getCfg(kind)
			if not cfg then return end
			storeValue(cfg, row, key, nil, nested)
			refresh()
		end
	end
	local borderEnabled = append({
		name = L["Show border"], kind = types.Checkbox, field = "portraitBorderEnabled", navigationTab = borderTab, isEnabled = canShowBorder,
	}, "detachedBorderEnabled", true, toBool, true)
	borderEnabled.get = isBorderShown
	resetInheritance(borderEnabled, "detachedBorderEnabled")
	local borderInherit = append({
		name = L["UFPortraitBorderInherit"], kind = types.Checkbox, field = "portraitBorderInherit", navigationTab = borderTab, isEnabled = isPortraitEnabled,
	}, "inherit", true, toBool, true, "border")
	resetInheritance(borderInherit, "inherit", "border")
	append({
		name = L["Texture"], kind = types.Dropdown, field = "portraitBorderTexture", navigationTab = borderTab, isEnabled = hasCustomBorder,
		generator = frames.DropdownRadioGenerator(function() return borderOptions(getShape()) end),
	}, "texture", "DEFAULT", nil, nil, "border")
	addSlider({ name = L["Size"], key = "edgeSize", field = "portraitBorderSize", min = 1, max = 64, default = 1 }, hasCustomBorder, "border", borderTab)
	append({
		name = L["UFPortraitBorderColorMode"], kind = types.Dropdown, field = "portraitBorderColorMode", navigationTab = borderTab, isEnabled = hasCustomBorder,
		values = {
			{ value = "CUSTOM", label = L["UFPortraitBorderColorCustom"] },
			{ value = "CLASS", label = L["UFPortraitBorderColorClass"] },
			{ value = "REACTION", label = L["UFPortraitBorderColorReaction"] },
		},
	}, "colorMode", "CUSTOM", nil, true, "border")
	addColor(L["UFPortraitBorderColorCustom"], "color", "portraitBorderColor", { 0, 0, 0, 0.8 }, function()
		local border = getPortrait().border
		return hasCustomBorder() and (not border.colorMode or border.colorMode == "CUSTOM")
	end, "border", borderTab)
	local function hasPortraitBorder() return canShowBorder() and isBorderShown() end
	addLayer("borderLayer", hasPortraitBorder, borderTab)
	for _, row in ipairs(settings) do
		if row.field == "portraitDetachedBorderOffset" then
			row.navigationTab = borderTab
			row.isShown = isPortraitEnabled
			row.isEnabled = hasPortraitBorder
			row.navigationHint = portraitHint
			resetInheritance(row, "detachedBorderOffset")
			break
		end
	end
	local separatorRows = {}
	for i = #settings, 1, -1 do
		local field = settings[i].field
		if field and field:match("^portraitSeparator") then separatorRows[#separatorRows + 1] = table.remove(settings, i) end
	end
	settings[#settings + 1] = { name = L["Separator"], kind = types.Divider, parentId = section, navigationTab = borderTab }
	for i = #separatorRows, 1, -1 do settings[#settings + 1] = separatorRows[i] end
	append({
		name = L["Texture"], kind = types.Dropdown, field = "portraitSeparatorTexture", navigationTab = borderTab,
		generator = frames.DropdownRadioGenerator(helper.TextureOptions),
		isEnabled = function()
			local cfg = getCfg(kind)
			return isPortraitEnabled() and not frames.ResolveGroupPortraitDetachedConfig(cfg, kind)
				and frames.ResolveGroupPortraitSeparatorConfig(cfg, kind, true)
		end,
	}, "texture", "SOLID", nil, nil, "separator")
end

-- Keep the legacy shared texture authoritative until the user changes the mode.
function Navigation.ConfigureTextureSettings(settings, kind, editModeId, getCfg, defaults, textureOptions)
	local types = addon.EditModeLib.SettingType
	local function shared()
		local cfg = getCfg(kind)
		return cfg and cfg.barTexture ~= nil and cfg.barTexture ~= "" and cfg.barTexture ~= "__PER_BAR__"
	end
	local function individual(cfg, bar)
		return cfg[bar] and cfg[bar].texture or defaults[bar] and defaults[bar].texture or "DEFAULT"
	end
	local function split(cfg)
		if not shared() then return end
		for _, bar in ipairs({ "health", "power" }) do
			local previous = individual(cfg, bar)
			cfg[bar] = cfg[bar] or {}
			if previous ~= cfg.barTexture then cfg[bar].previousTexture = previous end
			cfg[bar].texture = cfg.barTexture
		end
		cfg.barTexture = "__PER_BAR__"
	end
	local function refresh()
		local cfg = getCfg(kind)
		local editMode = addon.EditMode
		if editMode and editMode.SetValue then
			editMode:SetValue(editModeId, "barTexture", cfg.barTexture or "__PER_BAR__", nil, true)
			for _, bar in ipairs({ "health", "power" }) do editMode:SetValue(editModeId, bar .. "Texture", individual(cfg, bar), nil, true) end
		end
		addon.Aura.UF.GroupFrames:ApplyHeaderAttributes(kind)
		local internal = addon.EditModeLib.internal
		if internal and internal.RequestRefreshSettings then internal:RequestRefreshSettings() end
	end
	for i = #settings, 1, -1 do
		local row = settings[i]
		local bar = row.field == "healthTexture" and "health" or row.field == "powerTexture" and "power"
		if bar then
			row.isEnabled = nil
			row.isShown = function() return not shared() end
			row.navigationHint = function() return L["UFGroupSharedTexture"], nil, bar end
			row.get = function() return individual(getCfg(kind), bar) end
			row.set = function(_, value)
				local cfg = getCfg(kind)
				if not cfg then return end
				split(cfg)
				cfg[bar] = cfg[bar] or {}
				cfg[bar].texture = value or "DEFAULT"
				refresh()
			end
			row.navigationReset = function() row.set(nil, defaults[bar] and defaults[bar].texture or "DEFAULT") end
			row.generator = function(_, root)
				for _, option in ipairs(textureOptions()) do
					root:CreateRadio(option.label, function() return row.get() == option.value end, function() row.set(nil, option.value) end)
				end
				local cfg = getCfg(kind)
				local previous = cfg and cfg[bar] and cfg[bar].previousTexture
				if previous and previous ~= row.get() then
					root:CreateButton(L["UFGroupRestoreTexture"], function() row.set(nil, previous) end)
				end
			end
			local common = {
				name = L["UFGroupSharedTexture"], kind = types.Dropdown,
				field = bar .. "SharedTexture", parentId = bar, height = row.height,
				navigationResetExcluded = true, isShown = shared,
				navigationHint = function() return row.name, nil, bar end,
				get = function() return getCfg(kind).barTexture end,
				set = function(_, value)
					local cfg = getCfg(kind)
					if not cfg then return end
					cfg.barTexture = value or "DEFAULT"
					refresh()
				end,
			}
			common.generator = function(_, root)
				for _, option in ipairs(textureOptions()) do
					root:CreateRadio(option.label, function() return common.get() == option.value end, function() common.set(nil, option.value) end)
				end
			end
			table.insert(settings, i, common)
			table.insert(settings, i, {
				name = L["UFGroupSharedTextureHint"], kind = types.Divider, parentId = bar,
				navigationSearchExcluded = true, navigationResetExcluded = true, isShown = shared,
			})
			table.insert(settings, i, {
				name = L["UFGroupLinkTextures"], kind = types.Checkbox, field = bar .. "LinkTextures", parentId = bar,
				navigationResetExcluded = true, get = shared,
				set = function(_, value)
					local cfg = getCfg(kind)
					if not cfg then return end
					if value then cfg.barTexture = shared() and cfg.barTexture or individual(cfg, bar) else split(cfg) end
					refresh()
				end,
			})
		end
	end
end

function Navigation.Prepare(settings, kind, factoryValues, factoryConfig)
	if factoryValues and factoryConfig then
		factoryValues.overallAlpha = 1
		local portrait, bar = factoryConfig.portrait or {}, factoryConfig.dataBar or {}
		local separator, border = portrait.separator or {}, factoryConfig.border or {}
		for field, key in pairs({
			portraitEnabled = "enabled", portraitMode = "mode", portraitShape = "shape", portraitSide = "side",
			portraitSquareBackground = "squareBackground", portraitBorderWithFrame = "borderWithFrame", portraitDetached = "detached",
		}) do factoryValues[field] = portrait[key] end
		factoryValues.portraitDetachedSize = portrait.detachedSize or factoryConfig.height or 24
		factoryValues.portraitDetachedOffsetX, factoryValues.portraitDetachedOffsetY = addon.Aura.UF.GroupFrames.GetDefaultDetachedPortraitOffset(factoryConfig, kind, factoryConfig.width, factoryConfig.height, factoryValues.portraitDetachedSize)
		factoryValues.portraitDetachedBorderOffset = portrait.detachedBorderOffset or border.offset or border.inset or border.edgeSize or 1
		factoryValues.portraitDetachedStrata = portrait.detachedStrata or ""
		factoryValues.portraitDetachedFrameLevelOffset = portrait.detachedFrameLevelOffset or 1
		factoryValues.portraitSeparatorEnabled = separator.enabled ~= false
		factoryValues.portraitSeparatorSize = separator.size or border.edgeSize or 1
		factoryValues.portraitSeparatorUseCustomColor = separator.useCustomColor == true
		for field, key in pairs({
			dataBarEnabled = "enabled", dataBarPosition = "position", dataBarHeight = "height", dataBarGap = "gap",
			dataBarDetached = "detached", dataBarDetachedMatchHealthWidth = "detachedMatchHealthWidth", dataBarDetachedGrowFromCenter = "detachedGrowFromCenter",
			dataBarDetachedFrameLevelOffset = "detachedFrameLevelOffset", dataBarClassColor = "useClassColor", dataBarTexture = "texture", dataBarCustomAtlas = "customAtlas",
			dataBarTextLeft = "textLeft", dataBarTextCenter = "textCenter", dataBarTextRight = "textRight", dataBarTextClassColor = "useTextClassColor",
			dataBarFontSize = "fontSize", dataBarFont = "font", dataBarFontOutline = "fontOutline", dataBarShortNumbers = "useShortNumbers",
			dataBarRoundPercent = "roundPercent", dataBarHidePercent = "hidePercentSymbol",
		}) do factoryValues[field] = bar[key] end
		factoryValues.dataBarDetachedWidth = bar.detachedWidth or factoryConfig.width or 100
		factoryValues.dataBarDetachedOffsetX = bar.detachedOffset and bar.detachedOffset.x or 0
		factoryValues.dataBarDetachedOffsetY = bar.detachedOffset and bar.detachedOffset.y or 0
		factoryValues.dataBarDetachedStrata = bar.detachedStrata or ""
		factoryValues.incomingHealTexture = factoryConfig.health and factoryConfig.health.incomingHealTexture or "DEFAULT"
		factoryValues.showBuffPlacementPreview = false
		factoryValues.debuffHidePermanentAuras = factoryConfig.auras and factoryConfig.auras.debuff and factoryConfig.auras.debuff.hidePermanentAuras == true
		factoryValues.groupBorderEnabled = factoryConfig.groupBorder and factoryConfig.groupBorder.enabled == true
		factoryValues.combatIndicatorIcon = factoryConfig.status and factoryConfig.status.combatIndicator and factoryConfig.status.combatIndicator.icon or addon.Aura.UF.COMBAT_INDICATOR_DEFAULT_ICON or "DEFAULT"
		factoryValues.externalDrFont = factoryConfig.auras and factoryConfig.auras.externals and factoryConfig.auras.externals.drFont or "__EQOL_GLOBAL_FONT__"
	end
	if addon.EditModeNavigationDefaults then addon.EditModeNavigationDefaults.Prepare(settings, factoryValues, true) end
	local inheritedFonts = {
		healthFont = true, powerFont = true, statusTextFont = true, groupNumberFont = true,
		buffCooldownTextFont = true, buffStackFont = true, debuffCooldownTextFont = true, debuffStackFont = true,
		externalCooldownTextFont = true, externalStackFont = true,
	}
	local unavailable = (addon.AuraCompat and addon.AuraCompat:HasNativeAuraAnimationSupport()) and {} or {
		dispelTintGlowEffect = true, dispelTintGlowFrequency = true, dispelTintGlowX = true,
		dispelTintGlowY = true, dispelTintGlowLines = true, dispelTintGlowThickness = true,
	}
	local fields = {}
	for _, data in ipairs(settings) do
		if data.field then fields[data.field] = data end
	end
	local function hint(data, targetField, tabId, explanation, enableField)
		local target = fields[targetField]
		if not target or not data.isShown then return end
		data.navigationHint = function()
			local enable = enableField and fields[enableField]
			if enable and enable.get and not enable.get() then return enable.name, nil, enable.parentId end
			if target.isShown and not target.isShown() and target.navigationHint then return target.navigationHint() end
			return target.name, nil, tabId or target.parentId, explanation
		end
	end
	for _, data in ipairs(settings) do
		local field = data.field or ""
		-- The checkbox or tab already identifies the indicator/text being edited.
		if field:match("^leaderIcon") or field:match("^raidAssignmentIcon") or field:match("^assistIcon") then
			if field:match("Size$") then data.name = L["Icon size"]
			elseif field:match("Point$") then data.name = L["Anchor"]
			elseif field:match("OffsetX$") then data.name = L["Offset X"]
			elseif field:match("OffsetY$") then data.name = L["Offset Y"] end
		elseif data.parentId == "level" or field:match("^groupNumber") or field:match("^portraitDetached") then
			if field:match("FontSize$") or field:match("Size$") then data.name = field:match("^portrait") and L["Size"] or (_G.FONT_SIZE or L["Font"])
			elseif field:match("Font$") then data.name = L["Font"]
			elseif field:match("FontOutline$") then data.name = L["Font outline"]
			elseif field:match("Strata$") then data.name = L["Strata"]
			elseif field:match("OffsetX$") then data.name = L["Offset X"]
			elseif field:match("OffsetY$") then data.name = L["Offset Y"] end
		end
		if factoryValues and inheritedFonts[field] and addon.EditModeNavigationDefaults then addon.EditModeNavigationDefaults.Set(data, factoryValues[field]) end
		local partyOnly = field:match("^powerDetached") or (field:match("^portraitDetached") and field ~= "portraitDetachedBorderOffset") or field:match("^groupBorder")
			or field == "buffAnchorOutside" or field == "debuffAnchorOutside" or field == "externalAnchorOutside"
		local raidOnly = field:match("^raidAssignmentIcon") or field:match("^groupIndicator") or field:match("^raidGroup%d+$") or field == "groupGrowth" or field == "groupsPerRow"
		local raidLikeOnly = field:match("^groupNumber") or field:match("^assistIcon") or field == "statusTextShowGroup" or field == "statusTextGroupFormat"
		local primaryOnly = field == "anchorTarget" or field == "showBuffPlacementPreview" or field == "groupBy" or field == "sortMethod"
			or field == "sortDir" or field:match("^customSort") or field == "dynamicScaleMin"
		local compatOnly = field == "dispelTintFilterMode" or field == "debuffBossAuraSize"
		if field == "copyFrom" or unavailable[field] or (kind ~= "party" and partyOnly) or (kind ~= "raid" and raidOnly)
			or (kind == "party" and raidLikeOnly) or (kind ~= "party" and kind ~= "raid" and primaryOnly) or (not addon.AuraCompat and compatOnly) then
			data.navigationSearchExcluded = true
		end
		if field == "dynamicAnchorProfile" or ((kind == "party" or kind == "raid") and data.parentId == "frame" and (field == "anchorTarget" or field == "point" or field == "relativePoint" or field == "x" or field == "y")) then
			hint(data, "dynamicAnchorEnabled", "frame")
		elseif kind == "party" and field:match("^portraitDetached") and field ~= "portraitDetached" and field ~= "portraitDetachedBorderOffset"
			and field ~= "portraitDetachedStrata" and field ~= "portraitDetachedFrameLevelOffset" then
			hint(data, "portraitDetached", "portraitPosition")
		elseif kind == "party" and field:match("^powerDetached") and field ~= "powerDetached" then
			hint(data, "powerDetached", "power")
		elseif field == "dataBarDetached" then
			hint(data, "dataBarEnabled", "dataBar")
		elseif field:match("^dataBarDetached") then
			hint(data, "dataBarDetached", "dataBar")
		elseif field == "dataBarNameMaxChars" or field == "dataBarNameFirstWord" then
			hint(data, "dataBarTextLeft", "dataBarText", nil, "dataBarEnabled")
		elseif field:match("^healthDelimiter") then
			hint(data, "healthTextLeft", "healthText", L["UFNavTextFormatHint"])
		elseif field:match("^powerDelimiter") then
			hint(data, "powerTextLeft", "powerText", L["UFNavTextFormatHint"])
		elseif field == "absorbGlow" or field == "absorbGlowClampToHealth" then
			hint(data, "healthOrientation", "health")
		elseif kind == "raid" and (field:match("^groupIndicator") or field:match("^raidGroup%d+$") or field == "groupsPerRow") then
			hint(data, "groupBy", "raid")
		end
	end
	return settings
end
