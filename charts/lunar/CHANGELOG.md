# Changelog

All notable changes to the `lunar` Helm chart are recorded here.

The format roughly follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
chart versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

History starts at 1.0.0 (the snippet→script rename and ghcr.io
switchover); earlier 0.x versions had no production users. For 0.x
history see `git log -- charts/lunar/`.

## [3.17.0] - 2026-08-25

### Added

- **`hub.migrateJobBackoffLimit`** (default `10`, up from a hardcoded `2`) — how
  many times the migrate Job may retry before the release fails.

  This is the retry for lock contention. Changing a foreign key takes
  `ACCESS EXCLUSIVE` on **both** tables involved, so against a database still
  serving traffic a migration can lose a lock race — a deadlock, or a
  `lock_timeout` now that the Hub bounds how long its migrator will wait. Both
  are transient, and the next attempt usually gets the lock.

  Two attempts was not a budget for something contention-driven. Kubernetes
  backs off exponentially between attempts (10s, doubling, capped at 6m), so a
  full ten fits inside the default `migrateJobActiveDeadlineSeconds` with room
  to spare. A migration that is genuinely broken rather than unlucky still fails
  on the first attempt and every one after, so this costs nothing in the case
  that matters.

- **`hub.retention`** — first-class values for Hub data retention, which
  previously had to be passed as raw `hub.extraEnv`.

  ```yaml
  hub:
    retention:
      enabled: false        # master switch for the run-history sweep
      window: 90d           # how far back a run stays visible
      configWindow: 90d     # how long superseded config generations are kept
      cascadeEnabled: false # also prune those generations, and the Git tables
      vacuumEnabled: false  # reclaim the freed disk with a nightly VACUUM FULL
  ```

  **Off by default.** An install that sets none of these keeps run history
  forever, exactly as before this block existed, so upgrading changes nothing on
  its own.

  **`window` sets `HUB_RETENTION_RUNS` and `HUB_RETENTION_DERIVED` to the same
  value from one key, deliberately.** The Hub does not merely default them
  equal — it refuses to boot when they differ, because two of the derived
  surfaces are rebuilt from the run tables and would silently truncate
  themselves back to the runs window within a day. Exposing two keys would be
  exposing a boot failure. A separate `derivedWindow` can be added later,
  without a breaking change, once divergence is supported.

  **Write windows in days.** The grammar is Go's durations extended with `d`
  (24h) and `w` (7d), so `m` is still Go's *minutes*: `12m` is a twelve-minute
  window that passes every validation and deletes essentially all run history on
  the first sweep. Twelve months is `365d`.

  Two of these delete more than run rows, which is why they are separate
  switches rather than folded into `enabled`. `cascadeEnabled` removes the
  *definitions* history points at, and is the only thing that deletes a
  component. `vacuumEnabled` runs `VACUUM FULL`, which takes ACCESS EXCLUSIVE on
  each table it rewrites — readers stall for the duration and then succeed — and
  needs free disk of roughly the surviving data size. It is threshold-gated, so
  it runs on schedule and should rarely act.

  Four further keys expose the pace rather than the policy.
  `interval` (`1h`), `batchSize` (`5000`) and `maxBatchesPerRun` (`100`) bound
  the sweep; `vacuumLockTimeout` (`5s`) bounds the compaction's wait for
  ACCESS EXCLUSIVE. These matter most on the **first** sweep: an install
  turning retention on has years of rows to remove, and `maxBatchesPerRun` is
  the rate limit on that backfill — a budget for the whole tick, shared across
  the six runs-tier tables rather than per-table, so `batchSize` ×
  `maxBatchesPerRun` is the rows-per-tick ceiling. Lower it if the first sweep
  hurts, but note that a tick spending its whole budget on the runs tier skips
  the config-generation prune and the Git tier. The three sweep keys are
  validated at boot even when `enabled` is false, and none may be zero.

  `vacuumEnabled` is **not** gated by `enabled`. The compaction pass has its own
  queue and its own flag and never consults the master switch, so
  `enabled: false` with `vacuumEnabled: true` still compacts nightly.

  Requires a Hub image with the retention workers; on older images the variables
  are simply unread.

