local CP = _G.EnhanceQoL.Aura.CooldownPanels
local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL")
local Quick = {}
CP.QuickSetups = Quick

-- Both entry creation and the existing quick menu consume these same options.
function Quick:GetOptions(entry)
	if CP.helper.IsBarEntry(entry) then return CP.Bars.GetQuickSetupOptions(entry) end
	local options = {}
	local function add(id, text, apply, group) options[#options + 1] = { id = id, text = text, apply = apply, group = group } end
	if entry.type == "CDM_AURA" then
		for _, preset in ipairs(CP.ActionButtonOverlays.presets) do
			add("AURA:" .. preset[1], L[preset[2]], function(panelId, entryId, refresh)
				return CP.ActionButtonOverlays:ApplyPreset(panelId, entryId, preset[1], refresh)
			end, L["CooldownPanelOverlayTemplates"])
		end
	end
	local effectiveType = CP:GetLayoutEntryStandaloneEffectiveType(entry)
	local stacks = effectiveType == "SPELL" or effectiveType == "CDM_AURA"
	if effectiveType == "SLOT" then
		local slotID = tonumber(entry.slotID)
		stacks = slotID == 13 or slotID == 14
	end
	if stacks then
		add("STACKS", L["CooldownPanelQuickSetupStacksOnly"], function(panelId, entryId, refresh) return CP:ApplyStacksOnlyQuickSetup(panelId, entryId, refresh) end)
	end
	if effectiveType == "SPELL" or effectiveType == "CDM_AURA" then
		add("STATE", L["CooldownPanelStateTexture"], function(panelId, entryId, refresh) return CP:ApplyStateTextureQuickSetup(panelId, entryId, refresh) end)
	end
	local layouts, order = CP:GetTextInfoQuickSetupLayouts()
	for _, mode in ipairs({ "COOLDOWN", "ALWAYS" }) do
		local group = L[mode == "COOLDOWN" and "CooldownPanelQuickSetupTextInfoOnCooldown" or "CooldownPanelQuickSetupTextAlwaysWithCooldown"]
		for _, key in ipairs(order) do
			local layout = layouts[key]
			if layout then
				add(mode .. ":" .. key, L[layout.labelKey], function(panelId, entryId, refresh)
					if mode == "COOLDOWN" then return CP:ApplyTextInfoOnCooldownQuickSetup(panelId, entryId, refresh, key) end
					return CP:ApplyTextAlwaysWithCooldownQuickSetup(panelId, entryId, refresh, key)
				end, group)
			end
		end
	end
	if entry.type ~= "CDM_AURA" then
		add("READY", L["CooldownPanelQuickSetupTextInfoWhenReady"], function(panelId, entryId, refresh) return CP:ApplyTextInfoWhenReadyQuickSetup(panelId, entryId, refresh) end)
	end
	return options
end

function Quick:AppendMenu(root, entry, panelId, entryId)
	local groups = {}
	for _, option in ipairs(self:GetOptions(entry)) do
		local parent = root
		if option.group then
			groups[option.group] = groups[option.group] or root:CreateButton(option.group)
			parent = groups[option.group]
		end
		parent:CreateButton(option.text, function() option.apply(panelId, entryId, true) end)
	end
end
