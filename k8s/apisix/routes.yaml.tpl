# APISIX standalone routes — rendered by install-apisix.sh; must end with #END.
routes:
  - id: public-v1-api
    name: public-v1-api
    uri: /v1/*
    upstream:
      type: roundrobin
      nodes:
        "${GATEWAY_UPSTREAM}": 1

  - id: public-health
    name: public-health
    uri: /health*
    upstream:
      type: roundrobin
      nodes:
        "${GATEWAY_UPSTREAM}": 1

  - id: public-metrics
    name: public-metrics
    uri: /metrics
    upstream:
      type: roundrobin
      nodes:
        "${GATEWAY_UPSTREAM}": 1

  - id: admin-ui
    name: admin-ui
    hosts:
      - ${ADMIN_HOST}
    uri: /ui*
    priority: 100
    upstream:
      type: roundrobin
      nodes:
        "${UI_UPSTREAM}": 1

  - id: admin-ui-root
    name: admin-ui-root
    hosts:
      - ${ADMIN_HOST}
    uri: /
    priority: 100
    upstream:
      type: roundrobin
      nodes:
        "${UI_UPSTREAM}": 1

  - id: admin-ui-next-assets
    name: admin-ui-next-assets
    hosts:
      - ${ADMIN_HOST}
    uri: /_next/*
    priority: 100
    upstream:
      type: roundrobin
      nodes:
        "${UI_UPSTREAM}": 1

  - id: admin-ui-litellm-assets
    name: admin-ui-litellm-assets
    hosts:
      - ${ADMIN_HOST}
    uri: /litellm-asset-prefix/*
    priority: 100
    upstream:
      type: roundrobin
      nodes:
        "${UI_UPSTREAM}": 1

  - id: admin-ui-static-assets
    name: admin-ui-static-assets
    hosts:
      - ${ADMIN_HOST}
    uri: /assets/*
    priority: 100
    upstream:
      type: roundrobin
      nodes:
        "${UI_UPSTREAM}": 1

  - id: admin-ui-favicon
    name: admin-ui-favicon
    hosts:
      - ${ADMIN_HOST}
    uri: /favicon.ico
    priority: 100
    upstream:
      type: roundrobin
      nodes:
        "${UI_UPSTREAM}": 1

  - id: admin-backend
    name: admin-backend
    hosts:
      - ${ADMIN_HOST}
    uri: /*
    priority: 10
    upstream:
      type: roundrobin
      nodes:
        "${BACKEND_UPSTREAM}": 1
#END
