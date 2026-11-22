local _, addon = ...

local stockFrame
local stockHidden
local actionBarHiddenParent
local actionBarOriginalParent
local combatWatcher

local function shouldHideTotems(classTag)
	if not addon.db or not classTag then return false end
	local hideKey = classTag == "SHAMAN" and "shaman_HideTotem" or classTag:lower() .. "_HideTotemBar"
	if not addon.db[hideKey] then return false end
	return not addon.functions.IsEQoLUnitFrameEnabled("player")
end

local function hideStockFrame(frame)
	stockHidden = true
	frame:Hide()
end

local function updateStockFrame(shouldHide)
	local frame = _G.TotemFrame
	if not frame then return end
	if stockFrame ~= frame then
		stockFrame = frame
		stockHidden = nil
		frame:HookScript("OnShow", function(self)
			local _, classTag = UnitClass("player")
			if shouldHideTotems(classTag) then hideStockFrame(self) end
		end)
	end

	if shouldHide then
		if frame:IsShown() then hideStockFrame(frame) end
	elseif stockHidden then
		stockHidden = nil
		if frame.Update then frame:Update() end
	end
end

local function updateActionBar(frame, shouldHide)
	if shouldHide == (actionBarOriginalParent ~= nil) then return end
	if InCombatLockdown() then
		if not combatWatcher then
			combatWatcher = CreateFrame("Frame")
			combatWatcher:SetScript("OnEvent", function(self)
				self:UnregisterEvent("PLAYER_REGEN_ENABLED")
				addon.functions.UpdateBlizzardTotemVisibility()
			end)
		end
		combatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end

	-- The action bar has secure buttons and Blizzard still updates its shown state.
	if shouldHide then
		actionBarOriginalParent = frame:GetParent()
		if not actionBarHiddenParent then
			actionBarHiddenParent = CreateFrame("Frame", nil, UIParent)
			actionBarHiddenParent:SetAllPoints(UIParent)
			actionBarHiddenParent:Hide()
		end
		frame:SetParent(actionBarHiddenParent)
	else
		if frame:GetParent() == actionBarHiddenParent then frame:SetParent(actionBarOriginalParent) end
		actionBarOriginalParent = nil
	end
end

function addon.functions.UpdateBlizzardTotemVisibility()
	if not addon.db then return end
	local _, classTag = UnitClass("player")
	updateStockFrame(shouldHideTotems(classTag))
	if classTag == "SHAMAN" and addon.variables.isForever and not addon.variables.isTBC and _G.MultiCastActionBarFrame then
		updateActionBar(_G.MultiCastActionBarFrame, addon.db.shaman_HideTotemActionBar == true)
	end
end
