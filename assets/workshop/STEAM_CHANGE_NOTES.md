# Steam change notes

Copy the relevant version's text into Project Zomboid's Workshop change-note field for every upload. Keep it aligned with `CHANGELOG.md` and the corresponding GitHub Release.

## 1.1.1

- Added administration for existing offline player profiles.
- Reduced server processing for SLA progress updates in worlds with many stored characters.
- Dead-character SLA profiles are now removed after their replacement character is created instead of being kept as unused history.
- Advancement tooltips now show the number of free slots required.
- Hover over Advancement Slots for a short explanation of how to free them.
- Added an optional high-contrast setting for advancement and recovery markers.
- Controller users can now see the XP needed to free advancement slots.
- Fixed the digital watch's Survivor XP percentage updating every frame instead of once per second.

## 1.1.0

- Fixed the digital-watch Survivor XP percentage remaining visible over the full-screen world map.
- Added sandbox toggles for Survivor XP generation from each vanilla skill and one universal toggle for compatible custom skills.
- Replaced the SLA-only Workshop browse thumbnail with the full-name artwork.
- Clarified the dedicated-server shutdown and save-loss warning.

## 1.0.0

- Earn independently paced Survivor XP from accepted trainable-skill XP.
- Gain one Advancement Point for each Survivor Level and spend it directly from the vanilla Skills panel.
- Choose Global, Per Skill, or Free advancement accounting through sandbox settings.
- Track AP-created advancement separately from natural skill progress, including visible catch-up and recovery states.
- Support compatible custom trainable skills through automatic curve normalization.
- Provide server-authoritative multiplayer progression, remote administration, and optional one-use Survivor Level inheritance.
- Show optional Player 1 Survivor XP progress inside the digital watch.
- Preserve accepted skill levels when SLA is disabled and reconcile supported skill changes when it is re-enabled.
