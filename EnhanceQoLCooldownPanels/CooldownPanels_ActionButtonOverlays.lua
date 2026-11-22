local parentAddonName = "EnhanceQoL"
local addon = _G[parentAddonName]
if not addon then error(parentAddonName .. " is not loaded") end
local Panels = addon.Aura.CooldownPanels
local Helper = Panels.helper
local L = LibStub("AceLocale-3.0"):GetLocale(parentAddonName)
local Overlays = { proxies = {} }
Panels.ActionButtonOverlays = Overlays

Overlays.bars = {
	{ "ActionButton", "BINDING_HEADER_ACTIONBAR" },
	{ "MultiBarBottomLeftButton", "BINDING_HEADER_ACTIONBAR2" },
	{ "MultiBarBottomRightButton", "BINDING_HEADER_ACTIONBAR3" },
	{ "MultiBarRightButton", "BINDING_HEADER_ACTIONBAR4" },
	{ "MultiBarLeftButton", "BINDING_HEADER_ACTIONBAR5" },
	{ "MultiBar5Button", "BINDING_HEADER_ACTIONBAR6" },
	{ "MultiBar6Button", "BINDING_HEADER_ACTIONBAR7" },
	{ "MultiBar7Button", "BINDING_HEADER_ACTIONBAR8" },
}
Overlays.presets = {
	{ "ICON", "CooldownPanelOverlayIcon" },
	{ "FULL", "CooldownPanelOverlayFull" },
	{ "SWIPE", "CooldownPanelOverlaySwipe" },
	{ "TEXT", "CooldownPanelOverlayText" },
	{ "STACKS", "CooldownPanelQuickSetupStacksOnly" },
	{ "GLOW", "CooldownPanelOverlayGlow" },
}

local function plainNumber(value)
	return not (issecretvalue and issecretvalue(value)) and type(value) == "number"
end

Overlays.strata = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP" }

function Overlays:IsStrata(value)
	if (issecretvalue and issecretvalue(value)) or type(value) ~= "string" then return false end
	for _, strata in ipairs(self.strata) do if value == strata then return true end end
	return false
end

Overlays.presentationLayers = {
	visualHost = 0, cooldown = 1, overlay = 6, border = 2,
	counterOverlay = 6, layoutHandle = 26, previewGlowBorder = 3,
}

function Overlays:SyncPresentationLayer(icon, strata, level)
	for field, offset in pairs(self.presentationLayers) do
		local child = icon[field]
		if child then
			local currentStrata, currentLevel = child:GetFrameStrata(), child:GetFrameLevel()
			if self:IsStrata(currentStrata) and currentStrata ~= strata then child:SetFrameStrata(strata) end
			if plainNumber(currentLevel) and currentLevel ~= level + offset then child:SetFrameLevel(level + offset) end
		end
	end
	if Panels.AuraContainers and Panels.AuraContainers.SyncActionButtonLayer then Panels.AuraContainers:SyncActionButtonLayer(icon, strata, level) end
end

function Overlays:RefreshEntryLayer(entry)
	for _, proxy in pairs(self.proxies) do
		for icon, current in pairs(proxy.icons) do
			if current == entry and entry.actionButtonAnchor == proxy.buttonName then self:ApplyLayer(entry, icon) end
		end
	end
end

function Overlays:RestoreLayer(icon)
	local saved = icon._eqolActionButtonBaseLayer
	if not saved then return end
	icon:SetFrameStrata(saved.strata)
	icon:SetFrameLevel(saved.level)
	icon._eqolActionButtonBaseLayer = nil
	self:SyncPresentationLayer(icon, saved.strata, saved.level)
end

function Overlays:ApplyLayer(entry, icon)
	local strata = self:IsStrata(entry.actionButtonStrata) and entry.actionButtonStrata or "HIGH"
	local level = Helper.ClampInt(entry.actionButtonFrameLevel, 0, 10000, 20)
	if entry.actionButtonAutoLayer ~= false then
		local button = _G[entry.actionButtonAnchor]
		local sourceStrata = button and button:GetFrameStrata()
		local sourceLevel = button and button:GetFrameLevel()
		if self:IsStrata(sourceStrata) then strata = sourceStrata else strata = "HIGH" end
		local offset = Helper.ClampInt(entry.actionButtonLevelOffset, 1, 1000, 20)
		level = plainNumber(sourceLevel) and math.min(10000, sourceLevel + offset) or 20
	end
	local currentStrata, currentLevel = icon:GetFrameStrata(), icon:GetFrameLevel()
	if not self:IsStrata(currentStrata) or not plainNumber(currentLevel) then return end
	if not icon._eqolActionButtonBaseLayer then icon._eqolActionButtonBaseLayer = { strata = currentStrata, level = currentLevel } end
	if currentStrata ~= strata then icon:SetFrameStrata(strata) end
	if currentLevel ~= level then icon:SetFrameLevel(level) end
	self:SyncPresentationLayer(icon, strata, level)
