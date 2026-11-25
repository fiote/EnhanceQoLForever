local _, addon = ...

local nav = C_Navigation
local tracking = Enum.SuperTrackingType
if not (nav and nav.GetFrame and nav.WasClampedToScreen and nav.GetDistance and nav.GetTargetState and tracking) then return end

local atlases = {
	[tracking.Quest] = "Navigation-Tracked-Icon",
	[tracking.UserWaypoint] = "Waypoint-MapPin-Tracked",
	[tracking.Content] = "Waypoint-MapPin-Tracked",
	[tracking.Corpse] = "Navigation-Tombstone-Icon",
}
local states = Enum.NavigationState
local isInsideQuestBlob = C_Minimap and C_Minimap.IsInsideQuestBlob
local hasUserWaypoint = C_Map and C_Map.HasUserWaypoint
local superTrack = C_SuperTrack
local canAutoTrackWaypoint = hasUserWaypoint and superTrack.IsSuperTrackingUserWaypoint and superTrack.SetSuperTrackedUserWaypoint

function addon.functions.CreateNavigationWaypointFallback()
	local getPrivateDB = addon.functions.GetPrivateDB
	local function isEnabled() return getPrivateDB().navigationWaypointFallback == true end
	local function getScale() return math.max(0.5, math.min(1.5, tonumber(getPrivateDB().navigationWaypointScale) or 1)) end
	local marker = CreateFrame("Frame", nil, UIParent)
	marker:SetSize(32, 32)
	marker:SetFrameStrata("TOOLTIP")
	marker:EnableMouse(false)
	marker:Hide()

	local visuals = CreateFrame("Frame", nil, marker)
	visuals:SetSize(32, 32)
	visuals:SetPoint("CENTER")
	visuals:SetScale(getScale())
	local icon = visuals:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("CENTER")
	local arrow = visuals:CreateTexture(nil, "OVERLAY")
	arrow:SetAtlas("Navigation-Tracked-Arrow", true)
	local distanceText = visuals:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	distanceText:SetPoint("TOP", icon, "BOTTOM", 0, -8)

	local anchor = nav.GetFrame()
	local attachedTo, lastX, lastY, lastDistance, atlas, trackingKind
	local transparentUntil = 0
	local pendingWaypointTrack

	local function cancelWaypointTrack()
		if not pendingWaypointTrack then return end
		pendingWaypointTrack:Cancel()
		pendingWaypointTrack = nil
	end

	local function trackPlacedWaypoint()
		pendingWaypointTrack = nil
		if isEnabled() and hasUserWaypoint() and not superTrack.IsSuperTrackingUserWaypoint() then superTrack.SetSuperTrackedUserWaypoint(true) end
	end

	local function place(self)
		-- The event can supply a usable anchor independently of the default marker's visibility.
		local x, y = anchor:GetCenter()
		if not x or not y or GetTime() < transparentUntil then
			self:SetAlpha(0)
			return
		end

		local clamped = nav.WasClampedToScreen()
		if clamped then
			local cx, cy = UIParent:GetCenter()
			if not cx or not cy then
				self:SetAlpha(0)
				return
			end

			local dx, dy = x - cx, y - cy
			local magnitude = math.sqrt((dx / 500) ^ 2 + (dy / 200) ^ 2)
			if magnitude == 0 then
				self:SetAlpha(0)
				return
			end

			if attachedTo ~= UIParent or lastX ~= dx or lastY ~= dy then
				self:ClearAllPoints()
				self:SetPoint("CENTER", UIParent, "CENTER", dx / magnitude, dy / magnitude)
				local radius = math.max(icon:GetSize()) / math.sqrt(dx * dx + dy * dy)
				arrow:SetPoint("CENTER", icon, "CENTER", dx * radius, dy * radius)
				arrow:SetRotation(math.atan2(-dx, dy))
				attachedTo, lastX, lastY = UIParent, dx, dy
			end
			distanceText:Hide()
		else
			if attachedTo ~= anchor then
				self:ClearAllPoints()
				self:SetPoint("CENTER", anchor, "CENTER")
				attachedTo = anchor
			end
			local distance = nav.GetDistance()
			if not (issecretvalue and issecretvalue(distance)) and type(distance) == "number" and distance >= 0 then
				distance = math.floor(distance + 0.5)
				if trackingKind == tracking.Quest and distance == 0 then
					if self:GetAlpha() ~= 0 then self:SetAlpha(0) end
					return
				end
				if distance ~= lastDistance then
					local text = distance >= 1000 and AbbreviateNumbers(distance) or tostring(distance)
					distanceText:SetText(IN_GAME_NAVIGATION_RANGE:format(text))
					lastDistance = distance
				end
				distanceText:Show()
			else
				distanceText:Hide()
			end
		end
		arrow:SetShown(clamped)
		local alpha = clamped and 1 or (nav.GetTargetState() == states.Occluded and 0.6 or 1)
		if self:GetAlpha() ~= alpha then self:SetAlpha(alpha) end
	end

	local function refresh(changedQuestID, isInside)
		local kind = superTrack.GetHighestPrioritySuperTrackingType()
		local nextAtlas = atlases[kind]
		if not (isEnabled() and anchor and nextAtlas) or (kind == tracking.UserWaypoint and hasUserWaypoint and not hasUserWaypoint()) then
			marker:Hide()
			return
		end
		if kind == tracking.Quest and isInsideQuestBlob then
			local questID = C_SuperTrack.GetSuperTrackedQuestID()
			if questID and not (issecretvalue and issecretvalue(questID)) and questID > 0 then
				if questID ~= changedQuestID then isInside = isInsideQuestBlob(questID) end
				if isInside and not C_QuestLog.ReadyForTurnIn(questID) then
					marker:Hide()
					return
				end
			end
		end
		if nextAtlas ~= atlas then
			icon:SetAtlas(nextAtlas, true)
			atlas, attachedTo = nextAtlas, nil
		end
		trackingKind = kind
		place(marker)
		marker:Show()
	end

	marker:RegisterEvent("PLAYER_ENTERING_WORLD")
	marker:RegisterEvent("NAVIGATION_FRAME_CREATED")
	marker:RegisterEvent("NAVIGATION_FRAME_DESTROYED")
	marker:RegisterEvent("SUPER_TRACKING_CHANGED")
	if canAutoTrackWaypoint then marker:RegisterEvent("USER_WAYPOINT_UPDATED") end
	if isInsideQuestBlob then
		marker:RegisterEvent("PLAYER_INSIDE_QUEST_BLOB_STATE_CHANGED")
		marker:RegisterEvent("QUEST_LOG_UPDATE")
		marker:RegisterEvent("QUEST_POI_UPDATE")
	end
	marker:SetScript("OnUpdate", place)
	marker:SetScript("OnEvent", function(_, event, region, isInside)
		if event == "NAVIGATION_FRAME_DESTROYED" then
			anchor = nil
		elseif event == "NAVIGATION_FRAME_CREATED" then
			anchor = region or nav.GetFrame()
		elseif event == "PLAYER_INSIDE_QUEST_BLOB_STATE_CHANGED" then
			refresh(region, isInside)
			return
		elseif event == "PLAYER_ENTERING_WORLD" then
			anchor = nav.GetFrame() or anchor
		elseif event == "SUPER_TRACKING_CHANGED" then
			anchor = nav.GetFrame() or anchor
			transparentUntil = GetTime() + 0.2
		elseif event == "USER_WAYPOINT_UPDATED" then
			if hasUserWaypoint() then
				-- The map click can finish changing super tracking after this event.
				if isEnabled() and not pendingWaypointTrack then pendingWaypointTrack = C_Timer.NewTimer(0, trackPlacedWaypoint) end
			else
				cancelWaypointTrack()
				if trackingKind == tracking.UserWaypoint then anchor = nav.GetFrame() end
			end
		end
		refresh()
	end)
	refresh()

	return {
		get = isEnabled,
		getScale = getScale,
		setScale = function(value)
			getPrivateDB().navigationWaypointScale = value
			visuals:SetScale(getScale())
		end,
		set = function(enabled)
			getPrivateDB().navigationWaypointFallback = enabled == true
			if not enabled then cancelWaypointTrack() end
			refresh()
			return true
		end,
	}
end
