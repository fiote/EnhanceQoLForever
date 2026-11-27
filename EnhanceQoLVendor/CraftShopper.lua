-- luacheck: globals AUCTION_HOUSE_HEADER_ITEM NEED

local parentAddonName = "EnhanceQoL"
local childAddonName, addon = ...

if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL")
local f = CreateFrame("Frame")
local ICON_PATH = "Interface\\AddOns\\" .. parentAddonName .. "\\Icons\\"

addon.Vendor = addon.Vendor or {}
addon.Vendor.CraftShopper = addon.Vendor.CraftShopper or {}
addon.Vendor.CraftShopper.items = addon.Vendor.CraftShopper.items or {}
addon.Vendor.CraftShopper.multipliers = addon.Vendor.CraftShopper.multipliers or {}

local isRecraftTbl = { false, true } -- erst normale, dann Recrafts

local SCAN_DELAY = 0.3
local pendingScan
local pendingAHShowScan
local scanRunning
local ahCache = {} -- [itemID] = true/false
-- Confirmed purchases cover missing reagents until their counts rise in inventory.
local purchasedReagents = {}

local ShowCraftShopperFrameIfNeeded -- forward declaration
local BuildShoppingList -- forward declaration for early users
local createCrafterMultiplyFrame -- forward declaration
local EnsureCraftShopperProfessionsUI -- forward declaration
local RefreshMultiplyUIState -- forward declaration
local craftShopperCheckboxHooksInstalled = false
local professionsFrameHooksInstalled = false
local schematicFormHooksInstalled = false
local schematicFormMixinHooksInstalled = false

local CRAFT_SHOPPER_QUALITY_LOWEST = "lowest"
local CRAFT_SHOPPER_QUALITY_HIGHEST = "highest"
local craftShopperQualityOrder = {
	CRAFT_SHOPPER_QUALITY_LOWEST,
	CRAFT_SHOPPER_QUALITY_HIGHEST,
}
local craftShopperQualityList = {
	[CRAFT_SHOPPER_QUALITY_LOWEST] = L["vendorCraftShopperReagentQualityLowest"],
	[CRAFT_SHOPPER_QUALITY_HIGHEST] = L["vendorCraftShopperReagentQualityHighest"],
}

local function IsCraftShopperEnabled() return addon.db and addon.db["vendorCraftShopperEnable"] end

local function ShouldIncludeWarbandBank()
	return addon.db and addon.db["vendorCraftShopperIncludeWarbandBank"] == true
end

local function GetCraftShopperReagentQualityMode()
	if addon.db and addon.db["vendorCraftShopperReagentQuality"] == CRAFT_SHOPPER_QUALITY_LOWEST then return CRAFT_SHOPPER_QUALITY_LOWEST end
	return CRAFT_SHOPPER_QUALITY_HIGHEST
end

local function GetTrackRecipeCheckbox()
	if ProfessionsFrame and ProfessionsFrame.CraftingPage and ProfessionsFrame.CraftingPage.SchematicForm and ProfessionsFrame.CraftingPage.SchematicForm.TrackRecipeCheckbox then
		return ProfessionsFrame.CraftingPage.SchematicForm.TrackRecipeCheckbox
	end
end

local function HasTrackedRecipes()
	for _, isRecraft in ipairs(isRecraftTbl) do
		local recipes = C_TradeSkillUI.GetRecipesTracked(isRecraft)
		if recipes and #recipes > 0 then return true end
	end
	return false
end

local heavyEvents = {
	"BAG_UPDATE_DELAYED",
	"CRAFTINGORDERS_ORDER_PLACEMENT_RESPONSE",
	"AUCTION_HOUSE_SHOW",
	"AUCTION_HOUSE_CLOSED",
	"COMMODITY_PRICE_UPDATED",
	"COMMODITY_PRICE_UNAVAILABLE",
	"COMMODITY_PURCHASE_FAILED",
	"COMMODITY_PURCHASE_SUCCEEDED",
	"ADDON_ACTION_BLOCKED",
	"ADDON_ACTION_FORBIDDEN",
	"ITEM_SEARCH_RESULTS_UPDATED",
	"AUCTION_HOUSE_BROWSE_RESULTS_UPDATED",
	"AUCTION_HOUSE_SHOW_ERROR",
	"AUCTION_HOUSE_PURCHASE_COMPLETED",
	"COMMODITY_PURCHASED",
	"PLAYER_MONEY",
	"ITEM_DATA_LOAD_RESULT",
	"ADDON_LOADED",
	"TRADE_SKILL_SHOW",
	"TRADE_SKILL_CLOSE",
}

local heavyEventsRegistered = false

local function RegisterHeavyEvents()
	if heavyEventsRegistered then return end
	heavyEventsRegistered = true
	for _, event in ipairs(heavyEvents) do
		f:RegisterEvent(event)
	end
end

-- Remove stored multipliers for recipes that are no longer tracked
local function CleanupUntrackedMultipliers()
	local tracked = {}
	for _, isRecraft in ipairs(isRecraftTbl) do
		local recipes = C_TradeSkillUI.GetRecipesTracked(isRecraft) or {}
		for _, recipeID in ipairs(recipes) do
			tracked[recipeID] = true
		end
	end
	local removed = false
	for recipeID, _ in pairs(addon.Vendor.CraftShopper.multipliers or {}) do
		if not tracked[recipeID] then
			addon.Vendor.CraftShopper.multipliers[recipeID] = nil
			removed = true
		end
	end
	if removed then
		-- Rebuild immediately (not gated by resting) to reflect changes
		addon.Vendor.CraftShopper.items = BuildShoppingList()
		if addon.Vendor.CraftShopper.frame then addon.Vendor.CraftShopper.frame:Refresh() end
		ShowCraftShopperFrameIfNeeded()
	end
end

local function UnregisterHeavyEvents()
	if not heavyEventsRegistered then return end
	heavyEventsRegistered = false
	for _, event in ipairs(heavyEvents) do
		f:UnregisterEvent(event)
	end
end

-- Helpers to manage mini-frame state
local function GetCurrentRecipeID()
	local recipeID
	if
		ProfessionsFrame
		and ProfessionsFrame.CraftingPage
		and ProfessionsFrame.CraftingPage.SchematicForm
		and ProfessionsFrame.CraftingPage.SchematicForm.currentRecipeInfo
		and ProfessionsFrame.CraftingPage.SchematicForm.currentRecipeInfo.recipeID
	then
		recipeID = ProfessionsFrame.CraftingPage.SchematicForm.currentRecipeInfo.recipeID
	elseif C_TradeSkillUI and C_TradeSkillUI.GetSelectedRecipeID then
		recipeID = C_TradeSkillUI.GetSelectedRecipeID()
	end
	return recipeID
end

local function ShouldShowMultiplyFrame()
	if not IsCraftShopperEnabled() then return false end
	local checkbox = GetTrackRecipeCheckbox()
	if checkbox and checkbox:IsShown() then return true end
	if not ProfessionsFrame or not ProfessionsFrame:IsShown() then return false end
	if not ProfessionsFrame.CraftingPage or not ProfessionsFrame.CraftingPage:IsShown() then return false end

	local form = ProfessionsFrame.CraftingPage.SchematicForm
	if not form or not form:IsShown() then return false end
	if not (form.currentRecipeInfo and form.currentRecipeInfo.recipeID ~= nil) then return false end

	local transaction = form.GetTransaction and form:GetTransaction()
	if transaction and transaction.HasReagentSlots and not transaction:HasReagentSlots() then return false end

	return true
end

local function IsRecipeTrackedAny(recipeID)
	if not recipeID or not C_TradeSkillUI or not C_TradeSkillUI.IsRecipeTracked then return false end
	local ok, tracked = pcall(C_TradeSkillUI.IsRecipeTracked, recipeID, false)
	if ok and tracked then return true end
	local ok2, tracked2 = pcall(C_TradeSkillUI.IsRecipeTracked, recipeID, true)
	return ok2 and tracked2 or false
