local addon = _G.EnhanceQoL
local CooldownPanels = addon.Aura.CooldownPanels
local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL")
local generation = 0

local function playerGUID()
	local guid = UnitGUID and UnitGUID("player")
	if issecretvalue and issecretvalue(guid) then return nil end
	return type(guid) == "string" and guid ~= "" and guid or nil
end

local function setName(setID)
	if not (C_EquipmentSet and C_EquipmentSet.GetEquipmentSetInfo) then return nil end
	local name = C_EquipmentSet.GetEquipmentSetInfo(setID)
	if issecretvalue and issecretvalue(name) then return nil end
	return type(name) == "string" and name ~= "" and name or nil
end

function CooldownPanels:NormalizeEntryEquipmentSetFilter(entry)
	local filter = entry.equipmentSetFilter
	if filter == nil then return end
	local id = type(filter) == "table" and tonumber(filter.id)
	if not id or id < 0 or id > 2147483647 or id ~= math.floor(id)
		or type(filter.characterGUID) ~= "string" or filter.characterGUID == "" then
		entry.equipmentSetFilter = nil
		return
	end
	filter.id = id
	if type(filter.name) ~= "string" then filter.name = nil end
end

function CooldownPanels:GetEntryEquipmentSetFilterSelection(entry)
	local filter = entry and entry.equipmentSetFilter
	if not filter then return "__all" end
	if filter.characterGUID == playerGUID() and setName(filter.id) then return filter.id end
	return "__unavailable"
end

function CooldownPanels:GetEntryEquipmentSetFilterOptions(entry)
	local options = { { value = "__all", text = L["CooldownPanelEquipmentSetFilterAny"] } }
	local sets = {}
	if C_EquipmentSet and C_EquipmentSet.GetEquipmentSetIDs and playerGUID() then
		for _, id in ipairs(C_EquipmentSet.GetEquipmentSetIDs() or {}) do
			local name = setName(id)
			if name then sets[#sets + 1] = { value = id, text = name } end
		end
	end
	table.sort(sets, function(a, b)
		if a.text == b.text then return a.value < b.value end
		return a.text:lower() < b.text:lower()
	end)
	for _, option in ipairs(sets) do options[#options + 1] = option end
	if self:GetEntryEquipmentSetFilterSelection(entry) == "__unavailable" then
		options[#options + 1] = {
			value = "__unavailable",
			text = string.format(L["CooldownPanelEquipmentSetFilterUnavailable"], entry.equipmentSetFilter.name or UNKNOWN),
			disabled = true,
		}
	end
	return options
end

function CooldownPanels:EntryAllowsEquipmentSet(entry)
	local filter = entry and entry.equipmentSetFilter
	if not filter then return true end
	if filter.characterGUID ~= playerGUID() or not setName(filter.id) then return false end
	local _, _, _, equipped = C_EquipmentSet.GetEquipmentSetInfo(filter.id)
	if issecretvalue and issecretvalue(equipped) then return false end
	return equipped == true
end

function CooldownPanels:GetEquipmentSetFilterGeneration() return generation end
function CooldownPanels:InvalidateEquipmentSetFilters() generation = generation + 1 end

function CooldownPanels:SetEntryEquipmentSetFilter(panelId, entryId, value)
	local panel = self:GetPanel(panelId)
	local entry = panel and panel.entries and panel.entries[entryId]
	if not entry then return end
	if value == "__all" then
		entry.equipmentSetFilter = nil
	else
		local id, guid = tonumber(value), playerGUID()
		local validName
		for _, option in ipairs(self:GetEntryEquipmentSetFilterOptions()) do
			if option.value == id then validName = option.text; break end
		end
		if not guid or not validName then return end
		-- Set IDs belong to a character and may collide in shared profiles.
		entry.equipmentSetFilter = { id = id, characterGUID = guid, name = validName }
	end
	self:RebuildSpellIndex()
	self:CommitEntrySpecFilter(panelId, panel)
end
