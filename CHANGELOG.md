# Changelog

All notable public changes will be documented here.

## 1.1.2 - 2026-09-08

- Changing a skill level through Player Stats debug menu now clears that skill's advancement accounting without refunding AP.
- Removed red recovery mechanic. Lost skill XP no longer blocks advancement or reduces Survivor XP earned as you regain it.
- Survivor XP now rounds down to the nearest 10th in the Skills panel so the display does not show XP you have not earned.
- The mastery tooltip now explains when it clears the skill's occupied advancement slots.
- Per-skill slot limits and Survivor XP contribution settings now follow the Skills panel order.
- Fixed disabled sandbox options sometimes using enabled values.
- Reduced SLA's processing overhead while earning XP and using the Skills panel.
- Fixed missing server replies leaving SLA advancement and admin controls stuck waiting.
- Player Stats level edits remain usable if SLA's initial check fails.
- Fixed inheritance being lost if saving the replacement survivor fails.
- Fixed XP for another skill being missed when awarded during an AP purchase.

## 1.1.1 - 2026-09-06

- Added administration for existing offline player profiles.
- Reduced server processing for SLA progress updates in worlds with many stored characters.
- Dead-character SLA profiles are now removed after their replacement character is created instead of being kept as unused history.
- Advancement tooltips now show the number of free slots required.
- Hover over Advancement Slots for a short explanation of how to free them.
- Added an optional high-contrast setting for advancement and recovery markers.
- Controller users can now see the XP needed to free advancement slots.
- Fixed the digital watch's Survivor XP percentage updating every frame instead of once per second.

## 1.1.0 - 2026-09-01

- Fixed the digital-watch Survivor XP percentage remaining visible over the full-screen world map.
- Added sandbox toggles for Survivor XP generation from each vanilla skill and one universal toggle for compatible custom skills.
- Replaced the SLA-only Workshop browse thumbnail with the full-name artwork.
- Clarified the dedicated-server shutdown and save-loss warning.

## 1.0.0 - 2026-08-30

- Earn independently paced Survivor XP from accepted trainable-skill XP.
- Gain one Advancement Point for each Survivor Level and spend it directly from the vanilla Skills panel.
- Choose Global, Per Skill, or Free advancement accounting through sandbox settings.
- Track AP-created advancement separately from natural skill progress, including visible catch-up and recovery states.
- Support compatible custom trainable skills through automatic curve normalization.
- Provide server-authoritative multiplayer progression, remote administration, and optional one-use Survivor Level inheritance.
- Show optional Player 1 Survivor XP progress inside the digital watch.
- Preserve accepted skill levels when SLA is disabled and reconcile supported skill changes when it is re-enabled.
