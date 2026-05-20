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
{{- if not (gt (int .Values.hub.github.app.id) 0) -}}
{{- fail "hub.github.app.id is required (numeric, non-zero). Run scripts/create-github-app.sh in the lunar repo to create one if you don't have it yet." -}}
{{- end -}}
{{- if not (gt (int .Values.hub.github.app.installId) 0) -}}
{{- fail "hub.github.app.installId is required (numeric, non-zero). It's the installation ID for the App on your org or repo." -}}
{{- end -}}
{{- if not .Values.hub.github.app.privateKey.secretName -}}
{{- fail "hub.github.app.privateKey.secretName is required. Create a Kubernetes secret holding the App's private-key PEM." -}}
{{- end -}}
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

  1. hub.grafanaURLBase                       explicit override
  2. https://<grafana.ingress.hosts[0].host>  chart-managed Grafana ingress

Empty otherwise — the chart only derives a URL when it actually controls
the routing. Deliberately does NOT guess based on hub.ingress.api.host
(chart doesn't route Grafana traffic there) or hub.webhookURL (wrong
trust boundary). Installs that expose Grafana via external routing
MUST set hub.grafanaURLBase explicitly, especially when Grafana fronts
OIDC (otherwise redirect_uri is wrong or empty).

Consumed by hub-deployment.yaml as HUB_GRAFANA_URL_BASE and by
grafana-deployment.yaml as GF_SERVER_ROOT_URL.
*/}}
{{- define "lunar.grafanaURL" -}}
{{- $hub := .Values.hub -}}
{{- $grafanaIng := .Values.grafana.ingress -}}
{{- $grafanaHost := "" -}}
{{- if and $grafanaIng.enabled $grafanaIng.hosts -}}
{{- $grafanaHost = (index $grafanaIng.hosts 0).host -}}
{{- end -}}
{{- if $hub.grafanaURLBase -}}{{ $hub.grafanaURLBase }}
{{- else if $grafanaHost -}}{{ printf "https://%s" $grafanaHost }}
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
