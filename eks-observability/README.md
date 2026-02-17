# EKS Observability Stack

Full observability stack for Kubernetes clusters: metrics, logs, and traces.

## Components

| Component | Purpose |
|-----------|---------|
| VictoriaMetrics (operator + cluster) | Metrics storage and querying (Prometheus-compatible) |
| Loki (distributed) | Log aggregation |
| Promtail | Log collection from nodes |
| Tempo (distributed) | Distributed trace storage |
| OpenTelemetry Collector (DaemonSet) | Node-level metrics collection |
| OpenTelemetry Collector (Gateway) | Application trace/metric ingestion |
| Grafana | Visualization and dashboards |

## Architecture

All components are deployed in the `observability` namespace.

### Data Flow

#### Metrics

```
Pods (metrics endpoints)
  |
  v
vmagent (scrapes targets every 30s)
  |
  v
vminsert (write path)
  |
  v
vmstorage (persistent storage, 30d retention)
  ^
  |
vmselect (read path) <-- Grafana queries here
```

Applications can also push metrics via OTLP:

```
App --> OTel Gateway --> prometheusremotewrite --> vminsert --> vmstorage
```

#### Logs

```
Pod stdout/stderr
  |
  v
Promtail (DaemonSet, reads container logs from each node)
  |
  v
Loki gateway (nginx reverse proxy)
  |
  v
Loki distributor (routes to ingester)
  |
  v
Loki ingester (batches and flushes to S3)
  |
  v
S3 (chunks + TSDB index)
  ^
  |
Loki querier <-- Loki query-frontend <-- Grafana
```

#### Traces

```
Application (instrumented with OTEL SDK)
  |
  v  (OTLP gRPC/HTTP)
OTel Gateway (batches, adds cluster label)
  |
  v  (OTLP gRPC)
Tempo distributor (hashes trace ID, routes to ingester)
  |
  v
Tempo ingester (writes blocks)
  |
  v
S3 (trace blocks)
  ^
  |
Tempo querier <-- Tempo query-frontend <-- Grafana
```

## Installation

```bash
# Set your cluster name (optional, defaults to "production")
export CLUSTER_NAME=my-cluster

# Install everything
./install.sh
```

The install script deploys components in dependency order:
1. VM operator (CRDs)
2. VM stack (vmagent, vminsert, vmstorage, vmselect)
3. Loki
4. Promtail
5. Tempo
6. OTel DaemonSet
7. OTel Gateway
8. Grafana dashboards (ConfigMap)
9. Grafana

## Uninstallation

```bash
./uninstall.sh
```

Removes all Helm releases in reverse order and deletes the namespace.

## Port-Forward Commands

Access services locally for debugging:

```bash
# Grafana (dashboards)
kubectl port-forward svc/grafana 3000:80 -n observability

# VictoriaMetrics (Prometheus-compatible query API)
kubectl port-forward svc/vmselect-vm-victoria-metrics-k8s-stack 8481:8481 -n observability
# Query: http://localhost:8481/select/0/prometheus

# Loki (log query API)
kubectl port-forward svc/loki-loki-distributed-gateway 3100:80 -n observability

# Tempo (trace query API)
kubectl port-forward svc/tempo-query-frontend 3200:3200 -n observability
```

## Debugging

Check pod status:

```bash
kubectl get pods -n observability
```

Check logs for a specific component:

```bash
kubectl logs -l app.kubernetes.io/name=victoria-metrics-operator -n observability
kubectl logs -l app.kubernetes.io/name=loki -l app.kubernetes.io/component=ingester -n observability
kubectl logs -l app.kubernetes.io/name=tempo -l app.kubernetes.io/component=distributor -n observability
kubectl logs -l app.kubernetes.io/name=opentelemetry-collector -n observability
kubectl logs -l app.kubernetes.io/name=grafana -n observability
```

Verify Helm releases:

```bash
helm list -n observability
```

Check VictoriaMetrics targets being scraped:

```bash
kubectl port-forward svc/vmagent-vm-victoria-metrics-k8s-stack 8429:8429 -n observability
# Open http://localhost:8429/targets
```

## Application Integration

To send traces and metrics from your applications to this stack, configure the OpenTelemetry SDK with these environment variables:

```bash
OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-gateway-opentelemetry-collector.observability.svc.cluster.local:4317
OTEL_SERVICE_NAME=my-service
OTEL_RESOURCE_ATTRIBUTES=service.namespace=my-namespace
```

For Kubernetes deployments, add to your container spec:

```yaml
env:
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: "http://otel-gateway-opentelemetry-collector.observability.svc.cluster.local:4317"
  - name: OTEL_SERVICE_NAME
    value: "my-service"
  - name: OTEL_RESOURCE_ATTRIBUTES
    value: "service.namespace=my-namespace"
```

The OTel Gateway accepts both gRPC (port 4317) and HTTP (port 4318) OTLP protocols. It forwards:
- Traces to Tempo
- Metrics to VictoriaMetrics (via Prometheus remote write)

## Dashboards

Pre-configured dashboards are loaded automatically via ConfigMap sidecar:

| Dashboard | Description |
|-----------|-------------|
| JVM Services | HTTP request rates, latency, error rates, JVM heap, threads, GC |
| Pod Logs | Log volume and live log viewer per pod |
| Deployment Logs | Log volume and viewer grouped by deployment |
| Traces | Trace search, span rates, ingester stats, trace detail viewer |

## File Structure

```
eks-observability/
  install.sh              # Install script
  uninstall.sh            # Teardown script
  values/
    vm.yaml               # VictoriaMetrics cluster config
    loki.yaml             # Loki distributed config
    tempo.yaml            # Tempo distributed config
    promtail.yaml         # Promtail config
    otel-daemon.yaml      # OTel Collector DaemonSet config
    otel-gateway.yaml     # OTel Collector Gateway config
    grafana.yaml          # Grafana config (datasources, sidecar)
  dashboards/
    jvm-services.json     # JVM/Spring Boot metrics dashboard
    pod-logs.json         # Pod-level log dashboard
    deployment-logs.json  # Deployment-level log dashboard
    traces.json           # Tempo traces dashboard
```
