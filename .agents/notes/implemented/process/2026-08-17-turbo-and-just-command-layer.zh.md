# Agent Note: Turbo 与 just 命令层

Status: implemented

[English](2026-08-17-turbo-and-just-command-layer.md) | 中文

## Problem

仓库的每个任务都通过根目录 `package.json` 脚本运行。构建链脚本用 `&&` 拼接命令（`build` 运行 `build:lib && build:web`，`typecheck` 运行 `build:lib:host && typecheck:contracts-ready`，依此类推），因此排序存在于脚本内部的 shell 运算符中，而不是任务图中。贡献者得不到未变更工作的缓存、得不到按包的任务扇出，也没有 pnpm 脚本列表之外的简短命令名。根脚本编码了正确的顺序（Host lib 阶段先于 Client tsc，web 构建最后），因此任务运行器必须在不去重排或复制该逻辑的前提下增加价值。

## Decision

Turborepo（`turbo`，根 devDependency）与 `just`（一个 `justfile`）位于现有脚本之上。`pnpm run <script>` 仍是规范的仓库级命令；CI、门禁与 lefthook 钩子调用的命令保持不变。

- 构建链根脚本把它们的排序委托给 turbo 而非 shell `&&`：`"build": "turbo run build:lib:host build:lib:client build:web"`、`"build:lib": "turbo run build:lib:host build:lib:client"`，而 `typecheck`、`lint`、`lint:fix` 与 `doc-typecheck` 脚本运行 `turbo run build:lib:host <task>:contracts-ready`。叶子脚本（`build:lib:host`、`build:lib:client`、`build:web`、`*:contracts-ready`）保持不变，仍可被门禁运行器与 CI 直接调用。
- `turbo.json` 以 `//#` 前缀声明叶子根任务，并用 `dependsOn` 排序：`build:lib:client` 排在 `build:lib:host` 之后，`build:web` 排在 lib 阶段之后，每个 `*:contracts-ready` 任务排在 `build:lib:host` 之后。根任务自身不能调用 `turbo`——turbo 的 `recursive_turbo_invocations` 守卫会拒绝它——因此聚合脚本是对已声明叶子任务的普通调用，自身绝不成为被声明的任务。
- lib 阶段（`build:lib:host`、`build:lib:client`）与 `*:contracts-ready` 任务以 `cache: false` 运行。Host 与 Client 两个面写入同一个按包 `lib/` 目录，而 turbo 的输出所有权模型会在缓存未命中运行前删除任务声明的输出；缓存任一面都会抹掉另一面的输出。排序仍来自 `dependsOn`，`tsc -b` 通过 tsbuildinfo 保持自身的增量状态。
- 其余 turbo 任务覆盖按包任务图。`bundle` 与 `watch` 在定义了它们的包上扇出（按包的 tsdown 及其 watch 模式），其中 `bundle` 的输出排除 `lib/types`（由 tsc 所有、被 tsdown 消费）。`turbo run build` 通过 `dependsOn //#build:lib:client` 在 lib 阶段之后扇出到每个定义了 `build` 的包（`apps/web`、`website`、`native/landlock-run`）。三个有专属任务需求的包携带包级 `turbo.json` 文件（`extends: ["//"]`，按字段合并会保留根的 `dependsOn` 且只覆盖有差异的部分）：`apps/web/` 拥有 `dist/**` 构建输出与持久的 `dev`/`watch`，`website/` 拥有 `.dist/**` 输出与持久的 `dev`/`preview`，`native/landlock-run/` 拥有其构建输出与不缓存的 `release:*` 步骤；统一的 `bundle`/`watch` 配置保留在根目录。`test`、`test:coverage` 与 `test:snapshot` 以 `coverage/**` 输出缓存；`test:e2e` 因依赖实时 API key 而从不缓存；`clean`、`postinstall`、`prepack` 以及持久的 `dev`/`dev:web`/`watch` 任务从不缓存。
- 工作区依赖图在包之间存在真实环（经由 devDependencies），因此任何任务都不使用 `^` 前缀的拓扑依赖；排序按任务显式声明。
- `justfile` 将常用命令包装成简短配方（`just build`、`just test`、`just typecheck`、`just lint`、`just bundle`、`just watch`、`just docs-dev`、`just dev-web`、`just clean`），并提供参数透传配方（`just dsh web` 与 `just dsh --profile headless "task"` 依赖 `build`，以及 `just turbo run bundle`）。每个配方都委托给一次 pnpm 或 turbo 调用，因此配方不可能偏离规范脚本。

## Alternatives considered

**在 turbo 下为每个包提供构建脚本。** 给每个包自己的 `build`/`test` 脚本并让 turbo 排序图，会复制双面构建已经拥有的仓库级 `tsc -b` 聚合与 vitest 配置；排序风险（Host 先于 Client、生成的 Typert 契约先于 Client tsc）编码在根脚本中，无法按包复现。

**让根聚合本身成为 turbo 任务。** 声明一个脚本调用 `turbo` 的 `//#build` 会触发 turbo 的 `recursive_turbo_invocations` 守卫；声明为拼接的 `npm run` 链又会在其同样声明的 `dependsOn` 之外重复运行各阶段。因此聚合委托给已声明的叶子任务，后者是唯一允许存在的根任务。

**缓存 lib 阶段。** turbo 会在缓存未命中运行前删除任务的输出；Host 与 Client 两个面共享按包 `lib/` 输出目录，因此缓存任一面都会在链中抹掉另一面的输出。`cache: false` 让两个面始终保持运行且正确；`tsc -b` 的增量能力覆盖了缓存需求。

**`^` 拓扑依赖。** 工作区存在循环 devDependencies，turbo 的拓扑排序在环上失败；因此每个排序都显式声明。

**不引入任务运行器。** 这是现状，但 `&&` 链仍留在脚本内部，未变更的重建主导了本地迭代。

## Consequences

`pnpm run build`、`pnpm run typecheck`、`pnpm run lint` 与 `pnpm run doc-typecheck` 现在经由 turbo 执行：命令相同、顺序相同，带 turbo 的任务 UI 与按任务日志。lib 阶段不缓存（共享输出目录），因此构建仍会像之前一样完整重编译——而排序存在于 `turbo.json` 而非 shell 运算符中。`pnpm exec turbo run <task>` 与 `just <recipe>` 是新的入口；不用时零成本（turbo 是 devDependency，`just` 是本地二进制）。`turbo run build` 比 `pnpm run build` 运行得更多（website 与 native 包在 lib 阶段之后加入图），这一点已记录在文档中。本记录、`docs/development.md` 小节与 `justfile` 是这套工具仅有的新归属地；`AGENTS.md` 已达到其字数上限，不再增长。