end

local function UpdateMultiplyFrameState()
	local frame = _G.EQOLCrafterMultiply
	if not frame or not frame.ok or not frame.editBox then return end
	local txt = frame.editBox:GetText() or ""
	local rid = GetCurrentRecipeID()
	local isTracked = IsRecipeTrackedAny(rid)
	if txt == "" then
		frame.ok:SetText(isTracked and PROFESSIONS_UNTRACK_RECIPE or TRACK_ACHIEVEMENT)
	else
		if frame.autoFilled then
			frame.ok:SetText(PROFESSIONS_UNTRACK_RECIPE)
		else
			frame.ok:SetText(TRACK_ACHIEVEMENT)
		end
	end
end

local function EnsureMultiplyFrameExists()
	if _G.EQOLCrafterMultiply then return _G.EQOLCrafterMultiply end
	if not IsCraftShopperEnabled() then return nil end
	local form = ProfessionsFrame and ProfessionsFrame.CraftingPage and ProfessionsFrame.CraftingPage.SchematicForm
	if not form then return nil end
	if createCrafterMultiplyFrame then return createCrafterMultiplyFrame() end
end

RefreshMultiplyUIState = function()
	local checkbox = GetTrackRecipeCheckbox()
	if checkbox and checkbox.SetAlpha then checkbox:SetAlpha(IsCraftShopperEnabled() and 0 or 1) end

	local frame = _G.EQOLCrafterMultiply or EnsureMultiplyFrameExists()
	if frame then
		if ShouldShowMultiplyFrame() then
			frame:Show()
		else
			frame:Hide()
		end
	end

	if UpdateMultiplyFrameState then UpdateMultiplyFrameState() end
end

local function HookCraftShopperCheckboxIfNeeded()
	if craftShopperCheckboxHooksInstalled or not IsCraftShopperEnabled() then return end
	local checkbox = GetTrackRecipeCheckbox()
	if not checkbox or not checkbox.HookScript then return end

	checkbox:HookScript("OnShow", function()
		if RefreshMultiplyUIState then RefreshMultiplyUIState() end
	end)

	checkbox:HookScript("OnHide", function()
		if RefreshMultiplyUIState then RefreshMultiplyUIState() end
	end)

	craftShopperCheckboxHooksInstalled = true
end

local function HookSchematicFormStateIfNeeded()
	if schematicFormHooksInstalled then return end
	local form = ProfessionsFrame and ProfessionsFrame.CraftingPage and ProfessionsFrame.CraftingPage.SchematicForm
	if not form then return end

	if form.HookScript then
		form:HookScript("OnShow", function()
			if RefreshMultiplyUIState then RefreshMultiplyUIState() end
		end)
		form:HookScript("OnHide", function()
			if RefreshMultiplyUIState then RefreshMultiplyUIState() end
		end)
	end

	if hooksecurefunc then
		hooksecurefunc(form, "Init", function()
			if RefreshMultiplyUIState then RefreshMultiplyUIState() end
		end)
		hooksecurefunc(form, "Refresh", function()
			if RefreshMultiplyUIState then RefreshMultiplyUIState() end
		end)
	end

	schematicFormHooksInstalled = true
end

local function HookSchematicFormMixinIfNeeded()
	if schematicFormMixinHooksInstalled then return end
	if not hooksecurefunc or not ProfessionsRecipeSchematicFormMixin then return end

	local function onSchematicUpdate(form)
		if not IsCraftShopperEnabled() then return end
		if not ProfessionsFrame or not ProfessionsFrame.CraftingPage or form ~= ProfessionsFrame.CraftingPage.SchematicForm then return end
		if not _G.EQOLCrafterMultiply and createCrafterMultiplyFrame then createCrafterMultiplyFrame() end
		if RefreshMultiplyUIState then RefreshMultiplyUIState() end
	end

	hooksecurefunc(ProfessionsRecipeSchematicFormMixin, "Init", onSchematicUpdate)
	hooksecurefunc(ProfessionsRecipeSchematicFormMixin, "Refresh", onSchematicUpdate)
	hooksecurefunc(ProfessionsRecipeSchematicFormMixin, "OnShow", onSchematicUpdate)
	hooksecurefunc(ProfessionsRecipeSchematicFormMixin, "OnHide", onSchematicUpdate)

	schematicFormMixinHooksInstalled = true
end

local function HookProfessionsFrameVisibilityIfNeeded()
	if professionsFrameHooksInstalled then return end
	if not ProfessionsFrame or not ProfessionsFrame.HookScript then return end

	ProfessionsFrame:HookScript("OnShow", function()
		if not IsCraftShopperEnabled() then return end
		EnsureCraftShopperProfessionsUI()
		if RefreshMultiplyUIState then RefreshMultiplyUIState() end
	end)

	ProfessionsFrame:HookScript("OnHide", function()
		if RefreshMultiplyUIState then RefreshMultiplyUIState() end
	end)

	professionsFrameHooksInstalled = true
end

EnsureCraftShopperProfessionsUI = function()
	if not IsCraftShopperEnabled() then return end
	if IsAddOnLoaded and IsAddOnLoaded("Blizzard_Professions") then
		HookSchematicFormMixinIfNeeded()
		HookProfessionsFrameVisibilityIfNeeded()
		HookSchematicFormStateIfNeeded()
		if not EQOLCrafterMultiply and createCrafterMultiplyFrame then createCrafterMultiplyFrame() end
		HookCraftShopperCheckboxIfNeeded()
		if RefreshMultiplyUIState then RefreshMultiplyUIState() end
	else
		f:RegisterEvent("ADDON_LOADED")
	end
end

local function isAHBuyable(itemID)
	if ahCache[itemID] ~= nil then return ahCache[itemID] end
	local buyable = true
	local data = C_TooltipInfo.GetItemByID(itemID)
	if data and data.lines then
		for _, line in ipairs(data.lines) do
			if (line.type == 20 and line.leftText == ITEM_BIND_ON_EQUIP) or (line.type == 0 and line.leftText == ITEM_CONJURED) then
				buyable = false
				break
			end
		end
	end
	ahCache[itemID] = buyable
	return buyable
end
local schemCache = {} -- [recipeID] = schematic
local schemCacheRecraft = {} -- [recipeID] = schematic

local function getSchematic(recipeID, isRecraft)
	if isRecraft and schemCacheRecraft[recipeID] then return schemCacheRecraft[recipeID] end
	if not isRecraft and schemCache[recipeID] then return schemCache[recipeID] end
	local s = C_TradeSkillUI.GetRecipeSchematic(recipeID, isRecraft)
	if isRecraft then
		schemCacheRecraft[recipeID] = s
	else
		schemCache[recipeID] = s
	end
	return s
end

local function GetTrackedReagentItemID(slot)
	if not slot or not slot.reagents then return nil end
	local preferHighest = GetCraftShopperReagentQualityMode() == CRAFT_SHOPPER_QUALITY_HIGHEST

	-- Profession quality variants are ordered ascending. Pick the configured end
	-- first, then fall back to the opposite direction if a slot is sparse.
	if preferHighest then
		for index = #slot.reagents, 1, -1 do
			local reagent = slot.reagents[index]
			if reagent and reagent.itemID and reagent.itemID ~= 0 then return reagent.itemID end
		end
	else
		for _, reagent in ipairs(slot.reagents) do
			if reagent and reagent.itemID and reagent.itemID ~= 0 then return reagent.itemID end
		end
	end

	if preferHighest then
		for _, reagent in ipairs(slot.reagents) do
			if reagent and reagent.itemID and reagent.itemID ~= 0 then return reagent.itemID end
		end
	else
		for index = #slot.reagents, 1, -1 do
			local reagent = slot.reagents[index]
			if reagent and reagent.itemID and reagent.itemID ~= 0 then return reagent.itemID end
		end
	end

	return nil