### Upgrading

- **Drop any `HUB_RETENTION_*` entries from `hub.extraEnv` when you adopt
  `hub.retention`.** `extraEnv` renders after this block, so keeping both emits
  the same variable names twice in the Hub container. A plain `helm upgrade` is
  last-wins and survives it — your `extraEnv` value still takes effect, and the
  API server only warns `hides previous definition of "HUB_RETENTION_ENABLED",
  which may be dropped when using apply`. **Server-side apply rejects the object
  outright** (`duplicate entries for key [name="HUB_RETENTION_ENABLED"]`), so a
  GitOps install running `ServerSideApply=true` fails its next sync rather than
  degrading quietly. Installs that never set these through `extraEnv` are
  unaffected.

## [3.16.0] - 2026-08-24

### Changed

- **`hub.db.connectionOptions` is now a map** of Postgres connection
  parameters. Not every consumer separates options the same way, and the chart
  now renders the right syntax for each, so the separator is no longer yours to
  get right:

  ```yaml
  hub:
    db:
      # How Lunar reaches its own database.
      connectionOptions:
        sslmode: require
      # What the Hub hands to SQL API clients. Empty inherits the above.
      sqlapiConnectionOptions: {}
  ```

  Keys render in sorted order rather than the order written, so migrating an
  existing multi-option string may reorder it. Nothing reads connection options
  positionally, so this is cosmetic.

### Added

- **`hub.db.sqlapiConnectionOptions`** (optional) — the connection options the
  Hub hands to SQL API clients, surfaced by `lunar sql`. Empty, the default,
  inherits `hub.db.connectionOptions`, so nothing about an existing install
  changes.

  Set it when SQL API clients reach Postgres by a different route than the Hub
  does — through a connection pooler on a hostname of its own, say, which
  clients should verify:

  ```yaml
  hub:
    db:
      sqlapiConnectionOptions:
        sslmode: verify-full
        sslrootcert: system
  ```

  (`sslrootcert: system` needs libpq 16 or newer; older clients need an
  explicit CA path.) It moves `HUB_SQLAPI_CONNECTION_OPTIONS` and nothing else.

### Deprecated

- **A plain string is still accepted for either field** and reaches every
  consumer verbatim, so upgrading from 3.15.0 renders unchanged. Strings are
  removed in 4.0.0.

  While you pass one:

  - Helm logs `warning: cannot overwrite table with non table`. It is
    informational; your string is applied.
  - A string carrying more than one option is wrong for some consumers, since
    they do not share a separator. The install notes flag it. Switching that
    value to a map fixes it.


## [3.15.0] - 2026-08-24

### Added

- **`operator.scriptPodTopologySpreadConstraints`** — spread the script pods the
  operator creates at runtime across zones, nodes or subnets, instead of letting
  the scheduler pile them onto whichever node it likes best. Joins the existing
  `scriptPodNodeSelector`, `scriptPodTolerations`, `scriptPodPriorityClassName`,
  `scriptPodAnnotations` and `scriptPodSecurityContext`.

  Two conveniences worth knowing about:

  - `labelSelector` is optional. Kubernetes treats an omitted `labelSelector` as
    matching *no* pods, which makes the constraint a silent no-op, so the
    operator fills in its own script-pod selector
    (`app.kubernetes.io/managed-by: lunar-snippet-operator`) when one is not
    given. Set it explicitly only to narrow the spread — for example to a single
    script type via `lunar.earthly.dev/snippet-type`.
  - `maxSkew`, `topologyKey` and `whenUnsatisfiable` are validated when the
    operator starts, so a bad value fails the operator's boot with a clear
    message instead of having the API server reject every script pod it goes on
    to build.

  **Prefer `whenUnsatisfiable: ScheduleAnyway`.** Script pods are ephemeral,
  high-churn and single-shot: under `DoNotSchedule`, a cluster that cannot
  satisfy the constraint leaves them Pending until the operator's pending-pod
  timeout and script throughput silently drops.

  Note this is a *distribution* control, not a *supply* one — it helps when
  something like per-subnet IP pressure is lopsided, but it adds no capacity.

  Requires an operator image that reads
  `OPERATOR_SNIPPET_POD_TOPOLOGY_SPREAD_CONSTRAINTS` — pin `operator.image.tag`
  to a release that includes it. The empty default (`[]`) emits no env var, so
  an existing install's rendered operator Deployment is unchanged apart from the
  usual `helm.sh/chart` version label.

