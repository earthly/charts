# Lunar Helm Charts

Helm charts for deploying [Earthly Lunar](https://earthly.dev/earthly-lunar) on Kubernetes.

## Prerequisites

- Kubernetes 1.29+
- Helm 3.x
- PostgreSQL 16+ (external — not included in the chart)
- S3-compatible object storage (two buckets: logs and resources)
- A GitHub App installed on your organization — the fastest path to create one is [our manifest script](https://github.com/earthly/lunar/blob/main/scripts/create-github-app.sh) (browser-based flow, prints the credentials you'll need below)

## Installing

```bash
helm repo add earthly https://earthly.github.io/charts
helm repo update

helm install lunar earthly/lunar \
  --namespace lunar --create-namespace \
  -f values.yaml
```

Before the command above will succeed, create the [required secrets](#required-secrets) and set the [required values](#required-values).

### Required secrets

The chart references Kubernetes secrets for sensitive values. Create them before installing, or provision them with an external secret manager (External Secrets Operator, Sealed Secrets, Vault, etc.). All secret names and keys are configurable in `values.yaml` — the names below are the defaults.

```bash
# Database credentials
kubectl -n lunar create secret generic lunar-db \
  --from-literal=username='<db-user>' \
  --from-literal=password='<db-password>'

# Hub auth token (used by CLI and CI agents to authenticate)
kubectl -n lunar create secret generic lunar-auth-token \
  --from-literal=token='<generate-a-random-string>'

# GitHub App private key (base64-encoded PEM)
kubectl -n lunar create secret generic lunar-github-app \
  --from-file=private-key=path/to/private-key.pem

# GitHub webhook secret
kubectl -n lunar create secret generic lunar-github-webhook \
  --from-literal=webhook-secret='<your-webhook-secret>'

# Snippet secrets (can be empty if not needed yet)
kubectl -n lunar create secret generic lunar-collector-secrets \
  --from-literal=secrets='{}'
kubectl -n lunar create secret generic lunar-cataloger-secrets \
  --from-literal=secrets='{}'
kubectl -n lunar create secret generic lunar-policy-secrets \
  --from-literal=secrets='{}'
```

### Required values

Minimum `values.yaml` that has to be provided — everything else has a sensible default.

```yaml
hub:
  publicBaseURL: "https://lunar.example.com"

  db:
    name: lunar
    host: your-db-host.example.com

  s3:
    logsBucket: your-lunar-logs-bucket
    resourcesBucket: your-lunar-resources-bucket

  github:
    app:
      id: 123456
      installId: 78901234
```

`hub.publicBaseURL` should resolve to the Hub from the public internet — it's used for automatic GitHub webhook registration (see [Webhooks](#webhooks) below).

## Optional secrets

Only create these if you need the features they enable.

```bash
# GitHub PAT (legacy; only when hub.github.token.secretName is set.
# Takes precedence over the GitHub App when present.)
kubectl -n lunar create secret generic lunar-github-token \
  --from-literal=token='<your-github-token>'

# Elastic API key (when hub.logging.elastic.url is set)
kubectl -n lunar create secret generic lunar-elastic-api-key \
  --from-literal=api-key='<your-elastic-api-key>'

# Grafana admin (when grafana.enabled is true)
kubectl -n lunar create secret generic lunar-grafana-admin \
  --from-literal=username='admin' \
  --from-literal=password='<your-grafana-password>'
```

## Ingress

```yaml
hub:
  ingress:
    enabled: true
    className: nginx
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt
      nginx.ingress.kubernetes.io/backend-protocol: "GRPC"
    hosts:
      - host: lunar.example.com
        paths:
          - path: /
            pathType: Prefix
    tls:
      - secretName: lunar-tls
        hosts:
          - lunar.example.com
```

## Post-install

### Load your configuration

Install and configure the [Lunar CLI](https://docs.lunar.build/install/cli) (needs `LUNAR_HUB_HOST` and `LUNAR_HUB_TOKEN` at minimum), then pull your primary configuration into the Hub:

```bash
lunar hub pull github://your-org/your-config-repo@main
```

### Webhooks

The Hub automatically registers per-repo GitHub webhooks at `<hub.publicBaseURL>/webhooks/github` when manifests are pulled. No manual webhook configuration is required as long as:

- `hub.publicBaseURL` is set and reachable from GitHub
- The GitHub App has the `repository_hooks: write` permission (the manifest script grants this by default)

## Upgrading

```bash
helm repo update

helm upgrade lunar earthly/lunar \
  --namespace lunar \
  -f values.yaml
```

## Uninstalling

```bash
helm uninstall lunar --namespace lunar
```

This removes all Kubernetes resources created by the chart. The PVC for hub state is **not** deleted automatically — remove it manually if you want to discard all data.

## Values reference

Run `helm show values earthly/lunar` for the full, authoritative list. Defaults below are grouped by component.

<details>
<summary><strong>Global</strong></summary>

| Key | Description | Default |
|-----|-------------|---------|
| `nameOverride` | Override the chart name | `""` |
| `fullnameOverride` | Override the full release name | `""` |
| `imagePullSecrets` | Image pull secrets for all pods | `[]` |
| `serviceAccount.create` | Create a service account | `true` |
| `serviceAccount.automount` | Automount the service account token | `true` |
| `serviceAccount.annotations` | Service account annotations (e.g. IAM role ARN) | `{}` |
| `serviceAccount.name` | Service account name (auto-generated if empty) | `""` |

</details>

<details>
<summary><strong>Hub</strong></summary>

The central gRPC/HTTP server. Stores metadata, evaluates policies, and serves the API.

**Image**

| Key | Description | Default |
|-----|-------------|---------|
| `hub.image.repository` | Hub container image | `earthly/lunar-hub` |
| `hub.image.tag` | Image tag | `main` |
| `hub.image.pullPolicy` | Pull policy | `IfNotPresent` |
| `hub.extraEnv` | Additional environment variables (`name`/`value` or `valueFrom` pairs) | `[]` |

**Public URL**

| Key | Description | Default |
|-----|-------------|---------|
| `hub.publicBaseURL` | Externally-reachable base URL for the Hub. Required for automatic GitHub webhook registration | `""` |

**Database**

| Key | Description | Default |
|-----|-------------|---------|
| `hub.db.host` | PostgreSQL host | `""` **(required)** |
| `hub.db.name` | Database name | `""` **(required)** |
| `hub.db.port` | PostgreSQL port | `5432` |
| `hub.db.waitSecs` | Seconds to wait for DB readiness on startup | `45` |
| `hub.db.user.secretName` | Secret containing the DB username | `lunar-db` |
| `hub.db.user.secretKey` | Key within the secret | `username` |
| `hub.db.pass.secretName` | Secret containing the DB password | `lunar-db` |
| `hub.db.pass.secretKey` | Key within the secret | `password` |

**GitHub**

| Key | Description | Default |
|-----|-------------|---------|
| `hub.github.app.id` | GitHub App ID | `0` **(required)** |
| `hub.github.app.installId` | GitHub App Installation ID | `0` **(required)** |
| `hub.github.app.privateKey.secretName` | Secret containing the App private key | `lunar-github-app` |
| `hub.github.app.privateKey.secretKey` | Key within the secret | `private-key` |
| `hub.github.webhookSecret.secretName` | Secret containing the webhook secret | `lunar-github-webhook` |
| `hub.github.webhookSecret.secretKey` | Key within the secret | `webhook-secret` |
| `hub.github.token.secretName` | Legacy PAT secret; empty disables PAT auth (App is used instead) | `""` |
| `hub.github.token.secretKey` | Key within the secret | `token` |
| `hub.github.baseUrl` | GitHub API base URL (for GitHub Enterprise Server) | `""` |
| `hub.github.syncWindow` | How far back to sync GitHub data on first pull | `2160h` (90 days) |

**S3 / Object Storage**

| Key | Description | Default |
|-----|-------------|---------|
| `hub.s3.logsBucket` | S3 bucket for log storage | `""` **(required)** |
| `hub.s3.resourcesBucket` | S3 bucket for snippet resources | `""` **(required)** |
| `hub.s3.logsUrlTtl` | Pre-signed URL TTL for snippet log uploads — Go [duration string](https://pkg.go.dev/time#ParseDuration) | `5m` |
| `hub.s3.resourcesUrlTtl` | Pre-signed URL TTL for snippet resource downloads (init-container fetch) | `1h` |

**Auth**

| Key | Description | Default |
|-----|-------------|---------|
| `hub.auth.secretName` | Secret containing the Hub auth token | `lunar-auth-token` |
| `hub.auth.secretKey` | Key within the secret | `token` |

**Snippet secrets**

Secrets passed through to collector, cataloger, and policy snippet execution as environment variables. Each references a Kubernetes secret containing a JSON-encoded `map[string]string`.

| Key | Description | Default |
|-----|-------------|---------|
| `hub.secrets.collector.secretName` | Collector secrets | `lunar-collector-secrets` |
| `hub.secrets.collector.secretKey` | Key within the secret | `secrets` |
| `hub.secrets.cataloger.secretName` | Cataloger secrets | `lunar-cataloger-secrets` |
| `hub.secrets.cataloger.secretKey` | Key within the secret | `secrets` |
| `hub.secrets.policy.secretName` | Policy secrets | `lunar-policy-secrets` |
| `hub.secrets.policy.secretKey` | Key within the secret | `secrets` |

**Logging**

| Key | Description | Default |
|-----|-------------|---------|
| `hub.logging.level` | Log level (`debug`, `info`, `warn`, `error`) | `info` |
| `hub.logging.format` | Log format (`json` or `text`) | `json` |
| `hub.logging.tenantId` | Tenant identifier for log correlation | `localdev` |
| `hub.logging.elastic.url` | Elasticsearch URL (enables log shipping when set) | `""` |
| `hub.logging.elastic.apiKeySecret.secretName` | Elastic API key secret | `lunar-elastic-api-key` |
| `hub.logging.elastic.apiKeySecret.secretKey` | Key within the secret | `api-key` |
| `hub.logging.elastic.bufferSize` | Log buffer size before flushing | `100` |
| `hub.logging.elastic.flushInterval` | How often to flush the log buffer | `5s` |

**Policy queue**

| Key | Description | Default |
|-----|-------------|---------|
| `hub.policyQueue.pollInterval` | How often the queue is polled | `1s` |
| `hub.policyQueue.numWorkers` | Number of concurrent policy evaluation workers | `5` |

**Persistence**

The Hub uses a PVC for state, cached repos, and snippet code.

| Key | Description | Default |
|-----|-------------|---------|
| `hub.persistence.enabled` | Create a PVC for hub state | `true` |
| `hub.persistence.storageClass` | StorageClass (empty = cluster default) | `""` |
| `hub.persistence.size` | Volume size | `10Gi` |
| `hub.persistence.accessModes` | PVC access modes | `[ReadWriteOnce]` |

**Networking**

| Key | Description | Default |
|-----|-------------|---------|
| `hub.service.type` | Service type | `ClusterIP` |
| `hub.service.ports.server` | gRPC port | `8000` |
| `hub.service.ports.http` | HTTP port | `8001` |
| `hub.ingress.enabled` | Enable ingress for the Hub | `false` |
| `hub.ingress.className` | Ingress class | `""` |
| `hub.ingress.annotations` | Ingress annotations | `{}` |
| `hub.ingress.hosts` | Ingress host rules | see `values.yaml` |
| `hub.ingress.tls` | Ingress TLS config | `[]` |

**Probes**

| Key | Description | Default |
|-----|-------------|---------|
| `hub.readinessProbe.enabled` | Enable readiness probe | `true` |
| `hub.readinessProbe.initialDelaySeconds` | Delay before first check | `0` |
| `hub.readinessProbe.periodSeconds` | Check interval | `5` |
| `hub.readinessProbe.failureThreshold` | Failures before unready | `3` |
| `hub.livenessProbe.enabled` | Enable liveness probe | `true` |
| `hub.livenessProbe.initialDelaySeconds` | Delay before first check | `0` |
| `hub.livenessProbe.periodSeconds` | Check interval | `5` |
| `hub.livenessProbe.failureThreshold` | Failures before restart | `3` |

**Scheduling & pod spec**

| Key | Description | Default |
|-----|-------------|---------|
| `hub.resources` | CPU/memory requests and limits | `{}` |
| `hub.nodeSelector` | Node selector | `{}` |
| `hub.tolerations` | Tolerations | `[]` |
| `hub.affinity` | Affinity rules | `{}` |
| `hub.labels` | Additional deployment labels | `{}` |
| `hub.annotations` | Additional deployment annotations | `{}` |
| `hub.podLabels` | Additional pod labels | `{}` |
| `hub.podAnnotations` | Additional pod annotations | `{}` |
| `hub.podSecurityContext` | Pod security context | `{}` |
| `hub.securityContext` | Container security context | `{}` |
| `hub.volumeMounts` | Additional volume mounts | `[]` |
| `hub.volumes` | Additional volumes | `[]` |

</details>

<details>
<summary><strong>Operator</strong></summary>

Watches for snippet execution jobs and creates Kubernetes pods to run them.

**Images**

| Key | Description | Default |
|-----|-------------|---------|
| `operator.image.repository` | Operator image | `earthly/lunar-snippet-operator` |
| `operator.image.tag` | Image tag | `main` |
| `operator.image.pullPolicy` | Pull policy | `IfNotPresent` |
| `operator.initImage.repository` | Init container image | `earthly/lunar-snippet-init` |
| `operator.initImage.tag` | Image tag | `main` |
| `operator.sidecarImage.repository` | Sidecar container image | `earthly/lunar-snippet-sidecar` |
| `operator.sidecarImage.tag` | Image tag | `main` |

**Behavior**

| Key | Description | Default |
|-----|-------------|---------|
| `operator.snippetNamespace` | Namespace for snippet pods (must exist if set) | `""` (release namespace) |
| `operator.maxConcurrent` | Max concurrent snippet pods | `10` |
| `operator.healthPort` | Operator health check port | `8081` |
| `operator.extraEnv` | Additional environment variables | `[]` |

**Snippet pod configuration**

| Key | Description | Default |
|-----|-------------|---------|
| `operator.snippetContainerSpecPolicy` | Base container spec for policy snippet pods (resources, securityContext, env, etc.) | `{}` |
| `operator.snippetContainerSpecCollector` | Base container spec for collector snippet pods | `{}` |
| `operator.snippetContainerSpecCataloger` | Base container spec for cataloger snippet pods | `{}` |
| `operator.batchMaxCountPolicy` | Max jobs per policy pod; `0` uses the operator default | `0` |
| `operator.batchMaxCountCollector` | Max jobs per collector pod; `0` uses the operator default | `0` |
| `operator.batchMaxCountCataloger` | Max jobs per cataloger pod; `0` uses the operator default | `0` |
| `operator.snippetPodNodeSelector` | Node selector for snippet pods | `{}` |
| `operator.snippetPodTolerations` | Tolerations for snippet pods | `[]` |

**Logging**

| Key | Description | Default |
|-----|-------------|---------|
| `operator.logging.level` | Log level | `info` |
| `operator.logging.format` | Log format | `json` |
| `operator.logging.tenantId` | Tenant identifier | `localdev` |
| `operator.logging.elastic.*` | Same structure as `hub.logging.elastic.*` | — |

**Scheduling & pod spec**

| Key | Description | Default |
|-----|-------------|---------|
| `operator.resources` | CPU/memory requests and limits | `{}` |
| `operator.nodeSelector` | Node selector | `{}` |
| `operator.tolerations` | Tolerations | `[]` |
| `operator.affinity` | Affinity rules | `{}` |
| `operator.podLabels` | Additional pod labels | `{}` |
| `operator.podAnnotations` | Additional pod annotations | `{}` |
| `operator.podSecurityContext` | Pod security context | `{}` |
| `operator.securityContext` | Container security context | `{}` |

</details>

<details>
<summary><strong>Badges</strong></summary>

Optional service that generates embeddable SVG status badges for components.

| Key | Description | Default |
|-----|-------------|---------|
| `badges.enabled` | Deploy the badge service | `false` |
| `badges.secure` | Hub connects to badges over HTTPS | `false` |
| `badges.image.repository` | Badges image | `earthly/badges` |
| `badges.image.tag` | Image tag | `main` |
| `badges.secret.name` | Secret containing the badges auth token | `""` |
| `badges.secret.key` | Key within the secret | `""` |
| `badges.service.type` | Service type | `ClusterIP` |
| `badges.service.port` | Service port | `80` |
| `badges.ingress.*` | Same structure as `hub.ingress.*` | disabled |
| `badges.extraEnv` | Additional environment variables | `[]` |
| `badges.resources` | CPU/memory requests and limits | `{}` |
| `badges.nodeSelector` | Node selector | `{}` |
| `badges.tolerations` | Tolerations | `[]` |
| `badges.affinity` | Affinity rules | `{}` |

</details>

<details>
<summary><strong>Grafana</strong></summary>

Optional pre-built Grafana instance with dashboards for policy results, component health, and collection activity.

| Key | Description | Default |
|-----|-------------|---------|
| `grafana.enabled` | Deploy the pre-built Grafana instance | `false` |
| `grafana.image.repository` | Grafana image | `earthly/lunar-grafana` |
| `grafana.image.tag` | Image tag | `main` |
| `grafana.admin.user.secretName` | Secret containing the admin username | `lunar-grafana-admin` |
| `grafana.admin.user.secretKey` | Key within the secret | `username` |
| `grafana.admin.password.secretName` | Secret containing the admin password | `lunar-grafana-admin` |
| `grafana.admin.password.secretKey` | Key within the secret | `password` |
| `grafana.service.type` | Service type | `ClusterIP` |
| `grafana.service.port` | Service port | `80` |
| `grafana.ingress.*` | Same structure as `hub.ingress.*` | disabled |
| `grafana.extraEnv` | Additional environment variables | `[]` |
| `grafana.resources` | CPU/memory requests and limits | `{}` |
| `grafana.nodeSelector` | Node selector | `{}` |
| `grafana.tolerations` | Tolerations | `[]` |
| `grafana.affinity` | Affinity rules | `{}` |

</details>
