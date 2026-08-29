# Survivor Leveling & Advancement [B42]

Level your skills through normal play while at the same time progressing your Survivor Level, acquiring Advancement Points to boost your progress while keeping natural skill progression important.

## How it works

Trainable skill XP also earns you Survivor XP, with each Survivor Level granting one Advancement Point, or AP. The AP can then be spent in the vanilla Skills panel to raise the level of a selected skill, consuming the needed AP and occupying the needed Advancement Slot capacity to do so. By default, you are limited to 3 Advancement Slots across all skills. In order to earn a slot back, you must naturally earn the XP in the skill the AP was spent to bypass, while that same XP still applies towards your next level.

Losing levels or XP (Fitness/Strength) puts you into a recovery state that grants no Survivor XP from that skill until the lost progress is recovered.

Going from level 9 to level 10 requires 2 AP to 'master' the skill along with 2 free Advancement Slots, and clears any active Advancement Slots on the skill. If you have Global or Per Skill Advancement Slot limits set to 1, then mastery requires 1 free Advancement Slot while retaining the 2 AP cost. Free mode requires no Advancement Slots while retaining the 2 AP cost.

Optionally, there is also a sandbox Inheritance feature and a small digital watch integration in the settings. Inheritance allows the host to set a percentage of a deceased character's Survivor Level that passes to that player's next eligible survivor. The digital watch feature setting simply shows a small percentage on the watch interface that indicates how far into your current Survivor Level you are.

## Features

- Integrated directly into the vanilla Skills panel
- Global, Per Skill, and Free advancement slot modes
- Configurable Survivor XP settings
- Server-authoritative multiplayer progression and administration
- Full controller support for spending AP
- Split-screen compatible
- Optional Survivor Level inheritance after death
- Optional Player 1 Survivor XP percentage inside the digital watch

## Adding or removing SLA

SLA is designed to be safely added and removed from existing saves. Existing skills are preserved and historical progression is not converted into retroactive Survivor Levels.

Disabling SLA removes its interface while leaving skill levels already gained through AP in place. Re-enabling SLA restores its private state and reconciles supported skill progression that occurred while it was absent.

I always recommend backing up your save before making any modlist changes to an ongoing world regardless.

## Multiplayer administration

Authorized administrators can open "Admin Panel > Mini Scoreboard", right-click an online player, and choose "Survivor progression". Administrators can inspect progression, award positive Survivor XP or whole Survivor Levels, clear active Advancement Slots (without refunding AP or changing skill XP), and refresh the target state. An administrator can manage their own SLA progression from the "Admin" button in the Skills panel.

## Compatibility

**Incompatible:** [RPG Skills Systems B42 / RPGMenu](https://steamcommunity.com/sharedfiles/filedetails/?id=3666281346).

**Unsupported currently:** [Beyond Ten - Level 15 Skills](https://steamcommunity.com/sharedfiles/filedetails/?id=3765241705) and [Seesaw Game](https://steamcommunity.com/sharedfiles/filedetails/?id=3515515643) directly replace progression rules that SLA relies on.

**[Detailed Skill Tooltips](https://steamcommunity.com/sharedfiles/filedetails/?id=3572846242):** Load-order dependent. Load SLA after Detailed Skill Tooltips to append SLA's blue/red accounting text to DST's expanded skill tooltip. If SLA loads first, only SLA's blue/red accounting text is replaced, while Survivor Level progression and the + button tooltips remain functional.

Detailed Skill Tooltips, [Toughness Skill](https://steamcommunity.com/sharedfiles/filedetails/?id=3545533939), and [Show Skill XP Gain B42.20](https://steamcommunity.com/sharedfiles/filedetails/?id=3776490883) were tested together and worked without issue, but compatibility with every interface or custom-skill mod cannot be guaranteed.

## Current limits

- A skill at its effective maximum does not generate additional Survivor XP.
- Direct skill setters or third-party progression routes that emit no supported XP event do not generate Survivor XP.
- Only English text is currently included.

## Mod information

- Mod ID: `SurvivorLevelingAdvancement`
- Target: Project Zomboid Build 42.20 content track
- License: MIT
- [Source and issue tracker](https://github.com/Skeptic043/survivor-leveling-and-advancement)