### Changed

- **`operator.topologySpreadConstraints`** — documented that it spreads the
  operator Deployment's own replicas only, and cross-referenced the new
  `scriptPodTopologySpreadConstraints` for script pods. Comment-only; no
  rendered output changes.

## [3.14.0] - 2026-08-19

### Added

- **`hub.github.apps[].privateKeyFile`** (optional) — the data key in
  `appsSecret` holding that entry's PEM. Defaults to
  `<lowercase-owner>.pem`, so existing values render byte-for-byte
  unchanged.

  It exists so one owner can carry more than one App. GitHub's REST rate
  limit applies per App *installation*, so installing a second App on a busy
  org gives the Hub a second, independent budget — but two `apps` entries
  with the same owner would otherwise derive the same PEM filename and share
  a key. Requires Lunar Hub 3.14.0 or newer, which pools an owner's Apps and
  spreads read traffic across them; commit statuses and PR comments stay on
  the owner's first entry, because GitHub only lets the App that created a
  check run or comment update it. The version requirement is repeated in
  `values.yaml` and the README, since those are what an operator configures
  from.

### Changed

- **`hub.github.apps` uniqueness is now `(host, owner, appId)`** instead of
  owner alone. This admits the same owner name on two hosts (a github.com
  `earthly` and a GHES `earthly`), which the Hub has always supported and
  the chart previously rejected.

  Paired with a new guard: two *different* Apps resolving to the same PEM
  file now fail template rendering. That covers the case the relaxation
  would otherwise have opened up — same owner on two hosts derives one
  default filename for two different Apps, which would have had the second
  signing its JWT with the first's key. One App installed across several
  orgs still shares a key, which is legitimate.

## [3.13.3] - 2026-08-19

### Added

- **`hub.migrateJobActiveDeadlineSeconds`** — how long the pre-install/pre-upgrade
  migrate Job may run before Kubernetes kills it. Previously hardcoded, with no
  way to change it short of forking the chart.

### Changed

- **The migrate Job's deadline is now `3600`, up from a hardcoded `600`.** The
  old value was sized as though it were a budget for how long migrations may
  take. It isn't: it's a backstop that reaps a wedged Job, needed because the
  migrator's advisory lock waits forever, so a pod blocked behind another
  session would otherwise never exit.

  Sized as a budget, it fired on migrations that were healthy, just slow. Builds
  using `CREATE INDEX CONCURRENTLY` scale with table size, and a 17 GB install
  upgrading 3.12.0 → 3.13.2 spent roughly eight minutes inside a single
  concurrent build on a 2.1M-row table — overrunning the ten minutes and failing
  the hook with `DeadlineExceeded`.

  Ten minutes was also the worst available number, for two reasons. It matched
  the usual Helm timeout exactly, so the Job was killed at the precise moment
  Helm stopped waiting — ruling out the recovery where the upgrade reports
  failure but the work finishes in the background and the retry is a clean
  no-op. And a concurrent build cut short leaves an **invalid** index behind,
  which the migration's `CREATE INDEX CONCURRENTLY IF NOT EXISTS` then *skips*
  on every later run, so the retry reports success while the index stays
  unusable until someone drops it by hand.

  **How long an upgrade waits is your Helm timeout, not this value.** Keep this
  comfortably above it.

