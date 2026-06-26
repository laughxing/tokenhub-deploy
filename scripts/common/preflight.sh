#!/usr/bin/env bash

load_env_file() {
  local env_file=$1
  if [ -f "$env_file" ]; then
    set -a
    source "$env_file"
    set +a
  fi
}

require_command() {
  local command_name=$1
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing required command: $command_name" >&2
    exit 1
  fi
}

require_env() {
  local env_name=$1
  if [ -z "${!env_name:-}" ]; then
    echo "Missing required environment variable: $env_name" >&2
    exit 1
  fi
}

validate_master_key() {
  local master_key=$1
  case "$master_key" in
    sk-*) ;;
    *)
      echo "LITELLM_MASTER_KEY must start with sk-" >&2
      exit 1
      ;;
  esac
}

validate_file() {
  local file_path=$1
  if [ ! -f "$file_path" ]; then
    echo "File not found: $file_path" >&2
    exit 1
  fi
}

require_kubernetes_secret() {
  local namespace=$1
  local secret_name=$2
  if ! kubectl -n "$namespace" get secret "$secret_name" >/dev/null 2>&1; then
    echo "Missing Kubernetes Secret in namespace $namespace: $secret_name" >&2
    exit 1
  fi
}
