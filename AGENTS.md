# tokenhub-deploy Agent 指引

本仓库负责 TokenHub Kubernetes 部署与运维配置。

## 开发阶段

TokenHub 目前处于**内部开发期**。开发期间不需要考虑向前兼容，可优先采用最直接的设计与实现，不必为旧接口、旧数据格式或过渡方案保留额外兼容层。

## 开工前

1. 先确认变更是否有已批准需求包，例如 `product/tokenhub-product/docs/roadmaps/v1/requirements/REQ-V1-xxx-*`。
2. 阅读需求包的 `README.md` 和 `acceptance.md`。
3. 确认目标路径：`k8s/`、`minikube/` 或 `scripts/common/`。

## 工作边界

- Kubernetes / Helm 部署放在 `k8s/`。
- minikube 本地环说明放在 `minikube/`。
- Proxy 源码不在本仓修改，回到 `dev/tokenhub-proxy`。
- fake provider 源码不在本仓修改，回到 `dev/tokenhub-e2e`。

## 验证

部署变更应尽量执行最靠近变更点的校验。例如：

```bash
bash -n k8s/scripts/install.sh
helm template litellm "$TOKENHUB_PROXY_ROOT/helm/litellm" \
  -f k8s/values/base.yaml -f k8s/values/production.yaml
```

本地 minikube 回归：

```bash
k8s/scripts/local-install.sh
```

如果当前环境无法启动 Kubernetes，必须在需求包 `output/acceptance-results.md` 中记录 `NOT RUN` 原因、风险和下一步。

## Output 回写

部署变更完成后，将实际变更摘要写入对应需求包的 `output/changes.md`，将验证结果写入 `output/acceptance-results.md`。
