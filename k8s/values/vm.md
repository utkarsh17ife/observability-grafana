
*********************Testing Victoria metrics**********************

================================================================================                                                                                      
                      VICTORIAMETRICS DATA FLOW                                                                                                                     
================================================================================                                                                                                                                                                        
WRITE PATH (Metrics Collection)
--------------------------------------------------------------------------------                                                                                      
Source                    -->  Destination                -->  Final Storage
--------------------------------------------------------------------------------                                                                                      
vmagent (scraper)         -->  vminsert:8480              -->  vmstorage:8400
otel-gateway (OTLP)       -->  vminsert:8480              -->  vmstorage:8400
--------------------------------------------------------------------------------                                                                                                                                                                        
READ PATH (Querying)
--------------------------------------------------------------------------------                                                                             
Client                    -->  Query Engine               -->  Data Source
--------------------------------------------------------------------------------
Grafana                   -->  vmselect:8481              -->  vmstorage:8401
--------------------------------------------------------------------------------
ALERTING PATH
--------------------------------------------------------------------------------                                                                                      
Source                    -->  Processor                  -->  Notification
--------------------------------------------------------------------------------
vmalert                   -->  vmselect:8481 (queries)    -->  alertmanager:9093
--------------------------------------------------------------------------------                                                                                                                                                                        
POD CONNECTIONS SUMMARY
--------------------------------------------------------------------------------
Pod Name                          Port      Connects To
--------------------------------------------------------------------------------
vmagent                           8429      vminsert:8480 (push metrics)
otel-gateway                      4317      vminsert:8480 (remote write)
vminsert                          8480      vmstorage:8400 (store data)
vmstorage                         8400      - (receives from vminsert)
vmstorage                         8401      - (serves to vmselect)
vmselect                          8481      vmstorage:8401 (read data)
vmalert                           8080      vmselect:8481 (query metrics)
alertmanager                      9093      - (receives alerts)
Grafana                           3000      vmselect:8481 (query metrics)
--------------------------------------------------------------------------------
EXTERNAL TARGETS SCRAPED BY VMAGENT
--------------------------------------------------------------------------------                                                                                      
Target                            Port      Metrics
--------------------------------------------------------------------------------
node-exporter                     9100      Node/OS metrics
kube-state-metrics                8080      Kubernetes state
kubelet                           10250     Container metrics
application pods                  various   App metrics (if annotated)
--------------------------------------------------------------------------------
SERVICE ENDPOINTS
--------------------------------------------------------------------------------  
Service                                                    Port
--------------------------------------------------------------------------------  
vminsert-vm-victoria-metrics-k8s-stack                     8480
vmselect-vm-victoria-metrics-k8s-stack                     8481
vmstorage-vm-victoria-metrics-k8s-stack                    8400,8401,8482
vmagent-vm-victoria-metrics-k8s-stack                      8429
vmalert-vm-victoria-metrics-k8s-stack                      8080
vmalertmanager-vm-victoria-metrics-k8s-stack               9093
--------------------------------------------------------------------------------   


Test VictoriaMetrics APIs
                                                                                                                                                                    
# Port-forward vmselect (what Grafana uses)
kubectl port-forward svc/vmselect-vm-victoria-metrics-k8s-stack 8481:8481 -n observability

Then test these endpoints:

# 1. Health check
curl -s "http://localhost:8481/health"

# 2. List all metric names (what Grafana uses for autocomplete)
curl -s "http://localhost:8481/select/0/prometheus/api/v1/label/__name__/values" | jq '.data[:10]'

# 3. Query a metric (instant query)
curl -s "http://localhost:8481/select/0/prometheus/api/v1/query?query=up" | jq

# 4. Query range (what Grafana uses for graphs)
curl -s "http://localhost:8481/select/0/prometheus/api/v1/query_range" \
--data-urlencode "query=up" \
--data-urlencode "start=$(date -v-1H +%s)" \
--data-urlencode "end=$(date +%s)" \
--data-urlencode "step=60" | jq

# 5. List all labels
curl -s "http://localhost:8481/select/0/prometheus/api/v1/labels" | jq

# 6. Get label values (e.g., all namespaces)
curl -s "http://localhost:8481/select/0/prometheus/api/v1/label/namespace/values" | jq

# 7. Check active time series count
curl -s "http://localhost:8481/select/0/prometheus/api/v1/status/tsdb" | jq

Grafana Datasource URL
http://vmselect-vm-victoria-metrics-k8s-stack.observability.svc.cluster.local:8481/select/0/prometheus
The /select/0/prometheus path makes vmselect 100% Prometheus-compatible.






