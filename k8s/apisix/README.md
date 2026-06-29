# APISIX edge gateway (standalone, file-driven)

APISIX runs as an in-cluster edge router in front of LiteLLM gateway, backend, and UI. Use it when you need host-based splits, URI plugins, or other APISIX routing features beyond Kubernetes Ingress path rules.

## Layout

| File | Purpose |
| --- | --- |
| [config.yaml](config.yaml) | APISIX standalone data plane config (no etcd) |
| [routes.yaml.tpl](routes.yaml.tpl) | Route template; upstreams rendered by [../scripts/install-apisix.sh](../scripts/install-apisix.sh) |

## Traffic flow

```text
Client
  -> Kubernetes Ingress (api.localhost / admin.localhost)
  -> APISIX :9080
  -> LiteLLM gateway | backend | ui Services
```

When APISIX is enabled, LiteLLM chart Ingress is disabled via [../values/overlays/apisix.yaml](../values/overlays/apisix.yaml). Jaeger and other admin/ops UIs keep their own Ingress rules.

## Default routes (minikube)

| Host | Path | Upstream |
| --- | --- | --- |
| any | `/v1/*`, `/health*`, `/metrics` | gateway :4000 |
| `admin.localhost` | `/ui*`, `/`, `/_next/*`, assets | ui :3000 |
| `admin.localhost` | `/*` (catch-all) | backend :4001 |

Edit `routes.yaml.tpl` for custom plugins, canary splits, or additional hosts, then re-run `install-apisix.sh`.

## Install

After LiteLLM is running in the same namespace:

```bash
NAMESPACE=litellm RELEASE=litellm \
  API_HOST=api.localhost ADMIN_HOST=admin.localhost \
  k8s/scripts/install-apisix.sh
```

Production example:

```bash
NAMESPACE=litellm RELEASE=litellm \
  API_HOST=litellm.example.internal \
  ADMIN_HOST=admin.example.internal \
  k8s/scripts/install-apisix.sh
```

Helm values for production with APISIX:

```bash
VALUES_FILES="k8s/values/base.yaml k8s/values/production.yaml k8s/values/overlays/apisix.yaml k8s/values/overlays/production-apisix.yaml" \
  k8s/scripts/install.sh
k8s/scripts/install-apisix.sh
```
