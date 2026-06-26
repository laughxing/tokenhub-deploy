#!/usr/bin/env bash

wait_for_http() {
  local url=$1
  local timeout_seconds=${2:-120}
  local start_seconds
  local now_seconds

  require_command curl
  start_seconds=$(date +%s)

  while true; do
    if curl -fsS "$url" >/dev/null 2>&1; then
      return 0
    fi

    now_seconds=$(date +%s)
    if [ $((now_seconds - start_seconds)) -ge "$timeout_seconds" ]; then
      echo "Timed out waiting for $url" >&2
      return 1
    fi

    sleep 2
  done
}
