# Survivor Leveling & Advancement

A Project Zomboid Build 42 release candidate that turns ordinary skill activity into an independently paced Survivor Level and Advancement Point system. Advancement Points can immediately raise trainable skills while natural progression remains visible and meaningful.

## Status

The 1.0 release candidate is feature-complete. Core XP, Survivor Levels, Advancement Points, persistence, multiplayer authority, sandbox settings, Skills-screen integration, representative custom-skill compatibility, and representative Skills-tooltip compatibility are implemented and live-validated.

The current friends-only Workshop candidate passes clean-profile and Workshop-only loads, progression, AP spending, reload persistence, cross-version AP/XP retention, the complete deterministic gate, and the public-source gates. Before public release, it still needs the final different-owner dedicated-server session covering remote administration and restart persistence.

Development and current testing target Project Zomboid 42.20.4. The internal mod ID is `SurvivorLevelingAdvancement`. The mod does not enforce exact patch-version bounds, and compatibility will be claimed only for versions and integrations that have been tested.

## Installation

[Subscribe through the Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3792412209). The release candidate is currently friends-only while final multiplayer testing is completed. Steam Workshop is the supported installation route; remove duplicate manual copies from `Zomboid/mods` before testing or playing.

## Project links

- [Full feature and compatibility description](assets/workshop/WORKSHOP_DESCRIPTION.md)
- [Report a bug or issue](https://github.com/Skeptic043/survivor-leveling-and-advancement/issues/new/choose)
- [Changelog](CHANGELOG.md)

## Design goals

- Integrate with the vanilla Skills screen instead of duplicating it.
- Keep Survivor XP independent from each skill's sandbox XP multiplier.
- Support vanilla trainable skills and compatible modded skills through narrow adapters.
- Preserve multiplayer authority and character-bound progression.
- Keep update-sensitive Project Zomboid hooks isolated and replaceable.

## AI Use

AI was used to write all of the code in this project. The original concept, design direction, testing, debugging, and release decisions are my own. I spent many hours personally testing SLA and working through issues to make sure it behaves as intended. I'm grateful that AI tools helped me turn the idea into something I can share with the community. If you prefer not to use mods developed with AI assistance, I understand and respect that choice.

## License

[MIT](LICENSE)

## Support

If you enjoy the project, optional support is available through [Ko-fi](https://ko-fi.com/skeptic043). The mod and its features will not be gated behind donations.
