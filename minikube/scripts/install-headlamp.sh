#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
MINIKUBE_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

source "$MINIKUBE_ROOT/../scripts/common/preflight.sh"

HEADLAMP_NAMESPACE=${HEADLAMP_NAMESPACE:-headlamp}
HEADLAMP_RELEASE=${HEADLAMP_RELEASE:-headlamp}
HEADLAMP_VALUES_FILE=${HEADLAMP_VALUES_FILE:-"$MINIKUBE_ROOT/headlamp/values.yaml"}
HELM_TIMEOUT=${HELM_TIMEOUT:-5m}
HEADLAMP_HELM_REPO=${HEADLAMP_HELM_REPO:-https://kubernetes-sigs.github.io/headlamp/}

require_command kubectl
require_command helm
validate_file "$HEADLAMP_VALUES_FILE"

if ! helm repo list 2>/dev/null | awk '{print $1}' | grep -qx 'headlamp'; then
  helm repo add headlamp "$HEADLAMP_HELM_REPO"
fi
helm repo update headlamp >/dev/null

kubectl get namespace "$HEADLAMP_NAMESPACE" >/dev/null 2>&1 || kubectl create namespace "$HEADLAMP_NAMESPACE"

helm upgrade --install "$HEADLAMP_RELEASE" headlamp/headlamp \
  --namespace "$HEADLAMP_NAMESPACE" \
  --values "$HEADLAMP_VALUES_FILE" \
  --wait \
  --timeout "$HELM_TIMEOUT"

kubectl -n "$HEADLAMP_NAMESPACE" rollout status "deployment/${HEADLAMP_RELEASE}" --timeout="$HELM_TIMEOUT" 2>/dev/null \
  || kubectl -n "$HEADLAMP_NAMESPACE" rollout status "deployment/headlamp" --timeout="$HELM_TIMEOUT"

LOGIN_TOKEN=$(kubectl -n "$HEADLAMP_NAMESPACE" create token headlamp --duration=8760h)

cat <<EOF
Headlamp is ready at http://k8s.localhost

On minikube, point k8s.localhost at \$(minikube ip) in /etc/hosts, or use:
  curl --resolve "k8s.localhost:80:\$(minikube ip)" http://k8s.localhost/

Login: open Headlamp and choose "Token", then paste:

${LOGIN_TOKEN}

Token is valid for 8760h and belongs to ServiceAccount headlamp (cluster-admin, local dev only).

Uninstall:
  helm -n ${HEADLAMP_NAMESPACE} uninstall ${HEADLAMP_RELEASE}
EOF
