#!/bin/bash
set -e

NAMESPACE="observability"
INFRA_NAMESPACE="infrastructure"
CLUSTER_NAME="${CLUSTER_NAME:-your-cluster-name}"
MINIO_ACCESS_KEY="${MINIO_ACCESS_KEY:-admin}"
MINIO_SECRET_KEY="${MINIO_SECRET_KEY:-changeme123}"

echo "=== Observability Stack Installation ==="
echo "Namespace: $NAMESPACE"
echo "Infrastructure Namespace: $INFRA_NAMESPACE"
echo "Cluster: $CLUSTER_NAME"
echo ""
echo "Prerequisites:"
echo "  - Infrastructure stack must be installed first (MinIO, local-storage)"
echo "  - Run: cd infrastructure && ./install.sh"
echo ""

# Check if infrastructure namespace exists
if ! kubectl get namespace $INFRA_NAMESPACE &>/dev/null; then
  echo "ERROR: Infrastructure namespace '$INFRA_NAMESPACE' not found."
  echo "Please install infrastructure stack first: cd infrastructure && ./install.sh"
  exit 1
fi

# Check if MinIO is running
if ! kubectl get svc minio -n $INFRA_NAMESPACE &>/dev/null; then
  echo "ERROR: MinIO service not found in $INFRA_NAMESPACE namespace."
  echo "Please install infrastructure stack first: cd infrastructure && ./install.sh"
  exit 1
fi

# Create namespace
echo "Creating namespace..."
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Add Helm repos
echo "Adding Helm repositories..."
helm repo add vm https://victoriametrics.github.io/helm-charts/
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add grafana-community https://grafana-community.github.io/helm-charts
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update

# Install VictoriaMetrics Operator CRDs first
echo "Installing VictoriaMetrics Operator..."
helm upgrade --install vm-operator vm/victoria-metrics-operator \
  -n $NAMESPACE \
  --wait

echo "Waiting for VM Operator to be ready..."
kubectl wait --for=condition=available deployment/vm-operator-victoria-metrics-operator -n $NAMESPACE --timeout=120s

# Create MinIO credentials secret for Loki and Tempo
echo "Creating MinIO credentials secret..."
kubectl create secret generic minio-credentials \
  -n $NAMESPACE \
  --from-literal=access_key=$MINIO_ACCESS_KEY \
  --from-literal=secret_key=$MINIO_SECRET_KEY \
  --dry-run=client -o yaml | kubectl apply -f -

# Create MinIO buckets for Loki and Tempo using mc (MinIO Client)
echo "Creating MinIO buckets..."
kubectl run minio-mc --rm -i --restart=Never \
  --image=minio/mc:latest \
  -n $INFRA_NAMESPACE \
  --command -- /bin/sh -c "
    mc alias set myminio http://minio:9000 $MINIO_ACCESS_KEY $MINIO_SECRET_KEY && \
    mc mb --ignore-existing myminio/loki-chunks && \
    mc mb --ignore-existing myminio/loki-ruler && \
    mc mb --ignore-existing myminio/tempo-traces && \
    echo 'Buckets created successfully'
  " 2>/dev/null || echo "Buckets may already exist"

# Install VictoriaMetrics
echo "Installing VictoriaMetrics..."
helm upgrade --install vm vm/victoria-metrics-k8s-stack \
  -n $NAMESPACE \
  -f values/vm.yaml \
  --set-string vmagent.spec.externalLabels.cluster=$CLUSTER_NAME

# Install Loki with MinIO configuration
echo "Installing Loki..."
helm upgrade --install loki grafana/loki-distributed \
  -n $NAMESPACE \
  -f values/loki.yaml \
  --set "loki.structuredConfig.storage_config.aws.access_key_id=$MINIO_ACCESS_KEY" \
  --set "loki.structuredConfig.storage_config.aws.secret_access_key=$MINIO_SECRET_KEY"

# Install Promtail
echo "Installing Promtail..."
helm upgrade --install promtail grafana/promtail \
  -n $NAMESPACE \
  -f values/promtail.yaml

# Install Tempo with MinIO configuration
echo "Installing Tempo..."
helm upgrade --install tempo grafana-community/tempo-distributed \
  -n $NAMESPACE \
  -f values/tempo.yaml \
  --set "storage.trace.s3.access_key=$MINIO_ACCESS_KEY" \
  --set "storage.trace.s3.secret_key=$MINIO_SECRET_KEY"

# Install OpenTelemetry Collector (DaemonSet)
echo "Installing OpenTelemetry Collector (DaemonSet)..."
helm upgrade --install otel-daemon open-telemetry/opentelemetry-collector \
  -n $NAMESPACE \
  -f values/otel-daemon.yaml

# Install OpenTelemetry Collector (Gateway)
echo "Installing OpenTelemetry Collector (Gateway)..."
helm upgrade --install otel-gateway open-telemetry/opentelemetry-collector \
  -n $NAMESPACE \
  -f values/otel-gateway.yaml

# Create Grafana dashboard ConfigMap
echo "Creating Grafana dashboard ConfigMap..."
kubectl create configmap grafana-dashboards \
  --from-file=jvm-services.json=dashboards/jvm-services.json \
  --from-file=pod-logs.json=dashboards/pod-logs.json \
  --from-file=deployment-logs.json=dashboards/deployment-logs.json \
  --from-file=traces.json=dashboards/traces.json \
  -n $NAMESPACE \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl label configmap grafana-dashboards grafana_dashboard=1 -n $NAMESPACE --overwrite

# Install Grafana (using community chart)
echo "Installing Grafana..."
helm upgrade --install grafana grafana-community/grafana \
  -n $NAMESPACE \
  -f values/grafana.yaml

echo ""
echo "=== Installation Complete ==="
echo ""
echo "=========================================="
echo "Access Information:"
echo "=========================================="
echo ""
echo "Grafana:"
echo "  kubectl port-forward svc/grafana 3000:80 -n $NAMESPACE"
echo "  URL: http://localhost:3000"
echo "  User: admin"
echo "  Password: admin"
echo ""
echo "VictoriaMetrics (Prometheus API):"
echo "  kubectl port-forward svc/vmselect-vm-victoria-metrics-k8s-stack 8481:8481 -n $NAMESPACE"
echo "  URL: http://localhost:8481/select/0/prometheus"
echo ""
echo "Loki:"
echo "  kubectl port-forward svc/loki-loki-distributed-gateway 3100:80 -n $NAMESPACE"
echo "  URL: http://localhost:3100"
echo ""
echo "Tempo:"
echo "  kubectl port-forward svc/tempo-query-frontend 3100:3100 -n $NAMESPACE"
echo "  URL: http://localhost:3100"
echo ""
echo "=========================================="
echo "Application Integration:"
echo "=========================================="
echo ""
echo "OTEL Collector endpoint (for your applications):"
echo "  OTLP gRPC: otel-gateway-opentelemetry-collector.$NAMESPACE.svc.cluster.local:4317"
echo "  OTLP HTTP: otel-gateway-opentelemetry-collector.$NAMESPACE.svc.cluster.local:4318"
echo ""
echo "Example environment variables for Java apps:"
echo "  OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-gateway-opentelemetry-collector.$NAMESPACE.svc.cluster.local:4317"
echo "  OTEL_SERVICE_NAME=my-service"
echo ""
echo "Deploy sample services:"
echo "  kubectl apply -f services/"
