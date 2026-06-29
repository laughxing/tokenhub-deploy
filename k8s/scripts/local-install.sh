#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
K8S_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
MINIKUBE_ROOT=$(cd "$K8S_ROOT/../minikube" && pwd)

export VALUES_FILES="${VALUES_FILES:-$K8S_ROOT/values/base.yaml $K8S_ROOT/values/local-deps.yaml $K8S_ROOT/values/overlays/minikube.yaml $K8S_ROOT/values/overlays/apisix.yaml}"
export APPLY_LOCAL_DEPENDENCIES="${APPLY_LOCAL_DEPENDENCIES:-true}"
INSTALL_APISIX=${INSTALL_APISIX:-true}
INSTALL_HEADLAMP=${INSTALL_HEADLAMP:-true}

"$SCRIPT_DIR/install.sh"

if [ "$INSTALL_APISIX" = "true" ]; then
  "$SCRIPT_DIR/install-apisix.sh"
fi

if [ "$INSTALL_HEADLAMP" = "true" ]; then
  "$MINIKUBE_ROOT/scripts/install-headlamp.sh"
fi
