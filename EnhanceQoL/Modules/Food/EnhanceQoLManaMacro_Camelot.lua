local addon = _G.EnhanceQoL or select(2, ...)
local L = LibStub("AceLocale-3.0"):GetLocale("EnhanceQoL")
local C = addon.ForeverConsumables
local M = { name = "EnhanceQoLManaMacro" }

local function locked() return InCombatLockdown and InCombatLockdown() end

function addon.functions.updateManaMacro()
	if not addon.db or not addon.db.manaMacroEnabled or locked() then return end
	local _, class = UnitClass("player")
	local best, bestCooldown, bestPriority, bestItemRank
	local potionRanks = addon.ManaPotionPriority.GetRanks()
	local gemRanks = addon.ManaGemPriority.GetRanks()
	for _, entry in ipairs(C.items) do
		local gem = entry.category == "mana_gem"
		local potion = entry.category == "mana_potion" or entry.category == "healing_and_mana_potion"
		if (potion or (gem and class == "MAGE")) and C.IsEligible(entry) and C.GetCount(entry) > 0 and C.GetRecovery(entry, "mana") > 0 then
			C.RequestOwnedItemData(entry)
			local cooldown = C.GetCooldown(entry)
			local priority = (gem == (addon.db.manaMacroGemFirst ~= false)) and 1 or 2
			local itemRank = (gem and gemRanks[entry.id] or potionRanks[entry.id]) or math.huge
			if cooldown < math.huge and (not best or (cooldown == 0 and bestCooldown > 0) or ((cooldown == 0) == (bestCooldown == 0) and (priority < bestPriority or (priority == bestPriority and (itemRank < bestItemRank or (itemRank == bestItemRank and C.IsBetter(entry, best, "mana", false, cooldown, bestCooldown))))))) then
				best, bestCooldown, bestPriority, bestItemRank = entry, cooldown, priority, itemRank
			end
		end
	end
	local body = "#showtooltip"
	if best then body = string.format("#showtooltip item:%d\n/use item:%d", best.id, best.id) end
	if not addon.functions.EnsureGlobalMacro(M.name, "INV_Misc_QuestionMark", body, "manaMacroLimitReached", L["manaMacroLimitReached"]) then return end
	local _, _, currentBody = GetMacroInfo(M.name)
	if currentBody ~= body and not locked() then EditMacro(M.name, M.name, nil, body) end
end

M.frame = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "PLAYER_LEVEL_UP", "BAG_UPDATE_DELAYED", "BAG_UPDATE_COOLDOWN", "ITEM_DATA_LOAD_RESULT" }) do M.frame:RegisterEvent(event) end
M.frame:SetScript("OnEvent", function(_, event, itemID)
	if not addon.db or not addon.db.manaMacroEnabled then return end
	if event == "ITEM_DATA_LOAD_RESULT" and not C.requestedItems[itemID] then return end
	if locked() or M.pending then return end
	M.pending = true
	C_Timer.After(0.05, function()
		M.pending = nil
		addon.functions.updateManaMacro()
	end)
end)
