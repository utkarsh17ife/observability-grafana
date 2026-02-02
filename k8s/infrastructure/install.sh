#!/bin/bash
set -e

NAMESPACE="infrastructure"
CLUSTER_NAME="${CLUSTER_NAME:-your-cluster-name}"
MINIO_ROOT_USER="${MINIO_ROOT_USER:-admin}"
MINIO_ROOT_PASSWORD="${MINIO_ROOT_PASSWORD:-changeme123}"
REGISTRY_USER="${REGISTRY_USER:-admin}"
REGISTRY_PASSWORD="${REGISTRY_PASSWORD:-changeme123}"
ELASTICSEARCH_PASSWORD="${ELASTICSEARCH_PASSWORD:-changeme123}"
DOMAIN="${DOMAIN:-local}"
DATA_DIR="${DATA_DIR:-/data}"

# Detect if running on Docker Desktop and use appropriate storage class
if kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null | grep -q "docker-desktop"; then
  STORAGE_CLASS="${STORAGE_CLASS:-hostpath}"
  IS_DOCKER_DESKTOP=true
  echo "Detected Docker Desktop - using hostpath storage class"
else
  STORAGE_CLASS="${STORAGE_CLASS:-local-storage}"
  IS_DOCKER_DESKTOP=false
fi

echo "=== Infrastructure Services Installation ==="
echo "Namespace: $NAMESPACE"
echo "Storage Class: $STORAGE_CLASS"
echo "Data Directory: $DATA_DIR"
echo ""

# Create namespace
echo "Creating namespace..."
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Create namespace for applications (where Java apps will run)
echo "Creating applications namespace..."
kubectl create namespace applications --dry-run=client -o yaml | kubectl apply -f -

# Skip local PV creation for Docker Desktop (uses hostpath provisioner)
if [ "$IS_DOCKER_DESKTOP" = "false" ]; then

# Create Local Storage Class
echo "Creating Local Storage Class..."
kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-storage
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Retain
EOF

# Create local PVs for MinIO (4 nodes for distributed mode)
echo "Creating Local Persistent Volumes for MinIO..."
for i in 0 1 2 3; do
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: minio-pv-${i}
  labels:
    type: local
    app: minio
spec:
  storageClassName: local-storage
  capacity:
    storage: 50Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  local:
    path: ${DATA_DIR}/minio-${i}
  nodeAffinity:
    required:
      nodeSelectorTerms:
        - matchExpressions:
            - key: kubernetes.io/hostname
              operator: Exists
EOF
done

# Create local PV for Registry
echo "Creating Local Persistent Volume for Registry..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: registry-pv-0
  labels:
    type: local
    app: registry
spec:
  storageClassName: local-storage
  capacity:
    storage: 100Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  local:
    path: ${DATA_DIR}/registry
  nodeAffinity:
    required:
      nodeSelectorTerms:
        - matchExpressions:
            - key: kubernetes.io/hostname
              operator: Exists
EOF

# Create local PVs for VictoriaMetrics (2 storage nodes)
echo "Creating Local Persistent Volumes for VictoriaMetrics..."
for i in 0 1; do
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: victoriametrics-pv-${i}
  labels:
    type: local
    app: victoriametrics
spec:
  storageClassName: local-storage
  capacity:
    storage: 100Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  local:
    path: ${DATA_DIR}/victoriametrics-${i}
  nodeAffinity:
    required:
      nodeSelectorTerms:
        - matchExpressions:
            - key: kubernetes.io/hostname
              operator: Exists
EOF
done

# Create local PVs for Loki ingesters (3 nodes)
echo "Creating Local Persistent Volumes for Loki..."
for i in 0 1 2; do
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: loki-pv-${i}
  labels:
    type: local
    app: loki
spec:
  storageClassName: local-storage
  capacity:
    storage: 50Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  local:
    path: ${DATA_DIR}/loki-${i}
  nodeAffinity:
    required:
      nodeSelectorTerms:
        - matchExpressions:
            - key: kubernetes.io/hostname
              operator: Exists
EOF
done

# Create local PV for Grafana
echo "Creating Local Persistent Volume for Grafana..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: grafana-pv-0
  labels:
    type: local
    app: grafana
spec:
  storageClassName: local-storage
  capacity:
    storage: 10Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  local:
    path: ${DATA_DIR}/grafana
  nodeAffinity:
    required:
      nodeSelectorTerms:
        - matchExpressions:
            - key: kubernetes.io/hostname
              operator: Exists
EOF

else
  echo "Skipping local PV creation (Docker Desktop uses hostpath provisioner)"
fi

# Add Helm repos
echo "Adding Helm repositories..."
helm repo add minio https://charts.min.io/
helm repo add twuni https://twuni.github.io/docker-registry.helm
helm repo update

