# Survivor Leveling & Advancement

Survivor Leveling & Advancement gives each character an independently paced Survivor Level alongside Project Zomboid's normal skills. Skill activity earns Survivor XP, and each Survivor Level awards an Advancement Point that can raise a selected skill. Natural progression remains important because AP advancement is tracked separately and must be caught up through play.

## How it works

SLA gives each character a Survivor Level separate from their normal skills. By default, XP earned in supported trainable skills also earns Survivor XP, with each Survivor Level granting one Advancement Point, or AP. AP can then be spent directly in the vanilla skills panel to raise the level of a selected skill. Advancing a skill with AP occupies the required number of Advancement Slots. To earn a slot back, you must naturally earn the XP that the AP allowed you to bypass. That XP still applies toward the skill's next level, allowing AP to boost your progress without replacing natural skill progression. The final advancement to a skill's effective maximum, normally level 9 to level 10, is considered mastering the skill. Mastery costs 2 AP and requires 2 free Advancement Slots, then clears any active Advancement Slots on that skill. If the Global or Per Skill slot limit is set to 1, mastery only requires 1 free slot while retaining the 2 AP cost. Free mode requires no Advancement Slots while still retaining the 2 AP cost.

## Advancement modes

- **Global:** Shares one configurable pool of Advancement Slots across every skill, with a default limit of 3 active slots in total.
- **Per Skill:** Gives each skill its own configurable slot limit, using a default for compatible custom skills and optional overrides for vanilla skills.
- **Free:** Removes Advancement Slot limits and catch-up restrictions.

**Note:** Changing modes does not reset tracked progress. Natural skill XP earned while Free is selected still counts toward any preserved blue catch-up. Switching back to Global or Per Skill restores only what remains.

## Features and configuration

- Earn independent Survivor XP and Survivor Levels from supported trainable skill XP.
- Gain one AP per Survivor Level and spend AP to advance skills directly.
- Choose Global, Per Skill, or Free advancement modes.
- Keep AP advancement separate from natural progress through visible blue catch-up.
- Configure the Survivor XP multiplier, Fitness and Strength contribution, each vanilla skill toggle, and the compatible-custom-skill toggle.
- Normalize progression curves for compatible custom skills.
- Use server-authoritative multiplayer progression and administer existing online or offline profiles.
- Optionally inherit part of a dead character's Survivor Level.
- Use the vanilla Skills panel with controller and split-screen support.
- Optionally show Player 1 Survivor XP on the digital watch through Mod Options.
- Supports every standard language in Project Zomboid's language settings. All translations were done entirely by AI. If you notice incorrect or confusing text, please report it.

## Multiplayer administration and saving

Admins can manage existing online and offline SLA profiles. Positive Survivor XP and whole Survivor Levels apply immediately to offline profiles. Clear Advancements queues the action for offline profiles, remaining visible and cancellable, applying when that character reconnects. Clear Advancements does not refund AP or change vanilla skill XP. Changing a skill level through Player Stats automatically clears advancement accounting for that skill.

Single-player administration requires debug mode. Multiplayer administration uses the player's server-role permissions and validates changes on the server. Core Survivor progression, AP spending, advancement slots and optional inheritance are available in both modes.

**Player Stats XP limitation:** The 1.2.1 fix for skill XP grants with **Use multipliers** unchecked applies to single-player. In hosted and dedicated games, keep that checkbox checked when granting skill XP. If it is unchecked and the applicable sandbox XP multiplier is not 1x, SLA can award too much or too little Survivor XP. The skill XP itself and blue catch-up still use the actual skill award. This does not affect ordinary gameplay XP or the Survivor XP and Level buttons in SLA's own admin window.

SLA uses Project Zomboid's normal saves. For hosted and dedicated servers, set `SaveWorldEveryMinutes` above `0` to enable periodic world saves and shut down the server normally. A crash, forced shutdown, or power failure can lose SLA changes made since the last successful world save.

## Adding or removing SLA

SLA can be added to or removed from existing saves. Existing skills are preserved, and past progression does not grant retroactive Survivor Levels. Disabling SLA hides its interface but leaves AP-granted skill levels in place. Re-enabling it restores SLA state and reconciles supported progression earned while it was absent. As with any mod-list change, I strongly recommend backing up any ongoing world you care about.

## Optional level inheritance

Survivor Level inheritance is configured through sandbox settings. The host can set a percentage of a deceased character's Survivor Level to pass to that player's next eligible survivor. This lets a player retain some long-term progress while death still carries a cost.

## Installation

[Subscribe through the Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3792412209). Steam Workshop is the supported installation route, and no external mod dependencies are required. Remove duplicate manual copies from `Zomboid/mods` before testing or playing.

## Compatibility and limits

- **Incompatible:** [RPG Skills Systems B42 / RPGMenu](https://steamcommunity.com/sharedfiles/filedetails/?id=3666281346)
- **Currently unsupported:** [Beyond Ten - Level 15 Skills](https://steamcommunity.com/sharedfiles/filedetails/?id=3765241705) and [Seesaw Game](https://steamcommunity.com/sharedfiles/filedetails/?id=3515515643) directly replace progression rules that SLA relies on.
- **Load-order dependent:** Load SLA after [Detailed Skill Tooltips](https://steamcommunity.com/sharedfiles/filedetails/?id=3572846242) to append SLA accounting text to its expanded skill tooltip.
- **Tested together:** Detailed Skill Tooltips, [Toughness Skill](https://steamcommunity.com/sharedfiles/filedetails/?id=3545533939), and [Show Skill XP Gain B42.20](https://steamcommunity.com/sharedfiles/filedetails/?id=3776490883).
- Mods that replace skill-XP award functions, `Events.AddXP`, the vanilla Skills panel, online-player context menus, or digital-watch rendering may conflict with the related SLA feature.
- Compatible trainable custom skills need a usable XP curve and supported XP events.
- A skill at its effective maximum does not generate additional Survivor XP.
- Direct skill setters or unsupported progression routes do not generate Survivor XP.

## Technical context

- Internal mod ID: `SurvivorLevelingAdvancement`
- Target version: Project Zomboid Build 42.20
- Currently developed and tested on: Project Zomboid 42.20.4
- Server persistence: native world saves, with periodic saving controlled by `SaveWorldEveryMinutes`
- License: MIT

## Project links

- [Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3792412209)
- [Full Workshop description](assets/workshop/WORKSHOP_DESCRIPTION.md)
- [Report a bug or issue](https://github.com/Skeptic043/survivor-leveling-and-advancement/issues/new/choose)
- [Changelog](CHANGELOG.md)

## AI Use

AI was used to write all of the code in this project. The original concept, design direction, testing, debugging, and release decisions are my own. I spent many hours personally testing SLA and working through issues to make sure it behaves as intended. If you prefer not to use mods developed with AI assistance, I understand and respect that choice.

## License

- Survivor Leveling & Advancement is released under the [MIT License](LICENSE).

## Support

- [Ko-fi](https://ko-fi.com/skeptic043) donations are optional, and no mod features are locked behind a paywall.