## Component Overview

| Pod | Description | Port |
|-----|-------------|------|
| **vmstorage** | Time-series database storage engine. Stores all metric data on disk, handles compression & retention | 8400 (insert), 8401 (select), 8482 (HTTP) |
| **vminsert** | Write gateway/router. Receives metrics from vmagent & OTEL, routes to vmstorage shards | 8480 |
| **vmselect** | Query engine. Handles PromQL queries from Grafana, fetches data from vmstorage | 8481 |
| **vmagent** | Metrics scraper (like Prometheus). Discovers & scrapes targets, pushes to vminsert | 8429 |
| **vmalert** | Alerting engine. Evaluates rules against vmselect, sends alerts to alertmanager | 8080 |
| **vmalertmanager** | Alert notification manager. Deduplicates, groups, routes alerts to Slack/Email/etc | 9093 |
| **vm-operator** | Kubernetes operator. Manages VM custom resources, auto-configures scrape targets | 9443 |
| **vm-kube-state-metrics** | Kubernetes state exporter. Exports k8s object states (pod counts, deployments) | 8080 |
| **vm-prometheus-node-exporter** | Node/OS metrics exporter (DaemonSet). ONE POD PER NODE for CPU, memory, disk, network | 9100 |

## Data Flow

### Write Path (Metrics Collection)

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                              WRITE PATH                                       │
└──────────────────────────────────────────────────────────────────────────────┘

   ┌──────────────┐        ┌──────────────┐        ┌──────────────┐
   │   vmagent    │───────▶│   vminsert   │───────▶│  vmstorage   │
   │  (scraper)   │  :8480 │   (router)   │  :8400 │   (store)    │
   └──────────────┘        └──────────────┘        └──────────────┘
          │                                               │
   Scrapes metrics                               Stores time-series
   from targets                                  data on disk
   (pods, nodes)


   ┌──────────────┐
   │ otel-gateway │───────▶ vminsert:8480 (prometheusremotewrite)
   │   (OTLP)     │
   └──────────────┘
   App metrics via OTLP
```

### Read Path (Querying)

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                              READ PATH                                        │
└──────────────────────────────────────────────────────────────────────────────┘

   ┌──────────────┐        ┌──────────────┐        ┌──────────────┐
   │   Grafana    │───────▶│   vmselect   │───────▶│  vmstorage   │
   │              │  :8481 │  (query)     │  :8401 │   (store)    │
   └──────────────┘        └──────────────┘        └──────────────┘
                                  │
                           Prometheus-compatible
                           query API
```

### Alerting Path

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                            ALERTING PATH                                      │
└──────────────────────────────────────────────────────────────────────────────┘

   ┌──────────────┐        ┌──────────────┐        ┌──────────────┐
   │   vmalert    │───────▶│   vmselect   │        │alertmanager  │
   │              │  :8481 │  (queries)   │        │   :9093      │
   └──────────────┘        └──────────────┘        └──────────────┘
          │                                               ▲
          └───────────────────────────────────────────────┘
                         sends alerts
