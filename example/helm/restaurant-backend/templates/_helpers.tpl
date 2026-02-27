{{/*
Common labels
*/}}
{{- define "restaurant.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "restaurant.selectorLabels" -}}
app: {{ .Chart.Name }}
release: {{ .Release.Name }}
{{- end }}
