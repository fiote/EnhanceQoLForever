local addon = _G.EnhanceQoL
local Reminder = addon and addon.ClassBuffReminder
if not Reminder then return end

local function getConsumableMacro(entry)
	local itemId = tonumber(entry.itemId)
	if not itemId or itemId <= 0 then return nil end
	local kind = entry.sourceKind
	local useItem = "/use [nocombat] item:" .. itemId
	if kind == "FOOD" or kind == "FLASK" or kind == "FOREVER_FOOD" then return useItem end
	if kind == "WEAPON_BUFF_MAINHAND" or kind == "WEAPON_BUFF_OFFHAND" then
		local slot = tonumber(entry.actionInventorySlot)
		if slot == (_G.INVSLOT_MAINHAND or 16) or slot == (_G.INVSLOT_OFFHAND or 17) then return useItem .. "\n/use [nocombat] " .. slot end
	end
end

function Reminder:UpdateSelfBuffBinding(provider, entries, primary)
	if InCombatLockdown and InCombatLockdown() then return end
	local button = _G.EQOLSelfBuffReminderButton
	if not button then
		button = CreateFrame("Button", "EQOLSelfBuffReminderButton", UIParent, "SecureActionButtonTemplate")
		button:RegisterForClicks("AnyDown")
		button:SetAttribute("pressAndHoldAction", true)
	end
	local spell, unit, groupSpell, groupUnit
	local consumableMacro
	local includeConsumables = addon.db and addon.db.classBuffReminderKeybindConsumables == true
	local function consider(entry)
		if type(entry) ~= "table" then return end
		if entry.itemId then
			if includeConsumables and not consumableMacro then consumableMacro = getConsumableMacro(entry) end
			return
		end
		if not entry.actionSpellId or entry.actionInventorySlot or entry.actionPetSlot then return end
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
	if spell then consumableMacro = nil end
	button:SetAttribute("spell1", spell)
	button:SetAttribute("unit1", unit)
	button:SetAttribute("macrotext1", consumableMacro)
	button:SetAttribute("type1", spell and "spell" or (consumableMacro and "macro") or nil)
end
