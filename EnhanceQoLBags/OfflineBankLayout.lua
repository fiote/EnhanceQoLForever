local addon = _G.EnhanceQoL
local M = addon.Bags.OfflineBank
local L = addon.L
local V = { sources = setmetatable({}, { __mode = "k" }) }
M.Layout = V
V.builtinSort = { equipment = "itemLevel", consumables = "count", tradegoods = "count", recipes = "quality", quest = "quality", misc = "quality" }
V.sortFields = { itemLevel = "itemLevel", quality = "quality", name = "name", count = "count", sellPrice = "value", expansion = "expansionID", keystoneLevel = "keystoneLevel" }
V.ignoredSlots = { [""] = true, INVTYPE_BAG = true, INVTYPE_BODY = true, INVTYPE_NON_EQUIP_IGNORE = true, INVTYPE_QUIVER = true, INVTYPE_TABARD = true }

function V.CaptureItem(item, bagID, slotID, info)
	item.isBound = info.isBound
	local quest = C_Container.GetContainerItemQuestInfo and C_Container.GetContainerItemQuestInfo(bagID, slotID)
	item.isQuestItem, item.questID = quest and quest.isQuestItem, quest and quest.questID
	local rules = addon.Bags.ItemRules
	local observed = rules and rules.snapshots[tostring(bagID) .. ":" .. tostring(slotID)]
	if observed and observed.itemID == item.itemID and observed.itemLink == item.link and observed.count == item.count then
		if V.sources[item] ~= observed then
			item.ruleContext = rules.CopyContext(observed)
			item.ruleContext.bagID, item.ruleContext.slotID = nil, nil
			V.sources[item] = observed
		end
	elseif item.ruleContext and (item.ruleContext.itemID ~= item.itemID or item.ruleContext.itemLink ~= item.link) then
		item.ruleContext, V.sources[item] = nil, nil
	end
end

function V.DefaultCategory(context)
	if context.isQuestItem or context.questID or context.classID == 12 then return "quest" end
	if context.equipLoc and not V.ignoredSlots[context.equipLoc] then return "equipment" end
	local class = context.classID
	if class == 2 or class == 4 then return "equipment" end
	return ({ [0] = "consumables", [7] = "tradegoods", [9] = "recipes" })[class] or "misc"
end

function V.Context(item, metadata)
	local context = {}
	for key, value in pairs(item.ruleContext or {}) do context[key] = value end
	local capturedItemLevel = context.itemLevel
	local ref = item.link or item.itemID
	local facts = metadata[ref]
	if not facts then
		facts = addon.Bags.ItemRules.GetRuleItemInfo(ref) or {}
		metadata[ref] = facts
	end
	for key, value in pairs(facts) do
		if key ~= "statuses" and key ~= "loaded" then context[key] = value end
	end
	context.itemID, context.itemLink, context.count = item.itemID, item.link or facts.itemLink, item.count or 1
	context.quality = item.quality or facts.itemQuality
	if item.isBound ~= nil then context.isBound = item.isBound end
	if item.isQuestItem ~= nil then context.isQuestItem, context.questID = item.isQuestItem, item.questID
	elseif item.questID ~= nil then context.questID = item.questID end
	context.equipLoc, context.subClassID = facts.itemEquipLoc or context.equipLoc, facts.subclassID or context.subClassID
	if context.classID == nil or context.equipLoc == nil then
		local _, _, _, equipLoc, _, classID, subclassID = C_Item.GetItemInfoInstant(ref)
		context.equipLoc, context.classID, context.subClassID = context.equipLoc or equipLoc, context.classID or classID, context.subClassID or subclassID
	end
	context.subClassKey = context.classID and context.subClassID and (context.classID .. ":" .. context.subClassID) or nil
	context.professionGroupKey = context.professionGroupKey or (addon.GetProfessionGroupKeyForItem and addon.GetProfessionGroupKeyForItem(context.classID, context.subClassID, item.itemID))
	context.itemLevel = capturedItemLevel or facts.itemLevel
	context.canVendor = (context.sellPrice or 0) > 0
	context.defaultCategory = V.DefaultCategory(context)
	context.offline, context.bagID, context.slotID = true, nil, nil
	return context
end

