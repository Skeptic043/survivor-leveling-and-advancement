# Survivor Leveling & Advancement

A Project Zomboid mod in active development that turns ordinary skill activity into an independently paced Survivor Level and Advancement Point system. Advancement Points can immediately raise trainable skills while natural progression remains visible and meaningful.

## Status

Release preparation. The core XP, Survivor Level, Advancement Point, persistence, multiplayer-authority, sandbox-settings, Skills-screen integration, representative custom-skill compatibility, and representative Skills-tooltip compatibility are implemented and live-validated. The staged Workshop source package passed a clean-profile load, progression, AP-spend, and reload smoke. The final different-owner dedicated-server session and a later unlisted Workshop-subscription smoke remain before the first public build.

Development and current testing target Project Zomboid 42.20.4. The internal mod ID is `SurvivorLevelingAdvancement`. The mod does not enforce exact patch-version bounds, and compatibility will be claimed only for versions and integrations that have been tested.

## Design goals

- Integrate with the vanilla Skills screen instead of duplicating it.
- Keep Survivor XP independent from each skill's sandbox XP multiplier.
- Support vanilla trainable skills and compatible modded skills through narrow adapters.
- Preserve multiplayer authority and character-bound progression.
- Keep update-sensitive Project Zomboid hooks isolated and replaceable.

## License

[MIT](LICENSE)

## Support

If you enjoy the project, optional support is available through [Ko-fi](https://ko-fi.com/skeptic043). The mod and its features will not be gated behind donations.
