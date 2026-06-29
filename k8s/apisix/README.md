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
| `api.localhost` | `/v1/*`, `/health*`, `/metrics` | gateway :4000 |
| `admin.localhost` | `/ui*`, `/`, `/_next/*`, assets | ui :3000 |
| `admin.localhost` | `/*` (catch-all) | backend :4001 |

Public routes are host-scoped to `API_HOST` so management paths do not fall through on the public host. The public data-plane routes include conservative APISIX plugin defaults for remote-address rate limiting, request body size, and upstream timeouts. Edit `routes.yaml.tpl` for custom plugins, canary splits, or additional hosts, then re-run `install-apisix.sh`.

## Production boundary

For production, use split DNS and restrict the admin host to an internal or operator-only network:

| Variable | Purpose |
| --- | --- |
| `API_HOST` | Public LLM API host, for example `api.example.com` |
| `ADMIN_HOST` | Internal admin/UI host, for example `admin.example.internal` |
| `API_TLS_SECRET` | Kubernetes TLS Secret for `API_HOST` |
| `ADMIN_TLS_SECRET` | Kubernetes TLS Secret for `ADMIN_HOST` |
| `ADMIN_ALLOWED_IPS` | Optional comma-separated CIDR allowlist applied to admin routes with APISIX `ip-restriction` |
| `PUBLIC_RATE_LIMIT_COUNT` / `PUBLIC_RATE_LIMIT_WINDOW_SECONDS` | Public route rate-limit defaults |
| `PUBLIC_MAX_BODY_SIZE_BYTES` | Public route request body limit |
| `UPSTREAM_*_TIMEOUT_SECONDS` | APISIX upstream connect/send/read timeout defaults |

Recommended default: expose `API_HOST` publicly, keep `ADMIN_HOST` on private DNS/VPN, and set `ADMIN_ALLOWED_IPS` to the operator network CIDRs. If a production cluster already enforces admin access with mTLS, OIDC, VPN, or cloud load-balancer policy, document that control in the environment runbook.

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
  API_HOST=api.example.com \
  ADMIN_HOST=admin.example.internal \
  API_TLS_SECRET=tokenhub-api-tls \
  ADMIN_TLS_SECRET=tokenhub-admin-tls \
  ADMIN_ALLOWED_IPS="10.0.0.0/8,192.168.0.0/16" \
  k8s/scripts/install-apisix.sh
```

Render without applying to a cluster:

```bash
DRY_RUN=true \
  API_HOST=api.example.com \
  ADMIN_HOST=admin.example.internal \
  API_TLS_SECRET=tokenhub-api-tls \
  ADMIN_TLS_SECRET=tokenhub-admin-tls \
  ADMIN_ALLOWED_IPS="10.0.0.0/8,192.168.0.0/16" \
  k8s/scripts/install-apisix.sh
```

Helm values for production with APISIX:

```bash
VALUES_FILES="k8s/values/base.yaml k8s/values/production.yaml k8s/values/overlays/apisix.yaml k8s/values/overlays/production-apisix.yaml" \
  k8s/scripts/install.sh
k8s/scripts/install-apisix.sh
```
