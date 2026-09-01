# Survivor Leveling & Advancement [B42]

Level your skills through normal play while also progressing your Survivor Level and earning Advancement Points to boost selected skills while keeping natural progression important.

## Features

- Integrated directly into the vanilla skills panel
- A separately configurable Survivor XP multiplier that does not change skill XP
- Configurable Fitness and Strength contribution to Survivor XP
- Individually enable or disable Survivor XP generation for each vanilla skill, plus one universal toggle for compatible custom skills
- Automatic curve normalization for compatible custom skills
- Server-authoritative multiplayer progression
- Online-player administration for inspecting progression, awarding XP or levels, and clearing advancements
- Full controller support for spending AP
- Split-screen compatible
- Optional Survivor Level inheritance after death
- Optional Player 1 Survivor XP percentage inside the digital watch, enabled through Mod Options in the settings menu

## How it works

SLA gives each character a Survivor Level separate from their normal skills. By default, XP earned in supported trainable skills also earns Survivor XP, with each Survivor Level granting one Advancement Point, or AP. AP can then be spent directly in the vanilla skills panel to raise the level of a selected skill.

Advancing a skill with AP occupies the required number of Advancement Slots. To earn a slot back, you must naturally earn the XP that the AP allowed you to bypass. That XP still applies toward the skill's next level, allowing AP to boost your progress without replacing natural skill progression.

The final advancement to a skill's effective maximum, normally level 9 to level 10, is considered mastering the skill. Mastery costs 2 AP and requires 2 free Advancement Slots, then clears any active Advancement Slots on that skill. If the Global or Per Skill slot limit is set to 1, mastery only requires 1 free slot while retaining the 2 AP cost. Free mode requires no Advancement Slots while still retaining the 2 AP cost.

## Advancement modes

- **Global:** Shares one configurable pool of Advancement Slots across every skill, with a default limit of 3 active slots in total.
- **Per Skill:** Gives each skill its own configurable slot limit, using a default for compatible custom skills and optional overrides for vanilla skills.
- **Free:** Removes Advancement Slot limits and catch-up or recovery restrictions.

In Global and Per Skill modes, losing levels or XP (Fitness/Strength) puts that skill into a recovery state that grants no Survivor XP until the lost progress is recovered.

**Note:** Changing modes does not reset tracked progress. Natural skill XP earned while Free is selected still counts toward any preserved catch-up or recovery, and switching back to Global or Per Skill restores only what remains.

## Optional level inheritance

Survivor Level inheritance is configured through sandbox settings and allows the host to set a percentage of a deceased character's Survivor Level that passes to that player's next eligible survivor. This allows you to continue playing in a world you've invested significant progress in, while still retaining some of the downside of becoming Zomboid chow.

## Adding or removing SLA

SLA is designed to be safely added and removed from existing saves. Existing skills are preserved and historical progression is not converted into retroactive Survivor Levels.

Disabling SLA removes its interface while leaving skill levels already gained through AP in place. Re-enabling SLA restores its private state and reconciles supported skill progression that occurred while it was absent.

As with any mod-list change, I strongly recommend backing up any ongoing world you care about.

## Dedicated servers and hosting

Authorized administrators can open "Admin Panel > Mini Scoreboard" or "Admin Panel > Users List", right-click an online player, and choose "Survivor progression". Administrators can inspect progression, award positive Survivor XP or whole Survivor Levels, clear active Advancement Slots (without refunding AP or changing skill XP), and refresh the target state. An administrator can manage their own SLA progression from the "Admin" button in the Skills panel. Administration is limited to online players.

Dedicated servers should set the native `SaveWorldEveryMinutes` option to a nonzero value. Closing the server by any method other than the `quit` command can potentially lose SLA progression written after the last successful server save. A shorter save interval means less progression possibly lost in the event of a server failure.

## Compatibility

- **Incompatible: [RPG Skills Systems B42 / RPGMenu](https://steamcommunity.com/sharedfiles/filedetails/?id=3666281346)**

- **Currently unsupported: [Beyond Ten - Level 15 Skills](https://steamcommunity.com/sharedfiles/filedetails/?id=3765241705) and [Seesaw Game](https://steamcommunity.com/sharedfiles/filedetails/?id=3515515643)**. These mods directly replace progression rules that SLA relies on.

- **Load-order dependent: [Detailed Skill Tooltips](https://steamcommunity.com/sharedfiles/filedetails/?id=3572846242)**. Load SLA after Detailed Skill Tooltips to append SLA's blue/red accounting text to DST's expanded skill tooltip. If SLA loads first, only SLA's blue/red accounting text is replaced, while Survivor Level progression and the + button tooltips remain functional.

- **Tested together: [Detailed Skill Tooltips](https://steamcommunity.com/sharedfiles/filedetails/?id=3572846242), [Toughness Skill](https://steamcommunity.com/sharedfiles/filedetails/?id=3545533939), and [Show Skill XP Gain B42.20](https://steamcommunity.com/sharedfiles/filedetails/?id=3776490883)**. This combination worked without issue in testing, but compatibility with every interface or custom-skill mod cannot be guaranteed.

- **Potential hook conflicts:** Mods that replace the game's skill-XP award functions or `Events.AddXP` handling, vanilla Skills panel/progress-bar methods, online-player context menus, or digital-watch rendering may conflict with the corresponding SLA feature. SLA disables an affected capability when it detects that a required hook has been replaced rather than continuing with potentially incorrect behavior.

- **Custom progression boundary:** Compatible trainable skills that publish a usable XP curve and award XP through supported game events are expected to work. Mods that directly set skill XP or levels, replace skill caps or curves without compatible data, or otherwise bypass supported XP events may not grant Survivor XP or may be unsupported.

## Current limits

- A skill at its effective maximum does not generate additional Survivor XP.
- Direct skill setters or third-party progression routes that emit no supported XP event do not generate Survivor XP.
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
