-- luacheck: globals SendMailFrame_SendMail SendMailFrame_Reset
local parentAddonName = "EnhanceQoL"
local addonName, addon = ...
if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local L = addon.L
local MU = MenuUtil

local Mailbox = addon.Mailbox or {}
addon.Mailbox = Mailbox

local function getPrivateDB() return addon.functions and addon.functions.GetPrivateDB and addon.functions.GetPrivateDB() or addon.privateDB or {} end

local function usesSurnames() return addon.variables and addon.variables.isForever and not addon.variables.isTBC end

local function getForeverContacts(create)
	local history = addon.ChatIM and addon.ChatIM.ChannelHistory
	local gameType = history and history:GetCurrentGameType()
	local faction = UnitFactionGroup("player")
	if not gameType or (faction ~= "Alliance" and faction ~= "Horde") then return end

	-- Keep old profile contacts intact for compatibility. They lack the metadata needed for Forever mail.
	local privateDB = getPrivateDB()
	local directory = privateDB.mailboxContactsForever
	if not directory then
		if not create then return end
		directory = {}
		privateDB.mailboxContactsForever = directory
	end

	local scope = gameType .. ":" .. faction
	if create and not directory[scope] then directory[scope] = {} end
	return directory[scope]
end

local function normalizeMailboxContacts()
	if not addon or not addon.db then return nil end
	if usesSurnames() then return getForeverContacts() end
	local contacts = addon.db.mailboxContacts
	if type(contacts) == "table" then return contacts end

	local normalized = {}
	if type(contacts) == "string" and contacts ~= "" then
		local name, realm = contacts:match("^([^%-]+)%-(.+)$")
		name = name or contacts
		realm = realm or ""
		normalized[contacts] = {
			name = name,
			realm = realm,
		}
	end
	addon.db.mailboxContacts = normalized
	return normalized
end

Mailbox.NormalizeContacts = normalizeMailboxContacts

Mailbox.enabled = Mailbox.enabled or false
Mailbox.frame = Mailbox.frame or nil
Mailbox.searchText = Mailbox.searchText or ""
Mailbox.hooked = Mailbox.hooked or false
Mailbox.eventFrame = Mailbox.eventFrame or nil
Mailbox.rows = Mailbox.rows or {}
Mailbox.filtered = Mailbox.filtered or {}
Mailbox.sortKey = Mailbox.sortKey or "name"
Mailbox.sortAsc = Mailbox.sortAsc ~= false -- default true
Mailbox.seeded = Mailbox.seeded or false
Mailbox.lastRecipient = Mailbox.lastRecipient or nil
Mailbox.rememberHooksInit = Mailbox.rememberHooksInit or false
Mailbox.rememberHooksAttached = Mailbox.rememberHooksAttached or false
Mailbox.rememberEventFrame = Mailbox.rememberEventFrame or nil

local ROW_HEIGHT = 20
local widths = { 130, 92 }
local panelLayout = {
	rowHeight = 23,
	nameWidth = 128,
	listWidth = 246,
	scrollbarGutter = 16,
	forever = {
		surface = { 0.09, 0.07, 0.05, 1 },
		border = { 0.34, 0.26, 0.17, 1 },
		header = { 0.32, 0.24, 0.16, 1 },
		alternate = { 0.15, 0.11, 0.075, 1 },
		text = { 0.87, 0.78, 0.62 },
		hover = { 1, 0.78, 0.32, 0.18 },
	},
	retail = {
		surface = { 0.06, 0.07, 0.09, 1 },
		border = { 0.28, 0.30, 0.34, 1 },
		header = { 0.20, 0.22, 0.26, 1 },
		alternate = { 0.10, 0.12, 0.15, 1 },
		text = { 0.74, 0.78, 0.85 },
		hover = { 0.57, 0.72, 0.93, 0.22 },
	},
}

local function ensureDB()
	if not addon or not addon.db then return end
	if addon.functions and addon.functions.InitDBValue then
		addon.functions.InitDBValue("enableMailboxAddressBook", false)
		addon.functions.InitDBValue("mailboxContacts", {})
		addon.functions.InitDBValue("mailboxRememberLastRecipient", false)
	else
		addon.db.enableMailboxAddressBook = addon.db.enableMailboxAddressBook or false
		addon.db.mailboxContacts = addon.db.mailboxContacts or {}
		addon.db.mailboxRememberLastRecipient = addon.db.mailboxRememberLastRecipient or false
	end
	normalizeMailboxContacts()
