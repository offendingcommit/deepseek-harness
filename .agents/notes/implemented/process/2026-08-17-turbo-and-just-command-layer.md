# Agent Note: Turbo and just command layer

Status: implemented

English | [中文](2026-08-17-turbo-and-just-command-layer.zh.md)

## Problem

Every repository task runs through the root `package.json` scripts. The build-chain scripts concatenate commands with `&&` (`build` runs `build:lib && build:web`, `typecheck` runs `build:lib:host && typecheck:contracts-ready`, and so on), so the ordering lives in shell operators inside scripts rather than in a task graph. Contributors get no caching for unchanged work, no per-package task fan-out, and no short command names beyond the pnpm script list. The root scripts encode the correct ordering (Host lib phase before Client tsc, web build last), so a task runner must add value without re-ordering or duplicating that logic.

## Decision

Turborepo (`turbo`, a root devDependency) and `just` (a `justfile`) sit on top of the existing scripts. `pnpm run <script>` remains the canonical full-repository command; the commands CI, gates, and lefthook hooks invoke are unchanged.

- The build-chain root scripts delegate their sequencing to turbo instead of shell `&&`: `"build": "turbo run build:lib:host build:lib:client build:web"`, `"build:lib": "turbo run build:lib:host build:lib:client"`, and the `typecheck`, `lint`, `lint:fix`, and `doc-typecheck` scripts run `turbo run build:lib:host <task>:contracts-ready`. The leaf scripts (`build:lib:host`, `build:lib:client`, `build:web`, `*:contracts-ready`) are unchanged and remain directly invocable by the gate runner and CI.
- `turbo.json` declares the leaf root tasks with the `//#` prefix and orders them with `dependsOn`: `build:lib:client` after `build:lib:host`, `build:web` after the lib phase, and each `*:contracts-ready` task after `build:lib:host`. A root task cannot itself call `turbo` — turbo's `recursive_turbo_invocations` guard rejects it — so the aggregate scripts are plain invocations of declared leaf tasks, never declared tasks themselves.
- The lib phases (`build:lib:host`, `build:lib:client`) and the `*:contracts-ready` tasks run with `cache: false`. The Host and Client faces write into the same per-package `lib/` directories, and turbo's output-ownership model deletes a task's declared outputs before a cache-miss run; caching either face would wipe the other face's output. Ordering still comes from `dependsOn`, and `tsc -b` keeps its own incremental state through tsbuildinfo.
- The remaining turbo tasks cover the per-package graph. `bundle` and `watch` fan out over the packages defining them (per-package tsdown and its watch mode), with `bundle` outputs excluding `lib/types` (tsc-owned, consumed by tsdown). `turbo run build` fans out to every package defining `build` (`apps/web`, `website`, `native/landlock-run`) after the lib phase via a `dependsOn` on `//#build:lib:client`. The three packages with bespoke task needs carry package-level `turbo.json` files (`extends: ["//"]`, per-field merge keeps the root's `dependsOn` and overrides only what differs): `apps/web/` owns `dist/**` build outputs and persistent `dev`/`watch`, `website/` owns `.dist/**` outputs and persistent `dev`/`preview`, and `native/landlock-run/` owns its build outputs and uncached `release:*` steps; the uniform `bundle`/`watch` config stays at the root. `test`, `test:coverage`, and `test:snapshot` cache with `coverage/**` outputs; `test:e2e` is never cached because it depends on a live API key; `clean`, `postinstall`, `prepack`, and the persistent `dev`/`dev:web`/`watch` tasks never cache.
- The workspace dependency graph has genuine cycles among packages (via devDependencies), so no task uses `^`-prefixed topological dependencies; ordering is explicit per task.
- The `justfile` wraps the common commands in short recipes (`just build`, `just test`, `just typecheck`, `just lint`, `just bundle`, `just watch`, `just docs-dev`, `just dev-web`, `just clean`) plus argument passthrough recipes (`just dsh web` and `just dsh --profile headless "task"`, which depend on `build`, and `just turbo run bundle`). Every recipe delegates to a pnpm or turbo invocation, so the recipes cannot drift from the canonical scripts.

## Alternatives considered

**Per-package build scripts under turbo.** Giving every package its own `build`/`test` script and letting turbo order the graph would duplicate the repo-wide `tsc -b` aggregates and vitest configuration the two-face build already owns; the ordering hazards (Host before Client, generated Typert contracts before Client tsc) are encoded in the root scripts, not reproducible per package.

**Making the root aggregate a turbo task.** Declaring `//#build` with a script that calls `turbo` fails turbo's `recursive_turbo_invocations` guard; declaring it with the concatenated `npm run` chain would double-run the phases it also declares as `dependsOn`. The aggregates therefore delegate to declared leaf tasks, which are the only root tasks that may exist.

**Caching the lib phases.** Turbo deletes a task's outputs before a cache-miss run; the Host and Client faces share the per-package `lib/` output directories, so caching either face would erase the other's output mid-chain. `cache: false` keeps the faces always-running and correct; `tsc -b` incrementality covers the caching need.

**`^`-topological dependencies.** The workspace has circular devDependencies, and turbo's topological sort fails on cycles; every ordering is declared explicitly instead.

**No task runner.** The status quo, but the `&&` chains stay inside scripts, and unchanged rebuilds dominate local iteration.

## Consequences

`pnpm run build`, `pnpm run typecheck`, `pnpm run lint`, and `pnpm run doc-typecheck` now execute through turbo: same commands, same order, with turbo's task UI and per-task logging. The lib phases are not cached (shared output directories), so a build still recompiles fully — as before — while ordering lives in `turbo.json` instead of shell operators. `pnpm exec turbo run <task>` and `just <recipe>` are new entry points; they cost nothing when unused (turbo is a devDependency, `just` a local binary). `turbo run build` runs more than `pnpm run build` (the website and native packages join the graph after the lib phase), which is documented. This record, the `docs/development.md` section, and the `justfile` are the only new homes for this tooling; `AGENTS.md` is at its word budget and does not grow.
