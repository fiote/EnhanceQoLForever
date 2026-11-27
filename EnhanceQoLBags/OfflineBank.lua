-- luacheck: globals C_Bank ACCOUNT_BANK_TITLE
local addon = _G.EnhanceQoL
local L = addon.L
local M = { contextID = "characterBank", buttons = {}, headers = {} }
addon.Bags.OfflineBank = M
M.isTBC = addon.variables and addon.variables.isTBC
M.isForever = addon.variables and addon.variables.isForever and not M.isTBC
M.hasAccountBank = not M.isForever and not M.isTBC
M.types = { characterBank = Enum and Enum.BankType and Enum.BankType.Character or 0, accountBank = Enum and Enum.BankType and Enum.BankType.Account or 2 }

function M.GetStore()
	if not addon.savedVariablesLoaded then addon.InitializeSavedVariables() end
	addon.DB.bankSnapshots = addon.DB.bankSnapshots or { version = 1, characters = {} }
	return addon.DB.bankSnapshots
end

function M.GetSnapshot(contextID, characterGUID)
	local store = M.GetStore()
	-- Preserve foreign-flavor snapshots for imports; only Retail can read or update them.
	if contextID == "accountBank" then return M.hasAccountBank and store.accountBank or nil end
	local guid = characterGUID or UnitGUID("player")
	return guid and store.characters[guid] or nil
end

function M.GetCharacterIdentity()
	local name = M.isForever and addon.functions and addon.functions.GetUnitDisplayName and addon.functions.GetUnitDisplayName("player")
	return {
		name = name or UnitName("player"),
		realm = GetRealmName(),
		ruleset = M.isForever and addon.Bags.GetCurrentRuleset() or nil,
		faction = UnitFactionGroup("player"),
	}
end

function M.GetCharacters()
	local guid = UnitGUID("player")
	local current = M.GetCharacterIdentity()
	current.guid = guid
	local entries = { current }
	local store = M.GetStore()
	local tracker = addon.DB.moneyTracker or {}
	for id, snapshot in pairs(store.characters) do
		if id ~= guid then
			local owner, tracked = snapshot.owner or {}, tracker[id] or {}
			local name = owner.name or tracked.name
			if name and name ~= "" then
				entries[#entries + 1] = {
					guid = id, name = name, realm = owner.realm or tracked.realm,
					ruleset = owner.ruleset or tracked.ruleset, faction = owner.faction or tracked.faction,
				}
			end
		end
	end
	local lower = strlower or string.lower
	for _, entry in ipairs(entries) do
		entry.label = entry.name or UNKNOWN
		if not M.isForever and entry.realm and entry.realm ~= current.realm then
			entry.label = entry.label .. " - " .. entry.realm
		end
	end
	table.sort(entries, function(a, b)
		if a == current or b == current then return a == current end
		local left, right = lower(a.label), lower(b.label)
		if left ~= right then return left < right end
		return a.guid < b.guid
	end)
	return entries, current
end