end

local function stopMailboxDrag(frame)
	if not frame.mailboxDragging then return end
	frame.mailboxDragging = nil
	frame:StopMovingOrSizing()
	frame:SetUserPlaced(false)
end

local function getClassColor(class)
	local tbl = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS) or {}
	local c = tbl[class] or { r = 1, g = 1, b = 1 }
	return c.r or 1, c.g or 1, c.b or 1
end

local function normalizeRealmForCompare(realm)
	if type(realm) ~= "string" then return "" end
	return realm:gsub("[%s%-']", ""):lower()
end

local function lowerNoSpaces(value)
	return (value or ""):lower():gsub("%s", "")
end

local function buildRecipientForMail(name, realm, fallback)
	if usesSurnames() then return name end
	local recipientName = name
	local recipientRealm = realm

	if (not recipientName or recipientName == "") and type(fallback) == "string" and fallback ~= "" then
		recipientName, recipientRealm = fallback:match("^([^%-]+)%-(.+)$")
		if not recipientName or recipientName == "" then
			recipientName = fallback
			recipientRealm = recipientRealm or ""
		end
	end

	if not recipientName or recipientName == "" then return fallback end

	local myRealm = select(2, UnitFullName("player"))
	myRealm = myRealm or GetRealmName() or ""
	local normalizedRecipientRealm = normalizeRealmForCompare(recipientRealm)
	local normalizedMyRealm = normalizeRealmForCompare(myRealm)
	if normalizedRecipientRealm == "" or normalizedRecipientRealm == normalizedMyRealm then return recipientName end

	return string.format("%s-%s", recipientName, recipientRealm or "")
end

local function rememberRecipientEnabled() return addon.db and addon.db.mailboxRememberLastRecipient end

local function clearRememberedRecipient() Mailbox.lastRecipient = nil end

local function captureRememberedRecipient()
	if not rememberRecipientEnabled() then return end
	if not SendMailNameEditBox then return end
	local name = SendMailNameEditBox:GetText()
	if name and name ~= "" then
		Mailbox.lastRecipient = name
	else
		Mailbox.lastRecipient = nil
	end
end

local function restoreRememberedRecipient()
	if not rememberRecipientEnabled() then return end
	if not MailFrame or not MailFrame:IsShown() then return end
	if not SendMailNameEditBox then return end
	local name = Mailbox.lastRecipient
	if name and name ~= "" then
		SendMailNameEditBox:SetText(name)
		SendMailNameEditBox:HighlightText(0, 0)
	end
end

local mailboxFilteredSort

local function mailboxDisplayContactSort(a, b)
	return (a.sortKey or "") < (b.sortKey or "")
end

function Mailbox:EnsureRememberRecipientHooks()
	if self.rememberHooksInit then return end
	self.rememberHooksInit = true

	local function tryHook()
		if self.rememberHooksAttached then return end
		if type(SendMailFrame_SendMail) ~= "function" or type(SendMailFrame_Reset) ~= "function" then return end
		hooksecurefunc("SendMailFrame_SendMail", captureRememberedRecipient)
		hooksecurefunc("SendMailFrame_Reset", restoreRememberedRecipient)
		self.rememberHooksAttached = true
	end

	local frame = self.rememberEventFrame
	if not frame then
		frame = CreateFrame("Frame")
		self.rememberEventFrame = frame
	end
	frame:RegisterEvent("ADDON_LOADED")
	frame:RegisterEvent("MAIL_SHOW")
	frame:RegisterEvent("MAIL_CLOSED")
	frame:SetScript("OnEvent", function(_, event, addonName)
		if event == "ADDON_LOADED" then
			if addonName ~= "Blizzard_MailFrame" then return end
			tryHook()
		elseif event == "MAIL_SHOW" then
			tryHook()
		elseif event == "MAIL_CLOSED" then
			clearRememberedRecipient()
		end
	end)

	tryHook()
end

function Mailbox:SetRememberRecipientEnabled(v)
	ensureDB()
	addon.db.mailboxRememberLastRecipient = v and true or false
	if addon.db.mailboxRememberLastRecipient then
		self:EnsureRememberRecipientHooks()
	else
		clearRememberedRecipient()
	end
end

