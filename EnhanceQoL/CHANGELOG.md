# Changelog

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
