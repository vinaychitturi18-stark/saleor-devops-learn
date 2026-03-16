#!/usr/bin/env bash
# Usage: ./k8s/deploy.sh <dockerhub-username>
# Example: ./k8s/deploy.sh vinay123
#
# What this script does:
#  1. Substitutes DOCKERHUB_USER and INGRESS_CLUSTERIP placeholders in manifests
#  2. Applies all manifests to the cluster
#  3. Waits for postgres and saleor to be ready
#  4. Runs database migrations + collectstatic (one-time Job)

set -euo pipefail

DOCKERHUB_USER="${1:?Usage: $0 <dockerhub-username>}"
KUBECONFIG="${KUBECONFIG:-$HOME/.kube/saleor-k8s.conf}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

export KUBECONFIG

echo "==> Using Docker Hub user: $DOCKERHUB_USER"

# Get the nginx ingress controller ClusterIP (set after ingress-nginx is installed)
INGRESS_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx \
  -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")

if [ -z "$INGRESS_IP" ]; then
  echo "ERROR: ingress-nginx-controller service not found."
  echo "Install it first: kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.3/deploy/static/provider/baremetal/deploy.yaml"
  exit 1
fi
echo "==> Ingress ClusterIP: $INGRESS_IP"

# Apply manifests with substitutions applied via sed
for f in "$SCRIPT_DIR"/[0-9]*.yaml; do
  sed \
    -e "s|DOCKERHUB_USER|${DOCKERHUB_USER}|g" \
    -e "s|INGRESS_CLUSTERIP|${INGRESS_IP}|g" \
    "$f" | kubectl apply -f -
done

echo ""
echo "==> Waiting for postgres to be ready..."
kubectl rollout status deployment/postgres -n saleor --timeout=120s

echo "==> Waiting for saleor to be ready..."
kubectl rollout status deployment/saleor -n saleor --timeout=300s

echo ""
echo "==> All deployments are ready!"
echo ""

# Get NodePort for ingress
NODE_PORT=$(kubectl get svc ingress-nginx-controller -n ingress-nginx \
  -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[1].status.addresses[?(@.type=="InternalIP")].address}')

echo "==> Add this to your Mac's /etc/hosts:"
echo "    ${NODE_IP}  saleor.local"
echo ""
echo "==> Then access the stack at:"
echo "    Storefront : http://saleor.local:${NODE_PORT}/"
echo "    Dashboard  : http://saleor.local:${NODE_PORT}/dashboard/"
echo "    GraphQL    : http://saleor.local:${NODE_PORT}/graphql/"
