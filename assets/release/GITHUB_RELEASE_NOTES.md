# Survivor Leveling & Advancement v1.2.1

- Reaching a skill's maximum level through XP now frees any advancement slots still occupied by that skill. Previously, you would be left with XP owed without a way to earn it, this resolves that edge case.
- Fixed the admin window's Refresh button failing when offline profile details were unavailable.
- Added the currently selected character's name to the admin window and made the selected offline profile stay visible.
- Survivor XP now rounds down to the nearest 10th in the admin window, matching the Skills panel.
- Fixed incorrect Survivor XP from single-player Player Stats grants with 'Use multipliers' unchecked when the sandbox XP multiplier was not 1x.
- Known multiplayer issue: when granting skill XP through Player Stats, leave 'Use multipliers' checked. With it unchecked and the applicable skill XP multiplier set to anything other than 1x, Survivor XP can be too high or too low. This refers to the vanilla sandbox XP settings, not SLA's Survivor XP multiplier. Skill XP and blue catch-up remain correct. This update fixes the single-player behavior, while the fix for hosted and dedicated multiplayer is deferred for further investigation.
