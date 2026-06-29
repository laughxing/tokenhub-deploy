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
DRY_RUN=${DRY_RUN:-false}
API_TLS_SECRET=${API_TLS_SECRET:-}
ADMIN_TLS_SECRET=${ADMIN_TLS_SECRET:-}
PUBLIC_RATE_LIMIT_COUNT=${PUBLIC_RATE_LIMIT_COUNT:-600}
PUBLIC_RATE_LIMIT_WINDOW_SECONDS=${PUBLIC_RATE_LIMIT_WINDOW_SECONDS:-60}
PUBLIC_MAX_BODY_SIZE_BYTES=${PUBLIC_MAX_BODY_SIZE_BYTES:-10485760}
UPSTREAM_CONNECT_TIMEOUT_SECONDS=${UPSTREAM_CONNECT_TIMEOUT_SECONDS:-30}
UPSTREAM_SEND_TIMEOUT_SECONDS=${UPSTREAM_SEND_TIMEOUT_SECONDS:-600}
UPSTREAM_READ_TIMEOUT_SECONDS=${UPSTREAM_READ_TIMEOUT_SECONDS:-600}
ADMIN_ALLOWED_IPS=${ADMIN_ALLOWED_IPS:-}

GATEWAY_SVC="${LITELLM_RELEASE}-litellm-gateway"
BACKEND_SVC="${LITELLM_RELEASE}-litellm-backend"
UI_SVC="${LITELLM_RELEASE}-litellm-ui"
GATEWAY_UPSTREAM="${GATEWAY_SVC}:4000"
BACKEND_UPSTREAM="${BACKEND_SVC}:4001"
UI_UPSTREAM="${UI_SVC}:3000"

require_command envsubst
require_command kubectl
require_command sha256sum
validate_file "$APISIX_ROOT/config.yaml"
validate_file "$APISIX_ROOT/routes.yaml.tpl"

if [ "$DRY_RUN" != "true" ]; then
  for svc in "$GATEWAY_SVC" "$BACKEND_SVC" "$UI_SVC"; do
    if ! kubectl -n "$LITELLM_NAMESPACE" get svc "$svc" >/dev/null 2>&1; then
      echo "Missing LiteLLM Service $svc in namespace $LITELLM_NAMESPACE. Install LiteLLM before APISIX." >&2
      exit 1
    fi
  done
fi

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

ADMIN_ACCESS_PLUGINS=""
if [ -n "$ADMIN_ALLOWED_IPS" ]; then
  ADMIN_ACCESS_PLUGINS=$(python3 - "$ADMIN_ALLOWED_IPS" <<'PY'
import sys

cidrs = [item.strip() for item in sys.argv[1].split(",") if item.strip()]
if cidrs:
    print("    plugins:")
    print("      ip-restriction:")
    print("        whitelist:")
    for cidr in cidrs:
        print(f"          - {cidr}")
PY
)
fi

APISIX_TLS_BLOCK=""
if [ -n "$API_TLS_SECRET" ] || [ -n "$ADMIN_TLS_SECRET" ]; then
  APISIX_TLS_BLOCK="  tls:"
  if [ -n "$API_TLS_SECRET" ]; then
    APISIX_TLS_BLOCK="${APISIX_TLS_BLOCK}
    - hosts:
        - ${API_HOST}
      secretName: ${API_TLS_SECRET}"
  fi
  if [ -n "$ADMIN_TLS_SECRET" ]; then
    APISIX_TLS_BLOCK="${APISIX_TLS_BLOCK}
    - hosts:
        - ${ADMIN_HOST}
      secretName: ${ADMIN_TLS_SECRET}"
  fi
fi

export API_HOST ADMIN_HOST GATEWAY_UPSTREAM BACKEND_UPSTREAM UI_UPSTREAM
export PUBLIC_RATE_LIMIT_COUNT PUBLIC_RATE_LIMIT_WINDOW_SECONDS PUBLIC_MAX_BODY_SIZE_BYTES
export UPSTREAM_CONNECT_TIMEOUT_SECONDS UPSTREAM_SEND_TIMEOUT_SECONDS UPSTREAM_READ_TIMEOUT_SECONDS
export ADMIN_ACCESS_PLUGINS APISIX_TLS_BLOCK
envsubst '${API_HOST} ${ADMIN_HOST} ${GATEWAY_UPSTREAM} ${BACKEND_UPSTREAM} ${UI_UPSTREAM} ${PUBLIC_RATE_LIMIT_COUNT} ${PUBLIC_RATE_LIMIT_WINDOW_SECONDS} ${PUBLIC_MAX_BODY_SIZE_BYTES} ${UPSTREAM_CONNECT_TIMEOUT_SECONDS} ${UPSTREAM_SEND_TIMEOUT_SECONDS} ${UPSTREAM_READ_TIMEOUT_SECONDS} ${ADMIN_ACCESS_PLUGINS}' \
  < "$APISIX_ROOT/routes.yaml.tpl" > "$TMP_DIR/apisix.yaml"

APISIX_CONFIG_CHECKSUM=$(sha256sum "$APISIX_ROOT/config.yaml" "$TMP_DIR/apisix.yaml" | sha256sum)
APISIX_CONFIG_CHECKSUM=${APISIX_CONFIG_CHECKSUM%% *}

if [ "$DRY_RUN" = "true" ]; then
  echo "# Rendered APISIX routes"
  cat "$TMP_DIR/apisix.yaml"
  echo "---"
  echo "# Rendered APISIX Kubernetes manifests"
fi

if [ "$DRY_RUN" = "true" ]; then
  APPLY_CMD=(cat)
else
  APPLY_CMD=(kubectl apply -f -)
fi

kubectl -n "$APISIX_NAMESPACE" create configmap "${APISIX_NAME}-config" \
  --from-file=config.yaml="$APISIX_ROOT/config.yaml" \
  --dry-run=client -o yaml | "${APPLY_CMD[@]}"

kubectl -n "$APISIX_NAMESPACE" create configmap "${APISIX_NAME}-routes" \
  --from-file=apisix.yaml="$TMP_DIR/apisix.yaml" \
  --dry-run=client -o yaml | "${APPLY_CMD[@]}"

cat <<EOF | "${APPLY_CMD[@]}"
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
      annotations:
        checksum/config: ${APISIX_CONFIG_CHECKSUM}
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
${APISIX_TLS_BLOCK}
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

if [ "$DRY_RUN" = "true" ]; then
  exit 0
fi

kubectl -n "$APISIX_NAMESPACE" rollout status "deployment/${APISIX_NAME}" --timeout="$HELM_TIMEOUT"

API_SCHEME=http
ADMIN_SCHEME=http
if [ -n "$API_TLS_SECRET" ]; then
  API_SCHEME=https
fi
if [ -n "$ADMIN_TLS_SECRET" ]; then
  ADMIN_SCHEME=https
fi

cat <<EOF
APISIX edge gateway is ready.

Public LLM API:  ${API_SCHEME}://${API_HOST}/v1
Admin UI/API:    ${ADMIN_SCHEME}://${ADMIN_HOST}/ui

Routes are defined in k8s/apisix/routes.yaml.tpl (rendered to ConfigMap ${APISIX_NAME}-routes).
Upstream targets:
  gateway: ${GATEWAY_UPSTREAM}
  backend: ${BACKEND_UPSTREAM}
  ui:      ${UI_UPSTREAM}
Admin CIDR allowlist: ${ADMIN_ALLOWED_IPS:-<not set>}

Re-apply after route edits:
  API_HOST=${API_HOST} ADMIN_HOST=${ADMIN_HOST} k8s/scripts/install-apisix.sh
EOF
