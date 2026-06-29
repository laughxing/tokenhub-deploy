#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

source "$SCRIPT_DIR/../scripts/common/preflight.sh"
source "$SCRIPT_DIR/../scripts/common/paths.sh"
PROXY_ROOT=$(resolve_tokenhub_proxy_root "$SCRIPT_DIR")

ENV_FILE=${ENV_FILE:-"$SCRIPT_DIR/.env"}
NAMESPACE=${NAMESPACE:-litellm}
RELEASE=${RELEASE:-litellm}
VALUES_FILE=${VALUES_FILE:-"$SCRIPT_DIR/values-ha-example.yaml"}
HELM_TIMEOUT=${HELM_TIMEOUT:-10m}
IMAGE_PREFIX=${IMAGE_PREFIX:-}
IMAGE_TAG=${IMAGE_TAG:-local}
BUILD_IMAGES=${BUILD_IMAGES:-false}
APPLY_MINIKUBE_DEPENDENCIES=${APPLY_MINIKUBE_DEPENDENCIES:-false}
MINIKUBE_DEPENDENCIES_FILE=${MINIKUBE_DEPENDENCIES_FILE:-"$SCRIPT_DIR/minikube-dependencies.yaml"}

load_env_file "$ENV_FILE"

require_command kubectl
require_command helm
validate_file "$VALUES_FILE"

if [ -n "${LITELLM_MASTER_KEY:-}" ]; then
  validate_master_key "$LITELLM_MASTER_KEY"
fi

image_repo() {
  local component=$1
  if [ -n "$IMAGE_PREFIX" ]; then
    echo "${IMAGE_PREFIX}/litellm-${component}"
  else
    echo "litellm-${component}"
  fi
}

if [ "$BUILD_IMAGES" = "true" ]; then
  IMAGE_PREFIX="$IMAGE_PREFIX" IMAGE_TAG="$IMAGE_TAG" "$SCRIPT_DIR/build-images.sh"
fi

kubectl get namespace "$NAMESPACE" >/dev/null 2>&1 || kubectl create namespace "$NAMESPACE"

if [ -n "${LITELLM_MASTER_KEY:-}" ]; then
  kubectl create secret generic litellm-master-key-secret \
    --namespace "$NAMESPACE" \
    --from-literal=master-key="$LITELLM_MASTER_KEY" \
    --dry-run=client \
    -o yaml | kubectl apply -f -
fi

if [ -n "${LITELLM_LICENSE:-}" ] && [ -z "${LITELLM_SALT_KEY:-}" ]; then
  echo "LITELLM_SALT_KEY is required when LITELLM_LICENSE is provided for secret upsert" >&2
  exit 1
fi

if [ -n "${LITELLM_SALT_KEY:-}" ]; then
  runtime_secret_args=(--from-literal=salt-key="${LITELLM_SALT_KEY:-}")
  if [ -n "${LITELLM_LICENSE:-}" ]; then
    runtime_secret_args+=(--from-literal=license="$LITELLM_LICENSE")
  fi
  kubectl create secret generic litellm-runtime-secret \
    --namespace "$NAMESPACE" \
    "${runtime_secret_args[@]}" \
    --dry-run=client \
    -o yaml | kubectl apply -f -
fi

if [ -n "${DB_USERNAME:-}" ] && [ -n "${DB_PASSWORD:-}" ]; then
  kubectl create secret generic litellm-writer-secret \
    --namespace "$NAMESPACE" \
    --from-literal=username="$DB_USERNAME" \
    --from-literal=password="$DB_PASSWORD" \
    --dry-run=client \
    -o yaml | kubectl apply -f -

  kubectl create secret generic litellm-reader-secret \
    --namespace "$NAMESPACE" \
    --from-literal=username="${DB_READER_USERNAME:-$DB_USERNAME}" \
    --from-literal=password="${DB_READER_PASSWORD:-$DB_PASSWORD}" \
    --dry-run=client \
    -o yaml | kubectl apply -f -
fi

if [ -n "${REDIS_PASSWORD:-}" ]; then
  kubectl create secret generic litellm-redis-secret \
    --namespace "$NAMESPACE" \
    --from-literal=password="$REDIS_PASSWORD" \
    --dry-run=client \
    -o yaml | kubectl apply -f -
fi

provider_secret_args=()
for key in OPENAI_API_KEY AZURE_API_KEY AZURE_API_BASE ANTHROPIC_API_KEY AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_REGION; do
  if [ -n "${!key:-}" ]; then
    provider_secret_args+=(--from-literal="$key=${!key}")
  fi
