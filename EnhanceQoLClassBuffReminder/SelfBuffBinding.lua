local addon = _G.EnhanceQoL
local Reminder = addon and addon.ClassBuffReminder
if not Reminder then return end

local function isPlayerCandidate(entry)
	if entry.selfBuffMissing ~= nil then return entry.selfBuffMissing == true end
	if entry.targetSelectionKey then
		for _, candidate in ipairs(entry.targetCandidates or {}) do
			if candidate.unit == "player" or (UnitIsUnit and UnitIsUnit(candidate.unit, "player")) then return true end
		end
		return false
	end
	return not entry.countMissing
end

function Reminder:UpdateSelfBuffBinding(provider, entries, primary)
	if InCombatLockdown and InCombatLockdown() then return end
	local button = _G.EQOLSelfBuffReminderButton
	if not button then
		button = CreateFrame("Button", "EQOLSelfBuffReminderButton", UIParent, "SecureActionButtonTemplate")
		button:RegisterForClicks("AnyDown")
		button:SetAttribute("pressAndHoldAction", true)
		button:SetAttribute("unit1", "player")
	end
	local spell
	local function consider(entry)
		if type(entry) ~= "table" or not entry.actionSpellId or entry.itemId or entry.actionInventorySlot or entry.actionPetSlot then return end
		if entry.actionUnit and entry.actionUnit ~= "player" and not entry.targetSelectionKey then return end
		local kind = entry.sourceKind
		if kind and not kind:match("^CUSTOM_BUFF_") and not kind:match("^PALADIN_BLESSING_") then return end
		if entry.warningProvider then
			if not (self:CanReadAuraData() and not self:UnitHasProviderBuff("player", provider)) then return end
		elseif not isPlayerCandidate(entry) then return end
		spell = entry.actionSpellId
	end
	if entries then
		for _, entry in ipairs(entries) do
			consider(entry)
			if spell then break end
		end
	elseif primary then
		consider(primary)
	end
	button:SetAttribute("type1", spell and "spell" or nil)
	button:SetAttribute("spell1", spell)
end
