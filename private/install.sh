#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

source "$SCRIPT_DIR/../scripts/common/preflight.sh"
source "$SCRIPT_DIR/../scripts/common/paths.sh"
source "$SCRIPT_DIR/../scripts/common/wait-healthy.sh"
PROXY_ROOT=$(resolve_tokenhub_proxy_root "$SCRIPT_DIR")

ENV_FILE=${ENV_FILE:-"$SCRIPT_DIR/.env"}
COMPOSE_FILE=${COMPOSE_FILE:-"$SCRIPT_DIR/docker-compose.prod.yml"}
CONFIG_PATH=${LITELLM_CONFIG_PATH:-"$SCRIPT_DIR/config.example.yaml"}
LITELLM_PORT=${LITELLM_PORT:-4000}
RUN_MIGRATIONS=${RUN_MIGRATIONS:-true}
SKIP_BUILD=${SKIP_BUILD:-false}

load_env_file "$ENV_FILE"

require_command docker
require_env LITELLM_MASTER_KEY
require_env LITELLM_SALT_KEY
require_env DATABASE_URL
validate_master_key "$LITELLM_MASTER_KEY"
validate_file "$CONFIG_PATH"

image="${LITELLM_IMAGE:-litellm-database:local}"

if [ "$SKIP_BUILD" != "true" ]; then
  docker build \
    -f "$PROXY_ROOT/docker/Dockerfile.database" \
    -t "$image" \
    "$PROXY_ROOT"
fi

compose_args=(-f "$COMPOSE_FILE")
docker_env_args=()
if [ -f "$ENV_FILE" ]; then
  compose_args=(--env-file "$ENV_FILE" "${compose_args[@]}")
  docker_env_args=(--env-file "$ENV_FILE")
fi

if [ "$RUN_MIGRATIONS" = "true" ]; then
  docker run --rm \
    "${docker_env_args[@]}" \
    -e DATABASE_URL="$DATABASE_URL" \
    -e DATABASE_URL_READ_REPLICA="${DATABASE_URL_READ_REPLICA:-}" \
    -e LITELLM_MASTER_KEY="$LITELLM_MASTER_KEY" \
    -e LITELLM_SALT_KEY="$LITELLM_SALT_KEY" \
    -e LITELLM_MODE=PRODUCTION \
    -e OPENAI_API_KEY="${OPENAI_API_KEY:-}" \
    -e AZURE_API_KEY="${AZURE_API_KEY:-}" \
    -e AZURE_API_BASE="${AZURE_API_BASE:-}" \
    -e REDIS_HOST="${REDIS_HOST:-redis}" \
    -e REDIS_PORT="${REDIS_PORT:-6379}" \
    -e REDIS_PASSWORD="${REDIS_PASSWORD:-}" \
    -v "$CONFIG_PATH:/app/config.yaml:ro" \
    "$image" \
    --config /app/config.yaml \
    --skip_server_startup \
    --use_v2_migration_resolver
fi

(
  cd "$SCRIPT_DIR"
  LITELLM_IMAGE="$image" LITELLM_CONFIG_PATH="$CONFIG_PATH" LITELLM_PORT="$LITELLM_PORT" docker compose "${compose_args[@]}" up -d
)

wait_for_http "http://localhost:${LITELLM_PORT}/health/readiness" 120

cat <<EOF
LiteLLM private deployment is ready (image: ${image}).

Health:
  curl -sS http://localhost:${LITELLM_PORT}/health/readiness

Provider smoke test:
  curl -sS http://localhost:${LITELLM_PORT}/v1/chat/completions \\
    -H "Authorization: Bearer \${LITELLM_MASTER_KEY}" \\
    -H "Content-Type: application/json" \\
    -d '{"model":"gpt-4o","messages":[{"role":"user","content":"Say LiteLLM private deployment is ready"}]}'
EOF
