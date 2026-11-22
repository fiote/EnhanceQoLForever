-- luacheck: globals C_Bank ACCOUNT_BANK_TITLE
local addon = _G.EnhanceQoL
local L = addon.L
local M = { contextID = "characterBank", buttons = {}, headers = {} }
addon.Bags.OfflineBank = M
M.isTBC = addon.variables and addon.variables.isTBC
M.hasAccountBank = not (addon.variables and addon.variables.isForever) and not M.isTBC
M.types = { characterBank = Enum and Enum.BankType and Enum.BankType.Character or 0, accountBank = Enum and Enum.BankType and Enum.BankType.Account or 2 }

function M.GetStore()
	if not addon.savedVariablesLoaded then addon.InitializeSavedVariables() end
	addon.DB.bankSnapshots = addon.DB.bankSnapshots or { version = 1, characters = {} }
	return addon.DB.bankSnapshots
end

function M.GetSnapshot(contextID)
	local store = M.GetStore()
	-- Preserve foreign-flavor snapshots for imports; only Retail can read or update them.
	if contextID == "accountBank" then return M.hasAccountBank and store.accountBank or nil end
	local guid = UnitGUID("player")
	return guid and store.characters[guid] or nil
end

function M.IsViewable(contextID)
	if not M.sessionOpen or (contextID == "accountBank" and not M.hasAccountBank) then return false end
	if M.isTBC then return contextID == "characterBank" end
	return C_Bank and C_Bank.CanViewBank and C_Bank.CanViewBank(M.types[contextID]) == true
end

