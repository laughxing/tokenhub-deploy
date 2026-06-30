# APISIX standalone routes — rendered by install-apisix.sh; must end with #END.
routes:
  - id: public-v1-api
    name: public-v1-api
    hosts:
      - ${API_HOST}
    uri: /v1/*
    plugins:
      limit-count:
        count: ${PUBLIC_RATE_LIMIT_COUNT}
        time_window: ${PUBLIC_RATE_LIMIT_WINDOW_SECONDS}
        key: remote_addr
        rejected_code: 429
      client-control:
        max_body_size: ${PUBLIC_MAX_BODY_SIZE_BYTES}
    upstream:
      type: roundrobin
      timeout:
        connect: ${UPSTREAM_CONNECT_TIMEOUT_SECONDS}
        send: ${UPSTREAM_SEND_TIMEOUT_SECONDS}
        read: ${UPSTREAM_READ_TIMEOUT_SECONDS}
      nodes:
        "${GATEWAY_UPSTREAM}": 1

  - id: public-health
    name: public-health
    hosts:
      - ${API_HOST}
    uri: /health*
    plugins:
      limit-count:
        count: ${PUBLIC_RATE_LIMIT_COUNT}
        time_window: ${PUBLIC_RATE_LIMIT_WINDOW_SECONDS}
        key: remote_addr
        rejected_code: 429
    upstream:
      type: roundrobin
      timeout:
        connect: ${UPSTREAM_CONNECT_TIMEOUT_SECONDS}
        send: ${UPSTREAM_SEND_TIMEOUT_SECONDS}
        read: ${UPSTREAM_READ_TIMEOUT_SECONDS}
      nodes:
        "${GATEWAY_UPSTREAM}": 1

  - id: public-metrics
    name: public-metrics
    hosts:
      - ${API_HOST}
    uri: /metrics
    plugins:
      limit-count:
        count: ${PUBLIC_RATE_LIMIT_COUNT}
        time_window: ${PUBLIC_RATE_LIMIT_WINDOW_SECONDS}
        key: remote_addr
        rejected_code: 429
    upstream:
      type: roundrobin
      timeout:
        connect: ${UPSTREAM_CONNECT_TIMEOUT_SECONDS}
        send: ${UPSTREAM_SEND_TIMEOUT_SECONDS}
        read: ${UPSTREAM_READ_TIMEOUT_SECONDS}
      nodes:
        "${GATEWAY_UPSTREAM}": 1

  - id: admin-ui
    name: admin-ui
    hosts:
      - ${ADMIN_HOST}
    uri: /ui*
    priority: 100
${ADMIN_ACCESS_PLUGINS}
    upstream:
      type: roundrobin
      timeout:
        connect: ${UPSTREAM_CONNECT_TIMEOUT_SECONDS}
        send: ${UPSTREAM_SEND_TIMEOUT_SECONDS}
        read: ${UPSTREAM_READ_TIMEOUT_SECONDS}
      nodes:
        "${UI_UPSTREAM}": 1

  - id: admin-ui-root
    name: admin-ui-root
    hosts:
      - ${ADMIN_HOST}
    uri: /
    priority: 100
${ADMIN_ACCESS_PLUGINS}
    upstream:
      type: roundrobin
      timeout:
        connect: ${UPSTREAM_CONNECT_TIMEOUT_SECONDS}
        send: ${UPSTREAM_SEND_TIMEOUT_SECONDS}
        read: ${UPSTREAM_READ_TIMEOUT_SECONDS}
      nodes:
        "${UI_UPSTREAM}": 1

  - id: admin-ui-next-assets
    name: admin-ui-next-assets
    hosts:
      - ${ADMIN_HOST}
    uri: /_next/*
    priority: 100
${ADMIN_ACCESS_PLUGINS}
    upstream:
      type: roundrobin
      timeout:
        connect: ${UPSTREAM_CONNECT_TIMEOUT_SECONDS}
        send: ${UPSTREAM_SEND_TIMEOUT_SECONDS}
        read: ${UPSTREAM_READ_TIMEOUT_SECONDS}
      nodes:
        "${UI_UPSTREAM}": 1

  - id: admin-ui-litellm-assets
    name: admin-ui-litellm-assets
    hosts:
      - ${ADMIN_HOST}
    uri: /litellm-asset-prefix/*
    priority: 100
${ADMIN_ACCESS_PLUGINS}
    upstream:
      type: roundrobin
      timeout:
        connect: ${UPSTREAM_CONNECT_TIMEOUT_SECONDS}
        send: ${UPSTREAM_SEND_TIMEOUT_SECONDS}
        read: ${UPSTREAM_READ_TIMEOUT_SECONDS}
      nodes:
        "${UI_UPSTREAM}": 1

  - id: admin-ui-static-assets
    name: admin-ui-static-assets
    hosts:
      - ${ADMIN_HOST}
    uri: /assets/*
    priority: 100
${ADMIN_ACCESS_PLUGINS}
    upstream:
      type: roundrobin
      timeout:
        connect: ${UPSTREAM_CONNECT_TIMEOUT_SECONDS}
        send: ${UPSTREAM_SEND_TIMEOUT_SECONDS}
        read: ${UPSTREAM_READ_TIMEOUT_SECONDS}
      nodes:
        "${UI_UPSTREAM}": 1

  - id: admin-ui-favicon
    name: admin-ui-favicon
    hosts:
      - ${ADMIN_HOST}
    uri: /favicon.ico
    priority: 100
${ADMIN_ACCESS_PLUGINS}
    upstream:
      type: roundrobin
      timeout:
        connect: ${UPSTREAM_CONNECT_TIMEOUT_SECONDS}
        send: ${UPSTREAM_SEND_TIMEOUT_SECONDS}
        read: ${UPSTREAM_READ_TIMEOUT_SECONDS}
      nodes:
        "${UI_UPSTREAM}": 1

  - id: admin-backend
    name: admin-backend
    hosts:
      - ${ADMIN_HOST}
    uri: /*
    priority: 10
${ADMIN_ACCESS_PLUGINS}
    upstream:
      type: roundrobin
      timeout:
        connect: ${UPSTREAM_CONNECT_TIMEOUT_SECONDS}
        send: ${UPSTREAM_SEND_TIMEOUT_SECONDS}
        read: ${UPSTREAM_READ_TIMEOUT_SECONDS}
      nodes:
        "${BACKEND_UPSTREAM}": 1

  - id: web-app
    name: web-app
    hosts:
      - ${WEB_HOST}
    uri: /*
    priority: 10
    upstream:
      type: roundrobin
      timeout:
        connect: ${UPSTREAM_CONNECT_TIMEOUT_SECONDS}
        send: ${UPSTREAM_SEND_TIMEOUT_SECONDS}
        read: ${UPSTREAM_READ_TIMEOUT_SECONDS}
      nodes:
        "${WEB_UPSTREAM}": 1
#END
