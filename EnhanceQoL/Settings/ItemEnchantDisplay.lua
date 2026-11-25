local addonName, addon = ...
local L = LibStub("AceLocale-3.0"):GetLocale(addonName)

local display = {}
addon.ItemEnchantDisplay = display

local MAX_WIDTH = 112
local LINE_HEIGHT = 14
local GAP = 2

local function getRect(region)
	if not region or not region.GetRect then return end
	local left, bottom, width, height = region:GetRect()
	if issecretvalue(left) or issecretvalue(bottom) or issecretvalue(width) or issecretvalue(height) then return end
	if not left or not bottom or not width or not height then return end
	return left, bottom, left + width, bottom + height
end

local function excludeRegion(bands, region, left, right)
	if not region or not region:IsShown() then return end
	local x1, y1, x2, y2 = getRect(region)
	if not x1 or x2 <= left or x1 >= right then return end
	y1, y2 = y1 - GAP, y2 + GAP
	for index = #bands, 1, -1 do
		local band = bands[index]
		if y1 < band.top and y2 > band.bottom then
			local bottom, top = band.bottom, band.top
			table.remove(bands, index)
			if y2 < top then table.insert(bands, index, { bottom = y2, top = top }) end
			if y1 > bottom then table.insert(bands, index, { bottom = bottom, top = y1 }) end
		end
	end
end

local function chooseBand(bands, preferredTop)
	-- Prefer two lines, then use a single line if the row is crowded.
	for lines = 2, 1, -1 do
		local height = lines * LINE_HEIGHT
		for _, band in ipairs(bands) do
			local top = preferredTop and math.min(band.top, preferredTop) or band.top
			if top - band.bottom >= height then
				return lines, preferredTop and top - height or band.bottom
			end
		end
	end
end

local function updateTooltip(element, text, width, height, point)
	local frame = element.enchantWarningTooltip
	local warning = element.enchantWarning
	if frame then frame:Hide() end
	if not text and not warning then return end
	if not frame then
		frame = CreateFrame("Frame", nil, element)
		frame:SetFrameLevel(element:GetFrameLevel() + 20)
		frame:EnableMouse(true)
		frame:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			if self.enchantText then
				GameTooltip:SetText(self.enchantText, 1, 1, 1, 1, true)
				if self.warning then GameTooltip:AddLine(L["gearEnchantWarningLow"], 1, 0.82, 0, true) end
			else
				GameTooltip:SetText(L["gearEnchantWarningLow"], 1, 0.82, 0, 1, true)
			end
			GameTooltip:Show()
		end)
		frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
		element.enchantWarningTooltip = frame
	end
	frame.enchantText, frame.warning = text, warning
	frame:ClearAllPoints()
	frame:SetPoint(point, element.enchant, point)
	frame:SetSize(width, height)
	frame:Show()
end

function display.Layout(element, slot, itemLevelShown, inspectFrame)
	local text = element.enchant
	if not text or not text:GetText() or text:GetText() == "" then return end

	local side = addon.variables.itemSlotSide[slot] or 0
	local center = side == 2
	local point = center and "BOTTOM" or (side == 1 and "BOTTOMRIGHT" or "BOTTOMLEFT")
	local anchor = center and "TOP" or (side == 1 and "BOTTOMLEFT" or "BOTTOMRIGHT")
	local justify = center and "CENTER" or (side == 1 and "RIGHT" or "LEFT")
	local x = center and 0 or (side == 1 and -GAP or GAP)
	local y = center and GAP or (inspectFrame and 1 or -2)
	local width, lines = MAX_WIDTH, 1
	local alignTop

	local left, bottom, right, top = getRect(element)
	if left then
		local leftSlot = inspectFrame and _G.InspectHeadSlot or _G.CharacterHeadSlot
		local rightSlot = inspectFrame and _G.InspectHandsSlot or _G.CharacterHandsSlot
		local _, _, leftEdge = getRect(leftSlot)
		local rightEdge = getRect(rightSlot)
		if leftEdge and rightEdge and rightEdge > leftEdge then
			width = math.max(1, math.min(width, (rightEdge - leftEdge) / 2 - 2 * GAP))
		end

		local labelRight = center and (left + right + width) / 2 or (side == 1 and left + x or right + x + width)
		local labelLeft = labelRight - width
		local origin = center and top or bottom
		local bands = { { bottom = origin + y, top = center and top + 3 * LINE_HEIGHT or top } }
		if itemLevelShown then excludeRegion(bands, element.ilvl, labelLeft, labelRight) end
		excludeRegion(bands, element.trackLabel, labelLeft, labelRight)
		for _, gem in ipairs(element.gems or {}) do
			excludeRegion(bands, gem, labelLeft, labelRight)
		end

		local preferredTop
		if addon.db.charEnchantPosition == "ITEMLEVEL" and itemLevelShown and not center then
			local _, levelBottom = getRect(element.ilvl)
			if levelBottom then preferredTop = levelBottom - GAP end
		end
		local lineCount, labelBottom = chooseBand(bands, preferredTop)
		alignTop = preferredTop and lineCount
		if not lineCount and preferredTop then lineCount, labelBottom = chooseBand(bands) end
		if not lineCount then
			text:Hide()
			if element.enchantWarningTooltip then element.enchantWarningTooltip:Hide() end
			return
		end
		lines, y = lineCount, labelBottom - origin
	end

	local height = lines * LINE_HEIGHT
	if alignTop then
		point = side == 1 and "TOPRIGHT" or "TOPLEFT"
		y = y + height
	end
	text:ClearAllPoints()
	text:SetPoint(point, element, anchor, x, y)
	text:SetSize(width, height)
	text:SetJustifyH(justify)
	text:SetJustifyV(alignTop and "TOP" or "BOTTOM")
	text:SetWordWrap(true)
	text:SetNonSpaceWrap(true)
	text:SetMaxLines(lines)
	text:Show()

	local truncated = text:IsTruncated() or text:GetUnboundedStringWidth() > width
	local hitWidth = math.min(width, math.max(1, text:GetStringWidth()))
	local hitHeight = math.min(height, math.max(1, text:GetStringHeight()))
	updateTooltip(element, truncated and text:GetText() or nil, hitWidth, hitHeight, point)
end

function display.Clear(element)
	if not element then return end
	if element.enchant then element.enchant:SetText("") end
	element.enchantWarning = nil
	if element.enchantWarningTooltip then element.enchantWarningTooltip:Hide() end
end

function display.Apply(element, displayText, warning, slot, itemLevelShown, inspectFrame)
	display.Clear(element)
	if not element or not element.enchant or not displayText then return end
	element.enchant:SetFormattedText(displayText)
	element.enchantWarning = warning
	display.Layout(element, slot, itemLevelShown, inspectFrame)
end
