# Contributing

Thank you for helping improve Survivor Leveling & Advancement.

The project is still in pre-implementation preparation. Contribution guidance will expand once the first testable build exists.

## Expectations

- Keep changes focused and use a short-lived branch.
- Preserve vanilla behavior outside the mod's documented scope.
- Keep Project Zomboid-facing hooks narrow and compatibility-aware.
- Add deterministic checks for progression math, state, and migrations.
- Separate automated proof from live single-player or multiplayer validation.
- Do not commit generated packages, local saves, logs, credentials, machine paths, or private player data.
- Keep comments for non-obvious game behavior and invariants; prefer clear names and small functions elsewhere.

Bug fixes should identify the Project Zomboid build, mod version, single-player or server context, reproduction steps, and validation performed.
