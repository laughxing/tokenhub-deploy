#!/usr/bin/env bash

resolve_tokenhub_proxy_root() {
  local deploy_subdir=$1

  if [ -n "${TOKENHUB_PROXY_ROOT:-}" ]; then
    cd "$TOKENHUB_PROXY_ROOT" && pwd
    return
  fi

  local deploy_root
  deploy_root=$(cd "$deploy_subdir/.." && pwd)
  local candidate="$deploy_root/../../dev/tokenhub-proxy"
  if [ -d "$candidate" ]; then
    cd "$candidate" && pwd
    return
  fi

  echo "Cannot find tokenhub-proxy. Set TOKENHUB_PROXY_ROOT." >&2
  exit 1
}

resolve_tokenhub_e2e_root() {
  local deploy_subdir=$1

  if [ -n "${TOKENHUB_E2E_ROOT:-}" ]; then
    cd "$TOKENHUB_E2E_ROOT" && pwd
    return
  fi

  local deploy_root
  deploy_root=$(cd "$deploy_subdir/.." && pwd)
  local candidate="$deploy_root/../../dev/tokenhub-e2e"
  if [ -d "$candidate" ]; then
    cd "$candidate" && pwd
    return
  fi

  echo "Cannot find tokenhub-e2e. Set TOKENHUB_E2E_ROOT." >&2
  exit 1
}

resolve_tokenhub_web_root() {
  local deploy_subdir=$1

  if [ -n "${TOKENHUB_WEB_ROOT:-}" ]; then
    cd "$TOKENHUB_WEB_ROOT" && pwd
    return
  fi

  local deploy_root
  deploy_root=$(cd "$deploy_subdir/.." && pwd)
  local candidate="$deploy_root/../../dev/tokenhub-web"
  if [ -d "$candidate" ]; then
    cd "$candidate" && pwd
    return
  fi

  echo "Cannot find tokenhub-web. Set TOKENHUB_WEB_ROOT." >&2
  exit 1
}
