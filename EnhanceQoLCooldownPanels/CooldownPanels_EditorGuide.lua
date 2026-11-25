local _, addon = ...
addon = _G.EnhanceQoL or addon
local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL")
local Panels = addon.Aura.CooldownPanels

local HELP_ICON = "Interface\\common\\help-i"
local MARKER_SIZE = 24
local BUBBLE_WIDTH = 262

local steps = {
	{ field = "addPanelButton", text = "CooldownPanelGuideAddPanel" },
	{ field = "header", text = "CooldownPanelGuidePanel", fallback = "CooldownPanelGuideEmpty" },
	{ field = "addTile", text = "CooldownPanelGuideEntry", fallback = "CooldownPanelGuideNoEntry" },
	{ field = "searchBox", text = "CooldownPanelGuideSearch" },
	{ field = "classDropdown", text = "CooldownPanelGuideClass", retailField = "specDropdown", retailText = "CooldownPanelGuideSpec" },
	{ field = "gear", text = "CooldownPanelGuideMenu" },
}

local Guide = {}
Guide.__index = Guide

local function solid(frame, layer, inset, r, g, b)
	local texture = frame:CreateTexture(nil, layer)
	texture:SetPoint("TOPLEFT", inset, -inset)
	texture:SetPoint("BOTTOMRIGHT", -inset, inset)
	texture:SetColorTexture(r, g, b)
end

local function makeButton(parent, label, callback)
	local button = CreateFrame("Button", nil, parent)
	button:SetHeight(24)
	solid(button, "BACKGROUND", 0, 0.49, 0.36, 0.15)
	solid(button, "BORDER", 1, 0.19, 0.14, 0.08)
	local caption = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	caption:SetPoint("CENTER")
	button:SetFontString(caption)
	button:SetText(label)
	button:SetWidth(math.max(60, button:GetTextWidth() + 16))
	local hover = button:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAllPoints()
	hover:SetColorTexture(1, 0.80, 0.34, 0.15)
	button:SetScript("OnClick", callback)
	return button
end

local function firstVisibleControl(frame, field)
	local scroll = frame.scroll
	local clipBottom, clipTop = scroll:GetBottom(), scroll:GetTop()
	if not clipBottom or not clipTop then return end
	for i = 1, frame.categories.active or 0 do
		local category = frame.categories[i]
		local target = category[field]
		if target and target:IsVisible() then
			local bottom, top = target:GetBottom(), target:GetTop()
			if bottom and top and bottom >= clipBottom and top <= clipTop then return target end
		end
	end
end

function Guide:Stop()
	self.step, self.x, self.y, self.target, self.layoutStep = nil, nil, nil, nil, nil
	self.targetX, self.targetY, self.bubbleDY = nil, nil, nil
	self.layer:SetScript("OnUpdate", nil)
	self.layer:Hide()
end

function Guide:Move(x, y)
	local frame = self.editor
	self.x, self.y = x, y
	self.marker:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", x, y)
	self.bubble:SetPoint(
		"BOTTOMLEFT",
		frame,
		"BOTTOMLEFT",
		math.max(8, math.min(frame:GetWidth() - BUBBLE_WIDTH - 8, x + self.bubbleDX)),
		math.max(8, math.min(frame:GetHeight() - self.bubble:GetHeight() - 8, y + self.bubbleDY))
	)
end

