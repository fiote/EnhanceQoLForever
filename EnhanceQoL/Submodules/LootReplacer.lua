local addonName, addon = ...
local L = LibStub("AceLocale-3.0"):GetLocale(addonName)

local Loot = { enabled = false, rolls = {}, suppressed = {}, receipts = {}, nextReceipt = 0 }
addon.LootReplacer = Loot

local hasAnySecretValues = _G.hasanysecretvalues
local function hasSecretValues(...)
	if hasAnySecretValues then return hasAnySecretValues(...) end
	if not issecretvalue then return false end
	for index = 1, select("#", ...) do
		if issecretvalue((select(index, ...))) then return true end
	end
	return false
end

local receiptFormats = {}
local reputationFormats = {}
local function addReceiptFormat(formats, key, itemArgument)
	local format = _G[key]
	if not format then return end
	local pattern, captures, cursor, argument = { "^" }, {}, 1, 0
	local function addLiteral(text) pattern[#pattern + 1] = text:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1") end
	while true do
		local first, last, position, kind = format:find("%%(%d*)%$?%.?%d*([sdf])", cursor)
		if not first then break end
		addLiteral(format:sub(cursor, first - 1))
		argument = argument + 1
		captures[#captures + 1] = tonumber(position) or argument
		pattern[#pattern + 1] = kind == "d" and "(%d+)" or kind == "f" and "([%d.,]+)" or "(.-)"
		cursor = last + 1
	end
	addLiteral(format:sub(cursor))
	pattern[#pattern + 1] = "$"
	local itemCapture, countCapture
	for index, position in ipairs(captures) do
		if position == itemArgument then itemCapture = index end
		if position == itemArgument + 1 then countCapture = index end
	end
	if itemCapture then
		formats[#formats + 1] = {
			pattern = table.concat(pattern), item = itemCapture, count = countCapture, named = itemArgument > 1,
		}
	end
end

for _, key in ipairs({
	"LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF_MULTIPLE", "LOOT_ITEM_CREATED_SELF_MULTIPLE", "LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE",
	"LOOT_ITEM_SELF", "LOOT_ITEM_PUSHED_SELF", "LOOT_ITEM_CREATED_SELF", "LOOT_ITEM_BONUS_ROLL_SELF",
}) do
	addReceiptFormat(receiptFormats, key, 1)
end
for _, key in ipairs({
	"LOOT_ITEM_MULTIPLE", "LOOT_ITEM_PUSHED_MULTIPLE", "LOOT_ITEM_CREATED_MULTIPLE",
	"LOOT_ITEM", "LOOT_ITEM_PUSHED", "LOOT_ITEM_CREATED",
}) do
	addReceiptFormat(receiptFormats, key, 2)
end
for _, key in ipairs({
	"FACTION_STANDING_INCREASED", "FACTION_STANDING_INCREASED_ACCOUNT_WIDE",
	"FACTION_STANDING_INCREASED_ACH_BONUS", "FACTION_STANDING_INCREASED_ACH_BONUS_ACCOUNT_WIDE",
	"FACTION_STANDING_INCREASED_BONUS", "FACTION_STANDING_INCREASED_DOUBLE_BONUS",
	"FACTION_STANDING_INCREASED_GENERIC", "FACTION_STANDING_INCREASED_GENERIC_ACCOUNT_WIDE",
}) do
	addReceiptFormat(reputationFormats, key, 1)
end

function Loot:CanReceive(category)
	return self.enabled and self.config and self.config.received and self.config[category]
end

function Loot:AddReceipt(receipt, category)
	self.nextReceipt = self.nextReceipt + 1
	receipt.key, receipt.received, receipt.category = self.nextReceipt, true, category
	self.receipts[#self.receipts + 1] = receipt
	if self.preview or #self.receipts > self.config.receivedMaxRows or self.receiptRenderQueued then return end
	self.receiptRenderQueued = true
	RunNextFrame(function()
		self.receiptRenderQueued = nil
		if self.enabled and not self.preview and next(self.receipts) then self:Render() end
	end)
end

function Loot:ReceiveItem(link, count, source)
	if not self:CanReceive("receivedItems") then return end
	if issecretvalue and (issecretvalue(link) or issecretvalue(count)) then return end
	if type(link) ~= "string" then return end
	local item, name = link:match("|H(item:[^|]+)|h%[(.-)%]|h")
	if not item then return end
	count = count or 1
	local now = GetTime()
	for index = #self.receipts, 1, -1 do
		local receipt = self.receipts[index]
		if now - receipt.time > 1 then break end
		if not receipt.paired and receipt.source ~= source and receipt.item == item and receipt.count == count then
			receipt.paired = true
			return
		end
	end

	local _, _, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(item)
	if hasSecretValues(quality) then quality = nil end
	if hasSecretValues(icon) or not icon then
		icon = select(5, C_Item.GetItemInfoInstant(item))
		if hasSecretValues(icon) then icon = nil end
	end
	self:AddReceipt({ item = item, name = name, count = count, quality = quality, icon = icon, time = now, source = source }, "receivedItems")
end

local function playerMoney()
	local amount = GetMoney()
	if issecretvalue and issecretvalue(amount) then return nil end
	return amount
end

function Loot:OnMoneyChanged()
	local previous = self.moneyBalance
	self.moneyBalance = playerMoney()
	if not (self:CanReceive("receivedMoney") and previous and self.moneyBalance) then return end
	local gained = self.moneyBalance - previous
	if gained <= 0 then return end
	self:AddReceipt({
		name = C_CurrencyInfo.GetCoinTextureString(gained, self.config.fontSize),
		icon = C_CurrencyInfo.GetCoinIcon(gained),
		time = GetTime(),
	}, "receivedMoney")
end

function Loot:ReceiveCurrency(currencyID, gained)
	if not self:CanReceive("receivedCurrencies") then return end
	if issecretvalue and (issecretvalue(currencyID) or issecretvalue(gained)) then return end
	if not currencyID or not gained or gained <= 0 then return end
	local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
	if hasSecretValues(info) or not info then return end
	if hasSecretValues(info.name, info.iconFileID, info.quality) or not info.name then return end
	self:AddReceipt({ name = info.name, icon = info.iconFileID, quality = info.quality, count = gained, currency = true, time = GetTime() }, "receivedCurrencies")
end

function Loot:OnReputationMessage(message)
	if not self:CanReceive("receivedReputation") then return end
	if issecretvalue and issecretvalue(message) then return end
	if type(message) ~= "string" then return end
	for _, format in ipairs(reputationFormats) do
		local first, second, third, fourth = message:match(format.pattern)
		if first then
			local values = { first, second, third, fourth }
			local name, count = values[format.item], tonumber(values[format.count])
			if name ~= "" and (not count or count > 0) then
				self:AddReceipt({
					name = name, count = count, reputation = true,
					icon = "Interface\\Icons\\Achievement_Reputation_01", time = GetTime(),
				}, "receivedReputation")
			end
			return
		end
	end
end

function Loot:OnLootMessage(message, guid)
	if issecretvalue and (issecretvalue(message) or issecretvalue(guid)) then return end
	if type(message) ~= "string" then return end
	local playerGUID = UnitGUID("player")
	if issecretvalue and issecretvalue(playerGUID) then return end
	local fromPlayer = playerGUID and guid == playerGUID
	if guid and guid ~= "" and not fromPlayer then return end
	for _, format in ipairs(receiptFormats) do
		if not format.named or fromPlayer then
			local first, second, third = message:match(format.pattern)
			if first then
				local values = { first, second, third }
				self:ReceiveItem(values[format.item], tonumber(values[format.count]), "chat")
				return
			end
		end
	end
end

local function isGamepad()
	local input = _G.InputUtil
	return input and input.IsGamepadUIEnabled and input.IsGamepadUIEnabled()
end

local function isMasterLoot()
	local party = _G.C_PartyInfo
	if party and party.GetLootMethod then
		local method = party.GetLootMethod()
		return hasSecretValues(method) or method == Enum.LootMethod.Masterlooter
	end
	return GetLootMethod and GetLootMethod() == "master"
end

local function quickLootActive()
	return addon.db.autoQuickLoot and (not not IsShiftKeyDown()) == (not not addon.db.autoQuickLootWithShift)
end

local function getSlot(slot)
	local kind = GetLootSlotType(slot)
	if hasSecretValues(kind) then return nil, true end
	if kind == Enum.LootSlotType.None then return end
	local icon, name, count, currencyID, quality, locked = GetLootSlotInfo(slot)
	if hasSecretValues(icon, name, count, currencyID, quality, locked) then return nil, true end
	if currencyID and _G.CurrencyContainerUtil then
		name, icon, count, quality = _G.CurrencyContainerUtil.GetCurrencyContainerInfo(currencyID, count, name, icon, quality)
		if hasSecretValues(icon, name, count, quality) then return nil, true end
	end
	if not name and not icon then return end
	return {
		key = slot, slot = slot, icon = icon, name = name or RETRIEVING_ITEM_INFO, count = count,
		quality = quality, locked = locked, currencyID = currencyID, kind = kind,
	}
end

local function restoreRoll(frame, state)
	frame:SetAlpha(state.alpha)
	for region, mouse in pairs(state.mouse) do
		region:SetMouseClickEnabled(mouse.click)
		region:SetMouseMotionEnabled(mouse.motion)
	end
end

local function rememberMouse(region, state)
	if region.IsForbidden and region:IsForbidden() then return end
	if region.IsMouseClickEnabled and region.IsMouseMotionEnabled and region.SetMouseClickEnabled and region.SetMouseMotionEnabled then
		state[region] = { click = region:IsMouseClickEnabled(), motion = region:IsMouseMotionEnabled() }
	end
	if region.GetChildren then
		for _, child in ipairs({ region:GetChildren() }) do
			rememberMouse(child, state)
		end
	end
end

function Loot:SyncBlizzardRolls(covered)
	for index = 1, 4 do
		local frame = _G["GroupLootFrame" .. index]
		if frame and not (frame.IsForbidden and frame:IsForbidden()) then
			local state = self.suppressed[frame]
			local rollID = frame.rollID
			local shouldSuppress = frame:IsShown() and covered and not hasSecretValues(rollID) and covered[rollID]
			if state and not shouldSuppress then
				restoreRoll(frame, state)
				self.suppressed[frame] = nil
			elseif shouldSuppress and not state then
				state = { alpha = frame:GetAlpha(), mouse = {} }
				rememberMouse(frame, state.mouse)
				if state.mouse[frame] then
					self.suppressed[frame] = state
					frame:SetAlpha(0)
					for region in pairs(state.mouse) do
						region:SetMouseClickEnabled(false)
						region:SetMouseMotionEnabled(false)
					end
				end
			end
		end
	end
end

local function rollData(rollID, previous)
	local icon, name, count, quality, _, need, greed, disenchant, reasonNeed, reasonGreed, reasonDisenchant, _, transmog = GetLootRollItemInfo(rollID)
	if hasSecretValues(icon, name, count, quality, need, greed, disenchant, reasonNeed, reasonGreed, reasonDisenchant, transmog) then return end
	if not name then return end
	if previous and previous.icon == icon and previous.name == name and previous.count == count and previous.quality == quality
		and previous[1] == need and previous[2] == greed and previous[3] == disenchant and previous[4] == transmog
		and previous.reasons[1] == reasonNeed and previous.reasons[2] == reasonGreed and previous.reasons[3] == reasonDisenchant then
		return previous
	end
	return {
		key = rollID, rowKey = "roll:" .. rollID, rollID = rollID, icon = icon, name = name, count = count, quality = quality,
		[0] = true, [1] = need, [2] = greed, [3] = disenchant, [4] = transmog,
		reasons = { [1] = reasonNeed, [2] = reasonGreed, [3] = reasonDisenchant },
	}
end

local function getRollTimeLeft(rollID)
	local remaining = GetLootRollTimeLeft(rollID)
	if not hasSecretValues(remaining) then return remaining end
end

function Loot:Vote(rollID, choice)
	local record = self.rolls[rollID]
	if not self:CanReplaceRolls() or not record or record.submitted or (getRollTimeLeft(rollID) or 0) <= 0 then return end
	local data = rollData(rollID)
	if not data or not data[choice] then return end
	record.submitted = true
	RollOnLoot(rollID, choice)
	self:QueueRollRefresh()
end

function Loot:TrackRoll(rollID, duration)
	if hasSecretValues(rollID) or not rollID or self.rolls[rollID] then return end
	if (hasSecretValues(duration) or duration == nil) and _G.C_Loot and _G.C_Loot.GetLootRollDuration then duration = _G.C_Loot.GetLootRollDuration(rollID) end
	if hasSecretValues(duration) then duration = nil end
	self.rolls[rollID] = {
		duration = duration,
		created = GetTime(),
	}
end

function Loot:ScanRolls()
	if not GetActiveLootRollIDs then return end
	for _, rollID in ipairs(GetActiveLootRollIDs() or {}) do
		self:TrackRoll(rollID)
	end
end

function Loot:CanReplaceRolls()
	return self.enabled and not self.preview and not isGamepad()
end

local function rollConfirmationClosed(rollID)
	local popup = _G.StaticPopup_FindVisible("CONFIRM_LOOT_ROLL", rollID)
	return not popup or popup.data ~= rollID
end

function Loot:RefreshRolls()
	local rows, covered = {}, {}
	if self:CanReplaceRolls() then
		local now = GetTime()
		self.nextRollDetailsCheck = now + 1
		for rollID, record in pairs(self.rolls) do
			local remaining = getRollTimeLeft(rollID)
			if remaining and remaining > 0 then
				if record.confirming and rollConfirmationClosed(rollID) then
					record.confirming = nil
					for _, pendingID in ipairs(GetActiveLootRollIDs and GetActiveLootRollIDs() or {}) do
						if pendingID == rollID and not record.confirmed then record.submitted = nil end
					end
				end
				local data = rollData(rollID, record.lastData)
				if data then
					record.duration = math.max(record.duration or 0, remaining)
					data.remaining, data.duration = remaining, record.duration
					data.submitted, data.result = record.submitted, record.result
					rows[#rows + 1] = data
					covered[rollID] = true
				end
			elseif record.result and record.resultUntil > now then
				local data = rollData(rollID, record.lastData) or record.lastData
				if data then
					data.remaining = 0
					data.submitted, data.result = true, record.result
					rows[#rows + 1] = data
					covered[rollID] = true
				end
			elseif now - record.created > 0.35 then
				self.rolls[rollID] = nil
			end
			if rows[#rows] and rows[#rows].rollID == rollID then record.lastData = rows[#rows] end
		end
		table.sort(rows, function(left, right) return left.rollID < right.rollID end)
	end
	self.rollRows = rows
	self.coveredRolls = covered
	self:Render()
	self:SyncBlizzardRolls(covered)
end

function Loot:TickRolls()
	if self.rollRefreshQueued or not self:CanReplaceRolls() then return false end
	local now = GetTime()
	local checkDetails = now >= (self.nextRollDetailsCheck or 0)
	if checkDetails then self.nextRollDetailsCheck = now + 1 end
	for rollID, record in pairs(self.rolls) do
		local remaining = getRollTimeLeft(rollID)
		local data = self.coveredRolls[rollID] and record.lastData
		if remaining and remaining > 0 then
			if not data or data.remaining == 0 or (record.confirming and rollConfirmationClosed(rollID))
				or (checkDetails and rollData(rollID, data) ~= data) then
				self:RefreshRolls()
				return true
			end
			record.duration = math.max(record.duration or 0, remaining)
			data.remaining, data.duration = remaining, record.duration
			if not data.submitted and (data.timerNeedsTick or checkDetails) then self:UpdateRollTimer(data, now, checkDetails) end
		elseif not (record.result and record.resultUntil > now and data and data.remaining == 0)
			and (data or record.result or now - record.created > 0.35) then
			self:RefreshRolls()
			return true
		end
	end
	self:SyncBlizzardRolls(self.coveredRolls)
	return false
end

function Loot:QueueRollRefresh()
	if self.rollRefreshQueued then return end
	self.rollRefreshQueued = true
	RunNextFrame(function()
		self.rollRefreshQueued = nil
		self:RefreshRolls()
	end)
end

function Loot:RefreshSlots()
	local session = self.session
	if not session then return end
	local count = GetNumLootItems()
	if hasSecretValues(count) then return self:OpenBlizzardLoot(session.autoLoot, session.fromItem) end
	local rows = {}
	for slot = 1, count do
		if not session.cleared[slot] then
			local data, restricted = getSlot(slot)
			if restricted then return self:OpenBlizzardLoot(session.autoLoot, session.fromItem) end
			if data then
				data.session = session
				rows[#rows + 1] = data
			end
		end
	end
	self.lootRows = rows
	self:Render()
end

function Loot:CanLoot(data)
	return data and self.session and self.session == data.session and not self.session.cleared[data.slot]
end

function Loot:ClickSlot(data)
	if not self:CanLoot(data) then return end
	if IsModifiedClick() then
		local link = GetLootSlotLink(data.slot)
		if not hasSecretValues(link) and link then HandleModifiedItemClick(link) end
	else
		local current = getSlot(data.slot)
		if current and not current.locked then LootSlot(data.slot) end
	end
end

function Loot:LootAll()
	local session = self.session
	for _, data in ipairs(self.lootRows) do
		if self.session ~= session then return end
		local current = self:CanLoot(data) and getSlot(data.slot)
		if current and not current.locked then
			LootSlot(data.slot)
			if _G.StaticPopup_FindVisible("LOOT_BIND") then return end
		end
	end
end

function Loot:CloseSession()
	if not self.session then return end
	self.session = nil
	self.lootRows = {}
	StaticPopup_Hide("LOOT_BIND")
	self:Render()
	self:SyncLootRegistration()
end

function Loot:SyncLootRegistration()
	local frame = _G.LootFrame
	if not frame or (frame.IsForbidden and frame:IsForbidden()) then return end
	local want = self.enabled and not self.preview and not isGamepad() and not isMasterLoot()
	-- The stock frame keeps handling its current slots and close animation.
	if want and not self.ownsLootOpen and frame:IsEventRegistered("LOOT_OPENED") then
		frame:UnregisterEvent("LOOT_OPENED")
		self.ownsLootOpen = true
	elseif not want and self.ownsLootOpen and not self.session then
		frame:RegisterEvent("LOOT_OPENED")
		self.ownsLootOpen = nil
	end
end

function Loot:OpenBlizzardLoot(autoLoot, fromItem)
	if self.session then
		self.session = nil
		self.lootRows = {}
		self:Render()
	end
	local frame = _G.LootFrame
	if not frame or (frame.IsForbidden and frame:IsForbidden()) then return end
	local handler = frame:GetScript("OnEvent")
	if handler then securecallfunction(handler, frame, "LOOT_OPENED", autoLoot, fromItem) end
end

function Loot:Open(autoLoot, fromItem)
	if not self.ownsLootOpen then return end
	if hasSecretValues(autoLoot, fromItem) then return self:OpenBlizzardLoot(false, false) end
	if not self.enabled or self.preview or isGamepad() or isMasterLoot() then
		return self:OpenBlizzardLoot(autoLoot, fromItem)
	end

	local session = { cleared = {}, pending = autoLoot or quickLootActive(), autoLoot = autoLoot, fromItem = fromItem }
	self.session = session
	self.lootRows = {}
	if session.pending then
		self:Render()
		C_Timer.After(0.15, function()
			if self.session ~= session then return end
			session.pending = nil
			self:RefreshSlots()
		end)
	else
		self:RefreshSlots()
	end
end

function Loot:OnEvent(event, ...)
	local first, second = ...
	if event == "CHAT_MSG_LOOT" then
		if self:CanReceive("receivedItems") then self:OnLootMessage(first, select(12, ...)) end
	elseif event == "QUEST_LOOT_RECEIVED" then
		self:ReceiveItem(second, select(3, ...), "quest")
	elseif event == "QUEST_TURNED_IN" then
		if not self:CanReceive("receivedQuestXP") then return end
		if (issecretvalue and issecretvalue(second)) or type(second) ~= "number" or second <= 0 then return end
		self:AddReceipt({ name = "+" .. BreakUpLargeNumbers(second), icon = "Interface\\Icons\\XP_Icon", time = GetTime() }, "receivedQuestXP")
	elseif event == "PLAYER_MONEY" then
		self:OnMoneyChanged()
	elseif event == "CURRENCY_DISPLAY_UPDATE" then
		self:ReceiveCurrency(first, select(3, ...))
	elseif event == "CHAT_MSG_COMBAT_FACTION_CHANGE" then
		self:OnReputationMessage(first)
	elseif event == "LOOT_OPENED" then
		self:Open(first, second)
	elseif event == "LOOT_CLOSED" then
		self:CloseSession()
		self:SyncLootRegistration()
	elseif event == "LOOT_SLOT_CLEARED" or event == "LOOT_SLOT_CHANGED" then
		if not self.session then return end
		if hasSecretValues(first) then return self:OpenBlizzardLoot(self.session.autoLoot, self.session.fromItem) end
		self.session.cleared[first] = event == "LOOT_SLOT_CLEARED" or nil
		if not self.session.pending then self:RefreshSlots() end
	elseif event == "START_LOOT_ROLL" then
		self:TrackRoll(first, second)
		self:QueueRollRefresh()
	elseif event == "CONFIRM_LOOT_ROLL" or event == "CONFIRM_DISENCHANT_ROLL" then
		if hasSecretValues(first) then return end
		local record = self.rolls[first]
		if record and record.submitted then record.confirming = true end
	elseif event == "MAIN_SPEC_NEED_ROLL" then
		if hasSecretValues(first, second) then return end
		local record = self.rolls[first]
		if record then
			record.result = second
			record.submitted = true
			record.resultUntil = GetTime() + 3
			self:QueueRollRefresh()
		end
	elseif event == "CANCEL_LOOT_ROLL" then
		if hasSecretValues(first) then return end
		self.rolls[first] = nil
		self:QueueRollRefresh()
	elseif event == "CANCEL_ALL_LOOT_ROLLS" or event == "PLAYER_LEAVING_WORLD" then
		wipe(self.rolls)
		if event == "PLAYER_LEAVING_WORLD" then
			self.moneyBalance = nil
			wipe(self.receipts)
			self:CloseSession()
		end
		self:RefreshRolls()
	elseif event == "GAME_PAD_ACTIVE_CHANGED" or event == "PARTY_LOOT_METHOD_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
		if event == "PLAYER_ENTERING_WORLD" then self.moneyBalance = playerMoney() end
		self:SyncLootRegistration()
		self:ScanRolls()
		self:QueueRollRefresh()
	end
end

local events = {
	"LOOT_OPENED", "LOOT_CLOSED", "LOOT_SLOT_CLEARED", "LOOT_SLOT_CHANGED",
	"CHAT_MSG_LOOT", "QUEST_LOOT_RECEIVED", "QUEST_TURNED_IN", "PLAYER_MONEY", "CURRENCY_DISPLAY_UPDATE", "CHAT_MSG_COMBAT_FACTION_CHANGE",
	"START_LOOT_ROLL", "CANCEL_LOOT_ROLL", "CANCEL_ALL_LOOT_ROLLS", "CONFIRM_LOOT_ROLL", "CONFIRM_DISENCHANT_ROLL", "MAIN_SPEC_NEED_ROLL",
	"GAME_PAD_ACTIVE_CHANGED", "PARTY_LOOT_METHOD_CHANGED", "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD",
}

local function createEventFrame()
	local frame = CreateFrame("Frame")
	frame:SetScript("OnEvent", function(self, event, ...)
		Loot:OnEvent(event, ...)
		if not Loot.enabled and not Loot.session then self:UnregisterAllEvents() end
	end)
	return frame
end

function Loot:SetEnabled(enabled)
	enabled = enabled == true
	if self.enabled == enabled then return end
	self.enabled = enabled
	if enabled then
		self.events = self.events or createEventFrame()
		self:InitializeDisplay()
		if not self.rollConfirmationHooked and _G.ConfirmLootRoll then
			hooksecurefunc("ConfirmLootRoll", function(rollID)
				if not self.enabled or hasSecretValues(rollID) then return end
				local record = self.rolls[rollID]
				if record and record.confirming then record.confirmed = true end
			end)
			self.rollConfirmationHooked = true
		end
		self.events:Show()
		self.moneyBalance = playerMoney()
		for _, event in ipairs(events) do self.events:RegisterEvent(event) end
		self:ScanRolls()
	else
		self.preview = nil
		self.moneyBalance = nil
		wipe(self.rolls)
		wipe(self.receipts)
		self.events:Hide()
		self.events:UnregisterAllEvents()
		if self.session then
			self.events:RegisterEvent("LOOT_CLOSED")
			self.events:RegisterEvent("LOOT_SLOT_CLEARED")
			self.events:RegisterEvent("LOOT_SLOT_CHANGED")
		end
	end
	self:SyncLootRegistration()
	self:RefreshRolls()
	if self.display then
		addon.EditMode:RefreshFrame(self.editModeID)
		if enabled and addon.EditMode:IsInEditMode() and addon.EditMode:IsFrameVisibleInEditMode(self.editModeID) then
			self:SetPreview(not self.session)
		end
	end
end
