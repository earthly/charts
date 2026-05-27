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

## Layout

```text
charts/lunar/         # the lunar chart
  Chart.yaml          # chart metadata (name, version, kubeVersion)
  CHANGELOG.md        # per-chart release notes (canonical for chart history)
  README.md           # values reference + install guide (publicly rendered)
  values.yaml         # default values for the chart
  templates/          # k8s manifest templates (hub, operator, grafana, etc.)
  scripts/            # helper scripts shipped with the chart (e.g. app creation)
.github/workflows/    # CI: chart-releaser on main, bump-and-pr on dispatch
CHANGELOG.md          # repo-level notable changes (workflows, layout, tooling)
CODEOWNERS            # @dchw owns everything by default
lunar.yml             # lunar-config: domain + codeowners + description
README.md             # repo-level README
```

## Release flow

1. A new Lunar version (`lunar-hub-vX.Y.Z`) is released from `earthly/lunar`.
2. `earthly/lunar`'s `release.yml` dispatches the `bump-and-pr.yml` workflow
   here with `version=X.Y.Z`.
3. `bump-and-pr.yml` bumps `charts/lunar/Chart.yaml` `version` plus all the
   `*.image.tag` fields in `values.yaml`, pushes a `release/X.Y.Z` branch,
   opens a PR, and enables auto-merge (squash).
4. On merge to `main`, `release.yml` (the `Release Charts` workflow) runs
   `chart-releaser-action`, which packages the chart and publishes the tag
   + GitHub Release.
5. Update `charts/lunar/CHANGELOG.md` with the release notes — usually as
   part of the release PR or a follow-up PR on the same `release/X.Y.Z`
   branch before the bump PR merges.

## Editing checklist

- **Bumping the chart**: don't edit `Chart.yaml` / `values.yaml` image tags by
  hand. Trigger the `bump-and-pr.yml` workflow via `workflow_dispatch`.
- **Changing template behavior**: update `charts/lunar/templates/*.yaml` and
  `values.yaml`. Bump the chart minor (`X.Y+1.0`) for additions, major
  (`X+1.0.0`) for breaking values-shape changes, patch for fixes.
- **Editing the README**: keep the values table in sync with `values.yaml`.
  The README is the only doc surface users see on Artifact Hub.
- **Workflow changes**: anything under `.github/workflows/` — note the rename
  in repo-level `CHANGELOG.md` if it changes the public surface (file names,
  trigger names, dispatched-from contracts).

## Conventions

- **Branch naming**: `release/X.Y.Z` for chart bumps (created by the bump
  workflow). Other branches: `<author>/<short-description>` is fine.
- **PR titles**: include the chart change in the title (e.g. `chart: 2.2.0
  add multi-App GitHub auth`) so it's obvious from the release log.
- **CODEOWNERS**: @dchw is the default. Add additional owners per-path if a
  surface gets a dedicated owner.

## Pointers

- Per-chart release notes: [`charts/lunar/CHANGELOG.md`](charts/lunar/CHANGELOG.md)
- Repo-level changes: [`CHANGELOG.md`](CHANGELOG.md)
- Public docs site: <https://docs-lunar.earthly.dev/>
- Lunar source: <https://github.com/earthly/lunar>
