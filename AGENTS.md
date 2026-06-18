# AI Agent Guide for `earthly/charts`

## What this repo is

Public Helm charts for [Earthly Lunar](https://docs-lunar.earthly.dev/). Only
one chart lives here today:

- [`charts/lunar`](charts/lunar) — Lunar Hub + Operator + Grafana

The chart is published to `https://earthly.github.io/charts` by
[`chart-releaser-action`](https://github.com/helm/chart-releaser-action) on
every push to `main`. Each push that changes `charts/lunar/Chart.yaml`'s
`version` field cuts a new release; pushes that don't touch the version are
no-ops on the release index.

This file is for coding agents (and humans) working on the repo itself.
User-facing install/values docs live in `README.md`.

## Layout

```text
charts/lunar/         # the lunar chart
  Chart.yaml          # chart metadata (name, version, kubeVersion)
  CHANGELOG.md        # per-chart release notes (canonical for chart history)
  README.md           # values reference + install guide (publicly rendered)
  values.yaml         # default values for the chart
  templates/          # k8s manifest templates (hub, operator, grafana, etc.)
  scripts/            # helper scripts shipped with the chart (e.g. create-github-app.sh)
scripts/              # repo tooling, NOT shipped with the chart
  sync-release-notes.sh  # mirror CHANGELOG.md sections into GitHub release notes
.github/workflows/    # CI: chart-releaser on main, bump-and-pr on dispatch
.github/CODEOWNERS    # @dchw owns everything by default
CHANGELOG.md          # repo-level index pointing at per-chart changelogs
lunar.yml             # lunar-config: domain + codeowners + description
README.md             # repo-level README
```

## Release flow

1. A new Lunar version (`lunar-hub-vX.Y.Z`) is released from `earthly/lunar`.
2. The `bump-and-pr.yml` workflow here is triggered (`workflow_dispatch`) with
   `version=X.Y.Z`.
3. `bump-and-pr.yml` bumps `charts/lunar/Chart.yaml` `version` plus all the
   `*.image.tag` fields in `values.yaml`, pushes a `release/X.Y.Z` branch,
   opens a PR, and enables auto-merge (squash).
4. On merge to `main`, `release.yml` (the `Release Charts` workflow) runs
   `chart-releaser-action`, which packages the chart and publishes the tag
   (`lunar-X.Y.Z`) + GitHub Release.
5. Still in the same `release.yml` job, `scripts/sync-release-notes.sh` runs
   and copies the matching `## [X.Y.Z]` section from
   `charts/lunar/CHANGELOG.md` into that release's notes (see below).

So: **the changelog entry IS the release notes.** Write the
`charts/lunar/CHANGELOG.md` section for the new version — usually as part of the
release PR or a follow-up on the same `release/X.Y.Z` branch before the bump PR
merges — and the release body is populated for you.

## Release notes are derived from the changelog

`chart-releaser` seeds every release body with the chart `description`, so
without help every release reads `A Helm chart for Earthly Lunar 🌙`.
`scripts/sync-release-notes.sh` fixes that: for each
`charts/<chart>/CHANGELOG.md`, it maps every `## [X.Y.Z]` section to the
`<chart>-X.Y.Z` release tag and sets the release body to that section.

- Runs automatically as the last step of `release.yml`. It's deliberately in
  the same job as `chart-releaser` rather than a separate `on: release`
  workflow, because releases created with `GITHUB_TOKEN` don't trigger
  downstream workflow runs.
- Idempotent and self-healing — it reconciles every run, so fixing a typo in a
  past changelog entry repairs that release's notes on the next release.
- Skips releases with no matching changelog section (e.g. pre-1.0 history the
  changelog intentionally omits).

Run it by hand against the live repo when needed:

```bash
scripts/sync-release-notes.sh --dry-run            # preview, no writes
scripts/sync-release-notes.sh                       # reconcile all releases
scripts/sync-release-notes.sh --version 2.4.0       # just one release
```

Needs an authenticated `gh` and `awk`. Defaults to `$GITHUB_REPOSITORY`
(falls back to `earthly/charts`).

## Editing checklist

- **Bumping the chart**: don't edit `Chart.yaml` / `values.yaml` image tags by
  hand. Trigger the `bump-and-pr.yml` workflow via `workflow_dispatch`.
- **Changing template behavior**: update `charts/lunar/templates/*.yaml` and
  `values.yaml`. Bump the chart minor (`X.Y+1.0`) for additions, major
  (`X+1.0.0`) for breaking values-shape changes, patch for fixes. Add a
  `charts/lunar/CHANGELOG.md` entry — it becomes the release notes.
- **Editing the README**: keep the values table in sync with `values.yaml`.
  The README is the doc surface users see when they browse the chart.
- **Workflow / tooling changes**: anything under `.github/workflows/` or
  `scripts/` — these aren't chart-versioned; track them in git history (the
  repo-level `CHANGELOG.md` is just an index, not a per-commit log).

## Conventions

- **Branch naming**: `release/X.Y.Z` for chart bumps (created by the bump
  workflow). Other branches: `<author>/<short-description>` is fine.
- **PR titles**: include the chart change in the title (e.g. `chart: 2.2.0 add
  multi-App GitHub auth`) so it's obvious from the release log.
- **CODEOWNERS**: `@dchw` is the default (`.github/CODEOWNERS`). Add additional
  owners per-path if a surface gets a dedicated owner.

## Pointers

- Per-chart release notes: [`charts/lunar/CHANGELOG.md`](charts/lunar/CHANGELOG.md)
- Repo-level changelog index: [`CHANGELOG.md`](CHANGELOG.md)
- Public docs site: <https://docs-lunar.earthly.dev/>
- Lunar source: <https://github.com/earthly/lunar>
