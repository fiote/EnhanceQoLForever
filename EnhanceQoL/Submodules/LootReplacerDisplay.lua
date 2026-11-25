local addonName, addon = ...
local L = LibStub("AceLocale-3.0"):GetLocale(addonName)
local Loot = addon.LootReplacer
local EditMode = addon.EditMode
local ID = "floatingLoot"
local WHITE_TEXTURE = "Interface\\Buttons\\WHITE8x8"
local MAX_RECEIPT_ROWS = 10

local defaults = {
	point = "TOPLEFT", relativePoint = "CENTER", x = 170, y = 60,
	width = 320, scale = 1, rowHeight = 36, iconSize = 24, spacing = 3, sectionSpacing = 9,
	rowSide = "LEFT",
	font = "", fontSize = 13, outline = addon.functions.GetGlobalFontStyleConfigKey(), quality = true,
	textAlign = "LEFT", textX = 0, textY = 0, textClassColor = false,
	textColor = { r = 0.94, g = 0.92, b = 0.88, a = 1 },
	background = { r = 0.045, g = 0.055, b = 0.075, a = 0.86 },
	backgroundEnabled = true, backgroundTexture = "", backgroundInset = 0, backgroundClassColor = false,
	border = true, borderTexture = "", accentSide = "LEFT", borderSize = 2, borderOffset = 0, borderColorMode = "QUALITY",
	borderColor = { r = 0.94, g = 0.92, b = 0.88, a = 0.8 },
	animate = true, fadeIn = 140, fadeOut = 100,
	received = true, receivedMaxRows = 3, receivedDuration = 3.5, receivedRise = 12,
	receivedItems = true, receivedMoney = true, receivedCurrencies = true, receivedReputation = true, receivedQuestXP = true,
	receivedSkillUps = false,
	buttonSize = 22, timer = true,
	timerHeight = 1, timerText = false, timerFont = "", timerOutline = addon.functions.GetGlobalFontStyleConfigKey(),
	timerFontSize = 12, timerTextColor = { r = 0.94, g = 0.92, b = 0.88, a = 1 },
}

local function layoutConfig()
	local layouts = addon.db.floatingLootLayouts
	if type(layouts) ~= "table" then
		layouts = {}
		addon.db.floatingLootLayouts = layouts
	end
	local index = EditMode.lib:GetActiveLayoutIndex() or 0
	local config = layouts[index]
	if type(config) ~= "table" then
		config = {}
		layouts[index] = config
	end
	for key, value in pairs(defaults) do
		if type(config[key]) ~= type(value) then config[key] = type(value) == "table" and CopyTable(value) or value end
	end
	config.receivedMaxRows = math.max(1, math.min(MAX_RECEIPT_ROWS, math.floor(config.receivedMaxRows)))
	return config
end

function Loot:ApplyDisplayLayout()
	if self.resettingDisplay then return end
	local config = layoutConfig()
	self.config = config
	local kept = 0
	if config.received then
		for _, receipt in ipairs(self.receipts) do
			if config[receipt.category] then
				kept = kept + 1
				self.receipts[kept] = receipt
			end
		end
	end
	for index = #self.receipts, kept + 1, -1 do self.receipts[index] = nil end
	self.anchor:ClearAllPoints()
	self.anchor:SetPoint(config.point, UIParent, config.relativePoint, config.x, config.y)
	self:Render()
end

local choices = {
	{ id = 1, label = NEED, icon = "lootroll-toast-icon-need-up" },
	{ id = 2, label = GREED, icon = "lootroll-toast-icon-greed-up" },
	{ id = 3, label = ROLL_DISENCHANT or _G.DISENCHANT, texture = "Interface\\Buttons\\UI-GroupLoot-DE-Up" },
	{ id = 4, label = _G.TRANSMOGRIFICATION, icon = "lootroll-toast-icon-transmog-up" },
	{ id = 0, label = PASS, icon = "lootroll-toast-icon-pass-up" },
}

local function getClassColor()
	local class = addon.variables.unitClass
	if not class then return end
	return (C_ClassColor and C_ClassColor.GetClassColor(class)) or RAID_CLASS_COLORS[class]
end

local function font(text, cfg, color, size)
	addon.functions.ApplyFontString(text, cfg.font, size or cfg.fontSize, cfg.outline, nil, defaults.outline)
	color = color or cfg.textColor
	text:SetTextColor(color.r, color.g, color.b, cfg.textColor.a)
end

local function positionRow(row)
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", row.stackX, -row.stackY - (row.enterOffset or 0))
end

local function rowMetrics(cfg, data)
	if not (data and data.rollID and cfg.timer and not data.submitted) then return cfg.rowHeight, 0 end
	local bandHeight = math.max(cfg.timerHeight, cfg.timerText and cfg.timerFontSize + 2 or 0)
	return cfg.rowHeight + bandHeight - 1, bandHeight
end

local function addHighlight(button)
	local highlight = button:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(0.72, 0.79, 0.9, 0.1)
end

local function textButton(parent, label, onClick)
	local button = CreateFrame("Button", nil, parent)
	button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	button.label:SetPoint("CENTER")
	button.label:SetWordWrap(false)
	button.label:SetText(label)
	button:SetFontString(button.label)
	addHighlight(button)
	button:SetScript("OnClick", onClick)
	return button
end

local function showItemTooltip(owner, row)
	local data = row.data
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	if row.sample then
		GameTooltip:SetText(data.name)
	elseif data.rollID then
		GameTooltip:SetLootRollItem(data.rollID)
	elseif data.currencyID then
		GameTooltip:SetLootCurrency(data.slot)
	elseif data.kind == Enum.LootSlotType.Item then
		GameTooltip:SetLootItem(data.slot)
	else
		GameTooltip:SetText(data.name)
	end
	GameTooltip:Show()
end

local function hideTooltip(owner)
	if GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
end

