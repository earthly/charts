# Changelog

All notable changes to the `lunar` Helm chart are recorded here.

The format roughly follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
chart versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

History starts at 1.0.0 (the snippet→script rename and ghcr.io
switchover); earlier 0.x versions had no production users. For 0.x
history see `git log -- charts/lunar/`.

## [2.2.0] - 2026-05-26

### Added

- Multi-App GitHub auth. New `hub.github.apps` list pairs each
  `{owner, appId, installId}` with a per-owner PEM in an
  operator-managed Secret referenced by `hub.github.appsSecret`.
  In multi-App mode the chart renders `HUB_GITHUB_APPS` JSON and
  mounts the Secret at `/secrets/github-apps`. The legacy
  `hub.github.app.*` single-App configuration is unchanged and
  remains supported; render-time validation enforces mutual
  exclusivity between the two modes.

## [2.1.0] - 2026-05-25

### Added

- `hub.secrets.<scope>.perKey` (default `false`) flips the script-secrets
  delivery shape for each scope from a single `HUB_<SCOPE>_SECRETS=KEY1:VAL1,...`
  env var (`secretKeyRef`) to a per-key `envFrom: secretRef + prefix:` mount,
  surfacing each data key as `HUB_<SCOPE>_SECRET_<KEY>=<value>`. Operators
  can now rotate or add a single key with `kubectl patch secret` without
  re-supplying all the others. Requires hub >= 2.2.0; the hub merges both
  shapes when both are configured (per-key wins on conflict) so callers
  can migrate one key at a time. See README "Script secrets (optional)"
  for the full migration walkthrough.

## [2.0.0] - 2026-05-20

### Breaking

- **Dual-ingress topology.** Webhooks can now be exposed on a separate
  ingress from the API. `hub.ingress` reshaped into `hub.ingress.api`
  and `hub.ingress.webhooks`. The previous single-host ingress
  configuration is no longer accepted.
- `publicBaseURL` removed in favor of the new ingress shape plus
  `hub.webhookURL` for BYO fallback. The chart computes per-component
  URLs from the right ingress.

### Changed

- `HUB_GRAFANA_URL_BASE` and Grafana's own `GF_SERVER_ROOT_URL` resolve
  from a trust-boundary-correct chain (api ingress → grafana ingress →
  explicit `hub.grafanaURLBase` → `hub.webhookURL` fallback), instead
  of always pointing at the public webhook ingress. Fixes OIDC
  redirect-URI breakage on split-host installs.

## [1.0.2] - 2026-05-18

### Added

- Worker concurrency values under `hub.maxWorkers.{collect,policy,cronCollect,cataloger}`
  surface the Hub's `HUB_MAX_WORKERS_*` env vars through the chart.
- Operator pool size and Hub operator-queue pool size are configurable;
  defaults are unlimited.

## [1.0.1] - 2026-05-17

### Fixed

- Image tag pin uses the release version `2.1.1` rather than the
  `v`-prefixed `v2.1.1`, which did not exist in the registry.

## [1.0.0] - 2026-05-17

### Breaking

- "Snippet" → "Script" rename throughout values and templates.
  `operator.snippet*` keys are gone; use the new `script*` equivalents.
- Default image pulls switched from Docker Hub (`earthly/lunar-*`) to
  GitHub Container Registry (`ghcr.io/earthly/lunar-*`). Set
  `image.registry` back to `docker.io` for tenants still pinning
  Docker-Hub-only dev-build SHAs.
- All images pinned to the release version `2.1.1` instead of floating
  `main`.

### Changed

- README rewritten: values reference, image rows, and inline mentions
  updated for the rename. "snippet" survives only in the image names
  themselves.
