# tokenhub-deploy

TokenHub Kubernetes 部署与运维配置。

镜像从 `TOKENHUB_PROXY_ROOT` 指向的 `tokenhub-proxy` 源码构建；集成测试用的 fake provider 来自 `TOKENHUB_E2E_ROOT` 指向的 `tokenhub-e2e`。在 `tokenhub-all` 大仓布局下，这两个路径会自动解析到 `dev/tokenhub-proxy` 和 `dev/tokenhub-e2e`。

## 目录结构

```text
k8s/              # Kubernetes / Helm 部署（通用 + production + local overlay）
minikube/         # minikube 本地环启动说明
scripts/common/   # 安装脚本公共逻辑
```

Helm Chart 位于 `TOKENHUB_PROXY_ROOT/helm/litellm`。

## 环境变量

| 变量 | 说明 | 默认值（大仓布局） |
| --- | --- | --- |
| `TOKENHUB_PROXY_ROOT` | tokenhub-proxy 源码路径 | 未设置时按大仓布局自动解析 |
| `TOKENHUB_E2E_ROOT` | tokenhub-e2e 源码路径 | 未设置时按大仓布局自动解析 |

## 快速开始（minikube 本地环）

```bash
export LITELLM_MASTER_KEY="sk-local-master-key"
export LITELLM_SALT_KEY="sk-local-salt-key"
export DB_USERNAME="litellm"
export DB_PASSWORD="litellm-local-password"

minikube start --driver=docker
minikube addons enable ingress

cd deploy/tokenhub-deploy
LOAD_INTO_MINIKUBE=true IMAGE_TAG=local k8s/scripts/build-images.sh

NAMESPACE=litellm RELEASE=litellm IMAGE_TAG=local \
  LITELLM_MASTER_KEY="$LITELLM_MASTER_KEY" LITELLM_SALT_KEY="$LITELLM_SALT_KEY" \
  k8s/scripts/local-install.sh
```

- LLM API：`http://api.localhost/v1`（经 APISIX）
- Admin UI：`http://admin.localhost/ui`（经 APISIX）
- Jaeger UI：`http://trace.localhost`
- Headlamp：`http://k8s.localhost`

详细说明见 [k8s/README.md](k8s/README.md) 与 [minikube/README.md](minikube/README.md)。

## 真实 Kubernetes 集群

使用 `k8s/scripts/install.sh`，合并 `k8s/values/base.yaml` 与编辑后的 `k8s/values/production.yaml`，不 apply 本地依赖 manifest。见 [k8s/README.md](k8s/README.md#production--real-kubernetes)。
