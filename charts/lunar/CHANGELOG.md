# Changelog

All notable changes to the `lunar` Helm chart are recorded here.

The format roughly follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
chart versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

History starts at 1.0.0 (the snippet→script rename and ghcr.io
switchover); earlier 0.x versions had no production users. For 0.x
history see `git log -- charts/lunar/`.

## [2.10.0] - 2026-07-02

### Added

- **Deployment-level `annotations`.** New `hub.annotations`, `grafana.annotations`,
  and `operator.annotations` render onto each workload's Deployment `metadata`
  (distinct from the existing `podAnnotations`, which apply to the pod template).
  `hub.annotations` and `grafana.annotations` already existed as chart values but
  were never wired into a template; `operator.annotations` is new. Empty by
  default — no behavior change for existing installs.

## [2.9.0] - 2026-07-01

### Added

- **Configurable Postgres connection budget (R9).** New `hub.db.maxOpenConns`,
  `hub.db.maxPoolConns`, and `hub.db.operatorPoolSize` render to
  `HUB_DB_MAX_OPEN_CONNS` / `HUB_DB_MAX_POOL_CONNS` / `HUB_MAX_OPERATOR_POOL_SIZE`.
  Defaults are the hub's existing values (`40 / 40 / 5`), so a single-replica
  install is **unchanged** — no pool regression. The total Postgres connection
  count is `replicaCount × (maxOpenConns + maxPoolConns + operatorPoolSize)`, so
  **multi-replica deploys should lower `maxOpenConns`/`maxPoolConns`** to fit
  `max_connections` (keep `maxPoolConns` ≥ peak concurrent River workers — the
  sum of `hub.maxWorkers.*` — to avoid store-query serialization), and consider a
  connection pooler for larger N. See the HA operations runbook.

## [2.8.1] - 2026-07-01

### Docs

