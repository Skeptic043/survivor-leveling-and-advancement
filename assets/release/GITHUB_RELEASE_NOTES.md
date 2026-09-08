# Survivor Leveling & Advancement v1.1.2

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
