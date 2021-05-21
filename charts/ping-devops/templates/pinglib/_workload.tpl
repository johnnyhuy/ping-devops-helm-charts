{{- define "pinglib.workload.tpl" -}}
{{- $top := index . 0 -}}
{{- $v := index . 1 -}}
apiVersion: apps/v1
{{/*--------------- Deployment | StatefulSet ---------------*/}}
kind: {{ $v.workload.type }}
metadata:
  {{ include "pinglib.metadata.labels" .  | nindent 2  }}
  {{ include "pinglib.metadata.annotations" .  | nindent 2  }}
  name: {{ include "pinglib.fullname" . }}
spec:
  replicas: {{ $v.container.replicaCount }}
  selector:
    matchLabels: {{ include "pinglib.selector.labels" . | nindent 6 }}

  {{- if eq $v.workload.type "Deployment" }}
  {{/*--------------------- Deployment ---------------------*/}}
  strategy:
    {{- with $v.workload.deployment.strategy }}
    type: {{ .type}}
    {{- if (eq .type "RollingUpdate") }}
    rollingUpdate: {{ toYaml .rollingUpdate | nindent 6 }}
    {{- end }}
    {{- end }}

  {{- else if eq $v.workload.type "StatefulSet" }}
  {{/*--------------------- StatefulSet ---------------------*/}}
  serviceName: {{ include "pinglib.fullname" . }}-cluster
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      partition: {{ $v.workload.statefulSet.partition }}
  podManagementPolicy: OrderedReady
  {{- end }}
  {{/*-------------------------------------------------------*/}}

  template:
    metadata:
      {{ include "pinglib.metadata.labels" .  | nindent 6  }}
        {{ include "pinglib.selector.labels" . | nindent 8 }}
      annotations:
        {{ include "pinglib.annotations.vault" $v.vault | nindent 8 }}
        {{ $prodChecksum := (include (print $top.Template.BasePath "/" $v.name "/configmap.yaml") $top | fromYaml).data | toYaml | sha256sum }}
        {{ $globChecksum := (include (print $top.Template.BasePath "/global/configmap.yaml") $top | fromYaml).data | toYaml | sha256sum }}
        checksum/config: {{ print $prodChecksum $globChecksum | sha256sum }}
        {{- if $v.workload.annotations }}
        {{- toYaml $v.workload.annotations | nindent 8 }}
        {{- end }}
    spec:
      terminationGracePeriodSeconds: {{ $v.container.terminationGracePeriodSeconds }}
      {{- if $v.vault.enabled }}
      serviceAccountName: {{ $v.vault.hashicorp.annotations.serviceAccountName }}
      {{- end }}
      nodeSelector: {{ toYaml $v.container.nodeSelector | nindent 8 }}
      tolerations: {{ toYaml $v.container.tolerations | nindent 8 }}
      affinity: {{ toYaml $v.container.affinity | nindent 8 }}
      initContainers:
        {{ include "pinglib.workload.init.waitfor" (concat . (list $v.container.waitFor "")) | nindent 6 }}
        {{ include "pinglib.workload.init.genPrivateCert" . | nindent 6 }}
      containers:
      - name: {{ $v.name }}
        env: []


        {{/*--------------------- Image -------------------------*/}}
        {{- with $v.image }}
        image: "{{ .repository }}/{{ .name }}:{{ .tag }}"
        imagePullPolicy: {{ .pullPolicy }}
        {{- end }}


        {{/*--------------------- Command -----------------------*/}}
        {{- with $v.container.command }}
        command:
          {{- range regexSplit " " ( default "" . ) -1 }}
            - {{ . | quote }}
          {{- end }}
        {{- end }}


        {{/*--------------------- Ports -----------------------*/}}
        {{- with $v.services }}
        ports:
        {{- range $serviceName, $val := . }}
        {{- if ne $serviceName "clusterExternalDNSHostname" }}
        - containerPort: {{ $val.containerPort }}
          name: {{ $serviceName }}
        {{- end }}
        {{- end }}
        {{- end }}


        {{/*--------------------- Environment -----------------*/}}
        envFrom:
        - configMapRef:
            name: {{ include "pinglib.addreleasename" (append . "global-env-vars") }}
            optional: true
        - configMapRef:
            name: {{ include "pinglib.addreleasename" (append . "env-vars") }}
            optional: true
        - configMapRef:
            name: {{ include "pinglib.fullname" . }}-env-vars
        - secretRef:
            name: {{ $v.license.secret.devOps }}
            optional: true
        - secretRef:
            name: {{ include "pinglib.fullname" . }}-git-secret
            optional: true
        {{- if $v.container.envFrom }}
        {{- toYaml $v.container.envFrom | nindent 8}}
        {{- end }}

        {{/*--------------------- Probes ---------------------*/}}
        {{- with $v.probes }}
        livenessProbe:
          exec:
            command: [ {{ .liveness.command }} ]
          initialDelaySeconds: {{ .liveness.initialDelaySeconds }}
          periodSeconds: {{ .liveness.periodSeconds }}
          timeoutSeconds: {{ .liveness.timeoutSeconds }}
          successThreshold: {{ .liveness.successThreshold }}
          failureThreshold: {{ .liveness.failureThreshold }}
        readinessProbe:
          exec:
            command: [ {{ .readiness.command }} ]
          initialDelaySeconds: {{ .readiness.initialDelaySeconds }}
          periodSeconds: {{ .readiness.periodSeconds }}
          timeoutSeconds: {{ .readiness.timeoutSeconds }}
          successThreshold: {{ .readiness.successThreshold }}
          failureThreshold: {{ .readiness.failureThreshold }}
        {{- end }}

        {{/*--------------------- Resources ------------------*/}}
        resources: {{ toYaml $v.container.resources | nindent 10 }}

        {{/*------------------- Volume Mounts ----------------*/}}
        volumeMounts:
        {{- if and (eq $v.workload.type "StatefulSet") $v.workload.statefulSet.persistentvolume.enabled }}
        {{- range $volName, $val := $v.workload.statefulSet.persistentvolume.volumes }}
        - name: {{ $volName }}{{ if eq "none" $v.addReleaseNameToResource }}-{{ $top.Release.Name }}{{ end }}
          mountPath: {{ .mountPath }}
        {{- end }}
        {{- end }}
        {{- if $v.privateCert.generate }}
        - name: private-keystore
          mountPath: /run/secrets/private-keystore
          readOnly: true
        {{- end }}
        {{- include "pinglib.workload.volumeMounts" $v | nindent 8 }}

        {{/*---------------- Security Context -------------*/}}
        {{/* Futures: Support for container securityContexts */}}
        {{/*securityContext: {{ toYaml $v.container.securityContext | nindent 10 }}*/}}


      {{/*---------------- Security Context -------------*/}}
      securityContext: {{ toYaml $v.workload.securityContext | nindent 8 }}

      {{/*--------------------- Volumes ------------------*/}}
      volumes:
      {{- if and (eq $v.workload.type "StatefulSet") $v.workload.statefulSet.persistentvolume.enabled }}
      {{- range $volName, $val := $v.workload.statefulSet.persistentvolume.volumes }}
      - name: {{ $volName }}{{ if eq "none" $v.addReleaseNameToResource }}-{{ $top.Release.Name }}{{ end }}
        persistentVolumeClaim:
          claimName: {{ $volName }}{{ if eq "none" $v.addReleaseNameToResource }}-{{ $top.Release.Name }}{{ end }}
      {{- end }}
      {{- end }}
      {{- if $v.privateCert.generate }}
      - name: private-keystore
        emptyDir: {}
      - name: private-cert
        secret:
          secretName: {{ include "pinglib.fullname" . }}-private-cert
      {{- end }}
      {{- include "pinglib.workload.volumes" $v | nindent 6 }}

  {{/*----------------- VolumeClameTemplates ------------------*/}}
  {{- if and (eq $v.workload.type "StatefulSet") $v.workload.statefulSet.persistentvolume.enabled }}
  volumeClaimTemplates:
  {{- range $volName, $val := $v.workload.statefulSet.persistentvolume.volumes }}
  - metadata:
      name: {{ $volName }}{{ if eq "none" $v.addReleaseNameToResource }}-{{ $top.Release.Name }}{{ end }}
    spec:
      {{ toYaml $val.persistentVolumeClaim | nindent 6 }}
  {{- end }}
  {{- end }}
{{- end -}}


