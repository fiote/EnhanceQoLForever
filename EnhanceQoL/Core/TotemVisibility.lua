local _, addon = ...

local stockFrame
local stockHidden
local actionBarHiddenParent
local actionBarOriginalParent
local combatWatcher
local actionBarAlphaWatcher
local actionBarFade

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

local function refreshActionBarAlpha()
	local state = actionBarFade
	local frame = state.frame
	local flyout = _G.MultiCastFlyoutFrame
	local openButton = _G.MultiCastFlyoutFrameOpenButton
	local summonButton = _G.MultiCastSummonSpellButton
	local summonFlyout = summonButton and summonButton.flyoutButton
	local mouseIsOver = addon.functions.MouseIsOver
	state.isMouseOver = state.rules.MOUSEOVER == true and frame:IsVisible() and (
		mouseIsOver(frame)
		or (flyout and flyout:IsVisible())
		or (openButton and openButton:IsVisible() and mouseIsOver(openButton))
		or (summonFlyout and summonFlyout:IsVisible() and mouseIsOver(summonFlyout))
	) or false
	local show, rule = addon.functions.ShouldShowVisibilityConfig(state.rules, state)
	local alpha = state.originalAlpha
	if not show and not frame.isInEditMode then
		local hidden = rule == "ALWAYS_HIDE_IN_GROUP" or rule == "ALWAYS_HIDE_IN_PARTY" or rule == "ALWAYS_HIDE_IN_RAID"
		alpha = hidden and 0 or alpha * (1 - addon.functions.GetFrameFadeStrength())
	end
	if state.alpha == alpha then return end
	state.alpha = alpha
	-- Leave Blizzard in control of the secure buttons, anchoring and shown state.
	frame:SetAlpha(alpha)
end

local function updateActionBarFade(frame, rules)
	if not rules or not next(rules) then
		if not actionBarFade then return end
		actionBarAlphaWatcher:SetScript("OnUpdate", nil)
		actionBarAlphaWatcher:UnregisterAllEvents()
		actionBarFade.frame:SetAlpha(actionBarFade.originalAlpha)
		actionBarFade = nil
		return
	end

	if not actionBarFade then
		actionBarFade = { frame = frame, originalAlpha = frame:GetAlpha() }
		actionBarAlphaWatcher = actionBarAlphaWatcher or CreateFrame("Frame")
		local elapsed = 0
		actionBarAlphaWatcher:SetScript("OnUpdate", function(_, delta)
			elapsed = elapsed + delta
			if elapsed < (actionBarFade.rules.MOUSEOVER and 0.05 or 0.2) then return end
			elapsed = 0
			refreshActionBarAlpha()
		end)
		actionBarAlphaWatcher:SetScript("OnEvent", refreshActionBarAlpha)
		actionBarAlphaWatcher:RegisterEvent("PLAYER_REGEN_DISABLED")
		actionBarAlphaWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
	end
	actionBarFade.rules = rules
	refreshActionBarAlpha()
end

function addon.functions.UpdateBlizzardTotemVisibility()
	if not addon.db then return end
	local _, classTag = UnitClass("player")
	updateStockFrame(shouldHideTotems(classTag))
	if classTag == "SHAMAN" and addon.variables.isForever and not addon.variables.isTBC and _G.MultiCastActionBarFrame then
		local frame = _G.MultiCastActionBarFrame
		if type(addon.db.actionBarTotemVisibility) == "string" or addon.db.shaman_HideTotemActionBar ~= nil then
			addon.functions.CleanupTotemActionBarProfile(addon.db)
		end
		local rules = addon.db.actionBarTotemVisibility
		local hidden = rules and rules.ALWAYS_HIDDEN == true
		updateActionBar(frame, hidden == true)
		updateActionBarFade(frame, not hidden and not actionBarOriginalParent and rules)
	end
end