done

if [ "${#provider_secret_args[@]}" -gt 0 ]; then
  kubectl create secret generic litellm-provider-secrets \
    --namespace "$NAMESPACE" \
    "${provider_secret_args[@]}" \
    --dry-run=client \
    -o yaml | kubectl apply -f -
fi

require_kubernetes_secret "$NAMESPACE" litellm-master-key-secret
require_kubernetes_secret "$NAMESPACE" litellm-runtime-secret
require_kubernetes_secret "$NAMESPACE" litellm-writer-secret
require_kubernetes_secret "$NAMESPACE" litellm-reader-secret
if [ -n "${REDIS_PASSWORD:-}" ]; then
  require_kubernetes_secret "$NAMESPACE" litellm-redis-secret
fi
if [ "${#provider_secret_args[@]}" -gt 0 ]; then
  require_kubernetes_secret "$NAMESPACE" litellm-provider-secrets
fi

if [ "$APPLY_MINIKUBE_DEPENDENCIES" = "true" ]; then
  validate_file "$MINIKUBE_DEPENDENCIES_FILE"
  kubectl -n "$NAMESPACE" apply -f "$MINIKUBE_DEPENDENCIES_FILE"
  kubectl -n "$NAMESPACE" set image \
    deployment/litellm-minikube-fake-provider \
    fake-provider="$(image_repo fake-provider):$IMAGE_TAG"
  kubectl -n "$NAMESPACE" rollout status deployment/litellm-minikube-postgres --timeout="$HELM_TIMEOUT"
  kubectl -n "$NAMESPACE" rollout status deployment/litellm-minikube-redis --timeout="$HELM_TIMEOUT"
  kubectl -n "$NAMESPACE" rollout status deployment/litellm-minikube-fake-provider --timeout="$HELM_TIMEOUT"
fi

helm upgrade --install "$RELEASE" "$PROXY_ROOT/helm/litellm" \
  --namespace "$NAMESPACE" \
  --values "$VALUES_FILE" \
  --set gateway.image.repository="$(image_repo gateway)" \
  --set gateway.image.tag="$IMAGE_TAG" \
  --set backend.image.repository="$(image_repo backend)" \
  --set backend.image.tag="$IMAGE_TAG" \
  --set ui.image.repository="$(image_repo ui)" \
  --set ui.image.tag="$IMAGE_TAG" \
  --set migrationJob.image.repository="$(image_repo migrations)" \
  --set migrationJob.image.tag="$IMAGE_TAG" \
  --wait \
  --timeout "$HELM_TIMEOUT"

kubectl -n "$NAMESPACE" wait \
  --for=condition=complete \
  --timeout="$HELM_TIMEOUT" \
  job \
  -l "app.kubernetes.io/instance=$RELEASE,app.kubernetes.io/component=migrations" || true

kubectl -n "$NAMESPACE" rollout status "deployment/${RELEASE}-litellm-gateway" --timeout="$HELM_TIMEOUT"
kubectl -n "$NAMESPACE" rollout status "deployment/${RELEASE}-litellm-backend" --timeout="$HELM_TIMEOUT"
kubectl -n "$NAMESPACE" rollout status "deployment/${RELEASE}-litellm-ui" --timeout="$HELM_TIMEOUT"

if kubectl -n "$NAMESPACE" get deployment "${RELEASE}-litellm-otel-collector" >/dev/null 2>&1; then
  kubectl -n "$NAMESPACE" rollout status "deployment/${RELEASE}-litellm-otel-collector" --timeout="$HELM_TIMEOUT"
fi
if kubectl -n "$NAMESPACE" get deployment "${RELEASE}-litellm-jaeger" >/dev/null 2>&1; then
  kubectl -n "$NAMESPACE" rollout status "deployment/${RELEASE}-litellm-jaeger" --timeout="$HELM_TIMEOUT"
fi

cat <<EOF
LiteLLM clustered deployment is ready (image prefix: ${IMAGE_PREFIX:-<none>}, tag: ${IMAGE_TAG}).

Port-forward for local verification:
  kubectl -n ${NAMESPACE} port-forward svc/${RELEASE}-litellm-gateway 4000:4000

When tracing is enabled in values, open Jaeger UI via tracing.ingress.host (for example http://trace.localhost on minikube).

Health:
  curl -sS http://localhost:4000/health/readiness
EOF
