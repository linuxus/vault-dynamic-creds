#!/bin/zsh
#
# Vault Secret Operator Cleanup Script
# This script removes all VSO components from your Kubernetes cluster
#

# Terminal colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Set error handling
set -e

# Banner function
function print_banner() {
  echo "${RED}"
  echo "╔═════════════════════════════════════════════════════════════════════╗"
  echo "║                                                                     ║"
  echo "║           Vault Secret Operator Cleanup Script                      ║"
  echo "║                                                                     ║"
  echo "╚═════════════════════════════════════════════════════════════════════╝"
  echo "${NC}"
}

# Helper function to print section headers
function print_section() {
  echo "\n${PURPLE}==>${NC} ${CYAN}$1${NC}"
}

# Function to check if namespace exists
function check_namespace_exists() {
  kubectl get namespace $1 &> /dev/null
  return $?
}

# Function to check if Helm release exists
function check_helm_release_exists() {
  helm status $1 -n $2 &> /dev/null
  return $?
}

# Function to check if CRDs exist
function check_crd_exists() {
  kubectl get crd $1 &> /dev/null
  return $?
}

# Main script
print_banner

echo "${YELLOW}Warning:${NC} This script will remove Vault Secret Operator and all related resources."
echo "This action is irreversible. All VSO managed secrets will be deleted."
echo ""
echo "Do you want to proceed? [y/N]"
read confirm_cleanup

if [[ ! "$confirm_cleanup" =~ ^[Yy]$ ]]; then
  echo "Cleanup aborted. No changes were made."
  exit 0
fi

VSO_NAMESPACE="vault-secrets-operator-system"

# Check if VSO is installed
print_section "Checking for VSO installation"

if ! check_namespace_exists "$VSO_NAMESPACE"; then
  echo "${YELLOW}Warning:${NC} Namespace $VSO_NAMESPACE does not exist."
  echo "VSO might not be installed or was installed in a different namespace."
  
  echo "Do you want to specify a different namespace? [y/N]"
  read change_namespace
  
  if [[ "$change_namespace" =~ ^[Yy]$ ]]; then
    echo "Enter the namespace where VSO is installed:"
    read VSO_NAMESPACE
    
    if ! check_namespace_exists "$VSO_NAMESPACE"; then
      echo "${RED}Error:${NC} Namespace $VSO_NAMESPACE does not exist."
      exit 1
    fi
  else
    echo "Checking for CRDs anyway..."
  fi
fi

# Check for VSO Helm release
if check_namespace_exists "$VSO_NAMESPACE" && check_helm_release_exists "vault-secrets-operator" "$VSO_NAMESPACE"; then
  HAS_HELM_RELEASE=true
  echo "${GREEN}✓${NC} Found VSO Helm release in namespace $VSO_NAMESPACE"
else
  HAS_HELM_RELEASE=false
  echo "${YELLOW}Note:${NC} No VSO Helm release found in namespace $VSO_NAMESPACE"
fi

# Check for VSO CRDs
VSO_CRDS=(
  "vaultauths.secrets.hashicorp.com"
  "vaultconnections.secrets.hashicorp.com"
  "vaultdynamicsecrets.secrets.hashicorp.com"
  "vaultpkisecrets.secrets.hashicorp.com"
  "vaultstaticsecrets.secrets.hashicorp.com"
)

HAS_CRDS=false
for CRD in "${VSO_CRDS[@]}"; do
  if check_crd_exists "$CRD"; then
    HAS_CRDS=true
    echo "${GREEN}✓${NC} Found CRD: $CRD"
  fi
done

if [[ "$HAS_HELM_RELEASE" == "false" && "$HAS_CRDS" == "false" ]]; then
  echo "${YELLOW}Warning:${NC} No VSO components found. Nothing to clean up."
  echo "Do you want to proceed anyway? [y/N]"
  read proceed_anyway
  
  if [[ ! "$proceed_anyway" =~ ^[Yy]$ ]]; then
    echo "Cleanup aborted. No changes were made."
    exit 0
  fi
fi

# Find all namespaces with VSO resources
print_section "Checking for VSO resources across all namespaces"

VSO_RESOURCES_NAMESPACES=()

echo "Looking for VaultAuth resources..."
VAULTAUTH_NAMESPACES=$(kubectl get vaultauth --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}{"\n"}{end}' 2>/dev/null | sort -u) || true

echo "Looking for VaultDynamicSecret resources..."
VAULTDYNAMIC_NAMESPACES=$(kubectl get vaultdynamicsecret --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}{"\n"}{end}' 2>/dev/null | sort -u) || true

echo "Looking for VaultStaticSecret resources..."
VAULTSTATIC_NAMESPACES=$(kubectl get vaultstaticsecret --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}{"\n"}{end}' 2>/dev/null | sort -u) || true

# Combine all unique namespaces
for NS in $(echo -e "${VAULTAUTH_NAMESPACES}\n${VAULTDYNAMIC_NAMESPACES}\n${VAULTSTATIC_NAMESPACES}" | sort -u); do
  if [[ -n "$NS" ]]; then
    VSO_RESOURCES_NAMESPACES+=("$NS")
    echo "${YELLOW}!${NC} Found VSO resources in namespace: $NS"
  fi
done

