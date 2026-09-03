# Survivor Leveling & Advancement

Survivor Leveling & Advancement gives each character an independently paced Survivor Level alongside Project Zomboid's normal skills. Supported skill activity earns Survivor XP, and each Survivor Level grants an Advancement Point that can raise a selected skill. Natural progression remains important because AP advancement is tracked separately and must be caught up through play.

## How it works

SLA gives each character a Survivor Level separate from their normal skills. By default, XP earned in supported trainable skills also earns Survivor XP, with each Survivor Level granting one Advancement Point, or AP. AP can then be spent directly in the vanilla Skills panel to raise the level of a selected skill. Advancing a skill with AP occupies the required number of Advancement Slots, and naturally earning the XP that the AP bypassed returns those slots while still progressing the skill. The final advancement to a skill's effective maximum is treated as mastery, normally costs 2 AP, and clears that skill's active Advancement Slots.

## Advancement modes

- **Global:** Shares one configurable pool of Advancement Slots across every skill.
- **Per Skill:** Gives each skill its own configurable slot limit, including a default for compatible custom skills and optional vanilla-skill overrides.
- **Free:** Removes Advancement Slot limits and catch-up or recovery restrictions while retaining AP costs.

In Global and Per Skill modes, losing levels or XP in Fitness or Strength puts that skill into a recovery state that grants no Survivor XP until the lost progress is recovered. Changing modes does not reset tracked progress. Natural skill XP earned in Free mode still counts toward preserved catch-up or recovery if Global or Per Skill is selected again.

## Features and configuration

- Earn independent Survivor XP and Survivor Levels from supported trainable skill XP.
- Gain one AP per Survivor Level and spend AP directly from the vanilla Skills panel.
- Configure the Survivor XP multiplier and Fitness and Strength contribution.
- Let hosts enable or disable Survivor XP generation for individual vanilla skills and all compatible custom skills.
- Normalize progression curves automatically for compatible custom skills.
- Use server-authoritative multiplayer progression and online-player administration.
- Optionally inherit part of a dead character's Survivor Level.
- Use controller and split-screen support in the vanilla Skills panel.
- Optionally show Player 1 Survivor XP on the digital watch through Mod Options.

## Adding or removing SLA

SLA can be added to or removed from existing saves. Existing skills are preserved, and past progression does not grant retroactive Survivor Levels. Disabling SLA hides its interface but leaves AP-granted skill levels in place, while re-enabling it restores SLA state and reconciles supported progression earned while it was absent. As with any mod-list change, back up any ongoing world you care about before changing the mod list.

## Multiplayer administration and saving

Admins can inspect an online player's SLA progression, award positive Survivor XP or whole Survivor Levels, and clear active Advancement Slots without refunding AP or changing vanilla skill XP. Multiplayer progression is server-authoritative and stored with Project Zomboid's normal world data. Dedicated servers should set the native `SaveWorldEveryMinutes` option to a nonzero value because abruptly closing the server can lose progression written after the last successful save.

## Installation

[Subscribe through the Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3792412209) for the supported installation route. No external mod dependencies are required. Remove duplicate manual copies from `Zomboid/mods` before testing or playing.

## Compatibility and limits

- **Incompatible:** [RPG Skills Systems B42 / RPGMenu](https://steamcommunity.com/sharedfiles/filedetails/?id=3666281346)
- **Currently unsupported:** [Beyond Ten - Level 15 Skills](https://steamcommunity.com/sharedfiles/filedetails/?id=3765241705) and [Seesaw Game](https://steamcommunity.com/sharedfiles/filedetails/?id=3515515643)
- **Load-order dependent:** Load SLA after [Detailed Skill Tooltips](https://steamcommunity.com/sharedfiles/filedetails/?id=3572846242) to retain SLA accounting text in its expanded skill tooltip.
- **Tested together:** Detailed Skill Tooltips, [Toughness Skill](https://steamcommunity.com/sharedfiles/filedetails/?id=3545533939), and [Show Skill XP Gain B42.20](https://steamcommunity.com/sharedfiles/filedetails/?id=3776490883)
- Compatible custom skills need a usable XP curve and supported XP events.
- Skills at their effective maximum do not generate additional Survivor XP.
- Direct skill setters and unsupported progression routes do not generate Survivor XP.
- Only English text is currently included.

## Technical information

- Internal mod ID: `SurvivorLevelingAdvancement`
- Target version: Project Zomboid Build 42.20
- Developed and tested on: Project Zomboid 42.20.4
- License: MIT

## Project links

- [Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3792412209)
- [Full feature and compatibility description](assets/workshop/WORKSHOP_DESCRIPTION.md)
- [Report a bug or issue](https://github.com/Skeptic043/survivor-leveling-and-advancement/issues/new/choose)
- [Changelog](CHANGELOG.md)

## AI Use

AI was used to write all of the code in this project. The original concept, design direction, testing, debugging, and release decisions are my own. I spent many hours personally testing SLA and working through issues to make sure it behaves as intended. If you prefer not to use mods developed with AI assistance, I understand and respect that choice.

## License and support

Survivor Leveling & Advancement is released under the [MIT License](LICENSE). Optional support is available through [Ko-fi](https://ko-fi.com/skeptic043). Donations are optional, and no mod features are locked behind a paywall.