function M.GetBagIDs(contextID)
	if M.isTBC then
		local ids = { BANK_CONTAINER }
		for id = NUM_BAG_SLOTS + 1, NUM_BAG_SLOTS + NUM_BANKBAGSLOTS do
			if C_Container.GetContainerNumSlots(id) > 0 then ids[#ids + 1] = id end
		end
		return ids
	end
	if C_Bank.FetchPurchasedBankTabIDs then return C_Bank.FetchPurchasedBankTabIDs(M.types[contextID]) end
	local context
	if contextID == "characterBank" then context = addon.GetVisibleCharacterBankContext()
	else context = addon.GetVisibleWarbandBankContext() end
	return context and context.bagIDs
end

function M.CaptureContext(contextID, updatedBags)
	if not M.IsViewable(contextID) then return false end
	local ids = M.GetBagIDs(contextID)
	-- A temporarily absent tab list must not erase an earlier visit.
	if not ids or #ids == 0 then M.captureNeedsRetry = true; return false end
	local previous = M.GetSnapshot(contextID)
	if updatedBags then
		local relevant = false
		for _, bagID in ipairs(ids) do if updatedBags[bagID] then relevant = true; break end end
		if not relevant then return false end
		if previous and previous.incomplete then updatedBags = nil end
	end
	local snapshot = previous or { bags = {}, order = {} }
	local stamp, oldest, incomplete, captured = time(), nil, false, false
	for _, bagID in ipairs(ids) do
		local bag = snapshot.bags[bagID]
		local slots = (not updatedBags or updatedBags[bagID] or not bag) and C_Container.GetContainerNumSlots(bagID) or nil
		if slots and slots > 0 then
			bag = bag or { items = {} }
			bag.slots, bag.updatedAt = slots, stamp
			for slot = 1, slots do
				local info = C_Container.GetContainerItemInfo(bagID, slot)
				if info and info.itemID then
					local item = bag.items[slot] or {}
					item.itemID, item.link, item.icon = info.itemID, info.hyperlink, info.iconFileID
					item.count, item.quality = info.stackCount, info.quality
					if M.Layout then M.Layout.CaptureItem(item, bagID, slot, info) end
					bag.items[slot] = item
				else
					bag.items[slot] = nil
				end
			end
			for slot in pairs(bag.items) do if slot > slots then bag.items[slot] = nil end end
			captured = true
		elseif not updatedBags or updatedBags[bagID] or not bag then
			incomplete = true
		end
		if bag then
			snapshot.bags[bagID] = bag
			oldest = math.min(oldest or stamp, bag.updatedAt)
		end
	end
	if incomplete then M.captureNeedsRetry = true end
	if not captured then return false end
	local count = 0
	for _, bagID in ipairs(ids) do
		if snapshot.bags[bagID] then count = count + 1; snapshot.order[count] = bagID end
	end
	for index = #snapshot.order, count + 1, -1 do snapshot.order[index] = nil end
	for bagID in pairs(snapshot.bags) do
		local present = false
		for _, id in ipairs(ids) do if id == bagID then present = true; break end end
		if not present then snapshot.bags[bagID] = nil end
	end
	snapshot.updatedAt, snapshot.incomplete = oldest or stamp, incomplete
	local store = M.GetStore()
	if contextID == "accountBank" then
		store.accountBank = snapshot
	else
		local guid = UnitGUID("player")
		if not guid then return false end
		store.characters[guid] = snapshot
	end
	return true
end

function M.Capture(updatedBags)
	if not addon.Bags.IsEnabled() then return end
	M.captureNeedsRetry = nil
	local changed = M.CaptureContext("characterBank", updatedBags)
	if M.hasAccountBank then changed = M.CaptureContext("accountBank", updatedBags) or changed end
	if changed and M.frame and M.frame:IsShown() then M.Render() end
	return M.captureNeedsRetry
end

function M.QueueCapture()
	if M.pending or not M.sessionOpen then return end
	M.pending = true
	local session = M.session
	C_Timer.After(0.2, function()
		if session ~= M.session then return end
		M.pending = nil
		M.Capture()
	end)
end

function M.GetButton(index)
	local button = M.buttons[index]
	if button then return button end
	-- Plain buttons deliberately have no container, item-use or drag handlers.
	button = CreateFrame("Button", nil, M.content)
	button:SetSize(38, 38)
	button.Icon = button:CreateTexture(nil, "ARTWORK")
	button.Icon:SetAllPoints()
	button.Count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	button.Count:SetPoint("BOTTOMRIGHT", -2, 2)
	button:SetScript("OnEnter", function(self)
		local item = self.item
		if not item then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetHyperlink(item.link or ("item:" .. item.itemID))
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	M.buttons[index] = button
	return button
end

function M.Render()
	if not M.frame then return end
	for _, button in ipairs(M.buttons) do button.item = nil; button:Hide() end
	for _, header in ipairs(M.headers) do header:Hide() end
	local snapshot = M.GetSnapshot(M.contextID)
	M.characterTab:SetEnabled(M.contextID ~= "characterBank")
	if M.accountTab then M.accountTab:SetEnabled(M.contextID ~= "accountBank") end
	M.status:SetText(snapshot and string.format(L["bagsOfflineBankSavedAt"], date("%Y-%m-%d %H:%M", snapshot.updatedAt)) or L["bagsOfflineBankEmpty"])
	M.note:SetText(snapshot and snapshot.incomplete and L["bagsOfflineBankIncomplete"] or L["bagsOfflineBankReadOnly"])
	M.Layout.Render(snapshot)
end

function M.EnsureFrame()
	if M.frame then return end
	local frame = CreateFrame("Frame", "EnhanceQoLOfflineBankFrame", UIParent, "BackdropTemplate")
	M.frame = frame
	frame:SetSize(600, 480)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self) if not GetCursorInfo() then self:StartMoving() end end)
	frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
	frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	frame:SetBackdropColor(0.035, 0.04, 0.055, 0.97)
	frame:SetBackdropBorderColor(0.3, 0.33, 0.4, 1)
	frame.BackgroundTexture = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
	frame.BackgroundShade = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
	frame.CustomBorderFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	frame.CustomBorderFrame:SetFrameLevel(frame:GetFrameLevel() + 2)
	frame.CustomBorderFrame:EnableMouse(false)
	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 18, -16)
	title:SetText(L["bagsOfflineBankTitle"])
	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)
	frame.CloseButton = close
	if addon.Bags.Toolbar then addon.Bags.Toolbar.Attach(frame) end
	M.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	M.status:SetPoint("TOPLEFT", 18, -45)
	M.status:SetPoint("TOPRIGHT", -18, -45)
	M.status:SetJustifyH("LEFT")
	M.status:SetWordWrap(true)
	M.note = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	M.note:SetPoint("BOTTOMLEFT", 18, 14)
	M.note:SetPoint("BOTTOMRIGHT", -18, 14)
	M.note:SetJustifyH("LEFT")
	M.note:SetWordWrap(true)
	M.characterTab = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	M.characterTab:SetSize(200, 24)
	M.characterTab:SetPoint("TOPLEFT", 18, -90)
	M.characterTab:SetText(BANK)
	M.characterTab:SetScript("OnClick", function() M.SelectContext("characterBank") end)
	if M.hasAccountBank then
		M.accountTab = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
		M.accountTab:SetSize(200, 24)
		M.accountTab:SetPoint("LEFT", M.characterTab, "RIGHT", 8, 0)
		M.accountTab:SetText(ACCOUNT_BANK_PANEL_TITLE or ACCOUNT_BANK_TITLE or BANK)
		M.accountTab:SetScript("OnClick", function() M.SelectContext("accountBank") end)
	end
	if not M.hasAccountBank then M.characterTab:Hide() end
	M.scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
	M.scroll:SetPoint("TOPLEFT", 18, M.hasAccountBank and -128 or -88)
	M.scroll:SetPoint("BOTTOMRIGHT", -40, 52)
	M.content = CreateFrame("Frame", nil, M.scroll)
	M.content:SetSize(528, 1)
	M.scroll:SetScrollChild(M.content)
	frame:SetScript("OnHide", function() GameTooltip:Hide() end)
	table.insert(UISpecialFrames, "EnhanceQoLOfflineBankFrame")
	frame:Hide()
	for _, name in ipairs({ "RequestLayoutUpdate", "RequestBankLayoutUpdate", "RefreshGlobalFont" }) do
		if addon.Bags.functions[name] then hooksecurefunc(addon.Bags.functions, name, M.QueueRender) end
	end