local function newRow(parent)
	local row = CreateFrame("Frame", nil, parent)
	row.background = row:CreateTexture(nil, "BACKGROUND")
	row.background:SetAllPoints()
	row.edge = row:CreateTexture(nil, "BORDER")
	row.border = CreateFrame("Frame", nil, row, "BackdropTemplate")
	row.timer = row:CreateTexture(nil, "ARTWORK")
	row.timerLabel = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.timerLabel:SetWordWrap(false)
	row.item = CreateFrame("Button", nil, row)
	row.item:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	addHighlight(row.item)
	row.item:SetScript("OnEnter", function(button) showItemTooltip(button, row) end)
	row.item:SetScript("OnLeave", hideTooltip)
	row.item:SetScript("OnClick", function()
		if row.sample then return end
		if row.data.rollID then
			if not IsModifiedClick() then return end
			local link = GetLootRollItemLink(row.data.rollID)
			if not (issecretvalue and issecretvalue(link)) and link then HandleModifiedItemClick(link) end
		else
			Loot:ClickSlot(row.data)
		end
	end)

	row.icon = row.item:CreateTexture(nil, "ARTWORK")
	row.icon:SetTexCoord(0.075, 0.925, 0.075, 0.925)
	row.title = row.item:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row.title:SetJustifyH("LEFT")
	row.title:SetWordWrap(false)
	if row.title.SetMaxLines then row.title:SetMaxLines(1) end

	row.buttons = {}
	for index, choice in ipairs(choices) do
		local button = CreateFrame("Button", nil, row)
		local icon = button:CreateTexture(nil, "ARTWORK")
		if choice.icon then icon:SetAtlas(choice.icon) else icon:SetTexture(choice.texture) end
		icon:SetAllPoints()
		button:SetNormalTexture(icon)
		addHighlight(button)
		if button.SetMotionScriptsWhileDisabled then button:SetMotionScriptsWhileDisabled(true) end
		button:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(choice.label)
			local reason = row.data.reasons and row.data.reasons[choice.id]
			local description = reason and _G["LOOT_ROLL_INELIGIBLE_REASON" .. reason]
			if not self:IsEnabled() and description then GameTooltip:AddLine(description, 1, 0.4, 0.4, true) end
			GameTooltip:Show()
		end)
		button:SetScript("OnLeave", hideTooltip)
		button:SetScript("OnClick", function()
			if not row.sample then Loot:Vote(row.data.rollID, choice.id) end
		end)
		row.buttons[index] = button
	end

	row.result = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.fade = row:CreateAnimationGroup()
	row.fade:SetToFinalAlpha(true)
	row.alpha = row.fade:CreateAnimation("Alpha")
	row.alpha:SetSmoothing("OUT")
	row.rise = row.fade:CreateAnimation("Translation")
	row.rise:SetSmoothing("OUT")
	row.fade:SetScript("OnFinished", function()
		if row.retiring then
			Loot:ReleaseRow(row)
		elseif row.enterOffset then
			row.enterOffset = nil
			positionRow(row)
		end
	end)
	return row
end

local function fade(row, from, to, duration, rise)
	row.fade:Stop()
	row.enterOffset = duration > 0 and rise or nil
	positionRow(row)
	row:SetAlpha(from)
	if duration <= 0 then
		row:SetAlpha(to)
	else
		row.alpha:SetFromAlpha(from)
		row.alpha:SetToAlpha(to)
		row.alpha:SetDuration(duration / 1000)
		row.rise:SetOffset(0, row.enterOffset or 0)
		row.rise:SetDuration(duration / 1000)
		row.fade:Play()
	end
end

local function updateTimer(row, data)
	local remaining = data.remaining or 0
	if not row.nativeTimerEnd then
		local fraction = remaining / math.max(1, data.duration or 0)
		row.timer:SetWidth(math.max(0.01, row.timerSpan * math.min(1, fraction)))
	end
	if row.timerTextShown and not row.nativeTimerText then
		local seconds = math.ceil(remaining / 1000)
		if seconds ~= row.timerSeconds then
			row.timerSeconds = seconds
			row.timerLabel:SetText(seconds >= 60 and ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60) or tostring(seconds))
		end
	end
end

local timerFormatter
local function getTimerFormatter()
	if timerFormatter then return timerFormatter end
	local rounding = Enum.NumericRuleFormatRounding
	if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter and rounding) then return end
	local formatter = C_StringUtil.CreateNumericRuleFormatter()
	formatter:SetBreakpoints({
		{ threshold = 0, step = 1, rounding = rounding.Up, format = "%d" },
		{ threshold = 60, step = 1, rounding = rounding.Up, format = "%d:%02d", components = {
			{ div = 60, step = 1, rounding = rounding.Down },
			{ mod = 60, step = 1, rounding = rounding.Down },
		} },
	})
	timerFormatter = formatter
	return formatter
end

local function stopNativeTimer(row)
	if row.nativeTimerEnd then
		row.durationObject:Reset()
		row.durationBar:Hide()
		row.nativeTimerEnd = nil
	end
	if row.nativeTimerText then
		addon.functions.SetDurationTextBindingEnabled(row, "lootRollTimer", false)
		row.nativeTimerText = nil
		row.timerSeconds = nil
	end
end

local function syncDurationBar(row, data, now)
	local finish = now + data.remaining / 1000
	local total = math.max(1, data.duration or data.remaining) / 1000
	if row.nativeTimerTotal == total and row.nativeTimerEnd and math.abs(row.nativeTimerEnd - finish) < 0.15 then return end
	row.nativeTimerTotal, row.nativeTimerEnd = total, finish
	row.durationObject:SetTimeFromEnd(finish, total)
	row.durationBar:SetTimerDuration(row.durationObject, Enum.StatusBarInterpolation.Immediate, Enum.StatusBarTimerDirection.RemainingTime)
end

