# TokenHub Kubernetes deployment

Single deployment path for TokenHub LiteLLM components (gateway, backend, UI, migrations) on any Kubernetes cluster. Helm chart lives in `TOKENHUB_PROXY_ROOT/helm/litellm`.

## Layout

| Path | Purpose |
| --- | --- |
| [values/base.yaml](values/base.yaml) | Shared component and tracing defaults (no ingress host, no DB/Redis endpoints) |
| [values/local-deps.yaml](values/local-deps.yaml) | In-cluster Postgres, Redis, fake provider Service names and fake model config |
| [values/production.yaml](values/production.yaml) | External data stores, HA sizing, TLS ingress, real providers |
| [values/overlays/minikube.yaml](values/overlays/minikube.yaml) | Dev mode, single-replica resources, Jaeger host |
| [values/overlays/apisix.yaml](values/overlays/apisix.yaml) | Disable LiteLLM Ingress; APISIX is the edge router |
| [values/overlays/production-apisix.yaml](values/overlays/production-apisix.yaml) | Production admin UI URL when using APISIX |
| [apisix/](apisix/) | APISIX standalone config and route templates |
| [scripts/install-apisix.sh](scripts/install-apisix.sh) | Deploy APISIX edge gateway after LiteLLM |
| [dependencies/local/manifests.yaml](dependencies/local/manifests.yaml) | Optional ephemeral Postgres, Redis, fake provider (local/dev only) |
| [scripts/build-images.sh](scripts/build-images.sh) | Build component images from source |
| [scripts/install.sh](scripts/install.sh) | Generic install on any Kubernetes cluster |
| [scripts/local-install.sh](scripts/local-install.sh) | Local loop: apply dependencies + minikube overlay |

Local minikube bootstrap details: [../minikube/README.md](../minikube/README.md).

| Local URL | Purpose |
| --- | --- |
| `http://api.localhost` | Public LLM API via APISIX |
| `http://admin.localhost` | Admin UI and management API via APISIX |
| `http://trace.localhost` | Jaeger admin/ops UI |
| `http://k8s.localhost` | Headlamp cluster ops UI (minikube only) |

## Architecture

```text
Client -> Ingress -> APISIX :9080 -> gateway / backend / ui
gateway, backend -> PostgreSQL, Redis
gateway -> LLM providers
gateway, backend -> OpenTelemetry Collector -> Jaeger
```

APISIX handles host/path routing (see [apisix/README.md](apisix/README.md)). LiteLLM chart Ingress stays off when `overlays/apisix.yaml` is merged.

## Image build

Build from `tokenhub-proxy` and `tokenhub-e2e` (fake provider):

```bash
IMAGE_PREFIX= IMAGE_TAG=local k8s/scripts/build-images.sh
```

Push to your registry for real clusters:

```bash
IMAGE_PREFIX=registry.example.internal/team IMAGE_TAG=v1 k8s/scripts/build-images.sh
docker push registry.example.internal/team/litellm-gateway:v1
# ... push backend, migrations, ui as needed
```

For minikube, load images after build:

```bash
LOAD_INTO_MINIKUBE=true IMAGE_TAG=local k8s/scripts/build-images.sh
```

## Local minikube loop

See [../minikube/README.md](../minikube/README.md). Quick path:

```bash
export LITELLM_MASTER_KEY="sk-local-master-key"
export LITELLM_SALT_KEY="sk-local-salt-key"
export DB_USERNAME="litellm"
export DB_PASSWORD="litellm-local-password"

LOAD_INTO_MINIKUBE=true IMAGE_TAG=local k8s/scripts/build-images.sh

NAMESPACE=litellm RELEASE=litellm IMAGE_TAG=local \
  LITELLM_MASTER_KEY="$LITELLM_MASTER_KEY" LITELLM_SALT_KEY="$LITELLM_SALT_KEY" \
  k8s/scripts/local-install.sh
```

- LLM API: `http://api.localhost/v1`
- Admin UI: `http://admin.localhost/ui`
- Jaeger UI: `http://trace.localhost`

## Production / real Kubernetes

1. Build and push images to a registry the cluster can pull from.
2. Create Secrets.
3. Copy and edit [values/production.yaml](values/production.yaml).
4. Install with APISIX edge (recommended):