- Correct the `hub.grpc.maxConnectionAgeGrace` guidance. The prior note claimed
  grace must exceed a 600s idle-stream timeout so streams finish inside the
  window — but `PullManifest` (the one long server-stream) is kept open by a 30s
  heartbeat and can outlast any idle timeout, so 600s was never the bound. It's a
  non-issue in practice: `PullManifest` is only invoked by the one-shot `lunar`
  CLI on a freshly-dialed connection (age 0 → full runway), and the long-lived
  fetch client uses unary calls. Comment-only; no behavior change. (charts#69 nit)

> Note: patch on 2.8.0 — reconcile if another chart PR lands a 2.8.1 first.

## [2.8.0] - 2026-07-01

### Added

- **gRPC connection cycling for HA (R7).** New `hub.grpc.maxConnectionAge` and
  `hub.grpc.maxConnectionAgeGrace` (defaults `30m` / `10m`) render to
  `HUB_GRPC_MAX_CONNECTION_AGE` / `HUB_GRPC_MAX_CONNECTION_AGE_GRACE`. Bounding
  connection age makes long-lived HTTP/2 clients periodically reconnect, so they
  redistribute across hub replicas as the fleet scales and drop off a draining
  replica during a rollout instead of pinning to the one they first reached. The
  grace default (`10m`) exceeds the hub's 600s idle-stream timeout so a normal
  stream (e.g. `PullManifest`) completes inside the grace window rather than
  being cut. Requires a hub image with the knobs (earthly/lunar#1967); older
  images ignore the env vars. Set both to `0` to disable (single-instance).

> Note: additive; enabling by default is safe (clients transparently re-resolve
> on GOAWAY).

## [2.7.0] - 2026-07-01

### Fixed

- **Migrate Job no longer sets `serviceAccountName`.** As a pre-install hook the
  Job runs *before* the chart's ServiceAccount is created, so referencing it made
  the Job unschedulable on a **fresh** install (`serviceaccount "…" not found` →
  the Job burns `activeDeadlineSeconds` → `DeadlineExceeded` → `helm install`
  fails). The migrator makes no Kubernetes API calls (it only talks to Postgres),
  so it now uses the namespace `default` SA. Only affected first/greenfield
  installs — an upgrade already had the SA from the prior release. Image pulls are
  unaffected (`imagePullSecrets` is on the pod spec).

> Note: version sequences after 2.6.0 — reconcile if another chart PR lands a
> 2.7.0 first.

## [2.6.0] - 2026-07-01

### Fixed

- **Migrate Job now renders `hub.extraEnv`** (parity with the hub Deployment). The
  chart supplies SQL-API credentials only through `hub.extraEnv` (there is no
  dedicated `HUB_SQLAPI_*` value), and the 2.5.0 migrate Job omitted it — so on a
  **fresh** database the `01_sqlapi/user.sql` migration created the `sqlapi_user`
  role **without** a password, leaving the SQL API unable to authenticate. This
  only affected first/greenfield installs (an already-migrated DB doesn't re-run
  the migration), which is why it wasn't caught by an in-place upgrade. Any env you
  already set in `hub.extraEnv` for the hub (e.g. `HUB_SQLAPI_PASSWORD`) now also
  reaches the migrator.

> Note: version sequences after 2.5.0 — reconcile if another chart PR lands a 2.6.0
> first.

## [2.5.0] - 2026-06-26

### Changed

- **Migrations now run as a pre-rollout hook Job**, not at hub boot. A
  `hub-migrate` Job runs `/bin/lunar-hub-migrate` once per release via a Helm
  `pre-install`/`pre-upgrade` hook — before the hub Deployment is updated — so
  migrations complete and gate the rollout. The hub server asserts the schema
  is current at boot and refuses to start if it's behind, which also makes
  scaled-up/restarted pods safe (they don't run the Job). This replaces the
  per-pod init-container approach and is a prerequisite for running the hub as
  multiple replicas.
- Bump the hub, snippet operator/init/sidecar, and grafana image tags
  `2.4.1 → 2.5.0` so a default install of this chart pulls a hub image that
  ships `/bin/lunar-hub-migrate`. **Publish this chart version only once the
  2.5.0 images exist** (released from lunar).

### Requires

- A hub image that ships `/bin/lunar-hub-migrate`, **no longer migrates at
  boot**, and **asserts the schema at boot** (lunar ≥ the build that removes
  boot migration and adds the schema assertion). Older hub images are
  incompatible with this chart version (the migrate binary is absent, and a
  matching hub image won't self-migrate).

## [2.4.1] - 2026-06-24

### Changed

- Bump the hub, snippet operator/init/sidecar, grafana, and agent images
  to `2.4.1`. Highlights carried by the new images:
  - **Buildkite**: PR builds are scoped to the components actually
    changed, and webhook authentication is now durable via
    `HUB_BUILDKITE_WEBHOOK_TOKEN`.
  - **Operator**: runner-pod OOM kills are reported together with the
    snippet identity that triggered them, for faster diagnosis.
  - **Performance**: dashboard UI materialization is coalesced through a
    dirty table and refreshed more efficiently, cutting load and update
    lag on busy hubs.
  - **Security**: high-severity Go dependency updates
    (`golang.org/x/crypto`, `golang.org/x/net`, `golang.org/x/sys`,
    `jackc/pgx`).

## [2.4.0] - 2026-06-17

### Added

- `hub.github.apps[].host` and `hub.github.apps[].baseUrl` (both
  optional) let one multi-App Hub serve GitHub Enterprise Server orgs
  alongside github.com / GitHub Enterprise Cloud. When set, they render
  into the matching `HUB_GITHUB_APPS` entry as `host` / `base_url`, so
  the Hub keys that org's components by `(host, owner, name)` and calls
  its GHES API endpoint. Both default to github.com behaviour and are
  omitted from the rendered JSON when empty, so existing github.com-only
  multi-App configs render byte-for-byte unchanged. The Hub-side support
  shipped earlier in `earthly/lunar` (ENG-720); this exposes it through
  the chart (ENG-720 Phase 11).

## [2.3.1] - 2026-06-17

### Changed

- Grafana: moved the static, image-coupled `GF_*` settings out of the
  Grafana Deployment `env` and into the `lunar-grafana` image
  (`GF_INSTALL_PLUGINS`, `GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS`,
  `GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH`, `GF_USERS_ALLOW_SIGN_UP`,
  `GF_USERS_DEFAULT_THEME`, `GF_FEATURE_TOGGLES_ENABLE`). They now version
  with the image and no longer shadow it; override per-deployment via
  `grafana.extraEnv`. Requires a `lunar-grafana` image with these baked in
  (built from the matching `grafana/Earthfile`).

## [2.3.0] - 2026-06-05

### Added

- `operator.scriptPodPriorityClassName` (default `""`) sets the
  `priorityClassName` on every script pod the operator creates
  (earthly/lunar#1784), rendered as `OPERATOR_SNIPPET_POD_PRIORITY_CLASS_NAME`.
  Empty leaves the field unset, so pods take the cluster's default
  priority. The referenced PriorityClass must already exist in the
  cluster. Foundational for forcing snippets to be terminated before
  service pods in single-namespace setups, or prioritizing workloads
  in shared scratch namespaces.

## [2.2.1] - 2026-05-27

### Fixed

- Grafana: three bugs in the cronos Runs dashboard
  (earthly/lunar#1710). The `[collectors]`/`[policies]` links
  from the component dashboard now land on populated rows;
  policy script names in the Queued tab render as clickable
  links; the `Created` column displays relative time. Ships
  in `lunar-grafana:2.2.1`.

### Changed

- Hub: new partial B-tree index on `snippet_runs (started_at
  DESC) WHERE started_at IS NOT NULL` (earthly/lunar#1708)
  speeds up narrow-window Runs queries (~300× on a
  `started_at`-only filter, ~6.5× on a 1-day panel render).
  Applied by the hub's migration runner on startup; fresh
  environments build the index inline with a brief
  `ShareLock` on `snippet_runs`.

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