{{- define "pinglib.workload" -}}
{{- include "pinglib.merge.templates" (append . "workload") -}}
{{- end -}}

{{- define "pinglib.workload.init.waitfor" -}}
{{- $top := index . 0 -}}
{{- $v := index . 1 -}}
{{- $waitFor := index . 2 -}}
{{- $containerName := index . 3 -}}
{{- range $prod, $val := $waitFor }}
  {{- if or $top.Values.enabled (index $top.Values $prod).enabled }}
    {{- $host := include "pinglib.addreleasename" (list $top $v $prod) }}
    {{- $waitForServices := (index $top.Values $prod).services }}
    {{- $port := (index $waitForServices $val.service).servicePort | quote }}
    {{- $timeout := printf "-t %d" (int (default 300 $val.timeoutSeconds )) -}}
    {{- $server := printf "%s:%s" $host $port }}
- name: {{ default (print "wait-for" $prod "-init") $containerName }}
  imagePullPolicy: {{ $v.image.pullPolicy }}
  image: {{ $v.externalImage.pingtoolkit }}
  command: ['sh', '-c', 'echo "Waiting for {{ $server }}..." && wait-for {{ $server }} {{ $timeout }} -- echo "{{ $server }} running"']
  {{ include "pinglib.workload.init.default.resources" . | nindent 2 }}
  {{ include "pinglib.workload.init.default.securityContext" . | nindent 2 }}
    {{- end }}
  {{- end }}
{{- end -}}


