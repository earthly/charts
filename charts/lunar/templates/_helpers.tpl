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
Resolved name for the Grafana auth secret. In chart mode this is the chart-managed
admin secret (generated as <release>-grafana-admin when grafana.auth.secretName is
empty); in external mode it's the operator-supplied secret. Name kept as
"-grafana-admin" for continuity.
*/}}
{{- define "lunar.grafanaAuthSecretName" -}}
{{- .Values.grafana.auth.secretName | default (printf "%s-grafana-admin" (include "lunar.fullname" .)) -}}
{{- end }}

{{/*
Resolved name for the chart-managed read-only Grafana DB-role (grafana_user)
password secret, used by the lunar-dashboards provisioning tool's datasource.
*/}}
{{- define "lunar.grafanaDBSecretName" -}}
{{- .Values.grafana.provisioning.dbPassword.secretName | default (printf "%s-grafana-db" (include "lunar.fullname" .)) -}}
{{- end }}

{{/*
lunar-dashboards provisioning image ref (repository:tag). The tag defaults to the
hub image tag so dashboards match the running Hub's schema. Shared by the
provisioning Job and the reconverge sidecar.
*/}}
{{- define "lunar.provisioningImage" -}}
{{- printf "%s:%s" .Values.grafana.provisioning.image.repository (.Values.grafana.provisioning.image.tag | default .Values.hub.image.tag) -}}
{{- end }}

{{/*
Shell snippet: block until the Hub's gRPC answers (reflection `list`). deploy.sh
makes a single Hub gRPC call with no internal retry, so both the provisioning Job's
init container and the reconverge sidecar wait for the Hub before invoking it.
*/}}
{{- define "lunar.waitForHub" -}}
until grpcurl -plaintext -connect-timeout 5 -H "Authorization: Bearer $LUNAR_HUB_TOKEN" "$LUNAR_HUB_HOST:$LUNAR_HUB_GRPC_PORT" list >/dev/null 2>&1; do
  echo "waiting for hub..."; sleep 2;
done
{{- end }}

{{/*
Shell snippet: block until Grafana's API answers at $GRAFANA_URL. Shared by the
provisioning Job's init container (chart pod) and the reconverge sidecar.
*/}}
{{- define "lunar.waitForGrafana" -}}
until curl -fsS "$GRAFANA_URL/api/health" >/dev/null 2>&1; do
  echo "waiting for grafana..."; sleep 2;
done
{{- end }}

{{/*
LUNAR_HUB_* env for the lunar-dashboards provisioning tool (the provisioning hook
Job and the reconverge sidecar). deploy.sh uses it to resolve the Grafana endpoint
+ a read-only DB connection from the Hub over gRPC. Only LUNAR_HUB_TOKEN is sensitive.
*/}}
{{- define "lunar.grafanaProvisionHubEnv" -}}
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
{{- fail "hub.grafanaURLBase was renamed (grafana.externalURL in chart 2.0.0, now grafana.url in 3.0.0 — the value is a Grafana property; the hub consumes it, doesn't own it). See README \"Migrating from chart 1.x\"." -}}
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

  1. grafana.url                              explicit override
  2. https://<grafana.ingress.hosts[0].host>  chart-managed Grafana ingress

Empty otherwise — the chart only derives a URL when it actually controls
the routing. Deliberately does NOT guess based on hub.ingress.api.host
(chart doesn't route Grafana traffic there) or hub.webhookURL (wrong
trust boundary). Installs that expose Grafana via external routing
MUST set grafana.url explicitly, especially when Grafana fronts
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
{{- if $grafana.url -}}{{ $grafana.url }}
{{- else if $grafanaHost -}}{{ printf "https://%s" $grafanaHost }}
{{- end -}}
{{- end }}

{{/*
Validate the Grafana configuration:
  - Reject the pre-3.0.0 keys replaced in the mode/url/auth rework
    (grafana.enabled, grafana.provisioning.enabled, grafana.externalURL,
    grafana.admin). A stale value would otherwise be silently ignored, so fail
    fast with migration guidance.
  - grafana.mode must be one of chart | external | off.
  - chart mode needs a resolvable Grafana URL (grafana.url or chart-managed
    ingress) for GF_SERVER_ROOT_URL, and auth.tokenKey must be unset (the bundled
    pod uses basic admin auth).
  - external mode needs grafana.url and grafana.auth.secretName (the chart can't
    generate credentials for a Grafana it doesn't own).
*/}}
{{- define "lunar.validateGrafana" -}}
{{- if hasKey .Values.grafana "enabled" -}}
{{- fail "grafana.enabled was replaced by grafana.mode in chart 3.0.0. Set grafana.mode to one of:\n  - chart     (bundled Grafana pod + dashboards; was grafana.enabled=true)\n  - external  (bring-your-own Grafana + dashboards; was grafana.enabled=false + provisioning)\n  - off       (no Grafana, no dashboards)" -}}
{{- end -}}
{{- if hasKey .Values.grafana.provisioning "enabled" -}}
{{- fail "grafana.provisioning.enabled was removed in chart 3.0.0 — dashboard provisioning is now implied by grafana.mode (chart and external provision; off does not). Drop grafana.provisioning.enabled and set grafana.mode." -}}
{{- end -}}
{{- if hasKey .Values.grafana "externalURL" -}}
{{- fail "grafana.externalURL was renamed to grafana.url in chart 3.0.0 (it now applies to both chart and external modes). Rename grafana.externalURL -> grafana.url." -}}
{{- end -}}
{{- if hasKey .Values.grafana "admin" -}}
{{- fail "grafana.admin was renamed to grafana.auth in chart 3.0.0 (same secretName/userKey/passwordKey, plus an optional tokenKey for external Grafana). Rename grafana.admin -> grafana.auth." -}}
{{- end -}}
{{- $mode := .Values.grafana.mode -}}
{{- if not (has $mode (list "chart" "external" "off")) -}}
{{- fail (printf "grafana.mode must be one of chart | external | off (got %q)." $mode) -}}
{{- end -}}
{{- if eq $mode "chart" -}}
  {{- if .Values.grafana.auth.tokenKey -}}
    {{- fail "grafana.auth.tokenKey is only valid in grafana.mode=external — the bundled Grafana pod uses basic admin auth. Unset auth.tokenKey, or switch to grafana.mode=external." -}}
  {{- end -}}
  {{- $url := include "lunar.grafanaURL" . -}}
  {{- if not $url -}}
    {{- fail "grafana.url is required when grafana.mode is \"chart\" and the chart doesn't manage Grafana's ingress (the chart doesn't derive Grafana URLs it doesn't route to — see README \"Migrating from chart 1.x\" for the Caddy / content-routing case). Pick one:\n  - grafana.url = \"<your Grafana URL>\"       (BYO ingress / Caddy / external routing)\n  - grafana.ingress.enabled = true          (chart-managed Grafana ingress)\n  - grafana.mode = \"external\" or \"off\"" -}}
  {{- end -}}
{{- else if eq $mode "external" -}}
  {{- if not .Values.grafana.url -}}
    {{- fail "grafana.url is required when grafana.mode is \"external\" — it's the base URL of your Grafana that the Hub vends to the provisioning tool (and uses for [More Details] links)." -}}
  {{- end -}}
  {{- if not .Values.grafana.auth.secretName -}}
    {{- fail "grafana.auth.secretName is required when grafana.mode is \"external\" — the chart can't generate credentials for a Grafana it doesn't own. Provide a secret with basic creds (auth.userKey + auth.passwordKey) or a service-account token (set auth.tokenKey to the token's key)." -}}
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