if [[ ${#VSO_RESOURCES_NAMESPACES[@]} -gt 0 ]]; then
  echo ""
  echo "${YELLOW}Warning:${NC} VSO resources were found in the above namespaces."
  echo "These resources will stop functioning after VSO is removed."
  echo ""
  echo "Do you want to delete these VSO resources before removing the operator? [Y/n]"
  read delete_resources
  
  if [[ ! "$delete_resources" =~ ^[Nn]$ ]]; then
    print_section "Deleting VSO resources from all namespaces"
    
    for NS in "${VSO_RESOURCES_NAMESPACES[@]}"; do
      echo "Deleting VSO resources in namespace: $NS"
      
      # Delete VSO resources in this namespace
      kubectl delete vaultdynamicsecret --all -n "$NS" 2>/dev/null || true
      kubectl delete vaultstaticsecret --all -n "$NS" 2>/dev/null || true
      kubectl delete vaultauth --all -n "$NS" 2>/dev/null || true
      kubectl delete vaultpkisecret --all -n "$NS" 2>/dev/null || true
      
      echo "${GREEN}✓${NC} Deleted VSO resources in namespace: $NS"
    done
  fi
fi

# Uninstall VSO Helm release
if [[ "$HAS_HELM_RELEASE" == "true" ]]; then
  print_section "Uninstalling VSO Helm release"
  
  helm uninstall vault-secrets-operator -n "$VSO_NAMESPACE"
  echo "${GREEN}✓${NC} VSO Helm release uninstalled"
  
  # Wait a moment before deleting the namespace
  echo "Waiting for Helm release deletion to complete..."
  sleep 5
fi

# Delete namespace
if check_namespace_exists "$VSO_NAMESPACE"; then
  print_section "Deleting VSO namespace"
  
  kubectl delete namespace "$VSO_NAMESPACE" --timeout=60s || {
    echo "${YELLOW}Warning:${NC} Namespace deletion timed out. This is common if resources are still terminating."
    echo "The namespace will be deleted automatically when all resources are terminated."
    
    echo "Do you want to force delete the namespace? [y/N]"
    read force_delete
    
    if [[ "$force_delete" =~ ^[Yy]$ ]]; then
      echo "Attempting to force delete namespace by removing finalizers..."
      kubectl get namespace "$VSO_NAMESPACE" -o json | jq '.spec.finalizers = []' > /tmp/temp_ns.json
      kubectl replace --raw "/api/v1/namespaces/$VSO_NAMESPACE/finalize" -f /tmp/temp_ns.json || {
        echo "${RED}Error:${NC} Could not force delete namespace."
        echo "You may need to manually check what resources are preventing deletion:"
        echo "kubectl api-resources --verbs=list --namespaced -o name | xargs -n 1 kubectl get -n $VSO_NAMESPACE"
      }
      rm -f /tmp/temp_ns.json
    fi
  }
  
  echo "Namespace deletion initiated."
fi

# Delete CRDs
if [[ "$HAS_CRDS" == "true" ]]; then
  print_section "Deleting VSO Custom Resource Definitions"
  
  for CRD in "${VSO_CRDS[@]}"; do
    if check_crd_exists "$CRD"; then
      echo "Deleting CRD: $CRD"
      kubectl delete crd "$CRD" || {
        echo "${YELLOW}Warning:${NC} Could not delete CRD: $CRD"
        echo "You may need to manually delete it later."
      }
    fi
  done
  
  echo "${GREEN}✓${NC} VSO CRDs deleted"
fi

# Delete RBAC resources
print_section "Cleaning up RBAC resources"

CLUSTER_ROLES=(
  "vault-secrets-operator-manager-role"
  "vault-secrets-operator-metrics-reader"
  "vault-secrets-operator-proxy-role"
  "vault-secrets-operator-auth"
)

CLUSTER_ROLE_BINDINGS=(
  "vault-secrets-operator-manager-rolebinding"
  "vault-secrets-operator-proxy-rolebinding"
  "vault-secrets-operator-auth-binding"
)

for CR in "${CLUSTER_ROLES[@]}"; do
  kubectl delete clusterrole "$CR" 2>/dev/null || true
done

for CRB in "${CLUSTER_ROLE_BINDINGS[@]}"; do
  kubectl delete clusterrolebinding "$CRB" 2>/dev/null || true
done

echo "${GREEN}✓${NC} RBAC resources cleaned up"

# Verify cleanup
print_section "Verifying cleanup"

ALL_REMOVED=true

# Check if namespace still exists
if check_namespace_exists "$VSO_NAMESPACE"; then
  echo "${YELLOW}Warning:${NC} Namespace $VSO_NAMESPACE still exists."
  echo "It may be in the process of terminating. Check status with:"
  echo "kubectl get namespace $VSO_NAMESPACE"
  ALL_REMOVED=false
fi

# Check if CRDs still exist
for CRD in "${VSO_CRDS[@]}"; do
  if check_crd_exists "$CRD"; then
    echo "${YELLOW}Warning:${NC} CRD $CRD still exists."
    ALL_REMOVED=false
  fi
done

# Final status
if [[ "$ALL_REMOVED" == "true" ]]; then
  echo "${GREEN}Vault Secret Operator has been completely removed from the cluster.${NC}"
else
  echo "${YELLOW}Some VSO components may still be in the process of being removed.${NC}"
  echo "You may need to check again later or manually remove remaining components."
fi

echo ""
echo "Cleanup process complete!"