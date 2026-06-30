# tokenhub-web Deployment/Service/ConfigMap (REQ-V2-006).
# Rendered by install-web.sh via envsubst. Gin serves the SPA and /api/console/*.
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${WEB_NAME}-config
  namespace: ${WEB_NAMESPACE}
  labels:
    app.kubernetes.io/name: ${WEB_NAME}
data:
  TOKENHUB_WEB_ENV: "${WEB_ENV}"
  TOKENHUB_WEB_LISTEN_ADDR: ":${WEB_PORT}"
  TOKENHUB_WEB_ORIGIN: "${WEB_ORIGIN}"
  TOKENHUB_WEB_PUBLIC_API_BASE_URL: "${WEB_PUBLIC_API_BASE_URL}"
  TOKENHUB_WEB_LITELLM_ADMIN_BASE_URL: "${WEB_LITELLM_ADMIN_BASE_URL}"
  TOKENHUB_WEB_LITELLM_MODE: "${WEB_LITELLM_MODE}"
  TOKENHUB_WEB_MVP_MODELS: "${WEB_MVP_MODELS}"
  TOKENHUB_WEB_INITIAL_MAX_BUDGET: "${WEB_INITIAL_MAX_BUDGET}"
  TOKENHUB_WEB_OTP_DEV_SINK: "${WEB_OTP_DEV_SINK}"
  TOKENHUB_WEB_EMAIL_PROVIDER: "${WEB_EMAIL_PROVIDER}"
  TOKENHUB_WEB_COOKIE_SECURE: "${WEB_COOKIE_SECURE}"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${WEB_NAME}
  namespace: ${WEB_NAMESPACE}
  labels:
    app.kubernetes.io/name: ${WEB_NAME}
spec:
  replicas: ${WEB_REPLICAS}
  selector:
    matchLabels:
      app.kubernetes.io/name: ${WEB_NAME}
  template:
    metadata:
      annotations:
        checksum/config: "${WEB_CONFIG_CHECKSUM}"
      labels:
        app.kubernetes.io/name: ${WEB_NAME}
    spec:
      containers:
        - name: tokenhub-web
          image: ${WEB_IMAGE}
          imagePullPolicy: ${WEB_IMAGE_PULL_POLICY}
          ports:
            - containerPort: ${WEB_PORT}
              name: http
          envFrom:
            - configMapRef:
                name: ${WEB_NAME}-config
          env:
            - name: TOKENHUB_WEB_LITELLM_MASTER_KEY
              valueFrom:
                secretKeyRef:
                  name: ${WEB_MASTER_KEY_SECRET}
                  key: ${WEB_MASTER_KEY_SECRET_KEY}
            - name: TOKENHUB_WEB_SESSION_SECRET
              valueFrom:
                secretKeyRef:
                  name: ${WEB_SECRET}
                  key: session-secret
            - name: TOKENHUB_WEB_ADMIN_API_TOKEN
              valueFrom:
                secretKeyRef:
                  name: ${WEB_SECRET}
                  key: admin-token
          readinessProbe:
            httpGet:
              path: /healthz
              port: http
            initialDelaySeconds: 5
            periodSeconds: 5
          livenessProbe:
            httpGet:
              path: /healthz
              port: http
            initialDelaySeconds: 10
            periodSeconds: 10
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 500m
              memory: 256Mi
---
apiVersion: v1
kind: Service
metadata:
  name: ${WEB_NAME}
  namespace: ${WEB_NAMESPACE}
  labels:
    app.kubernetes.io/name: ${WEB_NAME}
spec:
  selector:
    app.kubernetes.io/name: ${WEB_NAME}
  ports:
    - name: http
      port: ${WEB_PORT}
      targetPort: http
