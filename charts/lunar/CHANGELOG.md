# Changelog

All notable changes to the `lunar` Helm chart are recorded here.

The format roughly follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
chart versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Entries below 0.4.0 are abbreviated — see the git history for that range
(`git log -- charts/lunar/`).

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

## [0.8.2] - 2026-05-17

### Fixed

- `OPERATOR_HUB_HOST` (and `LUNAR_HUB_HOST` on Grafana) now defaults to
  the fully-qualified `<release>-hub.<ns>.svc.<clusterDomain>` so
  snippet pods deployed in a different namespace can reach Hub without
  workarounds in `operator.extraEnv`. Removes the `helm upgrade
  --reuse-values` failure caused by the duplicate-env strategic-merge
  conflict.

### Added

- `clusterDomain` value (default `cluster.local`) and a `lunar.hubHost`
  template helper, matching the Bitnami / kube-prometheus-stack pattern.
- `operator.hubHost` value for explicit cross-namespace overrides
  (ENG-704).

## [0.8.1] - 2026-05-15

### Added

- `HUB_GRAFANA_URL_BASE` now defaults from `hub.publicBaseURL`, so a
  single value drives both the chart-rendered ingress hostname and the
  Hub's notion of its own external base URL.

## [0.8.0] - 2026-05-14

### Breaking

- License-driven configuration replaces standalone tenant and
  telemetry values. `tenantId` is no longer a top-level value, and the
  `telemetry.elastic.*` env vars (`HUB_ELASTIC_URL`,
  `HUB_ELASTIC_API_KEY`, etc.) are no longer rendered into the Hub
  deployment — both are now sourced from the license JWT at runtime.

### Added

- `hub.licence.secretName`/`secretKey`/`filePath` value group mounts a
  license file into the Hub pod and exports `HUB_LICENCE_FILE`.
- `lunar.hubLicenceCheck` render-time helper replaces
  `lunar.tenantIdCheck`.

## [0.7.0] - 2026-05-11

### Changed

- **Grafana enabled by default.** The bundled Grafana instance
  (dashboards for policy results, component health, collection activity)
  ships out of the box. On upgrade, existing installs that do not pin
  `grafana.enabled: false` will get a Grafana Deployment, Service, and
  chart-managed admin Secret. The admin Secret has
  `helm.sh/resource-policy: keep` so credentials persist across
  upgrade/uninstall.

### Added

- TLS support for Hub and Operator connections to Postgres
  (`sslmode=require` etc., piped through `*.connectionOptions`).

## [0.6.1] - 2026-05-04

### Changed

- Chart-managed secret defaults renamed to drop the `-hub-` segment for
  consistency (e.g., `<release>-hub-auth` → `<release>-auth`).

## [0.6.0] - 2026-05-04

### Breaking

- Ingress block reshaped — per-component ingress is gone in favor of a
  unified `hub.ingress` shape. Re-render and reapply if you used the old
  layout.
- `tenantId` is now a required chart value.

### Added

- **Auto-generated secrets** for chart-managed values. The Hub auth
  token, GitHub webhook secret, and Grafana admin credentials no longer
  need pre-creation: leave the `secretName` empty and the chart
  generates a random value via `lookup` + `randAlphaNum`, persists it
  with `helm.sh/resource-policy: keep`, and re-reads it on every
  subsequent upgrade. User-managed secrets continue to work — set
  `secretName` and the chart skips auto-generation.
- GitOps note in the README covering ArgoCD/Flux (where `lookup`
  returns empty on client-side render).

## [0.5.3] - 2026-05-01

### Breaking

- Hub PAT auth path removed. Use GitHub App authentication. The
  `hub.github.token.secretName` value is ignored.

## [0.5.1] - 2026-04-30

### Removed

- Badges service. Deprecated for some time; final removal here.

### Fixed

- IAM example in chart docs dropped the unused `s3:DeleteObject`
  action.

## [0.5.0] - 2026-04-23

### Breaking

- `hub.s3.urlExpirationMinutes` removed. Replaced by separate TTLs that
  match distinct backend concerns:
  - `hub.s3.logsUrlTtl` (default `5m`) → PUT URLs for log uploads.
  - `hub.s3.resourcesUrlTtl` (default `1h`) → GET URLs for resource archives.

### Changed

- `hub.github.token.secretName` made optional. `HUB_GITHUB_TOKEN` is
  only injected when set, so GitHub App installs no longer need a
  placeholder PAT secret.
- README rewritten in Helm-idiomatic shape (Prerequisites, Installing
  with required secrets/values, Optional secrets, Ingress, Post-install
  with webhooks note, Upgrading, Uninstalling, collapsible per-component
  values reference). Links the GitHub App manifest script and the Lunar
  CLI env-var docs.
- `kubeVersion` declared as `>=1.29.0-0`.

## [0.4.12] - 2026-04-21

### Added

- Per-snippet-type container specs and batch sizes for the operator:
  `operator.snippetContainerSpec.{policy,collector,cataloger}` and
  matching `batchMaxCount` values. Unset values fall back to the
  operator's built-in service defaults — policies now get a lighter
  default container and a denser default batch for better binpacking.

### Removed

- Global `operator.snippetContainerSpec` and `operator.batchMaxCount`
  superseded by the per-type values above.

## [0.4.11] - 2026-04-10

### Fixed

- Grafana kiosk nginx redirect scheme and port.

## [0.4.10] - 2026-04-08

### Fixed

- Guard against kiosk-config volume name collisions between the kiosk
  sidecar and existing Grafana volume mounts.

### Added

- Nginx kiosk sidecar on the Grafana deployment for embedded
  dashboards.

## [0.4.9] - 2026-04-08

### Added

- `terminationGracePeriodSeconds` configurable on the Hub deployment so
  in-flight requests can drain before pod shutdown.

## [0.4.8] - 2026-04-04

### Fixed

- Grafana plugin allowlist updated to accept the unsigned
  `earthly-text-diff-panel` plugin.

## [0.4.7] - 2026-04-03

### Added

- `hub.publicBaseURL` value for the Hub's external URL (used in webhook
  callbacks, generated links, etc.).

## [0.4.6] - 2026-04-01

### Added

- `HUB_BADGES_SECURE` env var plumbed through the Hub deployment
  template.

### Fixed

- Hub persistence now behaves correctly across reinstalls (PVC retention
  + naming).

## [0.4.4] - 2026-03-31

### Added

- Logging configuration plumbed through to the operator deployment
  (matches Hub's logging shape).

## [0.4.3] - 2026-03-27

### Changed

- Operator hardcoded to talk to Hub with `insecure=true` over the
  in-cluster gRPC channel (snippet pods → Hub via operator).

## [0.4.2] - 2026-03-13

### Added

- `nodeSelector` and `tolerations` configurable on the workload
  deployments.

## [0.4.1] - 2026-03-12

### Added

- `operator.snippetContainerSpec` for overriding the operator's default
  snippet container spec.

## [0.4.0] - 2026-03-06

### Added

- `imagePullSecrets` support across chart-managed deployments.

## [0.3.0] - 2026-03-06

### Added

- Operator deployment and Kubernetes orchestration shipped as part of
  the chart (snippet pod lifecycle now managed by the operator).

## [0.2.0] - 2026-02-12

### Added

- Standard `app.kubernetes.io/component` labels on each deployment.

## [0.1.0] - 2026-02-09

Initial chart release.
