local parentAddonName = "EnhanceQoL"
local addon = select(2, ...)
if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

local L = LibStub("AceLocale-3.0"):GetLocale(parentAddonName)
local QF = {}
addon.QuestZoneFilter = QF

function QF.Enabled()
	return QF.active == true
end

function QF.Pinned(questID)
	local pins = addon.db and addon.db.questTrackerZonePins
	return type(pins) == "table" and pins[questID] == true
end

function QF.ReadZone()
	QF.quests = nil
	local mapID = C_Map.GetBestMapForUnit("player")
	if not mapID then return end
	-- Micro maps use their containing map; dungeon maps keep their own quest POIs.
	for _ = 1, 8 do
		local info = C_Map.GetMapInfo(mapID)
		if not info or info.mapType ~= Enum.UIMapType.Micro or not info.parentMapID or info.parentMapID == 0 then break end
		mapID = info.parentMapID
	end
	local quests = C_QuestLog.GetQuestsOnMap(mapID)
	if not quests then return end
	QF.quests = {}
	for _, info in ipairs(quests) do
		QF.quests[info.questID] = true
	end
end

-- Keep pending watches per character, outside exported/shared settings profiles.
function QF.Pending(create)
	local guid = UnitGUID("player")
	if not guid then return end
	local private = addon.functions.GetPrivateDB()
	if create and type(private.questTrackerZoneHidden) ~= "table" then private.questTrackerZoneHidden = {} end
	local characters = private.questTrackerZoneHidden
	if not characters then return end
	if create and type(characters[guid]) ~= "table" then characters[guid] = {} end
	return characters[guid]
end

function QF.Refresh()
	-- Quest-log data must be available before pruning saved pending watches.
	if not IsPlayerInWorld() or InCombatLockdown() then return end
	local enabled = QF.Enabled()
	local pending = QF.Pending(enabled)
	if not pending then return end
	QF.quests = nil
	if enabled then QF.ReadZone() end

	-- Use the native watch APIs only. Replacing tracker methods taints the shared
	-- container layout and later prevents ScenarioObjectiveTracker from reading auras.
	QF.changing = true
	if enabled and QF.quests then
		local watches = {}
		for i = 1, C_QuestLog.GetNumQuestWatches() do
			watches[#watches + 1] = C_QuestLog.GetQuestIDForQuestWatchIndex(i)
		end
		for _, questID in ipairs(watches) do
			if not C_QuestLog.IsWorldQuest(questID) and not QF.quests[questID] and not QF.Pinned(questID) then
				pending[questID] = true
				C_QuestLog.RemoveQuestWatch(questID)
				if C_QuestLog.GetQuestWatchType(questID) ~= nil then pending[questID] = nil end
			end
		end
	end
	for questID in pairs(pending) do
		local index = C_QuestLog.GetLogIndexForQuestID(questID)
		if not index or index == 0 or C_QuestLog.IsWorldQuest(questID) then
			pending[questID] = nil
		elseif not enabled or not QF.quests or QF.quests[questID] or QF.Pinned(questID) then
			-- A full watch list or a rejected add retains the entry for a later retry.
			if C_QuestLog.GetQuestWatchType(questID) == nil then C_QuestLog.AddQuestWatch(questID) end
			if C_QuestLog.GetQuestWatchType(questID) ~= nil then pending[questID] = nil end
		end
	end
	QF.changing = nil
	if not next(pending) then
		local private = addon.functions.GetPrivateDB()
		private.questTrackerZoneHidden[UnitGUID("player")] = nil
		if not next(private.questTrackerZoneHidden) then private.questTrackerZoneHidden = nil end
	end
end

function QF.QueueRefresh()
	if QF.changing or QF.queued then return end
	if not QF.Enabled() and not QF.Pending() then return end
	QF.queued = true
	RunNextFrame(function()
		QF.queued = nil
		QF.Refresh()
	end)
end

function QF.MenuQuestID(owner, context)
	if context and context.questID then return context.questID end
	if owner and owner.questID then return owner.questID end
	-- Tracker menus belong to the container, while the clicked header belongs to a quest block.
	for _, focus in ipairs(GetMouseFoci()) do
		local frame = focus
		for _ = 1, 8 do
			if not frame then break end
			if frame.parentModule and (frame.parentModule == _G.QuestObjectiveTracker or frame.parentModule == _G.CampaignQuestObjectiveTracker) then return frame.id end
			frame = frame.GetParent and frame:GetParent()
		end
	end
end

function QF.AddMenu(owner, root, context)
	if not QF.Enabled() then return end
	local questID = QF.MenuQuestID(owner, context)
	if not questID then return end
	root:CreateDivider()
	root:CreateCheckbox(L["questTrackerZoneAlwaysShow"], function() return QF.Pinned(questID) end, function()
		if type(addon.db.questTrackerZonePins) ~= "table" then addon.db.questTrackerZonePins = {} end
		local pinned = not QF.Pinned(questID)
		addon.db.questTrackerZonePins[questID] = pinned or nil
		-- Pinning from the quest log also starts normal tracking; unpinning only removes the exception.
		if pinned and C_QuestLog.GetQuestWatchType(questID) == nil then
			local pending = QF.Pending(true)
			if pending then pending[questID] = true end
		end
		QF.QueueRefresh()
	end)
end

function QF.Init()
	QF.active = addon.db and addon.db.questTrackerZoneFilter == true
	if not QF.Enabled() and not QF.Pending() then return end
	if not QF.watcher then
		QF.watcher = CreateFrame("Frame")
		for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "QUEST_POI_UPDATE", "QUEST_LOG_UPDATE", "PLAYER_REGEN_ENABLED", "QUEST_WATCH_LIST_CHANGED", "QUEST_REMOVED" }) do
			QF.watcher:RegisterEvent(event)
		end
		QF.watcher:SetScript("OnEvent", function(_, event, questID)
			if event == "QUEST_REMOVED" then
				local pending = QF.Pending()
				if pending then pending[questID] = nil end
			end
			QF.QueueRefresh()
		end)
	end
	if QF.Enabled() and not QF.menus then
		QF.menus = true
		Menu.ModifyMenu("MENU_QUEST_OBJECTIVE_TRACKER", QF.AddMenu)
		Menu.ModifyMenu("MENU_QUEST_MAP_LOG_TITLE", QF.AddMenu)
	end
	QF.QueueRefresh()
end

function QF.RegisterSettings(category, expandable)
	addon.functions.SettingsCreateCheckbox(category, {
		var = "questTrackerZoneFilter",
		text = L["questTrackerZoneFilter"],
		desc = L["questTrackerZoneFilter_desc"],
		newTagID = "questTrackerZoneFilter",
		parentSection = expandable,
		default = false,
		func = function(value)
			addon.db.questTrackerZoneFilter = value and true or false
			QF.Init()
		end,
	})
end
