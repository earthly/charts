# Changelog

This repository ships Helm charts for Earthly Lunar. Each chart maintains its
own changelog alongside the chart source:

- [`charts/lunar/CHANGELOG.md`](charts/lunar/CHANGELOG.md) — `lunar` chart releases

Chart versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
and per-chart entries roughly follow [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

The currently published chart version is recorded in each chart's `Chart.yaml`.
Release tags pushed by [`chart-releaser-action`](https://github.com/helm/chart-releaser-action)
in `.github/workflows/release.yml` track per-chart releases on the GitHub
Releases page.

## Repo-level changes

Notable changes to the repository itself (workflows, layout, tooling) that
aren't tied to a chart version land here.

### 2026-05-27

- Added repo-root `CHANGELOG.md` and `AGENTS.md` to satisfy Lunar `repo-hygiene` checks.
- Renamed the chart bump workflow from `bump-and-release.yml` to `bump-and-pr.yml`
  to reflect that it opens a PR rather than pushing a release directly.
