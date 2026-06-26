#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

source "$SCRIPT_DIR/../scripts/common/preflight.sh"
source "$SCRIPT_DIR/../scripts/common/paths.sh"
PROXY_ROOT=$(resolve_tokenhub_proxy_root "$SCRIPT_DIR")

IMAGE_PREFIX=${IMAGE_PREFIX:-}
IMAGE_TAG=${IMAGE_TAG:-local}
LOAD_INTO_MINIKUBE=${LOAD_INTO_MINIKUBE:-false}
BUILD_UI=${BUILD_UI:-true}
BUILD_FAKE_PROVIDER=${BUILD_FAKE_PROVIDER:-true}

require_command docker

image_repo() {
  local component=$1
  if [ -n "$IMAGE_PREFIX" ]; then
    echo "${IMAGE_PREFIX}/litellm-${component}"
  else
    echo "litellm-${component}"
  fi
}

build_one() {
  local root=$1
  local component=$2
  local dockerfile=$3
  local repo
  repo=$(image_repo "$component")
  local ref="${repo}:${IMAGE_TAG}"

  docker build -f "$root/$dockerfile" -t "$ref" "$root"

  if [ "$LOAD_INTO_MINIKUBE" = "true" ]; then
    require_command minikube
    minikube image load "$ref"
  fi

  echo "$ref"
}

build_one "$PROXY_ROOT" gateway gateway/Dockerfile
build_one "$PROXY_ROOT" backend backend/Dockerfile
build_one "$PROXY_ROOT" migrations migrations/Dockerfile
if [ "$BUILD_UI" = "true" ]; then
  build_one "$PROXY_ROOT" ui ui/Dockerfile
fi
if [ "$BUILD_FAKE_PROVIDER" = "true" ]; then
  E2E_ROOT=$(resolve_tokenhub_e2e_root "$SCRIPT_DIR")
  build_one "$E2E_ROOT" fake-provider fake_provider/Dockerfile
fi

cat <<EOF
Built component images with prefix='${IMAGE_PREFIX:-<none>}' tag='${IMAGE_TAG}'.

Install with the same prefix/tag:
  IMAGE_PREFIX='${IMAGE_PREFIX}' IMAGE_TAG='${IMAGE_TAG}' cluster/install.sh

For minikube, either re-run this script with LOAD_INTO_MINIKUBE=true,
or build directly inside minikube's docker with:
  eval \$(minikube docker-env)
EOF