end

function BuildShoppingList()
	local need = {} -- [itemID] = fehlende Menge
	local multipliers = addon.Vendor.CraftShopper.multipliers or {}
	local hasQualityChoices = false

	for _, isRecraft in ipairs(isRecraftTbl) do
		local recipes = C_TradeSkillUI.GetRecipesTracked(isRecraft) or {}
		for _, recipeID in ipairs(recipes) do
			local schem = getSchematic(recipeID, isRecraft)
			local mult = multipliers[recipeID] or 1
			if schem and schem.reagentSlotSchematics then
				for _, slot in ipairs(schem.reagentSlotSchematics) do
					-- Nur Pflicht-Reagenzien mit echter ItemID erfassen.
					if slot.reagentType == Enum.CraftingReagentType.Basic and slot.required then
						local reqQty = slot.quantityRequired * mult
						local id = GetTrackedReagentItemID(slot)
						if id then
							if not hasQualityChoices then
								for _, reagent in ipairs(slot.reagents) do
									if reagent.itemID and reagent.itemID ~= 0 and reagent.itemID ~= id then
										hasQualityChoices = true
										break
									end
								end
							end
							need[id] = need[id] or {}
							need[id].qty = (need[id].qty or 0) + reqQty
							need[id].canAHBuy = isAHBuyable(id)
						end
					end
				end
			end
		end
	end

	local items = {}
	for itemID, want in pairs(need) do
		local owned = C_Item.GetItemCount(itemID, true, false, false, ShouldIncludeWarbandBank()) -- inkl. Bank, optional Warband Bank
		local purchase = purchasedReagents[itemID]
		if purchase then
			local inBags = C_Item.GetItemCount(itemID)
			purchase.quantity = math.max(0, purchase.quantity - math.max(0, inBags - purchase.inBags))
			purchase.inBags = inBags
			if purchase.quantity == 0 then purchasedReagents[itemID] = nil end
		end
		local missing = math.max(want.qty - owned - (purchase and purchase.quantity or 0), 0)
		if missing > 0 then
			table.insert(items, {
				itemID = itemID,
				qtyNeeded = want.qty,
				owned = owned,
				missing = missing,
				ahBuyable = want.canAHBuy,
				hidden = false,
			})
		end
	end
	addon.Vendor.CraftShopper.hasQualityChoices = hasQualityChoices
	return items
end

local function CancelPendingAHShowScan()
	if pendingAHShowScan then
		pendingAHShowScan:Cancel()
		pendingAHShowScan = nil
	end
end

local function HideCraftShopperFrame()
	if addon.Vendor.CraftShopper.frame then addon.Vendor.CraftShopper.frame.frame:Hide() end
end

local function CanRescanShoppingList()
	if AuctionHouseFrame and AuctionHouseFrame:IsShown() then return true end
	return IsResting and IsResting() or false
end

local function Rescan()
	if scanRunning then return end
	scanRunning = true
	pendingScan = nil
	if not CanRescanShoppingList() then
		scanRunning = false
		return
	end
	addon.Vendor.CraftShopper.items = BuildShoppingList()
	if addon.Vendor.CraftShopper.frame then addon.Vendor.CraftShopper.frame:Refresh() end
	scanRunning = false
	ShowCraftShopperFrameIfNeeded()
end

local function SyncCraftShopperQualityControls()
	local mode = GetCraftShopperReagentQualityMode()
	local frameDropdown = addon.Vendor.CraftShopper.frame and addon.Vendor.CraftShopper.frame.qualityPreference
	if frameDropdown and frameDropdown.GetValue and frameDropdown:GetValue() ~= mode then frameDropdown:SetValue(mode) end
end

function addon.Vendor.CraftShopper.GetReagentQualityMode()
	return GetCraftShopperReagentQualityMode()
end

function addon.Vendor.CraftShopper.RefreshShoppingList()
	SyncCraftShopperQualityControls()
	if not IsCraftShopperEnabled() then return end

	if HasTrackedRecipes() then
		RegisterHeavyEvents()
		Rescan()
	else
		UnregisterHeavyEvents()
		addon.Vendor.CraftShopper.items = {}
		if addon.Vendor.CraftShopper.frame then
			addon.Vendor.CraftShopper.frame:Refresh()
			addon.Vendor.CraftShopper.frame.frame:Hide()
		end
	end

	if RefreshMultiplyUIState then RefreshMultiplyUIState() end
end

function addon.Vendor.CraftShopper.SetReagentQualityMode(mode)
	if not addon.db then return end
	addon.db["vendorCraftShopperReagentQuality"] = mode == CRAFT_SHOPPER_QUALITY_LOWEST and CRAFT_SHOPPER_QUALITY_LOWEST or CRAFT_SHOPPER_QUALITY_HIGHEST
	addon.Vendor.CraftShopper.RefreshShoppingList()
end

function addon.Vendor.CraftShopper.SetIncludeWarbandBank(enabled)
	if not addon.db then return end
	addon.db["vendorCraftShopperIncludeWarbandBank"] = enabled == true
	addon.Vendor.CraftShopper.RefreshShoppingList()
end

local function ScheduleRescan()
	if not CanRescanShoppingList() then return end
	if pendingScan or scanRunning then return end
	pendingScan = C_Timer.NewTimer(SCAN_DELAY, Rescan)
end

local mapQuality = {
	[0] = Enum.AuctionHouseFilter.PoorQuality,
	[1] = Enum.AuctionHouseFilter.CommonQuality,
	[2] = Enum.AuctionHouseFilter.UncommonQuality,
	[3] = Enum.AuctionHouseFilter.RareQuality,
	[4] = Enum.AuctionHouseFilter.EpicQuality,
	[5] = Enum.AuctionHouseFilter.LegendaryQuality,
	[6] = Enum.AuctionHouseFilter.ArtifactQuality,
	[7] = Enum.AuctionHouseFilter.LegendaryCraftedItemOnly,
}

local function SetCheckButtonValue(button, value)
	if button and button.SetChecked then button:SetChecked(value == true) end
end

local function GetCheckButtonValue(button)
	return button and button.GetChecked and button:GetChecked() == true or false
end

local function CreateCraftShopperCheckButton(parent, label)
	local button = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	button.Text:SetText(label or "")
	button.SetValue = SetCheckButtonValue
	button.GetValue = GetCheckButtonValue
	return button
end

local function CreateCraftShopperIconButton(parent, texture, tooltipText, onClick)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(27, 27)
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetAllPoints()
	button.icon:SetTexture(texture)
	button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(tooltipText)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	button:SetScript("OnClick", onClick)
	return button
end

local function SetQualityButtonValue(button, mode)
	local value = mode == CRAFT_SHOPPER_QUALITY_LOWEST and CRAFT_SHOPPER_QUALITY_LOWEST or CRAFT_SHOPPER_QUALITY_HIGHEST
	button.value = value
	button:SetText(craftShopperQualityList[value] or value)
end

local function GetQualityButtonValue(button)
	return button.value or GetCraftShopperReagentQualityMode()
end

local function OpenQualityMenu(button)
	if MenuUtil and MenuUtil.CreateContextMenu then
		MenuUtil.CreateContextMenu(button, function(_, rootDescription)
			for _, mode in ipairs(craftShopperQualityOrder) do
				rootDescription:CreateRadio(craftShopperQualityList[mode] or mode, function() return GetCraftShopperReagentQualityMode() == mode end, function()
					if addon.Vendor and addon.Vendor.CraftShopper and addon.Vendor.CraftShopper.SetReagentQualityMode then
						addon.Vendor.CraftShopper.SetReagentQualityMode(mode)
					end
				end)
			end
		end)
	else
		local nextMode = GetCraftShopperReagentQualityMode() == CRAFT_SHOPPER_QUALITY_LOWEST and CRAFT_SHOPPER_QUALITY_HIGHEST or CRAFT_SHOPPER_QUALITY_LOWEST
		if addon.Vendor and addon.Vendor.CraftShopper and addon.Vendor.CraftShopper.SetReagentQualityMode then
			addon.Vendor.CraftShopper.SetReagentQualityMode(nextMode)
		end
	end
