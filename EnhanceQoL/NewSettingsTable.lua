local addonName, addon = ...

addon.variables.NewVersionTableEQOL = {}

-- 13.24.1
if not addon.variables.isTBC then addon.variables.NewVersionTableEQOL.MoverQuestLogPopupDetailFrame = true end
if not addon.variables.isTBC then addon.variables.NewVersionTableEQOL.enableFloatingLoot = true end
