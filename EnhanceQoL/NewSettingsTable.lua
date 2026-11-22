local addonName, addon = ...

addon.variables.NewVersionTableEQOL = {
	-- 13.23.0
	chatIMInfoFontSize = true,
	DataPanel_microbar_iconClassColor = true,
	DataPanel_microbar_showIconTooltips = true,
	DataPanel_microbar_iconStyle = true,
	DataPanel_microbar_iconColor = true,
	DataPanel_microbar_iconGap = true,
	Bags_categoriesEditor = true,
	Bags_globalCategorySortReverse = true,
}

if addon.variables.isForever and not addon.variables.isTBC then
	-- 13.23.0
	addon.variables.NewVersionTableEQOL.shaman_HideTotemActionBar = true
end
