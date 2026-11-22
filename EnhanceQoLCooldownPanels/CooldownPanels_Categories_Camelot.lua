local addon = assert(_G.EnhanceQoL, "EnhanceQoL is not loaded")
local CP = addon.Aura.CooldownPanels
local Categories = {}
CP.CooldownCategories = Categories

-- Build only when the existing tracked-entry index changes, never on cooldown events.
function Categories.RebuildIndex(runtime)
	local entriesByCategory, spellsByCategory, readySpellsByCategory = {}, {}, {}
	local categories = CP.SpellCooldownCategories or {}
	for spellID, panels in pairs(runtime.spellEntryIndex or {}) do
		local category = categories[spellID]
		if category then
			for panelID, entries in pairs(panels) do
				for entryID, meta in pairs(entries) do
					if meta.trackCooldown == true then
						entriesByCategory[category] = entriesByCategory[category] or {}
						local targets = entriesByCategory[category]
						targets[panelID] = targets[panelID] or {}
						targets[panelID][entryID] = meta
						spellsByCategory[category] = spellsByCategory[category] or {}
						local spells = spellsByCategory[category]
						spells[spellID] = true
						if meta.baseSpellId then spells[meta.baseSpellId] = true end
						if meta.resolvedSpellId then spells[meta.resolvedSpellId] = true end
						if meta.effectiveSpellId then spells[meta.effectiveSpellId] = true end
						readySpellsByCategory[category] = readySpellsByCategory[category] or {}
						readySpellsByCategory[category][meta.resolvedSpellId or meta.baseSpellId or spellID] = true
					end
				end
			end
		end
	end
	runtime.categoryCooldownEntries = entriesByCategory
	runtime.categoryCooldownSpells = spellsByCategory
	runtime.categoryCooldownReadySpells = readySpellsByCategory
end

function Categories.GetEntries(runtime, category)
	if category == nil or (issecretvalue and issecretvalue(category)) then return nil end
	return runtime and runtime.categoryCooldownEntries and runtime.categoryCooldownEntries[category]
end

function Categories.Invalidate(runtime, category)
	if not Categories.GetEntries(runtime, category) then return end
	for spellID in pairs(runtime.categoryCooldownSpells[category]) do
		CP:InvalidateSpellQueryCaches("duration", spellID)
		CP:InvalidateSpellQueryCaches("info", spellID)
		CP:InvalidateSpellQueryCaches("charges", spellID)
		CP:InvalidateSpellQueryCaches("chargeDuration", spellID)
	end
end

function Categories.UpdateReadySounds(runtime, category)
	if not Categories.GetEntries(runtime, category) then return end
	for spellID in pairs(runtime.categoryCooldownReadySpells[category]) do
		CP:HandleReadySoundSpellEvent(spellID, nil, true)
	end
end