function Mailbox:AddSelfToContacts()
	ensureDB()
	if not addon.db.enableMailboxAddressBook then return end

	local forever = usesSurnames()
	local name = forever and addon.functions.GetUnitDisplayName("player") or UnitName("player")
	if not name or name == "" then return end
	local realm = forever and "" or GetRealmName() or ""
	local class = select(2, UnitClass("player")) or "PRIEST"
	local r, g, b = getClassColor(class)
	local key = forever and name or string.format("%s-%s", name, realm)

	local contacts
	if forever then
		contacts = getForeverContacts(true)
	else
		contacts = normalizeMailboxContacts()
	end
	if not contacts then return end
	local rec = contacts[key] or {}
	rec.name = name
	rec.realm = realm
	rec.class = class
	rec.color = { r = r, g = g, b = b }
	contacts[key] = rec
end

local function filteredContacts()
	ensureDB()
	local list = {}
	local needle = (Mailbox.searchText or ""):lower()
	local contacts = normalizeMailboxContacts() or {}
	for key, rec in pairs(contacts) do
		if type(rec) ~= "table" then rec = { name = key, realm = "" } end
		local display = key
		local matchStr = (rec.name or "") .. "-" .. (rec.realm or "")
		if needle == "" or string.find(matchStr:lower(), needle, 1, true) then
			local r, g, b = 1, 1, 1
			if rec.class then
				r, g, b = getClassColor(rec.class)
			end
			table.insert(list, {
				key = key,
				display = string.format("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255, display),
				sortKey = (rec.name or key):lower(),
			})
		end
	end
	table.sort(list, mailboxDisplayContactSort)
	return list
end

local function onMailboxRowClick(button, mouseButton)
	button:OnClick(mouseButton)
end

-- HybridScroll row mixin
local RowMixin = {}
function RowMixin:OnAcquired()
	if self.initialized then return end
	self.bg = self:CreateTexture(nil, "BACKGROUND")
	self.bg:SetAllPoints(self)
	self.bg:SetColorTexture(0, 0, 0, 0)

	self.cols = {}
	local theme = Mailbox.frame.theme
	self.theme = theme
	if theme == panelLayout.forever then self:SetWidth(panelLayout.listWidth + panelLayout.scrollbarGutter) end
	local x = 0
	for i, w in ipairs(Mailbox.frame.columnWidths or widths) do
		local font = theme and i == 1 and "GameFontHighlight" or "GameFontHighlightSmall"
		local fs = self:CreateFontString(nil, "OVERLAY", font)
		fs:SetPoint("LEFT", x + (theme and 8 or 0), 0)
		fs:SetWidth(w - (theme and 14 or 0))
		fs:SetJustifyH("LEFT")
		if theme then
			fs:SetWordWrap(false)
			if i == 2 then fs:SetTextColor(unpack(theme.text)) end
		end
		self.cols[i] = fs
		x = x + w
	end
	if theme then
		local hover = self:CreateTexture(nil, "HIGHLIGHT")
		hover:SetAllPoints()
		hover:SetColorTexture(unpack(theme.hover))
	else
		self:SetHighlightTexture("Interface/QuestFrame/UI-QuestTitleHighlight")
	end
	self:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	self:SetScript("OnClick", onMailboxRowClick)
	self.initialized = true
end

function RowMixin:Init(elementData, index)
	self.key = elementData.key
	self.name = elementData.name
	self.realm = elementData.realm
	self.cols[1]:SetText(elementData.nameColored or elementData.name or "")
	if self.cols[2] then self.cols[2]:SetText(usesSurnames() and "" or elementData.realm or "") end
	if self.theme then self.bg:SetColorTexture(unpack(index % 2 == 0 and self.theme.alternate or self.theme.surface)) end
end

function RowMixin:OnClick(button)
	if button == "RightButton" then
		local key = self.key
		if not key then return end
		MU.CreateContextMenu(self, function(_, root)
			root:CreateTitle(usesSurnames() and (self.name or key) or key)
			root:CreateButton(REMOVE, function()
				local contacts = normalizeMailboxContacts()
				if contacts and contacts[key] then
					contacts[key] = nil
					if addon.Mailbox and addon.Mailbox.RefreshList then addon.Mailbox:RefreshList(true) end
				end
			end)
		end)
		return
	end

	if SendMailNameEditBox and self.key then
		local recipient = buildRecipientForMail(self.name, self.realm, self.key)
		SendMailNameEditBox:SetText(recipient or self.key)
		SendMailNameEditBox:HighlightText(0, 0)
		SendMailNameEditBox:ClearFocus()
	end
end

function Mailbox:UpdateVisibility()
	if not self.enabled then
		if self.frame then self.frame:Hide() end
		return
	end
	if not MailFrame then return end
	if not self.frame then self.frame = _G.EQOLMailboxFrame end
	-- The Lua file can initialize after login before the following XML creates the frame.
	if not self.frame then return end

	local shouldShow = MailFrame:IsShown() and (SendMailFrame and SendMailFrame:IsShown())
	if shouldShow then
		-- Match MailFrame height to avoid awkward gaps
		self.frame:SetHeight(MailFrame:GetHeight() or 430)
		self.frame:SetFrameStrata(MailFrame:GetFrameStrata() or "MEDIUM")
		self.frame:Show()
		if self.EnsureRows then self:EnsureRows() end
		self:RefreshList(true)
	else
		self.frame:Hide()
	end
end

local function ensureHooks()
	if Mailbox.hooked then return end
	Mailbox.hooked = true
	local function updateMailboxVisibilityDeferred()
		if addon.Mailbox then addon.Mailbox:UpdateVisibility() end
	end

	local function onMailboxEvent(_, event)
		if event == "MAIL_SHOW" then
			RunNextFrame(updateMailboxVisibilityDeferred)
		elseif event == "MAIL_SEND_INFO_UPDATE" then
			if addon.Mailbox then addon.Mailbox:RefreshList() end
		else -- MAIL_CLOSED
			if addon.Mailbox and addon.Mailbox.frame then addon.Mailbox.frame:Hide() end
		end
	end

	-- Events for show/hide
	Mailbox.eventFrame = Mailbox.eventFrame or CreateFrame("Frame")
	Mailbox.eventFrame:RegisterEvent("MAIL_SHOW")
	Mailbox.eventFrame:RegisterEvent("MAIL_CLOSED")
	Mailbox.eventFrame:RegisterEvent("MAIL_SEND_INFO_UPDATE")
	Mailbox.eventFrame:SetScript("OnEvent", onMailboxEvent)

	-- Also watch tab changes to update visibility
	hooksecurefunc("MailFrameTab_OnClick", function()
		if addon.Mailbox then addon.Mailbox:UpdateVisibility() end
	end)
end

function Mailbox:SetEnabled(v)
	ensureDB()
	self.enabled = v and true or false
	if self.enabled then
		-- Immediately add current character on enable
		self:AddSelfToContacts()
		-- Seed from moneyTracker if present and mailbox is empty
		local privateDB = getPrivateDB()
		local contacts = normalizeMailboxContacts()
		if not usesSurnames() and addon.db and contacts and next(contacts) == nil and type(privateDB.moneyTracker) == "table" then
			for guid, info in pairs(privateDB.moneyTracker) do
				if type(info) == "table" and info.name then
					local name = info.name
					local realm = info.realm or GetRealmName() or ""
					local class = info.class or select(2, UnitClass("player"))
					local r, g, b = getClassColor(class)
					local key = string.format("%s-%s", name, realm)
					contacts[key] = {
						name = name,
						realm = realm,
						class = class,
						color = { r = r, g = g, b = b },
					}
				end
			end
		end
		ensureHooks()
		-- If frame is loaded via XML OnLoad we already have it; else it will appear later
		self:UpdateVisibility()
	else
		if self.frame then self.frame:Hide() end
	end
end

mailboxFilteredSort = function(a, b)
	local sk = Mailbox.sortKey
	local av, bv
	if sk == "name" then
		av = a.name:lower()
		bv = b.name:lower()
		if av == bv then
			av = a.realm:lower()
			bv = b.realm:lower()
		end
	elseif sk == "realm" then
		av = (a.realm or ""):lower()
		bv = (b.realm or ""):lower()
	else
		av = a.name:lower()
		bv = b.name:lower()
	end
	if Mailbox.sortAsc then
		return av < bv
	else
		return av > bv
	end
end

-- Build filtered + sorted table from saved contacts
local function BuildFiltered()
	if not addon or not addon.db then
		wipe(Mailbox.filtered)
		return
	end
	-- If contacts are empty but we have moneyTracker info, import once
	local contacts = normalizeMailboxContacts() or {}
	local privateDB = getPrivateDB()
	local forever = usesSurnames()
	if not forever and not Mailbox.seeded and next(contacts) == nil and type(privateDB.moneyTracker) == "table" then
		for _, info in pairs(privateDB.moneyTracker) do
			if type(info) == "table" and info.name then
				local name = info.name
				local realm = info.realm or GetRealmName() or ""
				local class = info.class or select(2, UnitClass("player"))
				local r, g, b = getClassColor(class)
				local key = string.format("%s-%s", name, realm)
				contacts[key] = {
					name = name,
					realm = realm,
					class = class,
					color = { r = r, g = g, b = b },
				}
			end
		end
		Mailbox.seeded = true
	end
	if not contacts then
		wipe(Mailbox.filtered)
		return
	end
	wipe(Mailbox.filtered)
	-- determine own character to hide from list (normalize realms by removing spaces)
	local meName, meRealm
	if forever then
		meName = addon.functions.GetUnitDisplayName("player")
		meRealm = ""
	else
		meName, meRealm = UnitFullName("player")
		meRealm = meRealm or (GetRealmName() or "")
	end
	local myKeyLower = meName and (forever and meName or string.format("%s-%s", meName, meRealm)):lower()
	local myKeyLowerNS = lowerNoSpaces(myKeyLower)
	local needle = (Mailbox.searchText or ""):lower()
	for key, rec in pairs(contacts) do
		if type(rec) ~= "table" then rec = { name = key, realm = "" } end
		-- skip own character (compare raw-lower and also lower-without-spaces for realm)
		local skip = false
		if myKeyLower and key and key:lower() == myKeyLower then
			skip = true
		elseif not forever then
			local keyNS = lowerNoSpaces(key)
			if myKeyLowerNS and keyNS == myKeyLowerNS then
				skip = true
			elseif meName and rec then
				local rn = rec.name and rec.name:lower()
				local rr = lowerNoSpaces(rec.realm)
				if rn and rn == meName:lower() and rr == lowerNoSpaces(meRealm) then skip = true end
			end
		end
		if skip then
		-- continue
		else
			local name = rec.name or key
			local realm = rec.realm or ""
			local class = rec.class or ""
			local r, g, b = getClassColor(class)
			local displayName = string.format("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255, name)

			local match
			if needle == "" then
				match = true
			else
				if string.find(name:lower(), needle, 1, true) then match = true end
				if not match and realm ~= "" and string.find(realm:lower(), needle, 1, true) then match = true end
			end
			if match then table.insert(Mailbox.filtered, {
				key = key,
				name = name,
				nameColored = displayName,
				realm = realm,
			}) end
		end
	end

	table.sort(Mailbox.filtered, mailboxFilteredSort)
end

local function mailboxHeaderOnClick(self)
	if Mailbox.sortKey ~= self.sortKey then
		Mailbox.sortKey = self.sortKey
		Mailbox.sortAsc = true
	else
		Mailbox.sortAsc = not Mailbox.sortAsc
	end
	Mailbox:RefreshList(true)
end

local function mailboxScrollFrameUpdate()
	Mailbox:UpdateRows()
end

local function mailboxSearchBoxOnTextChanged(self)
	Mailbox.searchText = self:GetText() or ""
	if Mailbox.frame.theme then Mailbox.scrollFrame.scrollBar:SetValue(0) end
	Mailbox:RefreshList(true)
end

local function mailboxEnsureRowsAndRefresh()
	Mailbox:EnsureRows()
	Mailbox:UpdateRows()
end

local function mailboxLoginOnEvent()
	ensureDB()
	if addon.db.enableMailboxAddressBook then Mailbox:AddSelfToContacts() end
	-- Apply enable state once UI exists
	Mailbox:SetEnabled(addon.db.enableMailboxAddressBook)
	if addon.db.mailboxRememberLastRecipient then Mailbox:EnsureRememberRecipientHooks() end
end

function Mailbox:UpdateRows()
	if not self.scrollFrame or not self.rows then return end
	local buttons = self.rows
	local offset = HybridScrollFrame_GetOffset(self.scrollFrame)
	for i = 1, #buttons do
		local idx = i + offset
		local row = buttons[i]
		if self.filtered[idx] then
			row:Init(self.filtered[idx], idx)
			row:Show()
		else
			row:Hide()
		end
	end
	local displayed = self.scrollFrame:GetHeight() or (10 * ROW_HEIGHT)
	local height = self.frame.theme and panelLayout.rowHeight or ROW_HEIGHT
	HybridScrollFrame_Update(self.scrollFrame, #self.filtered * height, displayed)
	if self.frame.emptyText then
		local empty = #self.filtered == 0
		if empty then self.frame.emptyText:SetText(L[self.searchText == "" and "mailboxEmpty" or "mailboxNoMatchingCharacters"]) end
		self.frame.emptyText:SetShown(empty)
	end
end

function Mailbox:RefreshList(rebuild)
	if rebuild then BuildFiltered() end
	self:UpdateRows()
	if self.header and self.header.columns then
		for _, button in ipairs(self.header.columns) do
			local active = self.sortKey == button.sortKey
			local color = active and NORMAL_FONT_COLOR or HIGHLIGHT_FONT_COLOR
			button.label:SetTextColor(color.r, color.g, color.b)
		end
	end
end

local function createMailboxColumns(frame, modern)
	local columns = {
		{ key = "name", text = NAME },
		{ key = "realm", text = (FRIENDS_LIST_REALM or "Realm"):gsub(":%s*$", "") },
	}
	local header = Mailbox.header
	if modern then header.columns = {} end
	local x = 0
	for i, width in ipairs(frame.columnWidths or widths) do
		local column = columns[i]
		local button
		if modern then
			button = CreateFrame("Button", nil, header)
			button:SetPoint("TOPLEFT", header, "TOPLEFT", x, 0)
			button:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", x, 0)
			button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			button.label:SetPoint("LEFT", 8, 0)
			button.label:SetText(column.text)
			local hover = button:CreateTexture(nil, "HIGHLIGHT")
			hover:SetAllPoints()
			hover:SetColorTexture(unpack(frame.theme.hover))
			header.columns[i] = button
		else
			button = _G[header:GetName() .. "Col" .. i]
			local middle = _G[button:GetName() .. "Middle"]
			if middle then middle:SetWidth(width - 9) end
			button:SetText(column.text)
		end
		button:SetWidth(width)
		button.sortKey = column.key
		button:SetScript("OnClick", mailboxHeaderOnClick)
		x = x + width
	end
end

local function styleMailboxPanel(frame)
	local forever = usesSurnames()
	local theme = forever and panelLayout.forever or panelLayout.retail
	frame.theme = theme
	frame.columnWidths = forever and { panelLayout.listWidth } or { panelLayout.nameWidth, panelLayout.listWidth - panelLayout.nameWidth }
	if forever then
		Mailbox.sortKey = "name"
		local search, header, scroll = Mailbox.searchBox, Mailbox.header, Mailbox.scrollFrame
		search:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -33)
		header:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -60)
		header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -60)
		scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 12)
		local bar = scroll.scrollBar
		-- Let the stripes reach the list edge. Keep the scrollbar above the row buttons.
		bar:ClearAllPoints()
		bar:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", -1, -16)
		bar:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", -1, 16)
		bar:SetFrameLevel(scroll:GetFrameLevel() + 3)
	end

	local border = frame:CreateTexture(nil, "BACKGROUND")
	border:SetPoint("TOPLEFT", Mailbox.header, "TOPLEFT", -1, 1)
	border:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -11, 11)
	border:SetColorTexture(unpack(theme.border))

	local surface = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
	surface:SetPoint("TOPLEFT", Mailbox.header)
	surface:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 12)
	surface:SetColorTexture(unpack(theme.surface))

	local headerBackground = Mailbox.header:CreateTexture(nil, "BACKGROUND")
	headerBackground:SetAllPoints()
	headerBackground:SetColorTexture(unpack(theme.header))
	local divider = Mailbox.header:CreateTexture(nil, "ARTWORK")
	divider:SetPoint("TOPLEFT", Mailbox.header, "BOTTOMLEFT")
	divider:SetPoint("TOPRIGHT", Mailbox.header, "BOTTOMRIGHT")
	divider:SetHeight(1)
	divider:SetColorTexture(unpack(theme.border))

	frame.emptyText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.emptyText:SetPoint("CENTER", Mailbox.scrollFrame)
	frame.emptyText:SetWidth(panelLayout.listWidth - 24)
	frame.emptyText:SetTextColor(unpack(theme.text))
	frame.emptyText:SetWordWrap(true)
