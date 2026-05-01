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
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
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
Namespace where snippet pods run. Defaults to the release namespace.
*/}}
{{- define "lunar.snippetNamespace" -}}
{{- .Values.operator.snippetNamespace | default .Release.Namespace }}
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
Fail fast when tenantId is unset. tenantId is required — it's used for
telemetry routing (Elastic indices, Grafana dashboard scoping) and as
this Hub's instance ID for GitHub webhook registration. Earthly assigns it.
*/}}
{{- define "lunar.tenantIdCheck" -}}
{{- if not .Values.tenantId -}}
{{- fail "tenantId is required. Earthly assigns this value — ask your contact if you don't know it." -}}
{{- end -}}
{{- end }}

{{/*
Resolved name for the chart-managed Hub auth-token secret.
Honors hub.auth.secretName when set; otherwise derives from the release.
*/}}
{{- define "lunar.hubAuthSecretName" -}}
{{- .Values.hub.auth.secretName | default (printf "%s-hub-auth-token" (include "lunar.fullname" .)) -}}
{{- end }}

{{/*
Resolved name for the chart-managed GitHub webhook secret.
*/}}
{{- define "lunar.hubWebhookSecretName" -}}
{{- .Values.hub.github.webhookSecret.secretName | default (printf "%s-hub-github-webhook" (include "lunar.fullname" .)) -}}
{{- end }}

{{/*
Resolved name for the chart-managed Grafana admin secret.
*/}}
{{- define "lunar.grafanaAdminSecretName" -}}
{{- .Values.grafana.admin.secretName | default (printf "%s-grafana-admin" (include "lunar.fullname" .)) -}}
{{- end }}
