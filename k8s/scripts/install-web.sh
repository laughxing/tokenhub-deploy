#!/usr/bin/env bash
set -euo pipefail

# Installs tokenhub-web (REQ-V2-006) into the TokenHub namespace. Renders
# k8s/web/manifests.yaml.tpl with envsubst and applies it. The web Secret
# (session + admin token) is created here; the LiteLLM master key is reused from
# the existing litellm-master-key-secret so the BFF can reach the management API.

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
K8S_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
WEB_ROOT="$K8S_ROOT/web"

source "$K8S_ROOT/../scripts/common/preflight.sh"

NAMESPACE=${NAMESPACE:-litellm}
RELEASE=${RELEASE:-litellm}
WEB_NAME=${WEB_NAME:-tokenhub-web}
WEB_NAMESPACE=${WEB_NAMESPACE:-$NAMESPACE}
WEB_IMAGE=${WEB_IMAGE:-tokenhub-web:local}
WEB_IMAGE_PULL_POLICY=${WEB_IMAGE_PULL_POLICY:-IfNotPresent}
WEB_PORT=${WEB_PORT:-8080}
WEB_REPLICAS=${WEB_REPLICAS:-1}
WEB_ENV=${WEB_ENV:-production}
WEB_HOST=${WEB_HOST:-web.localhost}
WEB_ORIGIN=${WEB_ORIGIN:-http://${WEB_HOST}}
API_HOST=${API_HOST:-api.localhost}
# LiteLLM management API (/key, /organization, /team, /user, /spend) is served by
# the backend service (4001); the gateway (4000) serves the public /v1 proxy.
WEB_PUBLIC_API_BASE_URL=${WEB_PUBLIC_API_BASE_URL:-http://${API_HOST}}
WEB_LITELLM_ADMIN_BASE_URL=${WEB_LITELLM_ADMIN_BASE_URL:-http://${RELEASE}-litellm-backend:4001}
WEB_LITELLM_MODE=${WEB_LITELLM_MODE:-http}
WEB_MVP_MODELS=${WEB_MVP_MODELS:-deepseek-chat}
WEB_INITIAL_MAX_BUDGET=${WEB_INITIAL_MAX_BUDGET:-5}
WEB_OTP_DEV_SINK=${WEB_OTP_DEV_SINK:-true}
WEB_EMAIL_PROVIDER=${WEB_EMAIL_PROVIDER:-log}
WEB_COOKIE_SECURE=${WEB_COOKIE_SECURE:-false}
WEB_MASTER_KEY_SECRET=${WEB_MASTER_KEY_SECRET:-litellm-master-key-secret}
WEB_MASTER_KEY_SECRET_KEY=${WEB_MASTER_KEY_SECRET_KEY:-master-key}
WEB_SECRET=${WEB_SECRET:-tokenhub-web-secret}
WEB_SESSION_SECRET=${WEB_SESSION_SECRET:-$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 32)}
WEB_ADMIN_API_TOKEN=${WEB_ADMIN_API_TOKEN:-$(head -c 24 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 24)}
HELM_TIMEOUT=${HELM_TIMEOUT:-5m}
DRY_RUN=${DRY_RUN:-false}

require_command kubectl
require_command envsubst
require_command sha256sum
validate_file "$WEB_ROOT/manifests.yaml.tpl"

# Restart pods when non-secret config changes by hashing the rendered config values.
WEB_CONFIG_CHECKSUM=$(printf '%s' \
  "${WEB_ENV}|${WEB_PORT}|${WEB_ORIGIN}|${WEB_PUBLIC_API_BASE_URL}|${WEB_LITELLM_ADMIN_BASE_URL}|${WEB_LITELLM_MODE}|${WEB_MVP_MODELS}|${WEB_INITIAL_MAX_BUDGET}|${WEB_OTP_DEV_SINK}|${WEB_EMAIL_PROVIDER}|${WEB_COOKIE_SECURE}|${WEB_IMAGE}" \
  | sha256sum | cut -d' ' -f1)

export WEB_NAME WEB_NAMESPACE WEB_IMAGE WEB_IMAGE_PULL_POLICY WEB_PORT WEB_REPLICAS
export WEB_ENV WEB_ORIGIN WEB_PUBLIC_API_BASE_URL WEB_LITELLM_ADMIN_BASE_URL WEB_LITELLM_MODE
export WEB_MVP_MODELS WEB_INITIAL_MAX_BUDGET WEB_OTP_DEV_SINK WEB_EMAIL_PROVIDER WEB_COOKIE_SECURE
export WEB_MASTER_KEY_SECRET WEB_MASTER_KEY_SECRET_KEY WEB_SECRET WEB_CONFIG_CHECKSUM

RENDERED=$(envsubst '${WEB_NAME} ${WEB_NAMESPACE} ${WEB_IMAGE} ${WEB_IMAGE_PULL_POLICY} ${WEB_PORT} ${WEB_REPLICAS} ${WEB_ENV} ${WEB_ORIGIN} ${WEB_PUBLIC_API_BASE_URL} ${WEB_LITELLM_ADMIN_BASE_URL} ${WEB_LITELLM_MODE} ${WEB_MVP_MODELS} ${WEB_INITIAL_MAX_BUDGET} ${WEB_OTP_DEV_SINK} ${WEB_EMAIL_PROVIDER} ${WEB_COOKIE_SECURE} ${WEB_MASTER_KEY_SECRET} ${WEB_MASTER_KEY_SECRET_KEY} ${WEB_SECRET} ${WEB_CONFIG_CHECKSUM}' < "$WEB_ROOT/manifests.yaml.tpl")

if [ "$DRY_RUN" = "true" ]; then
  echo "# tokenhub-web Secret: ${WEB_SECRET} (session-secret, admin-token) in ${WEB_NAMESPACE}"
  echo "$RENDERED"
  exit 0
fi

kubectl get namespace "$WEB_NAMESPACE" >/dev/null 2>&1 || kubectl create namespace "$WEB_NAMESPACE"

kubectl -n "$WEB_NAMESPACE" create secret generic "$WEB_SECRET" \
  --from-literal=session-secret="$WEB_SESSION_SECRET" \
  --from-literal=admin-token="$WEB_ADMIN_API_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "$RENDERED" | kubectl apply -f -

kubectl -n "$WEB_NAMESPACE" rollout status "deployment/${WEB_NAME}" --timeout="$HELM_TIMEOUT"

cat <<EOF
tokenhub-web is deployed.

Service:   ${WEB_NAME}.${WEB_NAMESPACE}:${WEB_PORT}
Web host:  http://${WEB_HOST}  (route applied by install-apisix.sh)
LiteLLM:   ${WEB_LITELLM_ADMIN_BASE_URL} (mode=${WEB_LITELLM_MODE})
Admin top-up token stored in Secret ${WEB_SECRET} (key: admin-token).

Read it with:
  kubectl -n ${WEB_NAMESPACE} get secret ${WEB_SECRET} -o jsonpath='{.data.admin-token}' | base64 -d
EOF
