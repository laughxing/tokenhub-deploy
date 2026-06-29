#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
K8S_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
APISIX_ROOT="$K8S_ROOT/apisix"

source "$K8S_ROOT/../scripts/common/preflight.sh"

LITELLM_NAMESPACE=${LITELLM_NAMESPACE:-${NAMESPACE:-litellm}}
LITELLM_RELEASE=${LITELLM_RELEASE:-${RELEASE:-litellm}}
APISIX_NAMESPACE=${APISIX_NAMESPACE:-$LITELLM_NAMESPACE}
APISIX_NAME=${APISIX_NAME:-litellm-apisix}
APISIX_IMAGE=${APISIX_IMAGE:-apache/apisix:3.11.0-debian}
API_HOST=${API_HOST:-api.localhost}
ADMIN_HOST=${ADMIN_HOST:-admin.localhost}
INGRESS_CLASS=${INGRESS_CLASS:-nginx}
HELM_TIMEOUT=${HELM_TIMEOUT:-5m}

GATEWAY_SVC="${LITELLM_RELEASE}-litellm-gateway"
BACKEND_SVC="${LITELLM_RELEASE}-litellm-backend"
UI_SVC="${LITELLM_RELEASE}-litellm-ui"
GATEWAY_UPSTREAM="${GATEWAY_SVC}:4000"
BACKEND_UPSTREAM="${BACKEND_SVC}:4001"
UI_UPSTREAM="${UI_SVC}:3000"

require_command kubectl
validate_file "$APISIX_ROOT/config.yaml"
validate_file "$APISIX_ROOT/routes.yaml.tpl"

for svc in "$GATEWAY_SVC" "$BACKEND_SVC" "$UI_SVC"; do
  if ! kubectl -n "$LITELLM_NAMESPACE" get svc "$svc" >/dev/null 2>&1; then
    echo "Missing LiteLLM Service $svc in namespace $LITELLM_NAMESPACE. Install LiteLLM before APISIX." >&2
    exit 1
  fi
done

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

export GATEWAY_UPSTREAM BACKEND_UPSTREAM UI_UPSTREAM ADMIN_HOST
envsubst '${GATEWAY_UPSTREAM} ${BACKEND_UPSTREAM} ${UI_UPSTREAM} ${ADMIN_HOST}' \
  < "$APISIX_ROOT/routes.yaml.tpl" > "$TMP_DIR/apisix.yaml"

kubectl -n "$APISIX_NAMESPACE" create configmap "${APISIX_NAME}-config" \
  --from-file=config.yaml="$APISIX_ROOT/config.yaml" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "$APISIX_NAMESPACE" create configmap "${APISIX_NAME}-routes" \
  --from-file=apisix.yaml="$TMP_DIR/apisix.yaml" \
  --dry-run=client -o yaml | kubectl apply -f -

cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${APISIX_NAME}
  namespace: ${APISIX_NAMESPACE}
  labels:
    app.kubernetes.io/name: ${APISIX_NAME}
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: ${APISIX_NAME}
  template:
    metadata:
      labels:
        app.kubernetes.io/name: ${APISIX_NAME}
    spec:
      initContainers:
        - name: copy-config
          image: busybox:1.36
          command:
            - sh
            - -c
            - |
              cp /cfg-src/config.yaml /writable/config.yaml
              cp /cfg-src/apisix.yaml /writable/apisix.yaml
              chown 636:636 /writable/config.yaml /writable/apisix.yaml
              chmod u+rw /writable/config.yaml /writable/apisix.yaml
          volumeMounts:
            - name: apisix-config-src
              mountPath: /cfg-src/config.yaml
              subPath: config.yaml
              readOnly: true
            - name: apisix-routes-src
              mountPath: /cfg-src/apisix.yaml
              subPath: apisix.yaml
              readOnly: true
            - name: apisix-writable
              mountPath: /writable
      containers:
        - name: apisix
          image: ${APISIX_IMAGE}
          env:
            - name: APISIX_STAND_ALONE
              value: "true"
          ports:
            - containerPort: 9080
              name: http
          volumeMounts:
            - name: apisix-writable
              mountPath: /usr/local/apisix/conf/config.yaml
              subPath: config.yaml
            - name: apisix-writable
              mountPath: /usr/local/apisix/conf/apisix.yaml
              subPath: apisix.yaml
          readinessProbe:
            tcpSocket:
              port: http
            initialDelaySeconds: 10
            periodSeconds: 5
          resources:
            requests:
              cpu: 50m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 768Mi
      volumes:
        - name: apisix-writable
          emptyDir: {}
        - name: apisix-config-src
          configMap:
            name: ${APISIX_NAME}-config
        - name: apisix-routes-src
          configMap:
            name: ${APISIX_NAME}-routes
---
apiVersion: v1
kind: Service
metadata:
  name: ${APISIX_NAME}
  namespace: ${APISIX_NAMESPACE}
  labels:
    app.kubernetes.io/name: ${APISIX_NAME}
spec:
  selector:
    app.kubernetes.io/name: ${APISIX_NAME}
  ports:
    - name: http
      port: 9080
      targetPort: http
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${APISIX_NAME}
  namespace: ${APISIX_NAMESPACE}
  labels:
    app.kubernetes.io/name: ${APISIX_NAME}
spec:
  ingressClassName: ${INGRESS_CLASS}
  rules:
    - host: ${API_HOST}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: ${APISIX_NAME}
                port:
                  number: 9080
    - host: ${ADMIN_HOST}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: ${APISIX_NAME}
                port:
                  number: 9080
EOF

kubectl -n "$APISIX_NAMESPACE" rollout status "deployment/${APISIX_NAME}" --timeout="$HELM_TIMEOUT"

cat <<EOF
APISIX edge gateway is ready.

Public LLM API:  http://${API_HOST}/v1
Admin UI/API:    http://${ADMIN_HOST}/ui

Routes are defined in k8s/apisix/routes.yaml.tpl (rendered to ConfigMap ${APISIX_NAME}-routes).
Upstream targets:
  gateway: ${GATEWAY_UPSTREAM}
  backend: ${BACKEND_UPSTREAM}
  ui:      ${UI_UPSTREAM}

Re-apply after route edits:
  API_HOST=${API_HOST} ADMIN_HOST=${ADMIN_HOST} k8s/scripts/install-apisix.sh
EOF
