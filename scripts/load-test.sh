#!/bin/bash

API_URL="${API_URL:-http://localhost:8080}"
TOTAL_REQUESTS="${1:-100000}"
CONCURRENCY="${2:-10}"

echo "=== Load Test ==="
echo "API URL: $API_URL"
echo "Total Requests: $TOTAL_REQUESTS"
echo "Concurrency: $CONCURRENCY"
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
