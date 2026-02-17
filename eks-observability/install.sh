#!/bin/bash
set -e

NAMESPACE="observability"
CLUSTER_NAME="${CLUSTER_NAME:-production}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Observability Stack Installation ==="
echo "Namespace: $NAMESPACE"
echo "Cluster:   $CLUSTER_NAME"
echo ""

# --- Helper ---
wait_for_deployment() {
  local name=$1
  echo "Waiting for $name to be ready..."
  kubectl wait --for=condition=available deployment/"$name" -n "$NAMESPACE" --timeout=120s
}

# --- Namespace ---
create_namespace() {
  echo "Creating namespace..."
  kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
}

# --- Helm Repos ---
add_helm_repos() {
  echo "Adding Helm repositories..."
  helm repo add vm https://victoriametrics.github.io/helm-charts/
  helm repo add grafana https://grafana.github.io/helm-charts
  helm repo add grafana-community https://grafana-community.github.io/helm-charts
  helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
  helm repo update
}

# --- VictoriaMetrics ---
install_vm_operator() {
  echo "Installing VictoriaMetrics Operator..."
  helm upgrade --install vm-operator vm/victoria-metrics-operator \
    -n "$NAMESPACE" \
    --wait
  wait_for_deployment vm-operator-victoria-metrics-operator

  echo "Waiting for VM Operator webhook to become ready..."
  local retries=30
  for i in $(seq 1 $retries); do
    if kubectl get endpoints vm-operator-victoria-metrics-operator -n "$NAMESPACE" -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null | grep -q .; then
      echo "Webhook endpoint is ready."
      break
    fi
    if [ "$i" -eq "$retries" ]; then
      echo "ERROR: VM Operator webhook did not become ready in time."
      exit 1
    fi
    echo "  Attempt $i/$retries - webhook not ready yet, waiting 5s..."
    sleep 5
  done
  # Extra grace period for the webhook server to start accepting connections
  sleep 5
}

install_vm_stack() {
  echo "Installing VictoriaMetrics stack..."
  helm upgrade --install vm vm/victoria-metrics-k8s-stack \
    -n "$NAMESPACE" \
    -f "$SCRIPT_DIR/values/vm.yaml" \
    --set-string "vmagent.spec.externalLabels.cluster=$CLUSTER_NAME"
}

# --- Loki ---
install_loki() {
  echo "Installing Loki..."
  helm upgrade --install loki grafana/loki-distributed \
    -n "$NAMESPACE" \
    -f "$SCRIPT_DIR/values/loki.yaml"
}

# --- Promtail ---
install_promtail() {
  echo "Installing Promtail..."
  helm upgrade --install promtail grafana/promtail \
    -n "$NAMESPACE" \
    -f "$SCRIPT_DIR/values/promtail.yaml"
}

# --- Tempo ---
install_tempo() {
  echo "Installing Tempo..."
  helm upgrade --install tempo grafana-community/tempo-distributed \
    -n "$NAMESPACE" \
    -f "$SCRIPT_DIR/values/tempo.yaml"
}

# --- OpenTelemetry Collectors ---
install_otel_daemon() {
  echo "Installing OpenTelemetry Collector (DaemonSet)..."
  helm upgrade --install otel-daemon open-telemetry/opentelemetry-collector \
    -n "$NAMESPACE" \
    -f "$SCRIPT_DIR/values/otel-daemon.yaml"
}

install_otel_gateway() {
  echo "Installing OpenTelemetry Collector (Gateway)..."
  helm upgrade --install otel-gateway open-telemetry/opentelemetry-collector \
    -n "$NAMESPACE" \
    -f "$SCRIPT_DIR/values/otel-gateway.yaml"
}

# --- Grafana ---
install_grafana_dashboards() {
  echo "Creating Grafana dashboard ConfigMap..."
  kubectl create configmap grafana-dashboards \
    --from-file=jvm-services.json="$SCRIPT_DIR/dashboards/jvm-services.json" \
    --from-file=pod-logs.json="$SCRIPT_DIR/dashboards/pod-logs.json" \
    --from-file=deployment-logs.json="$SCRIPT_DIR/dashboards/deployment-logs.json" \
    --from-file=traces.json="$SCRIPT_DIR/dashboards/traces.json" \
    -n "$NAMESPACE" \
    --dry-run=client -o yaml | kubectl apply -f -
  kubectl label configmap grafana-dashboards grafana_dashboard=1 -n "$NAMESPACE" --overwrite
}

install_grafana() {
  echo "Installing Grafana..."
  helm upgrade --install grafana grafana-community/grafana \
    -n "$NAMESPACE" \
    -f "$SCRIPT_DIR/values/grafana.yaml"
}

# --- Main ---
create_namespace
add_helm_repos
install_vm_operator
install_vm_stack
install_loki
install_promtail
install_tempo
install_otel_daemon
install_otel_gateway
install_grafana_dashboards
install_grafana

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
echo "  kubectl port-forward svc/tempo-query-frontend 3200:3200 -n $NAMESPACE"
echo "  URL: http://localhost:3200"
echo ""
echo "=========================================="
echo "Application Integration:"
echo "=========================================="
echo ""
echo "OTEL Collector endpoint (for your applications):"
echo "  OTLP gRPC: otel-gateway-opentelemetry-collector.$NAMESPACE.svc.cluster.local:4317"
echo "  OTLP HTTP: otel-gateway-opentelemetry-collector.$NAMESPACE.svc.cluster.local:4318"
echo ""
echo "Environment variables for your apps:"
echo "  OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-gateway-opentelemetry-collector.$NAMESPACE.svc.cluster.local:4317"
echo "  OTEL_SERVICE_NAME=my-service"
echo ""
