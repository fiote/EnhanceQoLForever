local addon = _G.EnhanceQoL
local Reminder = addon.ClassBuffReminder
local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL")

local function storageKey(isItem)
	return isItem and "classBuffReminderCustomItems" or "classBuffReminderCustomSpells"
end

local function definitions(self, class, isItem)
	local stored = addon.db and addon.db[storageKey(isItem)]
	local selection = type(stored) == "table" and stored[class or self:GetClassToken()]
	return type(selection) == "table" and selection or nil
end

function Reminder:GetCustomBuffIds(class, isItem)
	local ids = {}
	for id, definition in pairs(definitions(self, class, isItem) or {}) do
		if type(id) == "number" and id > 0 and id == math.floor(id) and type(definition) == "table" then ids[#ids + 1] = id end
	end
	table.sort(ids)
	return ids
end

function Reminder:GetCustomBuffSpellIds(class) return self:GetCustomBuffIds(class, false) end

function Reminder:GetCustomBuffDefinition(class, id, isItem)
	local selection = definitions(self, class, isItem)
	return selection and selection[id] or nil
end

function Reminder:GetCustomBuffActionInfo(id, isItem)
	if isItem then
		if not C_Item then return nil end
		local icon = self.GetItemIcon(id)
		if not icon then return nil end
		local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
		if issecretvalue and issecretvalue(name) then name = nil end
		if not name and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
		return name or (L["Item"] .. " " .. id), icon
	end
	local info = C_Spell.GetSpellInfo(id)
	if info then return info.name, info.iconID end
end

local slotLabels = { [16] = "INVTYPE_WEAPONMAINHAND", [17] = "INVTYPE_WEAPONOFFHAND", [18] = "INVTYPE_RANGED" }

function Reminder:GetCustomWeaponSlotLabel(slot)
	return _G[slotLabels[slot]]
end

function Reminder:SupportsCustomWeaponSlot(slot)
	return slot == 16 or slot == 17 or (slot == 18 and (addon.variables.isForever or addon.variables.isTBC))
end

function Reminder:CustomWeaponSlotSelected(definition, slot)
	return (definition.weaponSlots and definition.weaponSlots[slot] == true) or definition.weaponSlot == slot
end

local function restricted(value)
	return issecretvalue and issecretvalue(value)
end

local function needsWeaponBuff(self, slot, expected)
	if not self:SupportsCustomWeaponSlot(slot) then return false end
	local item = GetInventoryItemID("player", slot)
	if restricted(item) or not item then return false end
	local _, _, _, location = C_Item.GetItemInfoInstant(item)
	if restricted(location) or not location or location == "INVTYPE_HOLDABLE" or location == "INVTYPE_RELIC" then return false end
	local active, id, remaining
	if self.GetForeverWeaponEnchant then
		active, id, remaining = self:GetForeverWeaponEnchant(slot, nil, expected)
	elseif addon.variables.isTBC and GetWeaponEnchantInfo then
		local _
		active, remaining, _, id = select(1 + (slot - 16) * 4, GetWeaponEnchantInfo())
		if restricted(active) then return false end
		active = active or false
	elseif C_PaperDollInfo and C_PaperDollInfo.GetTemporaryEnchantmentInfo then
		local info = C_PaperDollInfo.GetTemporaryEnchantmentInfo(slot)
		if restricted(info) then return false end
		active = info ~= nil
		if info then id, remaining = info.enchantID, info.remainingTimeMs end
	else
		return false
	end
	if restricted(active) or active == nil or restricted(id) or restricted(remaining) then return false end
	if active and not id then return false end
	if not active or id ~= expected then return true end
	if self:IsWeaponEnchantUsable(remaining) then return false end
	return true, self:GetWeaponWarningExpiration(remaining)
end

function Reminder:AddCustomBuffTooltipLines(tooltip, id, class, isItem)
	local definition = self:GetCustomBuffDefinition(class, id, isItem)
	if not definition then return end
	tooltip:AddLine(L[isItem and "ClassBuffReminderCustomItems" or "ClassBuffReminderCustomSpells"] .. ": " .. id, 1, 0.82, 0)
	if definition.enchantId then
		local slots = {}
		for slot = 16, 18 do
			if self:CustomWeaponSlotSelected(definition, slot) then slots[#slots + 1] = self:GetCustomWeaponSlotLabel(slot) end
		end
		tooltip:AddLine(table.concat(slots, ", ") .. " - " .. L["Temp. EnchantID"] .. ": " .. definition.enchantId, 1, 1, 1)
		return
	end
	tooltip:AddLine(L["ClassBuffReminderCustomAuras"] .. ":", 1, 0.82, 0)
	for _, id in ipairs(definition.auraIds) do
		local name = C_Spell.GetSpellName(id)
		tooltip:AddLine(name and name .. " (" .. id .. ")" or tostring(id), 1, 1, 1, true)
	end
end

function Reminder:SetCustomBuffDefinition(class, actionText, auraText, isItem, weaponSlot)
	if not addon.db then return false end
	local id = type(actionText) == "string" and actionText:match("^%s*(%d+)%s*$")
	id = tonumber(id)
	local valid = id and id > 0 and self:GetCustomBuffActionInfo(id, isItem)
	local auraIds, seen = {}, {}
	local enchantId, slots
	if weaponSlot then
		slots = {}
		for slot = 16, 18 do
			if self:SupportsCustomWeaponSlot(slot) and (weaponSlot == slot or (type(weaponSlot) == "table" and weaponSlot[slot] == true)) then slots[slot] = true end
		end
		enchantId = tonumber((auraText or ""):match("^%s*(%d+)%s*$"))
		valid = valid and isItem and next(slots) and enchantId and enchantId > 0
	else
		for token in (auraText or ""):gmatch("[^,%s;]+") do
			local auraId = token:match("^%d+$") and tonumber(token)
			local auraInfo = auraId and auraId > 0 and C_Spell.GetSpellInfo(auraId)
			if not (auraInfo and auraInfo.name) then valid = false; break end
			if not seen[auraId] then auraIds[#auraIds + 1] = auraId; seen[auraId] = true end
		end
	end
	if not valid or (isItem and not weaponSlot and #auraIds == 0) then
		if UIErrorsFrame then UIErrorsFrame:AddMessage(L[weaponSlot and "ClassBuffReminderCustomWeaponGuide" or isItem and "ClassBuffReminderCustomItemsInvalid" or "ClassBuffReminderCustomSpellsInvalid"], 1, 0.2, 0.2) end
		return false
	end
	if not weaponSlot and #auraIds == 0 then auraIds[1] = id end
	local key = storageKey(isItem)
	local stored = addon.db[key]
	if type(stored) ~= "table" then stored = {}; addon.db[key] = stored end
	if type(stored[class]) ~= "table" then stored[class] = {} end
	local definition = stored[class][id]
	if type(definition) ~= "table" then definition = {} end
	definition.weaponSlot = nil
	definition.weaponSlots = slots
	definition.enchantId = enchantId
	definition.auraIds = not weaponSlot and auraIds or nil
	stored[class][id] = definition
	self:OnSettingChanged()
	return true
end

function Reminder:RemoveCustomBuffDefinition(class, id, isItem)
	local stored = addon.db and addon.db[storageKey(isItem)]
	if type(stored) ~= "table" or type(stored[class]) ~= "table" then return end
	stored[class][id] = nil
	if not next(stored[class]) then stored[class] = nil end
	self:OnSettingChanged()
end

function Reminder:IsClassBuffOutOfCombatOnly(spellId)
	if not spellId or not self.supportsOutOfCombatBuffs then return false end
	local stored = addon.db and addon.db.classBuffReminderOutOfCombatOnlySpells
	if type(stored) ~= "table" then return false end
	if stored[spellId] == true then return true end
	local name = C_Spell.GetSpellName(spellId)
	if not name then return false end
	for id, enabled in pairs(stored) do
		if enabled == true and C_Spell.GetSpellName(id) == name then return true end
	end
	return false
end

function Reminder:SetClassBuffOutOfCombatOnly(row, enabled)
	if not (self.supportsOutOfCombatBuffs and addon.db) or row.trackerKey or row.itemId then return end
	local stored = addon.db.classBuffReminderOutOfCombatOnlySpells
	if type(stored) ~= "table" then stored = {}; addon.db.classBuffReminderOutOfCombatOnlySpells = stored end
	local names = {}
	for _, id in ipairs(row.spellIds) do
		local name = C_Spell.GetSpellName(id)
		if name then names[name] = true end
	end
	for id in pairs(stored) do
		if names[C_Spell.GetSpellName(id)] then stored[id] = nil end
	end
	for _, id in ipairs(row.spellIds) do stored[id] = enabled == true or nil end
	if enabled and addon.db.classBuffReminderCombatOnlySpells then
		for id in pairs(addon.db.classBuffReminderCombatOnlySpells) do
			if names[C_Spell.GetSpellName(id)] then addon.db.classBuffReminderCombatOnlySpells[id] = nil end
		end
	end
	self:OnSettingChanged()
end

local function canCheckItem(self, definition)
	return type(definition) == "table" and not definition.disabled and (not definition.content or self:IsTrackingContentSelected(definition.content))
end

function Reminder:CanCheckCustomBuffReminders()
	if self:IsReminderEvaluationBlockedByCombat() or not self:IsGroupModeAllowed() then return false end
	local readable = self:CanReadAuraData()
	if readable then
		for _, id in ipairs(self:GetCustomBuffSpellIds()) do
			if not self:IsSpellReminderDisabled(id) then return true end
		end
	end
	for _, definition in pairs(definitions(self, nil, true) or {}) do
		if canCheckItem(self, definition) and (readable or definition.enchantId) then return true end
	end
	return false
end

function Reminder:GetCustomBuffMissingEntries()
	local entries = {}
	if not self:CanCheckCustomBuffReminders() then return entries end
	local snapshot = self:CanReadAuraData() and self:GetPlayerAuraPresenceSnapshot()
	local readable = snapshot and not self:IsPlayerAuraSnapshotRestricted(snapshot)
	for _, id in ipairs(self:GetCustomBuffSpellIds()) do
		local definition = self:GetCustomBuffDefinition(nil, id)
		local auraIds = definition.auraIds
		if readable and not self:IsSpellReminderDisabled(id) and not self:AuraSnapshotHasAnySpellId(snapshot, auraIds, "CLASS_BUFFS") then
			local info = C_Spell.GetSpellInfo(id)
			if info then
				local entry = self:MakeSelfCastInteractionEntry(id, info.name, nil, nil, "CUSTOM_BUFF_" .. id, info.iconID)
				entry.customBuff = true
				entry.warningAuraQuery = { spellIds = auraIds, category = "CLASS_BUFFS" }
				entries[#entries + 1] = entry
			end
		end
	end
	for _, id in ipairs(self:GetCustomBuffIds(nil, true)) do
		local definition = self:GetCustomBuffDefinition(nil, id, true)
		local auraIds = definition.auraIds
		if canCheckItem(self, definition) then
			local function append(slot, expiration)
				local name, icon = self:GetCustomBuffActionInfo(id, true)
				if not name then return end
				local source = "CUSTOM_ITEM_" .. id
				if slot then source = source .. "_" .. slot end
				entries[#entries + 1] = {
					label = name, icon = icon, itemId = id, sourceKind = source, customBuff = true,
					warningAuraQuery = auraIds and { spellIds = auraIds, category = "CLASS_BUFFS" },
					warningExpiration = expiration, actionInventorySlot = slot,
				}
			end
			if definition.enchantId then
				for slot = 16, 18 do
					if self:CustomWeaponSlotSelected(definition, slot) then
						local missing, expiration = needsWeaponBuff(self, slot, definition.enchantId)
						if missing then append(slot, expiration) end
					end
				end
			elseif readable and not self:AuraSnapshotHasAnySpellId(snapshot, auraIds, "CLASS_BUFFS") then
				append()
			end
		end
	end
	return entries
end

function Reminder:GetCustomBuffOnlyProvider()
	self.customBuffOnlyProvider = self.customBuffOnlyProvider or { scope = "SELF", spellIds = {}, isSupplementalOnly = true }
	return self.customBuffOnlyProvider
end
