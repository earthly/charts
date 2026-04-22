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
Does the install look like it's configured for GitHub App auth?
True when both the numeric app.id and app.installId are non-zero.
*/}}
{{- define "lunar.hasGitHubApp" -}}
{{- if and (gt (int .Values.hub.github.app.id) 0) (gt (int .Values.hub.github.app.installId) 0) -}}
true
{{- end -}}
{{- end }}

{{/*
Does the install look like it's configured for GitHub PAT auth?
True when hub.github.token.secretName is set.
*/}}
{{- define "lunar.hasGitHubPAT" -}}
{{- if .Values.hub.github.token.secretName -}}
true
{{- end -}}
{{- end }}

{{/*
Fail fast when GitHub auth is misconfigured. Exactly one of App or PAT
must be configured — both is almost always a mistake, neither leaves
the hub unable to talk to GitHub.
*/}}
{{- define "lunar.githubAuthCheck" -}}
{{- $hasApp := include "lunar.hasGitHubApp" . -}}
{{- $hasPAT := include "lunar.hasGitHubPAT" . -}}
{{- if and $hasApp $hasPAT -}}
{{- fail "hub.github: configure either GitHub App auth (app.id + app.installId + app.privateKey) OR a PAT (token.secretName), not both." -}}
{{- end -}}
{{- if and (not $hasApp) (not $hasPAT) -}}
{{- fail "hub.github: no auth configured. Set GitHub App values (app.id + app.installId + app.privateKey.secretName) or a PAT (token.secretName)." -}}
{{- end -}}
{{- if and $hasApp (not .Values.hub.github.app.privateKey.secretName) -}}
{{- fail "hub.github.app: privateKey.secretName is required when app.id and app.installId are set." -}}
{{- end -}}
{{- end }}
