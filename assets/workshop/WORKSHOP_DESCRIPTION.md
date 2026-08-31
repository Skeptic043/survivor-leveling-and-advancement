# Survivor Leveling & Advancement [B42]

Level your skills through normal play while at the same time progressing your Survivor Level, acquiring Advancement Points to boost your progress while keeping natural skill progression important.

## How it works

SLA gives each character a separate Survivor Level. Supported trainable skill XP also earns Survivor XP, with each Survivor Level granting one Advancement Point, or AP. AP can then be spent in the vanilla skills panel to raise the level of a selected skill, spending the required AP and occupying the required number of Advancement Slots. In order to earn a slot back, you must naturally earn the XP in the skill the AP was spent to bypass, while that same XP still applies toward your next level.

## Advancement modes

- **Global:** Shares one configurable pool of Advancement Slots across every skill, with a default limit of 3 active slots in total.
- **Per Skill:** Gives each skill its own configurable slot limit, using a default for compatible custom skills and optional overrides for vanilla skills.
- **Free:** Removes Advancement Slot limits and catch-up or recovery restrictions while selected; switching back to Global or Per Skill restores any remaining prior tracked obligation instead of clearing it.

In Global and Per Skill modes, losing levels or XP (Fitness/Strength) puts that skill into a recovery state that grants no Survivor XP until the lost progress is recovered.

The final advancement to a skill's effective maximum, normally level 9 to level 10, requires 2 AP to 'master' the skill along with 2 free Advancement Slots, and clears any active Advancement Slots on the skill. If you have Global or Per Skill Advancement Slot limits set to 1, then mastery requires 1 free Advancement Slot while retaining the 2 AP cost. Free mode requires no Advancement Slots while retaining the 2 AP cost.

Survivor Level inheritance is configured through sandbox settings and allows the host to set a percentage of a deceased character's Survivor Level that passes to that player's next eligible survivor. The optional digital watch percentage is enabled per client through Mod Options and shows Player 1's progress toward the next Survivor Level.

## Features

- Integrated directly into the vanilla skills panel
- Global, Per Skill, and Free advancement slot modes
- A separately configurable Survivor XP multiplier that does not change skill XP
- Configurable Fitness and Strength contribution to Survivor XP
- Automatic curve normalization for compatible custom skills
- Configurable global, default per-skill, and vanilla-skill-specific Advancement Slot limits
- Server-authoritative multiplayer progression
- Online-player administration for inspecting progression, awarding XP or levels, and clearing advancements
- Full controller support for spending AP
- Split-screen compatible
- Optional Survivor Level inheritance after death
- Optional Player 1 Survivor XP percentage inside the digital watch

## Adding or removing SLA

SLA is designed to be safely added and removed from existing saves. Existing skills are preserved and historical progression is not converted into retroactive Survivor Levels.

Disabling SLA removes its interface while leaving skill levels already gained through AP in place. Re-enabling SLA restores its private state and reconciles supported skill progression that occurred while it was absent.

Regardless, I recommend backing up your save before changing the mod list of an ongoing world.

## Multiplayer administration

Authorized administrators can open "Admin Panel > Mini Scoreboard" or "Admin Panel > Users List", right-click an online player, and choose "Survivor progression". Administrators can inspect progression, award positive Survivor XP or whole Survivor Levels, clear active Advancement Slots (without refunding AP or changing skill XP), and refresh the target state. An administrator can manage their own SLA progression from the "Admin" button in the Skills panel. Administration is limited to online players.

## Compatibility

- **Incompatible: [RPG Skills Systems B42 / RPGMenu](https://steamcommunity.com/sharedfiles/filedetails/?id=3666281346)**

- **Unsupported currently: [Beyond Ten - Level 15 Skills](https://steamcommunity.com/sharedfiles/filedetails/?id=3765241705) and [Seesaw Game](https://steamcommunity.com/sharedfiles/filedetails/?id=3515515643)**. These mods directly replace progression rules that SLA relies on.

- **Load-order dependent: [Detailed Skill Tooltips](https://steamcommunity.com/sharedfiles/filedetails/?id=3572846242)**. Load SLA after Detailed Skill Tooltips to append SLA's blue/red accounting text to DST's expanded skill tooltip. If SLA loads first, only SLA's blue/red accounting text is replaced, while Survivor Level progression and the + button tooltips remain functional.

- **Tested together: [Detailed Skill Tooltips](https://steamcommunity.com/sharedfiles/filedetails/?id=3572846242), [Toughness Skill](https://steamcommunity.com/sharedfiles/filedetails/?id=3545533939), and [Show Skill XP Gain B42.20](https://steamcommunity.com/sharedfiles/filedetails/?id=3776490883)**. This combination worked without issue, but compatibility with every interface or custom-skill mod cannot be guaranteed.

## Current limits

- A skill at its effective maximum does not generate additional Survivor XP.
- Direct skill setters or third-party progression routes that emit no supported XP event do not generate Survivor XP.
- Dedicated servers should set the native `SaveWorldEveryMinutes` option to a nonzero value. Abrupt termination can lose SLA progression written after the last successful server save; a shorter interval reduces that window.
- Only English text is currently included.

## AI Use

AI was used to write all of the code in this project. The original concept, design direction, testing, debugging, and release decisions are my own. I spent many hours personally testing SLA and working through issues to make sure it behaves as intended. I'm grateful that AI tools helped me turn the idea into something I can share with the community. If you prefer not to use mods developed with AI assistance, I understand and respect that choice.

## Support

Optional support: [Ko-fi](https://ko-fi.com/skeptic043). All donations are strictly optional and no mod features are locked behind a paywall.

## Mod information

- Target version: Project Zomboid Build 42.20
- Developed and tested on: Project Zomboid 42.20.4
- Required dependencies: None
- License: MIT
- [Source and issue tracker](https://github.com/Skeptic043/survivor-leveling-and-advancement)
