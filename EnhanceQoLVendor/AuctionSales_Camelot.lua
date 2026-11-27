local addon = _G.EnhanceQoL
if not addon.variables.isForever or addon.variables.isTBC then return end

local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL")
local AH = C_AuctionHouse
local Sales = { live = {}, bags = {}, watchQueue = {}, watchResults = {}, watchRetries = {}, alerts = {}, sorts = {}, filters = {} }
addon.Vendor.AuctionSales = Sales

local liveLifetime = 60
local savedLifetime = 7 * 24 * 60 * 60
local fullScanCooldown = 15 * 60
local fullScanTimeout = 60
local historyDaySeconds = 24 * 60 * 60
local historyDays = 30
local marketPageSize = 50
local rowHeight = 36
local dateFormats = { dayFirst = "%d.%m. %H:%M", monthFirst = "%m/%d %H:%M", iso = "%Y-%m-%d %H:%M" }
local sorts = { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } }
local searchEvents = { "COMMODITY_SEARCH_RESULTS_UPDATED", "COMMODITY_SEARCH_RESULTS_ADDED", "ITEM_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_ADDED" }
local browseEvents = { "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_ADDED", "AUCTION_HOUSE_BROWSE_FAILURE" }
local quickEvents = { "AUCTION_HOUSE_AUCTION_CREATED", "AUCTION_HOUSE_SHOW_ERROR", "AUCTION_HOUSE_POST_ERROR", "PLAYER_REGEN_DISABLED" }
local bagEvents = { "BAG_UPDATE_DELAYED", "ITEM_LOCK_CHANGED" }

function Sales:IsEnabled()
	return addon.db and addon.db.vendorAuctionSales == true
end

local function refreshBagValue()
	local bags = addon.Bags
	if bags and bags.functions and bags.functions.RefreshAuctionValue then bags.functions.RefreshAuctionValue() end
end

local function priceKey(key)
	return ("%d:%d:%d:%d"):format(key.itemID, key.itemLevel or 0, key.itemSuffix or 0, key.battlePetSpeciesID or 0)
end

local regionCodes = { "US", "KR", "EU", "TW", "CN" }
local function marketScope()
	local region = _G.GetCurrentRegion and regionCodes[_G.GetCurrentRegion()]
	if not region and _G.GetCurrentRegionName then
		local name = _G.GetCurrentRegionName()
		for _, code in ipairs(regionCodes) do
			if name == code then region = code break end
		end
	end
	local rules, active = Enum.GameRule, C_GameRules and C_GameRules.IsGameRuleActive
	if not region or not active or not rules or not rules.HardcoreRuleset or not rules.RPRuleset or not rules.PvPRuleset then return end
	if active(rules.HardcoreRuleset) then return region .. ":Hardcore" end
	local rp, pvp = active(rules.RPRuleset), active(rules.PvPRuleset)
	if rp then return region .. (pvp and ":RP-PvP" or ":RP") end
	return region .. (pvp and ":PvP" or ":PvE")
end

local function marketForSide(side)
	local scope = side and marketScope()
	if scope then return scope .. ":" .. side end
end

local function marketKey()
	if not UnitExists("npc") then return end
	local faction = UnitFactionGroup("player")
	local auctioneerFaction = UnitFactionGroup("npc")
	if faction ~= "Alliance" and faction ~= "Horde" then return end
	if auctioneerFaction == faction then return marketForSide(faction) end
	if auctioneerFaction == "Neutral" then return marketForSide("Neutral") end
	if auctioneerFaction == "Alliance" or auctioneerFaction == "Horde" then return end
	if C_PvP.GetZonePVPInfo() == "friendly" then return marketForSide(faction) end
	return marketForSide("Neutral")
end

local function vendorDB()
	local db = _G.EnhanceQoLVendorDB
	if type(db) ~= "table" then
		db = {}
		_G.EnhanceQoLVendorDB = db
	end
	return db
end

local function watchList(create)
	local db = create and vendorDB() or _G.EnhanceQoLVendorDB
	if type(db) ~= "table" then return end
	if create and type(db.auctionWatch) ~= "table" then db.auctionWatch = {} end
	return type(db.auctionWatch) == "table" and db.auctionWatch or nil
end

local function excludedItems(create)
	local db = create and vendorDB() or _G.EnhanceQoLVendorDB
	if type(db) ~= "table" then return end
	if create and type(db.auctionExcluded) ~= "table" then db.auctionExcluded = {} end
	return type(db.auctionExcluded) == "table" and db.auctionExcluded or nil
end

local function isExcluded(itemID)
	local list = excludedItems()
	return list and list[itemID] ~= nil
end

local function coinText(value)
	return C_CurrencyInfo.GetCoinTextureString(value, 12)
end

local function historyMoney(price)
	return price and coinText(math.floor(price + 0.5)) or "—"
end

function Sales:FormatVendorDelta(delta, formatMoney)
	local amount = (formatMoney or coinText)(math.abs(delta))
	if delta > 0 then return "+" .. amount, 0.42, 0.92, 0.53 end
	if delta < 0 then return "−" .. amount, 1, 0.45, 0.45 end
	return amount, 0.8, 0.83, 0.88
end

function Sales:FormatPriceDate(at)
	local format = dateFormats[addon.db.vendorAuctionDateFormat]
	if not format then
		local locale = GetLocale()
		local region = _G.GetCurrentRegionName and _G.GetCurrentRegionName()
		local monthFirst = region ~= "EU" and (locale == "enUS" or locale == "koKR" or locale == "zhCN" or locale == "zhTW")
		format = monthFirst and dateFormats.monthFirst or dateFormats.dayFirst
	end
	return date(format, at)
end

local function savedPrices(create)
	local db = create and vendorDB() or _G.EnhanceQoLVendorDB
	if type(db) ~= "table" then return end
	if create and type(db.auctionPrices) ~= "table" then db.auctionPrices = {} end
	return type(db.auctionPrices) == "table" and db.auctionPrices or nil
end

local function readQuote(quotes, key, maxAge)
	local quote = type(quotes) == "table" and quotes[key]
	if type(quote) ~= "table" or type(quote.price) ~= "number" or type(quote.time) ~= "number" then return end
	local age = GetServerTime() - quote.time
	if age < 0 or age >= maxAge or quote.price <= 0 then return end
	return quote.price, quote.time
end

-- Quotes use copper per unit and an epoch timestamp. An explicit market can be used away from an auctioneer.
function Sales:GetSavedPrice(itemKey, market)
	if not self:IsEnabled() or not itemKey then return end
	local prices = savedPrices()
	market = market or self.market
	if prices and market then return readQuote(prices[market], priceKey(itemKey), savedLifetime) end
end

function Sales:GetMarket() return self.market end

local function prunePrices()
	local prices = savedPrices()
	if not prices then return end
	for market, quotes in pairs(prices) do
		if type(quotes) == "table" then
			for key in pairs(quotes) do
				if not readQuote(quotes, key, savedLifetime) then quotes[key] = nil end
			end
		end
		if type(quotes) ~= "table" or not next(quotes) then prices[market] = nil end
	end
end

local function auctioneerID()
	local guid = UnitGUID("npc")
	if not guid or (issecretvalue and issecretvalue(guid)) then return end
	return guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
end

function Sales:GetConfirmedMarketSide()
	local faction = UnitFactionGroup("player")
	if faction ~= "Alliance" and faction ~= "Horde" then return end
	local side = UnitFactionGroup("npc")
	if side == faction or side == "Neutral" then return side end
	if side == "Alliance" or side == "Horde" then return end
	local db = _G.EnhanceQoLVendorDB
	local names = db and db.auctioneerMarkets
	local confirmed = self.confirmedMarketSide or (names and names[auctioneerID()])
	if confirmed == faction or confirmed == "Neutral" then return confirmed end
end

local function marketLabel(side)
	if side == "Neutral" then return L["vendorAuctionNeutral"] end
	return _G["FACTION_" .. side:upper()] or side
end

local function snapshots(create)
	local db = create and vendorDB() or _G.EnhanceQoLVendorDB
	if type(db) ~= "table" then return end
	if create and type(db.auctionSnapshots) ~= "table" then db.auctionSnapshots = {} end
	return type(db.auctionSnapshots) == "table" and db.auctionSnapshots or nil
end

local function scannedItemNames(create)
	local db = create and vendorDB() or _G.EnhanceQoLVendorDB
	if type(db) ~= "table" then return end
	local locale = GetLocale()
	local index = db.auctionItemNames
	if type(index) ~= "table" or index.locale ~= locale or type(index.items) ~= "table" then
		if not create then return end
		index = { locale = locale, items = {} }
		db.auctionItemNames = index
	end
	return index.items
end

local function usableItemName(name)
	return (not issecretvalue or not issecretvalue(name)) and type(name) == "string" and name ~= ""
end

local function cachedItemName(itemID)
	if not C_Item or not C_Item.GetItemNameByID then return end
	if C_Item.IsItemDataCachedByID and not C_Item.IsItemDataCachedByID(itemID) then return end
	return C_Item.GetItemNameByID(itemID)
end

local function itemQuality(value)
	if (not issecretvalue or not issecretvalue(value)) and type(value) == "number" and value >= 0 and value <= 8 and value % 1 == 0 then return value end
end

local function cachedItemQuality(itemID)
	if not C_Item or not C_Item.GetItemQualityByID then return end
	if C_Item.IsItemDataCachedByID and not C_Item.IsItemDataCachedByID(itemID) then return end
	return itemQuality(C_Item.GetItemQualityByID(itemID))
end