local function configureDurationBar(row, data)
	local durationUtil = _G.C_DurationUtil
	if row.sample or not (durationUtil and durationUtil.CreateDuration and Enum.StatusBarInterpolation and Enum.StatusBarTimerDirection) then return end
	if not row.durationBar then
		row.durationBar = CreateFrame("StatusBar", nil, row)
		row.durationBar:Hide()
		if not row.durationBar.SetTimerDuration then return end
		row.durationBar:SetStatusBarTexture(WHITE_TEXTURE)
		row.durationObject = durationUtil.CreateDuration()
	end
	if not (row.durationObject and row.durationObject.SetTimeFromEnd and row.durationObject.Reset) then return end
	syncDurationBar(row, data, GetTime())
	if row.timerTextShown then
		local formatter = getTimerFormatter()
		if formatter and not row.nativeTimerText then
			local _, configured = addon.functions.ConfigureDurationTextBinding(row, "lootRollTimer", row.timerLabel, row.durationObject, {
				formatter = formatter, useProfileConfig = false, zeroDurationText = "", expiredText = "", updateInterval = 0.1,
			})
			row.nativeTimerText = configured
		end
	elseif row.nativeTimerText then
		addon.functions.SetDurationTextBindingEnabled(row, "lootRollTimer", false)
		row.nativeTimerText = nil
		row.timerSeconds = nil
	end
	return row.durationBar
end

function Loot:UpdateRollTimer(data, now, resync)
	local row = self.activeRows[data.rowKey]
	if not (row and row.data == data and row.timerSpan) then return end
	if resync and row.nativeTimerEnd then syncDurationBar(row, data, now) end
	if data.timerNeedsTick then updateTimer(row, data) end
end

local function styleRow(row, data, cfg, width, sample, style)
	row.data, row.sample = data, sample
	local height, timerBand = rowMetrics(cfg, data)
	local extraHeight = math.max(0, timerBand - 1)
	local mirrored = style.mirrored
	local itemSide, actionSide = style.itemSide, style.actionSide
	local direction = mirrored and -1 or 1
	row:SetSize(width, height)
	row.item:ClearAllPoints()
	row.item:SetPoint("TOP" .. itemSide)
	row.item:SetPoint("BOTTOM" .. itemSide, 0, extraHeight)
	row.background:SetShown(cfg.backgroundEnabled)
	if cfg.backgroundEnabled then
		local inset = cfg.backgroundInset
		row.background:ClearAllPoints()
		row.background:SetPoint("TOPLEFT", inset, -inset)
		row.background:SetPoint("BOTTOMRIGHT", -inset, inset)
		row.background:SetTexture(style.backgroundTexture)
		local bg = style.background
		row.background:SetVertexColor(bg.r, bg.g, bg.b, cfg.background.a)
	end

	local quality = data.quality and ITEM_QUALITY_COLORS[data.quality]
	local color = quality or style.text
	local borderColor = (cfg.borderColorMode == "QUALITY" and quality) or style.border
	local accent = cfg.border and not style.borderTexture
	row.edge:SetShown(accent)
	if accent then
		local offset = cfg.borderOffset
		local accentSide = cfg.accentSide == "RIGHT" and "RIGHT" or "LEFT"
		local offsetX = accentSide == "RIGHT" and offset or -offset
		row.edge:ClearAllPoints()
		row.edge:SetPoint("TOP" .. accentSide, offsetX, offset)
		row.edge:SetPoint("BOTTOM" .. accentSide, offsetX, -offset)
		row.edge:SetWidth(cfg.borderSize)
		row.edge:SetColorTexture(borderColor.r, borderColor.g, borderColor.b, cfg.borderColor.a)
	end
	row.border:SetShown(cfg.border and style.borderTexture ~= nil)
	if cfg.border and style.borderTexture then
		local offset = cfg.borderOffset
		local verticalOffset = style.borderOffsetY
		row.border:ClearAllPoints()
		row.border:SetPoint("TOPLEFT", -offset, verticalOffset)
		row.border:SetPoint("BOTTOMRIGHT", offset, -verticalOffset)
		if row.borderTexture ~= style.borderTexture or row.borderSize ~= cfg.borderSize then
			row.borderTexture, row.borderSize = style.borderTexture, cfg.borderSize
			row.border:SetBackdrop({ edgeFile = style.borderTexture, edgeSize = cfg.borderSize })
		end
		row.border:SetBackdropBorderColor(borderColor.r, borderColor.g, borderColor.b, cfg.borderColor.a)
	end
	local iconSize = math.min(cfg.iconSize, cfg.rowHeight - 6)
	local fontSize = math.min(cfg.fontSize, cfg.rowHeight - 8)
	row.icon:ClearAllPoints()
	row.icon:SetPoint(itemSide, direction * 8, 0)
	row.icon:SetSize(iconSize, iconSize)
	row.icon:SetTexture(data.icon or 134400)
	row.icon:SetDesaturated(data.locked == true)
	font(row.title, cfg, cfg.quality and quality or style.text, fontSize)

	local actionCount = 0
	for index, choice in ipairs(choices) do
		local button = row.buttons[index]
		local show = data.rollID and not data.submitted and (choice.id == 0 or choice.id == 1 or choice.id == 2 or data[choice.id])
		button:SetShown(not not show)
		if show then
			actionCount = actionCount + 1
			button:EnableMouse(not sample)
			button:SetEnabled(not sample and data[choice.id] == true)
			button:SetAlpha(data[choice.id] and 1 or 0.36)
		end
	end
	-- Pack only visible actions towards the edge opposite the item.
	local buttonWidth = 0
	if actionCount > 0 then
		local itemSpace = iconSize + 50
		local buttonSize = math.min(cfg.buttonSize, cfg.rowHeight - 6, math.max(1, (width - itemSpace - 6) / actionCount - 2))
		for index = #choices, 1, -1 do
			local button = row.buttons[index]
			if button:IsShown() then
				button:SetSize(buttonSize, buttonSize)
				button:ClearAllPoints()
				button:SetPoint(actionSide, -direction * (6 + buttonWidth), extraHeight / 2)
				buttonWidth = buttonWidth + buttonSize + 2
			end
		end
	end

	row.result:SetShown(data.submitted == true)
	if data.submitted then
		row.result:ClearAllPoints()
		row.result:SetPoint(actionSide, -direction * 9, 0)
		font(row.result, cfg, style.text, fontSize)
		row.result:SetText(data.result or "✓")
		buttonWidth = row.result:GetStringWidth() + 8
	end
	local itemWidth = math.max(1, width - buttonWidth - (buttonWidth > 0 and 6 or 0))
	row.item:SetWidth(itemWidth)
	row.item:EnableMouse(not sample and not data.received)
	local title = row.title
	local text = data.name
	if data.reputation and data.count then
		text = ("+%d %s"):format(data.count, text)
	elseif data.count and (data.currency or data.count > 1) then
		text = ("%s ×%d"):format(text, data.count)
	end
	title:SetText(text)
	local start = iconSize + 16
	local finish = math.max(start + 1, itemWidth - 8)
	local align, anchorX, titleWidth = itemSide, start, finish - start
	if cfg.textAlign == "CENTER" or cfg.textAlign == "RIGHT" then
		align = cfg.textAlign == "CENTER" and "CENTER" or actionSide
		anchorX = align == "CENTER" and (start + finish) / 2 or finish
		local naturalWidth = title:GetUnboundedStringWidth()
		if not (issecretvalue and issecretvalue(naturalWidth)) then titleWidth = math.max(1, math.min(titleWidth, math.ceil(naturalWidth))) end
	end
	title:ClearAllPoints()
	title:SetWidth(titleWidth)
	title:SetJustifyH(align)
	title:SetPoint(align, row.item, itemSide, direction * anchorX + cfg.textX, cfg.textY)
	title:SetAlpha(data.locked and 0.62 or 1)

	row.timerSpan = nil
	row.timerTextShown = timerBand > 0 and cfg.timerText
	row.timerLabel:SetShown(row.timerTextShown)
	data.timerNeedsTick = nil
	if timerBand > 0 then
		local labelSpace = 0
		if row.timerTextShown then
			local labelWidth = math.min(width / 4, math.ceil(cfg.timerFontSize * 3.6))
			labelSpace = labelWidth + 8
			local label = row.timerLabel
			addon.functions.ApplyFontString(label, cfg.timerFont, cfg.timerFontSize, cfg.timerOutline, nil, defaults.timerOutline)
			local tint = cfg.timerTextColor
			label:SetTextColor(tint.r, tint.g, tint.b, tint.a)
			label:ClearAllPoints()
			label:SetJustifyH(actionSide)
			label:SetPoint("BOTTOM" .. actionSide, -direction * 6, (timerBand - cfg.timerFontSize - 2) / 2)
			label:SetSize(labelWidth, cfg.timerFontSize + 2)
		end
		row.timerSpan = width - 2 - labelSpace
		local bar = configureDurationBar(row, data)
		local offsetY = (timerBand - cfg.timerHeight) / 2
		row.timer:SetShown(not bar)
		if bar then
			bar:ClearAllPoints()
			bar:SetPoint("BOTTOM" .. itemSide, direction * 2, offsetY)
			bar:SetReverseFill(mirrored)
			bar:SetSize(row.timerSpan, cfg.timerHeight)
			bar:SetStatusBarColor(color.r, color.g, color.b, 0.8)
			bar:Show()
		else
			stopNativeTimer(row)
			row.timer:ClearAllPoints()
			row.timer:SetPoint("BOTTOM" .. itemSide, direction * 2, offsetY)
			row.timer:SetHeight(cfg.timerHeight)
			row.timer:SetColorTexture(color.r, color.g, color.b, 0.8)
		end
		data.timerNeedsTick = not bar or (row.timerTextShown and not row.nativeTimerText)
		updateTimer(row, data)
	else
		row.timer:Hide()
		stopNativeTimer(row)
	end
