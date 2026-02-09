
Architecture:                                                                                                                                                         
Promtail → Gateway → Distributor → Ingester
Grafana  → Gateway → Query-Frontend → Querier

The gateway automatically routes:
  - Write requests (/loki/api/v1/push) → Distributor
  - Read requests (/loki/api/v1/query) → Query-Frontend → Querier

WRITE PATH:
Promtail → Gateway → Distributor → Ingester → Object Storage (MinIO)
                                                                                                                                                                        
READ PATH:
Grafana → Gateway → Query-Frontend → Querier → Object Storage (MinIO)
											 ↘ Ingester (recent data)  


BACKGROUND PROCESSES:                                                                                                                                                 
    Compactor → Object Storage (MinIO)                                                                                                                                  
        ↓
- Compacts index files                                                                                                                                              
- Runs retention/deletion                                                                                                                                           
- Deduplicates chunks                                                                                                                                               
                                                                                                                                                                        
Compactor responsibilities:
- Index compaction - Merges small index files into larger ones for faster queries
- Retention - Deletes old data based on retention_period (720h in your config)
- Chunk deduplication - Removes duplicate log entries



# Port-forward Loki gateway
kubectl port-forward svc/loki-loki-distributed-gateway 3100:80 -n observability
                                                                                                                                                                    
Then in another terminal, test these endpoints:
                                                                                                                                                                    
# 1. Check if Loki is ready
curl -s http://localhost:3100/ready
                                                                                                                                                                    
# 2. Check available labels (should show labels if logs exist)
curl -s http://localhost:3100/loki/api/v1/labels | jq
                                                                                                                                                                    
# 3. Query recent logs (last 1 hour)
curl -s "http://localhost:3100/loki/api/v1/query_range" \
--data-urlencode 'query={job=~".+"}' \
--data-urlencode "start=$(date -v-1H +%s)000000000" \
--data-urlencode "end=$(date +%s)000000000" \
--data-urlencode "limit=10" | jq
                                                                                                                                                                    
# 4. Check specific namespace logs
curl -s "http://localhost:3100/loki/api/v1/query_range" \
--data-urlencode 'query={namespace="applications"}' \
--data-urlencode "start=$(date -v-1H +%s)000000000" \
--data-urlencode "end=$(date +%s)000000000" \
--data-urlencode "limit=5" | jq