## [3.9.1] - 2026-08-10

### Added

- **`grafana.anonymousViewer`** (default `false`) — serve the bundled Grafana
  with no login. Unauthenticated visitors get the `Viewer` role in the default
  org and land straight on the dashboards, which is what makes the kiosk
  sidecar useful without handing out the admin password. Renders
  `GF_AUTH_ANONYMOUS_ENABLED` plus `GF_AUTH_ANONYMOUS_ORG_ROLE=Viewer` on the
  Grafana Deployment; the role is fixed by the template rather than read from
  values, so it can't be widened to Editor/Admin by a typo, and the admin login
  form stays enabled for real Editor/Admin access.

  `chart` mode only: `[auth.anonymous]` is a Grafana server setting read at
  boot, so the chart can only apply it to the pod it owns. Setting it under
  `external` or `off` now fails the install instead of silently doing nothing.

  **Only enable this when Grafana is not reachable from the internet.** A
  Grafana `Viewer` can issue arbitrary queries against every provisioned
  datasource — restricting that is a Grafana Enterprise feature — so anonymous
  Viewer grants anyone who can reach the Service read access to the whole Lunar
  database through the read-only datasource.

## [3.9.0] - 2026-08-07

### Added

- **First-class GitLab authentication** (`hub.gitlab.*`, ENG-1409). One
  `hub.gitlab.tokens` entry per top-level group (`{group, host?, baseUrl?}`),
  with the group access tokens in a single operator-created Secret
  (`hub.gitlab.tokensSecret.secretName`, one `<lowercase-group>.token` key
  per entry) mounted at `/secrets/gitlab`. The chart renders
  `HUB_GITLAB_TOKENS` with each entry's `token_path` derived into that
  mount, mirroring the multi-App GitHub pattern. Replaces the documented
  `hub.extraEnv` + `hub.volumes` passthrough workaround.
- **`hub.gitlab.webhookSecret`** — the GitLab webhook signing secret,
  chart-generated as `<release>-gitlab-webhook` (lookup + `resource-policy:
  keep`) when `secretName` is empty, BYO otherwise; delivered as
  `HUB_GITLAB_WEBHOOK_SECRET` (requires a hub image with the operator-level
  fallback). Unlike GitHub there is no paste-back: the Hub registers project
  hooks itself and stamps the secret on them. Per-entry
  `tokens[].webhookSecret` remains as an advanced inline override.

### Changed

- **GitLab-only installs now render.** The GitHub-required guard became an
  at-least-one-forge guard: GitHub-only, GitLab-only, and mixed-forge values
  all template, while a partial config for either forge still fails with a
  specific message (missing/duplicate/non-top-level GitLab groups included).
  GitHub-only output is byte-for-byte unchanged. The chart-managed GitHub
  webhook secret and the NOTES entries for GitHub secrets now render only
  when GitHub is configured.
- **Hub, operator, script-init, script-sidecar, and dashboards images bumped to
  `3.9.0`**, tracking the `lunar-hub` 3.9.0 release. The chart moves in lockstep
  with the hub so an upgrade picks up the matching images without overriding
  tags by hand.

## [3.6.1] - 2026-08-03

### Added

- **`grafana.replicaCount`** — scale the bundled Grafana Deployment beyond a
  single replica. Requires `grafana.db.host` (below) once > 1 — the chart
  fails fast otherwise, since Grafana's default per-pod SQLite backend can't
  be shared across replicas.
- **`grafana.db`** — points Grafana's own backend store (sessions, orgs,
  annotations — distinct from the read-only dashboard datasource under
  `grafana.provisioning.dbPassword`) at Postgres instead of the default
  per-pod SQLite. Wires `GF_DATABASE_*` on the Grafana container.
