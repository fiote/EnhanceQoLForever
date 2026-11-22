local addon = _G.EnhanceQoL
addon.Aura = addon.Aura or {}

-- Shared Forever food-buff coverage for reminders and aura presets.
addon.Aura.ForeverWellFedSpellIDs = {
	19705, 19706, 19708, 19709, 19710, 19711, 24799, 24870, 25661, 25694, 25941,
	470361, 470367, 1225778, 1225779, 1225780, 1225782, 1248406, 1248420, 1248421,
	1248422, 1248688, 1249519, 1249520, 1249521, 1249523, 1249907, 1249926, 1249927,
	1294007, 1302064, 1319310,
}

-- Mana recovery aura variants used by Forever consumables.
addon.Aura.ForeverDrinkSpellIDs = {
	430, 431, 432, 1133, 1135, 1137, 10250, 22734, 24355, 25696,
	26261, 26402, 26473, 26475, 29007, 446714, 468767,
}
