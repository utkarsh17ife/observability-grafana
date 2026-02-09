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

# Detect environment and use appropriate storage class
FIRST_NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if echo "$FIRST_NODE" | grep -q "docker-desktop"; then
  STORAGE_CLASS="${STORAGE_CLASS:-hostpath}"
  STANDALONE_MODE=true
  echo "Detected Docker Desktop - using hostpath storage class"
elif echo "$FIRST_NODE" | grep -qE "minikube|observability"; then
  STORAGE_CLASS="${STORAGE_CLASS:-standard}"
  STANDALONE_MODE=true
  echo "Detected Minikube - using standard storage class"
else
  STORAGE_CLASS="${STORAGE_CLASS:-local-storage}"
  STANDALONE_MODE=false
  echo "Production mode - using local-storage class"
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

# Skip local PV creation for Docker Desktop/Minikube (uses dynamic provisioner)
if [ "$STANDALONE_MODE" = "false" ]; then

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

# Create local PV for MinIO
echo "Creating Local Persistent Volume for MinIO..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: minio-pv-0
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
    path: ${DATA_DIR}/minio
  nodeAffinity:
    required:
      nodeSelectorTerms:
        - matchExpressions:
            - key: kubernetes.io/hostname
              operator: Exists
EOF

# Create local PV for VictoriaMetrics
echo "Creating Local Persistent Volume for VictoriaMetrics..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: victoriametrics-pv-0
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
    path: ${DATA_DIR}/victoriametrics
  nodeAffinity:
    required:
      nodeSelectorTerms:
        - matchExpressions:
            - key: kubernetes.io/hostname
              operator: Exists
EOF

else
  echo "Skipping local PV creation (using dynamic provisioner)"
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
if [ "$STANDALONE_MODE" = "true" ]; then
  # Standalone mode for Docker Desktop / Minikube (single replica)
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
    --set service.type=ClusterIP \
    --set securityContext.runAsUser=0 \
    --set securityContext.runAsGroup=0 \
    --set securityContext.fsGroup=0
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

if [ "$STANDALONE_MODE" = "false" ]; then
echo ""
echo "=========================================="
echo "IMPORTANT: Create directories on nodes BEFORE pods schedule:"
echo "=========================================="
echo "  mkdir -p ${DATA_DIR}/minio"
echo "  mkdir -p ${DATA_DIR}/victoriametrics"
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
