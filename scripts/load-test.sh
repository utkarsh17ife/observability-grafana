#!/bin/bash

# Usage info
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    cat << 'EOF'
Usage: ./load-test.sh [TOTAL_REQUESTS] [CONCURRENCY]

Environment variables:
  K8S_MODE=true     Enable Kubernetes mode (auto port-forward)
  NAMESPACE         Kubernetes namespace (default: applications)
  LOCAL_PORT        Local port for port-forward (default: 8080)
  API_URL           Override API URL directly

Examples:
  # Local docker-compose
  ./load-test.sh 1000 5

  # Kubernetes mode (auto port-forward)
  K8S_MODE=true ./load-test.sh 1000 5

  # Custom namespace
  K8S_MODE=true ./load-test.sh 1000 5

  # Direct URL
  API_URL=http://my-api:8080 ./load-test.sh 1000 5
EOF
    exit 0
fi

NAMESPACE="${NAMESPACE:-applications}"
K8S_MODE="${K8S_MODE:-false}"
LOCAL_PORT="${LOCAL_PORT:-8080}"
API_URL="${API_URL:-http://localhost:$LOCAL_PORT}"
TOTAL_REQUESTS="${1:-100000}"
CONCURRENCY="${2:-10}"

cleanup() {
    if [ -n "$PORT_FORWARD_PID" ]; then
        echo "Stopping port-forward (PID: $PORT_FORWARD_PID)..."
        kill $PORT_FORWARD_PID 2>/dev/null
    fi
}
trap cleanup EXIT

# Setup port-forward for k8s mode
if [ "$K8S_MODE" = "true" ]; then
    echo "Setting up port-forward to api-service in namespace $NAMESPACE..."
    kubectl port-forward svc/api-service $LOCAL_PORT:8080 -n $NAMESPACE &
    PORT_FORWARD_PID=$!
    sleep 2

    # Check if port-forward is running
    if ! kill -0 $PORT_FORWARD_PID 2>/dev/null; then
        echo "ERROR: Failed to setup port-forward. Is api-service running?"
        exit 1
    fi
    echo "Port-forward established on localhost:$LOCAL_PORT"
    echo ""
fi

echo "=== Load Test ==="
echo "API URL: $API_URL"
echo "Total Requests: $TOTAL_REQUESTS"
echo "Concurrency: $CONCURRENCY"
if [ "$K8S_MODE" = "true" ]; then
    echo "Mode: Kubernetes (namespace: $NAMESPACE)"
fi
echo ""

ENDPOINTS=(
    "GET:/fast:70"
    "GET:/slow:5"
    "GET:/error:5"
    "GET:/external-call:20"
)

send_request() {
    local method=$1
    local endpoint=$2
    curl -s -X "$method" "${API_URL}${endpoint}" -o /dev/null -w "%{http_code}"
}

pick_endpoint() {
    local rand=$((RANDOM % 100))
    local cumulative=0

    for entry in "${ENDPOINTS[@]}"; do
        IFS=':' read -r method endpoint weight <<< "$entry"
        cumulative=$((cumulative + weight))
        if [ $rand -lt $cumulative ]; then
            echo "$method:$endpoint"
            return
        fi
    done
    echo "GET:/fast"
}

worker() {
    local worker_id=$1
    local requests_per_worker=$2
    local success=0
    local failed=0

    for ((i=1; i<=requests_per_worker; i++)); do
        local picked=$(pick_endpoint)
        IFS=':' read -r method endpoint <<< "$picked"
        local status=$(send_request "$method" "$endpoint")

        if [[ "$status" =~ ^2 ]]; then
            ((success++))
        else
            ((failed++))
        fi

        if [ $((i % 100)) -eq 0 ]; then
            echo "Worker $worker_id: $i/$requests_per_worker (success: $success, failed: $failed)"
        fi
    done

    echo "Worker $worker_id completed: success=$success, failed=$failed"
}

REQUESTS_PER_WORKER=$((TOTAL_REQUESTS / CONCURRENCY))
echo "Starting $CONCURRENCY workers, $REQUESTS_PER_WORKER requests each..."
echo ""

START_TIME=$(date +%s)

for ((w=1; w<=CONCURRENCY; w++)); do
    worker $w $REQUESTS_PER_WORKER &
done

wait

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo ""
echo "=== Load Test Complete ==="
echo "Duration: ${DURATION}s"
echo "Requests: $TOTAL_REQUESTS"
echo "RPS: $((TOTAL_REQUESTS / (DURATION > 0 ? DURATION : 1)))"