end

local sampleRolls = {
	{ key = -1, rollID = -1, name = ITEM_QUALITY3_DESC, icon = 135350, quality = 3, duration = 60000, remaining = 41000, [0] = true, [1] = true, [2] = true },
}
local sampleLoot = {
	{ key = -2, name = ITEM_QUALITY2_DESC, icon = 134414, quality = 2, count = 3 },
	{ key = -3, name = ITEM_QUALITY1_DESC, icon = 133784, quality = 1 },
}
local sampleReceived = {
	{ category = "receivedSkillUps", name = L["floatingLootSkillUpSample"] .. ": 75", icon = Loot.skillUpIcon },
	{ category = "receivedItems", name = ITEM_QUALITY4_DESC, icon = 134419, quality = 4, count = 2 },
	{ category = "receivedMoney", name = "1", icon = "Interface\\Icons\\INV_Misc_Coin_01" },
	{ category = "receivedCurrencies", name = _G.CURRENCY, icon = 133784, count = 5, currency = true },
	{ category = "receivedReputation", name = _G.REPUTATION, icon = "Interface\\Icons\\Achievement_Reputation_01", count = 125, reputation = true },
	{ category = "receivedQuestXP", name = "+1250", icon = "Interface\\Icons\\XP_Icon" },
}

local function previewReceipts(cfg)
	local examples, rows = {}, {}
	if not cfg.received then return rows end
	for _, sample in ipairs(sampleReceived) do
		if cfg[sample.category] then examples[#examples + 1] = sample end
	end
	if #examples == 0 then return rows end
	for index = 1, cfg.receivedMaxRows do
		local data = CopyTable(examples[(index - 1) % #examples + 1])
		data.key, data.received = -3 - index, true
		rows[index] = data
	end
	return rows
end

function Loot:ExpireReceipts()
	local first = self.receipts[1]
	if self.preview or not first or not first.shownAt then return false end
	local now, cfg = GetTime(), self.config
	if not first.removeAt and now - first.shownAt < cfg.receivedDuration then return false end

	-- Keep fading receipts in their slots until the next entries can move in.
	local fadeOut = cfg.animate and cfg.fadeOut or 0
	for _, receipt in ipairs(self.receipts) do
		if not receipt.shownAt or (not receipt.removeAt and now - receipt.shownAt < cfg.receivedDuration) then break end
		if not receipt.removeAt then
			receipt.removeAt = now + fadeOut / 1000
			if fadeOut > 0 then
				local row = self.activeRows["received:" .. receipt.key]
				fade(row, row:GetAlpha(), 0, fadeOut)
			end
		end
	end

	local expired = false
	while first and first.removeAt and now >= first.removeAt do
		table.remove(self.receipts, 1)
		first = self.receipts[1]
		expired = true
	end
	return expired
end

function Loot:ReleaseRow(row)
	self.retiring[row] = nil
	row.retiring = nil
	row.fade:Stop()
	stopNativeTimer(row)
	row.enterOffset = nil
	row:Hide()
	row.data = nil
	self.pool[#self.pool + 1] = row
	if not self.rendering and not next(self.activeRows) and not next(self.retiring) then self.display:Hide() end
end

function Loot:RetireRow(key, row, instant)
	self.activeRows[key] = nil
	hideTooltip(row.item)
	row.item:EnableMouse(false)
	for _, button in ipairs(row.buttons) do
		hideTooltip(button)
		button:EnableMouse(false)
	end
	local duration = not instant and self.config.animate and self.config.fadeOut or 0
	if duration > 0 then
		row.retiring = true
		self.retiring[row] = true
		fade(row, row:GetAlpha(), 0, duration)
	else
		self:ReleaseRow(row)
	end
end

function Loot:UpdateJunkButtonParent(parent)
	if self.junkButtonParent == parent then return end
	self.junkButtonParent = parent
	local vendor = addon.Vendor
	if vendor and vendor.functions.RefreshLootJunkButton then vendor.functions.RefreshLootJunkButton() end
end

function Loot:Render()
	if not self.config then return end
	self.rendering = true
	local cfg = self.config
	local rolls = self.preview and sampleRolls or self.rollRows or {}
	local slots = self.preview and sampleLoot or self.lootRows or {}
	local received = self.preview and previewReceipts(cfg) or self.receipts
	local receivedCount = cfg.received and math.min(#received, cfg.receivedMaxRows) or 0
	local anchorWidth, anchorHeight = cfg.width * cfg.scale, rowMetrics(cfg, sampleRolls[1]) * cfg.scale
	local oldWidth, oldHeight = self.anchor:GetSize()
	if oldWidth ~= anchorWidth or oldHeight ~= anchorHeight then self.anchor:SetSize(anchorWidth, anchorHeight) end
	local desired = {}
	for _, data in ipairs(rolls) do desired[data.rowKey or "roll:" .. data.key] = data end
	for _, data in ipairs(slots) do desired["slot:" .. data.key] = data end
	for index = 1, receivedCount do
		local data = received[index]
		desired["received:" .. data.key] = data
	end
	for key, row in pairs(self.activeRows) do
		local data = desired[key]
		if not data or data.session ~= row.data.session or row.sample ~= self.preview then
			local receipt = row.data.received
			if receipt and not row.sample then row.data.shownAt, row.data.removeAt = nil, nil end
			self:RetireRow(key, row, receipt or data ~= nil or row.sample)
		end
	end
	-- Older fades retain the viewport until their last visible frame.
	if not next(desired) then
		self.footer:Hide()
		self:UpdateJunkButtonParent(nil)
		self.display:EnableMouseWheel(false)
		self.rendering = nil
		if not next(self.retiring) then self.display:Hide() end
		return
	end

	local width = cfg.width
	local classColor = getClassColor()
	local mirrored = cfg.rowSide == "RIGHT"
	local style = {
		mirrored = mirrored,
		itemSide = mirrored and "RIGHT" or "LEFT",
		actionSide = mirrored and "LEFT" or "RIGHT",
		text = cfg.textClassColor and classColor or cfg.textColor,
		background = cfg.backgroundClassColor and classColor or cfg.background,
		backgroundTexture = addon.functions.ResolveLSMMedia("background", cfg.backgroundTexture, WHITE_TEXTURE),
		border = cfg.borderColorMode == "CLASS" and classColor or cfg.borderColor,
		borderTexture = cfg.borderTexture ~= "" and addon.functions.ResolveLSMMedia("border", cfg.borderTexture, WHITE_TEXTURE) or nil,
	}
	local outsetX = cfg.border and math.max(0, cfg.borderOffset) or 0
	local outsetY = outsetX
	if cfg.border and style.borderTexture then
		-- Leave enough vertical space for both corners of large border textures.
		local minRowHeight = rowMetrics(cfg)
		style.borderOffsetY = math.max(cfg.borderOffset, cfg.borderSize + 1 - minRowHeight / 2)
		outsetY = math.max(0, style.borderOffsetY)
	end
	local y = outsetY
	local function place(data, key)
		local row = self.activeRows[key]
		local fresh = not row
		if fresh then
			row = table.remove(self.pool) or newRow(self.content)
			self.activeRows[key] = row
		end
		styleRow(row, data, cfg, width, self.preview, style)
		row.stackX, row.stackY = outsetX, y
		positionRow(row)
		row:Show()
		if fresh then
			local duration = cfg.animate and (not self.preview or data.received) and cfg.fadeIn or 0
			local rise = data.received and cfg.receivedRise > 0 and cfg.receivedRise or nil
			fade(row, 0, 1, duration, rise)
		end
		y = y + row:GetHeight() + cfg.spacing + outsetY * 2
	end

	for _, data in ipairs(rolls) do place(data, data.rowKey or "roll:" .. data.key) end
	if #rolls > 0 and #slots > 0 then y = y + cfg.sectionSpacing end
	for _, data in ipairs(slots) do place(data, "slot:" .. data.key) end
	if #slots > 0 then
		self.footer:SetPoint("TOPLEFT", self.content, "TOPLEFT", outsetX, -y)
		self.footer:SetWidth(width)
		self.all:ClearAllPoints()
		self.all:SetPoint("TOP" .. style.itemSide)
		self.close:ClearAllPoints()
		self.close:SetPoint("TOP" .. style.actionSide)
		font(self.all.label, cfg, style.text)
		font(self.close.label, cfg, style.text)
		local allWidth = math.max(92, self.all.label:GetUnboundedStringWidth() + 14)
		local closeWidth = math.max(60, self.close.label:GetUnboundedStringWidth() + 14)
		local maxButtonWidth = self.preview and (width - 8) / 2 or (width - 30) / 2
		allWidth = math.min(allWidth, maxButtonWidth)
		closeWidth = math.min(closeWidth, maxButtonWidth)
		self.all:SetWidth(allWidth)
		self.all.label:SetWidth(math.max(1, allWidth - 14))
		self.all:SetEnabled(not self.preview)
		self.all:EnableMouse(not self.preview)
		self.close:SetEnabled(not self.preview)
		self.close:EnableMouse(not self.preview)
		self.close:SetWidth(closeWidth)
		self.close.label:SetWidth(math.max(1, closeWidth - 14))
		y = y + self.footer:GetHeight()
	end
	self.footer:SetShown(#slots > 0)
	if receivedCount > 0 then
		if y > outsetY then y = y + cfg.sectionSpacing end
		for index = 1, receivedCount do
			local data = received[index]
			if not self.preview and not data.shownAt then data.shownAt = GetTime() end
			place(data, "received:" .. data.key)
		end
	end
	local viewportWidth = width + outsetX * 2
	self.content:SetSize(viewportWidth, y)
	self.display:SetScale(cfg.scale)
	self.display:SetPoint("TOPLEFT", self.anchor, "TOPLEFT", -outsetX, outsetY)
	local available = UIParent:GetHeight() / cfg.scale - 24
	local height = math.min(y, math.max(48, math.min(380, available)))
	self.display:SetSize(viewportWidth, height)
	self.display:EnableMouseWheel(y > height)
	self.display:SetVerticalScroll(math.min(self.display:GetVerticalScroll(), math.max(0, y - height)))
	self.display:Show()
	self:UpdateJunkButtonParent(self.session and not self.preview and #slots > 0 and self.footer or nil)
	self.rendering = nil
end

local function previewFont(description, value)
	description:AddInitializer(function(button)
		local label = button.fontString
		if not label then return end
		local face, size, flags = label:GetFont()
		button.eqolLootOriginalFont = { face, size, flags }
		addon.functions.SetFontWithFallback(label, value, size, flags)
		return label:GetStringWidth() + 32, math.max(20, label:GetStringHeight() + 4)
	end)
	description:AddResetter(function(button)
		if button.eqolLootOriginalFont then
			button.fontString:SetFont(unpack(button.eqolLootOriginalFont))
			button.eqolLootOriginalFont = nil
		end
	end)
end

local function previewTexture(description, value, mediaType)
	local path = addon.functions.ResolveLSMMedia(mediaType, value)
	if not path then return end
	description:AddInitializer(function(button)
		local swatch = button:AttachTexture()
		swatch:SetSize(38, 12)
		swatch:SetPoint("RIGHT", -6, 0)
		swatch:SetTexture(path)
		swatch:SetTexCoord(0, mediaType == "border" and 0.125 or 1, 0, 1)
		return button.fontString:GetStringWidth() + 76, 20
	end)
end

local function formatDecimal(value) return ("%.2f"):format(value) end
local function formatSeconds(value) return ("%.1f"):format(value) end

local function buildSettings()
	local kind = EditMode.lib.SettingType
	local settings = {}

	local function section(id, label)
		settings[#settings + 1] = { kind = kind.Collapsible, id = id, name = label }
	end

	local function divider(group, label)
		settings[#settings + 1] = { kind = kind.Divider, parentId = group, name = label }
	end

	local function field(group, key, label, settingKind, extra)
		local setting = extra or {}
		setting.parentId, setting.field, setting.name, setting.kind = group, key, label, settingKind
		if setting.default == nil then setting.default = defaults[key] end
		setting.get = setting.get or function() return layoutConfig()[key] end
		setting.set = setting.set or function(_, value)
			layoutConfig()[key] = value
			Loot:ApplyDisplayLayout()
		end
		settings[#settings + 1] = setting
		return setting
	end

	local function slider(group, key, label, min, max, step, enabled, formatter)
		return field(group, key, label, kind.Slider, {
			minValue = min, maxValue = max, valueStep = step, allowInput = true, isEnabled = enabled, formatter = formatter,
		})
	end

	local function sideOptions() return { LEFT = L["Left"], RIGHT = L["Right"] }, { "LEFT", "RIGHT" } end

	local function dropdown(group, key, label, options, enabled, preview)
		return field(group, key, label, kind.Dropdown, {
			height = 220,
			isEnabled = enabled,
			generator = function(_, root, data)
				local values, order = options()
				for _, value in ipairs(order) do
					local radio = root:CreateRadio(values[value], function() return data.get() == value end, function()
						data.set(nil, value)
						EditMode.lib.internal:RequestRefreshSettings()
					end)
					if preview then preview(radio, value) end
				end
			end,
		})
	end

	local function media(group, key, label, mediaType, defaultLabel, enabled)
		dropdown(group, key, label, function() return addon.functions.GetLSMMediaDropdown(mediaType, true, defaultLabel) end, enabled,
			mediaType == "font" and previewFont or function(description, value) previewTexture(description, value, mediaType) end)
	end

	local function color(group, key, label, enabled, opacityEnabled)
		field(group, key, label, kind.Color, {
			isEnabled = enabled,
			set = function(_, value)
				local config = layoutConfig()
				config[key] = { r = value.r, g = value.g, b = value.b, a = config[key].a }
				Loot:ApplyDisplayLayout()
			end,
		})
		field(group, key .. "Opacity", _G.OPACITY or L["CooldownPanelOpacityHeader"], kind.Slider, {
			default = defaults[key].a,
			minValue = 0, maxValue = 1, valueStep = 0.01, allowInput = true, formatter = formatDecimal,
			isEnabled = opacityEnabled,
			get = function() return layoutConfig()[key].a end,
			set = function(_, value)
				layoutConfig()[key].a = value
				Loot:ApplyDisplayLayout()
			end,
		})
	end

	section("layout", L["Layout"])
	local x = slider("layout", "x", L["Offset X"], -2000, 2000, 1)
	x.navigationReset = function()
		local config = layoutConfig()
		config.point, config.relativePoint, config.x = defaults.point, defaults.relativePoint, defaults.x
		Loot:ApplyDisplayLayout()
	end
	slider("layout", "y", L["Offset Y"], -2000, 2000, 1)
	slider("layout", "width", L["Width"], 220, 600, 1)
	slider("layout", "scale", L["Scale"], 0.65, 1.6, 0.05, nil, formatDecimal)
	dropdown("layout", "rowSide", L["floatingLootRowAlignment"], sideOptions).navigationField = "rowSide"
	slider("layout", "rowHeight", L["floatingLootRowHeight"], 22, 76, 1)
	slider("layout", "iconSize", L["Icon size"], 14, 64, 1)
	slider("layout", "spacing", L["Spacing"], 0, 20, 1)
	slider("layout", "sectionSpacing", L["floatingLootSectionSpacing"], 0, 32, 1)

	section("text", L["Text"])
	media("text", "font", L["Font"], "font", addon.functions.GetGlobalFontConfigLabel())
	local function outlineOptions()
		local values, order = addon.functions.GetFontStyleOptions(true)
		local none = addon.functions.NormalizeFontStyleChoice("", "", false)
		values[""] = values[none]
		for index, key in ipairs(order) do
			if key == none then order[index] = ""; break end
		end
		return values, order
	end
	dropdown("text", "outline", L["Font outline"], outlineOptions)
	slider("text", "fontSize", FONT_SIZE, 8, 32, 1)
	dropdown("text", "textAlign", L["classicReminderAlignment"], function()
		if layoutConfig().rowSide == "RIGHT" then
			return { LEFT = L["Right"], CENTER = L["Center"], RIGHT = L["Left"] }, { "RIGHT", "CENTER", "LEFT" }
		end
		return { LEFT = L["Left"], CENTER = L["Center"], RIGHT = L["Right"] }, { "LEFT", "CENTER", "RIGHT" }
	end)
	slider("text", "textX", L["Offset X"], -40, 40, 1)
	slider("text", "textY", L["Offset Y"], -24, 24, 1)
	field("text", "quality", L["floatingLootQualityColors"], kind.Checkbox)
	divider("text", L["floatingLootFooterButtons"]:format(_G.LOOT_ALL or L["floatingLootAll"], CLOSE))
	field("text", "textClassColor", L["Use class color"], kind.Checkbox, { tooltip = L["floatingLootFooterColorDesc"] })
	color("text", "textColor", L["Font color"], function() return not layoutConfig().textClassColor end)

	section("appearance", L["Background"])
	local function backgroundEnabled() return layoutConfig().backgroundEnabled end
	field("appearance", "backgroundEnabled", L["Show"], kind.Checkbox)
	media("appearance", "backgroundTexture", L["Background texture"], "background", L["Solid"], backgroundEnabled)
	field("appearance", "backgroundClassColor", L["Use class color"], kind.Checkbox, { isEnabled = backgroundEnabled })
	color("appearance", "background", L["Background color"], function()
		local config = layoutConfig()
		return config.backgroundEnabled and not config.backgroundClassColor
	end, backgroundEnabled)
	slider("appearance", "backgroundInset", L["Background inset"], 0, 8, 1, backgroundEnabled)

	section("border", L["Border"])
	local function borderEnabled() return layoutConfig().border end
	field("border", "border", L["Show"], kind.Checkbox)
	media("border", "borderTexture", L["Border texture"], "border", L["floatingLootBorderAccent"], borderEnabled)
	dropdown("border", "accentSide", L["floatingLootBorderAccentSide"], sideOptions, function()
		local config = layoutConfig()
		return config.border and config.borderTexture == ""
	end).navigationField = "accentSide"
	slider("border", "borderSize", L["Border size"], 1, 80, 1, borderEnabled)
	slider("border", "borderOffset", L["Border offset"], -8, 80, 1, borderEnabled)
	dropdown("border", "borderColorMode", L["Style"], function()
		return { QUALITY = L["floatingLootQualityColors"], CLASS = L["ClassColor"], CUSTOM = L["Color"] }, { "QUALITY", "CLASS", "CUSTOM" }
	end, borderEnabled)
	color("border", "borderColor", L["Border color"], function()
		local config = layoutConfig()
		return config.border and config.borderColorMode == "CUSTOM"
	end, borderEnabled)

	section("animation", L["floatingLootAnimation"])
	field("animation", "animate", L["floatingLootAnimation"], kind.Checkbox)
	local function animationsEnabled() return layoutConfig().animate end
	slider("animation", "fadeIn", L["Fade In"] .. " (ms)", 0, 500, 10, animationsEnabled)
	slider("animation", "fadeOut", L["Fade Out"] .. " (ms)", 0, 500, 10, animationsEnabled)
	divider("animation", L["floatingLootReceived"])
	field("animation", "received", L["Show"], kind.Checkbox)
	local function receivedEnabled() return layoutConfig().received end
	slider("animation", "receivedMaxRows", L["Max rows"], 1, MAX_RECEIPT_ROWS, 1, receivedEnabled).navigationField = "receivedMaxRows"
	slider("animation", "receivedDuration", L["combatTextDuration"], 1, 10, 0.5, receivedEnabled, formatSeconds)
	slider("animation", "receivedRise", L["floatingLootRise"], 0, 32, 1, function()
		local config = layoutConfig()
		return config.received and config.animate and config.fadeIn > 0
	end)
	field("animation", "receivedItems", _G.ITEMS, kind.Checkbox, { isEnabled = receivedEnabled })
	field("animation", "receivedMoney", _G.MONEY, kind.Checkbox, { isEnabled = receivedEnabled })
	field("animation", "receivedCurrencies", _G.CURRENCY, kind.Checkbox, { isEnabled = receivedEnabled })
	field("animation", "receivedReputation", _G.REPUTATION, kind.Checkbox, { isEnabled = receivedEnabled })
	field("animation", "receivedQuestXP", L["xpBarQuestXP"], kind.Checkbox, { isEnabled = receivedEnabled })
	field("animation", "receivedSkillUps", L["floatingLootSkillUps"], kind.Checkbox, { isEnabled = receivedEnabled, navigationField = "receivedSkillUps" })

	section("rolls", L["groupLootRollFrames"])
	slider("rolls", "buttonSize", L["floatingLootButtonSize"], 16, 38, 1)
	divider("rolls", L["floatingLootTimer"])
	field("rolls", "timer", L["Show"], kind.Checkbox)
	local function timerEnabled() return layoutConfig().timer end
	local function timerTextEnabled()
		local config = layoutConfig()
		return config.timer and config.timerText
	end
	slider("rolls", "timerHeight", L["Bar height"], 1, 20, 1, timerEnabled)
	field("rolls", "timerText", L["Show duration"], kind.Checkbox, { isEnabled = timerEnabled })
	media("rolls", "timerFont", L["Font"], "font", addon.functions.GetGlobalFontConfigLabel(), timerTextEnabled)
	dropdown("rolls", "timerOutline", L["Font outline"], outlineOptions, timerTextEnabled)
	slider("rolls", "timerFontSize", FONT_SIZE, 8, 32, 1, timerTextEnabled)
	color("rolls", "timerTextColor", L["Font color"], timerTextEnabled, timerTextEnabled)
	return settings
end

function Loot:SetPreview(enabled)
	enabled = enabled and true or nil
	if self.preview == enabled then return end
	self.preview = enabled
	self.sampleAnimationEnds, self.sampleFadingOut = nil, nil
	self:SyncLootRegistration()
	self:ScanRolls()
	self:RefreshRolls()
end

function Loot:ShowAnimationSample()
	if not self.enabled or not self.config or self.session then return end
	self:SetPreview(true)
	local cfg = self.config
	local duration = cfg.animate and cfg.fadeIn or 0
	for _, row in pairs(self.activeRows) do
		if row.sample then
			local rise = row.data.received and cfg.receivedRise > 0 and cfg.receivedRise or nil
			fade(row, 0, 1, duration, rise)
		end
	end
	self.sampleFadingOut = nil
	self.sampleAnimationEnds = cfg.animate and GetTime() + duration / 1000 + cfg.receivedDuration or nil
end

function Loot:InitializeDisplay()
	if self.display then return end
	local anchor = CreateFrame("Frame", "EQOLFloatingLootAnchor", UIParent)
	anchor:SetSize(defaults.width, (rowMetrics(defaults, sampleRolls[1])))
	anchor:SetClampedToScreen(true)
	local display = CreateFrame("ScrollFrame", "EQOLFloatingLoot", UIParent)
	display:SetPoint("TOPLEFT", anchor)
	display:SetFrameStrata("DIALOG")
	display:SetClampedToScreen(true)
	display:Hide()
	local content = CreateFrame("Frame", nil, display)
	display:SetScrollChild(content)
	display:SetScript("OnMouseWheel", function(self, delta)
		local target = self:GetVerticalScroll() - delta * 36
		self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), target)))
	end)
	display:SetScript("OnSizeChanged", function(self)
		self:SetVerticalScroll(math.min(self:GetVerticalScroll(), self:GetVerticalScrollRange()))
	end)
	local footer = CreateFrame("Frame", nil, content)
	footer:SetHeight(25)
	local all = textButton(footer, _G.LOOT_ALL or L["floatingLootAll"], function() Loot:LootAll() end)
	all:SetHeight(25)
	local close = textButton(footer, CLOSE, function() if Loot.session then CloseLoot() end end)
	close:SetHeight(25)

	self.anchor, self.display, self.content = anchor, display, content
	self.footer, self.all, self.close = footer, all, close
	self.activeRows, self.retiring, self.pool = {}, {}, {}
	self.editModeID = ID
	self.rollClock = 0
	self.events:SetScript("OnUpdate", function(_, elapsed)
		if not self.enabled then return end
		if self.sampleAnimationEnds and GetTime() >= self.sampleAnimationEnds then
			local duration = self.config.animate and self.config.fadeOut or 0
			if not self.sampleFadingOut and duration > 0 then
				self.sampleAnimationEnds, self.sampleFadingOut = GetTime() + duration / 1000, true
			else
				self.sampleAnimationEnds, self.sampleFadingOut = nil, nil
			end
			for _, row in pairs(self.activeRows) do
				if row.sample then
					if self.sampleFadingOut then fade(row, row:GetAlpha(), 0, duration)
					else fade(row, 1, 1, 0) end
				end
			end
		end
		local expired = self:ExpireReceipts()
		if next(self.rolls) then
			self.rollClock = self.rollClock + elapsed
			if self.rollClock >= 0.1 then
				self.rollClock = 0
				if self:TickRolls() then return end
			end
		end
		if expired then self:Render() end
	end)

	EditMode:RegisterFrame(ID, {
		frame = anchor, title = L["floatingLoot"], managerCategory = "loot",
		isEnabled = function() return self.enabled end,
		layoutDefaults = defaults, settings = buildSettings(), settingsFactoryDefaults = defaults,
		managePosition = false, persistPosition = false,
		showReset = false,
		showSettingsReset = false,
		buttons = { { text = L["Show sample"], click = function() self:ShowAnimationSample() end } },
		settingsNavigation = {
			direct = true,
			categories = { { id = "floatingLoot", name = L["floatingLoot"], groups = { "layout", "text", "appearance", "border", "animation", "rolls" } } },
			reset = function(_, applyDefaults)
				self.resettingDisplay = true
				local ok, err = pcall(applyDefaults)
				self.resettingDisplay = nil
				if not ok then error(err) end
				self:ApplyDisplayLayout()
			end,
		},
		onApply = function() self:ApplyDisplayLayout() end,
		onPositionChanged = function(_, _, data)
			local config = layoutConfig()
			config.point, config.relativePoint, config.x, config.y = data.point, data.relativePoint, data.x, data.y
		end,
		onEnter = function() self:SetPreview(not self.session) end,
		onExit = function() self:SetPreview(false) end,
		onVisibilityChanged = function(visible) if not visible then self:SetPreview(false) end end,
	})
	EditMode.lib:RegisterCallback("layout", function()
		if not self.enabled then return end
		self:ApplyDisplayLayout()
		EditMode.lib.internal:RequestRefreshSettingValues()
	end)
end
