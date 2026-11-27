local addonName, addon = ...

addon.variables.NewVersionTableEQOL = {}

-- 13.24.4
if addon.variables.isForever and not addon.variables.isTBC then addon.variables.NewVersionTableEQOL.navigationWaypointStrata = true end
if not addon.variables.isTBC then addon.variables.NewVersionTableEQOL.questTrackerQuickToggles = true end
