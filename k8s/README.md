# TokenHub Kubernetes deployment

Single deployment path for TokenHub LiteLLM components (gateway, backend, UI, migrations) on any Kubernetes cluster. Helm chart lives in `TOKENHUB_PROXY_ROOT/helm/litellm`.

## Layout

| Path | Purpose |
| --- | --- |
| [values/base.yaml](values/base.yaml) | Shared component and tracing defaults (no ingress host, no DB/Redis endpoints) |
| [values/local-deps.yaml](values/local-deps.yaml) | In-cluster Postgres, Redis, fake provider Service names and fake model config |
| [values/production.yaml](values/production.yaml) | External data stores, HA sizing, TLS ingress, real providers |
| [values/overlays/minikube.yaml](values/overlays/minikube.yaml) | Localhost ingress, dev mode, single-replica resources |
| [dependencies/local/manifests.yaml](dependencies/local/manifests.yaml) | Optional ephemeral Postgres, Redis, fake provider (local/dev only) |
| [scripts/build-images.sh](scripts/build-images.sh) | Build component images from source |
| [scripts/install.sh](scripts/install.sh) | Generic install on any Kubernetes cluster |
| [scripts/local-install.sh](scripts/local-install.sh) | Local loop: apply dependencies + minikube overlay |

Local minikube bootstrap details: [../minikube/README.md](../minikube/README.md).

| Local URL | Purpose |
| --- | --- |
| `http://api.localhost` | LiteLLM API and management |
| `http://trace.localhost` | Jaeger admin/ops UI |
| `http://k8s.localhost` | Headlamp cluster ops UI (minikube only) |

## Architecture

```text
Client -> Ingress -> gateway (4000) / backend (4001) / ui (3000)
gateway, backend -> PostgreSQL, Redis
gateway -> LLM providers (fake provider locally, real providers in production)
gateway, backend -> OpenTelemetry Collector -> Jaeger (tracing enabled in base values)
```

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

- LLM API: `http://api.localhost`
- Jaeger UI: `http://trace.localhost`

## Production / real Kubernetes

1. Build and push images to a registry the cluster can pull from.
2. Create Secrets (`litellm-master-key-secret`, `litellm-runtime-secret`, `litellm-writer-secret`, `litellm-reader-secret`, `litellm-redis-secret`, `litellm-provider-secrets`).
3. Copy and edit [values/production.yaml](values/production.yaml) for your ingress host, TLS, PostgreSQL, Redis, and provider keys.
4. Install **without** local dependencies:

```bash
export NAMESPACE=litellm
export RELEASE=litellm
export IMAGE_PREFIX=registry.example.internal/team
export IMAGE_TAG=v1
export LITELLM_MASTER_KEY=sk-replace-me
export LITELLM_SALT_KEY=sk-replace-me
export DB_USERNAME=litellm
export DB_PASSWORD=replace-me
export REDIS_PASSWORD=replace-me
export OPENAI_API_KEY=replace-me

VALUES_FILES="k8s/values/base.yaml /secure/litellm-production.yaml" \
  k8s/scripts/install.sh
```

Use your edited production values file instead of the in-repo example when endpoints and hostnames differ.

### Minikube to real K8s checklist

| Item | Local (minikube) | Real cluster |
| --- | --- | --- |
| Install script | `local-install.sh` | `install.sh` |
| Values merge | `base` + `local-deps` + `overlays/minikube` | `base` + `production` |
| Local dependencies | `APPLY_LOCAL_DEPENDENCIES=true` (default in local-install) | Do not apply |
| Ingress host | `api.localhost`, `trace.localhost` | Your DNS + TLS |
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
