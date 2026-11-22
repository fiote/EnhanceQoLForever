local addon = _G.EnhanceQoL or select(2, ...)
local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL")
local C = addon.ForeverConsumables
local function createPriority(isGem)
local P = {}
local dbKey = isGem and "manaGemPriority" or "manaPotionPriority"

function P.IsItem(entry)
	if not entry then return false end
	if isGem then return entry.category == "mana_gem" end
	return entry.category == "mana_potion" or entry.category == "healing_and_mana_potion"
end

function P.GetSelection()
	local result, seen = {}, {}
	for _, id in ipairs(addon.db[dbKey] or {}) do
		if not seen[id] and P.IsItem(C.byID[id]) then
			result[#result + 1] = id
			seen[id] = true
		end
	end
	return result
end

function P.GetRanks()
	local ranks = {}
	for index, id in ipairs(P.GetSelection()) do ranks[id] = index end
	return ranks
end

function P.SetSelection(selection)
	addon.db[dbKey] = selection
	addon.functions.updateManaMacro()
end

function P.Remove(id)
	local list = P.GetSelection()
	for index, value in ipairs(list) do
		if value == id then
			table.remove(list, index)
			P.SetSelection(list)
			return
		end
	end
end

function P.Move(fromIndex, toIndex)
	local list = P.GetSelection()
	if not list[fromIndex] or toIndex < 1 or toIndex > #list then return end
	table.insert(list, toIndex, table.remove(list, fromIndex))
	P.SetSelection(list)
end

function P.Label(id)
	local name = C_Item.GetItemInfo(id)
	if not name and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
	return name and name:gsub("|A.-|a", ""):gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match("^%s*(.-)%s*$") or ("item:%d"):format(id)
end

function P.GetEntries()
	local entries = {}
	for _, id in ipairs(P.GetSelection()) do entries[#entries + 1] = { id = id, itemID = id, label = P.Label(id), icon = C_Item.GetItemIconByID(id), showID = false } end
	return entries
end

function P.GetOptions()
	local ranks, options = P.GetRanks(), {}
	for _, entry in ipairs(C.items) do
		if P.IsItem(entry) and not ranks[entry.id] then
			options[#options + 1] = { id = entry.id, label = P.Label(entry.id), icon = C_Item.GetItemIconByID(entry.id) or 134400, level = entry.requiredLevel or 0 }
		end
	end
	table.sort(options, function(a, b)
		if a.level ~= b.level then return a.level > b.level end
		if a.label ~= b.label then return a.label < b.label end
		return a.id < b.id
	end)
	return options
end

function P.Render(parent, app, control, state)
	parent._state = state
	addon.LibSettingsDesigner.UI.AddReorderListWidget(parent, app, control, { startY = 0 })
	local entries = P.GetEntries()
	for index, row in ipairs(parent.reorderRows or {}) do
		local entry = entries[index]
		if entry then
			row:SetScript("OnEnter", function(owner) GameTooltip:SetOwner(owner, "ANCHOR_RIGHT"); GameTooltip:SetItemByID(entry.id); GameTooltip:Show() end)
			row:SetScript("OnLeave", function(owner) if GameTooltip:IsOwned(owner) then GameTooltip:Hide() end end)
			row:SetScript("OnHide", function(owner) if GameTooltip:IsOwned(owner) then GameTooltip:Hide() end end)
		end
	end
	local picker = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
	picker:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -14, 0)
	picker:SetWidth(260)
	picker:SetDefaultText(L[isGem and "manaGemPriorityAdd" or "healthPotionPriorityAdd"])
	picker:SetEnabled(app:IsControlEnabled(control))
	picker:SetupMenu(function(_, root)
		root:SetScrollMode(360)
		for _, option in ipairs(P.GetOptions()) do
			local label = option.level > 0 and ("%s (%s %d)"):format(option.label, L["Level"], option.level) or option.label
			local button = root:CreateButton(("|T%d:18:18:0:0|t %s"):format(option.icon, label), function()
				if not app:IsControlEnabled(control) then return end
				local list = P.GetSelection()
				list[#list + 1] = option.id
				P.SetSelection(list)
				C_Timer.After(0, function() if parent:IsShown() and state.frame:IsShown() then state:RenderContent() end end)
			end)
			button:SetTooltip(function(tooltip) tooltip:SetItemByID(option.id) end)
		end
	end)
	return picker
end

function P.RegisterSettings(category, section, parentCheck)
	addon.functions.SettingsCreateCustom(category, {
		var = dbKey, text = L[dbKey], desc = L["manaItemPriorityDesc"], newTagID = dbKey,
		parentCheck = parentCheck, parentSection = section, default = {},
		get = function() return addon.db[dbKey] or {} end,
		set = P.SetSelection, getEntries = P.GetEntries, removeEntry = P.Remove, moveEntry = P.Move,
		emptyText = L[isGem and "manaGemPriorityEmpty" or "healthPotionPriorityEmpty"], refreshOnChange = true,
		getHeight = function() return 150 + #P.GetSelection() * 32 end, render = P.Render,
	})
end

return P
end

addon.ManaPotionPriority = createPriority(false)
addon.ManaGemPriority = createPriority(true)