end

local function AnchorFrameToCurrentScreenPosition(frame)
	if not frame or not UIParent or not frame.GetLeft or not frame.GetTop then return end
	local left = frame:GetLeft()
	local top = frame:GetTop()
	if not left or not top then return end

	local frameScale = frame.GetEffectiveScale and frame:GetEffectiveScale() or 1
	local parentScale = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
	if frameScale <= 0 then frameScale = 1 end
	if parentScale <= 0 then parentScale = 1 end

	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * frameScale / parentScale, top * frameScale / parentScale)
end

local function IsReadable(value, kind)
	return (not _G.issecretvalue or not _G.issecretvalue(value)) and type(value) == kind
end

local function IsPositiveNumber(value)
	return IsReadable(value, "number") and value > 0
end

local function MatchesItemKey(left, right)
	if not IsReadable(left, "table") or not IsReadable(right, "table") then return false end
	for name, value in pairs(right) do
		if not IsReadable(value, "number") or not IsReadable(left[name], "number") or left[name] ~= value then return false end
	end
	return true
end

local function CanUseAuctionHouse()
	local ahFrame = AuctionHouseFrame
	if not ahFrame or not ahFrame:IsShown() or InCombatLockdown() or not C_AuctionHouse.IsThrottledMessageSystemReady() then return false end
	if ahFrame.BuyDialog and ahFrame.BuyDialog:IsShown() then return false end
	if _G.StaticPopup_Visible and (_G.StaticPopup_Visible("BUYOUT_AUCTION") or _G.StaticPopup_Visible("PURCHASE_AUCTION_UNIQUE")) then return false end
	local sales = addon.Vendor.AuctionSales
	return not sales or not (sales.fullScan or sales.watchSearch or (sales.search and not sales.search.received)
		or (sales.foreignScanPendingUntil and GetTime() < sales.foreignScanPendingUntil))
end

local function GetPurchaseOffer(search, missing)
	local ah = C_AuctionHouse
	local ahFrame = AuctionHouseFrame
	local itemID = search.key.itemID
	if search.commodity then
		local quantity, cost = 0, 0
		for index = 1, ah.GetNumCommoditySearchResults(itemID) do
			local row = ah.GetCommoditySearchResultInfo(itemID, index)
			if not IsReadable(row, "table") or not IsPositiveNumber(row.unitPrice) or not IsPositiveNumber(row.quantity)
				or not IsReadable(row.numOwnerItems, "number") or row.numOwnerItems < 0 or row.numOwnerItems > row.quantity then return end
			local units = math.min(missing - quantity, row.quantity - row.numOwnerItems)
			quantity = quantity + units
			cost = cost + units * row.unitPrice
			if quantity == missing then break end
		end
		if quantity > 0 then return { quantity = quantity, cost = cost } end
		return
	end

	local view = ahFrame.ItemBuyFrame
	if not view or not view:IsShown() or not MatchesItemKey(view.itemKey, search.key) then return end
	local best
	for index = 1, ah.GetNumItemSearchResults(search.key) do
		local row = ah.GetItemSearchResultInfo(search.key, index)
		if IsReadable(row, "table") and MatchesItemKey(row.itemKey, search.key) and IsPositiveNumber(row.auctionID)
			and IsReadable(row.containsOwnerItem, "boolean") and not row.containsOwnerItem
			and IsReadable(row.containsAccountItem, "boolean") and not row.containsAccountItem
			and IsPositiveNumber(row.quantity) and row.quantity <= missing and IsPositiveNumber(row.buyoutAmount) then
			local unitPrice = row.buyoutAmount / row.quantity
			if not best or unitPrice < best.unitPrice or (unitPrice == best.unitPrice and row.auctionID < best.auctionID) then
				best = { auctionID = row.auctionID, quantity = row.quantity, cost = row.buyoutAmount, unitPrice = unitPrice }
			end
		end
	end
	return best
end

local function BrowseReagent(item)
	local itemName, _, quality, _, _, _, _, _, equipLoc, _, _, classID, subclassID = C_Item.GetItemInfo(item.itemID)
	if not itemName then return end
	local filters = { Enum.AuctionHouseFilter.ExactMatch }
	if mapQuality[quality] then table.insert(filters, 1, mapQuality[quality]) end
	AuctionHouseFrame:GetCategoriesList():SetSelectedCategory(nil)
	AuctionHouseFrame:SetDisplayMode(_G.AuctionHouseFrameDisplayMode.Buy)
	AuctionHouseFrame:SetSearchText(itemName)
	C_AuctionHouse.SendBrowseQuery({
		searchString = itemName,
		sorts = {
			{ sortOrder = Enum.AuctionHouseSortOrder.Name, reverseSort = false },
			{ sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false },
		},
		filters = filters,
		itemClassFilters = { classID = classID, subClassID = subclassID, inventoryType = equipLoc },
	})
end

local function CreateShopperWindow(name, parent, title)
	local forever = addon.variables.isForever
	local frame = CreateFrame("Frame", name, parent, forever and "PortraitFrameTemplate" or "BasicFrameTemplate")
	if forever then
		frame:SetBorder("ButtonFrameTemplateNoPortrait")
		frame:SetPortraitShown(false)
		frame:SetTitleOffsets(26, -26)
		frame:SetTitle(title)
	else
		frame.TitleText:SetText(title)
	end
	frame.CloseButton:ClearAllPoints()
	frame.CloseButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, forever and 1 or 0)
	frame.CloseButton:SetSize(20, 20)
	return frame
end

