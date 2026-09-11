# Survivor Leveling & Advancement [B42]

Earn points by leveling your skills, then spend them on the skills you choose. SLA adds a Survivor Level and Advancement Points to the normal Skills panel while keeping natural skill progression in place. Want some of that progress to survive your next bad decision? Optional level inheritance lets your next character keep a percentage of your Survivor Level, with fresh points to spend.

Single-player, multiplayer, split-screen, and controller support. No required dependencies.

## How advancement works

XP earned in supported skills also builds your Survivor Level, with each Survivor Level giving you one Advancement Point, or AP. Spend AP using the **+** buttons beside your skills. By default, you can have three advancement slots occupied at once. Practicing an advanced skill frees its slots as you earn the XP you skipped, with that XP also counting toward your next skill level.

The final advancement to a skill's effective maximum, normally level 9 to level 10, is considered mastering the skill. Mastery costs 2 AP and requires 2 free Advancement Slots, then clears any active Advancement Slots on that skill. If the Global or Per Skill slot limit is set to 1, mastery only requires 1 free slot while retaining the 2 AP cost. Free mode requires no Advancement Slots while still retaining the 2 AP cost. A skill at its effective maximum does not generate additional Survivor XP.

## Keep some progress after death

Enable Survivor Level inheritance and choose how much carries over to your next character in the same world. For example, dying at Survivor Level 20 with inheritance set to 50% gives your next character Survivor Level 10 and 10 AP to spend. Your old skill levels are not copied, allowing you to choose where the inherited points go. Inheritance is optional and disabled by default.

## Settings

- **Global:** Shares one configurable pool of Advancement Slots across every skill, with a default limit of 3 active slots in total.
- **Per Skill:** Gives each skill its own configurable slot limit, using a default for compatible custom skills and optional overrides for vanilla skills.
- **Free:** Removes Advancement Slot limits and catch-up restrictions.
- Adjust Survivor XP speed without changing skill XP. Choose whether Fitness, Strength, individual vanilla skills, and compatible custom skills contribute.
- In Mod Options, enable higher-contrast advancement markers or Player 1 Survivor XP percentage on the digital watch.
- Supports every standard language in Project Zomboid's language settings. All translations were done entirely by AI. If you notice incorrect or confusing text, please report it.

**Note:** Changing modes does not reset tracked progress. Natural skill XP earned while Free is selected still counts toward any preserved blue catch-up. Switching back to Global or Per Skill restores only what remains.

## Adding or removing SLA

SLA can be added to or removed from existing saves. Existing skills are preserved, and past progression does not grant retroactive Survivor Levels. Disabling SLA hides its interface but leaves AP-granted skill levels in place. Re-enabling it restores SLA state and reconciles supported progression earned while it was absent. As with any mod-list change, I strongly recommend backing up any ongoing world you care about.

## Dedicated servers and hosting

Admins can grant Survivor XP or whole levels to existing online and offline profiles. Offline grants apply immediately. Clear Advancements frees slots without refunding AP or changing skill XP. For offline characters it stays pending and cancellable until they reconnect. Editing a skill level through Player Stats clears that skill's accounting.

SLA uses Project Zomboid's normal saves. On hosted and dedicated servers, enable SaveWorldEveryMinutes and shut down the server normally.

## Compatibility

- **Incompatible: [RPG Skills Systems B42 / RPGMenu](https://steamcommunity.com/sharedfiles/filedetails/?id=3666281346)**
- **Currently unsupported: [Beyond Ten - Level 15 Skills](https://steamcommunity.com/sharedfiles/filedetails/?id=3765241705) and [Seesaw Game](https://steamcommunity.com/sharedfiles/filedetails/?id=3515515643)**. These mods directly replace progression rules that SLA relies on.
- **Load-order dependent: [Detailed Skill Tooltips](https://steamcommunity.com/sharedfiles/filedetails/?id=3572846242)**. Load SLA after Detailed Skill Tooltips to append SLA's blue catch-up text to DST's expanded skill tooltip. If SLA loads first, only SLA's blue catch-up text is replaced, while Survivor Level progression and the + button tooltips remain functional.
- **Tested together: [Detailed Skill Tooltips](https://steamcommunity.com/sharedfiles/filedetails/?id=3572846242), [Toughness Skill](https://steamcommunity.com/sharedfiles/filedetails/?id=3545533939), and [Show Skill XP Gain B42.20](https://steamcommunity.com/sharedfiles/filedetails/?id=3776490883)**. This combination worked without issue in testing, but compatibility with every interface or custom-skill mod cannot be guaranteed.
- Mods that replace skill XP handling, caps or curves, the Skills panel, player menus or digital-watch display may conflict. SLA disables an affected integration if its required hooks are replaced. Compatible custom skills need a usable XP curve and supported XP events. Direct skill setters or progression routes without supported XP events do not generate Survivor XP.

## AI Use

AI was used to write all of the code in this project. The original concept, design direction, testing, debugging, and release decisions are my own. I spent many hours personally testing SLA and working through issues to make sure it behaves as intended. If you prefer not to use mods developed with AI assistance, I understand and respect that choice.

## Support

- [Ko-fi](https://ko-fi.com/skeptic043) donations are optional, and no mod features are locked behind a paywall.

## Mod information

- Developed/tested on version: 42.20.4
- Required dependencies: None
- License: MIT
- [Source and issue tracker](https://github.com/Skeptic043/survivor-leveling-and-advancement)
