1. Port-forward the query-frontend (same endpoint Grafana uses):                                                                                         
kubectl port-forward svc/tempo-query-frontend 3200:3200 -n observability                                                                                 
                                                                                                                                                        
1. Check if Tempo is healthy:                                                                                                                            
curl -s http://localhost:3200/ready

1. Check Tempo build info / status:
curl -s http://localhost:3200/status/config | head -50

1. Search for recent traces (last 1h):
# Search all traces
curl -s "http://localhost:3200/api/search?limit=5&start=$(date -v-1H +%s)&end=$(date +%s)" | jq .

# Search by service name
curl -s "http://localhost:3200/api/search?tags=service.name%3Dapi-service&limit=5&start=$(date -v-1H +%s)&end=$(date +%s)" | jq .

5. If you find a traceID from above, fetch it directly:
curl -s "http://localhost:3200/api/traces/<TRACE_ID>" | jq .

6. Check if the ingester has any live traces:
curl -s "http://localhost:3200/api/search?limit=1" | jq .

7. Check Tempo metrics for ingested spans:
# Port-forward distributor to check if spans are arriving
kubectl port-forward svc/tempo-distributor 3200:3200 -n observability
# Then:
curl -s "http://localhost:3200/metrics" | grep -E "tempo_distributor_spans_received|tempo_ingester_traces_created"

Start with steps 1-4. If step 4 returns empty results, the issue is either:
- OTEL collector not forwarding traces to Tempo distributor
- Tempo ingester not flushing to storage
