local AutoClear = {}
_G.EnhanceQoL.Bags.NewItemAutoClear = AutoClear

function AutoClear.GetDelay(settings)
	local value = tonumber(settings.newItemsAutoClearDelay)
	if not value or value ~= value then return -1 end
	return math.max(-1, math.min(60, math.floor(value + 0.5)))
end

local function cancelTimer(tracker)
	if tracker.timer then tracker.timer:Cancel() end
	tracker.timer, tracker.deadline = nil, nil
end

function AutoClear.Create(options)
	return { options = options, slots = {} }
end

local function getActiveDelay(settings)
	if settings.showNewItems == false or settings.oneBagMode == true then return -1 end
	return AutoClear.GetDelay(settings)
end

local function expire(tracker, now, delay)
	local options = tracker.options
	local nextDeadline
	local changed = false
	for bagID, slots in pairs(tracker.slots) do
		for slotID, entry in pairs(slots) do
			local deadline = entry.firstSeen + delay
			if deadline <= now then
				slots[slotID] = nil
				local info = C_Container.GetContainerItemInfo(bagID, slotID)
				if options.getIdentity(bagID, slotID, info) == entry.identity then
					if options.clearSlot(bagID, slotID) then changed = true end
				end
			elseif not nextDeadline or deadline < nextDeadline then
				nextDeadline = deadline
			end
		end
	end

	if tracker.deadline ~= nextDeadline then
		cancelTimer(tracker)
		if nextDeadline then
			tracker.deadline = nextDeadline
			tracker.timer = C_Timer.NewTimer(nextDeadline - now, function()
				tracker.timer, tracker.deadline = nil, nil
				local settings = options.getSettings()
				local currentDelay = getActiveDelay(settings)
				if settings ~= tracker.settings or currentDelay < 0 or not options.isEnabled() then
					tracker.settings, tracker.slots = nil, {}
				elseif expire(tracker, GetTime(), currentDelay) then
					options.requestRefresh()
				end
			end)
		end
	end
	return changed
end

function AutoClear.Update(tracker, settings, visible, scan)
	local delay = getActiveDelay(settings)
	local settingsChanged = tracker.settings ~= settings
	if settingsChanged or (delay < 0 and tracker.delay ~= delay) then
		cancelTimer(tracker)
		tracker.slots = {}
	end
	tracker.settings = settings
	local delayChanged = tracker.delay ~= delay
	tracker.delay = delay
	if delay < 0 then return false end
	if not settingsChanged and not delayChanged and not (visible and scan) then return false end
	local now = GetTime()

	if visible and (scan or settingsChanged or delayChanged) then
		local options = tracker.options
		local current = {}
		for bagID = options.firstBag, options.lastBag do
			local slots = tracker.slots[bagID]
			for slotID = 1, C_Container.GetContainerNumSlots(bagID) or 0 do
				local info = C_Container.GetContainerItemInfo(bagID, slotID)
				if options.isNew(bagID, slotID, info) then
					local identity = options.getIdentity(bagID, slotID, info)
					if identity then
						current[bagID] = current[bagID] or {}
						local saved = slots and slots[slotID]
						current[bagID][slotID] = saved and saved.identity == identity and saved or { identity = identity, firstSeen = now }
					end
				end
			end
		end
		tracker.slots = current
	end
	return expire(tracker, now, delay)
end