# Create secrets for MinIO
echo "Creating MinIO credentials secret..."
kubectl create secret generic minio-credentials \
  -n $NAMESPACE \
  --from-literal=rootUser=$MINIO_ROOT_USER \
  --from-literal=rootPassword=$MINIO_ROOT_PASSWORD \
  --dry-run=client -o yaml | kubectl apply -f -

# Create secrets for Docker Registry
echo "Creating Registry credentials secret..."
HTPASSWD=$(htpasswd -Bbn $REGISTRY_USER $REGISTRY_PASSWORD)
kubectl create secret generic registry-credentials \
  -n $NAMESPACE \
  --from-literal=htpasswd="$HTPASSWD" \
  --dry-run=client -o yaml | kubectl apply -f -

# Create registry auth secret for pulling images in applications namespace
echo "Creating image pull secret in applications namespace..."
kubectl create secret docker-registry regcred \
  -n applications \
  --docker-server=registry-docker-registry.$NAMESPACE.svc.cluster.local:5000 \
  --docker-username=$REGISTRY_USER \
  --docker-password=$REGISTRY_PASSWORD \
  --dry-run=client -o yaml | kubectl apply -f -

# Install MinIO
echo "Installing MinIO..."
if [ "$IS_DOCKER_DESKTOP" = "true" ]; then
  # Standalone mode for Docker Desktop (single node)
  # Use explicit image to avoid architecture issues
  helm upgrade --install minio minio/minio \
    -n $NAMESPACE \
    --set rootUser=$MINIO_ROOT_USER \
    --set rootPassword=$MINIO_ROOT_PASSWORD \
    --set mode=standalone \
    --set replicas=1 \
    --set persistence.enabled=true \
    --set persistence.storageClass=$STORAGE_CLASS \
    --set persistence.size=10Gi \
    --set image.repository=quay.io/minio/minio \
    --set image.tag=latest \
    --set mcImage.repository=quay.io/minio/mc \
    --set mcImage.tag=latest \
    --set resources.requests.memory=512Mi \
    --set consoleService.type=ClusterIP \
    --set service.type=ClusterIP
else
  # Distributed mode for production (4 nodes)
  helm upgrade --install minio minio/minio \
    -n $NAMESPACE \
    -f values.yaml \
    --set rootUser=$MINIO_ROOT_USER \
    --set rootPassword=$MINIO_ROOT_PASSWORD \
    --set persistence.storageClass=$STORAGE_CLASS
fi

# Install Docker Registry
echo "Installing Docker Registry..."
helm upgrade --install registry twuni/docker-registry \
  -n $NAMESPACE \
  -f values.yaml \
  --set persistence.storageClass=$STORAGE_CLASS

echo ""
echo "=== Installation Complete ==="

if [ "$IS_DOCKER_DESKTOP" = "false" ]; then
echo ""
echo "=========================================="
echo "IMPORTANT: Create directories on nodes BEFORE pods schedule:"
echo "=========================================="
echo "  # Infrastructure services"
echo "  mkdir -p ${DATA_DIR}/minio-{0,1,2,3}"
echo "  mkdir -p ${DATA_DIR}/registry"
echo ""
echo "  # Observability services (for observability stack)"
echo "  mkdir -p ${DATA_DIR}/victoriametrics-{0,1}"
echo "  mkdir -p ${DATA_DIR}/loki-{0,1,2}"
echo "  mkdir -p ${DATA_DIR}/grafana"
fi
echo ""
echo "=========================================="
echo "Access Information:"
echo "=========================================="
echo ""
echo "MinIO Console:"
echo "  kubectl port-forward svc/minio-console 9001:9001 -n $NAMESPACE"
echo "  URL: http://localhost:9001"
echo "  User: $MINIO_ROOT_USER"
echo ""
echo "MinIO API (for apps):"
echo "  http://minio.$NAMESPACE.svc.cluster.local:9000"
echo ""
echo "Docker Registry:"
echo "  kubectl port-forward svc/registry-docker-registry 5000:5000 -n $NAMESPACE"
echo "  Internal: registry-docker-registry.$NAMESPACE.svc.cluster.local:5000"
echo ""
echo "=========================================="
echo "Docker Push/Pull:"
echo "=========================================="
echo "To push images (after port-forward):"
echo "  docker tag myapp:latest localhost:5000/myapp:latest"
echo "  docker push localhost:5000/myapp:latest"
echo ""
echo "In Kubernetes deployments:"
echo "  image: registry-docker-registry.$NAMESPACE.svc.cluster.local:5000/myapp:latest"
echo "  imagePullSecrets:"
echo "    - name: regcred"
