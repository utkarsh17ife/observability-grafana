#!/bin/bash
set -e

NAMESPACE="observability"

echo "=== Observability Stack Uninstall ==="
echo "Namespace: $NAMESPACE"
echo ""

# Uninstall in reverse order
echo "Uninstalling Grafana..."
helm uninstall grafana -n "$NAMESPACE" 2>/dev/null || true

echo "Deleting Grafana dashboard ConfigMap..."
kubectl delete configmap grafana-dashboards -n "$NAMESPACE" 2>/dev/null || true

echo "Uninstalling OpenTelemetry Gateway..."
helm uninstall otel-gateway -n "$NAMESPACE" 2>/dev/null || true

echo "Uninstalling OpenTelemetry DaemonSet..."
helm uninstall otel-daemon -n "$NAMESPACE" 2>/dev/null || true

echo "Uninstalling Tempo..."
helm uninstall tempo -n "$NAMESPACE" 2>/dev/null || true

echo "Uninstalling Promtail..."
helm uninstall promtail -n "$NAMESPACE" 2>/dev/null || true

echo "Uninstalling Loki..."
helm uninstall loki -n "$NAMESPACE" 2>/dev/null || true

echo "Uninstalling VictoriaMetrics stack..."
helm uninstall vm -n "$NAMESPACE" 2>/dev/null || true

echo "Uninstalling VictoriaMetrics Operator..."
helm uninstall vm-operator -n "$NAMESPACE" 2>/dev/null || true

echo "Deleting VictoriaMetrics CRDs..."
kubectl get crds -o name | grep victoriametrics | while read crd; do kubectl delete "$crd" 2>/dev/null || true; done

echo "Deleting namespace..."
kubectl delete namespace "$NAMESPACE" 2>/dev/null || true

echo ""
echo "=== Uninstall Complete ==="
