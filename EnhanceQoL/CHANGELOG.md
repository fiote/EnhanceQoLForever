# Changelog

## [13.24.4] - 2026-11-26

### Added

- Toggle the current-zone filter, quest NPC names, and the 3D waypoint from the Quest Tracker header. The buttons stay visible and are disabled in combat.
- Use Auction Sales Quick Sell to post bag items one offer at a time with Space or sell a selected item directly. Skip items and set an optional price floor.
- Preview mana costs on Resource Bars and the Player Unit Frame with a configurable texture and color. Shared Resource Bars support a separate Mana override.
- Choose the layer of the 3D waypoint relative to other interface windows.
- Buy stackable reagents and individual auctions from the Craft Shopper list. Confirmed purchases immediately update the missing quantities.
- Set Party Frame strata in Edit Mode and adjust the portrait strata and frame level while the portrait stays attached.
- Choose the minimum item quality for Floating Loot reward notifications.

### Changed

- The Auction Sales window matches the Auction House layout, groups identical items, and flags prices below vendor value. Open offers directly from each watchlist row.
- The Craft Shopper list uses the Auction House layout, with inline search and a compact purchase dialog.

### Fixed

- Auction Sales price suggestions ignore isolated low listings.
- Auction Sales Price History opens and switches date ranges without errors, and chart labels stay inside the panel.
- The Precise format in Custom Aura Containers shows hours and minutes on long buff and debuff timers.
- Tracked map pins you placed clear when you reach them.
- The Well Fed filter in the Food & Drink Macro excludes Clam Linguine and the other affected clam dishes.

## [13.24.3] - 2026-11-26

### Added

- Unit Frames: Show the PvP flag countdown on your player frame with configurable text position, font, and color.

### Fixed

- Experience Bar: The bar keeps its last progress when XP data is unavailable and hides when the game disables XP tracking.
- Cooldown Panels: Changing forms refreshes only the panels that need an update.
- Navigation: The 3D waypoint keeps its configured size after a UI reload.
- Food Buff Reminder: Clam Linguine and other previously missing Well Fed items appear in the food selection.

## [13.24.2] - 2026-11-25

### Added

- Class Buff Reminder: The buff keybind can also cast buffs for your group.
- Mover: Drag the trade window by its title bar.
- Floating Loot: Optionally show skill gains and their new ranks. Set the alignment of the rows and the side of the accent line independently.
- Experience Bar: Show session time, progress including completed quests, or quest and rested XP percentages. Text can be placed in two additional positions.
- Navigation: Adjust the size of the 3D waypoint under Graphics & Game Options.

### Changed

- Floating Loot: The animation preview plays on all visible loot, roll, and reward rows.
- Experience Bar: Quest and rested XP overlays appear side by side when both are enabled.
- Experience Bar: Session time and XP rate update while the bar is visible.

### Fixed

- Character and Inspect: Long enchantment labels wrap within their column, leaving room for sockets and item details.
- Inspect: The average item level is calculated from equipped gear and shown with one decimal place.
- Action Bars: Hiding the Pet Bar with Always Hidden also hides its tooltips.
- Micro Menu: The option to hide notification diamonds now works on Blizzard’s micro menu buttons.
- Navigation: The 3D waypoint follows newly placed map pins and clears when the pin is removed.

## [13.24.1] - 2026-11-25

### Added

- Loot: Enable Floating Loot to use a movable display for loot, group rolls, and received items, money, currencies, reputation, and quest XP. In Edit Mode, choose which rewards appear and customize the visible rows, appearance, animations, and roll timers. Three rewards appear at once by default, and additional rewards wait for a free row. When the junk deletion option is enabled and bags are full, its icon appears inside the loot window.

### Fixed

- Mover: You can now move the quest details popup by dragging its title bar.
- Navigation: The 3D quest marker hides when its distance reads 0 yards.

## [13.24.0] - 2026-11-24

### Added

- First Start Guide: Open `/eqol guide` to practice configuring the Player Frame, Resource Bars, and Damage Meter in Edit Mode, or try the Cooldown Panels editor tour. Explore a sample fight in the Damage Meter and jump to the relevant setting to enable a feature after practicing.
- Cooldown Panels: The Hover Buff Panel layout shows cooldowns and tracked auras when you hover over its launcher. Customize the opening direction, icons, labels, and appearance, and optionally show an active buff count. Start with a blank panel or load selected raid buff groups or the full raid buff preset.
- Class Buff Reminder: Track and use custom buff items from their icons, show bag counts and spell keybinds, and track a temporary weapon enchant across multiple weapon slots. The active buff count can be shown and styled in Edit Mode. Item presets can fill in the enchant automatically.
- Group Frames: Style portrait borders, decorations, level badges, and cast displays in Edit Mode. Party pet portraits have separate visibility, position, and scale controls.
- Unit Frames: Preview the old and new status text spacing before switching styles.
- Cooldown Panels: Start or stop the animated editor tour with the yellow info icon in the modern `/ecd` editor.
- Cooldown Panels: Added a Movement Speed aura preset.
- Auction House: Scan the market or search results in Auction Sales (`/eqolauction`) and set price and quantity targets. Browse saved prices by category or item quality, search by name, ID, or link, and open 7- or 30-day price charts. Saved prices can appear in tooltips and contribute to the estimated bag value.
- Buff Placement: Filter party and raid indicators by the recipient’s class.
- Frame Visibility: Set visibility rules and fade amount for the Shaman totem action bar.

### Changed

- Profiles: Choose whether to activate a profile when you create it. The settings distinguish the active character profile from the default for new characters.
- Bags: The switch for EnhanceQoL’s replacement bags is now in its own section under Bags & Inventory.
- Class Buff Reminder: On a fresh setup, reminders also appear while solo once the feature is enabled.

### Fixed

- Bags: Reordering toolbar buttons no longer prevents the bags or bank from opening. Missing item data no longer causes repeated category refreshes.
- Chat History: Large filtered histories load faster, and opening a mail or trade entry no longer freezes the game.
- Mail Log: Open All records collected gold.
- Cooldown Panels: Totem bars clear when their slots are empty.
- Data Panel: Entries keep their configured spacing and align correctly after text reflows.
- Button Sink: Menus opened from collected buttons stay open when automatic closing after a click is enabled.
- Unit Frames: Smoothed the leading edge of round, star, and hexagon portrait cast bars using the Solid texture.
- Party and Raid Frames: Heal absorb previews clear when leaving Edit Mode, even in combat.
- Food Buff Reminder: The food selected in the right-click menu is remembered across reloads.
- Minimap: The moon keeps its default position when no custom anchor or offset is set.
- Bags: The gold tooltip shows characters from the current ruleset and lists totals by faction.
- Action Bars: Hover over the main bar’s decorations or page arrows to reveal it and switch pages.
- Navigation: The 3D quest waypoint works again and remembers your choice across reloads. It hides inside the active quest area until the quest is ready to turn in.
