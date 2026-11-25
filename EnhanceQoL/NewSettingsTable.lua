local addonName, addon = ...

addon.variables.NewVersionTableEQOL = {}

-- 13.24.2
addon.variables.NewVersionTableEQOL.MoverTradeFrame = true
if addon.variables.isForever and not addon.variables.isTBC then addon.variables.NewVersionTableEQOL.navigationWaypointScale = true end
