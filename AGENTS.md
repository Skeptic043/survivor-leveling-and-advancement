# Survivor Leveling & Advancement Agent Rules

Active project folder: `E:\Projects\PZ Mods\Survivor Leveling and Advancement`

## Scope

- Confine runtime and project modifications to this project folder unless explicitly authorized otherwise. Read-only access is permitted to installed Project Zomboid files; other sibling mod repositories remain off-limits. The workspace-level `AGENTS.md` governs shared-knowledge preflight and capture before this mod's rules apply.
- Do not modify or borrow from `Basekeeper (shelved)` or any other mod.
- Do not add runtime mod files until the user explicitly lifts the implementation pause.

## Orchestration

- The primary agent is the project orchestrator and owns `.project/`, architecture decisions, work-packet boundaries, integration, and user checkpoints.
- Any authorized research, debugging, implementation, or validation task that can change `Contents/**` or `tests/**` requires a bounded implementation executor. The primary orchestrator may inspect and review those paths but must not author their changes directly. Applying or staging an executor-returned diff is integration, not permission to revise it; conflicts or corrections in protected paths go back to an executor.
- A general session default that discourages delegation does not override this repository's explicit executor requirement. Before the first write to a protected path, the orchestrator must dispatch the bounded packet.
- Keep the repository-local protected-diff hook enabled. A primary-checkout commit that stages `Contents/**` or `tests/**` requires an exact receipt naming a distinct executor and reviewer for that staged diff; never bypass the hook with `--no-verify`.
- Implementation agents receive one bounded packet with named scope, permitted paths, prerequisites, validation commands, and a factual handoff contract.
- Implementation agents never read or edit `.project/`. They begin with their named `.agents/packets/<packet-id>.md` brief and follow only the reusable `.agents/contracts/` references named there.
- Implementation agents do not browse unrelated executor documents, broaden scope, inspect sibling mods, commit, push, publish, or begin a dependent packet unless their work order explicitly permits it.
- Use one branch and isolated worktree per implementation packet when Git state exists. Do not run overlapping writers against the same files.
- A packet worktree is temporary execution space, not an archive. After integration or explicit closure, verify recoverability, remove the clean worktree, and retire its local branch when safe. Preserve dirty or unresolved worktrees until deliberately reconciled.
- The orchestrator independently reviews every returned diff and evidence before integration. A worker report is not acceptance.

## Canonical documents — orchestrator only

- `.project/DESIGN.md` defines intended behavior.
- `.project/DECISIONS.md` records accepted decisions and superseded interpretations.
- `.project/RESEARCH.md` records verified game behavior, evidence, and technical risks.
- `.project/COMPATIBILITY.md` records version-pinned compatibility evidence and public support status.
- `.project/PLAN.md` defines implementation order and gates.
- `.project/STATE.md` records current project status.

Keep the opening current-phase section of `STATE.md` genuinely current and concise. Replace superseded status instead of stacking multiple competing "current" summaries; detailed completed evidence belongs in the appropriate validation/decision record and Git history.

When documents disagree, stop and reconcile them before implementation. Do not silently choose an interpretation.

Executor-facing information is indexed separately in `.agents/INDEX.md`. Treat it as routing for active packets and reusable contracts, not as required sequential reading or a second canonical history. Completed packet briefs remain historical unless a current packet explicitly references them. The orchestrator keeps active routing synchronized with material canonical decisions before dispatch.

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

- No commits or pushes in this mod repository, publication, Workshop actions, or releases without explicit user authorization.
- Before every Workshop update or version release, prepare a non-empty Steam change note and matching GitHub release notes. Keep the canonical history in `CHANGELOG.md` and the Steam-ready copy in `assets/workshop/STEAM_CHANGE_NOTES.md`.
- Record material design changes in `.project/DECISIONS.md` and update affected canonical documents together.
