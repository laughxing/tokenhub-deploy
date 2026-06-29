# Minikube local loop

Bootstrap minikube for the TokenHub V1 Kubernetes path. Application manifests and Helm values are under [../k8s/](../k8s/); this directory only covers minikube-specific setup.

## Prerequisites

- [minikube](https://minikube.sigs.k8s.io/docs/start/)
- Docker with BuildKit and buildx
- Helm 3, kubectl

## Start cluster

```bash
minikube start --driver=docker
minikube addons enable ingress
```

Ingress uses `api.localhost`, `admin.localhost`, `trace.localhost`, and `k8s.localhost`. Public LLM traffic and admin UI/API go through **APISIX** on `api.localhost` / `admin.localhost`.

## Build and load images

From `deploy/tokenhub-deploy`:

```bash
LOAD_INTO_MINIKUBE=true IMAGE_TAG=local k8s/scripts/build-images.sh
```

Alternative: build inside minikube's Docker daemon:

```bash
eval $(minikube docker-env)
IMAGE_TAG=local k8s/scripts/build-images.sh
```

## Install

```bash
export LITELLM_MASTER_KEY="sk-local-master-key"
export LITELLM_SALT_KEY="sk-local-salt-key"
export DB_USERNAME="litellm"
export DB_PASSWORD="litellm-local-password"

NAMESPACE=litellm RELEASE=litellm IMAGE_TAG=local \
  LITELLM_MASTER_KEY="$LITELLM_MASTER_KEY" LITELLM_SALT_KEY="$LITELLM_SALT_KEY" \
  k8s/scripts/local-install.sh
```

This applies local dependencies, LiteLLM (Helm), **APISIX** edge gateway, and **Headlamp** (`INSTALL_APISIX=false` / `INSTALL_HEADLAMP=false` to skip).

## Smoke test

```bash
curl -sS http://api.localhost/v1/models \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY}"

curl -sS http://admin.localhost/key/generate \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"models":["deepseek-chat"],"max_budget":10,"rpm_limit":60,"tpm_limit":100000}'

curl -sS http://api.localhost/v1/chat/completions \
  -H "Authorization: Bearer <virtual-key>" \
  -H "traceparent: 00-11111111111111111111111111111111-2222222222222222-01" \
  -H "Content-Type: application/json" \
  -d '{"model":"deepseek-chat","messages":[{"role":"user","content":"你好"}]}'
```

Jaeger UI: `http://trace.localhost` — search trace id `11111111111111111111111111111111`.

## APISIX edge gateway

Complex host/path routing lives in [../k8s/apisix/routes.yaml.tpl](../k8s/apisix/routes.yaml.tpl). Re-apply after edits:

```bash
k8s/scripts/install-apisix.sh
```

## Kubernetes ops UI (Headlamp)

`local-install.sh` installs [Headlamp](https://headlamp.dev/) in namespace `headlamp` with Ingress `http://k8s.localhost`. Use it to browse Pods, Deployments, Services, Ingress, logs, and events for the local cluster.

Install or refresh Headlamp alone:

```bash
minikube/scripts/install-headlamp.sh
```

The script prints a **login token** for the Headlamp ServiceAccount `headlamp` (cluster-admin, local dev only). In Headlamp, choose **Token** authentication and paste it.

| URL | Purpose |
| --- | --- |
| `http://api.localhost` | LiteLLM LLM API (via APISIX) |
| `http://admin.localhost` | Admin UI and management API (via APISIX) |
| `http://trace.localhost` | Jaeger trace query |
| `http://k8s.localhost` | Headlamp cluster ops UI |

## Clean up

```bash
helm -n litellm uninstall litellm
helm -n headlamp uninstall headlamp
kubectl delete namespace litellm headlamp
```

Data in local dependencies uses ephemeral `emptyDir` volumes; deleting the namespace removes all local state.

## Moving to a real cluster

See [../k8s/README.md](../k8s/README.md#minikube-to-real-k8s-checklist). Use `k8s/scripts/install.sh` with `base.yaml` + edited `production.yaml`; do not run `local-install.sh` or apply local dependency manifests.