{{- define "pinglib.workload.init.genPrivateCert" -}}
{{- $top := index . 0 -}}
{{- $v := index . 1 -}}
{{- if $v.privateCert.generate }}
- name: generate-private-cert-init
  imagePullPolicy: {{ $v.image.pullPolicy }}
  image: {{ $v.externalImage.pingtoolkit }}
  command: ["/bin/sh"]
  args:
    - -c
    - >-
        _certPath=/run/secrets/private-cert &&
        _certEnv=/run/secrets/private-keystore/keystore.env &&
        echo "Generating ${_certEnv}" &&
        PRIVATE_KEYSTORE_PIN=$(openssl rand -base64 32) &&
        PRIVATE_KEYSTORE_TYPE=pkcs12 &&
        PRIVATE_KEYSTORE=$(openssl ${PRIVATE_KEYSTORE_TYPE} -export -inkey ${_certPath}/tls.key -in ${_certPath}/tls.crt -password pass:${PRIVATE_KEYSTORE_PIN} | base64 | tr -d \\n) &&
        echo "PRIVATE_KEYSTORE_TYPE=${PRIVATE_KEYSTORE_TYPE}">>${_certEnv} &&
        echo "PRIVATE_KEYSTORE_PIN=${PRIVATE_KEYSTORE_PIN}">>${_certEnv} &&
        echo "PRIVATE_KEYSTORE=${PRIVATE_KEYSTORE}">>${_certEnv}
  {{ include "pinglib.workload.init.default.resources" . | nindent 2 }}
  {{ include "pinglib.workload.init.default.securityContext" . | nindent 2 }}
  {{/*--------------------- Resources ------------------*/}}
  volumeMounts:
  - name: private-cert
    mountPath: /run/secrets/private-cert
  - name: private-keystore
    mountPath: /run/secrets/private-keystore
{{- end }}
{{- end -}}


{{- define "pinglib.workload.init.default.resources" -}}
resources:
  limits:
    cpu: 0
    memory: 128Mi
  requests:
    cpu: 0
    memory: 64Mi
{{- end -}}

{{- define "pinglib.workload.init.default.securityContext" -}}
securityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop:
    - ALL
  readOnlyRootFilesystem: true
  runAsGroup: 1000
  runAsNonRoot: true
  runAsUser: 100
{{- end -}}


{{/*--------------------------------------------------
  template volumes and volumeMounts expect a struture
  like:

  pingfederate-admin
    secretVolumes:
      pingfederate-license:
        items:
          license: /opt/in/instance/server/default/conf/pingfederate.lic
          hello: /opt/in/instance/server/default/hello.txt

  configMapVolumes:
    pingfederate-props:
        items:
          pf-props: /opt/in/etc/pingfederate.properties

------------------------------------------------------*/}}
{{- define "pinglib.workload.volumes" -}}
{{ $v := . }}
{{ range tuple "secretVolumes" "configMapVolumes" }}
{{ $volType := . }}
{{- range $volName, $volVal := (index $v .) }}
- name: {{ $volName }}
  {{- if eq $volType "secretVolumes" }}
  secret:
    secretName: {{ $volName }}
  {{- else if eq $volType "configMapVolumes" }}
  configMap:
    name: {{ $volName }}
  {{- end }}
    items:
    {{- range $keyName, $keyVal := $volVal.items }}
    - key: {{ $keyName }}
      path: {{ base $keyVal }}
    {{- end }}
{{- end }}
{{- end }}
{{- end -}}

{{- define "pinglib.workload.volumeMounts" -}}
{{ $v := . }}
{{ range tuple "secretVolumes" "configMapVolumes" }}
{{ $volType := . }}
{{- range $volName, $volVal := (index $v .) }}
{{- range $keyName, $keyVal := $volVal.items }}
- name: {{ $volName }}
  mountPath: {{ $keyVal }}
  subPath: {{ base $keyVal }}
  readOnly: true
{{- end }}
{{- end }}
{{- end }}
{{- end -}}