end

-- Resolve only ordinary action data. The button's live action slot includes paging.
function Overlays:GetButtonLabel(name, index)
	local label = tostring(index)
	local button = _G[name]
	if not button then return label end
	local slot = button.action
	if not (issecretvalue and issecretvalue(slot)) and slot == nil and button.GetAttribute then slot = button:GetAttribute("action") end
	if not plainNumber(slot) or slot <= 0 then return label end
	local textureAPI = _G.GetActionTexture or (_G.C_ActionBar and _G.C_ActionBar.GetActionTexture)
	local infoAPI = _G.GetActionInfo or (_G.C_ActionBar and _G.C_ActionBar.GetActionInfo)
	local texture = textureAPI and textureAPI(slot)
	local kind, id
	if infoAPI then kind, id = infoAPI(slot) end
	local title
	if not (issecretvalue and issecretvalue(kind)) and plainNumber(id) and id > 0 then
		if kind == "spell" then
			if _G.C_Spell and _G.C_Spell.GetSpellName then title = _G.C_Spell.GetSpellName(id)
			elseif _G.GetSpellInfo then title = _G.GetSpellInfo(id) end
		elseif kind == "item" then
			local getItem = _G.GetItemInfo or (_G.C_Item and _G.C_Item.GetItemInfo)
			if getItem then title = getItem(id) end
		elseif kind == "macro" and _G.GetMacroInfo then title = _G.GetMacroInfo(id) end
	end
	if not (issecretvalue and issecretvalue(texture)) and (type(texture) == "number" or type(texture) == "string") then
		label = label .. ": |T" .. texture .. ":16:16:0:0|t"
	end
	if not (issecretvalue and issecretvalue(title)) and type(title) == "string" and title ~= "" then
		label = label .. (label == tostring(index) and ": " or " ") .. title
	end
	return label
end

function Overlays:IsButtonName(name)
	if type(name) ~= "string" then return false end
	for _, bar in ipairs(self.bars) do
		local index = name:match("^" .. bar[1] .. "(%d+)$")
		if index and tonumber(index) >= 1 and tonumber(index) <= 12 then return true end
	end
	return false
end

function Overlays:ReadGeometry(name)
	local button = _G[name]
	if not button or not button.GetCenter then return nil end
	local x, y = button:GetCenter()
	local scale = button:GetEffectiveScale()
	local rootScale = UIParent:GetEffectiveScale()
	local width, height = button:GetSize()
	-- Action button geometry can become restricted; never derive values from secrets.
	if not (plainNumber(x) and plainNumber(y) and plainNumber(scale) and plainNumber(rootScale) and plainNumber(width) and plainNumber(height)) then return nil end
	if scale <= 0 or rootScale <= 0 or width <= 0 or height <= 0 then return nil end
	return x * scale / rootScale, y * scale / rootScale, width * scale, height * scale
end

function Overlays:UpdateProxy(proxy)
	local x, y, width, height = self:ReadGeometry(proxy.buttonName)
	if not x then return false end
	if proxy.x ~= x or proxy.y ~= y then
		proxy:ClearAllPoints()
		proxy:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
		proxy.x, proxy.y = x, y
	end
	proxy.widthPixels, proxy.heightPixels = width, height
	return true
end

function Overlays:EnsureTracker()
	if self.tracker then return end
	self.tracker = CreateFrame("Frame")
	self.tracker.elapsed = 0
	self.tracker:SetScript("OnUpdate", function(frame, elapsed)
		frame.elapsed = frame.elapsed + elapsed
		if frame.elapsed < 0.1 then return end
		frame.elapsed = 0
		local active = false
		for _, proxy in pairs(Overlays.proxies) do
			local used = false
			for icon, entry in pairs(proxy.icons) do
				if entry.actionButtonAnchor ~= proxy.buttonName or icon.entryId ~= entry.id or not icon:IsShown() then
					proxy.icons[icon] = nil
				else used = true end
			end
			if used then
				active = true
				if Overlays:UpdateProxy(proxy) then
					for icon, entry in pairs(proxy.icons) do
						Overlays:ApplyLayer(entry, icon)
						if entry.actionButtonMatchSize ~= false then
							local scale = icon:GetEffectiveScale()
							if plainNumber(scale) and scale > 0 then
								local width, height = proxy.widthPixels / scale, proxy.heightPixels / scale
								local currentWidth, currentHeight = icon:GetSize()
								if plainNumber(currentWidth) and plainNumber(currentHeight) and (currentWidth ~= width or currentHeight ~= height) then icon:SetSize(width, height) end
							end
						end
					end
				end
			end
		end
		if not active then frame:Hide() end
	end)