function Sales:QueueItemQualities(items)
	if not C_Item or not C_Item.RequestLoadItemDataByID then return end
	local requested = self.requestedQualities or {}
	self.requestedQualities = requested
	local queue = self.qualityQueue or {}
	for itemID in pairs(items) do
		if not requested[itemID] then
			requested[itemID] = true
			queue[#queue + 1] = itemID
		end
	end
	if #queue == 0 or self.qualityQueue then return end
	self.qualityQueue = queue
	local index = 1
	local function step()
		if self.qualityQueue ~= queue then return end
		local last = math.min(index + 39, #queue)
		while index <= last do
			local itemID = queue[index]
			if cachedItemQuality(itemID) ~= nil then
				self:OnMarketItemData(itemID, true)
			else
				C_Item.RequestLoadItemDataByID(itemID)
			end
			index = index + 1
		end
		if index <= #queue then
			C_Timer.After(0.2, step)
		else
			self.qualityQueue = nil
		end
	end
	C_Timer.After(0, step)
end

local function historyDay(at)
	return math.floor(at / historyDaySeconds)
end

local function median(samples)
	table.sort(samples)
	local middle = math.floor(#samples / 2)
	if #samples % 2 == 1 then return samples[middle + 1] end
	return (samples[middle] + samples[middle + 1]) / 2
end

local function auctionHistory(create)
	local db = create and vendorDB() or _G.EnhanceQoLVendorDB
	if type(db) ~= "table" then return end
	if create and not db.auctionHistory then db.auctionHistory = {} end
	return db.auctionHistory
end

local function migrateMarketKeys()
	local markets = { snapshots() or {}, auctionHistory() or {}, savedPrices() or {} }
	local sources = {}
	for _, entries in ipairs(markets) do
		for key in pairs(entries) do
			local region, ruleset, side = key:match("^CAMWOW([A-Z]+)%d+Realm%d+([%a%-]+):(%a+)$")
			if (ruleset == "PvE" or ruleset == "PvP" or ruleset == "RP" or ruleset == "RP-PvP" or ruleset == "Hardcore")
				and (side == "Alliance" or side == "Horde" or side == "Neutral") then
				for _, code in ipairs(regionCodes) do
					if region == code then
						local target = code .. ":" .. ruleset .. ":" .. side
						if sources[target] == nil then
							sources[target] = key
						elseif sources[target] ~= key then
							sources[target] = false
						end
						break
					end
				end
			end
		end
	end
	-- Retain old market entries when the destination already has its own data or the old key is ambiguous.
	for target, source in pairs(sources) do
		if source then
			for _, entries in ipairs(markets) do
				if entries[target] == nil then
					entries[target] = entries[source]
					entries[source] = nil
				end
			end
		end
	end
end

local function pruneAuctionHistory(today)
	local history = auctionHistory()
	if not history then return end
	for market, days in pairs(history) do
		for day, entry in pairs(days) do
			if day <= today - historyDays then
				days[day] = nil
			elseif day < today and not entry.finalized then
				-- A single observation stays scalar. Multiple observations become a median and count.
				for itemID, samples in pairs(entry.items) do
					if type(samples) == "table" then entry.items[itemID] = { median(samples), #samples } end
				end
				entry.finalized = true
			end
		end
		if not next(days) then history[market] = nil end
	end
end

local function recordHistoryScan(days, snapshot)
	local day = historyDay(snapshot.time)
	local entry = days[day]
	if entry and entry.finalized then return end
	if not entry then
		entry = { items = {} }
		days[day] = entry
	end
	for itemID, result in pairs(snapshot.items) do
		local price = result[1]
		if price and price > 0 then
			local samples = entry.items[itemID]
			if type(samples) == "table" then
				samples[#samples + 1] = price
			elseif samples then
				entry.items[itemID] = { samples, price }
			else
				entry.items[itemID] = price
			end
		end
	end
end

local function summarizeHistory(itemID, market, today, range, points)
	local history, saved = auctionHistory(), snapshots()
	local days = history and history[market]
	local snapshot = saved and saved[market]
	local latest = snapshot and snapshot.items[itemID]
	local latestPrice = latest and latest[1]
	local snapshotDay = snapshot and historyDay(snapshot.time)
	local sum, observed = 0, 0
	for day = today - range + 1, today do
		local entry = days and days[day]
		local price = entry and entry.items[itemID]
		if not days and day == snapshotDay then price = latestPrice end
		local scans = 1
		if type(price) == "table" then
			scans = entry.finalized and price[2] or #price
			price = entry.finalized and price[1] or median(price)
		end
		if price then
			if points then points[#points + 1] = { day = day, price = price, scans = scans } end
			if day > today - 7 then
				sum = sum + price
				observed = observed + 1
			end
		end
	end
	return observed > 0 and sum / observed or nil, observed, latestPrice, snapshot and snapshot.time
end

function Sales:GetPriceHistory(itemID, market, range)
	local today = historyDay(GetServerTime())
	local points = {}
	local average, observed, latest, scannedAt = summarizeHistory(itemID, market, today, range, points)
	return { today = today, latest = latest, scannedAt = scannedAt, points = points, observed = observed, average = average }
end

function Sales:GetFullScanCooldown()
	local db = _G.EnhanceQoLVendorDB
	local latest = math.max(self.lastReplicateAt or 0, db and db.auctionReplicateAt or 0)
	if latest <= 0 then return 0 end
	local age = GetServerTime() - latest
	return age >= 0 and math.max(0, fullScanCooldown - age) or 0
end

function Sales:RecordFullScanResponse()
	self.lastReplicateAt = GetServerTime()
	vendorDB().auctionReplicateAt = self.lastReplicateAt
end

local function cooldownText(seconds)
	return L["vendorAuctionScanCooldown"]:format(math.floor(seconds / 60), seconds % 60)
end

-- Full scans index the minimum buyout and available units by base item ID.
function Sales:GetSnapshotPrice(itemID, neutral)
	if not self:IsEnabled() then return end
	local faction = UnitFactionGroup("player")
	if faction ~= "Alliance" and faction ~= "Horde" then return end
	local db = snapshots()
	local snapshot = db and db[marketForSide(neutral and "Neutral" or faction)]
	local value = snapshot and snapshot.items[itemID]
	if value then return value[1], snapshot.time, value[2] end
end

local function factionMarket()
	local faction = UnitFactionGroup("player")
	if faction == "Alliance" or faction == "Horde" then return marketForSide(faction), faction end
end

local function storedListingPrice(key, market)
	if not market or not Sales:IsEnabled() then return end
	local price, at = Sales:GetSavedPrice(key, market)
	local db = snapshots()
	local snapshot = db and db[market]
	if snapshot and (not at or snapshot.time >= at) then
		local scanned = snapshot.items[key.itemID]
		if scanned and scanned[1] then return scanned[1], snapshot.time, "snapshot" end
		return
	end
	return price, at, "saved"
end

function Sales:GetListingPrice(key)
	local live = readQuote(self.live, priceKey(key), liveLifetime)
	if live then return live, nil, "live" end
	return storedListingPrice(key, self.market or (not self.open and factionMarket()))
end

local function addHistoryTooltip(tooltip, itemID)
	local market, side = factionMarket()
	if not market then return end
	local today = historyDay(GetServerTime())
	local function addMarket(key, marketSide)
		local average, observed = summarizeHistory(itemID, key, today, 7)
		if average then
			local text = L["vendorAuctionHistoryTooltipLine"]:format(marketLabel(marketSide), observed)
			tooltip:AddDoubleLine(text, historyMoney(average), 0.65, 0.72, 0.81, 0.90, 0.94, 1)
		end
	end
	addMarket(market, side)
	addMarket(marketForSide("Neutral"), "Neutral")
end

function Sales:RegisterSnapshotTooltip()
	if self.snapshotTooltipRegistered or not TooltipDataProcessor or not TooltipDataProcessor.AddTooltipPostCall then return end
	self.snapshotTooltipRegistered = true
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
		if not self:IsEnabled() then return end
		if tooltip ~= GameTooltip or not data or (tooltip.IsForbidden and tooltip:IsForbidden()) then return end
		local id = data.id
		if (issecretvalue and issecretvalue(id)) or type(id) ~= "number" then return end
		if addon.db.vendorAuctionHistoryTooltip then addHistoryTooltip(tooltip, id) end
		if addon.db.vendorAuctionPriceTooltip == false then return end
		local price, at = self:GetSnapshotPrice(id)
		local neutral, neutralAt = self:GetSnapshotPrice(id, true)
		if not price and not neutral then return end

		local info = tooltip.GetProcessingTooltipInfo and tooltip:GetProcessingTooltipInfo()
		local count
		if info and info == tooltip:GetPrimaryTooltipInfo() and info.getterName == "GetBagItem" and not info.append and info.getterArgs then
			local bag, slot = info.getterArgs[1], info.getterArgs[2]
			if (not issecretvalue or (not issecretvalue(bag) and not issecretvalue(slot))) and type(bag) == "number" and type(slot) == "number" then
				local item = C_Container.GetContainerItemInfo(bag, slot)
				if item and (not issecretvalue or not issecretvalue(item.itemID)) and item.itemID == id then count = item.stackCount end
			end
		end
		if (issecretvalue and issecretvalue(count)) or type(count) ~= "number" or count < 2 then count = 1 end
		local function addStackAndDelta(unitPrice)
			if count > 1 then
				tooltip:AddDoubleLine(L["vendorAuctionSnapshotStack"]:format(count), coinText(unitPrice * count), 0.65, 0.72, 0.81, 0.90, 0.94, 1)
			end
			local vendorPrice = select(11, C_Item.GetItemInfo(id))
			if (issecretvalue and issecretvalue(vendorPrice)) or type(vendorPrice) ~= "number" or vendorPrice <= 0 then return end
			local amount, r, g, b = self:FormatVendorDelta((unitPrice - vendorPrice) * count)
			tooltip:AddDoubleLine(L["vendorAuctionBagValueDelta"], amount, 0.65, 0.72, 0.81, r, g, b)
		end
		if price then
			tooltip:AddDoubleLine(L["vendorAuctionSnapshotPrice"]:format(self:FormatPriceDate(at)), coinText(price), 0.65, 0.72, 0.81, 0.90, 0.94, 1)
			addStackAndDelta(price)
		end
		if neutral then
			local label = marketLabel("Neutral") .. " · " .. self:FormatPriceDate(neutralAt)
			tooltip:AddDoubleLine(label, coinText(neutral), 0.65, 0.72, 0.81, 0.90, 0.94, 1)
			if not price then addStackAndDelta(neutral) end
		end
	end)
end

function Sales:ShowScanTooltip(button)
	GameTooltip:SetOwner(button, "ANCHOR_TOPRIGHT")
	GameTooltip:SetText(L["vendorAuctionScan"])
	GameTooltip:AddLine(L["vendorAuctionScanTooltip"], 1, 1, 1, true)
	if self.fullScan then
		GameTooltip:AddLine(marketLabel(self.fullScan.side) .. " · " .. (button.scanStatus or L["vendorAuctionScanWaiting"]), 0.48, 0.76, 0.96)
	else
		local wait = self:GetFullScanCooldown()
		if wait > 0 then GameTooltip:AddLine(cooldownText(wait), 1, 0.71, 0.44, true) end
	end
	local saved = snapshots()
	local faction = UnitFactionGroup("player")
	if saved and (faction == "Alliance" or faction == "Horde") then
		for _, side in ipairs({ faction, "Neutral" }) do
			local snapshot = saved[marketForSide(side)]
			if snapshot and snapshot.time then
				GameTooltip:AddLine(L["vendorAuctionScanSavedAt"]:format(marketLabel(side), self:FormatPriceDate(snapshot.time)), 0.65, 0.72, 0.81)
			end
		end
	end
	GameTooltip:Show()
end

local function updateCooldownButton(button, elapsed)
	button.cooldownElapsed = (button.cooldownElapsed or 0) + elapsed
	if button.cooldownElapsed < 1 then return end
	button.cooldownElapsed = button.cooldownElapsed % 1
	Sales:UpdateScanDisplay()
end

function Sales:UpdateScanDisplay()
	local panel = self.panel
	if not panel or not panel.scanButton then return end
	local button, bar = panel.scanButton, panel.scanBar
	button:SetShown(self.open == true)
	if not self.open then
		button:SetScript("OnUpdate", nil)
		bar:Hide()
		return
	end
	local scan = self.fullScan
	if scan then
		button:SetScript("OnUpdate", nil)
		local percent = scan.percent
		local progress = scan.browse and scan.started and L["vendorAuctionScanBrowseProgress"]:format(scan.count)
		button.scanStatus = progress or (percent and L["vendorAuctionScanProgress"]:format(percent)) or L["vendorAuctionScanWaiting"]
		bar:SetValue(percent or 0)
		bar.pulse:SetShown(percent == nil)
		bar:Show()
	else
		local wait = self:GetFullScanCooldown()
		button.scanStatus = nil
		button:SetScript("OnUpdate", wait > 0 and updateCooldownButton or nil)
		bar:Hide()
	end
	if panel:IsShown() and GameTooltip:IsOwned(button) then self:ShowScanTooltip(button) end
end

function Sales:StopFullScan(message)
	if self.fullScan and self.fullScan.ticker then self.fullScan.ticker:Cancel() end
	self.fullScan = nil
	self:UpdateScanDisplay()
	if message then print(message) end
end

function Sales:ObserveFullScanRequest()
	if self.open then self.foreignScanPendingUntil = GetTime() + fullScanTimeout end
end

function Sales:FinishFullScan(scan, items, entries, distinct)
	local snapshot = { time = GetServerTime(), items = items }
	if scan.browse then snapshot.browseResults = entries else snapshot.listings = entries end
	local saved, history = snapshots(true), auctionHistory(true)
	local previous = saved[scan.market]
	local days = history[scan.market]
	if not days then
		days = {}
		history[scan.market] = days
		if previous and previous.time <= snapshot.time and historyDay(previous.time) > historyDay(snapshot.time) - historyDays then
			recordHistoryScan(days, previous)
		end
	end
	recordHistoryScan(days, snapshot)
	pruneAuctionHistory(historyDay(snapshot.time))
	saved[scan.market] = snapshot
	local names, missingQualities = scannedItemNames(true), {}
	for itemID, result in pairs(items) do
		if not names[itemID] then
			local name = cachedItemName(itemID)
			if not usableItemName(name) then name = scan.names and scan.names[itemID] end
			if usableItemName(name) then names[itemID] = name end
		end
		local old = previous and previous.items[itemID]
		result.quality = result.quality or (scan.qualities and scan.qualities[itemID]) or cachedItemQuality(itemID) or (old and old.quality)
		if result.quality == nil then missingQualities[itemID] = true end
	end
	self.marketCatalog = nil
	self:QueueItemQualities(missingQualities)
	if self.market ~= scan.market then
		self.market = scan.market
		self.search = nil
		self.watchSearch = nil
		wipe(self.live)
		wipe(self.alerts)
	end
	self:StopFullScan(not scan.passive and L["vendorAuctionScanDone"]:format(marketLabel(scan.side), distinct) or nil)
	refreshBagValue()
	wipe(self.watchResults)
	self:QueueWatchList()
	self:Refresh(true)
end

function Sales:StartBrowseScan(side, market, passive)
	local scan = { browse = true, side = side, market = market, passive = passive, results = {}, qualities = {}, count = 0, deadline = GetTime() + fullScanTimeout }
	self.fullScan = scan
	scan.ticker = C_Timer.NewTicker(0.2, function()
		if self.fullScan ~= scan then return end
		if GetTime() >= scan.deadline then
			self:StopFullScan(not passive and L["vendorAuctionScanNoReply"] or nil)
		elseif scan.requestMore and AH.IsThrottledMessageSystemReady() then
			scan.requestMore = nil
			AH.RequestMoreBrowseResults()
		end
	end)
	self:UpdateScanDisplay()
	return scan
end

function Sales:InterruptBrowseScan()
	local scan = self.fullScan
	if scan and scan.browse then self:StopFullScan(not scan.passive and L["vendorAuctionScanFailed"] or nil) end
end

function Sales:ObserveBrowseQuery(query)
	if self.sendingBrowse then return end
	self:InterruptBrowseScan()
	if not self:IsEnabled() or not self.open or self.fullScan or type(query) ~= "table" or query.searchString ~= "" then return end
	if (query.minLevel and query.minLevel ~= 0) or (query.maxLevel and query.maxLevel ~= 0)
		or (query.filters and next(query.filters)) or (query.itemClassFilters and next(query.itemClassFilters))
		or (query.sorts and next(query.sorts)) then return end
	local side = self:GetConfirmedMarketSide()
	local market = marketForSide(side)
	if market then self:StartBrowseScan(side, market, true) end
end

function Sales:ReadBrowseResults(event, added)
	local scan = self.fullScan
	if not scan or not scan.browse then return end
	if not self:IsEnabled() or not self.open or not AuctionHouseFrame:IsShown() then self:StopFullScan() return end
	if event == "AUCTION_HOUSE_BROWSE_FAILURE" then self:InterruptBrowseScan() return end
	local results
	local first = not scan.started
	if event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then
		scan.started = true
		results = AH.GetBrowseResults()
	elseif scan.started then
		results = added
	end
	if not results then return end
	local before = scan.count
	for _, result in ipairs(results) do
		local key, price, quantity = result.itemKey, result.minPrice, result.totalQuantity
		if not key or not key.itemID or key.itemID <= 0 or type(price) ~= "number" or type(quantity) ~= "number" then
			self:StopFullScan(not scan.passive and L["vendorAuctionScanIncomplete"] or nil)
			return
		end
		local id = priceKey(key)
		if not scan.results[id] then scan.count = scan.count + 1 end
		scan.results[id] = { itemID = key.itemID, price = price, quantity = quantity }
		if scan.qualities[key.itemID] == nil and AH.GetItemKeyInfo then
			local info = AH.GetItemKeyInfo(key)
			scan.qualities[key.itemID] = itemQuality(info and info.quality) or false
		end
	end
	if not AH.HasFullBrowseResults() then
		if first or scan.count ~= before then
			scan.deadline = GetTime() + fullScanTimeout
			scan.requestMore = not scan.passive
			self:UpdateScanDisplay()
		end
		return
	end
	local items, distinct = {}, 0
	for _, result in pairs(scan.results) do
		local id, quantity = result.itemID, result.quantity
		if quantity > 0 then
			local price = result.price > 0 and result.price or nil
			local value = items[id]
			if value then
				value[2] = value[2] + quantity
				if price and (not value[1] or price < value[1]) then value[1] = price end
			else
				items[id] = { [1] = price, [2] = quantity }
				distinct = distinct + 1
			end
		end
	end
	if distinct == 0 then self:StopFullScan(not scan.passive and L["vendorAuctionScanEmpty"] or nil) return end
	self:FinishFullScan(scan, items, scan.count, distinct)
end

function Sales:StartFullScan(side)
	if not self:IsEnabled() then return end
	local faction = UnitFactionGroup("player")
	local market = marketForSide(side)
	if not market or (side ~= faction and side ~= "Neutral") or not self.open or not AuctionHouseFrame:IsShown() then return end
	local auctioneer = UnitFactionGroup("npc")
	if (auctioneer == "Alliance" or auctioneer == "Horde" or auctioneer == "Neutral") and auctioneer ~= side then return end
	if not AH.SendBrowseQuery or not AH.RequestMoreBrowseResults or not AH.GetBrowseResults or not AH.HasFullBrowseResults then
		print(L["vendorAuctionScanFailed"])
		return
	end
	if self.fullScan or self.quick or InCombatLockdown() or self.watchSearch or (self.search and not self.search.received)
		or not AH.IsThrottledMessageSystemReady() then
		print(L["vendorAuctionBusy"])
		return
	end
	self.confirmedMarketSide = side
	local npc = auctioneerID()
	if npc then
		local db = vendorDB()
		db.auctioneerMarkets = db.auctioneerMarkets or {}
		db.auctioneerMarkets[npc] = side
	end
	self:StartBrowseScan(side, market, false)
	self.sendingBrowse = true
	AH.SendBrowseQuery({ searchString = "", sorts = {}, filters = {}, itemClassFilters = {} })
	self.sendingBrowse = nil
end

function Sales:ChooseFullScan(owner)
	if self.fullScan then return end
	local faction = UnitFactionGroup("player")
	if faction ~= "Alliance" and faction ~= "Horde" then return end
	local auctioneer = UnitFactionGroup("npc")
	if auctioneer == faction or auctioneer == "Neutral" then
		self:StartFullScan(auctioneer)
	elseif auctioneer ~= "Alliance" and auctioneer ~= "Horde" and _G.MenuUtil then
		_G.MenuUtil.CreateContextMenu(owner, function(_, root)
			root:CreateTitle(L["vendorAuctionScan"])
			root:CreateButton(marketLabel(faction), function() self:StartFullScan(faction) end)
			root:CreateButton(marketLabel("Neutral"), function() self:StartFullScan("Neutral") end)
		end)
	end
end

function Sales:ReadFullScan()
	local scan = self.fullScan
	if not scan or scan.browse or scan.reading then return end
	local function stop(message)
		self:StopFullScan(not scan.passive and message or nil)
	end
	scan.reading = true
	local total = AH.GetNumReplicateItems()
	if not total or total <= 0 then stop(L["vendorAuctionScanEmpty"]) return end
	scan.percent = 0
	self:UpdateScanDisplay()
	local index, items, distinct = 0, {}, 0
	scan.names = {}
	local function step()
		if self.fullScan ~= scan then return end
		if not self:IsEnabled() or not self.open or not AuctionHouseFrame:IsShown() then self:StopFullScan() return end
		local last = math.min(index + 400, total)
		while index < last do
			local name, _, count, quality, _, _, _, _, _, buyout, _, _, _, _, _, _, id = AH.GetReplicateItemInfo(index)
			if not id or id <= 0 or not count or count <= 0 or not buyout then
				stop(L["vendorAuctionScanIncomplete"])
				return
			end
			local price = buyout > 0 and math.max(1, math.floor(buyout / count)) or nil
			local value = items[id]
			if value then
				value[2] = value[2] + count
				if price and (not value[1] or price < value[1]) then value[1] = price end
			else
				items[id] = { [1] = price, [2] = count }
				distinct = distinct + 1
			end
			if items[id].quality == nil then items[id].quality = itemQuality(quality) end
			if not scan.names[id] and usableItemName(name) then scan.names[id] = name end
			index = index + 1
		end
		if index < total then
			local percent = math.floor(index * 100 / total)
			if percent ~= scan.percent then
				scan.percent = percent
				self:UpdateScanDisplay()
			end
			C_Timer.After(0, step)
		else
			if AH.GetNumReplicateItems() ~= total then stop(L["vendorAuctionScanIncomplete"]) return end
			self:FinishFullScan(scan, items, total, distinct)
		end
	end
	step()
end

local function sellFrameFor(location)
	if not location or not AuctionHouseFrame or not AuctionHouseFrame:IsShown() then return end
	local status = AH.GetItemCommodityStatus(location)
	if status == Enum.ItemCommodityStatus.Commodity then return AuctionHouseFrame.CommoditiesSellFrame, true end
	if status == Enum.ItemCommodityStatus.Item then return AuctionHouseFrame.ItemSellFrame, false end
end

local function sameItem(location, other)
	return other and other:IsBagAndSlot() and C_Item.DoesItemExist(other) and C_Item.GetItemGUID(location) == C_Item.GetItemGUID(other)
end

local function isStaged(location)
	local native = sellFrameFor(location)
	return native and native:IsShown() and sameItem(location, native:GetItem())
end

local function locationFor(row)
	if not row or isExcluded(row.key.itemID) then return end
	local location = ItemLocation:CreateFromBagAndSlot(row.bag, row.slot)
	local info = C_Container.GetContainerItemInfo(row.bag, row.slot)
	if not info or info.isBound or info.hyperlink ~= row.link or C_Item.GetItemGUID(location) ~= row.guid then return end
	-- Blizzard locks the selected bag slot while its sell frame displays it.
	if info.isLocked then
		if isStaged(location) then return location end
	elseif AH.IsSellItemValid(location, false) then
		return location
	end
end

local function listingStats(key, exactKey, commodity, limit, collectBook)
	local best, quantity, matched = nil, 0, 0
	local book = collectBook and {}
	local function collect(price, count, sellers)
		if count <= 0 then return end
		quantity = quantity + count
		if price and price > 0 then
			if not limit or price <= limit then matched = matched + count end
			if not best or price < best then best = price end
			if book then
				local tier = book[price]
				if not tier then
					tier = { price = price, count = 0, sellers = 0 }
					book[price] = tier
				end
				tier.count = tier.count + count
				tier.sellers = tier.sellers + math.max(1, sellers or 1)
			end
		end
	end
	if commodity then
		for index = 1, AH.GetNumCommoditySearchResults(key.itemID) do
			local result = AH.GetCommoditySearchResultInfo(key.itemID, index)
			if result then
				local ownItems = result.numOwnerItems
				local sellers = result.totalNumberOfOwners
				if sellers and ownItems > 0 then sellers = sellers - 1 end
				collect(result.unitPrice, result.quantity - ownItems, sellers)
			end
		end
	else
		local id = exactKey and priceKey(exactKey)
		for index = 1, AH.GetNumItemSearchResults(key) do
			local result = AH.GetItemSearchResultInfo(key, index)
			if result and not result.containsOwnerItem and not result.containsAccountItem and (not id or priceKey(result.itemKey) == id) then
				collect(result.buyoutAmount, result.quantity, result.totalNumberOfOwners)
			end
		end
	end
	local tiers
	if book then
		tiers = {}
		for _, tier in pairs(book) do tiers[#tiers + 1] = tier end
		table.sort(tiers, function(a, b) return a.price < b.price end)
	end
	return best, quantity, matched, tiers
end

local function purchaseTotal(tiers, wanted)
	local total = 0
	for _, tier in ipairs(tiers or {}) do
		local count = math.min(wanted, tier.count)
		total, wanted = total + tier.price * count, wanted - count
		if wanted == 0 then return total end
	end
end

local function hasFullResults(key, commodity)
	if commodity then return AH.HasFullCommoditySearchResults(key.itemID) end
	return AH.HasFullItemSearchResults(key)
end

local function matchingKey(search, event, arg)
	local commodity = event:find("^COMMODITY_") ~= nil
	if commodity ~= search.commodity then return end
	local key = search.key
	if commodity then return arg == key.itemID and key or nil end
	if type(arg) ~= "table" then return end
	local id = priceKey(arg)
	if id == priceKey(key) or (search.row and id == priceKey(search.exactKey)) then return arg end
end

local function storeQuote(key, price)
	local time = GetServerTime()
	local quote = price and { price = price, time = time }
	Sales.live[key] = quote
	local market = Sales.market
	if not market then return end
	local previous = savedPrices()
	previous = previous and previous[market]
	previous = type(previous) == "table" and previous[key]
	if quote then
		local prices = savedPrices(true)
		if type(prices[market]) ~= "table" then prices[market] = {} end
		prices[market][key] = quote
	else
		local prices = savedPrices()
		if prices and type(prices[market]) == "table" then prices[market][key] = nil end
	end
	if (type(previous) == "table" and previous.price or nil) ~= price then refreshBagValue() end
end

local function nameFor(key)
	local info = AH.GetItemKeyInfo(key)
	return info and info.itemName or C_Item.GetItemNameByID(key.itemID) or ("#" .. key.itemID)
end

function Sales:GetBrowsingMarket()
	return self.browsingMarket or self.market or factionMarket()
end

local function matchesMarketCategory(catalog, itemID, category)
	if not category then return true end
	local itemType = catalog.types[itemID]
	if itemType == false then return nil end
	if not itemType then
		local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
		if classID == nil then
			catalog.types[itemID] = false
			return nil
		end
		itemType = { classID = classID, subclassID = subclassID }
		catalog.types[itemID] = itemType
	end
	local unresolved
	for _, filter in ipairs(category.filters) do
		if (filter.classID == nil or filter.classID == itemType.classID) and (filter.subClassID == nil or filter.subClassID == itemType.subclassID) then
			if filter.inventoryType == nil then return true end
			if itemType.inventoryType == nil then itemType.inventoryType = C_Item.GetItemInventoryTypeByID(itemID) or false end
			if filter.inventoryType == itemType.inventoryType then return true end
			if itemType.inventoryType == false then unresolved = true end
		end
	end
	if unresolved then return nil end
	return false
end

function Sales:GetScannedItems(market, query, category, quality)
	local items = {}
	query = query:match("^%s*(.-)%s*$")
	if not market or (query == "" and not category and quality == nil) then return items end
	local exactID = tonumber(query:match("|Hitem:(%d+)") or query:match("^item:(%d+)") or query:match("^(%d+)$"))
	query = query:lower()
	local today = historyDay(GetServerTime())
	local catalog = self.marketCatalog
	if not catalog or catalog.market ~= market or catalog.day ~= today then
		local ids = {}
		local history, saved = auctionHistory(), snapshots()
		local snapshot = saved and saved[market]
		local snapshotItems = snapshot and snapshot.items or {}
		for itemID, result in pairs(snapshotItems) do
			if result[1] then ids[itemID] = true end
		end
		for day, record in pairs(history and history[market] or {}) do
			if day > today - historyDays and day <= today then
				for itemID in pairs(record.items) do ids[itemID] = true end
			end
		end
		catalog = { market = market, day = today, ids = ids, snapshotItems = snapshotItems, names = {}, qualities = {}, types = {}, prices = {}, requested = {} }
		self.marketCatalog = catalog
	end
	if catalog.results and catalog.query == query and catalog.exactID == exactID and catalog.category == category and catalog.quality == quality then
		return catalog.results, catalog.missingNames
	end
	if catalog.query ~= query or catalog.category ~= category or catalog.exactID ~= exactID or catalog.quality ~= quality then catalog.viewport = nil end
	if catalog.category ~= category then catalog.categoryMatches = {} end
	local categoryMatches = catalog.categoryMatches
	local missingNames, missingQuality = false, false
	local missingQualities = quality ~= nil and {}
	local requestedQualities = self.requestedQualities
	local known = scannedItemNames(true)
	local function considerItem(itemID)
		local matchesCategory = true
		if categoryMatches and category then
			matchesCategory = categoryMatches[itemID]
			if matchesCategory == nil then
				matchesCategory = matchesMarketCategory(catalog, itemID, category)
				categoryMatches[itemID] = matchesCategory
			end
		end
		if matchesCategory == false then return end
		local name = catalog.names[itemID]
		if name == nil then
			local text = known[itemID] or cachedItemName(itemID)
			name = usableItemName(text) and { display = text, search = text:lower() } or false
			catalog.names[itemID] = name
			if name then known[itemID] = text end
		end
		if not name then missingNames = true end
		local matchesName = exactID or query == "" or (name and name.search:find(query, 1, true))
		if name and not matchesName then return end
		local rarity = catalog.qualities[itemID]
		if rarity == nil then
			local result = catalog.snapshotItems[itemID]
			rarity = (result and result.quality) or cachedItemQuality(itemID) or false
			if result and rarity ~= false then result.quality = rarity end
			catalog.qualities[itemID] = rarity
		end
		if rarity == false then
			missingQuality = true
			if missingQualities and not (requestedQualities and requestedQualities[itemID]) then missingQualities[itemID] = true end
		end
		if quality ~= nil and rarity ~= quality then return end
		if not matchesCategory or not matchesName then return end
		local item = catalog.prices[itemID]
		if not item then
			local average, _, latest, at = summarizeHistory(itemID, market, today, 7)
			item = { key = AH.MakeItemKey(itemID), count = latest, limit = average, scannedAt = latest and at or nil, market = market }
			catalog.prices[itemID] = item
		end
		item.name = name and name.display or ("#" .. itemID)
		item.quality = rarity or nil
		items[#items + 1] = { entry = item, name = item.name, id = itemID }
	end
	if exactID then
		if catalog.ids[exactID] then considerItem(exactID) end
	else
		for itemID in pairs(catalog.ids) do considerItem(itemID) end
	end
	catalog.query, catalog.exactID, catalog.category, catalog.quality = query, exactID, category, quality
	catalog.results, catalog.missingNames, catalog.missingQuality = items, missingNames, missingQuality
	if missingQualities and next(missingQualities) then self:QueueItemQualities(missingQualities) end
	return items, missingNames
end

function Sales:OnMarketItemData(itemID, success)
	local catalog = self.marketCatalog
	if not success then return end
	local updateName = catalog and catalog.names[itemID] == false
	local updateQuality = catalog and catalog.qualities[itemID] == false
	if not updateName and not updateQuality and not (self.requestedQualities and self.requestedQualities[itemID]) then return end
	local rarity = cachedItemQuality(itemID)
	if rarity ~= nil then
		for _, snapshot in pairs(snapshots() or {}) do
			local result = snapshot.items[itemID]
			if result and result.quality == nil then result.quality = rarity end
		end
	end
	if not catalog then return end
	local dirty
	if updateName then
		local name = cachedItemName(itemID)
		if usableItemName(name) then
			scannedItemNames(true)[itemID] = name
			catalog.names[itemID] = { display = name, search = name:lower() }
			dirty = true
		end
	end
	if updateQuality and rarity ~= nil then
		catalog.qualities[itemID] = rarity
		dirty = true
	end
	if not dirty then return end
	catalog.types[itemID] = nil
	if catalog.categoryMatches then catalog.categoryMatches[itemID] = nil end
	catalog.results = nil
	if catalog.refreshQueued then return end
	catalog.refreshQueued = true
	C_Timer.After(0.1, function()
		catalog.refreshQueued = nil
		if self.marketCatalog == catalog and self.mode == "market" and (self.marketCategory or self.marketQuality ~= nil or (self.filters.market or ""):find("%S")) then
			self:Refresh()
		end
	end)
end

function Sales:QueueVisibleMarketNames()
	local catalog = self.marketCatalog
	if self.mode ~= "market" or not catalog or not (catalog.missingNames or catalog.missingQuality) or catalog.viewportQueued or not C_Item.RequestLoadItemDataByID then return end
	catalog.viewportQueued = true
	C_Timer.After(0, function()
		catalog.viewportQueued = nil
		local panel = self.panel
		if self.marketCatalog ~= catalog or self.mode ~= "market" or not panel or not panel:IsShown() then return end
		local offset, height = panel.scroll:GetVerticalScroll(), panel.scroll:GetHeight()
		if height <= 0 then return end
		local first = math.floor(offset / rowHeight) + 1
		local last = math.min(#panel.rows, math.ceil((offset + height) / rowHeight))
		local viewport = ("%d:%d:%d"):format(self.marketPage, first, last)
		if catalog.viewport == viewport then return end
		catalog.viewport = viewport
		for index = first, last do
			local row = panel.rows[index]
			if row:IsShown() then
				local itemID = row.entry.key.itemID
				if (catalog.names[itemID] == false or catalog.qualities[itemID] == false) and not catalog.requested[itemID] then
					catalog.requested[itemID] = true
					if not (self.requestedQualities and self.requestedQualities[itemID]) then C_Item.RequestLoadItemDataByID(itemID) end
				end
			end
		end
	end)
end

local function browsingMarketLabel(market)
	if not market then return "—" end
	local scope, side = market:match("^(.*):([^:]+)$")
	if not scope then return "—" end
	if scope == marketScope() then return marketLabel(side) end
	return scope .. " · " .. marketLabel(side)
end

function Sales:ChooseBrowsingMarket(owner)
	if not _G.MenuUtil then return end
	local available, markets = {}, {}
	local function collect(market)
		if market and not available[market] then
			available[market] = true
			markets[#markets + 1] = market
		end
	end
	collect(factionMarket())
	collect(marketForSide("Neutral"))
	for market in pairs(snapshots() or {}) do collect(market) end
	for market in pairs(auctionHistory() or {}) do collect(market) end
	table.sort(markets)
	_G.MenuUtil.CreateContextMenu(owner, function(_, root)
		for _, market in ipairs(markets) do
			root:CreateRadio(browsingMarketLabel(market), function() return self:GetBrowsingMarket() == market end, function()
				self.browsingMarket = market
				self.marketSelection = nil
				self.marketPage = 1
				self.panel.scrollBar:SetValue(0)
				self:Refresh()
			end)
		end
	end)
end

function Sales:ChooseMarketCategory(owner)
	if not _G.MenuUtil then return end
	if not _G.AuctionCategories then C_AddOns.LoadAddOn("Blizzard_AuctionHouseUI") end
	local function choose(category)
		self.marketCategory = category
		self.marketPage = 1
		self.panel.scrollBar:SetValue(0)
		self:Refresh()
	end
	local function addOption(menu, text, category)
		menu:CreateRadio(text, function() return self.marketCategory == category end, function() choose(category) end)
	end
	local function addCategories(menu, categories)
		for _, category in ipairs(categories or {}) do
			if category.filters and not category.implicitFilter and not category:HasFlag("WOW_TOKEN_FLAG") then
				if category.subCategories and #category.subCategories > 0 then
					local submenu = menu:CreateButton(category.name)
					addOption(submenu, _G.ALL or L["vendorAuctionMarketAllCategories"], category)
					addCategories(submenu, category.subCategories)
				else
					addOption(menu, category.name, category)
				end
			end
		end
	end
	_G.MenuUtil.CreateContextMenu(owner, function(_, root)
		addOption(root, L["vendorAuctionMarketAllCategories"], nil)
		addCategories(root, _G.AuctionCategories)
	end)
end

local function marketQualityLabel(quality)
	local name = quality and _G["ITEM_QUALITY" .. quality .. "_DESC"]
	if not name then return L["vendorAuctionMarketAllQualities"] end
	local color = ITEM_QUALITY_COLORS[quality]
	return color and (color.hex .. name .. "|r") or name
end

function Sales:ChooseMarketQuality(owner)
	if not _G.MenuUtil then return end
	_G.MenuUtil.CreateContextMenu(owner, function(_, root)
		local function addOption(quality)
			root:CreateRadio(marketQualityLabel(quality), function() return self.marketQuality == quality end, function()
				self.marketQuality = quality
				self.marketPage = 1
				self.panel.scrollBar:SetValue(0)
				self:Refresh()
			end)
		end
		addOption(nil)
		for quality = 0, 8 do
			if _G["ITEM_QUALITY" .. quality .. "_DESC"] then addOption(quality) end
		end
	end)
end

local function bagItemKey(location, itemID, commodity)
	if commodity then return AH.MakeItemKey(itemID) end
	return AH.GetItemKeyFromItem(location)
end

local function formatQuote(key)
	if not key then return "" end
	local price, at, source = Sales:GetListingPrice(key)
	if not price then return "" end
	if source == "live" then return L["vendorAuctionLivePrice"]:format(coinText(price)) end
	if source == "snapshot" then return L["vendorAuctionScanUnitPrice"]:format(coinText(price)) end
	return L["vendorAuctionSavedPrice"]:format(coinText(price), Sales:FormatPriceDate(at))
end

local function getBagRows(rows, market)
	wipe(rows)
	for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.hyperlink and not isExcluded(info.itemID) and not info.isBound and not _G.C_WowTokenPublic.IsAuctionableWowToken(info.itemID) then
				local location = ItemLocation:CreateFromBagAndSlot(bag, slot)
				local commodity = AH.GetItemCommodityStatus(location)
				local valid = info.isLocked and not market and isStaged(location) or not info.isLocked and AH.IsSellItemValid(location, false)
				if valid and commodity ~= Enum.ItemCommodityStatus.Unknown then
					local key = bagItemKey(location, info.itemID, commodity == Enum.ItemCommodityStatus.Commodity)
					local guid = C_Item.GetItemGUID(location)
					if key and guid then
						local price
						if market then price = storedListingPrice(key, market) else price = Sales:GetListingPrice(key) end
						rows[#rows + 1] = {
							bag = bag, slot = slot, link = info.hyperlink, guid = guid, count = info.stackCount, key = key,
							icon = info.iconFileID, quality = info.quality,
							value = price and price * info.stackCount or 0,
						}
					end
				end
			end
		end
	end
	table.sort(rows, function(a, b)
		if a.value ~= b.value then return a.value > b.value end
		if a.bag ~= b.bag then return a.bag < b.bag end
		return a.slot < b.slot
	end)
end

function Sales:GetBagValue(includeVendorDelta)
	if not self:IsEnabled() then return end
	local market, faction = factionMarket()
	if not market then return end
	local db, prices = snapshots(), savedPrices()
	if not (db and db[market]) and not (prices and prices[market]) then return end
	local rows = {}
	getBagRows(rows, market)
	local total, top = 0, {}
	local vendorTotal = includeVendorDelta and 0 or nil
	for _, row in ipairs(rows) do
		if row.value <= 0 then break end
		total = total + row.value
		if #top < 5 then top[#top + 1] = row end
		if vendorTotal then
			local unitPrice = select(11, C_Item.GetItemInfo(row.link))
			vendorTotal = unitPrice and vendorTotal + unitPrice * row.count or nil
		end
	end
	return total, top, marketLabel(faction), vendorTotal and total - vendorTotal or nil
end

function Sales:ReadResults(event, arg)
	local search = self.search
	if not search or not self.panel or not self.panel:IsShown() then return end
	local queryKey = matchingKey(search, event, arg)
	if not queryKey then return end
	if search.row then
		local location = locationFor(search.row)
		local native = sellFrameFor(location)
		if not native or not native:IsShown() or not sameItem(location, native:GetItem()) then return end
	end

	local price = listingStats(queryKey, search.exactKey, search.commodity)
	local full = hasFullResults(queryKey, search.commodity)
	local key = priceKey(search.exactKey or queryKey)
	if price or full then storeQuote(key, price) end
	search.received = true
	search.status = not price and (full and L["vendorAuctionNoPrice"] or L["vendorAuctionNoVisiblePrice"]) or nil
	if search.row then self:ReadSellOffer(search, queryKey, full) end
	if price then
		local quote = self.live[key]
		C_Timer.After(liveLifetime, function()
			if self.live[key] == quote then self:Refresh(self.mode == "sell") end
		end)
	end
	self:Refresh(self.mode == "sell")
end

function Sales:StartSearch(search)
	self.search = search
	search.status = L["vendorCraftShopperWaitingForPrice"]
	C_Timer.After(10, function()
		if self.search ~= search or search.received or search.quick then return end
		self.search = nil
		self.status = L["vendorAuctionTimedOut"]
		self:Refresh()
	end)
end

function Sales:SelectBag(row, quick)
	if not quick then
		if self.quickPost then return end
		self:StopQuickSell()
	end
	if not self.open or not AuctionHouseFrame or not AuctionHouseFrame:IsShown() then
		self.selected = row
		self:Refresh()
		return
	end
	if self.fullScan then return end
	if InCombatLockdown() or GetCursorInfo() then return end
	if not AH.IsThrottledMessageSystemReady() then
		self.status = L["vendorAuctionBusy"]
		self:Refresh()
		return
	end
	local location = locationFor(row)
	local native, commodity = sellFrameFor(location)
	if not native then self:Refresh(true) return end
	local key = bagItemKey(location, row.key.itemID, commodity)
	if not key then return end
	local queryKey = commodity and key or _G.AuctionHouseUtil.ConvertItemSellItemKey(AH.GetItemKeyFromItem(location))
	if not queryKey then return end
	self.selected = row
	self:StartSearch({ key = queryKey, exactKey = key, commodity = commodity, row = row, quick = quick })
	AuctionHouseFrame:SetPostItem(location)
	self:Refresh()
	return true
end

function Sales:FinishWatch(search, quantity, matched, price, full, failed, tiers)
	self.watchSearch = nil
	local list = watchList()
	if not list or list[search.id] ~= search.entry then return end
	self.watchResults[search.id] = { quantity = quantity, matched = matched, failed = failed, tiers = tiers }
	if price or full then
		storeQuote(search.id, price)
	end

	local entry = search.entry
	local reached = not failed and matched >= (entry.quantity or 1)
	if reached and not self.alerts[search.id] then
		self.alerts[search.id] = true
		local available = L["vendorAuctionWatchAvailable"]:format(matched)
		if entry.limit and price then
			print(L["vendorAuctionWatchAlert"]:format(nameFor(entry.key), coinText(price), coinText(entry.limit)) .. " " .. available)
		else
			print(L["vendorAuctionWatchFound"]:format(nameFor(entry.key), available))
		end
	elseif full and not reached then
		self.alerts[search.id] = nil
	end
	self:Refresh(self.mode == "sell")
end

function Sales:ReadWatchResults(event, arg)
	local search = self.watchSearch
	if not search then return end
	local key = matchingKey(search, event, arg)
	if not key then return end
	local price, quantity, matched, tiers = listingStats(key, search.exactKey, search.commodity, search.entry.limit, true)
	local full = hasFullResults(key, search.commodity)
	if full or matched >= (search.entry.quantity or 1) then
		self:FinishWatch(search, quantity, matched, price, full, nil, tiers)
	else
		search.page = true
		search.latest = { quantity, matched, price, tiers }
	end
end

function Sales:AdvanceWatchScan()
	if self.fullScan or self.quick then return end
	if not self.open or not AuctionHouseFrame or not AuctionHouseFrame:IsShown() then return end
	local search = self.watchSearch
	local pending = self.pendingWatchFind
	if pending then
		local list = watchList()
		local id = self.watchKey and priceKey(self.watchKey)
		if self.mode ~= "watch" or not list or list[id] ~= pending.entry then
			self.pendingWatchFind = nil
		elseif GetTime() >= pending.deadline then
			self.pendingWatchFind = nil
			self.status = L["vendorAuctionBusy"]
			self:Refresh()
		elseif not search then
			if not InCombatLockdown() and AH.IsThrottledMessageSystemReady() then self:SearchWatchedItem() end
			return
		end
	end
	if not search and #self.watchQueue == 0 then
		if self.watchTicker then self.watchTicker:Cancel() end
		self.watchTicker = nil
		return
	end
	if search and GetTime() >= search.deadline then
		local latest = search.latest
		if latest then
			self:FinishWatch(search, latest[1], latest[2], latest[3], false, nil, latest[4])
		else
			self:FinishWatch(search, 0, 0, nil, false, true)
		end
		return
	end
	if InCombatLockdown() or not AH.IsThrottledMessageSystemReady() then return end
	if search then
		if not search.page then return end
		search.page = nil
		local full
		if search.commodity then
			full = AH.RequestMoreCommoditySearchResults(search.key.itemID)
		else
			full = AH.RequestMoreItemSearchResults(search.key)
		end
		if full and self.watchSearch == search then
			local event = search.commodity and "COMMODITY_SEARCH_RESULTS_UPDATED" or "ITEM_SEARCH_RESULTS_UPDATED"
			self:ReadWatchResults(event, search.commodity and search.key.itemID or search.key)
		end
		return
	end
	if self.search and not self.search.received then return end
	local id = table.remove(self.watchQueue, 1)
	local list = watchList()
	local entry = list and list[id]
	if not entry then return end
	local info = AH.GetItemKeyInfo(entry.key)
	if not info then
		local retry = (self.watchRetries[id] or 0) + 1
		self.watchRetries[id] = retry
		if retry < 5 then
			self.watchQueue[#self.watchQueue + 1] = id
		else
			self.watchResults[id] = { failed = true }
			self:Refresh()
		end
		return
	end
	self.watchSearch = {
		id = id, entry = entry, key = entry.key, exactKey = entry.exact and entry.key or nil,
		commodity = info.isCommodity, deadline = GetTime() + 12,
	}
	AH.SendSearchQuery(entry.key, sorts, true)
end

function Sales:CheckWatch(entry, defer)
	if not self.open then return end
	local id = priceKey(entry.key)
	self.watchRetries[id] = nil
	if not self.watchSearch or self.watchSearch.entry ~= entry then
		for index, queued in ipairs(self.watchQueue) do
			if queued == id then table.remove(self.watchQueue, index) break end
		end
		table.insert(self.watchQueue, defer and #self.watchQueue + 1 or 1, id)
	end
	if not self.watchTicker then
		self.watchTicker = C_Timer.NewTicker(0.4, function() self:AdvanceWatchScan() end)
	end
end

function Sales:QueueWatchList()
	for _, entry in pairs(watchList() or {}) do self:CheckWatch(entry, true) end
end

local function watchReady(entry, result)
	return result and not result.failed and result.matched >= (entry.quantity or 1)
end

function Sales:SearchWatchedItem()
	local list = watchList()
	local entry = list and self.watchKey and list[priceKey(self.watchKey)]
	local frame = AuctionHouseFrame
	if not entry or not frame or not frame:IsShown() or InCombatLockdown() then return end
	local ready = not self.fullScan and AH.IsThrottledMessageSystemReady()
	if not ready and not self.fullScan and self.watchTicker then
		self.pendingWatchFind = { entry = entry, deadline = GetTime() + 12 }
		self.status = L["vendorAuctionScanWaiting"]
		self:Refresh()
		return
	end
	self.pendingWatchFind = nil
	if not ready then
		self.status = L["vendorAuctionBusy"]
		self:Refresh()
		return
	end

	local info = AH.GetItemKeyInfo(entry.key)
	local name = info and info.itemName
	if not name then
		self.status = L["vendorAuctionTimedOut"]
		self:Refresh()
		return
	end
	self.status = nil
	frame:SetDisplayMode(_G.AuctionHouseFrameDisplayMode.Buy)
	frame:GetCategoriesList():SetSelectedCategory(nil)
	frame:SetSearchText(name)
	frame.SearchBar:StartSearch()
	frame:Raise()
	self:Refresh()
end

local panelWidth, panelHeight = 420, 540
local historyHeight, historyGap, minimumPanelHeight = 308, 8, 350
local rowNameLeft, rowQuantityRight, rowPriceRight = 44, 106, 8
local rowGutter = 23
local watchActionWidth, watchActionInset = 78, 90
local palette = {
	panel = { 0.09, 0.07, 0.05, 1 },
	card = { 0.24, 0.17, 0.11, 1 },
	border = { 0.34, 0.26, 0.17, 1 },
	row = { 0.10, 0.075, 0.05, 0.95 },
	alternate = { 0.15, 0.11, 0.075, 0.95 },
	hover = { 1, 0.78, 0.32, 0.17 },
	selected = { 0.31, 0.22, 0.11, 1 },
	accent = { 1, 0.82, 0, 1 },
	text = { 1, 1, 1, 1 },
	muted = { 0.87, 0.78, 0.62, 1 },
	dim = { 0.62, 0.56, 0.47, 1 },
	good = { 0.48, 0.85, 0.58, 1 },
	ready = { 0.10, 0.19, 0.10, 1 },
	warning = { 1, 0.63, 0.34, 1 },
}
local white = "Interface\\Buttons\\WHITE8x8"
local border = { bgFile = white, edgeFile = white, edgeSize = 1 }

local function paint(frame, color, edge)
	frame:SetBackdrop(border)
	frame:SetBackdropColor(unpack(color))
	frame:SetBackdropBorderColor(unpack(edge or palette.border))
end

local function fill(frame, layer, color)
	local texture = frame:CreateTexture(nil, layer)
	texture:SetColorTexture(unpack(color))
	return texture
end

local function label(parent, font, x, y, color)
	local text = parent:CreateFontString(nil, "OVERLAY", font)
	text:SetPoint("TOPLEFT", x, y)
	text:SetJustifyH("LEFT")
	text:SetTextColor(unpack(color or palette.text))
	return text
end

local function auctionWindow(name, title)
	local frame = CreateFrame("Frame", name, UIParent, "PortraitFrameTemplate")
	frame:SetBorder("ButtonFrameTemplateNoPortrait")
	frame:SetPortraitShown(false)
	frame:SetTitleOffsets(26, -26)
	frame:SetTitle(title)
	return frame
end

local function button(parent, text, width, onClick)
	local control = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	control:SetSize(width, 24)
	control:SetText(text)
	control:GetFontString():SetWordWrap(false)
	control:SetScript("OnClick", onClick)
	return control
end

local function watchDropHighlight(target, receiveItem)
	local overlay = CreateFrame("Frame", nil, target, "BackdropTemplate")
	overlay:SetAllPoints()
	overlay:SetFrameLevel(target:GetFrameLevel() + 6)
	paint(overlay, { 0.08, 0.2, 0.12, 0.22 }, palette.good)
	overlay:EnableMouse(true)
	overlay:SetScript("OnReceiveDrag", receiveItem)
	overlay:SetScript("OnMouseUp", function(_, mouseButton)
		if mouseButton == "LeftButton" then receiveItem() end
	end)
	local hint = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	hint:SetPoint("CENTER")
	hint:SetTextColor(unpack(palette.good))
	hint:SetText(L["vendorAuctionWatchDrop"])
	overlay.hint = hint
	local pulse = overlay:CreateAnimationGroup()
	pulse:SetLooping("BOUNCE")
	local alpha = pulse:CreateAnimation("Alpha")
	alpha:SetFromAlpha(0.55)
	alpha:SetToAlpha(1)
	alpha:SetDuration(0.7)
	overlay:SetScript("OnShow", function() pulse:Play() end)
	overlay:SetScript("OnHide", function() pulse:Stop() end)
	overlay:Hide()
	return overlay
end

function Sales:UpdateWatchDropHint()
	local panel = self.panel
	if not panel or not panel.watchDrop then return end
	local active = panel:IsShown() and self.mode == "watch" and GetCursorInfo() == "item"
	local highlightInput = active and panel.input:IsShown()
	panel.watchDrop:SetShown(active)
	panel.watchDrop.hint:SetShown(not highlightInput or panel.input:GetText() ~= "")
	panel.watchInputDrop:SetShown(highlightInput)
	panel.watchInputDrop.hint:SetShown(highlightInput and panel.input:GetText() == "")
end

function Sales:UpdateWatchTab()
	local tab = self.panel.watchTab
	local count = 0
	for id, entry in pairs(watchList() or {}) do
		if watchReady(entry, self.watchResults[id]) then count = count + 1 end
	end
	tab.readyCount = count
	local title = L["vendorAuctionWatch"]
	tab:SetText(count > 0 and ("%s (%d)"):format(title, count) or title)
end

local function tab(parent, text, width, onClick)
	local control = CreateFrame("Button", nil, parent, "BackdropTemplate")
	control:SetSize(width, 26)
	paint(control, palette.panel)
	local caption = control:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	caption:SetPoint("LEFT", 5, 0)
	caption:SetPoint("RIGHT", -5, 0)
	caption:SetWordWrap(false)
	control:SetFontString(caption)
	control:SetText(text)

	local hover = fill(control, "HIGHLIGHT", palette.hover)
	hover:SetAllPoints()
	control:SetHighlightTexture(hover)
	local marker = fill(control, "OVERLAY", palette.accent)
	marker:SetHeight(2)
	marker:SetPoint("BOTTOMLEFT", 8, 1)
	marker:SetPoint("BOTTOMRIGHT", -8, 1)
	control.marker = marker
	control:SetScript("OnClick", onClick)
	return control
end

local function selectTab(control, active)
	control:SetBackdropColor(unpack(active and palette.selected or palette.panel))
	control:GetFontString():SetTextColor(unpack(active and palette.accent or palette.muted))
	control.marker:SetShown(active)
end

local function itemLabel(link, key, fallback)
	return (link and link:match("|h%[(.-)%]|h")) or fallback or nameFor(key)
end

local function paintItem(text, quality)
	quality = itemQuality(quality)
	local color = quality and ITEM_QUALITY_COLORS[quality]
	if color then
		text:SetTextColor(color.r, color.g, color.b, 1)
	else
		text:SetTextColor(unpack(palette.text))
	end
end

local function updateScrollRange(panel)
	local bar = panel.scrollBar
	local maximum = math.max(0, panel.content:GetHeight() - panel.scroll:GetHeight())
	bar:SetMinMaxValues(0, maximum)
	bar:SetValue(math.min(bar:GetValue(), maximum))
	bar:SetShown(maximum > 0)
end

local function headerColumn(parent, width, anchor, x, field, align, sales, textInset)
	local column = CreateFrame("Button", nil, parent)
	column:SetSize(width, 24)
	column:SetPoint(anchor, x, -1)
	local text = column:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	text:SetPoint("TOPLEFT", textInset or 0, 0)
	text:SetPoint("BOTTOMRIGHT")
	text:SetWordWrap(false)
	text:SetJustifyH(align)
	column:SetFontString(text)
	column:SetScript("OnEnter", function() text:SetTextColor(unpack(palette.accent)) end)
	column:SetScript("OnLeave", function(control)
		text:SetTextColor(unpack(control.sorted and palette.accent or palette.muted))
	end)
	column.arrow = CreateFrame("Frame", nil, column)
	column.arrow:SetSize(10, 10)
	column.arrow.left = column.arrow:CreateLine(nil, "ARTWORK")
	column.arrow.right = column.arrow:CreateLine(nil, "ARTWORK")
	for _, line in ipairs({ column.arrow.left, column.arrow.right }) do
		line:SetThickness(1.4)
		line:SetColorTexture(unpack(palette.accent))
	end
	column.align = align
	column.textInset = textInset or 0
	column:SetScript("OnClick", function() sales:SortBy(field) end)
	return column
end

function Sales:SortBy(field)
	self:StopQuickSell()
	local current = self.sorts[self.mode]
	self.sorts[self.mode] = { field = field, ascending = not current or current.field ~= field or not current.ascending }
	if self.mode == "market" then
		self.marketPage = 1
		if self.marketCatalog then self.marketCatalog.viewport = nil end
	end
	self.panel.scrollBar:SetValue(0)
	self:Refresh()
end

local function showSort(column, title, field, sorting)
	local active = sorting and sorting.field == field
	local text = column:GetFontString()
	column.sorted = active
	column:SetText(title)
	text:SetTextColor(unpack(active and palette.accent or palette.muted))
	column.arrow:SetShown(active and true or false)
	if not active then return end
	column.arrow:ClearAllPoints()
	local width = math.min(text:GetStringWidth(), text:GetWidth(), column:GetWidth() - 14)
	if column.align == "RIGHT" then
		column.arrow:SetPoint("RIGHT", -width - 4, 0)
	else
		column.arrow:SetPoint("LEFT", math.min(column.textInset + width + 4, column:GetWidth() - 10), 0)
	end
	local arrow = column.arrow
	local low, high = 2, 7
	if not sorting.ascending then low, high = high, low end
	arrow.left:SetStartPoint("BOTTOMLEFT", arrow, 1, low)
	arrow.left:SetEndPoint("BOTTOMLEFT", arrow, 5, high)
	arrow.right:SetStartPoint("BOTTOMLEFT", arrow, 5, high)
	arrow.right:SetEndPoint("BOTTOMLEFT", arrow, 9, low)
end

local function filteredRows(items, selling, search, sorting)
	local output = {}
	search = search:lower():match("^%s*(.-)%s*$")
	for index, row in ipairs(items) do
		local item = selling and row or row.entry
		local name = itemLabel(item.link, item.key, row.name)
		if search == "" or name:lower():find(search, 1, true) or tostring(item.key.itemID):find(search, 1, true) then
			output[#output + 1] = { row = row, item = item, name = name, index = index }
		end
	end
	if sorting or not selling then
		local field = sorting and sorting.field or "name"
		local ascending = not sorting or sorting.ascending
		if field == "price" then
			for _, entry in ipairs(output) do
				if selling then
					local key = entry.item.key
					entry.price = Sales:GetListingPrice(key)
				else
					entry.price = entry.item.limit
				end
			end
		end
		table.sort(output, function(a, b)
			if not sorting and a.row.ready ~= b.row.ready then return a.row.ready == true end
			local left, right
			if field == "quantity" then
				left, right = a.item.count or a.item.quantity, b.item.count or b.item.quantity
			else
				left, right = a[field], b[field]
			end
			if left ~= right then
				if left == nil or right == nil then return left ~= nil end
				if ascending then return left < right end
				return left > right
			end
			if a.name ~= b.name then return a.name < b.name end
			if not selling then return a.row.id < b.row.id end
			return a.index < b.index
		end)
	end
	return output
end

local function vendorUnitPrice(link)
	local value = select(11, C_Item.GetItemInfo(link))
	if (issecretvalue and issecretvalue(value)) or type(value) ~= "number" or value < 0 then return end
	return value
end

local function groupBagRows(rows)
	local groups, byKey = {}, {}
	for _, row in ipairs(rows) do
		local id = priceKey(row.key)
		local group = byKey[id]
		if not group then
			group = { key = row.key, link = row.link, icon = row.icon, quality = row.quality, count = 0, value = 0, stacks = {} }
			byKey[id] = group
			groups[#groups + 1] = group
		end
		group.count = group.count + row.count
		group.value = group.value + row.value
		group.stacks[#group.stacks + 1] = row
	end
	table.sort(groups, function(a, b)
		if a.value ~= b.value then return a.value > b.value end
		local first, second = a.stacks[1], b.stacks[1]
		if first.bag ~= second.bag then return first.bag < second.bag end
		return first.slot < second.slot
	end)
	return groups
end

local function quickPrice(search, key, market)
	local _, _, _, tiers = listingStats(key, search.exactKey, search.commodity, nil, true)
	if #tiers == 0 then return end
	local historyMedian
	if search.commodity and market then
		local samples = {}
		for _, point in ipairs(Sales:GetPriceHistory(search.row.key.itemID, market, 7).points) do
			samples[#samples + 1] = point.price
		end
		if #samples >= 3 then historyMedian = median(samples) end
	end

	for index, tier in ipairs(tiers) do
		local ceiling = tier.price + math.max(1, math.floor(tier.price * 0.05))
		local nextTier, thirdTier = tiers[index + 1], tiers[index + 2]
		local nearby = nextTier and nextTier.price <= ceiling
		-- A large stack from one seller does not establish the going price on its own.
		local supported = tier.sellers >= 3
			or (tier.sellers >= 2 and nearby)
			or (thirdTier and thirdTier.price <= ceiling and (not search.commodity or tier.count >= 3))
		if supported then return tier.price, historyMedian or tier.price end
	end

	-- On thin markets, use a live offer only when it closely matches recent scans.
	if historyMedian then
		for _, tier in ipairs(tiers) do
			if tier.price >= 0.9 * historyMedian and tier.price <= 1.1 * historyMedian then return tier.price, historyMedian end
		end
	end
	return nil, nil, tiers[#tiers].price
end

local function nativeDialogOpen()
	local overlay = AuctionHouseFrame and AuctionHouseFrame.DialogOverlay
	return overlay and overlay:IsShown()
end

local function nativeOfferMatches(native, commodity, offer)
	local price
	if commodity then
		price = native:GetUnitPrice()
	else
		local bid, buyout = native:GetPrice()
		if bid then return false end
		price = buyout
	end
	return price == offer.price and native:GetQuantity() == offer.quantity
end

local function setNativeOffer(native, commodity, offer)
	native.QuantityInput:SetQuantity(offer.quantity)
	if not commodity then native:SetSecondaryPriceInputEnabled(false) end
	native.PriceInput:SetAmount(offer.price)
	return nativeOfferMatches(native, commodity, offer)
end

function Sales:GuardNativePost(quick, native)
	if quick.postGuard then quick.postGuard:Hide() end
	if not native.quickSellGuard then
		local guard = CreateFrame("Button", nil, native.PostButton)
		guard:SetAllPoints()
		guard:SetFrameLevel(native.PostButton:GetFrameLevel() + 1)
		guard:SetScript("OnClick", function() self:PostQuickSell() end)
		native.quickSellGuard = guard
	end
	quick.postGuard = native.quickSellGuard
	quick.postGuard:Show()
end

function Sales:ClearQuickSellDraft(quick)
	if quick.postGuard then quick.postGuard:Hide() end
	local location = not self.quickPost and not InCombatLockdown() and not nativeDialogOpen() and locationFor(quick.row)
	if location and isStaged(location) then AuctionHouseFrame:ClearPostItem() end
end

function Sales:StopQuickSell(message)
	local quick = self.quick
	if not quick then return end
	self.quick = nil
	if quick.ticker then quick.ticker:Cancel() end
	if self.search and self.search.quick == quick then self.search = nil end
	self:ClearQuickSellDraft(quick)
	if self.quickPost and self.quickPost.confirmed then self.quickPost = nil end
	self.panel.quickKeys:EnableKeyboard(false)
	self.panel.quickKeys.spaceDown = nil
	self.status = message
	self:Refresh(true)
end

function Sales:ReadSellOffer(search, key, full)
	local quick = search.quick
	if search.offer or (quick and (quick ~= self.quick or quick.blocked or self.quickPost)) then return end
	if not full then
		if quick then quick.page = key end
		return
	end
	if quick then quick.page = nil end
	local price, reference, highest = quickPrice(search, key, self.market)
	local vendor = vendorUnitPrice(search.row.link)
	local floor = vendorDB().quickSellFloor or 0
	local threshold = reference and math.ceil(reference * floor / 100)
	local offer = { market = self.market, expires = GetTime() + 30 }
	local native = sellFrameFor(locationFor(search.row))
	if vendor == nil then
		C_Item.RequestLoadItemDataByID(search.row.key.itemID)
		offer.message = L["vendorAuctionQuickNoVendor"]
	elseif (price or highest) and (price or highest) < vendor then
		offer.message = L["vendorAuctionQuickBelowVendor"]:format(coinText(price or highest), coinText(vendor))
	elseif not price then
		offer.message = L["vendorAuctionQuickNoPrice"]
	elseif floor > 0 and price < threshold then
		offer.message = L["vendorAuctionQuickUnderFloor"]:format(coinText(price), coinText(threshold))
	else
		local increment = AH.SupportsCopperValues() and 1 or _G.COPPER_PER_SILVER
		offer.price = math.ceil(price / increment) * increment
		offer.quantity = search.commodity and search.row.count or 1
		if not native or not setNativeOffer(native, search.commodity, offer) then
			offer.price = nil
			offer.message = L["vendorAuctionQuickStopped"]
		end
	end
	search.offer = offer
	if not quick then
		if native and not offer.price then native.PriceInput:SetAmount(0) end
		return
	end
	if offer.price then
		quick.offer = offer
		quick.deadline = offer.expires
		self.status = L["vendorAuctionQuickOffer"]:format(offer.quantity, coinText(offer.price * offer.quantity))
	else
		quick.blocked = true
		self:ClearQuickSellDraft(quick)
		self.status = offer.message
	end
end

function Sales:SkipQuickSell()
	local quick = self.quick
	if not quick or self.quickPost or not quick.row then return end
	self.search = nil
	self:ClearQuickSellDraft(quick)
	local key = priceKey(quick.row.key)
	repeat
		quick.index = quick.index + 1
	until not quick.rows[quick.index] or priceKey(quick.rows[quick.index].key) ~= key
	quick.row, quick.offer, quick.page, quick.blocked = nil, nil, nil, nil
	quick.deadline = GetTime() + 12
	self.status = nil
	self:AdvanceQuickSell()
	self:Refresh(true)
end

function Sales:AdvanceQuickSell()
	local quick = self.quick
	if not quick then return end
	if not self.open or not AuctionHouseFrame:IsShown() or self.market ~= quick.market or InCombatLockdown() then
		self:StopQuickSell(L["vendorAuctionQuickStopped"])
		return
	end

	if quick.blocked then return end
	local post = self.quickPost
	if post and post.confirmed then
		local row = post.row
		local info = C_Container.GetContainerItemInfo(row.bag, row.slot)
		local remaining = info and info.hyperlink == row.link and C_Item.GetItemGUID(ItemLocation:CreateFromBagAndSlot(row.bag, row.slot)) == row.guid
			and info.stackCount or 0
		if remaining == row.count - quick.offer.quantity and not (remaining > 0 and info.isLocked) then
			self.quickPost = nil
			if remaining == 0 then
				quick.index = quick.index + 1
			else
				row.count = remaining
			end
			quick.row, quick.offer = nil, nil
			quick.deadline = GetTime() + 12
			self:Refresh(true)
		end
	end
	if post and not post.confirmed and nativeDialogOpen() then
		quick.deadline = GetTime() + 12
		return
	end
	if GetTime() >= quick.deadline then
		self:StopQuickSell(L["vendorAuctionTimedOut"])
		return
	end
	if self.quickPost or self.fullScan or self.watchSearch or nativeDialogOpen() or GetCursorInfo() or not AH.IsThrottledMessageSystemReady() then return end
	if quick.row then
		local location = locationFor(quick.row)
		local native, commodity = sellFrameFor(location)
		if not self.search or self.search.quick ~= quick or not native or not native:IsShown() or not sameItem(location, native:GetItem()) then
			self:StopQuickSell(L["vendorAuctionQuickStopped"])
			return
		end
		local offer = quick.offer
		if offer and not nativeOfferMatches(native, commodity, offer) then setNativeOffer(native, commodity, offer) end
		local key = quick.page
		if key then
			local search = self.search
			quick.page = nil
			if search.commodity then
				AH.RequestMoreCommoditySearchResults(key.itemID)
			else
				AH.RequestMoreItemSearchResults(key)
			end
			if self.quick == quick and hasFullResults(key, search.commodity) then
				self:ReadSellOffer(search, key, true)
				self:Refresh()
			end
		end
		return
	end

	local row = quick.rows[quick.index]
	if not row then
		self:StopQuickSell(L["vendorAuctionQuickDone"])
		return
	end
	local info = C_Container.GetContainerItemInfo(row.bag, row.slot)
	if not locationFor(row) or info.stackCount ~= row.count then
		self:StopQuickSell(L["vendorAuctionQuickStopped"])
		return
	end
	quick.row = row
	self.status = nil
	if not self:SelectBag(row, quick) then
		self:StopQuickSell(L["vendorAuctionQuickStopped"])
		return
	end
	if self.quick == quick and not quick.blocked then
		local native = sellFrameFor(locationFor(row))
		if native then
			self:GuardNativePost(quick, native)
			if not quick.offer then native.PriceInput:SetAmount(0) end
		end
	end
end

function Sales:PostQuickSell()
	local quick = self.quick
	local offer = quick and quick.offer
	if not offer or self.quickPost or GetTime() >= quick.deadline then return end
	if not self.open or self.market ~= quick.market or self.fullScan or InCombatLockdown() or GetCursorInfo()
		or nativeDialogOpen() or not AH.IsThrottledMessageSystemReady() then return end
	local row = quick.row
	local location = locationFor(row)
	local native, commodity = sellFrameFor(location)
	local info = location and C_Container.GetContainerItemInfo(row.bag, row.slot)
	if not native or not native:IsShown() or not sameItem(location, native:GetItem()) or info.stackCount ~= row.count then
		self:StopQuickSell(L["vendorAuctionQuickStopped"])
		return
	end
	local vendor = vendorUnitPrice(row.link)
	if vendor == nil or offer.price < vendor then
		quick.offer, quick.blocked = nil, true
		self:ClearQuickSellDraft(quick)
		self.status = vendor == nil and L["vendorAuctionQuickNoVendor"]
			or L["vendorAuctionQuickBelowVendor"]:format(coinText(offer.price), coinText(vendor))
		self:Refresh(true)
		return
	end
	if not nativeOfferMatches(native, commodity, offer) then
		if not setNativeOffer(native, commodity, offer) then self:StopQuickSell(L["vendorAuctionQuickStopped"]) end
		return
	end
	local allowed, reason = native:CanPostItem()
	if not allowed then
		self:StopQuickSell(reason or L["vendorAuctionQuickStopped"])
		return
	end
	self.quickPost = { row = row }
	quick.deadline = GetTime() + 12
	self.status = L["vendorAuctionQuickPosting"]
	native:PostItem()
	self:Refresh()
end

function Sales:StartQuickSell(selected)
	if self.quick or self.quickPost or not self.open or self.mode ~= "sell" or self.fullScan
		or InCombatLockdown() or nativeDialogOpen() or GetCursorInfo() then return end
	local rows = {}
	if selected then
		rows[1] = selected
	else
		getBagRows(self.bags)
		local visible = filteredRows(groupBagRows(self.bags), true, self.filters.sell or "", self.sorts.sell)
		for _, entry in ipairs(visible) do
			for _, stack in ipairs(entry.row.stacks) do rows[#rows + 1] = stack end
		end
	end
	if #rows == 0 then self:Refresh(true) return end
	local quick = { rows = rows, index = 1, market = self.market, deadline = GetTime() + 12 }
	local search = selected and self.search
	local offer = search and search.row == selected and search.offer
	local location = offer and locationFor(selected)
	local native, commodity = sellFrameFor(location)
	local reuse = offer and offer.price and offer.market == self.market and offer.expires > GetTime()
		and native and native:IsShown() and sameItem(location, native:GetItem()) and nativeOfferMatches(native, commodity, offer)
	if reuse then
		quick.row, quick.offer, quick.deadline = selected, offer, offer.expires
		search.quick = quick
	end
	self.quick = quick
	self.panel.filter:ClearFocus()
	self.panel.quickKeys:EnableKeyboard(true)
	quick.ticker = C_Timer.NewTicker(0.15, function() self:AdvanceQuickSell() end)
	if reuse then
		self:GuardNativePost(quick, native)
		self:PostQuickSell()
	else
		self:AdvanceQuickSell()
	end
	self:Refresh()
end

local function createList(panel, sales)
	local list = CreateFrame("Frame", nil, panel, "BackdropTemplate")
	paint(list, palette.row)
	local header = fill(list, "BACKGROUND", palette.card)
	header:SetPoint("TOPLEFT", 1, -1)
	header:SetPoint("TOPRIGHT", -1, -1)
	header:SetHeight(24)
	list:SetPoint("TOPLEFT", 12, -114)
	list:SetPoint("BOTTOMRIGHT", -12, 127)
	panel.list = list
	panel.columnItem = headerColumn(list, 170, "TOPLEFT", 10, "name", "LEFT", sales, rowNameLeft - 9)
	panel.columnQuantity = headerColumn(list, 86, "TOPRIGHT", -rowGutter - rowQuantityRight, "quantity", "RIGHT", sales)
	panel.columnPrice = headerColumn(list, 94, "TOPRIGHT", -rowGutter - rowPriceRight, "price", "RIGHT", sales)

	local scroll = CreateFrame("ScrollFrame", nil, list, "UIPanelScrollFrameTemplate")
	scroll.scrollBarHideable = true
	scroll:SetPoint("TOPLEFT", 1, -26)
	scroll:SetPoint("BOTTOMRIGHT", -rowGutter, 1)
	scroll:SetClipsChildren(true)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(panelWidth - 48, 1)
	scroll:SetScrollChild(content)
	panel.scroll, panel.content, panel.rows = scroll, content, {}

	local bar = scroll.ScrollBar
	bar:ClearAllPoints()
	bar:SetPoint("TOPRIGHT", list, "TOPRIGHT", -3, -43)
	bar:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -3, 18)
	bar.scrollStep = rowHeight * 2
	bar:HookScript("OnValueChanged", function() sales:QueueVisibleMarketNames() end)
	bar:Hide()
	panel.scrollBar = bar
	scroll:SetScript("OnSizeChanged", function() updateScrollRange(panel) end)
	scroll:EnableMouseWheel(true)

	panel.empty = label(list, "GameFontHighlight", 15, -45, palette.muted)
	panel.empty:SetWidth(panelWidth - 62)
end

function Sales:BuildPriceHistory()
	local frame = auctionWindow("EnhanceQoLAuctionSalesHistoryFrame", L["vendorAuctionHistory"])
	frame:SetSize(panelWidth, historyHeight)
	frame:SetFrameStrata("DIALOG")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame.range = 7

	local header = CreateFrame("Frame", nil, frame)
	header:SetPoint("TOPLEFT", 10, -23)
	header:SetPoint("TOPRIGHT", -10, -23)
	header:SetHeight(44)
	frame:RegisterForDrag("LeftButton")
	header:EnableMouse(true)
	header:RegisterForDrag("LeftButton")
	local function startMoving()
		frame.detached, frame.dragging = true, true
		frame:StartMoving()
		self:RestoreHistoryDock()
	end
	frame:SetScript("OnDragStart", startMoving)
	header:SetScript("OnDragStart", startMoving)
	local function stopMoving()
		if not frame.dragging then return end
		frame:StopMovingOrSizing()
		frame.dragging = nil
	end
	header:SetScript("OnDragStop", stopMoving)
	frame:SetScript("OnDragStop", stopMoving)
	frame:SetScript("OnHide", function()
		stopMoving()
		self:RestoreHistoryDock()
	end)
	frame.header = header

	local icon = CreateFrame("Frame", nil, header, "BackdropTemplate")
	icon:SetSize(34, 34)
	icon:SetPoint("LEFT", 5, 0)
	paint(icon, palette.panel)
	icon.texture = icon:CreateTexture(nil, "ARTWORK")
	icon.texture:SetPoint("TOPLEFT", 2, -2)
	icon.texture:SetPoint("BOTTOMRIGHT", -2, 2)
	icon.texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	frame.icon = icon
	frame.item = label(header, "GameFontHighlightMedium", 54, -7)
	frame.item:SetPoint("TOPRIGHT", -43, -7)
	frame.item:SetWordWrap(false)
	frame.market = label(header, "GameFontHighlight", 54, -26, palette.muted)

	local function priceCard(text, point, offset, color)
		local card = CreateFrame("Frame", nil, frame, "BackdropTemplate")
		card:SetSize(195, 64)
		card:SetPoint(point, offset, -74)
		paint(card, palette.card)
		local heading = label(card, "GameFontHighlight", 10, -6, palette.muted)
		heading:SetWidth(174)
		heading:SetWordWrap(false)
		heading:SetText(text)
		local value = label(card, "GameFontHighlightLarge", 10, -21, color)
		value:SetWidth(174)
		value:SetWordWrap(false)
		local detail = label(card, "GameFontHighlight", 10, -44, palette.muted)
		detail:SetWidth(174)
		detail:SetWordWrap(false)
		return value, detail
	end
	frame.latest, frame.scanTime = priceCard(L["vendorAuctionHistoryLatest"], "TOPLEFT", 10)
	frame.average, frame.coverage = priceCard(L["vendorAuctionHistoryAverage"], "TOPRIGHT", -10, palette.accent)
	local description = label(frame, "GameFontHighlight", 11, -145, palette.muted)
	description:SetWidth(panelWidth - 26)
	description:SetMaxLines(2)
	description:SetText(L["vendorAuctionHistoryDescription"])

	local plot = CreateFrame("Frame", nil, frame)
	plot:SetPoint("TOPLEFT", 111, -173)
	plot:SetSize(286, 76)
	local backdrop = fill(plot, "BACKGROUND", palette.card)
	backdrop:SetPoint("TOPLEFT", -4, 4)
	backdrop:SetPoint("BOTTOMRIGHT", 4, -4)
	for _, edge in ipairs({ "TOP", "BOTTOM" }) do
		local guide = fill(plot, "BACKGROUND", palette.border)
		guide:SetPoint(edge .. "LEFT")
		guide:SetPoint(edge .. "RIGHT")
		guide:SetHeight(1)
	end
	frame.plot = plot
	frame.high = label(frame, "GameFontHighlightSmall", 14, -173, palette.muted)
	frame.low = label(frame, "GameFontHighlightSmall", 14, -239, palette.muted)
	for _, axis in ipairs({ frame.high, frame.low }) do
		axis:SetWidth(90)
		axis:SetWordWrap(false)
	end
	frame.first = label(plot, "GameFontHighlight", 0, 0, palette.muted)
	frame.first:ClearAllPoints()
	frame.first:SetPoint("TOPLEFT", plot, "BOTTOMLEFT", 0, -8)
	frame.last = plot:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.last:SetTextColor(unpack(palette.muted))
	frame.last:SetPoint("TOPRIGHT", plot, "BOTTOMRIGHT", 0, -8)
	frame.empty = plot:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.empty:SetPoint("CENTER")
	frame.empty:SetWidth(236)
	frame.empty:SetTextColor(unpack(palette.muted))

	frame.markers, frame.lines, frame.ranges = {}, {}, {}
	for index, range in ipairs({ 7, historyDays }) do
		local control = button(frame, L["vendorAuctionHistoryDays"]:format(range), 83, function()
			frame.range = range
			self:RefreshPriceHistory()
		end)
		control:GetFontString():SetFontObject(GameFontHighlight)
		control:SetHeight(22)
		control:SetPoint("BOTTOM", (index - 1.5) * 91, 10)
		frame.ranges[range] = control
	end
	frame:Hide()
	self.history = frame
end

function Sales:RestoreHistoryDock()
	local panel = self.panel
	if not panel then return end
	if panel.historyAnchor then
		panel:ClearAllPoints()
		panel:SetPoint(unpack(panel.historyAnchor, 1, 5))
		panel.historyAnchor = nil
	end
	local height = panel.baseHeight or panelHeight
	if panel:GetHeight() ~= height then panel:SetHeight(height) end
end

function Sales:DockPriceHistory()
	local frame = self.history
	if not frame or not frame:IsShown() or frame.detached then return end
	self:RestoreHistoryDock()
	local anchor = self.panel and self.panel:IsShown() and self.panel or (frame.posting and AuctionHouseFrame)
	if not anchor then return end
	local toScreen = anchor:GetEffectiveScale() / UIParent:GetEffectiveScale()
	local screenHeight = UIParent:GetHeight()
	local below = (anchor:GetBottom() or 0) * toScreen
	local above = screenHeight - (anchor:GetTop() or 0) * toScreen
	local left = (anchor:GetLeft() or 0) * toScreen
	local right = UIParent:GetWidth() - (anchor:GetRight() or 0) * toScreen
	frame:ClearAllPoints()
	local available = screenHeight - historyHeight - 3 * historyGap
	if anchor == self.panel and available >= minimumPanelHeight then
		anchor:SetHeight(math.min(anchor.baseHeight or panelHeight, available))
		local top = anchor:GetTop()
		local requiredTop = anchor:GetHeight() + historyHeight + 2 * historyGap
		if top and top < requiredTop then
			local point, relative, relativePoint, x, y = anchor:GetPoint()
			anchor.historyAnchor = { point, relative, relativePoint, x, y }
			anchor:ClearAllPoints()
			anchor:SetPoint(point, relative, relativePoint, x, y + requiredTop - top)
		end
		frame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -historyGap)
	elseif below >= historyHeight + historyGap then
		frame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -historyGap)
	elseif above >= historyHeight + historyGap then
		frame:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, historyGap)
	elseif right < frame:GetWidth() + historyGap and left > right then
		frame:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -historyGap, 0)
	else
		frame:SetPoint("TOPLEFT", anchor, "TOPRIGHT", historyGap, 0)
	end
	frame:SetUserPlaced(false)
end

function Sales:OpenPriceHistory(posting)
	if not self.history then self:BuildPriceHistory() end
	local frame = self.history
	if not frame:IsShown() then frame.detached = nil end
	frame.posting = posting
	frame:Show()
	self:DockPriceHistory()
	frame:Raise()
	self:RefreshPriceHistory()
end

local function historyDate(day, short)
	return date(short and "!%m-%d" or "!%Y-%m-%d", day * historyDaySeconds)
end

function Sales:RefreshPriceHistory()
	local frame = self.history
	if not frame or not frame:IsShown() then return end
	local itemID, name, quality
	if frame.posting then
		itemID, name = self.postHistoryItemID, self.postHistoryName
	else
		local control = self.panel.historyButton
		itemID, name = control.itemKey and control.itemKey.itemID, control.itemLabel
		quality = control.itemQuality
	end

	local market = not frame.posting and self.mode == "market" and self:GetBrowsingMarket()
		or self.market or (not self.open and factionMarket())
	local side = market and market:match(":([^:]+)$")
	local data = self:GetPriceHistory(itemID, market, frame.range)
	local icon = itemID and C_Item.GetItemIconByID(itemID)
	quality = quality or (itemID and cachedItemQuality(itemID))
	frame.icon:SetShown(itemID ~= nil)
	frame.icon.texture:SetTexture(icon or 134400)
	frame.item:SetText(name or L["vendorAuctionHistory"])
	paintItem(frame.item, quality)
	frame.market:SetText(itemID and side and browsingMarketLabel(market) or "")
	frame.latest:SetText(historyMoney(data.latest))
	frame.scanTime:SetText(itemID and data.scannedAt and self:FormatPriceDate(data.scannedAt) or "")
	frame.average:SetText(historyMoney(data.average))
	frame.coverage:SetText(itemID and L["vendorAuctionHistoryCoverage"]:format(data.observed) or "")
	for range, button in pairs(frame.ranges) do
		button:SetEnabled(range ~= frame.range)
	end

	local firstDay = data.today - frame.range + 1
	frame.first:SetText(historyDate(firstDay, true))
	frame.last:SetText(historyDate(data.today, true))
	frame.empty:SetText(L[itemID and "vendorAuctionHistoryEmpty" or "vendorAuctionHistorySelectItem"])
	frame.empty:SetShown(#data.points == 0)
	local low, high
	for _, point in ipairs(data.points) do
		low = math.min(low or point.price, point.price)
		high = math.max(high or point.price, point.price)
	end
	frame.high:SetPoint("TOPLEFT", 14, low == high and -205 or -173)
	frame.high:SetText(high and historyMoney(high) or "")
	frame.low:SetText(low ~= high and historyMoney(low) or "")
	for _, marker in ipairs(frame.markers) do marker:Hide() end
	for _, line in ipairs(frame.lines) do line:Hide() end

	local plot, previous, previousX, previousY = frame.plot
	local lineIndex = 0
	for index, point in ipairs(data.points) do
		local x = plot:GetWidth() * (point.day - firstDay) / (frame.range - 1)
		local y = plot:GetHeight() * (low == high and 0.5 or (point.price - low) / (high - low))
		local marker = frame.markers[index]
		if not marker then
			marker = CreateFrame("Button", nil, plot)
			marker:SetSize(9, 14)
			local dot = fill(marker, "ARTWORK", palette.accent)
			dot:SetSize(6, 6)
			dot:SetPoint("CENTER")
			marker:SetScript("OnEnter", function(buttonFrame)
				GameTooltip:SetOwner(buttonFrame, "ANCHOR_TOP")
				GameTooltip:SetText(historyDate(buttonFrame.point.day))
				GameTooltip:AddLine(historyMoney(buttonFrame.point.price))
				GameTooltip:AddLine(L["vendorAuctionHistoryScans"]:format(buttonFrame.point.scans), palette.muted[1], palette.muted[2], palette.muted[3])
				GameTooltip:Show()
			end)
			local function hideTooltip(buttonFrame)
				if GameTooltip:IsOwned(buttonFrame) then GameTooltip:Hide() end
			end
			marker:SetScript("OnLeave", hideTooltip)
			marker:SetScript("OnHide", hideTooltip)
			frame.markers[index] = marker
		end
		marker.point = point
		marker:SetPoint("CENTER", plot, "BOTTOMLEFT", x, y)
		marker:Show()
		if previous and point.day == previous.day + 1 then
			lineIndex = lineIndex + 1
			local line = frame.lines[lineIndex]
			if not line then
				line = plot:CreateLine(nil, "ARTWORK")
				line:SetThickness(2)
				line:SetColorTexture(unpack(palette.accent))
				frame.lines[lineIndex] = line
			end
			line:SetStartPoint("BOTTOMLEFT", plot, previousX, previousY)
			line:SetEndPoint("BOTTOMLEFT", plot, x, y)
			line:Show()
		end
		previous, previousX, previousY = point, x, y
	end
end

function Sales:UpdatePostPriceHistory()
	if not self.postHistoryButtons then return end
	self.postHistoryItemID, self.postHistoryName = nil, nil
	for sellFrame, control in pairs(self.postHistoryButtons) do
		local location = self.open and sellFrame:IsVisible() and sellFrame:GetItem()
		local itemID = location and C_Item.DoesItemExist(location) and C_Item.GetItemID(location)
		local hasItem = (not issecretvalue or not issecretvalue(itemID)) and type(itemID) == "number" and itemID > 0
		control:SetShown(hasItem)
		if hasItem then
			self.postHistoryItemID = itemID
			self.postHistoryName = C_Item.GetItemNameByID(itemID) or ("#" .. itemID)
		end
	end
	if self.history and self.history.posting then self:RefreshPriceHistory() end
end

function Sales:RegisterPostPriceHistory(frame)
	if self.postHistoryButtons then return end
	self.postHistoryButtons = {}
	local pending
	local function queueUpdate()
		if not self.open or pending then return end
		pending = true
		C_Timer.After(0, function()
			pending = nil
			self:UpdatePostPriceHistory()
		end)
	end
	for _, key in ipairs({ "ItemSellFrame", "CommoditiesSellFrame" }) do
		local sellFrame = frame[key]
		local display = sellFrame and sellFrame.ItemDisplay
		if display and sellFrame.SetItem and sellFrame.GetItem then
			local control = button(display, L["vendorAuctionHistory"], 145, function() self:OpenPriceHistory(true) end)
			control:SetHeight(20)
			control:SetPoint("TOPRIGHT", -8, -5)
			self.postHistoryButtons[sellFrame] = control
			hooksecurefunc(sellFrame, "SetItem", queueUpdate)
			sellFrame:HookScript("OnShow", queueUpdate)
			sellFrame:HookScript("OnHide", queueUpdate)
		end
	end
end

function Sales:BuildPanel()
	local panel = auctionWindow("EnhanceQoLAuctionSalesFrame", L["vendorAuctionSales"])
	panel:SetFrameStrata("DIALOG")
	panel:SetSize(panelWidth, panelHeight)
	panel:SetClampedToScreen(true)
	panel:SetMovable(true)
	panel:EnableMouse(true)
	panel:SetScript("OnShow", function()
		for _, event in ipairs(bagEvents) do self.events:RegisterEvent(event) end
		self.events:RegisterEvent("CURSOR_CHANGED")
	end)
	panel:SetScript("OnHide", function()
		for _, event in ipairs(bagEvents) do self.events:UnregisterEvent(event) end
		self.events:UnregisterEvent("CURSOR_CHANGED")
		self:UpdateWatchDropHint()
		self:StopQuickSell()
		self.search, self.status = nil, nil
		self.pendingWatchFind = nil
		self.marketCatalog = nil
		local history = self.history
		if history and history:IsShown() then
			if history.posting then self:DockPriceHistory() else history:Hide() end
		end
		GameTooltip:Hide()
	end)
	panel:Hide()
	self.panel = panel

	local header = CreateFrame("Frame", nil, panel)
	header:SetPoint("TOPLEFT", 20, 0)
	header:SetPoint("TOPRIGHT", -26, 0)
	header:SetHeight(20)
	header:EnableMouse(true)
	header:RegisterForDrag("LeftButton")
	header:SetScript("OnDragStart", function()
		panel.historyAnchor = nil
		panel:StartMoving()
	end)
	header:SetScript("OnDragStop", function()
		panel:StopMovingOrSizing()
		panel.moved = true
		self:DockPriceHistory()
	end)
	local scanButton = CreateFrame("Button", nil, panel)
	scanButton:SetSize(22, 22)
	scanButton:SetPoint("TOPRIGHT", -43, -26)
	scanButton:SetScript("OnClick", function(control) self:ChooseFullScan(control) end)
	local magnifier = scanButton:CreateTexture(nil, "ARTWORK")
	magnifier:SetAtlas("common-search-magnifyingglass")
	magnifier:SetSize(15, 15)
	magnifier:SetPoint("CENTER")
	magnifier:SetVertexColor(0.8, 0.8, 0.8)
	local scanHover = scanButton:CreateTexture(nil, "HIGHLIGHT")
	scanHover:SetAtlas("common-search-magnifyingglass")
	scanHover:SetAllPoints(magnifier)
	scanHover:SetBlendMode("ADD")
	panel.scanButton = scanButton
	scanButton:SetScript("OnEnter", function(control) self:ShowScanTooltip(control) end)
	scanButton:SetScript("OnLeave", function(control) if GameTooltip:IsOwned(control) then GameTooltip:Hide() end end)

	local scanBar = CreateFrame("StatusBar", nil, panel)
	scanBar:SetPoint("TOPLEFT", scanButton, "BOTTOMLEFT", 0, -1)
	scanBar:SetPoint("TOPRIGHT", scanButton, "BOTTOMRIGHT", 0, -1)
	scanBar:SetHeight(4)
	scanBar:SetStatusBarTexture(white)
	scanBar:SetStatusBarColor(unpack(palette.accent))
	scanBar:SetMinMaxValues(0, 100)
	local track = fill(scanBar, "BACKGROUND", palette.border)
	track:SetAllPoints()
	local pulse = CreateFrame("Frame", nil, scanBar)
	pulse:SetAllPoints()
	local segment = fill(pulse, "ARTWORK", palette.accent)
	segment:SetSize(8, 4)
	segment:SetPoint("LEFT")
	pulse:SetScript("OnUpdate", function(frame, elapsed)
		frame.phase = ((frame.phase or 0) + elapsed) % 1.6
		local offset = (scanBar:GetWidth() - 8) * (1 - math.abs(frame.phase / 0.8 - 1))
		segment:SetPoint("LEFT", offset, 0)
	end)
	scanBar.pulse = pulse
	panel.scanBar = scanBar
	self:UpdateScanDisplay()
	local settings = CreateFrame("Button", nil, panel)
	settings:SetSize(22, 22)
	settings:SetPoint("LEFT", scanButton, "RIGHT", 5, 0)
	local settingsIcon = settings:CreateTexture(nil, "ARTWORK")
	settingsIcon:SetAtlas("QuestLog-icon-setting")
	settingsIcon:SetSize(19, 19)
	settingsIcon:SetPoint("CENTER")
	local settingsHover = settings:CreateTexture(nil, "HIGHLIGHT")
	settingsHover:SetAtlas("QuestLog-icon-setting")
	settingsHover:SetAllPoints(settingsIcon)
	settingsHover:SetBlendMode("ADD")
	settings:SetScript("OnClick", function()
		if addon.functions.OpenConfigCenter then addon.functions.OpenConfigCenter("economy.auction-crafting", "vendorAuctionSales") end
	end)
	settings:SetScript("OnEnter", function(control)
		GameTooltip:SetOwner(control, "ANCHOR_TOP")
		GameTooltip:SetText(SETTINGS)
		GameTooltip:Show()
	end)
	settings:SetScript("OnLeave", GameTooltip_Hide)
	panel.settingsButton = settings

	local actions = CreateFrame("Frame", nil, panel)
	actions:SetHeight(26)
	actions:SetPoint("BOTTOMLEFT", 13, 12)
	actions:SetPoint("BOTTOMRIGHT", -13, 12)
	panel.sellActions = actions
	panel.quickButton = button(actions, L["vendorAuctionQuickSell"], 126, function()
		if self.quick then self:PostQuickSell() else self:StartQuickSell() end
	end)
	panel.quickButton:SetPoint("RIGHT")
	panel.quickButton:SetScript("OnEnter", function(control)
		GameTooltip:SetOwner(control, "ANCHOR_TOP")
		GameTooltip:SetText(L["vendorAuctionQuickTooltip"], 1, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	panel.quickButton:SetScript("OnLeave", GameTooltip_Hide)
	panel.quickStop = button(actions, CANCEL, 88, function() self:StopQuickSell() end)
	panel.quickStop:SetPoint("LEFT")
	panel.quickSkip = button(actions, L["vendorAuctionQuickSkip"], 108, function() self:SkipQuickSell() end)
	panel.quickSkip:SetPoint("RIGHT", panel.quickButton, "LEFT", -6, 0)
	panel.sellOne = button(actions, L["vendorAuctionQuickSingle"], 128, function() self:StartQuickSell(self.selected) end)
	panel.sellOne:SetPoint("RIGHT", panel.quickButton, "LEFT", -6, 0)
	panel.quickKeys = CreateFrame("Frame", nil, panel)
	panel.quickKeys:SetScript("OnKeyDown", function(keys, key)
		local active = self.quick and not InCombatLockdown() and not GetCurrentKeyBoardFocus() and not nativeDialogOpen()
		local handle = active and not IsModifierKeyDown() and (key == "SPACE" or key == "ESCAPE")
		keys:SetPropagateKeyboardInput(not handle)
		if not handle then return end
		if key == "ESCAPE" then
			self:StopQuickSell()
		elseif not keys.spaceDown then
			keys.spaceDown = true
			self:PostQuickSell()
		end
	end)
	panel.quickKeys:SetScript("OnKeyUp", function(keys, key)
		if key == "SPACE" then keys.spaceDown = nil end
	end)

	local sell = tab(panel, _G.AUCTION_HOUSE_FRAME_TITLE_SELL, 107, function() self:SetMode("sell") end)
	sell:SetPoint("TOPLEFT", 14, -52)
	local watch = tab(panel, L["vendorAuctionWatch"], 132, function() self:SetMode("watch") end)
	watch:SetPoint("LEFT", sell, "RIGHT", 6, 0)
	local market = tab(panel, L["vendorAuctionMarket"], 96, function()
		self:SetMode("market")
		panel.filter:SetFocus()
	end)
	market:SetPoint("LEFT", watch, "RIGHT", 6, 0)
	local more = tab(panel, "...", 36, function(control)
		if not _G.MenuUtil then return end
		_G.MenuUtil.CreateContextMenu(control, function(_, root)
			root:CreateButton(L["vendorAuctionExcluded"], function() self:SetMode("excluded") end)
			local advanced = root:CreateButton(L["vendorAuctionQuickFloor"])
			advanced:SetTooltip(function(tooltip) tooltip:AddLine(L["vendorAuctionQuickFloorTooltip"], 1, 1, 1, true) end)
			for _, percent in ipairs({ 0, 70, 80, 90, 100, 110, 125 }) do
				advanced:CreateRadio(percent == 0 and _G.OFF or ("%d%%"):format(percent), function()
					return (vendorDB().quickSellFloor or 0) == percent
				end, function()
					self:StopQuickSell()
					vendorDB().quickSellFloor = percent ~= 0 and percent or nil
					if self.search then self.search.offer = nil end
					self:Refresh()
				end)
			end
		end)
	end)
	more:SetPoint("TOPRIGHT", -14, -52)
	panel.sellTab, panel.watchTab, panel.marketTab, panel.more = sell, watch, market, more
	watch:SetScript("OnReceiveDrag", function() self:ReceiveWatchItem() end)
	watch:SetScript("OnEnter", function(control)
		if not control.readyCount or control.readyCount == 0 then return end
		GameTooltip:SetOwner(control, "ANCHOR_TOP")
		GameTooltip:SetText(L["vendorAuctionWatchReadyCount"]:format(control.readyCount))
		GameTooltip:Show()
	end)
	watch:SetScript("OnLeave", function(control)
		if GameTooltip:IsOwned(control) then GameTooltip:Hide() end
	end)

	local filter = CreateFrame("EditBox", nil, panel, "SearchBoxTemplate")
	filter:SetPoint("TOPLEFT", 18, -82)
	filter:SetPoint("TOPRIGHT", -16, -82)
	filter:SetHeight(24)
	filter:SetAutoFocus(false)
	filter:HookScript("OnEnterPressed", function(box) box:ClearFocus() end)
	filter:HookScript("OnTextChanged", function(box)
		local value = box:GetText()
		if not self.mode or value == (self.filters[self.mode] or "") then return end
		self.filters[self.mode] = value
		self:StopQuickSell()
		if self.mode == "market" then self.marketPage = 1 end
		panel.scrollBar:SetValue(0)
		self:Refresh()
	end)
	panel.filter = filter
	panel.marketButton = button(panel, "", 126, function(control) self:ChooseBrowsingMarket(control) end)
	panel.marketButton:SetPoint("TOPRIGHT", -12, -80)
	panel.marketCategory = button(panel, "", 166, function(control) self:ChooseMarketCategory(control) end)
	panel.marketCategory:SetHeight(24)
	panel.marketCategory:SetPoint("TOPLEFT", 12, -110)
	panel.marketQuality = button(panel, "", 112, function(control) self:ChooseMarketQuality(control) end)
	panel.marketQuality:SetHeight(24)
	panel.marketQuality:SetPoint("LEFT", panel.marketCategory, "RIGHT", 6, 0)
	local function pageButton(text, offset, step)
		local control = button(panel, text, 24, function()
			self.marketPage = self.marketPage + step
			panel.scrollBar:SetValue(0)
			self:Refresh()
		end)
		control:SetHeight(24)
		control:SetPoint("TOPRIGHT", offset, -110)
		return control
	end
	panel.marketPrevious = pageButton("<", -94, -1)
	panel.marketNext = pageButton(">", -12, 1)
	panel.marketPage = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	panel.marketPage:SetPoint("TOPRIGHT", -40, -117)
	panel.marketPage:SetWidth(50)
	panel.addWatch = button(panel, _G.ADD, 82, function()
		self:ResetWatchEditor(true)
		panel.input:SetFocus()
	end)
	panel.addWatch:SetPoint("TOPRIGHT", -14, -82)
	createList(panel, self)
	local function receiveItem()
		if self.mode == "watch" then self:ReceiveWatchItem() end
	end
	panel:SetScript("OnReceiveDrag", receiveItem)
	panel.list:EnableMouse(true)
	panel.list:SetScript("OnReceiveDrag", receiveItem)
	panel.scroll:EnableMouse(true)
	panel.scroll:SetScript("OnReceiveDrag", receiveItem)
	local detailCard = CreateFrame("Frame", nil, panel, "BackdropTemplate")
	paint(detailCard, palette.card)
	detailCard:SetPoint("TOPLEFT", panel.list, "BOTTOMLEFT", 0, -9)
	detailCard:SetPoint("BOTTOMRIGHT", -12, 12)
	panel.detailCard = detailCard
	local icon = CreateFrame("Frame", nil, detailCard, "BackdropTemplate")
	paint(icon, palette.panel)
	icon:SetSize(44, 44)
	icon:SetPoint("TOPLEFT", 9, -9)
	icon:SetFrameLevel(detailCard:GetFrameLevel() + 1)
	icon:EnableMouse(true)
	icon.texture = icon:CreateTexture(nil, "ARTWORK")
	icon.texture:SetPoint("TOPLEFT", 2, -2)
	icon.texture:SetPoint("BOTTOMRIGHT", -2, 2)
	icon.texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	icon:SetScript("OnEnter", function(control)
		if not control.itemID then return end
		GameTooltip:SetOwner(control, "ANCHOR_RIGHT")
		if control.link then GameTooltip:SetHyperlink(control.link) else GameTooltip:SetItemByID(control.itemID) end
		GameTooltip:Show()
	end)
	icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
	panel.detailIcon = icon

	panel.detail = label(detailCard, "GameFontHighlight", 62, -9)
	panel.detail:SetWidth(228)
	panel.detail:SetWordWrap(false)
	panel.quote = label(detailCard, "GameFontHighlightSmall", 62, -30)
	panel.quote:SetWidth(188)
	panel.quote:SetWordWrap(false)
	panel.status = label(detailCard, "GameFontHighlightSmall", 62, -47, palette.muted)
	panel.status:SetWidth(184)
	for index, field in ipairs({ "total", "budget" }) do
		local text = detailCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		text:SetPoint("TOPRIGHT", -9, -39 - (index - 1) * 17)
		text:SetWidth(144)
		text:SetJustifyH("RIGHT")
		text:SetWordWrap(false)
		text:SetTextColor(unpack(index == 1 and palette.text or palette.muted))
		panel[field] = text
	end
	panel.historyButton = button(detailCard, L["vendorAuctionHistory"], 150, function() self:OpenPriceHistory() end)
	panel.historyButton:SetPoint("BOTTOMLEFT", 8, 8)
	panel.restore = button(detailCard, REMOVE, 95, function()
		if self.excludedSelection then self:SetExcluded(self.excludedSelection, false) end
	end)
	panel.restore:SetPoint("BOTTOMRIGHT", -8, 8)

	panel.input = CreateFrame("EditBox", nil, detailCard, "BackdropTemplate")
	paint(panel.input, palette.panel)
	panel.input:SetFontObject(GameFontHighlightSmall)
	panel.input:SetTextInsets(6, 6, 0, 0)
	panel.input:SetAutoFocus(false)
	panel.input:SetSize(156, 24)
	panel.input:SetPoint("BOTTOMLEFT", 8, 65)
	panel.input:SetScript("OnReceiveDrag", receiveItem)
	panel.input:SetScript("OnTextChanged", function(box)
		if panel.save then panel.save:SetEnabled(self.watchKey ~= nil or box:GetText() ~= "") end
		self:UpdateWatchDropHint()
	end)
	panel.input:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
	panel.input:SetScript("OnEnterPressed", function(box) box:ClearFocus() end)
	local amount = CreateFrame("EditBox", nil, detailCard, "BackdropTemplate")
	paint(amount, palette.panel)
	amount:SetFontObject(GameFontHighlightSmall)
	amount:SetTextInsets(6, 6, 0, 0)
	amount:SetAutoFocus(false)
	amount:SetNumeric(true)
	amount:SetMaxLetters(7)
	amount:SetSize(72, 24)
	amount:SetPoint("BOTTOMLEFT", 179, 65)
	amount:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
	amount:SetScript("OnEnterPressed", function(box) box:ClearFocus() end)
	panel.amount = amount
	panel.amountLabel = label(detailCard, "GameFontHighlightSmall", 179, -72, palette.muted)
	panel.amountLabel:SetText(L["vendorAuctionWatchAmount"])
	panel.inputLabel = label(detailCard, "GameFontHighlightSmall", 8, -72, palette.muted)
	panel.inputLabel:SetText(L["vendorAuctionWatchItemInput"])
	panel.moneyLabel = label(detailCard, "GameFontHighlightSmall", 8, -131, palette.muted)
	panel.moneyLabel:SetText(L["vendorAuctionWatchLimit"])
	panel.money = CreateFrame("Frame", "EnhanceQoLAuctionWatchMoney", detailCard, "MoneyInputFrameTemplate")
	panel.money:SetPoint("BOTTOMLEFT", 8, 12)
	for _, field in ipairs({ panel.money.gold, panel.money.silver, panel.money.copper }) do
		for _, texture in pairs({ field.left, field.right, _G[field:GetName() .. "Middle"] }) do texture:Hide() end
		if not field.SetBackdrop then Mixin(field, BackdropTemplateMixin) end
		paint(field, palette.panel)
	end
	panel.save = button(detailCard, SAVE, 78, function()
		local input = panel.input:GetText()
		local itemID = self.watchKey and self.watchKey.itemID or tonumber(input:match("^%s*(%d+)%s*$") or input:match("item:(%d+)"))
		local limit = _G.MoneyInputFrame_GetCopper(panel.money)
		local quantity = panel.amount:GetNumber()
		if not itemID or itemID <= 0 or itemID > 2147483647 then
			self.status = L["vendorAuctionWatchInvalid"]
		else
			local key = self.watchKey or AH.MakeItemKey(itemID)
			if key and (AH.GetItemKeyInfo(key) or C_Item.DoesItemExistByID(itemID)) then
				local id = priceKey(key)
				local entry = {
					key = key, limit = limit > 0 and limit or nil, quantity = quantity > 0 and quantity or nil,
					exact = self.watchExact or false, link = self.watchLink,
				}
				watchList(true)[id] = entry
				self.watchKey, self.status, self.watchAdding = key, nil, nil
				panel.input:SetText("")
				self.alerts[id], self.watchResults[id] = nil, nil
				self:CheckWatch(entry)
			else
				self.status = L["vendorAuctionWatchInvalid"]
			end
		end
		self:Refresh()
	end)
	panel.save:SetPoint("BOTTOMRIGHT", -8, 8)
	panel.remove = button(detailCard, REMOVE, 95, function()
		if not self.watchKey then return end
		local list = watchList()
		local id = priceKey(self.watchKey)
		if list then list[id] = nil end
		self.watchResults[id], self.alerts[id] = nil, nil
		self:ResetWatchEditor()
	end)
	panel.remove:SetPoint("TOPRIGHT", -8, -8)
	amount:SetScript("OnTextChanged", function() self:UpdateWatchTotals() end)
	_G.MoneyInputFrame_SetOnValueChangedFunc(panel.money, function() self:UpdateWatchTotals() end)
	panel.watchInputDrop = watchDropHighlight(panel.input, receiveItem)
	panel.watchDrop = watchDropHighlight(panel.list, receiveItem)
end

function Sales:SelectWatchEntry(item)
	local panel = self.panel
	self.watchAdding = nil
	if self.pendingWatchFind and self.pendingWatchFind.entry ~= item then self.pendingWatchFind = nil end
	self.watchKey, self.watchExact, self.watchLink, self.status = item.key, item.exact, item.link, nil
	panel.input:SetText("")
	panel.amount:SetText(item.quantity and tostring(item.quantity) or "")
	_G.MoneyInputFrame_SetCopper(panel.money, item.limit or 0)
end

function Sales:ResetWatchEditor(adding)
	local panel = self.panel
	self.watchAdding = adding
	self.pendingWatchFind = nil
	self.watchKey, self.watchExact, self.watchLink, self.status = nil, nil, nil, nil
	panel.input:SetText("")
	panel.amount:SetText("")
	_G.MoneyInputFrame_SetCopper(panel.money, 0)
	self:Refresh()
end

function Sales:UpdateWatchTotals()
	local panel = self.panel
	if not panel or not panel.amount or not panel.money then return end
	local wanted = self.mode == "watch" and panel.amount:GetNumber() or 0
	local limit = wanted > 0 and _G.MoneyInputFrame_GetCopper(panel.money) or 0
	local result = wanted > 0 and self.watchKey and self.watchResults[priceKey(self.watchKey)]
	local total = result and purchaseTotal(result.tiers, wanted)
	local budget = limit > 0 and wanted * limit
	panel.total:SetText(total and L["vendorAuctionWatchTotal"]:format(coinText(total)) or "")
	panel.total:SetTextColor(unpack(total and budget and total > budget and palette.warning or palette.text))
	panel.budget:SetText(budget and L["vendorAuctionWatchBudget"]:format(coinText(budget)) or "")
end

function Sales:EditWatch(key, link, suggestedPrice, exact)
	if not self.panel or not self.panel:IsShown() then self:TogglePanel() end
	local panel = self.panel
	local watch = watchList()
	local entry = watch and watch[priceKey(key)]
	self.watchAdding = nil
	self.watchKey = AH.MakeItemKey(key.itemID, key.itemLevel, key.itemSuffix, key.battlePetSpeciesID)
	self.watchExact, self.watchLink = exact ~= false, link or (entry and entry.link)
	panel.input:SetText("")
	panel.amount:SetText(entry and entry.quantity and tostring(entry.quantity) or "")
	_G.MoneyInputFrame_SetCopper(panel.money, entry and (entry.limit or 0) or suggestedPrice or 0)
	self:SetMode("watch")
	panel.money.gold:SetFocus()
	panel.money.gold:HighlightText()
end

function Sales:ReceiveWatchItem()
	local kind, itemID, link = GetCursorInfo()
	if kind ~= "item" or not itemID then return end
	local location = _G.C_Cursor.GetCursorItem()
	local key = location and location:IsValid() and C_Item.DoesItemExist(location)
		and bagItemKey(location, itemID, AH.GetItemCommodityStatus(location) == Enum.ItemCommodityStatus.Commodity)
	self:EditWatch(key or AH.MakeItemKey(itemID), link, nil, key and true or false)
	ClearCursor()
	self:UpdateWatchDropHint()
	return true
end

function Sales:SetExcluded(entry, exclude)
	local itemID = entry.key.itemID
	local list = excludedItems(exclude)
	if exclude then
		self:StopQuickSell()
		list[itemID] = { key = entry.key, link = entry.link, icon = entry.icon, quality = entry.quality }
		if self.selected and self.selected.key.itemID == itemID then
			local location = ItemLocation:CreateFromBagAndSlot(self.selected.bag, self.selected.slot)
			local native = sellFrameFor(location:IsValid() and C_Item.DoesItemExist(location) and location or nil)
			if native and native:IsShown() and C_Item.GetItemGUID(location) == self.selected.guid and sameItem(location, native:GetItem()) and not InCombatLockdown() then
				AuctionHouseFrame:ClearPostItem()
			end
			self.selected, self.search = nil, nil
		end
	elseif list then
		list[itemID] = nil
		self.excludedSelection = nil
	end
	self:Refresh(true)
	refreshBagValue()
end

function Sales:OpenExclusionMenu(owner, entry, exclude)
	if not _G.MenuUtil then return end
	_G.MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateButton(exclude and L["vendorAuctionExclude"] or REMOVE, function() self:SetExcluded(entry, exclude) end)
	end)
end

function Sales:RegisterWatchMenu()
	if self.watchMenuRegistered or not (_G.Menu and _G.Menu.ModifyMenu) then return end
	self.watchMenuRegistered = true
	_G.Menu.ModifyMenu("MENU_AUCTION_HOUSE_FAVORITE", function(owner, description)
		if not addon.db.vendorAuctionSales or not self.open or InCombatLockdown() then return end
		local row = owner.GetRowData and owner:GetRowData()
		local key = (row and row.itemKey) or (owner.GetItemKey and owner:GetItemKey())
		if not key or not key.itemID then return end

		-- Browse rows are recycled when the result list scrolls or refreshes.
		local itemKey = AH.MakeItemKey(key.itemID, key.itemLevel, key.itemSuffix, key.battlePetSpeciesID)
		local watch = watchList()
		local text = watch and watch[priceKey(itemKey)] and L["vendorAuctionWatchEdit"] or L["vendorAuctionWatchAdd"]
		local suggestion = row and (row.minPrice or row.unitPrice or row.buyoutAmount)
		local link = row and row.itemLink
		description:CreateDivider()
		description:CreateTitle("EnhanceQoL")
		description:CreateButton(text, function()
			if addon.db.vendorAuctionSales and self.open and AuctionHouseFrame:IsShown() and not InCombatLockdown() then
				self:EditWatch(itemKey, link, suggestion)
			end
		end)
	end)
end

function Sales:SetMode(mode)
	self:StopQuickSell()
	self.mode, self.search, self.status = mode, nil, nil
	self.pendingWatchFind = nil
	self.panel.filter:SetText(self.filters[mode] or "")
	self.panel.scrollBar:SetValue(0)
	self:Refresh(mode == "sell")
end

function Sales:Refresh(rebuild)
	local panel = self.panel
	if not panel or not panel:IsShown() then
		self:RefreshPriceHistory()
		return
	end
	local selling = self.mode == "sell"
	local watching = self.mode == "watch"
	local browsing = self.mode == "market"
	local excluding = self.mode == "excluded"
	local filter = self.filters[self.mode] or ""
	local market = browsing and self:GetBrowsingMarket()
	if browsing and self.marketSelection and self.marketSelection.market ~= market then self.marketSelection = nil end
	if selling and rebuild then getBagRows(self.bags) end
	if self.selected and not locationFor(self.selected) then
		if self.search and self.search.row then self.search = nil end
		self.selected = nil
	end

	local items, missingNames = selling and groupBagRows(self.bags) or self.bags
	if browsing then
		items, missingNames = self:GetScannedItems(market, filter, self.marketCategory, self.marketQuality)
	elseif not selling then
		items = {}
		local entries = watching and (watchList() or {}) or (excludedItems() or {})
		for _, entry in pairs(entries) do
			local info = AH.GetItemKeyInfo(entry.key)
			local id = priceKey(entry.key)
			items[#items + 1] = {
				entry = entry, name = info and info.itemName or nameFor(entry.key), info = info, id = id,
				ready = watching and watchReady(entry, self.watchResults[id]) and true or false,
			}
		end
	end
	local sorting = self.sorts[self.mode]
	local catalog = browsing and self.marketCatalog
	if catalog and catalog.results == items then
		if catalog.sortedSource ~= items or catalog.sorting ~= sorting then
			catalog.sortedSource, catalog.sorting = items, sorting
			catalog.sorted = filteredRows(items, false, "", sorting)
		end
		items = catalog.sorted
	elseif not browsing then
		items = filteredRows(items, selling, filter, sorting)
	end
	local pages = browsing and math.max(1, math.ceil(#items / marketPageSize)) or 1
	local first = 0
	if browsing then
		self.marketPage = math.min(self.marketPage or 1, pages)
		first = (self.marketPage - 1) * marketPageSize
	end
	local visible = browsing and math.min(marketPageSize, #items - first) or #items
	local watchSearchAvailable = watching and self.open == true
	local rowOffer = self.quick and self.quick.offer or (not self.quick and self.search and self.search.offer)
	if rowOffer and (not rowOffer.price or rowOffer.expires <= GetTime()) then rowOffer = nil end
	local offerKey = rowOffer and self.selected and priceKey(self.selected.key)
	local columnInset = watchSearchAvailable and watchActionInset or 0
	for index = 1, visible do
		local result = items[first + index]
		local entry = result.row
		local row = panel.rows[index]
		if not row then
			row = CreateFrame("Button", nil, panel.content)
			row:SetSize(panelWidth - 48, rowHeight)
			row:SetPoint("TOPLEFT", 0, -(index - 1) * rowHeight)
			row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
			row:SetScript("OnReceiveDrag", function()
				if self.mode == "watch" then self:ReceiveWatchItem() end
			end)
			row:SetScript("OnClick", function(control, mouseButton)
				local item = control.entry
				if self.mode == "sell" then
					if mouseButton == "RightButton" then
						self:OpenExclusionMenu(control, item, true)
					else
						self.status = nil
						self:SelectBag(item.stacks[1])
					end
				elseif self.mode == "market" then
					if mouseButton == "RightButton" then return end
					self.marketSelection = item
					self:Refresh()
					self:OpenPriceHistory()
					if not item.count and not item.limit and self.history.range == 7 then
						self.history.range = historyDays
						self:RefreshPriceHistory()
					end
				elseif self.mode == "excluded" then
					if mouseButton == "RightButton" then
						self:OpenExclusionMenu(control, item, false)
					else
						self.excludedSelection = item
						self:Refresh()
					end
				elseif not self:ReceiveWatchItem() then
					self:SelectWatchEntry(item)
					self:Refresh()
				end
			end)
			row.bg = fill(row, "BACKGROUND", palette.row)
			row.bg:SetAllPoints()
			local hover = fill(row, "HIGHLIGHT", palette.hover)
			hover:SetAllPoints()
			row:SetHighlightTexture(hover)
			row.marker = fill(row, "ARTWORK", palette.accent)
			row.marker:SetPoint("TOPLEFT", 0, -1)
			row.marker:SetPoint("BOTTOMLEFT", 0, 1)
			row.marker:SetWidth(2)
			row.icon = row:CreateTexture(nil, "ARTWORK")
			row.icon:SetSize(24, 24)
			row.icon:SetPoint("LEFT", 10, 0)
			row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			row.vendorWarning = row:CreateTexture(nil, "OVERLAY")
			row.vendorWarning:SetTexture("Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew")
			row.vendorWarning:SetSize(15, 15)
			row.vendorWarning:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", 3, -2)
			row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			row.name:SetPoint("LEFT", rowNameLeft, 0)
			row.name:SetJustifyH("LEFT")
			row.name:SetWordWrap(true)
			row.name:SetMaxLines(2)
			row.count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			row.count:SetPoint("RIGHT", -rowQuantityRight, 0)
			row.count:SetTextColor(unpack(palette.text))
			row.price = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			row.price:SetPoint("RIGHT", -rowPriceRight, 0)
			row.available = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			row.available:SetPoint("BOTTOMRIGHT", -rowPriceRight, 4)
			row.available:SetText(L["vendorAuctionWatchBuyable"])
			row.available:SetTextColor(unpack(palette.good))
			row.find = button(row, L["vendorAuctionWatchBuySearch"], watchActionWidth, function()
				if self.mode ~= "watch" or not self.open then return end
				self:SelectWatchEntry(row.entry)
				self:SearchWatchedItem()
			end)
			row.find:SetHeight(22)
			row.find:SetPoint("RIGHT", -6, 0)
			row:SetScript("OnEnter", function(control)
				GameTooltip:SetOwner(control, "ANCHOR_RIGHT")
				if control.entry.link then GameTooltip:SetHyperlink(control.entry.link) else GameTooltip:SetItemByID(control.entry.key.itemID) end
				if control.vendorNotice then GameTooltip:AddLine(control.vendorNotice, palette.warning[1], palette.warning[2], palette.warning[3], true) end
				GameTooltip:Show()
			end)
			row:SetScript("OnLeave", function() GameTooltip:Hide() end)
			panel.rows[index] = row
		end
		row.entry = selling and entry or entry.entry
		local reached = watching and entry.ready
		row.find:SetShown(watchSearchAvailable)
		row.available:SetShown(reached and true or false)
		row.available:SetPoint("BOTTOMRIGHT", -rowPriceRight - columnInset, 4)
		row.count:SetPoint("RIGHT", -rowQuantityRight - columnInset, 0)
		row.price:SetPoint("RIGHT", -rowPriceRight - columnInset, reached and 6 or 0)
		local highlight
		row.vendorNotice = nil
		if selling then
			local price = offerKey == priceKey(entry.key) and rowOffer.price or self:GetListingPrice(entry.key)
			local vendor = vendorUnitPrice(entry.link)
			local belowVendor = price and vendor and price < vendor
			if belowVendor then row.vendorNotice = L["vendorAuctionQuickBelowVendor"]:format(coinText(price), coinText(vendor)) end
			row.name:SetWidth(195)
			row.name:SetText(itemLabel(entry.link, entry.key))
			paintItem(row.name, entry.quality)
			row.icon:SetTexture(entry.icon)
			row.count:SetText(entry.count)
			row.price:SetTextColor(unpack(belowVendor and palette.warning or price and palette.text or palette.dim))
			row.price:SetText(price and coinText(price) or "—")
			highlight = self.selected and priceKey(self.selected.key) == priceKey(entry.key)
		elseif browsing then
			local item = entry.entry
			row.name:SetWidth(152)
			row.name:SetText(entry.name)
			paintItem(row.name, item.quality)
			row.icon:SetTexture(C_Item.GetItemIconByID(item.key.itemID) or 134400)
			row.count:SetText(historyMoney(item.count))
			row.price:SetTextColor(unpack(item.limit and palette.accent or palette.dim))
			row.price:SetText(historyMoney(item.limit))
			highlight = self.marketSelection and self.marketSelection.key.itemID == item.key.itemID
			if highlight then self.marketSelection = item end
		else
			local item = entry.entry
			row.name:SetWidth(watchSearchAvailable and 112 or watching and 195 or 320)
			row.name:SetText(itemLabel(item.link, item.key, entry.name))
			paintItem(row.name, item.quality or (entry.info and entry.info.quality))
			row.icon:SetTexture(item.icon or (entry.info and entry.info.iconFileID) or C_Item.GetItemIconByID(item.key.itemID))
			if watching then
				row.count:SetText(item.quantity or "—")
				row.price:SetTextColor(unpack(palette.text))
				row.price:SetText(item.limit and coinText(item.limit) or L["vendorAuctionWatchAnyPrice"])
				highlight = self.watchKey and priceKey(self.watchKey) == entry.id
			else
				row.count:SetText("")
				row.price:SetText("")
				highlight = self.excludedSelection == item
			end
		end
		row.vendorWarning:SetShown(row.vendorNotice ~= nil)
		row.marker:SetShown(highlight or reached or false)
		row.marker:SetColorTexture(unpack(reached and palette.good or palette.accent))
		row.bg:SetColorTexture(unpack(highlight and palette.selected or reached and palette.ready or (index % 2 == 0 and palette.alternate or palette.row)))
		row:Show()
	end
	for index = visible + 1, #panel.rows do panel.rows[index]:Hide() end
	local selected = selling and self.selected or (browsing and self.marketSelection) or (excluding and self.excludedSelection) or nil
	local hasWatchItem = watching and self.watchKey ~= nil
	local sellStatus = selling and (self.quick or self.status) or nil
	panel.detailCard:SetShown(watching or selected ~= nil or sellStatus ~= nil)
	panel.list:SetPoint("TOPLEFT", 12, browsing and -142 or -114)
	local actionsVisible = selling and self.open == true
	local footerInset = panel.footerButton and 29 or 0
	local bottomInset = footerInset + (actionsVisible and 30 or 0)
	panel.sellActions:SetShown(actionsVisible)
	panel.sellActions:SetPoint("BOTTOMLEFT", 13, 12 + footerInset)
	panel.sellActions:SetPoint("BOTTOMRIGHT", -13, 12 + footerInset)
	panel.detailCard:SetPoint("BOTTOMRIGHT", -12, 12 + bottomInset)
	panel.list:SetPoint("BOTTOMRIGHT", -12, bottomInset
		+ (watching and (hasWatchItem and 180 or 198) or ((selected or sellStatus) and (browsing and 118 or 127) or 12)))
	panel.content:SetHeight(math.max(1, visible * rowHeight))
	updateScrollRange(panel)
	panel.columnQuantity:SetShown(not excluding)
	panel.columnPrice:SetShown(not excluding)
	panel.columnQuantity:SetPoint("TOPRIGHT", -rowGutter - rowQuantityRight - columnInset, -1)
	panel.columnPrice:SetPoint("TOPRIGHT", -rowGutter - rowPriceRight - columnInset, -1)
	showSort(panel.columnItem, _G.AUCTION_HOUSE_HEADER_ITEM or L["vendorAuctionItemID"], "name", sorting)
	showSort(panel.columnQuantity, (browsing and L["vendorAuctionMarketLatest"]) or (watching and L["vendorAuctionWatchWanted"]) or (_G.AUCTION_HOUSE_QUANTITY_LABEL or L["Amount"]), "quantity", sorting)
	showSort(panel.columnPrice, (browsing and L["vendorAuctionHistoryAverage"]) or (selling and _G.AUCTION_HOUSE_HEADER_UNIT_PRICE) or L["vendorAuctionTarget"], "price", sorting)
	panel.empty:SetShown(#items == 0)
	panel.empty:SetText((catalog and self.marketQuality ~= nil and catalog.missingQuality and L["vendorAuctionMarketUnknownQuality"])
		or (browsing and missingNames and L["vendorAuctionMarketUnknownNames"])
		or ((filter:find("%S") or (browsing and (self.marketCategory or self.marketQuality ~= nil))) and L["vendorAuctionNoMatches"])
		or (browsing and L["vendorAuctionMarketSearch"]) or (selling and L["vendorAuctionEmpty"])
		or (watching and L["vendorAuctionWatchEmpty"]) or L["vendorAuctionExcludedEmpty"])

	local key = selected and selected.key or (watching and self.watchKey)
	local search = self.search
	local quote = (selling or watching) and formatQuote(key) or ""
	if selling and rowOffer then
		quote = (_G.AUCTION_HOUSE_HEADER_UNIT_PRICE or L["Amount"]) .. "  " .. coinText(rowOffer.price)
	end
	local detail = (browsing and selected and selected.name) or (key and itemLabel(selected and selected.link or (watching and self.watchLink), key))
	local status = self.status or (selling and search and ((not self.quick and search.offer and search.offer.message) or search.status))
	if browsing and selected and selected.scannedAt then status = self:FormatPriceDate(selected.scannedAt) end
	if watching and not status and key then
		local result = self.watchResults[priceKey(key)]
		local list = watchList()
		local entry = list and list[priceKey(key)]
		if result and entry then
			if result.failed then
				status = L["vendorAuctionTimedOut"]
			elseif entry.limit then
				status = L["vendorAuctionWatchAtTarget"]:format(result.matched)
			else
				status = L["vendorAuctionWatchAvailable"]:format(result.matched)
			end
		end
	end
	local icon = panel.detailIcon
	icon.itemID, icon.link = key and key.itemID, selected and selected.link or (watching and self.watchLink)
	local keyInfo = key and AH.GetItemKeyInfo(key)
	icon:SetShown(key and true or false)
	if key then icon.texture:SetTexture((selected and selected.icon) or (keyInfo and keyInfo.iconFileID) or C_Item.GetItemIconByID(key.itemID)) end
	panel.detail:SetText(detail or "")
	paintItem(panel.detail, browsing and selected and selected.quality)
	self:UpdateWatchTotals()
	panel.quote:SetText(quote)
	panel.status:SetText(status or "")
	panel.status:SetWidth(selling and 325 or 184)
	panel.quickButton:SetShown(selling and self.open == true)
	panel.quickButton:SetText(L[self.quick and "vendorAuctionQuickPost" or "vendorAuctionQuickSell"])
	panel.quickButton:SetEnabled(not self.quickPost and (self.quick and self.quick.offer ~= nil or not self.quick and #items > 0))
	panel.quickStop:SetShown(selling and self.quick ~= nil)
	panel.quickSkip:SetShown(selling and self.quick ~= nil)
	panel.quickSkip:SetEnabled(self.quick and self.quick.row ~= nil and not self.quickPost or false)
	panel.sellOne:SetShown(selling and self.open == true and not self.quick and selected ~= nil)
	panel.sellOne:SetEnabled(not self.quickPost)
	selectTab(panel.sellTab, selling)
	selectTab(panel.watchTab, watching)
	selectTab(panel.marketTab, browsing)
	selectTab(panel.more, excluding)
	self:UpdateWatchTab()
	panel.filter:SetPoint("TOPRIGHT", (browsing and -146) or (watching and -104) or -16, -82)
	if panel.filter.Instructions then panel.filter.Instructions:SetText(browsing and L["vendorAuctionMarketSearch"] or _G.SEARCH) end
	panel.marketButton:SetText(browsingMarketLabel(market))
	panel.marketButton:SetShown(browsing)
	panel.marketCategory:SetText(self.marketCategory and self.marketCategory.name or L["vendorAuctionMarketAllCategories"])
	panel.marketCategory:SetShown(browsing)
	panel.marketQuality:SetText(marketQualityLabel(self.marketQuality))
	panel.marketQuality:SetShown(browsing)
	panel.marketPrevious:SetShown(browsing and pages > 1)
	panel.marketNext:SetShown(browsing and pages > 1)
	panel.marketPage:SetShown(browsing and pages > 1)
	if browsing then
		panel.marketPrevious:SetEnabled(self.marketPage > 1)
		panel.marketNext:SetEnabled(self.marketPage < pages)
		panel.marketPage:SetText(("%d / %d"):format(self.marketPage, pages))
	end
	panel.addWatch:SetShown(watching)
	panel.addWatch:SetEnabled(not self.watchAdding)
	local historyButton = panel.historyButton
	historyButton.itemKey = (selling or watching or browsing) and key or nil
	historyButton.itemLabel = historyButton.itemKey and detail or nil
	historyButton.itemQuality = browsing and selected and selected.quality
	historyButton:SetShown(historyButton.itemKey ~= nil)
	panel.restore:SetShown(excluding)
	panel.restore:SetEnabled(self.excludedSelection ~= nil)
	panel.input:SetShown(watching and not hasWatchItem)
	panel.inputLabel:SetShown(watching and not hasWatchItem)
	panel.amount:SetPoint("BOTTOMLEFT", hasWatchItem and 8 or 179, hasWatchItem and 39 or 65)
	panel.amountLabel:SetPoint("TOPLEFT", hasWatchItem and 8 or 179, hasWatchItem and -84 or -72)
	panel.money:SetPoint("BOTTOMLEFT", hasWatchItem and 114 or 8, hasWatchItem and 42 or 12)
	panel.moneyLabel:SetPoint("TOPLEFT", hasWatchItem and 114 or 8, hasWatchItem and -84 or -131)
	panel.amount:SetShown(watching)
	panel.amountLabel:SetShown(watching)
	panel.moneyLabel:SetShown(watching)
	panel.money:SetShown(watching)
	panel.save:SetShown(watching)
	panel.save:SetEnabled(hasWatchItem or panel.input:GetText() ~= "")
	local list = watching and watchList()
	local savedWatchItem = list and key and list[priceKey(key)] ~= nil or false
	panel.remove:SetShown(savedWatchItem)
	self:UpdateWatchDropHint()
	self:RefreshPriceHistory()
	self:QueueVisibleMarketNames()
end

function Sales:SetFooterButton(button)
	local panel = self.panel
	panel.footerButton = button
	button:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 13, 10)
	self:Refresh()
end

function Sales:TogglePanel()
	if not self:IsEnabled() then return end
	if not self.panel then self:BuildPanel() end
	local panel = self.panel
	if panel:IsShown() then panel:Hide() return end
	local auction = self.open and AuctionHouseFrame and AuctionHouseFrame:IsShown() and AuctionHouseFrame
	panel.baseHeight = auction and (auction:GetHeight() * auction:GetEffectiveScale() / panel:GetEffectiveScale()) or panelHeight
	panel:SetHeight(panel.baseHeight)
	if not panel.moved then
		panel:ClearAllPoints()
		local shopper = addon.Vendor.CraftShopper and addon.Vendor.CraftShopper.frame
		if not self.open or not AuctionHouseFrame or not AuctionHouseFrame:IsShown() then
			panel:SetPoint("CENTER", UIParent)
		elseif shopper and shopper:IsShown() then
			panel:SetPoint("TOPRIGHT", AuctionHouseFrame, "TOPLEFT", -5, 0)
		else
			panel:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", 5, 0)
		end
	end
	panel:Show()
	if self.history and self.history:IsShown() then self:DockPriceHistory() end
	self:UpdateScanDisplay()
	self:SetMode(self.mode or "sell")
end

function Sales:Close()
	self:StopQuickSell()
	self.quickPost = nil
	self:StopFullScan()
	self.open = nil
	self.foreignScanPendingUntil = nil
	self.confirmedMarketSide = nil
	self.market, self.selected, self.search, self.status = nil, nil, nil, nil
	self.watchSearch = nil
	self.pendingWatchFind = nil
	if self.watchTicker then
		self.watchTicker:Cancel()
		self.watchTicker = nil
	end
	if self.events then
		for _, event in ipairs(searchEvents) do self.events:UnregisterEvent(event) end
		for _, event in ipairs(quickEvents) do self.events:UnregisterEvent(event) end
		for _, event in ipairs(browseEvents) do self.events:UnregisterEvent(event) end
		self.events:UnregisterEvent("REPLICATE_ITEM_LIST_UPDATE")
	end
	wipe(self.watchQueue)
	wipe(self.watchRetries)
	wipe(self.watchResults)
	wipe(self.alerts)
	wipe(self.live)
	wipe(self.bags)
	if self.history then self.history:Hide() end
	self:UpdatePostPriceHistory()
	if self.panel then self.panel:Hide() end
	if self.launch then self.launch:Hide() end
end

function Sales:Open()
	local frame = AuctionHouseFrame
	if not frame or not frame:IsShown() then return end
	self:RegisterWatchMenu()
	self:RegisterPostPriceHistory(frame)
	if not self.open then
		self.open = true
		self.market = marketForSide(self:GetConfirmedMarketSide()) or marketKey()
		for _, event in ipairs(searchEvents) do self.events:RegisterEvent(event) end
		for _, event in ipairs(quickEvents) do self.events:RegisterEvent(event) end
		for _, event in ipairs(browseEvents) do self.events:RegisterEvent(event) end
		self.events:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
		self:QueueWatchList()
		self:UpdateScanDisplay()
		self:UpdatePostPriceHistory()
		self:Refresh(true)
	end
	if not self.launch then
		self.launch = button(frame, L["vendorAuctionSales"], 165, function() self:TogglePanel() end)
		self.launch:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, -3)
	end
	self.launch:Show()
end

function Sales:OnEvent(event, arg, success)
	if event == "AUCTION_HOUSE_SHOW" then
		C_Timer.After(0, function()
			if addon.db.vendorAuctionSales then self:Open() end
		end)
	elseif event == "AUCTION_HOUSE_CLOSED" then
		self:Close()
	elseif event == "AUCTION_HOUSE_AUCTION_CREATED" then
		if self.quickPost then
			if self.quick then
				self.quickPost.confirmed = true
			else
				self.quickPost = nil
				self:Refresh(true)
			end
		end
	elseif event == "AUCTION_HOUSE_SHOW_ERROR" or event == "AUCTION_HOUSE_POST_ERROR" then
		if self.quick or self.quickPost then
			self.quickPost = nil
			if self.quick then self:StopQuickSell(L["vendorAuctionQuickStopped"]) else self:Refresh() end
		end
	elseif event == "PLAYER_REGEN_DISABLED" then
		self:StopQuickSell(L["vendorAuctionQuickStopped"])
	elseif event == "CURSOR_CHANGED" then
		self:UpdateWatchDropHint()
	elseif event == "REPLICATE_ITEM_LIST_UPDATE" then
		if self.open and self.foreignScanPendingUntil and GetTime() < self.foreignScanPendingUntil
			and AH.GetNumReplicateItems and AH.GetNumReplicateItems() > 0 then
			self.foreignScanPendingUntil = nil
			self:RecordFullScanResponse()
			local side = self:GetConfirmedMarketSide()
			local market = side and marketForSide(side)
			if market and AH.GetReplicateItemInfo then
				self:InterruptBrowseScan()
				if self.fullScan then self:StopFullScan() end
				self.fullScan = { side = side, market = market, passive = true }
				self:ReadFullScan()
			else
				self:UpdateScanDisplay()
			end
		end
	elseif event:find("^AUCTION_HOUSE_BROWSE_") then
		self:ReadBrowseResults(event, arg)
	elseif event == "BAG_UPDATE_DELAYED" or event == "ITEM_DATA_LOAD_RESULT" or event == "ITEM_LOCK_CHANGED" then
		if event == "ITEM_DATA_LOAD_RESULT" then self:OnMarketItemData(arg, success) end
		if self.mode ~= "sell" or self.bagsDirty or not self.panel or not self.panel:IsShown() then return end
		self.bagsDirty = true
		C_Timer.After(0, function()
			self.bagsDirty = nil
			if self.mode == "sell" then self:Refresh(true) end
		end)
	else
		self:ReadResults(event, arg)
		self:ReadWatchResults(event, arg)
	end
end

function Sales:ApplySettings()
	local bags = addon.Bags and addon.Bags.functions
	if bags and bags.RefreshAuctionValueSettings then bags.RefreshAuctionValueSettings() end
	if not self:IsEnabled() then
		if self.events then self.events:UnregisterAllEvents() end
		self.qualityQueue, self.requestedQualities = nil, nil
		self:Close()
		refreshBagValue()
		return
	end
	migrateMarketKeys()
	prunePrices()
	pruneAuctionHistory(historyDay(GetServerTime()))
	self:RegisterSnapshotTooltip()
	if AH.ReplicateItems and not self.replicationHooked then
		self.replicationHooked = true
		hooksecurefunc(AH, "ReplicateItems", function() self:ObserveFullScanRequest() end)
	end
	if AH.SendBrowseQuery and AH.GetBrowseResults and AH.HasFullBrowseResults and not self.browseHooked then
		self.browseHooked = true
		hooksecurefunc(AH, "SendBrowseQuery", function(query) self:ObserveBrowseQuery(query) end)
		for _, method in ipairs({ "SearchForFavorites", "SearchForItemKeys", "SendSearchQuery", "SendSellSearchQuery" }) do
			if AH[method] then hooksecurefunc(AH, method, function() self:InterruptBrowseScan() end) end
		end
		if AH.RequestMoreBrowseResults then
			hooksecurefunc(AH, "RequestMoreBrowseResults", function()
				local scan = self.fullScan
				if scan and scan.browse then scan.requestMore = nil end
			end)
		end
	end
	self:UpdateScanDisplay()
	if not self.events then
		self.events = CreateFrame("Frame")
		self.events:SetScript("OnEvent", function(_, event, ...) self:OnEvent(event, ...) end)
	end
	self.events:RegisterEvent("AUCTION_HOUSE_SHOW")
	self.events:RegisterEvent("AUCTION_HOUSE_CLOSED")
	self.events:RegisterEvent("ITEM_DATA_LOAD_RESULT")
	self:Open()
	self:Refresh(true)
	refreshBagValue()
end

function Sales:Initialize()
	if self.initialized then return end
	self.initialized = true
	self:ApplySettings()
end

if SlashCmdList then
	_G.SLASH_EQOLAUCTION1 = "/eqolauction"
	SlashCmdList.EQOLAUCTION = function() Sales:TogglePanel() end
end
