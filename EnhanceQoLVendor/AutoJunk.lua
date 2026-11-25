local addon = _G.EnhanceQoL
if not addon or not addon.variables.isForever or addon.variables.isTBC then return end

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL")
local M = { lootOpen = false }

function M.GetCandidate(bag, slot)
	local info = C_Container.GetContainerItemInfo(bag, slot)
	if not info or info.quality ~= 0 or info.isLocked or not info.itemID or not info.hyperlink then return end
	if addon.db.vendorExcludeSellList and addon.db.vendorExcludeSellList[info.itemID] then return end
	local protected, pending = addon.Vendor.functions.GetDestroyProtectionReason(info.itemID, info, info.quality)
	if protected or pending then return end
	local quest = C_Container.GetContainerItemQuestInfo(bag, slot)
	if not quest or quest.isQuestItem or quest.questID then return end
	local name, _, quality, _, _, _, _, _, _, _, price, _, _, bindType = C_Item.GetItemInfo(info.hyperlink)
	if not name or quality ~= 0 or bindType == nil or bindType == 4 or type(price) ~= "number" or price < 0 then return end
	if type(info.stackCount) ~= "number" or info.stackCount < 1 then return end
	return {
		bag = bag, slot = slot, itemID = info.itemID, link = info.hyperlink,
		count = info.stackCount, value = price * info.stackCount,
	}
end

function M.FindCheapest()
	local cheapest
	for bag = 0, NUM_BAG_SLOTS do
		local free, family = C_Container.GetContainerNumFreeSlots(bag)
		-- Only ordinary bags can provide a general-purpose loot slot.
		if family == 0 then
			if type(free) ~= "number" or free > 0 then return end
			for slot = 1, C_Container.GetContainerNumSlots(bag) do
				local candidate = M.GetCandidate(bag, slot)
				if candidate and (not cheapest or candidate.value < cheapest.value) then cheapest = candidate end
			end
		elseif family == nil and C_Container.GetContainerNumSlots(bag) > 0 then
			-- Unequipped bag slots have no family and cannot provide storage.
			return
		end
	end
	return cheapest
end

local function hideTooltip(button)
	if GameTooltip:IsOwned(button) then GameTooltip:Hide() end
end

local function createButton(parent, floating)
	local button
	if floating then
		button = CreateFrame("Button", nil, parent, "InsecureActionButtonTemplate")
		button:SetSize(22, 22)
		button:SetPoint("CENTER")
		local icon = button:CreateTexture(nil, "ARTWORK")
		icon:SetSize(13, 13)
		icon:SetPoint("CENTER")
		icon:SetAtlas("common-icon-redx")
		button:SetNormalTexture(icon)
		button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
		button:SetMotionScriptsWhileDisabled(true)
	else
		button = CreateFrame("Button", "EnhanceQoLLootJunkButton", parent, "UIPanelButtonTemplate,InsecureActionButtonTemplate")
		button:SetSize(190, 26)
		button:SetPoint("TOP", parent, "BOTTOM", 0, -4)
		button:SetText(L["vendorLootJunkButtonLabel"])
		parent:HookScript("OnShow", function() M.Refresh() end)
	end
	button:RegisterForClicks("LeftButtonUp")
	button:SetScript("OnClick", function(self) M.DeleteSelected(self) end)
	button:SetScript("OnEnter", function(self)
		if self ~= M.button or not M.entry then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(L["vendorLootJunkButtonLabel"])
		GameTooltip:AddLine(string.format(L["vendorLootJunkButtonTooltip"], M.entry.link, M.entry.count, C_CurrencyInfo.GetCoinTextureString(M.entry.value)), 1, 1, 1, true)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", hideTooltip)
	button:SetScript("OnHide", hideTooltip)
	return button
end

function M.Refresh()
	-- Cursor events fire inside pickup/delete. Keep the clicked button active until the action finishes.
	if M.deleting then return end
	local loot = addon.LootReplacer
	local footer = loot and loot.junkButtonParent
	local button
	if footer then
		M.floatingButton = M.floatingButton or createButton(footer, true)
		button = M.floatingButton
	elseif _G.LootFrame then
		M.blizzardButton = M.blizzardButton or createButton(_G.LootFrame, false)
		button = M.blizzardButton
	end
	if M.button and M.button ~= button then M.button:Hide() end
	M.button = button
	M.entry = nil
	if not button then return end
	if M.lootOpen and addon.db and addon.db.vendorLootJunkButton == true then M.entry = M.FindCheapest() end
	local enabled = not UnitAffectingCombat("player") and not InCombatLockdown() and GetCursorInfo() == nil
	button:SetShown(M.entry ~= nil)
	button:SetEnabled(enabled)
	if footer then button:SetAlpha(enabled and 1 or 0.4) end
	hideTooltip(button)
end

function M.DeleteSelected(button)
	if not M.lootOpen or not M.entry or not addon.db or addon.db.vendorLootJunkButton ~= true then return end
	if button ~= M.button or not button:IsVisible() or UnitAffectingCombat("player") or InCombatLockdown() or GetCursorInfo() ~= nil then return end
	local entry = M.entry
	local current = M.FindCheapest()
	-- Never replace the displayed stack with a different target during the click.
	if not current or current.bag ~= entry.bag or current.slot ~= entry.slot or current.itemID ~= entry.itemID or current.link ~= entry.link or current.count ~= entry.count or current.value ~= entry.value then
		M.Refresh()
		return
	end
	M.deleting = true
	C_Container.PickupContainerItem(entry.bag, entry.slot)
	local kind, itemID, link = GetCursorInfo()
	if kind ~= "item" or itemID ~= entry.itemID or link ~= entry.link then
		ClearCursor()
		M.deleting = false
		M.Refresh()
		return
	end
	-- Called synchronously from the button's hardware click, never from an event or timer.
	DeleteCursorItem()
	if CursorHasItem() then
		ClearCursor()
		print(L["vendorLootJunkButtonBlocked"])
	else
		print(string.format(L["vendorLootJunkButtonDeleted"], entry.link, entry.count, C_CurrencyInfo.GetCoinTextureString(entry.value)))
	end
	M.deleting = false
	M.entry = nil
	button:Hide()
end

addon.Vendor.functions.RefreshLootJunkButton = M.Refresh
M.frame = CreateFrame("Frame")
for _, event in ipairs({ "LOOT_OPENED", "LOOT_CLOSED", "BAG_UPDATE_DELAYED", "GET_ITEM_INFO_RECEIVED", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "CURSOR_CHANGED" }) do
	M.frame:RegisterEvent(event)
end
M.frame:SetScript("OnEvent", function(_, event)
	if event == "LOOT_OPENED" then M.lootOpen = true end
	if event == "LOOT_CLOSED" then M.lootOpen = false end
	if M.lootOpen or event == "LOOT_CLOSED" then M.Refresh() end
end)
