local addonName, addon = ...

addon.variables.NewVersionTableEQOL = {}

-- 13.24.0
addon.variables.NewVersionTableEQOL.firstStartGuide = true

if addon.variables.isForever and not addon.variables.isTBC then
	-- 13.24.0
	addon.variables.NewVersionTableEQOL.shaman_TotemActionBarVisibility = true
	addon.variables.NewVersionTableEQOL.vendorAuctionSales = true
	addon.variables.NewVersionTableEQOL.vendorAuctionSalesSection = true
	addon.variables.NewVersionTableEQOL.vendorAuctionBagFooter = true
	addon.variables.NewVersionTableEQOL.vendorAuctionBagFooterValue = true
	addon.variables.NewVersionTableEQOL.vendorAuctionBagFooterDelta = true
	addon.variables.NewVersionTableEQOL.vendorAuctionPriceTooltip = true
	addon.variables.NewVersionTableEQOL.vendorAuctionHistoryTooltip = true
	addon.variables.NewVersionTableEQOL.vendorAuctionDateFormat = true
end
