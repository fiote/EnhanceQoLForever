local addon = _G.EnhanceQoL
local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL")
local Meter = addon.DamageMeter

-- Spell IDs available in all supported flavors. Totals and rates belong to the selected sample.
local sampleAbilities = {
	DRUID = { { 5176, 136006 }, { 8921, 136096 } },
	WARRIOR = { { 78, 132282 }, { 772, 132155 } },
	HUNTER = { { 75, 132369 }, { 3044, 132218 } },
	MAGE = { { 133, 135812 }, { 116, 135846 } },
	PALADIN = { { 26573, 135926 }, { 20271, 135959 } },
}

local function disableWindowInput(frame)
	frame:EnableMouse(false)
	frame:EnableMouseWheel(false)
	for _, child in ipairs({ frame:GetChildren() }) do disableWindowInput(child) end
end

function Meter:CreateFirstStartPreview(parent, onAction)
	local config, session, formatNumber = self:GetFirstStartPreviewData()
	local preview = setmetatable({
		windows = {},
		windowStyleVersions = {},
		GetConfig = function() return config end,
		IsWindowEnabled = function() return true end,
		GetEffectiveDamageMeterType = function() return "DamageDone" end,
		ApplyWindowAnchor = function() end,
	}, { __index = self })
	local frame = preview:EnsureWindow(1, parent)
	frame:SetFrameStrata("TOOLTIP")
	frame:SetFrameLevel(parent:GetFrameLevel() + 1)
	frame:SetPoint("CENTER", parent)
	local count = math.min(config.visibleRows, #session.combatSources)
	for i = 1, count do preview:CreateRow(frame, i) end
	preview:ApplyWindowStyle(1, count)
	frame.empty:Hide()
	frame.moveHandle:Hide()
	frame.resizeButton:Hide()
	disableWindowInput(frame)

	frame.returnButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	frame.returnButton:SetPoint("TOP", frame, "BOTTOM", 0, -8)
	frame.returnButton:SetText(L["FirstStepsDemoTotals"])
	frame.returnButton:SetSize(math.max(100, frame.returnButton:GetTextWidth() + 24), 25)

	local function display(player)
		local abilities = player and sampleAbilities[player.classFilename]
		local list = abilities or session.combatSources
		frame.header:SetText(player and player.name or L["damageMeterTypeDamageDone"])
		frame.returnButton:SetShown(player ~= nil)
		for i, row in ipairs(frame.rows) do
			local entry = list[i]
			row:SetShown(entry ~= nil)
			if entry then
				local name, icon = entry.name, entry.specIconID
				local amount, rate, maximum = entry.totalAmount, entry.amountPerSecond, session.maxAmount
				if abilities then
					local id = entry[1]
					name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id) or (L["Spell"] .. " " .. id)
					icon = entry[2]
					local fraction = i == 1 and 0.65 or 0.35
					amount, rate = player.totalAmount * fraction, player.amountPerSecond * fraction
					maximum = player.totalAmount * 0.65
				end
				local colors = preview:GetRowColorState(frame, config, (player or entry).classFilename)
				row.icon:SetTexture(icon)
				row.name:SetText(name)
				row.name:SetTextColor(colors.nr, colors.ng, colors.nb, colors.na)
				preview:ApplyRankText(row, i, config)
				row.bar:SetMinMaxValues(0, maximum)
				row.bar:SetValue(amount)
				row.bar:SetStatusBarColor(colors.r, colors.g, colors.b, colors.a)
				amount, rate = formatNumber(amount, config.abbreviation), formatNumber(rate, config.abbreviation)
				row.value:SetText(row._damageMeterUseValueColumns and amount or (amount .. " | " .. rate))
				row.rateValue:SetText(row._damageMeterUseValueColumns and rate or "")
				row:EnableMouse(onAction ~= nil and player == nil)
			end
		end
	end
	for i, row in ipairs(frame.rows) do
		for _, script in ipairs({ "OnMouseDown", "OnMouseUp", "OnEnter", "OnLeave" }) do row:SetScript(script, nil) end
		row:RegisterForClicks("LeftButtonUp")
		row:SetScript("OnClick", function()
			display(session.combatSources[i])
			onAction("details")
		end)
	end
	frame.returnButton:SetScript("OnClick", function()
		display(nil)
		onAction("totals")
	end)
	frame.ResetPreview = function(_, width, height)
		config.width, config.rowHeight = width, height
		preview.windowStyleVersions[1] = (preview.windowStyleVersions[1] or 0) + 1
		preview:ApplyWindowStyle(1, count)
		display(nil)
	end
	if not onAction then
		local defaultWidth, defaultHeight = config.width, config.rowHeight
		local function refreshLayout()
			preview.windowStyleVersions[1] = preview.windowStyleVersions[1] + 1
			preview:ApplyWindowStyle(1, count)
			display(nil)
		end
		preview.windowStyleVersions[1] = 0
		frame.GetPreviewValue = function(_, field) return config[field] end
		frame.SetPreviewValue = function(_, field, value)
			config[field] = value
			refreshLayout()
		end
		frame.ResetEditPreview = function()
			config.width, config.rowHeight = defaultWidth, defaultHeight
			refreshLayout()
		end
	end
	return frame
end
