local addon = _G.EnhanceQoL
local Reminder = addon.ClassBuffReminder
local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL")

function Reminder:GetCustomBuffSpellIds(class)
	local stored = addon.db and addon.db.classBuffReminderCustomSpells
	local selection = type(stored) == "table" and stored[class or self:GetClassToken()]
	local ids = {}
	for id, enabled in pairs(type(selection) == "table" and selection or {}) do
		if type(id) == "number" and id > 0 and id == math.floor(id) and type(enabled) == "table" then ids[#ids + 1] = id end
	end
	table.sort(ids)
	return ids
end

function Reminder:GetCustomBuffDefinition(class, id)
	local stored = addon.db and addon.db.classBuffReminderCustomSpells
	local selection = type(stored) == "table" and stored[class or self:GetClassToken()]
	return type(selection) == "table" and selection[id] or nil
end

function Reminder:AddCustomBuffTooltipLines(tooltip, spellId, class)
	local definition = self:GetCustomBuffDefinition(class, spellId)
	if not definition then return end
	tooltip:AddLine(L["ClassBuffReminderCustomSpells"] .. ": " .. spellId, 1, 0.82, 0)
	tooltip:AddLine(L["ClassBuffReminderCustomAuras"] .. ":", 1, 0.82, 0)
	for _, id in ipairs(definition.auraIds) do
		local name = C_Spell.GetSpellName(id)
		tooltip:AddLine(name and name .. " (" .. id .. ")" or tostring(id), 1, 1, 1, true)
	end
end

function Reminder:SetCustomBuffDefinition(class, spellText, auraText)
	if not addon.db then return false end
	local id = type(spellText) == "string" and spellText:match("^%s*(%d+)%s*$")
	id = tonumber(id)
	local info = id and id > 0 and C_Spell.GetSpellInfo(id)
	local auraIds, seen = {}, {}
	local valid = info and info.name
	for token in (auraText or ""):gmatch("[^,%s;]+") do
		local auraId = token:match("^%d+$") and tonumber(token)
		local auraInfo = auraId and auraId > 0 and C_Spell.GetSpellInfo(auraId)
		if not (auraInfo and auraInfo.name) then valid = false; break end
		if not seen[auraId] then auraIds[#auraIds + 1] = auraId; seen[auraId] = true end
	end
	if not valid then
		if UIErrorsFrame then UIErrorsFrame:AddMessage(L["ClassBuffReminderCustomSpellsInvalid"], 1, 0.2, 0.2) end
		return false
	end
	if #auraIds == 0 then auraIds[1] = id end
	local stored = addon.db.classBuffReminderCustomSpells
	if type(stored) ~= "table" then stored = {}; addon.db.classBuffReminderCustomSpells = stored end
	if type(stored[class]) ~= "table" then stored[class] = {} end
	stored[class][id] = { auraIds = auraIds }
	self:OnSettingChanged()
	return true
end

function Reminder:RemoveCustomBuffDefinition(class, id)
	local stored = addon.db and addon.db.classBuffReminderCustomSpells
	if type(stored) ~= "table" or type(stored[class]) ~= "table" then return end
	stored[class][id] = nil
	if not next(stored[class]) then stored[class] = nil end
	self:OnSettingChanged()
end

function Reminder:IsClassBuffOutOfCombatOnly(spellId)
	if not self.supportsOutOfCombatBuffs then return false end
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
	if not (self.supportsOutOfCombatBuffs and addon.db) or row.trackerKey then return end
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

function Reminder:CanCheckCustomBuffReminders()
	if not self:CanReadAuraData() or self:IsReminderEvaluationBlockedByCombat() or not self:IsGroupModeAllowed() then return false end
	for _, id in ipairs(self:GetCustomBuffSpellIds()) do
		if not self:IsSpellReminderDisabled(id) then return true end
	end
	return false
end

function Reminder:GetCustomBuffMissingEntries()
	local entries = {}
	if not self:CanCheckCustomBuffReminders() then return entries end
	local snapshot = self:GetPlayerAuraPresenceSnapshot()
	if not snapshot or self:IsPlayerAuraSnapshotRestricted(snapshot) then return entries end
	for _, id in ipairs(self:GetCustomBuffSpellIds()) do
		local definition = self:GetCustomBuffDefinition(nil, id)
		local auraIds = definition.auraIds
		if not self:IsSpellReminderDisabled(id) and not self:AuraSnapshotHasAnySpellId(snapshot, auraIds, "CLASS_BUFFS") then
			local info = C_Spell.GetSpellInfo(id)
			if info then
				local entry = self:MakeSelfCastInteractionEntry(id, info.name, nil, nil, "CUSTOM_BUFF_" .. id, info.iconID)
				entry.customBuff = true
				entry.warningAuraQuery = { spellIds = auraIds, category = "CLASS_BUFFS" }
				entries[#entries + 1] = entry
			end
		end
	end
	return entries
end

function Reminder:GetCustomBuffOnlyProvider()
	self.customBuffOnlyProvider = self.customBuffOnlyProvider or { scope = "SELF", spellIds = {}, isSupplementalOnly = true }
	return self.customBuffOnlyProvider
end
