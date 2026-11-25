local addon = _G.EnhanceQoL
local Reminder = addon and addon.ClassBuffReminder
if not Reminder then return end

function Reminder:UpdateSelfBuffBinding(provider, entries, primary)
	if InCombatLockdown and InCombatLockdown() then return end
	local button = _G.EQOLSelfBuffReminderButton
	if not button then
		button = CreateFrame("Button", "EQOLSelfBuffReminderButton", UIParent, "SecureActionButtonTemplate")
		button:RegisterForClicks("AnyDown")
		button:SetAttribute("pressAndHoldAction", true)
	end
	local spell, unit, groupSpell, groupUnit
	local function consider(entry)
		if type(entry) ~= "table" or not entry.actionSpellId or entry.itemId or entry.actionInventorySlot or entry.actionPetSlot then return end
		local kind = entry.sourceKind
		if kind and not kind:match("^CUSTOM_BUFF_") and not kind:match("^PALADIN_BLESSING_") then return end
		local actionUnit = entry.actionUnit
		local selfMissing
		if entry.targetSelectionKey then
			if not actionUnit then return end
			selfMissing = actionUnit == "player" or (UnitIsUnit and UnitIsUnit(actionUnit, "player"))
		elseif entry.warningProvider then
			actionUnit = "player"
			selfMissing = self:CanReadAuraData() and not self:UnitHasProviderBuff("player", provider)
		elseif not actionUnit or actionUnit == "player" then
			actionUnit = "player"
			selfMissing = entry.selfBuffMissing == true or (entry.selfBuffMissing == nil and not entry.countMissing)
		end
		if selfMissing then
			spell, unit = entry.actionSpellId, actionUnit
		elseif actionUnit and not groupSpell and (entry.targetSelectionKey or ((entry.warningProvider or entry.groupCast) and entry.countMissing and entry.countMissing > 0)) then
			groupSpell, groupUnit = entry.actionSpellId, actionUnit
		end
	end
	if entries then
		for _, entry in ipairs(entries) do
			consider(entry)
			if spell then break end
		end
	elseif primary then
		consider(primary)
	end
	spell, unit = spell or groupSpell, unit or groupUnit
	button:SetAttribute("type1", spell and "spell" or nil)
	button:SetAttribute("spell1", spell)
	button:SetAttribute("unit1", unit)
end
