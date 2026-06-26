# tokenhub-deploy

TokenHub 部署与运维配置：商用私有化/集群部署、APISIX 边缘配置、V1 平台本地编排。

镜像从 `TOKENHUB_PROXY_ROOT` 指向的 `tokenhub-proxy` 源码构建；集成测试用的 fake provider 来自 `TOKENHUB_E2E_ROOT` 指向的 `tokenhub-e2e`。在 `tokenhub-all` 大仓布局下，这两个路径会自动解析到 `dev/tokenhub-proxy` 和 `dev/tokenhub-e2e`。

## 目录结构

```text
cluster/          # Kubernetes / minikube 高可用部署
private/          # 单站点私有化 Compose 部署
platform/         # V1 平台本地编排（APISIX + LiteLLM 组件 + fake provider）
apisix/           # APISIX standalone 配置
scripts/common/   # 安装脚本公共逻辑
```

## 部署路径

| 路径 | 用途 | 主要文件 |
| --- | --- | --- |
| [private](private/README.md) | 单站点私有化/on-prem | `private/docker-compose.prod.yml`, `private/install.sh` |
| [cluster](cluster/README.md) | K8s 高可用 | `cluster/build-images.sh`, `cluster/install.sh`, `cluster/values-ha-example.yaml` |
| [platform](platform/docker-compose.yml) | V1 本地集成栈 | `platform/docker-compose.yml`, `platform/litellm_config.example.yaml` |

Helm Chart 位于 `TOKENHUB_PROXY_ROOT/helm/litellm`（由 cluster 脚本引用）。

## 环境变量

| 变量 | 说明 | 默认值（大仓布局） |
| --- | --- | --- |
| `TOKENHUB_PROXY_ROOT` | tokenhub-proxy 源码路径 | 未设置时按大仓布局自动解析 |
| `TOKENHUB_E2E_ROOT` | tokenhub-e2e 源码路径 | 未设置时按大仓布局自动解析 |

手动覆盖路径时建议使用绝对路径，避免脚本和 Compose 的相对路径基准不同。

## 快速开始

V1 平台本地栈（需已 clone 大仓内各子仓库）：

```bash
export LITELLM_MASTER_KEY="sk-local-master-key"
cd platform
docker compose -f docker-compose.yml up --build
```

公开 API：`http://localhost:9080/v1`

商用私有化部署见 [private/README.md](private/README.md)；集群部署见 [cluster/README.md](cluster/README.md)。