function Guide:Refresh()
	if not self.step then return end
	local frame, definition = self.editor, steps[self.step]
	local target = frame[definition.field] or (definition.retailField and frame[definition.retailField]) or firstVisibleControl(frame, definition.field)
	local key = definition.text
	if definition.retailField and target == frame[definition.retailField] then key = definition.retailText end
	if not target then
		target = definition.field == "addTile" and firstVisibleControl(frame, "header") or frame.addPanelButton
		key = definition.fallback
	end
	local x, y, w, h = target:GetRect()
	local left, bottom = frame:GetRect()
	if not x or not left then return end
	x, y = x - left, y - bottom
	local markerX, markerY = x + w + 4, y + (h - MARKER_SIZE) / 2
	if markerX + MARKER_SIZE > frame:GetWidth() - 4 then markerX = x - MARKER_SIZE - 4 end
	markerX = math.max(3, markerX)
	if self.target == target and self.layoutStep == self.step and self.targetX == markerX and self.targetY == markerY then return end

	self.target, self.layoutStep = target, self.step
	self.targetX, self.targetY = markerX, markerY
	local bubble = self.bubble
	bubble.label:SetText(L[key])
	bubble.progress:SetText(("%d / %d"):format(self.step, #steps))
	bubble.back:SetShown(self.step > 1)
	bubble.next:SetText(L[self.step == #steps and "CooldownPanelGuideDone" or "CooldownPanelGuideNext"])
	bubble.next:SetWidth(math.max(60, bubble.next:GetTextWidth() + 16))
	bubble:SetHeight(64 + bubble.label:GetStringHeight())
	self.bubbleDX = x - markerX
	self.bubbleDY = y + h + 7 - markerY
	if y + h + 7 + bubble:GetHeight() > frame:GetHeight() - 8 then
		self.bubbleDY = y - bubble:GetHeight() - 7 - markerY
	end
	self.focus:ClearAllPoints()
	self.focus:SetPoint("TOPLEFT", target, "TOPLEFT", -2, 2)
	self.focus:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 2, -2)
	self.layer:Show()
	local startX = self.x or frame.helpButton:GetLeft() - left
	local startY = self.y or frame.helpButton:GetBottom() - bottom
	self:Move(startX, startY)
	local elapsed = 0
	self.layer:SetScript("OnUpdate", function(_, delta)
		elapsed = elapsed + delta
		local t = math.min(1, elapsed / 0.30)
		local progress = t * t * (3 - 2 * t)
		self:Move(startX + (markerX - startX) * progress, startY + (markerY - startY) * progress)
		if t == 1 then self.layer:SetScript("OnUpdate", nil) end
	end)
end

function Guide:Go(step)
	if step > #steps then
		self:Stop()
	else
		self.step = step
		self:Refresh()
	end
end

function Panels:AttachEditorGuide(frame)
	local guide = setmetatable({ editor = frame }, Guide)
	local layer = CreateFrame("Frame", nil, frame)
	layer:SetAllPoints()
	layer:SetFrameLevel(frame:GetFrameLevel() + 25)
	layer:EnableMouse(false)
	layer:Hide()
	guide.layer = layer

	local marker = layer:CreateTexture(nil, "OVERLAY")
	marker:SetSize(MARKER_SIZE, MARKER_SIZE)
	marker:SetTexture(HELP_ICON)
	guide.marker = marker

	local focus = CreateFrame("Frame", nil, layer)
	focus:EnableMouse(false)
	for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
		local line = focus:CreateTexture(nil, "OVERLAY")
		line:SetColorTexture(1, 0.78, 0.28, 0.9)
		if side == "TOP" or side == "BOTTOM" then
			line:SetPoint(side .. "LEFT")
			line:SetPoint(side .. "RIGHT")
			line:SetHeight(1)
		else
			line:SetPoint("TOP" .. side)
			line:SetPoint("BOTTOM" .. side)
			line:SetWidth(1)
		end
	end
	guide.focus = focus

	local bubble = CreateFrame("Frame", nil, layer)
	bubble:SetFrameLevel(layer:GetFrameLevel() + 2)
	bubble:SetWidth(BUBBLE_WIDTH)
	solid(bubble, "BACKGROUND", 0, 0.87, 0.64, 0.24)
	solid(bubble, "BORDER", 1, 0.12, 0.09, 0.05)
	bubble.progress = bubble:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	bubble.progress:SetPoint("TOPLEFT", 12, -9)
	bubble.label = bubble:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	bubble.label:SetPoint("TOPLEFT", 12, -25)
	bubble.label:SetWidth(BUBBLE_WIDTH - 24)
	bubble.label:SetJustifyH("LEFT")
	bubble.back = makeButton(bubble, BACK or L["UFNavBack"], function() guide:Go(guide.step - 1) end)
	bubble.back:SetPoint("BOTTOMLEFT", 10, 9)
	bubble.next = makeButton(bubble, L["CooldownPanelGuideNext"], function() guide:Go(guide.step + 1) end)
	bubble.next:SetPoint("BOTTOMRIGHT", -10, 9)
	guide.bubble = bubble

	frame.editorGuide = guide
	local helpButton = frame.helpButton
	local function hideTooltip(button)
		if GameTooltip and GameTooltip:IsOwned(button) then GameTooltip:Hide() end
	end
	helpButton:SetScript("OnEnter", function(button)
		if not GameTooltip then return end
		GameTooltip:SetOwner(button, "ANCHOR_LEFT", -6, 0)
		GameTooltip:SetText(L["Cooldown Panels"], 1, 0.82, 0)
		GameTooltip:AddLine(L[guide.step and "CooldownPanelGuideStop" or "CooldownPanelGuideStart"], 1, 1, 1)
		GameTooltip:Show()
	end)
	helpButton:SetScript("OnLeave", hideTooltip)
	helpButton:SetScript("OnHide", hideTooltip)
	helpButton:SetScript("OnClick", function(button)
		hideTooltip(button)
		if guide.step then guide:Stop() else guide:Go(1) end
	end)
	frame:HookScript("OnHide", function() guide:Stop() end)
	frame.scroll:HookScript("OnVerticalScroll", function() guide:Refresh() end)
	return guide
end