function V.Sort(section)
	local mode, reverse = addon.ResolveCategorySortMode(section.definition, V.builtinSort)
	local field = mode and V.sortFields[mode]
	if not field then return end
	table.sort(section.items, function(a, b)
		if reverse then a, b = b, a end
		local left, right = a[field], b[field]
		if left ~= right then
			if mode == "name" then return left < right end
			return left > right
		end
		if a.quality ~= b.quality then return a.quality > b.quality end
		if a.name ~= b.name then return a.name < b.name end
		return a.order < b.order
	end)
end

function V.Build(snapshot)
	local settings = addon.GetSettings()
	local oneBag = addon.GetOneBagMode()
	local categories = settings.showCategories == true and not oneBag
	local definitions = categories and addon.GetCategorySectionDefinitions() or { { id = "all", sortMode = addon.ResolveCategorySortMode({ id = "misc" }, V.builtinSort), collapsible = false } }
	local sections, byID, metadata, count = {}, {}, {}, 0
	for _, definition in ipairs(definitions) do
		local section = { id = definition.id, definition = definition, items = {}, combined = {} }
		sections[#sections + 1], byID[definition.id] = section, section
	end
	for _, bagID in ipairs(snapshot and snapshot.order or {}) do
		local bag = snapshot.bags[bagID]
		for slotID = 1, bag.slots do
			local item = bag.items[slotID]
			if item then
				local context = not oneBag and V.Context(item, metadata) or {}
				local id = "all"
				if categories then
					id = addon.GetMatchingCustomCategoryID(context) or addon.NormalizeCategorySectionID(context.defaultCategory)
				end
				local section = byID[id]
				if section and not (categories and addon.IsCategorySectionHidden(id)) then
					local key
					if not oneBag and settings.combineUnstackableItems then
						key = ((item.count or 1) > 1 or (context.itemStackCount or 0) > 1) and item.itemID or (item.link or item.itemID)
					end
					local row = key and section.combined[key]
					if row then
						row.count = row.count + (item.count or 1)
						row.value = row.price * row.count
					else
						count = count + 1
						row = { item = item, bagID = bagID, slotID = slotID, count = item.count or 1, order = count, desaturated = section.definition.desaturateItems == true,
							name = string.lower(context.itemName or ""), quality = context.quality or -1,
							price = context.sellPrice or 0, itemLevel = context.itemLevel or 0,
							expansionID = context.expansionID or -1, keystoneLevel = tonumber((item.link or ""):match("keystone:%d+:%d+:(%d+)")) or 0 }
						row.value = row.price * row.count
						section.items[#section.items + 1] = row
						if key then section.combined[key] = row end
					end
				end
			end
		end
	end
	local visible = {}
	for _, section in ipairs(sections) do
		if #section.items > 0 then
			if not oneBag then V.Sort(section) end
			visible[#visible + 1] = section
		end
	end
	return visible
end

function V.Options()
	local scale = addon.GetItemScale() / 100
	local size, spacing = math.max(24, math.floor(37 * scale + 0.5)), math.max(2, math.floor(4 * scale + 0.5))
	local indent = addon.GetCategoryTreeView() and addon.GetCategoryTreeIndent() or 0
	local frameScale = addon.GetBagFrameScale() / 100
	frameScale = math.min(frameScale, (UIParent:GetWidth() - 40) / math.max(480, size * 4 + spacing * 3 + indent * 2 + 60), (UIParent:GetHeight() - 40) / 300)
	local available = math.max(size * 4 + spacing * 3, UIParent:GetWidth() / frameScale - 100 - indent * 2)
	local columns = math.max(4, math.min(addon.GetBankMaxColumns(), math.floor((available + spacing) / (size + spacing))))
	return { size = size, spacing = spacing, columns = columns, width = columns * (size + spacing) - spacing,
		scale = frameScale, gap = addon.GetCompactCategoryGap(), compact = addon.GetSettings().showCategories and not addon.GetOneBagMode() and addon.GetCompactCategoryLayout(),
		indent = indent }
end

function V.Collapsed(id)
	local settings = addon.GetSettings()
	local collapsed = settings.collapsedBankSections or settings.collapsedWarbandSections
	return id and collapsed and collapsed[id] == true or false
end

function V.ToggleCollapsed(id)
	local settings = addon.GetSettings()
	settings.collapsedBankSections = settings.collapsedBankSections or settings.collapsedWarbandSections or {}
	settings.collapsedWarbandSections = settings.collapsedBankSections
	settings.collapsedBankSections[id] = not settings.collapsedBankSections[id] or nil
	M.Render()
end

function V.Header(label, color, key, element, x, y, width, height)
	V.headerCount = V.headerCount + 1
	local header = M.headers[V.headerCount]
	if not header then
		header = CreateFrame("Button", nil, M.content)
		header.Text = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		header.Text:SetPoint("LEFT")
		header.Text:SetJustifyH("LEFT")
		header:SetScript("OnClick", function(self) if self.collapseID then V.ToggleCollapsed(self.collapseID) end end)
		M.headers[V.headerCount] = header
	end
	header.collapseID = key
	header:EnableMouse(key ~= nil)
	header:ClearAllPoints()
	header:SetPoint("TOPLEFT", M.content, "TOPLEFT", x, -y)
	header:SetSize(math.max(1, width), height)
	addon.ApplyConfiguredFont(header.Text, nil, element)
	header.Text:SetText((key and (V.Collapsed(key) and "+ " or "- ") or "") .. addon.FormatTextElement(element, label))
	header.Text:SetTextColor(unpack(color or { 1, 0.82, 0 }))
	header.Text:SetWidth(width)
	header.Text:SetWordWrap(false)
	header:Show()
end

function V.Metrics(section, options)
	local definition = section.definition
	local header = definition.label or definition.labelKey
	local collapsed = definition.collapsible ~= false and V.Collapsed(section.id)
	local columns = math.max(1, math.min(options.columns, #section.items))
	local rows = collapsed and 0 or math.ceil(#section.items / columns)
	local element = definition.groupID and "subcategoryHeader" or "categoryHeader"
	local appearance = addon.GetResolvedTextAppearance(element)
	local headerHeight = header and math.max(18, appearance.size + 4) or 0
	local headerWidth = 0
	if header then
		V.measure = V.measure or M.content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		V.measure:Hide()
		addon.ApplyConfiguredFont(V.measure, nil, element)
		V.measure:SetText(addon.FormatTextElement(element, definition.label or L[definition.labelKey]))
		headerWidth = math.min(options.width, math.ceil(V.measure:GetStringWidth()) + 16)
	end
	return { itemCount = #section.items, sectionColumnCount = options.columns, visibleColumns = columns, rows = rows,
		blockWidth = columns * (options.size + options.spacing) - options.spacing,
		blockHeight = headerHeight + (headerHeight > 0 and rows > 0 and 6 or 0) + rows * (options.size + options.spacing) - (rows > 0 and options.spacing or 0),
		headerHeight = headerHeight, headerWidth = headerWidth, collapsed = collapsed }
end

function V.BlockWidth(_, metrics)
	return math.max(metrics.blockWidth + V.currentOptions.indent, metrics.headerWidth)
end

function V.PlaceSection(section, options, metrics, x, y, width)
	local definition = section.definition
	local header = definition.label or (definition.labelKey and L[definition.labelKey])
	local indent = header and options.indent or 0
	if header then
		V.Header(header, definition.color, definition.collapsible ~= false and section.id or nil,
			definition.groupID and "subcategoryHeader" or "categoryHeader", x, y, width, metrics.headerHeight)
		y = y + metrics.headerHeight + (not metrics.collapsed and 6 or 0)
	end
	if metrics.collapsed then return end
	for index, row in ipairs(section.items) do
		V.buttonCount = V.buttonCount + 1
		local button = M.GetButton(V.buttonCount)
		button.item, button.bagID, button.slotID = row.item, row.bagID, row.slotID
		button.sectionID, button.itemCount = section.id, row.count
		button:SetSize(options.size, options.size)
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", M.content, "TOPLEFT", x + indent + ((index - 1) % metrics.visibleColumns) * (options.size + options.spacing),
			-y - math.floor((index - 1) / metrics.visibleColumns) * (options.size + options.spacing))
		button.Icon:SetTexture(row.item.icon or C_Item.GetItemIconByID(row.item.itemID) or 134400)
		button.Icon:SetDesaturated(row.desaturated or definition.desaturateItems == true)
		button._bagsRenderTexture = row.item.icon or C_Item.GetItemIconByID(row.item.itemID) or 134400
		addon.ApplyItemButtonSkin(button, row.item.quality)
		addon.ApplyConfiguredFont(button.Count, nil, "stackCount")
		local anchor = addon.GetStackCountAnchor()
		button.Count:ClearAllPoints()
		button.Count:SetPoint(anchor, button, anchor, anchor:find("LEFT") and 2 or -2, anchor:find("TOP") and -2 or 2)
		button.Count:SetText(row.count > 1 and row.count or "")
		button:Show()
	end
end

function V.Render(snapshot)
	local options = V.Options()
	V.currentOptions = options
	M.frame:SetScale(options.scale)
	M.frame:SetWidth(math.max(480, options.width + options.indent * 2 + 60))
	M.frame:SetHeight(math.min(480, UIParent:GetHeight() / options.scale - 40))
	M.content:SetWidth(M.frame:GetWidth() - 58)
	local skin = addon.GetActiveSkinDefinition().frame
	addon.ApplyFrameBackgroundSkin(M.frame, skin)
	M.frame:SetBackdropBorderColor(0, 0, 0, 0)
	local sections = V.Build(snapshot)
	M.sections = sections
	V.headerCount, V.buttonCount = 0, 0
	V.spacers = V.spacers or {}
	local spacerCount = 0
	local y, index, activeGroup = 0, 1, nil
	while index <= #sections do
		local section = sections[index]
		local definition = section.definition
		if definition.groupID ~= activeGroup then
			activeGroup = definition.groupID
			if activeGroup then
				if definition.groupSpacerBefore and y > 0 then y = y + 14 end
				if not definition.groupHideTitle then
					local height = math.max(18, addon.GetResolvedTextAppearance("categoryHeader").size + 4)
					V.Header(definition.groupLabel, definition.groupColor, definition.groupCollapseID, "categoryHeader", 0, y, options.width, height)
					y = y + height + 6
				end
			end
		end
		local groupCollapsed = activeGroup and not definition.groupHideTitle and V.Collapsed(definition.groupCollapseID)
		if definition.spacerBefore and not groupCollapsed then
			spacerCount = spacerCount + 1
			local line = V.spacers[spacerCount]
			if not line then line = M.content:CreateTexture(nil, "ARTWORK"); V.spacers[spacerCount] = line end
			local color = skin and skin.dividerColor or { 1, 1, 1, 0.08 }
			line:ClearAllPoints(); line:SetPoint("TOPLEFT", M.content, "TOPLEFT", 0, -y)
			line:SetPoint("RIGHT", M.content, "RIGHT", 0, 0); line:SetHeight(1)
			line:SetColorTexture(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 0.08)
			line:Show(); y = y + 7
		end
		if groupCollapsed then
			repeat index = index + 1 until index > #sections or sections[index].definition.groupID ~= activeGroup
		elseif activeGroup and definition.groupCombineSubcategories then
			local combined = { id = section.id, items = {}, definition = { desaturateItems = definition.desaturateItems, collapsible = false } }
			repeat
				for _, row in ipairs(sections[index].items) do combined.items[#combined.items + 1] = row end
				index = index + 1
			until index > #sections or sections[index].definition.groupID ~= activeGroup or not sections[index].definition.groupCombineSubcategories or sections[index].definition.spacerBefore
			local metrics = V.Metrics(combined, options)
			V.PlaceSection(combined, options, metrics, options.indent, y, options.width)
			y = y + metrics.blockHeight + 10
		else
			local entries, group = {}, definition.groupID
			local last = index
			repeat
				local candidate = sections[last]
				local metrics = V.Metrics(candidate, options)
				entries[#entries + 1] = { section = candidate, metrics = metrics, collapsed = metrics.collapsed }
				last = last + 1
			until not options.compact or last > #sections or sections[last].definition.groupID ~= group or sections[last].definition.groupCombineSubcategories or sections[last].definition.spacerBefore
			local row, _, height
			if options.compact then
				row, _, height = addon.Bags.PlanCompactRow(entries, options.width - (group and options.indent or 0), options.gap, options.size, options.spacing, 10, V.BlockWidth)
			else row, height = { entries[1] }, entries[1].metrics.blockHeight end
			local x = group and options.indent or 0
			for _, entry in ipairs(row) do
				local width = options.compact and V.BlockWidth(entry.section, entry.metrics) or options.width
				V.PlaceSection(entry.section, options, entry.metrics, x, y, width)
				x = x + width + options.gap
			end
			index = index + #row
			y = y + height + 10
		end
	end
	for i = spacerCount + 1, #V.spacers do V.spacers[i]:Hide() end
	if snapshot and #sections == 0 then V.Header(EMPTY, nil, nil, "categoryHeader", 0, 0, options.width, 20); y = 24 end
	M.content:SetHeight(math.max(1, y))
end
