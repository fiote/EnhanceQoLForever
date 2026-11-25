local addon = _G.EnhanceQoL
local Panels = addon.Aura.CooldownPanels
local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL")

local Preset = {}
Panels.HoverBuffPreset = Preset

-- Recipient auras from Forever 1.60.1.71037. The tracked aura entry expands
-- ordinary spell families to their ranks. Other IDs are separate aura sources.
local categories = {
	-- Mark of the Wild, Gift of the Wild, Kings, Fish Bowl and Enchanted Lute.
	{ "Stats", 5232, { 21849, 20217, 25898, 1230098, 1230653 } },
	-- Fortitude, Prayer of Fortitude, Blood Pact and First Aid Kit.
	{ "Stamina", 1243, { 21562, 6307, 1230124 } },
	-- Battle Shout, Might, Greater Might, Furious Howl, Trueshot Aura and Lodestone.
	{ "AttackPower", 6673, { 19740, 25782, 25916, 24604, 1299346, 1299348, 19506, 20905, 20906, 1230164 } },
	-- Power of the Guardian from the warlock version of Atiesh.
	{ "SpellPower", 28143 },
	-- Moonkin Aura, Leader of the Pack, Power of the Guardian from mage Atiesh, and Camp Chair.
	{ "CriticalStrike", 24907, { 24932, 28142, 1229519 } },
	-- Sprint, Dash, Aspect of the Cheetah, Aspect of the Pack, Ghost Wolf and Swiftness Potion.
	{ "MovementSpeed", 2983, { 8696, 11305, 1850, 9821, 5118, 13159, 2645, 2379 }, pickerOnly = true },
}

function Preset:IsAvailable()
	return Panels.HoverBuffPanel and Panels.HoverBuffPanel:IsAvailable()
end

local function label(key) return L["CooldownPanelHoverBuffPreset" .. key] end

function Preset:AppendPickerEntries(append)
	for _, category in ipairs(categories) do
		local key, spellID, alternatives = unpack(category)
		append({
			key = "hover-buff:" .. key,
			kind = "HOVER_BUFF_AURA",
			category = "SPECIAL",
			value = key,
			name = label(key),
			icon = C_Spell.GetSpellTexture(spellID),
			searchIDs = spellID .. " " .. table.concat(alternatives or {}, " "),
			description = L["CooldownPanelPickerCombined"],
		})
	end
end

function Preset:FindEntry(panel, key)
	for id, entry in pairs(panel.entries) do
		if entry.type == "CDM_AURA" and entry.hoverBuffPresetKey == key then return id end
	end
end

function Preset:AddEntry(panelId, key)
	local panel = Panels:GetPanel(panelId)
	if not panel or not self:IsAvailable() or self:FindEntry(panel, key) then return end
	for _, category in ipairs(categories) do
		if category[1] == key then
			local spellIDs = {}
			for _, spellID in ipairs(category[3] or {}) do spellIDs[#spellIDs + 1] = spellID end
			return Panels:AddEntry(panelId, "CDM_AURA", category[2], {
				cdmAuraOverlaySpellIDs = spellIDs,
				hoverBuffPresetKey = key,
				buffName = label(key),
				auraUnit = "player",
				auraFilter = "HELPFUL",
			})
		end
	end
end

function Preset:CreatePanel()
	if not self:IsAvailable() then return nil end
	local panelId, panel = Panels:CreatePanel(L["CooldownPanelHoverBuffPresetRaid"])
	if not panel then return nil end
	local layout = panel.layout
	layout.layoutMode = "HOVER_BUFF"
	layout.hoverBuffIcon = 135995
	layout.hoverBuffTitle = nil
	layout.hoverBuffCount = true
	layout.hoverBuffPerRow = 2
	layout.hoverBuffAnimation = "REVEAL"
	layout.hoverBuffDisplay = "BOTH"

	for _, category in ipairs(categories) do
		if not category.pickerOnly and not self:AddEntry(panelId, category[1]) then
			Panels:DeletePanel(panelId)
			return nil
		end
	end
	return panelId
end
