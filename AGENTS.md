# Survivor Leveling & Advancement Agent Rules

Active project folder: `E:\Projects\PZ Mods\Survivor Leveling and Advancement`

## Scope

- Confine runtime and project modifications to this project folder unless explicitly authorized otherwise. Read-only access is permitted to installed Project Zomboid files and to `../pz-knowledge` for shared PZ research; other sibling mod repositories remain off-limits. During otherwise-authorized work in this repository, the project orchestrator has standing authorization to make narrowly scoped proposals to `pz-knowledge` without a separate permission prompt, but only on a dedicated branch and under that repository's own `AGENTS.md`, validation, risk, PR, review, and merge rules; this does not authorize pushes to or merges into `pz-knowledge/main`.
- Do not modify or borrow from `Basekeeper (shelved)` or any other mod.
- Do not add runtime mod files until the user explicitly lifts the implementation pause.

## Orchestration

- The primary agent is the project orchestrator and owns `.project/`, architecture decisions, work-packet boundaries, integration, and user checkpoints.
- Implementation agents receive one bounded packet with named scope, permitted paths, prerequisites, validation commands, and a factual handoff contract.
- Implementation agents never read or edit `.project/`. They begin with their named `.agents/packets/<packet-id>.md` brief and follow only the reusable `.agents/contracts/` references named there.
- Implementation agents do not browse unrelated executor documents, broaden scope, inspect sibling mods, commit, push, publish, or begin a dependent packet unless their work order explicitly permits it.
- Use one branch and isolated worktree per implementation packet when Git state exists. Do not run overlapping writers against the same files.
- The orchestrator independently reviews every returned diff and evidence before integration. A worker report is not acceptance.
- At the end of any substantial research, debugging, implementation, compatibility, or architecture task involving Project Zomboid behavior, the orchestrator explicitly asks: "Did this work establish, refine, dispute, supersede, or revalidate any generally reusable Project Zomboid knowledge that is not already adequately represented in `pz-knowledge`?" If no, do nothing and do not manufacture a contribution. If yes, inspect the existing shared knowledge first and propose only the reusable knowledge through its governed branch/PR workflow before treating the broader task as fully wrapped up.

## Canonical documents — orchestrator only

- `.project/DESIGN.md` defines intended behavior.
- `.project/DECISIONS.md` records accepted decisions and superseded interpretations.
- `.project/RESEARCH.md` records verified game behavior, evidence, and technical risks.
- `.project/COMPATIBILITY.md` records version-pinned compatibility evidence and public support status.
- `.project/PLAN.md` defines implementation order and gates.
- `.project/STATE.md` records current project status.

When documents disagree, stop and reconcile them before implementation. Do not silently choose an interpretation.

Executor-facing information is indexed separately in `.agents/INDEX.md`. The orchestrator keeps that layer synchronized with material canonical decisions before dispatch.

## Engineering rules

- Target the Build 42.20 content track without patch-version gates. Record the exact tested patch in compatibility evidence.
- Preserve vanilla skill behavior except where the design explicitly changes it.
- Treat multiplayer as a required acceptance target.
- Keep persisted data namespaced and schema-versioned.
- Server validates authoritative XP, AP spending, allotment limits, inheritance, and skill advancement.
- Discover eligible skills dynamically; do not hard-code the vanilla list.
- Ordinary Survivor credit comes from the authoritative accepted XP event with only the sandbox skill-XP multiplier removed. Do not invent missing event amounts, route flags, prior positions, or maximum-level success.
- Keep Project Zomboid API access behind narrow progression, XP-source, persistence, network, UI, and feedback adapters.
- Prefer capability checks over version-number branching. When a required seam is absent or changed, fail closed and report the unsupported capability.
- Chain patched vanilla methods through one owned hook boundary, preserve prior behavior, and make load/reload idempotent.
- Detect replacement of required owned hooks after installation. Disable the affected capability instead of silently producing incorrect state.
- Scope recursion and internal-mutation suppression to a transaction, player, and perk. Never use one process-wide suppression boolean.
- Keep core math and state transitions deterministic and testable without a running game where practical.
- Keep persisted state schema-versioned and adapter-identity/curve-aware with explicit forward migrations; never silently discard or rewrite unknown newer state.
- Keep comments sparse. Comment only non-obvious game API behavior, compatibility constraints, invariants, or intentional deviations that the code cannot express clearly.

## Change control

- No commits, pushes, publication, Workshop actions, or releases without explicit user authorization.
- Record material design changes in `.project/DECISIONS.md` and update affected canonical documents together.

## Shared Project Zomboid knowledge

Before researching Project Zomboid engine or API behavior, read `../pz-knowledge/AGENTS.md` and search the shared knowledge map from `../pz-knowledge/index.md`. Treat shared pages as navigation and synthesis, not primary evidence; inspect their cited sources when verification is required.

Keep this mod's feature, architecture, product, specification, constraint, tradeoff, and TODO decisions in this repository. Propose durable, generally reusable Project Zomboid discoveries to `pz-knowledge` through its branch, validation, risk, and review process.
