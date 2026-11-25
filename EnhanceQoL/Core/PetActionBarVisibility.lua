local _, addon = ...

local hiddenParent
local originalParent
local combatWatcher
local pendingBar
local pendingHidden

local function SetPetActionBarHidden(bar, shouldHide)
	local parent = bar:GetParent()
	local isHidden = hiddenParent ~= nil and parent == hiddenParent
	if isHidden == shouldHide then
		if pendingBar == bar then
			pendingBar = nil
			combatWatcher:UnregisterEvent("PLAYER_REGEN_ENABLED")
		end
		return
	end

	if InCombatLockdown() then
		if not combatWatcher then
			combatWatcher = CreateFrame("Frame")
			combatWatcher:SetScript("OnEvent", function(self)
				self:UnregisterEvent("PLAYER_REGEN_ENABLED")
				local barToUpdate = pendingBar
				pendingBar = nil
				if barToUpdate then SetPetActionBarHidden(barToUpdate, pendingHidden) end
			end)
		end
		pendingBar = bar
		pendingHidden = shouldHide
		combatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end

	-- Keep Blizzard's own shown state current while its secure bar is concealed.
	if shouldHide then
		if not hiddenParent then
			hiddenParent = CreateFrame("Frame", nil, UIParent)
			hiddenParent:SetAllPoints(UIParent)
			hiddenParent:Hide()
		end
		originalParent = parent
		bar:SetParent(hiddenParent)
		local owner = GameTooltip:GetOwner()
		while owner and owner ~= bar do
			owner = owner:GetParent()
		end
		if owner then
			GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
			GameTooltip:Hide()
		end
	else
		bar:SetParent(originalParent)
		originalParent = nil
	end
end

addon.functions.SetPetActionBarHidden = SetPetActionBarHidden