end

function M.SelectContext(contextID)
	if contextID == "accountBank" and not M.hasAccountBank then return end
	M.contextID = contextID
	M.scroll:SetVerticalScroll(0)
	M.Render()
end

function M.Toggle()
	if not addon.Bags.IsEnabled() then return end
	M.EnsureFrame()
	if M.frame:IsShown() then M.frame:Hide(); return end
	M.scroll:SetVerticalScroll(0)
	M.Render()
	M.frame:Show()
end

function M.QueueRender()
	if M.renderPending or not M.frame or not M.frame:IsShown() then return end
	M.renderPending = true
	C_Timer.After(0, function()
		M.renderPending = nil
		if M.frame:IsShown() then M.Render() end
	end)
end

function M.CreateOpenButton(frame)
	local button = CreateFrame("Button", nil, frame)
	button:SetSize(18, 18)
	button:SetNormalTexture("Interface\\Icons\\INV_Misc_Bag_10_Blue")
	button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
	button:SetScript("OnClick", M.Toggle)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(L["bagsOfflineBankButton"])
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return button
end

M.events = CreateFrame("Frame")
M.events:RegisterEvent("BANKFRAME_OPENED")
M.events:RegisterEvent("BANKFRAME_CLOSED")
M.updatedBags = {}
M.events:RegisterEvent("BAG_UPDATE")
M.events:RegisterEvent("BAG_UPDATE_DELAYED")
M.events:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
M.events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
M.events:RegisterEvent("DISPLAY_SIZE_CHANGED")
M.events:RegisterEvent("UI_SCALE_CHANGED")
if M.isTBC then M.events:RegisterEvent("PLAYERBANKBAGSLOTS_CHANGED") end
if not M.isTBC then M.events:RegisterEvent("BANK_TABS_CHANGED") end
M.events:SetScript("OnEvent", function(_, event, bagID)
	if event == "BAG_UPDATE" then
		if M.sessionOpen and bagID ~= nil then M.updatedBags[bagID] = true end
		return
	elseif event == "GET_ITEM_INFO_RECEIVED" or event == "DISPLAY_SIZE_CHANGED" or event == "UI_SCALE_CHANGED" then
		M.QueueRender()
	elseif event == "BANKFRAME_OPENED" then
		for id in pairs(M.updatedBags) do M.updatedBags[id] = nil end
		M.session = (M.session or 0) + 1
		M.sessionOpen, M.pending = true, nil
		if M.frame then M.frame:Hide() end
		M.QueueCapture()
		local session = M.session
		for _, delay in ipairs({ 0.8, 2 }) do
			C_Timer.After(delay, function() if M.sessionOpen and M.session == session then M.Capture() end end)
		end
	elseif event == "BANKFRAME_CLOSED" then
		-- Never read containers after closing: clients may already have cleared them.
		M.sessionOpen, M.pending = false, nil
		M.session = (M.session or 0) + 1
	else
		if event == "BAG_UPDATE_DELAYED" then
			local updatedBags = next(M.updatedBags) and M.updatedBags or nil
			-- Keep synchronous snapshots before close; unrelated player-bag updates need no bank scan.
			local needsRetry = M.Capture(updatedBags)
			for id in pairs(M.updatedBags) do M.updatedBags[id] = nil end
			if updatedBags and not needsRetry then return end
		elseif event == "PLAYERBANKSLOTS_CHANGED" then
			M.Capture()
		end
		M.QueueCapture()
	end
end)

if addon.Bags.ItemRules then addon.Bags.ItemRules.Subscribe(M.QueueRender) end

_G.SLASH_EQOLOFFLINEBANK1 = "/eqolbank"
SlashCmdList.EQOLOFFLINEBANK = M.Toggle
