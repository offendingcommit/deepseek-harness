# DeepSeek Harness monorepo command runner.
# Thin recipes over the canonical pnpm scripts and the cached turbo task graph;
# `pnpm run <script>` remains the source of truth. Install just with Homebrew.

default:
    @just --list

# Install workspace dependencies (pnpm workspaces)
install:
    pnpm install

# Full product build: host + client lib faces and the web app
build:
    pnpm run build

# Library layer only (pnpm run build:lib)
build-lib:
    pnpm run build:lib

# Bundle every package defining `bundle` in parallel (cached by turbo)
bundle:
    turbo run bundle

# Run all package watchers (persistent)
watch:
    turbo run watch

# Unit tests (vitest)
test:
    pnpm run test

# Unit tests under the CI coverage gate (pnpm run test:coverage)
test-coverage:
    pnpm run test:coverage

# Real-API tests, self-skip without DEEPSEEK_API_KEY (pnpm run test:e2e)
test-e2e:
    pnpm run test:e2e

# Keyless snapshot replay; pass a vitest -t filter: just test-snapshot 'name'
test-snapshot filter="":
    pnpm run test:snapshot {{ if filter != "" { "-t " + filter } else { "" } }}

# Typecheck the repository
typecheck:
    pnpm run typecheck

# Lint (oxlint)
lint:
    pnpm run lint

# Remove build outputs and safe residue
clean:
    pnpm run clean

# knip + publint + workspace constraints + NodeNext consumer check
hygiene:
    pnpm run hygiene

# All documentation gates
doc-sync:
    pnpm run doc-sync

# VitePress docs dev server (persistent)
docs-dev:
    pnpm run docs:dev

# Web GUI dev server (persistent)
dev-web:
    pnpm run dev:web

# Run the dsh CLI from source (builds first): just dsh web / just dsh --profile headless "task"
dsh args="": build
    pnpm dsh {{args}}

# Run a demo: just demo acp (defaults to cordis)
demo name="cordis":
    pnpm run demo:{{name}}

# Turbo passthrough: just turbo run bundle
turbo args="":
    pnpm exec turbo {{args}}
