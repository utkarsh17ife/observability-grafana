VictoriaMetrics (Metrics Storage)                                                                                                                    
  ┌────────────────────────────────┬───────────────────────────────────────────────┬─────────────────────────────────────────┐                         
  │              Pod               │                    Purpose                    │                 Scaling                 │                         
  ├────────────────────────────────┼───────────────────────────────────────────────┼─────────────────────────────────────────┤                         
  │ vmstorage-vm-*                 │ Stores time-series metrics data               │ StatefulSet - scale for HA/capacity     │                         
  ├────────────────────────────────┼───────────────────────────────────────────────┼─────────────────────────────────────────┤                         
  │ vminsert-vm-*                  │ Receives metrics, routes to storage           │ Deployment - scale for write throughput │                         
  ├────────────────────────────────┼───────────────────────────────────────────────┼─────────────────────────────────────────┤                         
  │ vmselect-vm-*                  │ Query endpoint for reading metrics            │ StatefulSet - scale for query load      │                         
  ├────────────────────────────────┼───────────────────────────────────────────────┼─────────────────────────────────────────┤                         
  │ vmagent-vm-*                   │ Scrapes Prometheus targets, sends to vminsert │ Deployment - 1 per cluster usually      │                         
  ├────────────────────────────────┼───────────────────────────────────────────────┼─────────────────────────────────────────┤                         
  │ vmalert-vm-*                   │ Evaluates alerting rules                      │ Deployment - 1 per cluster              │                         
  ├────────────────────────────────┼───────────────────────────────────────────────┼─────────────────────────────────────────┤                         
  │ vmalertmanager-vm-*            │ Routes alerts, sends notifications            │ StatefulSet - 1 per cluster             │                         
  ├────────────────────────────────┼───────────────────────────────────────────────┼─────────────────────────────────────────┤                         
  │ vm-victoria-metrics-operator-* │ Manages VM CRDs (VMAgent, VMAlert, etc.)      │ Deployment - 1 per cluster              │                         
  ├────────────────────────────────┼───────────────────────────────────────────────┼─────────────────────────────────────────┤                         
  │ vm-kube-state-metrics-*        │ Exports K8s object states as metrics          │ Deployment - 1 per cluster              │                         
  ├────────────────────────────────┼───────────────────────────────────────────────┼─────────────────────────────────────────┤                         
  │ vm-prometheus-node-exporter-*  │ Collects node-level metrics (CPU, disk, etc.) │ DaemonSet - 1 per node                  │                         
  └────────────────────────────────┴───────────────────────────────────────────────┴─────────────────────────────────────────┘                         
  Loki (Log Storage)                                                                                                                                   
  ┌─────────────────────────┬────────────────────────────────────────────┬──────────────────────────────────────────┐                                  
  │           Pod           │                  Purpose                   │                 Scaling                  │                                  
  ├─────────────────────────┼────────────────────────────────────────────┼──────────────────────────────────────────┤                                  
  │ loki-*-ingester-*       │ Receives logs, writes to S3                │ StatefulSet - scale for write throughput │                                  
  ├─────────────────────────┼────────────────────────────────────────────┼──────────────────────────────────────────┤                                  
  │ loki-*-distributor-*    │ Load balances incoming logs to ingesters   │ Deployment - scale for ingestion         │                                  
  ├─────────────────────────┼────────────────────────────────────────────┼──────────────────────────────────────────┤                                  
  │ loki-*-querier-*        │ Reads logs from S3                         │ StatefulSet - scale for query load       │                                  
  ├─────────────────────────┼────────────────────────────────────────────┼──────────────────────────────────────────┤                                  
  │ loki-*-query-frontend-* │ Query splitting, caching, optimization     │ Deployment - scale for query load        │                                  
  ├─────────────────────────┼────────────────────────────────────────────┼──────────────────────────────────────────┤                                  
  │ loki-*-compactor-*      │ Compacts index, handles retention/deletion │ StatefulSet - 1 per cluster only         │                                  
  ├─────────────────────────┼────────────────────────────────────────────┼──────────────────────────────────────────┤                                  
  │ loki-*-gateway-*        │ Nginx proxy, routes API requests           │ Deployment - scale for load              │                                  
  └─────────────────────────┴────────────────────────────────────────────┴──────────────────────────────────────────┘                                  
  Tempo (Trace Storage)                                                                                                                                
  ┌────────────────────────┬───────────────────────────────┬──────────────────────────────────────────┐                                                
  │          Pod           │            Purpose            │                 Scaling                  │                                                
  ├────────────────────────┼───────────────────────────────┼──────────────────────────────────────────┤                                                
  │ tempo-ingester-*       │ Receives traces, writes to S3 │ StatefulSet - scale for write throughput │                                                
  ├────────────────────────┼───────────────────────────────┼──────────────────────────────────────────┤                                                
  │ tempo-distributor-*    │ Load balances incoming traces │ Deployment - scale for ingestion         │                                                
  ├────────────────────────┼───────────────────────────────┼──────────────────────────────────────────┤                                                
  │ tempo-querier-*        │ Queries traces from S3        │ Deployment - scale for query load        │                                                
  ├────────────────────────┼───────────────────────────────┼──────────────────────────────────────────┤                                                
  │ tempo-query-frontend-* │ Query optimization            │ Deployment - scale for query load        │                                                
  ├────────────────────────┼───────────────────────────────┼──────────────────────────────────────────┤                                                
  │ tempo-compactor-*      │ Compacts trace blocks         │ Deployment - 1 per cluster only          │                                                
  ├────────────────────────┼───────────────────────────────┼──────────────────────────────────────────┤                                                
  │ tempo-memcached-*      │ Query cache                   │ StatefulSet - optional, improves perf    │                                                
  └────────────────────────┴───────────────────────────────┴──────────────────────────────────────────┘                                                
  OpenTelemetry Collectors                                                                                                                             
  ┌────────────────┬───────────────────────────────────────────┬───────────────────────────────────┐                                                   
  │      Pod       │                  Purpose                  │              Scaling              │                                                   
  ├────────────────┼───────────────────────────────────────────┼───────────────────────────────────┤                                                   
  │ otel-daemon-*  │ Collects telemetry from apps on each node │ DaemonSet - 1 per node            │                                                   
  ├────────────────┼───────────────────────────────────────────┼───────────────────────────────────┤                                                   
  │ otel-gateway-* │ Central collector, routes to backends     │ Deployment - scale for throughput │                                                   
  └────────────────┴───────────────────────────────────────────┴───────────────────────────────────┘                                                   
  Log Collection                                                                                                                                       
  ┌────────────┬────────────────────────────────────────┬────────────────────────┐                                                                     
  │    Pod     │                Purpose                 │        Scaling         │                                                                     
  ├────────────┼────────────────────────────────────────┼────────────────────────┤                                                                     
  │ promtail-* │ Collects container logs, sends to Loki │ DaemonSet - 1 per node │                                                                     
  └────────────┴────────────────────────────────────────┴────────────────────────┘ 

