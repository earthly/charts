# Agent Instructions

Public Helm charts for [Earthly Lunar](https://earthly.dev/earthly-lunar). User-facing docs live in `README.md`; this file is for coding agents working on the repo itself.

## Layout

- `charts/<name>/` — each chart in its own directory (currently just `lunar`, designed to be multi-chart).
- `charts/<name>/CHANGELOG.md` — per-chart changelog, [Keep a Changelog](https://keepachangelog.com/) format.
- `charts/<name>/Chart.yaml`, `values.yaml`, `templates/`, `scripts/` — standard Helm chart layout.
- `README.md` — installation and operator-facing docs. Substantial (~37KB); keep in sync when changing chart behavior, values, or required secrets.
- `lunar.yml` — repo-level Lunar config.

## Workflow for chart changes

1. Edit `charts/<chart>/` templates / values / scripts.
2. Run `helm lint charts/<chart>` to sanity-check templates.
3. Update `charts/<chart>/CHANGELOG.md` under `## [Unreleased]` if user-visible behavior or values change.
4. Update the relevant section of `README.md` if you changed required secrets, required values, install steps, or any operator-facing surface.

Do NOT bump `Chart.yaml` `version` manually. Releases go through the `Bump Version` workflow (`.github/workflows/bump-and-release.yml`), which updates both `Chart.yaml` and the image tags in `values.yaml` atomically.

## Release

`chart-releaser` (`.github/workflows/release.yml`) runs on every push to `main` and publishes any chart whose `Chart.yaml` version is newer than the last released tag. Don't run it manually.

## Tests

There is no automated test suite — `helm lint` is the floor. For non-trivial template changes, render against representative `values.yaml` snippets locally with `helm template` and eyeball the output before opening a PR.