end

function Overlays:GetAnchor(entry, icon)
	if not entry or entry.type ~= "CDM_AURA" or Helper.IsBarEntry(entry) or not self:IsButtonName(entry.actionButtonAnchor) then
		self:RestoreLayer(icon)
		return nil
	end
	local name = entry.actionButtonAnchor
	local proxy = self.proxies[name]
	if not proxy then
		proxy = CreateFrame("Frame", nil, UIParent)
		proxy:SetSize(1, 1)
		proxy.buttonName = name
		proxy.icons = setmetatable({}, { __mode = "k" })
		self.proxies[name] = proxy
	end
	if not self:UpdateProxy(proxy) then
		self:RestoreLayer(icon)
		return nil
	end
	self:ApplyLayer(entry, icon)
	proxy.icons[icon] = entry
	self:EnsureTracker()
	self.tracker:Show()
	local scale = icon:GetEffectiveScale()
	if entry.actionButtonMatchSize ~= false and plainNumber(scale) and scale > 0 then
		return proxy, proxy.widthPixels / scale, proxy.heightPixels / scale
	end
	return proxy
end

function Overlays:ApplyPreset(panelId, entryId, preset, refreshDialog)
	if InCombatLockdown() then return false end
	local panel = Panels:GetPanel(panelId)
	local entry = panel and panel.entries and panel.entries[entryId]
	if not entry or entry.type ~= "CDM_AURA" or Helper.IsBarEntry(entry) then return false end
	local valid = false
	for _, option in ipairs(self.presets) do if option[1] == preset then valid = true end end
	if not valid then return false end
	Panels:DisableEntryGlowForQuickSetup(panelId, entryId, entry)
	Panels:DisableEntryCountersForQuickSetup(entry)
	entry.alwaysShow = false
	entry.cdmAuraAlwaysShowUseGlobal = false
	entry.cdmAuraAlwaysShowMode = "HIDE"
	entry.hideIcon = false
	entry.showIconTextureUseGlobal = false
	entry.showIconTexture = preset == "ICON" or preset == "FULL"
	entry.showCooldown = preset == "FULL" or preset == "SWIPE" or preset == "TEXT"
	entry.showCooldownTextUseGlobal = false
	entry.showCooldownText = preset == "FULL" or preset == "TEXT"
	entry.cooldownVisualsUseGlobal = false
	entry.cooldownDrawSwipe = preset == "FULL" or preset == "SWIPE"
	entry.cooldownDrawEdge = false
	entry.cooldownDrawBling = false
	entry.showStacksUseGlobal = false
	entry.showStacks = preset == "STACKS" or preset == "FULL"
	entry.stackStyleUseGlobal = false
	entry.stackAnchor = "CENTER"
	entry.stackX, entry.stackY = 0, 0
	entry.stackFontSize = 20
	entry.cooldownTextUseGlobal = false
	entry.cooldownTextX, entry.cooldownTextY = 0, 0
	entry.showChargesUseGlobal = false
	entry.staticText = ""
	entry.staticTextShowOnCooldown = false
	entry.glowReadyUseGlobal = false
	entry.glowReady = preset == "GLOW" or preset == "FULL"
	entry.glowStyle = "BLIZZARD"
	entry.glowUseGlobal = false
	entry.glowDuration = 0
	entry.glowUseClassColor = false
	entry.glowColor = { 1, 0.82, 0.2, 1 }
	entry.pandemicGlow = false
	entry.auraDurationThresholdShowEnabled = false
	entry.auraDurationThresholdGlowEnabled = false
	entry.cdmAuraOverlayEnabledUseGlobal = false
	entry.cdmAuraOverlayEnabled = false
	entry.stateTextureInput = ""
	Panels:RefreshEntryStyleMutation(panelId, entryId, entry, refreshDialog ~= false)
	return true
end

function Overlays:GenerateButtonMenu(root, get, set)
	root:CreateRadio(_G.NONE, function() return not get() end, function() set(nil) end)
	for _, bar in ipairs(self.bars) do
		if _G[bar[1] .. "1"] then
			local menu = root:CreateButton(_G[bar[2]] or bar[1])
			for index = 1, 12 do
				local name = bar[1] .. index
				if _G[name] then menu:CreateRadio(self:GetButtonLabel(name, index), function() return get() == name end, function() set(name) end) end
			end
		end
	end
end