- **`grafana.kiosk`** — settings for the kiosk sidecar (the nginx proxy that
  injects `?kiosk` into dashboard URLs): `image.repository`/`image.tag`
  (previously hardcoded to `nginx:1-alpine`, now defaulting to the tighter
  `nginx:1.31.3-alpine` so it doesn't drift per-node), `resources`, and
  `securityContext` — all separate from the `grafana.*` knobs above since
  it's a different container with a different footprint and uid.
- **`grafana.topologySpreadConstraints`** — spread Grafana replicas across
  nodes. Defaults to a soft node-spread (`ScheduleAnyway`, no-op at
  `replicaCount: 1`), matching the `hub` default; set explicitly to override.
- Liveness/readiness probes on all three containers in the Grafana pod
  (`grafana`, `kiosk`, `provision-reconverge`) — previously none, so a wedged
  container wasn't detected by Kubernetes.
- The Grafana provisioning Job now honors `grafana.annotations` and
  `grafana.podAnnotations`, matching the existing hub/operator pattern.

### Changed

- **`grafana.securityContext` no longer applies to the kiosk sidecar.** It now
  scopes to the Grafana server container only; the kiosk container reads the
  new `grafana.kiosk.securityContext` (default `{}`). **If you set
  `grafana.securityContext`, copy the block to `grafana.kiosk.securityContext`
  when upgrading** — otherwise the kiosk container loses those settings
  silently (or, under an enforced Pod Security Standards namespace, the pod
  can be rejected outright).

## [3.6.0] - 2026-07-30

### Changed

- **Hub, operator, script-init, script-sidecar, and dashboards images bumped to
  `3.6.0`**, tracking the `lunar-hub` 3.6.0 release. No template or values
  changes in this release — the chart moves in lockstep with the hub so an
  upgrade picks up the matching images without overriding tags by hand.

## [3.4.1] - 2026-07-20

### Added

- **`operator.scriptInitContainerSpec` and `operator.scriptSidecarContainerSpec`** —
  set the container spec for the init and sidecar containers the operator injects
  into each script pod (one of each, shared across all script types). Same overlay
  rules as the `operator.scriptContainerSpec*` settings: you set `resources`, env,
  and so on, while the operator overlays the image, env, and volume mounts. Set
  `resources` here so the init and sidecar containers satisfy a namespace
  `ResourceQuota` or `LimitRange` that requires requests. Empty (`{}`) uses the
  operator's built-in defaults.

## [3.2.1] - 2026-07-14

### Added

- **Operator pods can be spread with `operator.topologySpreadConstraints`.**
  Opt-in — set it to spread the operator across nodes or zones when running more
  than one replica. Empty by default (no constraints applied).
- **The Hub migration job now honors `hub.annotations` and `hub.podAnnotations`.**
  Applied to the pre-install/pre-upgrade migration Job and its pod, matching the
  annotation controls already available on the long-running components.

## [3.1.0] - 2026-07-13

### Added

- **`operator.scriptPodAnnotations` and `operator.scriptPodSecurityContext`** — set
  pod annotations and a pod-level `securityContext` (`fsGroup`, `runAsUser`,
  `seccompProfile`, …) on the script pods the operator spawns at runtime. The
  pod-level `securityContext` is commonly required to run under a "restricted" Pod
  Security Standards namespace. These join the existing `scriptPodNodeSelector`,
  `scriptPodTolerations`, and `scriptPodPriorityClassName`; container-level
  securityContext is set separately via `operator.scriptContainerSpec*`. Requires an
  operator image that reads `OPERATOR_SNIPPET_POD_ANNOTATIONS` /
  `OPERATOR_SNIPPET_POD_SECURITY_CONTEXT` — pin `operator.image.tag` to a release
  that includes it.

## [3.0.0] - 2026-07-11

### Breaking

- **`grafana.enabled` + `grafana.provisioning.enabled` are replaced by a single
  `grafana.mode`** — `chart` (bundled Grafana pod + dashboards; the default),
  `external` (dashboards provisioned into your own Grafana), or `off` (neither).
  The chart fails fast if either removed key is still set.
- **`grafana.externalURL` → `grafana.url`; `grafana.admin` → `grafana.auth`.**
  `auth` keeps `secretName` / `userKey` / `passwordKey` and adds an optional
  `tokenKey` for a service-account token (Grafana Cloud/Enterprise). `external`
  mode requires `url` + `auth.secretName`.
- **Coordinated upgrade with the Hub.** Grafana provisioning now requires a
  matching Hub — pin `hub.image.tag` to this release and upgrade them together.
- **Manifests with duplicate snippet names are now rejected.** If a manifest
  imports the same policy or collector more than once and they resolve to the
  same name, loading now fails — give each import a unique `name:`. Manifests
  that previously loaded this way must be updated.

### Changed

- **Grafana is now stock upstream `grafana/grafana` (default `13.1.0`), not a
  Lunar-built image.** Dashboards, datasources and plugins are installed over the
  Grafana API instead of baked into the image.
- **`block-release` checks are no longer shown on pull requests.** PR comments and
  commit statuses now show only the checks that gate the PR (`block-pr` and
  `block-pr-and-release`).

### Added

- **Provision dashboards into a bring-your-own Grafana (`grafana.mode: external`),
  or disable Grafana entirely (`off`).**

### Fixed

- **Closed and merged pull requests no longer appear as "Active"** in dashboards
  and the SQL API.

- **Check dashboards and the SQL API `checks` views now show one row per applying
  import** — results are no longer duplicated when the same policy applies through
  multiple imports. Update any custom queries that relied on the previous grain.

### Security

- **The snippet execution base image was updated** to clear known curl CVEs.


## [2.17.0] - 2026-07-09

### Changed

- **images**: default image tags (hub, operator, init, sidecar, grafana) bumped
  to `2.8.0` — the lunar-hub 2.8.0 release. Highlights: operator Manager leader
  election (active-active snippet execution with single-leader pod GC at
  `operator.replicaCount >= 2`, completing the RBAC/`replicaCount` support added
  in 2.16.0), pre-merge `lunar-config.yml` validation (`hub pull --dry-run` +
  JSON Schema), and `LUNAR_COMPONENT_META` surfacing catalog component metadata
  to collectors and policies. Image-tag bump only — no chart template changes.

### Security

- Patches `golang.org/x/net` and OpenSSL CVEs across all published images (hub,
  grafana, operator, init, sidecar): `yq` bumped to 4.53.3 and the Alpine base
  to 3.23.5. Upgrading the chart pulls the patched images.

## [2.16.0] - 2026-07-08

### Added

- `operator.replicaCount` (default `1`) — run the snippet operator at N≥2. Safe
  at N>1 on an operator image with Manager leader election (lunar ENG-1136):
  snippet execution stays active-active (River workers) while exactly one replica
  runs the pod-GC reconciler via a leader-election `Lease`. On a pre-LE image, N>1
  is still safe but runs N duplicate (idempotent) GC passes.
- Leader-election RBAC on the operator `Role`: `coordination.k8s.io/leases` (the
  `events` grant already existed). Required when `operator.replicaCount > 1` on
  the leader-elected image.

## [2.15.0] - 2026-07-08

### Changed

- **images**: default image tags (hub, operator, init, sidecar, grafana) bumped
  to `2.7.0` — the lunar-hub 2.7.0 release. This is the multi-replica HA hub:
  `replicaCount >= 2` support with a PodDisruptionBudget, cross-replica secret-cache
  and doneness-cache invalidation, advisory-lock dedup of PR comments and check-runs,
  readiness-gated S3 bundle backfill at boot, and reduced GitHub API pressure at
  `N >= 2`. Image-tag bump only — no chart template changes.

## [2.13.0] - 2026-07-03

### Changed

- **hub**: added a `preStop` hook (`hub.preStopSleepSeconds`, default 10s) that
  sleeps before SIGTERM, giving k8s time to deregister the pod from the Service
  so new requests stop arriving before the hub drains (graceful shutdown, Hub HA
  R4, ENG-1120). `terminationGracePeriodSeconds` (60) covers this plus the hub's
  shutdown budget (`HUB_SHUTDOWN_TIMEOUT`, 45s).
- **hub**: the readiness probe now targets `/ready` (was `/health`) with
  `failureThreshold: 1`, so the pod reports not-ready as soon as the hub begins
  graceful shutdown and k8s deregisters it. Liveness still targets `/health`
  (process-only, so a draining or DB-blipped pod is never restarted). Requires a
  hub image that serves `/ready` (lunar-hub with ENG-1120).
- **images**: default image tags (hub, operator, init, sidecar, grafana) bumped
  to `2.6.0` — the first hub release that serves `/ready` — in lockstep with the
  readiness-probe change above, so the chart default never points at an image
  that 404s the probe.

## [2.12.0] - 2026-07-02

### Changed

- **Hub `/var/lib/lunar` is now an ephemeral `emptyDir`, not a PVC.** The hub
  holds no durable state on disk — only re-extracted runtimes and a rebuildable
  snippet-code cache (code is served from S3) — so the RWO `hub-data`
  PersistentVolumeClaim is removed in favour of an `emptyDir` with a configurable
  `hub.stateDir.sizeLimit` (default `2Gi`). This removes the last per-instance
  source of truth on the hub filesystem, so the hub `RollingUpdate`s at
  `replicaCount > 1` with no shared-volume contention. Supersedes the 2.11.0
  render-time guard that forced persistence off for HA — there is no longer a
  persistence toggle to conflict, so both the guard and `Recreate` strategy are
  gone.

### Removed

- **`hub.persistence`** (`.enabled`/`.storageClass`/`.size`/`.accessModes`) and
  the `hub-data` PVC template — replaced by the ephemeral `emptyDir` above.
- **`hub.rootDir`** / the `HUB_ROOT_DIR` env var — dead/legacy; no such hub
  config field.

> **Upgrade note.** The existing `<release>-hub-data` PVC carried
> `helm.sh/resource-policy: keep`, so upgrading will not delete it — it's simply
> orphaned; remove it manually to reclaim storage. **Sequencing:** deploy the B1
> S3-serve stack and trigger one manifest re-pull (so the current manifest has S3
> `bundle_key`s) *before* moving replicas onto cold-disk `emptyDir` pods.
>
> Note: version sequences after 2.11.0 — reconcile if another chart PR lands a
> 2.12.0 first.

## [2.11.0] - 2026-07-02

### Added

- **Multi-replica baseline for the hub.** New `hub.replicaCount` (default `1`,
  unchanged behavior), `hub.terminationGracePeriodSeconds` (default `60`),
  `hub.topologySpreadConstraints` (default none), and an optional
  `hub.podDisruptionBudget` (default **off** — a PDB on a single replica can
  block voluntary node drains; enable for HA). These let the hub run at
  `replicaCount > 1` healthily (spread across nodes/zones, drain-safe). HA also
  requires `hub.persistence.enabled=false` (hub state lives in Postgres) — the
  chart now **fails fast at render time** on `replicaCount > 1` with persistence
  still enabled, instead of leaving replicas stuck contending for one RWO PVC.
  A **soft node-spread is applied by default** (maxSkew 1 across
  `kubernetes.io/hostname`, `ScheduleAnyway`) so multi-replica deploys survive a
  node loss without extra config; override via `hub.topologySpreadConstraints`.
  The chart also **fails fast if the PDB sets both `minAvailable` and
  `maxUnavailable`** (the API server rejects that).

> Note: version sequences after 2.10.0 — reconcile if another chart PR lands a
> 2.11.0 first. The emptyDir change (charts#68) supersedes the persistence
> fail-fast guard here.

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
