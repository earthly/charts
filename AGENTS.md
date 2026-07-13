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
  README.md           # values reference + install guide (publicly rendered)
  values.yaml         # default values for the chart
  templates/          # k8s manifest templates (hub, operator, grafana, etc.)
  scripts/            # helper scripts shipped with the chart (e.g. create-github-app.sh)
.github/workflows/    # chart publication, version bump, and Lunar completion callback
.github/CODEOWNERS    # @dchw owns everything by default
lunar.yml             # lunar-config: domain + codeowners + description
README.md             # repo-level README
```

## Release flow

1. A human release signer reviews an exact Lunar `main` SHA and dispatches
   Lunar's `release.yml` for `lunar-hub` with that reviewed SHA and `X.Y.Z`.
2. Lunar's workflow validates the authorization, runs its release gate, creates
   `lunar-hub-vX.Y.Z` on the signer's behalf, publishes the images, then triggers
   this repository's `bump-and-pr.yml` with `version=X.Y.Z`.
3. `bump-and-pr.yml` bumps `charts/lunar/Chart.yaml` `version` plus all the
   `*.image.tag` fields in `values.yaml`, pushes a `release/X.Y.Z` branch,
   opens a PR, and enables auto-merge (squash).
4. On merge to `main`, `release.yml` (the `Release Charts` workflow) runs
   `chart-releaser-action`, which packages the chart and publishes the Helm
   chart tag (`lunar-X.Y.Z`) + chart GitHub Release in this repository. The
   prefix is the chart name; it is unrelated to the CLI's `lunar-vX.Y.Z` tag
   and does not release the CLI. `bump-and-pr.yml` explicitly dispatches
   it after auto-merge because merges performed with `GITHUB_TOKEN` do not
   emit a downstream `push` workflow. A daily scheduled reconciliation is the
   fallback for a delayed merge or missed dispatch.
5. Still in the same `release.yml` job, the workflow verifies the public tag
   and `.tgz`, sends a metadata-only `lunar-chart-released` repository dispatch
   to `earthly/lunar`, and then replaces the chart GitHub Release body with a link
   to the canonical Self-hosted GitBook page. That link is the durable completion
   marker: push and scheduled reconciliation skip an already-marked release, while
   a manual workflow dispatch forces the callback for repair.
6. Lunar independently verifies the public release and chart package, resolves
   the packaged Lunar SHA and charts tag SHA, promotes eligible Self-hosted
   fragments from both repositories, and publishes the canonical notes.

## Release-note source flow

Structured fragments in `earthly/lunar/release-notes.d/` are the only canonical
source for future release-note prose. This repository has no maintained
changelog. Existing historical release bodies and Git history preserve the old
record.

- Lunar's weekday drafting workflow checks out Charts `main` and scans it with
  an independent `earthly/charts` watermark. Charts sends no per-merge source
  notification.
- Version-only/image-tag-only release PRs are expected to become `no-note`.
  User-visible values, templates, compatibility, installation, and upgrade
  changes can produce `source_repo: earthly/charts` Self-hosted fragments.
- `release.yml` sends chart metadata only after the chart is public: version/date,
  chart tag and SHA, release URL, package name, and packaged Lunar image version.
  It never sends release-note prose.
- Chart GitHub Release bodies point to
  <https://docs-lunar.earthly.dev/release-notes/self-hosted>. GitBook is the
  canonical release-note surface.

Only the completion callback requires the `LUNAR_REPO_DISPATCH_TOKEN` Actions
secret. A failed run before the completion marker is retried by reconciliation;
accepted callbacks are marked once, and explicit manual callbacks remain idempotent.

## Editing checklist

- **Bumping the chart**: don't edit `Chart.yaml` / `values.yaml` image tags by
  hand. Trigger the `bump-and-pr.yml` workflow via `workflow_dispatch`.
- **Changing template behavior**: update `charts/lunar/templates/*.yaml` and
  `values.yaml`. Bump the chart minor (`X.Y+1.0`) for additions, major
  (`X+1.0.0`) for breaking values-shape changes, patch for fixes. Do not write a
  separate changelog entry; Lunar drafts source-aware fragments after merge.
- **Editing the README**: keep the values table in sync with `values.yaml`.
  The README is the doc surface users see when they browse the chart.
- **Workflow / tooling changes**: anything under `.github/workflows/` or
  `scripts/` — these aren't chart-versioned; track them in git history.

## Conventions

- **Branch naming**: `release/X.Y.Z` for chart bumps (created by the bump
  workflow). Other branches: `<author>/<short-description>` is fine.
- **PR titles**: include the chart change in the title (e.g. `chart: 2.2.0 add
  multi-App GitHub auth`) so it's obvious from the release log.
- **CODEOWNERS**: `@dchw` is the default (`.github/CODEOWNERS`). Add additional
  owners per-path if a surface gets a dedicated owner.

## Pointers

- Canonical Self-hosted release notes: <https://docs-lunar.earthly.dev/release-notes/self-hosted>
- Public docs site: <https://docs-lunar.earthly.dev/>
- Lunar source: <https://github.com/earthly/lunar>