function Overlays:AppendSettings(settings, panelId, entryId)
	local types = addon.EditModeLib.SettingType
	local function entry()
		local panel = Panels:GetPanel(panelId)
		return panel and panel.entries and panel.entries[entryId]
	end
	local function shown()
		local current = entry()
		return current and current.type == "CDM_AURA" and not Helper.IsBarEntry(current)
	end
	local function set(field, value)
		if InCombatLockdown() then return end
		local current = entry()
		if not current then return end
		current[field] = value
		if field == "actionButtonAnchor" or field == "actionButtonMatchSize" then
			Panels:RefreshPanel(panelId)
			if field == "actionButtonAnchor" then
				local internal = addon.EditModeLib and addon.EditModeLib.internal
				if internal and internal.RefreshSettingValues then internal:RefreshSettingValues() end
			end
		else
			Overlays:RefreshEntryLayer(current)
		end
	end
	settings[#settings + 1] = {
		name = L["CooldownPanelActionButtonAnchor"], kind = types.Dropdown,
		parentId = "cooldownPanelStandaloneIcon", navigationField = "actionButtonAnchor", height = 260,
		isShown = shown, navigationSearchExcluded = not shown(), navigationDefaultVerified = true,
		navigationReset = function() set("actionButtonAnchor", nil) end,
		get = function() return entry() and entry().actionButtonAnchor or "NONE" end,
		set = function(_, value) set("actionButtonAnchor", Overlays:IsButtonName(value) and value or nil) end,
		generator = function(_, root)
			Overlays:GenerateButtonMenu(root, function() return entry() and entry().actionButtonAnchor end, function(value) set("actionButtonAnchor", value) end)
		end,
	}
	settings[#settings + 1] = {
		name = L["CooldownPanelActionButtonMatchSize"], kind = types.Checkbox,
		parentId = "cooldownPanelStandaloneIcon", navigationField = "actionButtonMatchSize", default = true,
		navigationDefaultVerified = true, isShown = shown, navigationSearchExcluded = not shown(),
		isEnabled = function() return entry() and Overlays:IsButtonName(entry().actionButtonAnchor) end,
		get = function() return not entry() or entry().actionButtonMatchSize ~= false end,
		set = function(_, value) set("actionButtonMatchSize", value == true) end,
	}
	local function anchored()
		return shown() and Overlays:IsButtonName(entry().actionButtonAnchor)
	end
	local function automatic() return not entry() or entry().actionButtonAutoLayer ~= false end
	settings[#settings + 1] = {
		name = L["CooldownPanelActionButtonAutoLayer"], kind = types.Checkbox,
		parentId = "cooldownPanelStandaloneIcon", navigationField = "actionButtonAutoLayer", default = true,
		navigationDefaultVerified = true, isShown = shown, navigationSearchExcluded = not shown(), isEnabled = anchored,
		get = automatic, set = function(_, value) set("actionButtonAutoLayer", value == true) end,
	}
	settings[#settings + 1] = {
		name = L["Strata"], kind = types.Dropdown,
		parentId = "cooldownPanelStandaloneIcon", navigationField = "actionButtonStrata", default = "HIGH", height = 220,
		navigationDefaultVerified = true, isShown = shown, navigationSearchExcluded = not shown(),
		isEnabled = function() return anchored() and not automatic() end,
		get = function() return entry() and entry().actionButtonStrata or "HIGH" end,
		set = function(_, value) if Overlays:IsStrata(value) then set("actionButtonStrata", value) end end,
		values = (function()
			local values = {}
			for _, strata in ipairs(Overlays.strata) do values[#values + 1] = { value = strata, text = strata } end
			return values
		end)(),
	}
	for _, option in ipairs({
		{ "actionButtonFrameLevel", "UFFrameLevel", 0, 10000, 20, false },
		{ "actionButtonLevelOffset", "UFDetachedPowerLevelOffset", 1, 1000, 20, true },
	}) do
		settings[#settings + 1] = {
			name = L[option[2]], kind = types.Slider, allowInput = true,
			parentId = "cooldownPanelStandaloneIcon", navigationField = option[1], default = option[5],
			minValue = option[3], maxValue = option[4], valueStep = 1,
			navigationDefaultVerified = true, isShown = shown, navigationSearchExcluded = not shown(),
			isEnabled = function() return anchored() and automatic() == option[6] end,
			get = function() return Helper.ClampInt(entry() and entry()[option[1]], option[3], option[4], option[5]) end,
			set = function(_, value) set(option[1], Helper.ClampInt(value, option[3], option[4], option[5])) end,
		}
	end
end

function Overlays:AppendMenu(root, panelId, entryId)
	local panel = Panels:GetPanel(panelId)
	local entry = panel and panel.entries and panel.entries[entryId]
	if not entry or entry.type ~= "CDM_AURA" or Helper.IsBarEntry(entry) then return end
	local menu = root:CreateButton(L["CooldownPanelOverlayTemplates"])
	for _, option in ipairs(self.presets) do
		menu:CreateButton(L[option[2]], function() Overlays:ApplyPreset(panelId, entryId, option[1]) end)
	end
end
