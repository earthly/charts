{{/*
Expand the name of the chart.
*/}}
{{- define "lunar.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "lunar.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "lunar.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "lunar.labels" -}}
helm.sh/chart: {{ include "lunar.chart" . }}
{{ include "lunar.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "lunar.selectorLabels" -}}
app.kubernetes.io/name: {{ include "lunar.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "lunar.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "lunar.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Namespace where script pods run. Defaults to the release namespace.
*/}}
{{- define "lunar.scriptNamespace" -}}
{{- .Values.operator.scriptNamespace | default .Release.Namespace }}
{{- end }}

{{/*
Fail fast when GitHub App auth is misconfigured.
*/}}
{{- define "lunar.githubAuthCheck" -}}
{{- $hasApps := gt (len .Values.hub.github.apps) 0 -}}
{{- $hasLegacy := or (gt (int .Values.hub.github.app.id) 0) (gt (int .Values.hub.github.app.installId) 0) -}}
{{- if and $hasApps $hasLegacy -}}
{{- fail "hub.github.apps is mutually exclusive with hub.github.app.id / hub.github.app.installId. Use one mode or the other." -}}
{{- end -}}
{{- if $hasApps -}}
{{- include "lunar.githubAppsCheck" . -}}
{{- else -}}
{{- if not (gt (int .Values.hub.github.app.id) 0) -}}
{{- fail "hub.github.app.id is required (numeric, non-zero), or use hub.github.apps for multi-App routing. Run scripts/create-github-app.sh in the lunar repo to create one if you don't have it yet." -}}
{{- end -}}
{{- if not (gt (int .Values.hub.github.app.installId) 0) -}}
{{- fail "hub.github.app.installId is required (numeric, non-zero). It's the installation ID for the App on your org or repo." -}}
{{- end -}}
{{- if not .Values.hub.github.app.privateKey.secretName -}}
{{- fail "hub.github.app.privateKey.secretName is required. Create a Kubernetes secret holding the App's private-key PEM." -}}
{{- end -}}
{{- if not .Values.hub.github.app.owner -}}
{{- fail "hub.github.app.owner is required (chart >= 2.2.0). It's the GitHub org or user the App is installed on. Operators upgrading from chart < 2.2.0 must set this; the Hub now requires HUB_GITHUB_APP_OWNER to route webhooks." -}}
{{- end -}}
{{- end -}}
{{- end }}

{{/*
Validate the multi-App config (hub.github.apps + hub.github.appsSecret).
Called from lunar.githubAuthCheck when apps is non-empty.
*/}}
{{- define "lunar.githubAppsCheck" -}}
{{- if not .Values.hub.github.appsSecret.secretName -}}
{{- fail "hub.github.appsSecret.secretName is required when hub.github.apps is set. Create a Kubernetes secret with one PEM key per entry, named '<lowercase-owner>.pem'." -}}
{{- end -}}
{{- $seen := dict -}}
{{- range $i, $app := .Values.hub.github.apps -}}
{{- if not $app.owner -}}
{{- fail (printf "hub.github.apps[%d].owner is required" $i) -}}
{{- end -}}
{{- if not (gt (int $app.appId) 0) -}}
{{- fail (printf "hub.github.apps[%d] (%s): appId is required (numeric, non-zero)" $i $app.owner) -}}
{{- end -}}
{{- if not (gt (int $app.installId) 0) -}}
{{- fail (printf "hub.github.apps[%d] (%s): installId is required (numeric, non-zero)" $i $app.owner) -}}
{{- end -}}
{{- $key := lower $app.owner -}}
{{- if hasKey $seen $key -}}
{{- fail (printf "hub.github.apps: duplicate owner %q (case-insensitive)" $app.owner) -}}
{{- end -}}
{{- $_ := set $seen $key true -}}
{{- end -}}
{{- end }}

{{/*
Render the HUB_GITHUB_APPS JSON env value from hub.github.apps. Each
entry's private_key_path is derived from <lowercase-owner>.pem under
the Secret mountPath /secrets/github-apps. Used by hub-deployment.yaml.

host and base_url are emitted only when set on the entry, so existing
github.com / GHEC entries render byte-for-byte unchanged. Set both on a
GHES entry so the Hub keys its components by (host, owner, name) and
talks to that host's API endpoint.
*/}}
{{- define "lunar.githubAppsJSON" -}}
{{- $entries := list -}}
{{- range .Values.hub.github.apps -}}
{{- $entry := dict
    "owner" .owner
    "app_id" (.appId | int64)
    "private_key_path" (printf "/secrets/github-apps/%s.pem" (lower .owner))
    "install_id" (.installId | int64)
-}}
{{- if .host -}}{{- $_ := set $entry "host" .host -}}{{- end -}}
{{- if .baseUrl -}}{{- $_ := set $entry "base_url" .baseUrl -}}{{- end -}}
{{- $entries = append $entries $entry -}}
{{- end -}}
{{- $entries | toJson -}}
{{- end }}

{{/*
Fail fast when licence mount configuration is invalid.
*/}}
{{- define "lunar.hubLicenceCheck" -}}
{{- if not .Values.hub.licence.secretName -}}
{{- fail "hub.licence.secretName is required. Create a Kubernetes secret containing the signed hub licence JWT." -}}
{{- end -}}
{{- if not .Values.hub.licence.secretKey -}}
{{- fail "hub.licence.secretKey is required." -}}
{{- end -}}
{{- if not .Values.hub.licence.filePath -}}
{{- fail "hub.licence.filePath is required." -}}
{{- end -}}
{{- end }}

{{/*
Resolved name for the chart-managed Hub auth-token secret.
Honors hub.auth.secretName when set; otherwise derives from the release.
*/}}
{{- define "lunar.hubAuthSecretName" -}}
{{- .Values.hub.auth.secretName | default (printf "%s-auth-token" (include "lunar.fullname" .)) -}}
{{- end }}

{{/*
Resolved name for the chart-managed GitHub webhook secret.
*/}}
{{- define "lunar.hubWebhookSecretName" -}}
{{- .Values.hub.github.webhookSecret.secretName | default (printf "%s-github-webhook" (include "lunar.fullname" .)) -}}
{{- end }}

{{/*
Resolved name for the chart-managed Grafana admin secret.
*/}}
{{- define "lunar.grafanaAdminSecretName" -}}
{{- .Values.grafana.admin.secretName | default (printf "%s-grafana-admin" (include "lunar.fullname" .)) -}}
{{- end }}

{{/*
Resolved name for the chart-managed read-only Grafana DB-role (grafana_user)
password secret, used by the lunar-dashboards deploy tool's datasource.
*/}}
{{- define "lunar.grafanaDBSecretName" -}}
{{- .Values.grafana.dashboardsDeploy.dbPassword.secretName | default (printf "%s-grafana-db" (include "lunar.fullname" .)) -}}
{{- end }}

{{/*
LUNAR_HUB_* env for the lunar-dashboards deploy tool (the deploy hook Job and the
reconverge sidecar). deploy.sh uses it to resolve the Grafana endpoint + a
read-only DB connection from the Hub over gRPC. Only LUNAR_HUB_TOKEN is sensitive.
*/}}
{{- define "lunar.grafanaDeployHubEnv" -}}
- name: LUNAR_HUB_HOST
  value: {{ include "lunar.hubHost" . | quote }}
- name: LUNAR_HUB_GRPC_PORT
  value: {{ .Values.hub.service.ports.server | quote }}
- name: LUNAR_HUB_HTTP_PORT
  value: {{ .Values.hub.service.ports.http | quote }}
- name: LUNAR_HUB_INSECURE
  value: "true"
- name: LUNAR_HUB_TOKEN
  valueFrom:
    secretKeyRef:
      name: {{ include "lunar.hubAuthSecretName" . }}
      key: {{ .Values.hub.auth.secretKey }}
{{- end }}

{{/*
In-cluster DNS name for the Hub service, in `<svc>.<ns>.svc.<clusterDomain>`
form so it resolves from any namespace (the operator's scriptNamespace, in
particular). Callers that need to honor a per-component override should do
`default (include "lunar.hubHost" .) .Values.<component>.hubHost`.
*/}}
{{- define "lunar.hubHost" -}}
{{- printf "%s-hub.%s.svc.%s" (include "lunar.fullname" .) .Release.Namespace .Values.clusterDomain -}}
{{- end }}

{{/*
Reject chart 1.x ingress shape early with a migration message. Anyone
upgrading from 1.x with their old values intact would otherwise get a
cryptic render error or, worse, silently end up with no ingress at all.
*/}}
{{- define "lunar.rejectLegacyIngressShape" -}}
{{- $h := .Values.hub -}}
{{- if hasKey $h "publicBaseURL" -}}
{{- fail "hub.publicBaseURL was renamed to hub.webhookURL in chart 2.0.0 (and is now optional — defaults to https://<hub.ingress.webhooks.host>). See README \"Migrating from chart 1.x\"." -}}
{{- end -}}
{{- if hasKey $h "grafanaURLBase" -}}
{{- fail "hub.grafanaURLBase was renamed to grafana.externalURL in chart 2.0.0 (the value is a Grafana property; the hub consumes it, doesn't own it). See README \"Migrating from chart 1.x\"." -}}
{{- end -}}
{{- if or (hasKey $h.ingress "host") (hasKey $h.ingress "grpcAnnotations") (hasKey $h.ingress "httpAnnotations") -}}
{{- fail "hub.ingress shape changed in chart 2.0.0. Move 'host' under api.host AND webhooks.host. Move 'grpcAnnotations'/'httpAnnotations' under api.grpcAnnotations/api.httpAnnotations. See README \"Migrating from chart 1.x\"." -}}
{{- end -}}
{{- if hasKey $h.ingress.api "annotations" -}}
{{- fail "hub.ingress.api.annotations is not a chart value. Per-Ingress annotations go in hub.ingress.api.grpcAnnotations and hub.ingress.api.httpAnnotations (the chart collapsed the middle layer to keep the merge contract simple). Annotations shared with the webhooks Ingress go in hub.ingress.annotations." -}}
{{- end -}}
{{- end }}

{{/*
Effective external URL where GitHub posts webhooks. hub.webhookURL when
set; otherwise derived from hub.ingress.webhooks.host ONLY when chart-
managed ingress is enabled (the chart only derives a URL when it
actually routes traffic at that host). Empty otherwise — BYO-ingress
installs must set hub.webhookURL explicitly.

Consumed by hub-deployment.yaml as HUB_PUBLIC_BASE_URL.
*/}}
{{- define "lunar.webhookURL" -}}
{{- $hub := .Values.hub -}}
{{- if $hub.webhookURL -}}
{{- $hub.webhookURL -}}
{{- else if and $hub.ingress.enabled $hub.ingress.webhooks.host -}}
{{- printf "https://%s" $hub.ingress.webhooks.host -}}
{{- end -}}
{{- end }}

{{/*
Effective base URL for Grafana. Resolution chain (highest priority first):

  1. grafana.externalURL                      explicit override
  2. https://<grafana.ingress.hosts[0].host>  chart-managed Grafana ingress

Empty otherwise — the chart only derives a URL when it actually controls
the routing. Deliberately does NOT guess based on hub.ingress.api.host
(chart doesn't route Grafana traffic there) or hub.webhookURL (wrong
trust boundary). Installs that expose Grafana via external routing
MUST set grafana.externalURL explicitly, especially when Grafana fronts
OIDC (otherwise redirect_uri is wrong or empty).

Consumed by hub-deployment.yaml as HUB_GRAFANA_URL_BASE and by
grafana-deployment.yaml as GF_SERVER_ROOT_URL.
*/}}
{{- define "lunar.grafanaURL" -}}
{{- $grafana := .Values.grafana -}}
{{- $grafanaIng := $grafana.ingress -}}
{{- $grafanaHost := "" -}}
{{- if and $grafanaIng.enabled $grafanaIng.hosts -}}
{{- $grafanaHost = (index $grafanaIng.hosts 0).host -}}
{{- end -}}
{{- if $grafana.externalURL -}}{{ $grafana.externalURL }}
{{- else if $grafanaHost -}}{{ printf "https://%s" $grafanaHost }}
{{- end -}}
{{- end }}

{{/*
Fail fast when grafana.enabled is true but the chart can't determine a
Grafana URL. Specifically catches the 1.x "Caddy / content-routing"
upgrader: in 1.x, GF_SERVER_ROOT_URL and HUB_GRAFANA_URL_BASE both
defaulted to publicBaseURL. 2.0.0 deliberately drops that fallback —
guessing at a URL the chart doesn't route to is wrong. Without this
guard, upgraders silently end up with GF_SERVER_ROOT_URL unset →
Grafana defaults to http://localhost:3000/ → OIDC redirect_uri breaks.

Three escape hatches, depending on topology:
  - Set grafana.externalURL (BYO ingress / Caddy / external routing)
  - Enable grafana.ingress (chart-managed Grafana ingress)
  - Set grafana.enabled: false (skip Grafana entirely)
*/}}
{{- define "lunar.validateGrafana" -}}
{{- if .Values.grafana.enabled -}}
  {{- $url := include "lunar.grafanaURL" . -}}
  {{- if not $url -}}
    {{- fail "grafana.externalURL is required when grafana.enabled is true and the chart doesn't manage Grafana's ingress (chart 2.0.0 no longer derives Grafana URLs it doesn't route to — see README \"Migrating from chart 1.x\" for the Caddy / content-routing case). Pick one:\n  - grafana.externalURL = \"<your Grafana URL>\"  (BYO ingress / Caddy / external routing)\n  - grafana.ingress.enabled = true              (chart-managed Grafana ingress)\n  - grafana.enabled = false                     (skip Grafana entirely)" -}}
  {{- end -}}
{{- end -}}
{{- end }}

{{/*
Fail fast on ingress misconfiguration:
  - hub.webhookURL (whenever set) must be a full URL with scheme. This
    fires for BYO ingress too, where it matters most — a bare hostname
    in HUB_PUBLIC_BASE_URL silently breaks webhook registration.
  - When chart-managed ingress is enabled, api.host and webhooks.host
    are required.
  - When both webhookURL and webhooks.host are set, host portions must
    match — otherwise GitHub POSTs into the void.
*/}}
{{- define "lunar.validateIngress" -}}
{{- $hub := .Values.hub -}}
{{- if $hub.webhookURL -}}
  {{- $parsed := urlParse $hub.webhookURL -}}
  {{- if not $parsed.host -}}
    {{- fail (printf "hub.webhookURL %q must be a full URL including scheme (e.g. https://webhooks.example.com)." $hub.webhookURL) -}}
  {{- end -}}
  {{- if not (has $parsed.scheme (list "http" "https")) -}}
    {{- fail (printf "hub.webhookURL %q has unsupported scheme %q. GitHub webhook URLs must be http or https." $hub.webhookURL $parsed.scheme) -}}
  {{- end -}}
{{- end -}}
{{- if $hub.ingress.enabled -}}
  {{- if not $hub.ingress.api.host -}}
    {{- fail "hub.ingress.api.host is required when hub.ingress.enabled is true." -}}
  {{- end -}}
  {{- if not $hub.ingress.webhooks.host -}}
    {{- fail "hub.ingress.webhooks.host is required when hub.ingress.enabled is true." -}}
  {{- end -}}
  {{- if $hub.webhookURL -}}
    {{- $parsed := urlParse $hub.webhookURL -}}
    {{- $publicHost := lower (regexReplaceAll ":\\d+$" $parsed.host "") -}}
    {{- $webhookHost := lower $hub.ingress.webhooks.host -}}
    {{- if ne $publicHost $webhookHost -}}
      {{- fail (printf "hub.webhookURL host (%q) must equal hub.ingress.webhooks.host (%q). GitHub POSTs to webhookURL/webhooks/github and must reach the webhooks ingress." $publicHost $webhookHost) -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- end }}

{{/*
Resolve per-ingress annotations by merging the per-Ingress map on top
of the shared ingress.annotations default. Per-Ingress wins on key
collision.

Usage:
  {{ include "lunar.ingress.annotations" (dict "shared" .Values.hub.ingress.annotations "specific" .Values.hub.ingress.api.grpcAnnotations) }}
*/}}
{{- define "lunar.ingress.annotations" -}}
{{- $specific := default (dict) .specific -}}
{{- $shared := default (dict) .shared -}}
{{- $merged := merge (deepCopy $specific) $shared -}}
{{- if $merged -}}
{{- toYaml $merged -}}
{{- end -}}
{{- end }}