end

-- Frame OnLoad from XML
function EQOLMailboxFrame_OnLoad(frame, modern)
	ensureDB()
	Mailbox.frame = frame
	Mailbox.searchBox = _G[frame:GetName() .. "SearchBox"]
	Mailbox.header = _G[frame:GetName() .. "Header"]
	Mailbox.scrollFrame = _G[frame:GetName() .. "ScrollFrame"]
	Mailbox.scrollFrame.scrollBar = _G[frame:GetName() .. "ScrollFrameScrollBar"]

	frame:SetFrameStrata("DIALOG")
	local title = (L and L["MailboxWindowTitle"]) or "Address Book"
	local forever = modern and usesSurnames()
	if modern then
		styleMailboxPanel(frame)
		if forever then
			frame:SetBorder("ButtonFrameTemplateNoPortrait")
			frame:SetPortraitShown(false)
			frame:SetTitleOffsets(26, -26)
			frame:SetTitle(title)
		else
			frame.TitleText:SetText(title)
		end
		frame.CloseButton:SetSize(20, 20)
		frame.CloseButton:ClearAllPoints()
		frame.CloseButton:SetPoint("TOPRIGHT", -4, forever and 1 or 0)
	else
		frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		frame.title:SetPoint("TOP", frame, "TOP", 0, -6)
		frame.title:SetText(title)
	end

	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	if frame.SetDontSavePosition then frame:SetDontSavePosition(true) end
	frame:SetScript("OnDragStart", function(self)
		self:StartMoving()
		self.mailboxDragging = true
	end)
	frame:SetScript("OnDragStop", stopMailboxDrag)
	frame:HookScript("OnHide", stopMailboxDrag)
	if Mailbox.searchBox then frame:HookScript("OnMouseDown", function() Mailbox.searchBox:ClearFocus() end) end

	if not modern and Mailbox.searchBox then
		frame.searchLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		frame.searchLabel:SetPoint("RIGHT", Mailbox.searchBox, "LEFT", -5, 0)
		frame.searchLabel:SetText(SEARCH .. ":")
	end

	createMailboxColumns(frame, modern)

	function Mailbox:EnsureRows()
		if not self.scrollFrame then return end
		local have = (self.rows and #self.rows) or 0
		local height = self.scrollFrame:GetHeight() or 0
		-- Grow the existing pool once layout resolves; replacing it leaves visible orphan rows.
		local rowHeight = modern and panelLayout.rowHeight or ROW_HEIGHT
		local needed = math.ceil(height / rowHeight) + 1
		if have > 0 and have >= needed then return end

		HybridScrollFrame_CreateButtons(self.scrollFrame, "EQOLMailboxRowTemplate", modern and 0 or 5, modern and 0 or -6)
		self.rows = self.scrollFrame.buttons or {}
		self.scrollFrame.rows = self.rows
		for _, row in ipairs(self.rows) do
			Mixin(row, RowMixin)
			row:OnAcquired()
		end
		self.scrollFrame.update = mailboxScrollFrameUpdate
	end
	Mailbox:EnsureRows()

	-- Search box handler
	if modern then
		Mailbox.searchBox:SetAutoFocus(false)
		Mailbox.searchBox:HookScript("OnTextChanged", mailboxSearchBoxOnTextChanged)
		Mailbox.searchBox:HookScript("OnEnterPressed", function(box) box:ClearFocus() end)
	elseif Mailbox.searchBox then
		Mailbox.searchBox:SetScript("OnTextChanged", mailboxSearchBoxOnTextChanged)
	end

	-- Initial build
	Mailbox:RefreshList(true)
	-- Ensure rows even if OnLoad sizing was 0
	if not Mailbox.rows or #Mailbox.rows == 0 then RunNextFrame(mailboxEnsureRowsAndRefresh) end
	Mailbox:UpdateVisibility()
end

-- Called from XML OnShow to finalize rows after the frame has a real height
function EQOLMailboxFrame_OnShow(frame)
	if not addon or not addon.Mailbox then return end
	local mb = addon.Mailbox
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", MailFrame or UIParent, "TOPRIGHT", 6, 0)
	mb:EnsureRows()
	mb:RefreshList(true)
end

-- Register a local login listener to add the player if enabled
if not Mailbox.loginFrame then
	Mailbox.loginFrame = CreateFrame("Frame")
	Mailbox.loginFrame:SetScript("OnEvent", mailboxLoginOnEvent)
	if IsLoggedIn and IsLoggedIn() then
		mailboxLoginOnEvent()
	else
		Mailbox.loginFrame:RegisterEvent("PLAYER_LOGIN")
	end
end