local function CreateCraftShopperFrame()
	if addon.Vendor.CraftShopper.frame then return addon.Vendor.CraftShopper.frame end
	local frame = CreateShopperWindow("EnhanceQoLCraftShopperFrame", UIParent, L["vendorCraftShopperTitle"])
	frame:SetSize(380, 400)
	frame:Hide()
	frame.frame = frame
	frame.rows = {}
	frame:SetFrameStrata(AuctionHouseFrame:GetFrameStrata())
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:SetResizable(true)
	if frame.SetResizeBounds then
		frame:SetResizeBounds(360, 280, nil, nil)
	elseif frame.SetMinResize then
		frame:SetMinResize(360, 280)
	end
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
		AnchorFrameToCurrentScreenPosition(self)
		self.userMoved = true
		self:StartMoving()
	end)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

	local resizeButton = CreateFrame("Button", nil, frame)
	resizeButton:SetSize(13, 13)
	resizeButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -9, 9)
	resizeButton:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	resizeButton:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	resizeButton:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	resizeButton:SetScript("OnMouseDown", function(self, button)
		if button ~= "LeftButton" then return end
		self:SetButtonState("PUSHED", true)
		if self:GetHighlightTexture() then self:GetHighlightTexture():Hide() end
		AnchorFrameToCurrentScreenPosition(frame)
		frame:StartSizing("BOTTOMRIGHT")
	end)
	resizeButton:SetScript("OnMouseUp", function(self, button)
		if button ~= "LeftButton" then return end
		self:SetButtonState("NORMAL")
		if self:GetHighlightTexture() then self:GetHighlightTexture():Show() end
		frame:StopMovingOrSizing()
		frame.userSized = true
		frame:Refresh()
	end)
	frame.ResizeButton = resizeButton

	local search = CreateFrame("EditBox", nil, frame, "SearchBoxTemplate")
	search:SetHeight(25)
	-- The native search box's left border extends five points beyond the edit box.
	search:SetPoint("TOPLEFT", frame, "TOPLEFT", 22, -33)
	search:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -17, -33)
	search:HookScript("OnTextChanged", function() frame:Refresh() end)
	frame.search = search

	local ahCheck = CreateCraftShopperCheckButton(frame, L["vendorCraftShopperAHBuyable"])
	ahCheck:SetPoint("TOPLEFT", search, "BOTTOMLEFT", -10, -4)
	ahCheck:SetScript("OnClick", function() frame:Refresh() end)
	ahCheck:SetValue(true)
	frame.ahBuyable = ahCheck

	local qualityLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	qualityLabel:SetPoint("TOPLEFT", ahCheck, "BOTTOMLEFT", 6, -4)
	qualityLabel:SetText(L["vendorCraftShopperReagentQuality"])

	local qualityPreference = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	qualityPreference:SetHeight(22)
	qualityPreference:SetPoint("TOPLEFT", qualityLabel, "BOTTOMLEFT", 0, -4)
	qualityPreference:SetScript("OnClick", OpenQualityMenu)
	qualityPreference.SetValue = SetQualityButtonValue
	qualityPreference.GetValue = GetQualityButtonValue
	qualityPreference:SetValue(GetCraftShopperReagentQualityMode())
	frame.qualityPreference = qualityPreference

	local header = CreateFrame("Frame", nil, frame)
	header:SetHeight(25)
	frame.header = header

	local headerBackground = header:CreateTexture(nil, "BACKGROUND")
	headerBackground:SetAllPoints()
	if addon.variables.isForever then
		headerBackground:SetColorTexture(0.32, 0.24, 0.16, 0.65)
	else
		headerBackground:SetColorTexture(0.27, 0.30, 0.34, 0.55)
	end
	header.item = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	header.item:SetPoint("LEFT", 7, 0)
	header.item:SetText(AUCTION_HOUSE_HEADER_ITEM)
	header.item:SetJustifyH("LEFT")

	header.need = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	header.need:SetText(NEED)
	header.need:SetJustifyH("RIGHT")

	local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
	scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -31, 20)
	scroll.scrollBarHideable = true
	frame.scroll = scroll

	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(1, 1)
	scroll:SetScrollChild(content)
	frame.content = content

	local popup = CreateShopperWindow("EnhanceQoLCraftShopperPurchaseFrame", frame, L["vendorCraftShopperConfirmPurchase"])
	popup:SetSize(300, 132)
	popup:SetPoint("CENTER", frame, "CENTER")
	popup:SetFrameStrata("DIALOG")
	popup:EnableMouse(true)
	popup:Hide()

	local purchaseIcon = popup:CreateTexture(nil, "ARTWORK")
	purchaseIcon:SetSize(30, 30)
	purchaseIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	local purchaseName = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	purchaseName:SetPoint("LEFT", purchaseIcon, "RIGHT", 8, 0)
	purchaseName:SetJustifyH("LEFT")
	purchaseName:SetWordWrap(false)

	local summary = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	summary:SetPoint("TOPLEFT", popup, "TOPLEFT", 16, -70)
	summary:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -16, -70)
	summary:SetJustifyH("CENTER")

	local confirm = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
	confirm:SetSize(126, 24)
	confirm:SetPoint("BOTTOMLEFT", 17, 11)
	confirm:SetText(L["vendorCraftShopperBuyNow"])
	local cancel = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
	cancel:SetSize(126, 24)
	cancel:SetPoint("BOTTOMRIGHT", -17, 11)
	cancel:SetText(L["vendorCraftShopperCancel"])

	local ah = C_AuctionHouse
	local function SetPurchaseName(name, quantity)
		purchaseName:SetText(("%s × %d"):format(name, quantity))
		local width = math.min(purchaseName:GetUnboundedStringWidth(), popup:GetWidth() - 78)
		purchaseName:SetWidth(width)
		purchaseIcon:ClearAllPoints()
		purchaseIcon:SetPoint("TOPLEFT", popup, "TOP", -(width + purchaseIcon:GetWidth() + 8) / 2, -34)
	end

	function frame:EndQuote(cancelQuote)
		local query = self.purchaseSearch
		self.purchaseSearch = nil
		if cancelQuote and query and query.commodity and query.cost then ah.CancelCommoditiesPurchase() end
		popup:Hide()
	end

	local function cancelPurchase()
		local query = frame.purchaseSearch
		if query and query.commodity and query.waiting then
			-- The next price event has no item ID. Drain it before opening another quote.
			query.cancelled = true
			popup:Hide()
		else
			frame:EndQuote(true)
		end
	end
	cancel:SetScript("OnClick", cancelPurchase)
	popup.CloseButton:SetScript("OnClick", cancelPurchase)
	frame:HookScript("OnHide", cancelPurchase)

	function frame:RefreshPurchaseAction()
		local query = self.purchaseSearch
		if not query or not query.cost then
			confirm:SetEnabled(false)
			return
		end
		local funds = GetMoney()
		local affordable = IsReadable(funds, "number") and funds >= query.cost
		SetPurchaseName(query.name, query.offer and query.offer.quantity or query.missing)
		summary:SetText(("%s%s"):format(_G.GetMoneyString(query.cost, true),
			affordable and "" or ("\n" .. (_G.ERR_NOT_ENOUGH_MONEY or ""))))
		confirm:SetEnabled(affordable)
	end

	local function purchaseFailed(query)
		query.waiting, query.cost, query.offer = nil, nil, nil
		summary:SetText(L["vendorCraftShopperPurchaseFailed"])
		frame:RefreshPurchaseAction()
	end

	local function queryItem(query, minPrice)
		local ahFrame = AuctionHouseFrame
		ahFrame:GetCategoriesList():SetSelectedCategory(nil)
		ahFrame:SetDisplayMode(_G.AuctionHouseFrameDisplayMode.Buy)
		ahFrame:SetSearchText(query.name)
		ahFrame:SelectBrowseResult({ itemKey = query.key, minPrice = minPrice or 0 })
		ahFrame:QueryItem(_G.AuctionHouseSearchContext.BuyItems, query.key)
	end

	function frame:StartQuickBuy(item)
		if self.purchaseSearch or not CanUseAuctionHouse() then return end
		if self.checkout and GetTime() <= self.checkout.expires then return end
		if C_Item.GetItemCount(item.itemID, true, false, false, ShouldIncludeWarbandBank()) ~= item.owned then
			Rescan()
			return
		end

		local key = ah.MakeItemKey(item.itemID)
		local info = IsReadable(key, "table") and ah.GetItemKeyInfo(key)
		local knownType = IsReadable(info, "table") and IsReadable(info.isCommodity, "boolean")
		local commodity = knownType and info.isCommodity
		local browse = not knownType or (not commodity and (not IsReadable(info.isEquipment, "boolean") or info.isEquipment))
		local query = { key = key, itemID = item.itemID, commodity = commodity, browsing = browse, waiting = true,
			missing = item.missing, name = item.name, owned = item.owned }
		if query.commodity and self.uncertainQuote then return end
		self.purchaseSearch = query
		purchaseIcon:SetTexture(item.icon or 134400)
		SetPurchaseName(item.name, item.missing)
		summary:SetText(L["vendorCraftShopperWaitingForPrice"])
		self:RefreshPurchaseAction()
		popup:Show()

		if query.commodity then
			local offer = GetPurchaseOffer(query, item.missing)
			local estimatedUnitPrice = offer and offer.quantity == item.missing and math.ceil(offer.cost / offer.quantity) or nil
			query.sending = true
			ah.StartCommoditiesPurchase(item.itemID, item.missing, estimatedUnitPrice)
			query.sending = nil
		elseif browse then
			BrowseReagent(item)
		else
			queryItem(query)
		end
		C_Timer.After(8, function()
			if self.purchaseSearch ~= query or not query.waiting then return end
			if query.commodity then self.uncertainQuote = true end
			if query.cancelled then self:EndQuote() else purchaseFailed(query) end
		end)
	end

	function frame:OnAuctionResults(event, value, total)
		local query = self.purchaseSearch
		if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
			if not IsReadable(value, "string") or (value ~= childAddonName and value ~= parentAddonName) then return end
			if query and query.sending then
				self.uncertainQuote = true
				purchaseFailed(query)
			elseif self.checkout and self.checkout.sending then
				self.checkout = nil
			end
			return
		end
		if event == "COMMODITY_PURCHASE_FAILED" and self.checkout and not self.checkout.auctionID then self.checkout = nil end
		if event == "AUCTION_HOUSE_SHOW_ERROR" then
			if self.checkout and self.checkout.auctionID then self.checkout = nil end
			return
		end
		if not query then return end
		if query.commodity then
			if event == "COMMODITY_PRICE_UPDATED" and (query.waiting or query.cost) then
				query.waiting = nil
				if query.cancelled then
					query.cost = IsPositiveNumber(total) and total or nil
					self:EndQuote(true)
				elseif IsPositiveNumber(total) then
					query.cost = total
					self:RefreshPurchaseAction()
					C_Timer.After(30, function()
						if self.purchaseSearch == query and query.cost then self:EndQuote(true) end
					end)
				else
					purchaseFailed(query)
				end
			elseif event == "COMMODITY_PRICE_UNAVAILABLE" or event == "COMMODITY_PURCHASE_FAILED" then
				if query.cancelled then self:EndQuote() else purchaseFailed(query) end
			end
			return
		end

		if event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" and query.waiting and query.browsing then
			local best
			for _, result in ipairs(ah.GetBrowseResults()) do
				if IsReadable(result, "table") and IsReadable(result.itemKey, "table") and IsPositiveNumber(result.itemKey.itemID)
					and result.itemKey.itemID == query.itemID and IsPositiveNumber(result.minPrice)
					and (not best or result.minPrice < best.minPrice) then
					local info = ah.GetItemKeyInfo(result.itemKey)
					if IsReadable(info, "table") and IsReadable(info.isCommodity, "boolean") and not info.isCommodity then best = result end
				end
			end
			if best then
				query.browsing, query.key = nil, best.itemKey
				queryItem(query, best.minPrice)
			end
			return
		end
		if event ~= "ITEM_SEARCH_RESULTS_UPDATED" or not query.waiting or not MatchesItemKey(value, query.key) then return end
		local offer = GetPurchaseOffer(query, query.missing)
		if not offer then
			purchaseFailed(query)
			return
		end
		query.waiting, query.offer, query.cost = nil, offer, offer.cost
		self:RefreshPurchaseAction()
	end

	confirm:SetScript("OnClick", function()
		local query = frame.purchaseSearch
		if not query or not query.cost or not CanUseAuctionHouse() then return end
		local itemID, funds = query.key.itemID, GetMoney()
		local current
		for _, item in ipairs(addon.Vendor.CraftShopper.items) do
			if item.itemID == itemID then
				current = item
				break
			end
		end
		if not current or current.hidden or current.missing ~= query.missing
			or C_Item.GetItemCount(itemID, true, false, false, ShouldIncludeWarbandBank()) ~= query.owned then
			frame:EndQuote(true)
			Rescan()
			return
		end
		local offer = query.offer
		if query.commodity then
			if not IsPositiveNumber(ah.GetQuoteDurationRemaining()) then
				frame:EndQuote(true)
				return
			end
		else
			local fresh = GetPurchaseOffer(query, query.missing)
			if not fresh then
				purchaseFailed(query)
				return
			end
			if not offer or fresh.auctionID ~= offer.auctionID or fresh.quantity ~= offer.quantity or fresh.cost ~= offer.cost then
				query.offer, query.cost = fresh, fresh.cost
				frame:RefreshPurchaseAction()
				return
			end
		end
		if not IsReadable(funds, "number") or funds < query.cost then return end
		local checkout = {
			itemID = itemID, quantity = offer and offer.quantity or query.missing, auctionID = offer and offer.auctionID,
			inBags = C_Item.GetItemCount(itemID), expires = GetTime() + 15, sending = true,
		}
		frame.checkout = checkout
		frame:EndQuote()
		if query.commodity then
			ah.ConfirmCommoditiesPurchase(itemID, query.missing, nil)
		else
			ah.PlaceBid(offer.auctionID, offer.cost)
		end
		checkout.sending = nil
	end)

	for _, method in ipairs({ "StartCommoditiesPurchase", "ConfirmCommoditiesPurchase", "CancelCommoditiesPurchase" }) do
		hooksecurefunc(ah, method, function()
			local query = frame.purchaseSearch
			if query and query.commodity and not query.sending then frame:EndQuote() end
			local checkout = frame.checkout
			if method == "ConfirmCommoditiesPurchase" and checkout and not checkout.auctionID and not checkout.sending then frame.checkout = nil end
		end)
	end

	function frame:OnPurchase(event, id, quantity)
		local checkout = self.checkout
		if not checkout or GetTime() > checkout.expires then return end
		if event == "COMMODITY_PURCHASED" then
			if checkout.auctionID or not IsPositiveNumber(id) or id ~= checkout.itemID or not IsPositiveNumber(quantity) or quantity ~= checkout.quantity then return end
		elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
			if checkout.auctionID then return end
		elseif not IsPositiveNumber(id) or id ~= checkout.auctionID then
			return
		end
		self.checkout = nil
		local purchase = purchasedReagents[checkout.itemID]
		purchasedReagents[checkout.itemID] = {
			quantity = checkout.quantity + (purchase and purchase.quantity or 0),
			inBags = checkout.inBags,
		}
		Rescan()
	end

	local empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	empty:SetPoint("TOP", scroll, "TOP", 0, -18)
	empty:SetText(_G.BROWSE_NO_RESULTS)

	function frame:Refresh()
		local shopper = addon.Vendor.CraftShopper
		local showQuality = shopper.hasQualityChoices == true
		qualityLabel:SetShown(showQuality)
		qualityPreference:SetShown(showQuality)
		qualityPreference:SetWidth(self:GetWidth() - 30)
		header:ClearAllPoints()
		if showQuality then
			header:SetPoint("TOPLEFT", qualityPreference, "BOTTOMLEFT", -4, -8)
		else
			header:SetPoint("TOPLEFT", ahCheck, "BOTTOMLEFT", 2, -6)
		end
		header:SetWidth(self:GetWidth() - 45)

		local searchText = (search:GetText() or ""):lower()
		local rowWidth = header:GetWidth()
		local rowHeight = 37
		local needWidth = math.max(46, header.need:GetUnboundedStringWidth() + 8)
		header.need:SetPoint("RIGHT", header, "RIGHT", -103, 0)
		header.need:SetWidth(needWidth)
		header.item:SetWidth(rowWidth - 117 - needWidth)

		local visible = {}
		for _, item in ipairs(shopper.items) do
			if not item.hidden and (not ahCheck:GetValue() or item.ahBuyable) then
				local name, _, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(item.itemID)
				item.name = name or ("item:" .. item.itemID)
				item.quality, item.icon = quality, icon
				if searchText == "" or item.name:lower():find(searchText, 1, true) then
					visible[#visible + 1] = item
				end
			end
		end
		table.sort(visible, function(left, right)
			if left.name == right.name then return left.itemID < right.itemID end
			return left.name < right.name
		end)

		for index, item in ipairs(visible) do
			local row = self.rows[index]
			if not row then
				row = CreateFrame("Frame", nil, content)
				row:SetHeight(rowHeight)
				row:EnableMouse(true)
				row.background = row:CreateTexture(nil, "BACKGROUND")
				row.background:SetAllPoints()
				row:SetScript("OnEnter", function(button)
					GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
					GameTooltip:SetItemByID(button.item.itemID)
					GameTooltip:Show()
				end)
				row:SetScript("OnLeave", function() GameTooltip:Hide() end)

				row.icon = row:CreateTexture(nil, "ARTWORK")
				row.icon:SetSize(26, 26)
				row.icon:SetPoint("LEFT", 7, 0)
				row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
				row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
				row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
				row.name:SetJustifyH("LEFT")
				row.name:SetWordWrap(false)

				row.qty = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
				row.qty:SetPoint("RIGHT", row, "RIGHT", -103, 0)
				row.qty:SetJustifyH("RIGHT")

				row.searchBtn = CreateCraftShopperIconButton(row, ICON_PATH .. "search.tga", L["vendorCraftShopperSearchAH"], function()
					if CanUseAuctionHouse() and not self.purchaseSearch then BrowseReagent(row.item) end
				end)
				row.searchBtn:SetPoint("RIGHT", row, "RIGHT", -35, 0)
				row.buyBtn = CreateCraftShopperIconButton(row, ICON_PATH .. "buy.tga", L["vendorCraftShopperBuyItems"], function()
					self:StartQuickBuy(row.item)
				end)
				row.buyBtn:SetPoint("RIGHT", row, "RIGHT", -66, 0)
				row.removeBtn = CreateCraftShopperIconButton(row, ICON_PATH .. "delete.tga", L["vendorCraftShopperHideFromList"], function()
					row.item.hidden = true
					self:Refresh()
				end)
				row.removeBtn:SetPoint("RIGHT", row, "RIGHT", -4, 0)
				self.rows[index] = row
			end

			row.item = item
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(index - 1) * rowHeight)
			row:SetWidth(rowWidth)
			row.icon:SetTexture(item.icon or 134400)
			row.name:SetWidth(rowWidth - 152 - needWidth)
			row.name:SetText(item.name)
			local red, green, blue = C_Item.GetItemQualityColor(item.quality or 1)
			row.name:SetTextColor(red, green, blue)
			row.qty:SetWidth(needWidth)
			row.qty:SetText(item.missing)
			row.searchBtn:SetShown(item.ahBuyable)
			row.buyBtn:SetShown(item.ahBuyable)
			row.background:SetColorTexture(1, 1, 1, index % 2 == 0 and 0.065 or 0.035)
			row:Show()
		end
		for index = #visible + 1, #self.rows do
			self.rows[index]:Hide()
		end

		content:SetSize(rowWidth, math.max(1, #visible * rowHeight))
		if scroll:GetVerticalScroll() > scroll:GetVerticalScrollRange() then
			scroll:SetVerticalScroll(scroll:GetVerticalScrollRange())
		end
		empty:SetShown(#visible == 0)
	end

	addon.Vendor.CraftShopper.frame = frame
	frame:SetScript("OnSizeChanged", function(self)
		if self:IsShown() then self:Refresh() end
	end)
	return frame
end

function ShowCraftShopperFrameIfNeeded()
	if not AuctionHouseFrame or not AuctionHouseFrame:IsShown() then return end

	local hasItems = false
	for _, item in ipairs(addon.Vendor.CraftShopper.items) do
		if item.ahBuyable and item.missing > 0 then
			hasItems = true
			break
		end
	end

	if hasItems then
		local ui = CreateCraftShopperFrame()
		SyncCraftShopperQualityControls()
		if not ui.frame.userMoved and not ui.frame.userSized then
			ui.frame:ClearAllPoints()
			ui.frame:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", addon.variables.isForever and 12 or 7, 0)
			local width = math.max(380, AuctionHouseFrame:GetWidth() * 0.44)
			local height = math.max(280, AuctionHouseFrame:GetHeight())
			ui.frame:SetSize(width, height)
		end
			ui.frame:Show()
		ui:Refresh()
	else
		HideCraftShopperFrame()
	end
end

function addon.Vendor.CraftShopper.EnableCraftShopper()
	f:RegisterEvent("TRACKED_RECIPE_UPDATE")
	EnsureCraftShopperProfessionsUI()
	if HasTrackedRecipes() then
		RegisterHeavyEvents()
		Rescan()
	else
		UnregisterHeavyEvents()
	end
	if RefreshMultiplyUIState then RefreshMultiplyUIState() end
end

function addon.Vendor.CraftShopper.DisableCraftShopper()
	f:UnregisterEvent("TRACKED_RECIPE_UPDATE")
	f:UnregisterEvent("ADDON_LOADED")
	UnregisterHeavyEvents()
	CancelPendingAHShowScan()
	if pendingScan then
		pendingScan:Cancel()
		pendingScan = nil
	end
	if addon.Vendor.CraftShopper.frame then addon.Vendor.CraftShopper.frame.frame:Hide() end
	if _G.EQOLCrafterMultiply then _G.EQOLCrafterMultiply:Hide() end
	local checkbox = GetTrackRecipeCheckbox()
	if checkbox and checkbox.SetAlpha then checkbox:SetAlpha(1) end
end

local function initializeCraftShopper()
	if addon.db["vendorCraftShopperEnable"] then addon.Vendor.CraftShopper.EnableCraftShopper() end
end
if IsLoggedIn and IsLoggedIn() then
	initializeCraftShopper()
else
	f:RegisterEvent("PLAYER_LOGIN")
end

local function addToCraftShopper(el)
	if not el or not el.GetText then return end
	local txt = el:GetText()
	local count = tonumber(txt)
	if count == nil then
		el:SetText("")
		return
	end

	-- Determine current recipeID from the professions UI
	local recipeID
	if
		ProfessionsFrame
		and ProfessionsFrame.CraftingPage
		and ProfessionsFrame.CraftingPage.SchematicForm
		and ProfessionsFrame.CraftingPage.SchematicForm.currentRecipeInfo
		and ProfessionsFrame.CraftingPage.SchematicForm.currentRecipeInfo.recipeID
	then
		recipeID = ProfessionsFrame.CraftingPage.SchematicForm.currentRecipeInfo.recipeID
	end

	if not recipeID then return end

	count = math.floor(count)
	if count <= 0 then
		-- 0 => löschen: Multiplikator entfernen und Rezept untracken
		addon.Vendor.CraftShopper.multipliers[recipeID] = nil
		if C_TradeSkillUI and C_TradeSkillUI.SetRecipeTracked then pcall(C_TradeSkillUI.SetRecipeTracked, recipeID, false, false) end
		el:SetText("")
	else
		-- Store multiplier and ensure recipe is tracked
		addon.Vendor.CraftShopper.multipliers[recipeID] = count
		if C_TradeSkillUI and C_TradeSkillUI.SetRecipeTracked then pcall(C_TradeSkillUI.SetRecipeTracked, recipeID, true, false) end
		el:SetText("")
	end

	-- Update list immediately and show the UI
	addon.Vendor.CraftShopper.items = BuildShoppingList()
	if addon.Vendor.CraftShopper.frame then addon.Vendor.CraftShopper.frame:Refresh() end
	ShowCraftShopperFrameIfNeeded()
end

createCrafterMultiplyFrame = function()
	local schematicForm = ProfessionsFrame and ProfessionsFrame.CraftingPage and ProfessionsFrame.CraftingPage.SchematicForm
	if not schematicForm then return nil end
	if _G.EQOLCrafterMultiply then return _G.EQOLCrafterMultiply end

	local fCMF = CreateFrame("frame", "EQOLCrafterMultiply", schematicForm, "BackdropTemplate")
	-- Compact, unobtrusive container in the top-right of the schematic form

	-- local parent = ProfessionsFrame.CraftingPage.SchematicForm.TrackRecipeCheckbox
	local parent = fCMF
	-- fCMF:SetPoint("RIGHT", ProfessionsFrame.CraftingPage.SchematicForm.TrackRecipeCheckbox, "LEFT", -5)
	fCMF:SetPoint("TOPRIGHT", schematicForm, "TOPRIGHT", -5)
	fCMF:SetSize(260, 32)
	fCMF:SetFrameStrata("HIGH")
	fCMF:EnableMouse(true)
	fCMF.autoFilled = false

	-- Visible, skinned OK button
	local btnOK = CreateFrame("Button", nil, fCMF, "UIPanelButtonTemplate")
	local eb = CreateFrame("EditBox", nil, fCMF, "InputBoxTemplate")
	local label = fCMF:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")

	fCMF.ok = btnOK
	btnOK:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -3, -2)
	btnOK:SetSize(70, 22)
	btnOK:SetText(TRACK_ACHIEVEMENT)
	btnOK:SetScript("OnClick", function()
		if btnOK:GetText() == PROFESSIONS_UNTRACK_RECIPE then
			fCMF.autoFilled = false
			eb:SetText("0")
			addToCraftShopper(eb)
			eb:ClearFocus()
			if RefreshMultiplyUIState then RefreshMultiplyUIState() end
			return
		end
		if eb and eb.GetText then
			if nil == eb:GetText() or eb:GetText() == "" then
				fCMF.autoFilled = true
				eb:SetText("1")
			end
		end
		addToCraftShopper(eb)
		eb:ClearFocus()
		if RefreshMultiplyUIState then RefreshMultiplyUIState() end
	end)

	-- Label + edit box for quantity
	label:SetPoint("RIGHT", eb, "LEFT", -6, 0)
	label:SetText(L["vendorCraftShopperTrackQuantity"])

	fCMF.editBox = eb
	eb:SetPoint("RIGHT", btnOK, "LEFT", -3, 0)
	eb:SetAutoFocus(false)
	eb:SetHeight(22)
	eb:SetWidth(60)
	eb:SetFontObject(ChatFontNormal)
	eb:SetMaxLetters(5)

	eb:SetScript("OnEnterPressed", function(self)
		if (self:GetText() or "") == "" then
			if self:GetParent() then self:GetParent().autoFilled = true end
			self:SetText("1")
		end
		addToCraftShopper(self)
		self:ClearFocus()
		if RefreshMultiplyUIState then RefreshMultiplyUIState() end
	end)
	eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	eb:SetScript("OnTextChanged", function(self, userInput)
		if userInput and self:GetParent() then self:GetParent().autoFilled = false end
		if RefreshMultiplyUIState then RefreshMultiplyUIState() end
	end)

	-- Ensure sub-widgets are visible (frame visibility controlled below)
	eb:Show()
	btnOK:Show()

	-- Track recipe changes to refresh button label
	fCMF._accum = 0
	fCMF.lastRecipeID = nil
	local function updateRecipeWatcher(self, elapsed)
		self._accum = (self._accum or 0) + elapsed
		if self._accum < 0.3 then return end
		self._accum = 0
		local rid
		if GetCurrentRecipeID then rid = GetCurrentRecipeID() end
		if rid ~= self.lastRecipeID then
			self.lastRecipeID = rid
			self.autoFilled = false
			if self.editBox and self.editBox:GetText() ~= "" then self.editBox:SetText("") end
			if UpdateMultiplyFrameState then UpdateMultiplyFrameState() end
		end
	end
	fCMF:SetScript("OnShow", function(self)
		self._accum = 0
		self:SetScript("OnUpdate", updateRecipeWatcher)
	end)
	fCMF:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)

	-- Default hidden; only show when enabled and professions is visible
	fCMF:Hide()
	if RefreshMultiplyUIState then RefreshMultiplyUIState() end

	return fCMF
end

f:SetScript("OnEvent", function(_, event, arg1, arg2)
	if event == "PLAYER_LOGIN" then
		initializeCraftShopper()
	elseif event == "ADDON_LOADED" and arg1 == "Blizzard_Professions" then
		if IsCraftShopperEnabled() then EnsureCraftShopperProfessionsUI() end
		-- No longer need to listen for further ADDON_LOADED
		f:UnregisterEvent("ADDON_LOADED")
	elseif event == "TRADE_SKILL_SHOW" then
		if IsCraftShopperEnabled() then EnsureCraftShopperProfessionsUI() end
		if RefreshMultiplyUIState then RefreshMultiplyUIState() end
	elseif event == "TRADE_SKILL_CLOSE" then
		if _G.EQOLCrafterMultiply then _G.EQOLCrafterMultiply:Hide() end
		local checkbox = GetTrackRecipeCheckbox()
		if checkbox and checkbox.SetAlpha and IsCraftShopperEnabled() then checkbox:SetAlpha(1) end
	elseif event == "TRACKED_RECIPE_UPDATE" then
		CleanupUntrackedMultipliers()
		if HasTrackedRecipes() then
			RegisterHeavyEvents()
			ScheduleRescan()
		else
			UnregisterHeavyEvents()
			if pendingScan then
				pendingScan:Cancel()
				pendingScan = nil
			end
			if addon.Vendor.CraftShopper.frame then addon.Vendor.CraftShopper.frame.frame:Hide() end
		end
		if RefreshMultiplyUIState then RefreshMultiplyUIState() end
	elseif event == "BAG_UPDATE_DELAYED" then
		ScheduleRescan()
	elseif event == "CRAFTINGORDERS_ORDER_PLACEMENT_RESPONSE" then
		if arg1 == 0 and not scanRunning then Rescan() end
	elseif event == "AUCTION_HOUSE_SHOW" then
		Rescan()
		CancelPendingAHShowScan()
		-- AH open can race recipe tracking data settling; retry once shortly after show.
		pendingAHShowScan = C_Timer.NewTimer(SCAN_DELAY, function()
			pendingAHShowScan = nil
			Rescan()
		end)
	elseif event == "ITEM_SEARCH_RESULTS_UPDATED" or event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" or event == "COMMODITY_PRICE_UPDATED"
		or event == "COMMODITY_PRICE_UNAVAILABLE" or event == "COMMODITY_PURCHASE_FAILED" or event == "AUCTION_HOUSE_SHOW_ERROR"
		or event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
		local panel = addon.Vendor.CraftShopper.frame
		if panel then panel:OnAuctionResults(event, arg1, arg2) end
	elseif event == "AUCTION_HOUSE_PURCHASE_COMPLETED" or event == "COMMODITY_PURCHASED" or event == "COMMODITY_PURCHASE_SUCCEEDED" then
		local panel = addon.Vendor.CraftShopper.frame
		if panel then panel:OnPurchase(event, arg1, arg2) end
	elseif event == "PLAYER_MONEY" then
		local panel = addon.Vendor.CraftShopper.frame
		if panel and panel:IsShown() then panel:RefreshPurchaseAction() end
	elseif event == "ITEM_DATA_LOAD_RESULT" then
		if not arg2 then return end
		local shopper = addon.Vendor.CraftShopper
		if shopper.frame and shopper.frame:IsShown() then
			for _, item in ipairs(shopper.items) do
				if item.itemID == arg1 then
					shopper.frame:Refresh()
					break
				end
			end
		end
	elseif event == "AUCTION_HOUSE_CLOSED" then
		CancelPendingAHShowScan()
		local panel = addon.Vendor.CraftShopper.frame
		if panel then
			panel.checkout, panel.uncertainQuote = nil, nil
			panel:EndQuote()
		end
		HideCraftShopperFrame()
	else
		Rescan()
	end
end)

function addon.Vendor.functions.checkList()
	Rescan()
	for _, item in ipairs(addon.Vendor.CraftShopper.items) do
		if item.ahBuyable then
			local info = C_Item.GetItemInfo(item.itemID)
			print(L["vendorCraftShopperCheckListPrint"]:format(info or ("ItemID " .. item.itemID), item.missing))
		end
	end
end
