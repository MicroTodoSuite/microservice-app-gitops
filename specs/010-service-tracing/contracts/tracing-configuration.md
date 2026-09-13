# Contract: Tracing Configuration and Egress

## Service configuration

Every service's base ConfigMap (`apps/<service>/base/configmap.yaml`) MUST
contain:

```yaml
OTEL_EXPORTER_OTLP_ENDPOINT: "http://jaeger-collector.observability.svc:4317"
OTEL_SERVICE_NAME: "<service>"   # frontend, auth-api, todos-api, users-api, log-message-processor
```

- Every rendered economical overlay (`dev`, `staging`, `prod`, `demo`) delivers
  both values to the service container, through the Deployment's existing
  `envFrom`.
- No overlay overrides `OTEL_EXPORTER_OTLP_ENDPOINT` with a different value.
- No rendered application or environment contains `ZIPKIN_URL` or any other
  Zipkin setting.
- A service started without `OTEL_EXPORTER_OTLP_ENDPOINT` runs normally with
  export disabled.

How each service reads the values:

| Service | Endpoint | Service name |
| --- | --- | --- |
| `auth-api` | OpenTelemetry Go SDK reads the variable | Resource attribute set in code, equal to `auth-api` |
| `todos-api` | OpenTelemetry JS exporter reads the variable | `OTEL_SERVICE_NAME` |
| `users-api` | `management.otlp.tracing.endpoint`, set from the variable only when it has a value, with `management.otlp.tracing.transport=grpc` | `spring.application.name` (`users-api`) |
| `log-message-processor` | OpenTelemetry Python exporter reads the variable | `OTEL_SERVICE_NAME` |
| `frontend` | `entrypoint.sh` substitutes it into `otel_exporter` | `otel_service_name frontend` |

## Egress

`environments/base/networkpolicy-allow-tracing-egress.yaml`, rendered into
every economical environment namespace:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-tracing-egress
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/component: business-service
  policyTypes: ["Egress"]
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: observability
          podSelector:
            matchLabels:
              app.kubernetes.io/name: jaeger
      ports:
        - protocol: TCP
          port: 4317
```

- Exactly one egress rule, one peer (namespace and pod selector in the same
  peer, which requires both), and one port.
- No change to Jaeger's own NetworkPolicy, which already admits 4317.

## Validation

`tests/contract/service-tracing.sh` fails when any statement above does not
hold in the rendered desired state, and runs in `validate-gitops`.