function M.PopulateCharacterMenu(root, entries, current)
	local function addCharacter(parent, entry)
		parent:CreateRadio(entry.label, function()
			return (M.characterGUID or current.guid) == entry.guid
		end, function()
			M.SelectCharacter(entry)
		end)
	end
	if root.SetScrollMode then root:SetScrollMode(360) end
	if not M.isForever then
		for _, entry in ipairs(entries) do addCharacter(root, entry) end
		return
	end

	local groups, order = {}, {}
	local factions = { Alliance = FACTION_ALLIANCE, Horde = FACTION_HORDE }
	local function rulesetLabel(ruleset)
		if ruleset == "" then return UNKNOWN end
		return ruleset == "Hardcore" and (HARDCORE or ruleset) or ruleset
	end
	local primaryRuleset = current.ruleset or ""
	local primaryFaction = factions[current.faction] and current.faction or ""
	root:CreateTitle(rulesetLabel(primaryRuleset) .. " · " .. (factions[primaryFaction] or UNKNOWN))
	for _, entry in ipairs(entries) do
		local ruleset = entry.ruleset or ""
		local faction = factions[entry.faction] and entry.faction or ""
		if ruleset == primaryRuleset and faction == primaryFaction then
			addCharacter(root, entry)
		else
			if not groups[ruleset] then
				groups[ruleset] = {}
				order[#order + 1] = ruleset
			end
			local group = groups[ruleset]
			group[faction] = group[faction] or {}
			group[faction][#group[faction] + 1] = entry
		end
	end
	if #order > 0 then root:CreateDivider() end
	table.sort(order, function(a, b)
		if (a == primaryRuleset) ~= (b == primaryRuleset) then return a == primaryRuleset end
		if a == "" then return false end
		if b == "" then return true end
		return a < b
	end)
	for _, ruleset in ipairs(order) do
		local rulesetMenu = root:CreateButton(rulesetLabel(ruleset))
		for _, faction in ipairs({ "Alliance", "Horde", "" }) do
			local characters = groups[ruleset][faction]
			if characters then
				local factionMenu = rulesetMenu:CreateButton(factions[faction] or UNKNOWN)
				if factionMenu.SetScrollMode then factionMenu:SetScrollMode(360) end
				for _, entry in ipairs(characters) do addCharacter(factionMenu, entry) end
			end
		end
	end
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

local function isUnequippedBankBag(contextID, bagID, bag)
	if not (addon.variables.isForever and contextID == "characterBank" and C_Bank.ShouldUsePlayerBagsInBank
		and C_Bank.ShouldUsePlayerBagsInBank() and C_Container.GetContainerItemID) then return false end
	local indices = Enum and Enum.BagIndex
	local first = indices and indices.CharacterBankTab_1
	local last = indices and indices.CharacterBankTab_9
	local equipment = indices and indices.Characterbanktab
	if not (first and last and equipment and bagID > first and bagID <= last) then return false end
	-- Trust an empty equipment slot only while the main bank is readable. Keep saved items
	-- if the equipment and capacity reads both temporarily come back empty.
	return (not bag or not next(bag.items)) and C_Container.GetContainerNumSlots(first) > 0
		and C_Container.GetContainerItemID(equipment, bagID - first + 1) == nil
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
		elseif slots == 0 and isUnequippedBankBag(contextID, bagID, bag) then
			captured = captured or bag ~= nil
			snapshot.bags[bagID], bag = nil, nil
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
		snapshot.owner = M.GetCharacterIdentity()
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
	button.icon = button.Icon
	button.searchOverlay = button:CreateTexture(nil, "OVERLAY", nil, 7)
	button.searchOverlay:SetAllPoints()
	button.searchOverlay:SetColorTexture(0, 0, 0, 0.8)
	button.searchOverlay:Hide()
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
	local snapshot = M.GetSnapshot(M.contextID, M.characterGUID)
	M.characterTab:SetEnabled(M.contextID ~= "characterBank")
	if M.accountTab then M.accountTab:SetEnabled(M.contextID ~= "accountBank") end
	M.savedAt:SetShown(snapshot ~= nil)
	if snapshot then M.savedAt:SetText(string.format(L["bagsOfflineBankSavedAt"], date("%Y-%m-%d %H:%M", snapshot.updatedAt))) end
	M.note:SetText(snapshot and snapshot.incomplete and L["bagsOfflineBankIncomplete"] or "")
	M.note:SetShown(snapshot and snapshot.incomplete == true or false)
	M.characterPicker:SetShown(M.contextID == "characterBank")
	M.characterPicker:SetText(M.characterName or M.GetCharacterIdentity().name or UNKNOWN)
	M.frame.HeaderSearchRight = M.contextID == "characterBank" and M.characterPicker or nil
	local search = M.frame.SearchBox
	search:SetShown(snapshot ~= nil)
	local baseSize = addon.GetResolvedTextAppearance().size
	addon.ApplyConfiguredFont(M.frame.Title, baseSize + 2)
	addon.ApplyConfiguredFont(search, math.max(10, baseSize - 1))
	if search.Instructions then addon.ApplyConfiguredFont(search.Instructions, math.max(10, baseSize - 1)) end
	addon.Bags.Header.Apply(M.frame, M.frame.CloseButton)
	M.status:SetShown(snapshot == nil)
	M.scroll:SetShown(snapshot ~= nil)
	M.Layout.Render(snapshot)
end

function M.SizeToContent(width, height, scale, hasSnapshot)
	local frame = M.frame
	local headerWidth = frame.Title:GetStringWidth() + (hasSnapshot and 140 or 0)
		+ (frame.HeaderSearchRight and frame.HeaderSearchRight:GetWidth() + 10 or 0) + 72
	local maxWidth = (UIParent:GetWidth() - 40) / scale
	local maxHeight = (UIParent:GetHeight() - 40) / scale
	width = math.max(420, math.ceil(headerWidth), width + 36)
	frame:SetWidth(math.min(width, maxWidth))
	local function footerHeight()
		M.note:SetWidth(math.max(1, frame:GetWidth() - 36))
		local height = hasSnapshot and math.ceil(M.savedAt:GetStringHeight()) + 24 or 14
		return height + (M.note:IsShown() and math.ceil(M.note:GetStringHeight()) + 4 or 0)
	end
	local bottom = footerHeight()
	local availableHeight = math.max(1, maxHeight - M.scrollTop - bottom)
	local scrolls = hasSnapshot and height > availableHeight
	if scrolls then
		frame:SetWidth(math.min(width + 22, maxWidth))
		bottom = footerHeight()
		availableHeight = math.max(1, maxHeight - M.scrollTop - bottom)
	end
	M.scroll:SetPoint("BOTTOMRIGHT", scrolls and -40 or -18, bottom)
	if M.scroll.ScrollBar then M.scroll.ScrollBar:SetShown(scrolls) end
	M.content:SetWidth(math.max(1, frame:GetWidth() - (scrolls and 58 or 36)))
	M.content:SetHeight(height)
	local visibleHeight = hasSnapshot and math.min(height, availableHeight) or math.ceil(M.status:GetStringHeight()) + 12
	frame:SetHeight(M.scrollTop + math.max(24, visibleHeight) + bottom)
	M.scroll:SetVerticalScroll(math.min(M.scroll:GetVerticalScroll(), math.max(0, height - visibleHeight)))
end

function M.EnsureFrame()
	if M.frame then return end
	local frame = CreateFrame("Frame", "EnhanceQoLOfflineBankFrame", UIParent, "BackdropTemplate")
	M.frame = frame
	frame:SetSize(420, 120)
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
	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetSize(24, 24)
	close:SetPoint("TOPRIGHT", -10, -6)
	close:SetScript("OnClick", function() frame:Hide() end)
	frame.CloseButton = close
	if addon.Bags.Toolbar then addon.Bags.Toolbar.Attach(frame) end
	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("LEFT", frame, "TOPLEFT", 18, -18)
	title:SetJustifyH("LEFT")
	title:SetWordWrap(false)
	title:SetText(BANK)
	frame.Title = title
	M.savedAt = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	M.savedAt:SetPoint("BOTTOMLEFT", 18, 14)
	local search = CreateFrame("EditBox", nil, frame, "SearchBoxTemplate")
	frame.SearchBox = search
	search:SetAutoFocus(false)
	search:SetHeight(20)
	search:HookScript("OnTextChanged", function()
		M.Layout.ApplySearch()
	end)
	local picker = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	M.characterPicker = picker
	picker:SetSize(152, 24)
	picker:SetPoint("RIGHT", close, "LEFT", -5, 0)
	local arrow = picker:CreateTexture(nil, "ARTWORK")
	arrow:SetTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
	arrow:SetPoint("RIGHT", -5, 0)
	arrow:SetSize(14, 14)
	local pickerLabel = picker:GetFontString()
	pickerLabel:ClearAllPoints()
	pickerLabel:SetPoint("LEFT", 8, 0)
	pickerLabel:SetPoint("RIGHT", arrow, "LEFT", -3, 0)
	pickerLabel:SetJustifyH("LEFT")
	pickerLabel:SetWordWrap(false)
	picker:SetScript("OnClick", function(self)
		if not MenuUtil or not MenuUtil.CreateContextMenu then return end
		local entries, current = M.GetCharacters()
		MenuUtil.CreateContextMenu(self, function(_, root) M.PopulateCharacterMenu(root, entries, current) end)
	end)
	M.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	local statusY = M.hasAccountBank and -82 or -46
	M.status:SetPoint("TOPLEFT", 18, statusY)
	M.status:SetPoint("TOPRIGHT", -18, statusY)
	M.status:SetJustifyH("LEFT")
	M.status:SetWordWrap(true)
	M.status:SetText(L["bagsOfflineBankEmpty"])
	M.note = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	M.note:SetPoint("BOTTOMLEFT", M.savedAt, "TOPLEFT", 0, 4)
	M.note:SetJustifyH("LEFT")
	M.note:SetWordWrap(true)
	M.characterTab = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	M.characterTab:SetSize(178, 24)
	M.characterTab:SetPoint("TOPLEFT", 18, -46)
	M.characterTab:SetText(BANK)
	M.characterTab:SetScript("OnClick", function() M.SelectContext("characterBank") end)
	if M.hasAccountBank then
		M.accountTab = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
		M.accountTab:SetSize(178, 24)
		M.accountTab:SetPoint("LEFT", M.characterTab, "RIGHT", 8, 0)
		M.accountTab:SetText(ACCOUNT_BANK_PANEL_TITLE or ACCOUNT_BANK_TITLE or BANK)
		M.accountTab:SetScript("OnClick", function() M.SelectContext("accountBank") end)
	end
	if not M.hasAccountBank then M.characterTab:Hide() end
	frame.Divider = frame:CreateTexture(nil, "ARTWORK")
	frame.Divider:SetPoint("TOPLEFT", 18, statusY + 7)
	frame.Divider:SetPoint("TOPRIGHT", -18, statusY + 7)
	frame.Divider:SetHeight(1)
	M.scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
	M.scroll.scrollBarHideable = true
	M.scroll:EnableMouseWheel(true)
	M.scroll:SetClipsChildren(true)
	M.scroll:SetPoint("TOPLEFT", 18, statusY)
	M.scrollTop = -statusY
	M.content = CreateFrame("Frame", nil, M.scroll)
	M.content:SetSize(528, 1)
	M.scroll:SetScrollChild(M.content)
	frame:SetScript("OnHide", function()
		search:ClearFocus()
		search:SetText("")
		GameTooltip:Hide()
	end)
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

function M.SelectCharacter(entry)
	M.characterGUID, M.characterName = entry.guid, entry.label
	M.SelectContext("characterBank")
end

function M.Toggle()
	if not addon.Bags.IsEnabled() then return end
	M.EnsureFrame()
	if M.frame:IsShown() then M.frame:Hide(); return end
	M.characterGUID, M.characterName = nil, nil
	M.contextID = "characterBank"
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
local renderEvents = { GET_ITEM_INFO_RECEIVED = true, DISPLAY_SIZE_CHANGED = true, UI_SCALE_CHANGED = true, PLAYER_LEVEL_UP = true }
if C_EventUtils and C_EventUtils.IsEventValid then
	for _, event in ipairs({ "SKILL_LINES_CHANGED", "TOYS_UPDATED" }) do
		if C_EventUtils.IsEventValid(event) then renderEvents[event] = true end
	end
end
for event in pairs(renderEvents) do M.events:RegisterEvent(event) end
if M.isTBC then M.events:RegisterEvent("PLAYERBANKBAGSLOTS_CHANGED") end
if not M.isTBC then M.events:RegisterEvent("BANK_TABS_CHANGED") end
M.events:SetScript("OnEvent", function(_, event, bagID)
	if event == "BAG_UPDATE" then
		if M.sessionOpen and bagID ~= nil then M.updatedBags[bagID] = true end
		return
	elseif renderEvents[event] then
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