```bash
export NAMESPACE=litellm RELEASE=litellm
export IMAGE_PREFIX=registry.example.internal/team IMAGE_TAG=v1
export LITELLM_MASTER_KEY=sk-replace-me LITELLM_SALT_KEY=sk-replace-me
export DB_USERNAME=litellm DB_PASSWORD=replace-me
export REDIS_PASSWORD=replace-me OPENAI_API_KEY=replace-me

VALUES_FILES="k8s/values/base.yaml k8s/values/production.yaml k8s/values/overlays/apisix.yaml k8s/values/overlays/production-apisix.yaml" \
  k8s/scripts/install.sh

API_HOST=api.example.com \
ADMIN_HOST=admin.example.internal \
API_TLS_SECRET=tokenhub-api-tls \
ADMIN_TLS_SECRET=tokenhub-admin-tls \
ADMIN_ALLOWED_IPS="10.0.0.0/8,192.168.0.0/16" \
  k8s/scripts/install-apisix.sh
```

Use your edited production values file instead of the in-repo example when endpoints differ.

Production edge defaults:

- `API_HOST` is the public LLM API host and is the only host bound to public `/v1/*`, `/health*`, and `/metrics` APISIX routes.
- `ADMIN_HOST` is for LiteLLM UI/backend only. Keep it on private DNS/VPN or set `ADMIN_ALLOWED_IPS` to operator CIDRs; use mTLS/OIDC/load-balancer policy if your environment provides a stronger control.
- `API_TLS_SECRET` and `ADMIN_TLS_SECRET` add TLS blocks to the APISIX Ingress. Leave them unset only for local or explicitly TLS-terminated upstream environments.
- Public APISIX routes expose configurable rate limit, request body size, and upstream timeout defaults via `PUBLIC_RATE_LIMIT_*`, `PUBLIC_MAX_BODY_SIZE_BYTES`, and `UPSTREAM_*_TIMEOUT_SECONDS`.

Render APISIX without applying:

```bash
DRY_RUN=true \
  API_HOST=api.example.com \
  ADMIN_HOST=admin.example.internal \
  API_TLS_SECRET=tokenhub-api-tls \
  ADMIN_TLS_SECRET=tokenhub-admin-tls \
  ADMIN_ALLOWED_IPS="10.0.0.0/8,192.168.0.0/16" \
  k8s/scripts/install-apisix.sh
```

Or without APISIX (Kubernetes Ingress only — less flexible routing):

```bash
VALUES_FILES="k8s/values/base.yaml k8s/values/production.yaml" k8s/scripts/install.sh
```

### Minikube to real K8s checklist

| Item | Local (minikube) | Real cluster |
| --- | --- | --- |
| Install script | `local-install.sh` | `install.sh` |
| Values merge | `base` + `local-deps` + `minikube` + `apisix` | `base` + `production` + `apisix` |
| Edge routing | APISIX @ `api.localhost` / `admin.localhost` | APISIX @ public API DNS + restricted admin DNS |
| Ops Ingress | `trace.localhost`, `k8s.localhost` | Jaeger / Headlamp on your DNS |
| Local dependencies | `APPLY_LOCAL_DEPENDENCIES=true` (default in local-install) | Do not apply |
| Database / Redis | In-cluster `litellm-local-*` Services | External managed endpoints in production values |
| Images | `LOAD_INTO_MINIKUBE=true` or minikube docker-env | Push to registry, set `IMAGE_PREFIX` / `IMAGE_TAG` |
| Replicas / resources | Single replica (minikube overlay) | HA settings in production values |

No changes to Helm chart templates or `dependencies/local/manifests.yaml` are required when moving to production—only values overlays and Secret/registry setup.

## Required Secrets

| Secret | Keys |
| --- | --- |
| `litellm-master-key-secret` | `master-key` |
| `litellm-runtime-secret` | `salt-key`, optional `license` |
| `litellm-writer-secret` | `username`, `password` |
| `litellm-reader-secret` | `username`, `password` |
| `litellm-redis-secret` | `password` (production with auth) |
| `litellm-provider-secrets` | Provider keys such as `OPENAI_API_KEY` |

`install.sh` can upsert Secrets from environment variables when they are set.

## Verify

```bash
kubectl -n litellm get pods
kubectl -n litellm get ingress

curl -sS http://api.localhost/v1/models -H "Authorization: Bearer ${LITELLM_MASTER_KEY}"
curl -sS http://api.localhost/health/readiness
```

Port-forward when ingress is unavailable:

```bash
kubectl -n litellm port-forward svc/litellm-litellm-gateway 4000:4000
```

## Clean up

```bash
helm -n litellm uninstall litellm
kubectl delete namespace litellm
```
