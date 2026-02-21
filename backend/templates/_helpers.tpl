{{/*
チャート名を展開
*/}}
{{- define "sake-hack.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
デフォルトの完全修飾アプリケーション名を作成
*/}}
{{- define "sake-hack.fullname" -}}
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
チャートラベルで使用されるチャート名とバージョンを作成
*/}}
{{- define "sake-hack.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
共通ラベル
*/}}
{{- define "sake-hack.labels" -}}
helm.sh/chart: {{ include "sake-hack.chart" . }}
{{ include "sake-hack.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
セレクタラベル
*/}}
{{- define "sake-hack.selectorLabels" -}}
app.kubernetes.io/name: {{ include "sake-hack.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Secret名
*/}}
{{- define "sake-hack.secretName" -}}
{{- if .Values.secrets.existingSecretName -}}
{{- .Values.secrets.existingSecretName | trunc 63 | trimSuffix "-" -}}
{{- else if .Values.secrets.name -}}
{{- .Values.secrets.name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-secrets" (include "sake-hack.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end }}

{{/*
ConfigMap名
*/}}
{{- define "sake-hack.configMapName" -}}
{{- if .Values.configMap.name -}}
{{- .Values.configMap.name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-config" (include "sake-hack.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end }}
