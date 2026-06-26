# tokenhub-deploy Agent 指引

本仓库负责 TokenHub 部署与运维配置，包括 V1 本地平台栈、APISIX 配置、私有化 Compose、Kubernetes/Helm 和运行手册。

## 开发阶段

TokenHub 目前处于**内部开发期**。开发期间不需要考虑向前兼容，可优先采用最直接的设计与实现，不必为旧接口、旧数据格式或过渡方案保留额外兼容层。

## 开工前

1. 先确认变更是否有已批准需求包，例如 `product/tokenhub-product/docs/roadmaps/v1/requirements/REQ-V1-xxx-*`。
2. 阅读需求包的 `README.md` 和 `acceptance.md`。
3. 确认目标部署路径：`platform/`、`private/`、`cluster/` 或 `apisix/`。

## 工作边界

- V1 本地集成栈放在 `platform/`。
- APISIX standalone 配置放在 `apisix/`。
- 私有化部署放在 `private/`。
- K8s / Helm 相关部署放在 `cluster/`。
- Proxy 源码不在本仓修改，回到 `dev/tokenhub-proxy`。
- fake provider 源码不在本仓修改，回到 `dev/tokenhub-e2e`。

## 验证

部署变更应尽量执行最靠近变更点的校验。例如：

```bash
docker compose -f platform/docker-compose.yml config
docker compose -f platform/docker-compose.yml up --build
```

如果当前环境无法启动 Docker 或 Kubernetes，必须在需求包 `output/verified.md` 中记录 `NOT RUN` 原因、风险和下一步。

## Output 回写

部署变更完成后，将实际变更摘要写入对应需求包的 `output/changes.md`，将验证结果写入 `output/verified.md`。
