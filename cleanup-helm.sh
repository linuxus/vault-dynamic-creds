#!/bin/bash
# Script to remove Vault Secret Operator and all related resources

echo "Removing Vault Secret Operator..."

# Step 1: Uninstall the Helm release
echo "Uninstalling Helm release..."
helm uninstall vault-secrets-operator -n vault-secrets-operator-system

# Step 2: Delete the namespace (this will take some time)
echo "Deleting namespace..."
kubectl delete namespace vault-secrets-operator-system --timeout=300s

# If the namespace is stuck in Terminating state, you might need to remove finalizers
# Uncomment if needed:
# NS_JSON=$(kubectl get namespace vault-secrets-operator-system -o json)
# echo $NS_JSON | jq '.spec.finalizers = null' > ns.json
# kubectl replace --raw "/api/v1/namespaces/vault-secrets-operator-system/finalize" -f ns.json

# Step 3: Delete CRDs
echo "Deleting Custom Resource Definitions..."
for CRD in vaultauths vaultconnections vaultdynamicsecrets vaultpkisecrets vaultstaticsecrets; do
  kubectl delete crd ${CRD}.secrets.hashicorp.com
done

# Step 4: Clean up RBAC resources
echo "Cleaning up RBAC resources..."
for RESOURCE in vault-secrets-operator-manager-role vault-secrets-operator-metrics-reader vault-secrets-operator-proxy-role; do
  kubectl delete clusterrole $RESOURCE 2>/dev/null || true
done

for BINDING in vault-secrets-operator-manager-rolebinding vault-secrets-operator-proxy-rolebinding; do
  kubectl delete clusterrolebinding $BINDING 2>/dev/null || true
done

# Additional cleanup for any custom resources you created
kubectl delete clusterrole vault-secrets-operator-auth 2>/dev/null || true
kubectl delete clusterrolebinding vault-secrets-operator-auth-binding 2>/dev/null || true

echo "Vault Secret Operator has been removed."

# # Check if VSO namespace exists
# kubectl get ns vault-secrets-operator-system

# # Check if VSO CRDs exist
# kubectl get crd | grep vault

# # Check if any VSO cluster roles exist
# kubectl get clusterrole | grep vault-secrets-operator