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
{{- fail "hub.publicBaseURL was renamed to hub.webhookURL in chart 2.0.0 (and now defaults to https://<hub.ingress.webhooks.host>). See README \"Migrating from chart 1.x\"." -}}
{{- end -}}
{{- if or (hasKey $h.ingress "host") (hasKey $h.ingress "grpcAnnotations") (hasKey $h.ingress "httpAnnotations") -}}
{{- fail "hub.ingress shape changed in chart 2.0.0. Move 'host' under api.host AND webhooks.host. Move 'grpcAnnotations'/'httpAnnotations' under api.grpcAnnotations/api.httpAnnotations. See README \"Migrating from chart 1.x\"." -}}
{{- end -}}
{{- end }}

{{/*
Effective external URL where GitHub posts webhooks. Falls back to
"https://<hub.ingress.webhooks.host>" when not explicitly set and the
chart's ingress is enabled. Empty when neither is configured — lunar
itself warns at boot in that case.

Consumed by hub-deployment.yaml as HUB_PUBLIC_BASE_URL (lunar env var
name preserved from chart 1.x).
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
Effective base URL for Grafana — used by hub to build [More Details]
links in PR comments. Resolution chain (highest priority first):

  1. hub.grafanaURLBase explicit override
  2. https://<grafana.ingress.hosts[0].host>  when chart manages Grafana's ingress
  3. https://<hub.ingress.api.host>           when chart manages Hub's ingress
  4. lunar.webhookURL                         BYO fallback

The api.host fallback (#3) is the correct trust boundary for human-facing
Grafana — same network as lunar CLI / CI agent traffic — even when no
path-routing is configured there. Customers in non-trivial topologies
should set grafanaURLBase explicitly.

Consumed by hub-deployment.yaml as HUB_GRAFANA_URL_BASE.
*/}}
{{- define "lunar.grafanaURL" -}}
{{- $hub := .Values.hub -}}
{{- $grafana := .Values.grafana -}}
{{- if $hub.grafanaURLBase -}}
{{- $hub.grafanaURLBase -}}
{{- else if and $grafana.ingress.enabled $grafana.ingress.hosts -}}
{{- $firstHost := (index $grafana.ingress.hosts 0).host -}}
{{- if $firstHost -}}
{{- printf "https://%s" $firstHost -}}
{{- else -}}
{{- include "lunar.webhookURL" . -}}
{{- end -}}
{{- else if and $hub.ingress.enabled $hub.ingress.api.host -}}
{{- printf "https://%s" $hub.ingress.api.host -}}
{{- else -}}
{{- include "lunar.webhookURL" . -}}
{{- end -}}
{{- end }}

{{/*
Fail fast on ingress misconfiguration: missing required hosts when
ingress is enabled, and (when the user explicitly overrides webhookURL)
a webhookURL host that doesn't match webhooks.host.
*/}}
{{- define "lunar.validateIngress" -}}
{{- $hub := .Values.hub -}}
{{- if $hub.ingress.enabled -}}
  {{- if not $hub.ingress.api.host -}}
    {{- fail "hub.ingress.api.host is required when hub.ingress.enabled is true." -}}
  {{- end -}}
  {{- if not $hub.ingress.webhooks.host -}}
    {{- fail "hub.ingress.webhooks.host is required when hub.ingress.enabled is true." -}}
  {{- end -}}
  {{- if $hub.webhookURL -}}
    {{- $parsed := urlParse $hub.webhookURL -}}
    {{- if not $parsed.host -}}
      {{- fail (printf "hub.webhookURL %q must be a full URL including scheme (e.g. https://webhooks.example.com)." $hub.webhookURL) -}}
    {{- end -}}
    {{- $publicHost := lower (regexReplaceAll ":\\d+$" $parsed.host "") -}}
    {{- $webhookHost := lower $hub.ingress.webhooks.host -}}
    {{- if ne $publicHost $webhookHost -}}
      {{- fail (printf "hub.webhookURL host (%q) must equal hub.ingress.webhooks.host (%q). GitHub POSTs to webhookURL/webhooks/github and must reach the webhooks ingress." $publicHost $webhookHost) -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- end }}

{{/*
Resolve per-ingress className. Block-level value wins; falls back to
the shared ingress.className default. Empty is allowed (no className
rendered).

Usage:
  {{ include "lunar.ingress.className" (dict "shared" .Values.hub.ingress.className "block" .Values.hub.ingress.api.className) }}
*/}}
{{- define "lunar.ingress.className" -}}
{{- default .shared .block -}}
{{- end }}

{{/*
Resolve per-ingress TLS list. Block-level list wins when non-empty;
otherwise falls back to ingress.tls. Empty list passes through.

Usage:
  {{ include "lunar.ingress.tls" (dict "shared" .Values.hub.ingress.tls "block" .Values.hub.ingress.api.tls) }}
*/}}
{{- define "lunar.ingress.tls" -}}
{{- if .block -}}
{{- toYaml .block -}}
{{- else -}}
{{- toYaml .shared -}}
{{- end -}}
{{- end }}

{{/*
Resolve per-ingress annotations by deep-merging the shared, block, and
optional sub-block layers in priority order (deepest wins). Sub-block
is used for api.grpcAnnotations / api.httpAnnotations.

Usage:
  {{ include "lunar.ingress.annotations" (dict "shared" .Values.hub.ingress.annotations "block" .Values.hub.ingress.api.annotations "sub" .Values.hub.ingress.api.grpcAnnotations) }}
*/}}
{{- define "lunar.ingress.annotations" -}}
{{- $sub := default (dict) .sub -}}
{{- $block := default (dict) .block -}}
{{- $shared := default (dict) .shared -}}
{{- $merged := merge (deepCopy $sub) $block $shared -}}
{{- if $merged -}}
{{- toYaml $merged -}}
{{- end -}}
{{- end }}
