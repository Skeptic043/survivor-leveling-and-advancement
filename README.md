# Survivor Leveling & Advancement

A planned Project Zomboid mod that turns ordinary skill activity into an independently paced Survivor Level and Advancement Point system. Advancement Points can immediately raise trainable skills while natural progression remains visible and meaningful.

## Status

Pre-implementation design and technical preparation. There is no installable release yet.

The initial target is Project Zomboid 42.20.3. The internal mod ID will be `SurvivorLevelingAdvancement`. Compatibility will be stated only for versions and integrations that have been tested.

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