```

## vmagent vs node-exporter

**Do we need vmagent on all nodes like node-exporter?**

**NO!** Here's why they're different:

| Component | Deployment Type | Why |
|-----------|-----------------|-----|
| **node-exporter** | DaemonSet (1 per node) | Collects LOCAL hardware metrics (CPU, RAM, disk). Must run on each node to access `/proc`, `/sys` filesystem |
| **vmagent** | Deployment (1 replica) | PULLS metrics from targets over network. Can scrape any pod from anywhere. Doesn't need local access to nodes |

### How node-exporter works

```
Node: observability       →  vm-prometheus-node-exporter-dmxsn (collects THIS node's metrics)
Node: observability-m02   →  vm-prometheus-node-exporter-rztzn (collects THIS node's metrics)
Node: observability-m03   →  vm-prometheus-node-exporter-tghwc (collects THIS node's metrics)
```

### Data flow with node-exporter

```
node-exporter (node1) ──┐
node-exporter (node2) ──┼──▶ vmagent ──▶ vminsert ──▶ vmstorage
node-exporter (node3) ──┘    (scrapes all)
```

### Application metrics flow (via OTEL)

```
Java App → OTEL Agent → otel-gateway → vminsert → vmstorage
                        (via OTLP)    (remote write)
```

**Note:** Application metrics come via OTEL, NOT vmagent scraping!

## Service Endpoints

| Service | Port | URL Path |
|---------|------|----------|
| vminsert | 8480 | `/insert/0/prometheus/api/v1/write` |
| vmselect | 8481 | `/select/0/prometheus/api/v1/query` |
| vmstorage | 8400, 8401, 8482 | Internal |
| vmagent | 8429 | `/metrics` |
| vmalert | 8080 | `/api/v1/alerts` |
| alertmanager | 9093 | `/api/v2/alerts` |

## Grafana Datasource URL

```
http://vmselect-vm-victoria-metrics-k8s-stack.observability.svc.cluster.local:8481/select/0/prometheus
```

The `/select/0/prometheus` path makes vmselect 100% Prometheus-compatible.

## Testing VictoriaMetrics

### Port-forward vmselect

```bash
kubectl port-forward svc/vmselect-vm-victoria-metrics-k8s-stack 8481:8481 -n observability
```

### Test queries

```bash
# Health check
curl -s "http://localhost:8481/health"

# List all metric names
curl -s "http://localhost:8481/select/0/prometheus/api/v1/label/__name__/values" | jq '.data[:10]'

# Query a metric
curl -s "http://localhost:8481/select/0/prometheus/api/v1/query?query=up" | jq

# List all labels
curl -s "http://localhost:8481/select/0/prometheus/api/v1/labels" | jq

# Get label values (e.g., namespaces)
curl -s "http://localhost:8481/select/0/prometheus/api/v1/label/namespace/values" | jq
```

## Useful PromQL Queries for Grafana

Request Rate

sum(rate(http_server_requests_seconds_count{application="api-service"}[1m])) by (uri, method, status)

Average Response Time

sum(rate(http_server_requests_seconds_sum{application="api-service"}[1m])) by (uri)
/
sum(rate(http_server_requests_seconds_count{application="api-service"}[1m])) by (uri)

95th Percentile Latency

histogram_quantile(0.95,
   sum(rate(http_server_requests_seconds_bucket{application="api-service"}[5m])) by (le, uri)
)

Error Rate

sum(rate(http_server_requests_seconds_count{application="api-service", status=~"5.."}[1m]))
/
sum(rate(http_server_requests_seconds_count{application="api-service"}[1m]))

Requests by Status Code

sum(rate(http_server_requests_seconds_count{application="api-service"}[1m])) by (status, uri)



curl http://localhost:8080/actuator/prometheus 


http_server_requests_seconds_bucket{application="api-service",error="none",exception="none",method="GET",outcome="SUCCESS",status="200",uri="/fast",le="30.0",} 5010.0
http_server_requests_seconds_bucket{application="api-service",error="none",exception="none",method="GET",outcome="SUCCESS",status="200",uri="/fast",le="+Inf",} 5010.0
http_server_requests_seconds_count{application="api-service",error="none",exception="none",method="GET",outcome="SUCCESS",status="200",uri="/fast",} 5010.0
http_server_requests_seconds_sum{application="api-service",error="none",exception="none",method="GET",outcome="SUCCESS",status="200",uri="/fast",} 284.789628457
# HELP http_server_requests_seconds_max  
# TYPE http_server_requests_seconds_max gauge
http_server_requests_seconds_max{application="api-service",error="none",exception="none",method="GET",outcome="SUCCESS",status="200",uri="/slow",} 4.917738544
http_server_requests_seconds_max{application="api-service",error="none",exception="none",method="GET",outcome="SUCCESS",status="200",uri="/external-call",} 0.570911917
http_server_requests_seconds_max{application="api-service",error="none",exception="none",method="GET",outcome="SERVER_ERROR",status="500",uri="/error",} 0.104900792
http_server_requests_seconds_max{application="api-service",error="none",exception="none",method="GET",outcome="CLIENT_ERROR",status="404",uri="/**",} 0.0
http_server_requests_seconds_max{application="api-service",error="none",exception="none",method="GET",outcome="SUCCESS",status="200",uri="/fast",} 0.18855975
# HELP tomcat_sessions_active_max_sessions  
# TYPE tomcat_sessions_active_max_sessions gauge
tomcat_sessions_active_max_sessions{application="api-service",} 0.0
# HELP jvm_threads_peak_threads The peak live thread count since the Java virtual machine started or peak was reset
# TYPE jvm_threads_peak_threads gauge
jvm_threads_peak_threads{application="api-service",} 38.0
# HELP jvm_memory_max_bytes The maximum amount of memory in bytes that can be used for memory management
# TYPE jvm_memory_max_bytes gauge
jvm_memory_max_bytes{application="api-service",area="nonheap",id="CodeHeap 'profiled nmethods'",} 1.22912768E8
jvm_memory_max_bytes{application="api-service",area="heap",id="Eden Space",} 3.5782656E7
jvm_memory_max_bytes{application="api-service",area="nonheap",id="CodeHeap 'non-nmethods'",} 5828608.0
jvm_memory_max_bytes{application="api-service",area="nonheap",id="Metaspace",} -1.0
jvm_memory_max_bytes{application="api-service",area="nonheap",id="CodeHeap 'non-profiled nmethods'",} 1.22916864E8
jvm_memory_max_bytes{application="api-service",area="heap",id="Tenured Gen",} 8.9522176E7
jvm_memory_max_bytes{application="api-service",area="heap",id="Survivor Space",} 4456448.0
jvm_memory_max_bytes{application="api-service",area="nonheap",id="Compressed Class Space",} 1.073741824E9
# HELP tomcat_sessions_alive_max_seconds  
# TYPE tomcat_sessions_alive_max_seconds gauge
tomcat_sessions_alive_max_seconds{application="api-service",} 0.0
# HELP jvm_memory_used_bytes The amount of used memory
# TYPE jvm_memory_used_bytes gauge
jvm_memory_used_bytes{application="api-service",area="nonheap",id="CodeHeap 'profiled nmethods'",} 2.13056E7
jvm_memory_used_bytes{application="api-service",area="heap",id="Eden Space",} 1.0574792E7
jvm_memory_used_bytes{application="api-service",area="nonheap",id="CodeHeap 'non-nmethods'",} 1364736.0
jvm_memory_used_bytes{application="api-service",area="nonheap",id="Metaspace",} 6.6028112E7
jvm_memory_used_bytes{application="api-service",area="nonheap",id="CodeHeap 'non-profiled nmethods'",} 1.0882944E7
jvm_memory_used_bytes{application="api-service",area="heap",id="Tenured Gen",} 3.8432336E7
jvm_memory_used_bytes{application="api-service",area="heap",id="Survivor Space",} 1102168.0
jvm_memory_used_bytes{application="api-service",area="nonheap",id="Compressed Class Space",} 8300384.0
# HELP jvm_classes_unloaded_classes_total The total number of classes unloaded since the Java virtual machine has started execution
# TYPE jvm_classes_unloaded_classes_total counter
jvm_classes_unloaded_classes_total{application="api-service",} 1.0
# HELP executor_completed_tasks_total The approximate total number of tasks that have completed execution
# TYPE executor_completed_tasks_total counter
executor_completed_tasks_total{application="api-service",name="applicationTaskExecutor",} 0.0
# HELP tomcat_sessions_created_sessions_total  
# TYPE tomcat_sessions_created_sessions_total counter
tomcat_sessions_created_sessions_total{application="api-service",} 0.0
# HELP process_cpu_usage The "recent cpu usage" for the Java Virtual Machine process
# TYPE process_cpu_usage gauge
process_cpu_usage{application="api-service",} 0.13525641025641025
# HELP jvm_classes_loaded_classes The number of classes that are currently loaded in the Java virtual machine
# TYPE jvm_classes_loaded_classes gauge
jvm_classes_loaded_classes{application="api-service",} 13278.0
# HELP system_cpu_usage The "recent cpu usage" of the system the application is running in
# TYPE system_cpu_usage gauge
system_cpu_usage{application="api-service",} 0.05865736979597236
# HELP logback_events_total Number of log events that were enabled by the effective log level
# TYPE logback_events_total counter
logback_events_total{application="api-service",level="warn",} 0.0
logback_events_total{application="api-service",level="trace",} 0.0
logback_events_total{application="api-service",level="info",} 17537.0
logback_events_total{application="api-service",level="debug",} 1428.0
logback_events_total{application="api-service",level="error",} 726.0
# HELP jvm_threads_states_threads The current number of threads
# TYPE jvm_threads_states_threads gauge
jvm_threads_states_threads{application="api-service",state="new",} 0.0
jvm_threads_states_threads{application="api-service",state="terminated",} 0.0
jvm_threads_states_threads{application="api-service",state="runnable",} 11.0
jvm_threads_states_threads{application="api-service",state="blocked",} 0.0
jvm_threads_states_threads{application="api-service",state="waiting",} 8.0
jvm_threads_states_threads{application="api-service",state="timed-waiting",} 18.0
# HELP disk_total_bytes Total space for path
# TYPE disk_total_bytes gauge
disk_total_bytes{application="api-service",path="/app/.",} 1.33532536832E11
# HELP executor_pool_max_threads The maximum allowed number of threads in the pool
# TYPE executor_pool_max_threads gauge
executor_pool_max_threads{application="api-service",name="applicationTaskExecutor",} 2.147483647E9
# HELP jvm_gc_memory_allocated_bytes_total Incremented for an increase in the size of the (young) heap memory pool after one GC to before the next
# TYPE jvm_gc_memory_allocated_bytes_total counter
jvm_gc_memory_allocated_bytes_total{application="api-service",} 7.21148832E8
# HELP tomcat_sessions_active_current_sessions  
# TYPE tomcat_sessions_active_current_sessions gauge
tomcat_sessions_active_current_sessions{application="api-service",} 0.0
# HELP jvm_threads_daemon_threads The current number of live daemon threads
# TYPE jvm_threads_daemon_threads gauge
jvm_threads_daemon_threads{application="api-service",} 33.0
# HELP http_client_requests_seconds  
# TYPE http_client_requests_seconds summary
http_client_requests_seconds_count{application="api-service",client_name="worker-service.applications.svc.cluster.local",error="none",exception="none",method="GET",outcome="SUCCESS",status="200",uri="/process",} 1427.0
http_client_requests_seconds_sum{application="api-service",client_name="worker-service.applications.svc.cluster.local",error="none",exception="none",method="GET",outcome="SUCCESS",status="200",uri="/process",} 446.936304999
# HELP http_client_requests_seconds_max  
# TYPE http_client_requests_seconds_max gauge
http_client_requests_seconds_max{application="api-service",client_name="worker-service.applications.svc.cluster.local",error="none",exception="none",method="GET",outcome="SUCCESS",status="200",uri="/process",} 0.526762876
# HELP system_load_average_1m The sum of the number of runnable entities queued to available processors and the number of runnable entities running on the available processors averaged over a period of time
# TYPE system_load_average_1m gauge
system_load_average_1m{application="api-service",} 1.53125
# HELP tomcat_sessions_rejected_sessions_total  
# TYPE tomcat_sessions_rejected_sessions_total counter
tomcat_sessions_rejected_sessions_total{application="api-service",} 0.0
# HELP executor_pool_core_threads The core number of threads for the pool
# TYPE executor_pool_core_threads gauge
executor_pool_core_threads{application="api-service",name="applicationTaskExecutor",} 8.0
# HELP api_requests_total Total API requests
# TYPE api_requests_total counter
api_requests_total{application="api-service",service="api-service",} 7163.0









   cannot process vmselect conn 10.244.0.9:42742: cannot process vmselect request in 31 seconds: cannot execute "search_v7": search error: error when searching for tagFilters=[{AccountID=0,ProjectID=0,__name__="kube_pod_owner",cluster="your-cluster-name",namespace=~"infrastructure|kube-system|observability",owner_kind!="Job",pod=~"api-service-7957b95d65-6pk2l|..worker-service-58f8b588-h5tqd"}] on the time range [2026-02-04T14:49:00Z..2026-02-04T14:59:00Z]: deadline exceeded                                                                                                        │
│                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          │

1. Check OTEL metrics (coming via OTEL collector -> vminsert):                                                                                           
# OTEL metrics typically have service_name or job labels from OTEL                                                                                       
curl -s "http://localhost:8481/select/0/prometheus/api/v1/label/__name__/values" | jq '.data[]' | grep -i "http_server"                                  
                                                                                                                                                         
1. Check Node Exporter metrics:
# node_* metrics are exclusive to prometheus-node-exporter
curl -s "http://localhost:8481/select/0/prometheus/api/v1/query?query=node_cpu_seconds_total" | jq '.data.result | length'

1. Quick validation of both in one go:
# OTEL source - your Java app metrics scraped from /actuator/prometheus
curl -s "http://localhost:8481/select/0/prometheus/api/v1/query?query=api_requests_total" | jq '.data.result | length'

# Node exporter source - node metrics
curl -s "http://localhost:8481/select/0/prometheus/api/v1/query?query=node_memory_MemTotal_bytes" | jq '.data.result | length'

If result length is 0, that source isn't being scraped.

4. Check all active scrape targets and their jobs:
# List all unique job labels - shows what's being scraped
curl -s "http://localhost:8481/select/0/prometheus/api/v1/label/job/values" | jq .

This will return something like:
{
   "data": ["api-service", "node-exporter", "kubelet", "vmagent", ...]
}

5. Check target counts per job:
# How many targets per job
curl -s "http://localhost:8481/select/0/prometheus/api/v1/query?query=count(up)%20by%20(job)" | jq '.data.result[] | {job: .metric.job, count:
.value[1]}'

The up metric is added by the scraper for every target — if node-exporter and your app jobs show up with up == 1, both sources are healthy.
