#!/bin/zsh
#
# Enhanced Vault Secret Operator Installation Script
# This script installs and configures Vault Secret Operator for Kubernetes
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
  echo "${BLUE}"
  echo "╔═════════════════════════════════════════════════════════════════════╗"
  echo "║                                                                     ║"
  echo "║           Vault Secret Operator Installation Script                 ║"
  echo "║                                                                     ║"
  echo "╚═════════════════════════════════════════════════════════════════════╝"
  echo "${NC}"
}

# Helper function to print section headers
function print_section() {
  echo "\n${PURPLE}==>${NC} ${CYAN}$1${NC}"
}

# Helper function for validation
function validate_command() {
  if ! command -v $1 &> /dev/null; then
    echo "${RED}Error:${NC} $1 is not installed or not found in PATH."
    exit 1
  fi
}

# Check if file exists
function check_file_exists() {
  if [[ ! -f $1 ]]; then
    echo "${RED}Error:${NC} File $1 not found."
    echo "Please create this file before running the script."
    exit 1
  fi
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

# Function to create default vso-values.yaml if it doesn't exist
function create_default_values() {
  if [[ ! -f "vso-values.yaml" ]]; then
    print_section "Creating default vso-values.yaml"
    
    cat > vso-values.yaml << EOF
# Default Vault Secret Operator values
defaultVaultConnection:
  enabled: true
  address: "http://vault-internal.vault.svc.cluster.local:8200"
  skipTLSVerify: false

defaultAuthMethod:
  enabled: true
  kubernetes:
    role: "vault-secrets-operator-role"
    serviceAccount:
      name: "vault-secrets-operator"
    path: "kubernetes"

# For production deployments, adjust resources as needed
controller:
  logLevel: info
  resources:
    limits:
      cpu: 500m
      memory: 256Mi
    requests:
      cpu: 100m
      memory: 128Mi
EOF
    
    echo "${GREEN}Created default vso-values.yaml file.${NC}"
    echo "${YELLOW}NOTE:${NC} Please review and update this file with your specific configuration before continuing."
    
    # Ask if the user wants to continue or edit the file
    echo "\nDo you want to continue with the default values or edit the file first?"
    select yn in "Continue" "Edit" "Exit"; do
      case $yn in
        Continue ) break;;
        Edit ) ${EDITOR:-vi} vso-values.yaml; break;;
        Exit ) exit;;
      esac
    done
  fi
}

# Function to check if VSO CRDs already exist
function check_crds_exist() {
  kubectl get crd vaultauths.secrets.hashicorp.com &> /dev/null
  return $?
}

# Function to check Vault connectivity
function check_vault_connectivity() {
  local vault_addr=$(grep "address:" vso-values.yaml | head -1 | awk '{print $2}' | tr -d '"')
  
  if [[ -z "$vault_addr" ]]; then
    echo "${YELLOW}Warning:${NC} Could not extract Vault address from vso-values.yaml"
    return 0
  fi
  
  # Remove http:// or https:// prefix for kubectl exec
  local vault_host=${vault_addr#*//}
  local vault_host=${vault_host%%:*}
  
  echo "${BLUE}Testing connectivity to Vault at ${vault_addr}...${NC}"
  
  # Try to connect to Vault using kubectl and curl from a temporary pod
  kubectl run vault-test --rm -it --restart=Never --image=curlimages/curl -- \
    curl -s -o /dev/null -w "%{http_code}" "${vault_addr}/v1/sys/health" || local exit_code=$?
  
  if [[ $exit_code -ne 0 ]]; then
    echo "${YELLOW}Warning:${NC} Could not connect to Vault. Please ensure Vault is running and accessible."
    echo "Do you want to continue anyway? [y/N]"
    read continue_install
    if [[ ! "$continue_install" =~ ^[Yy]$ ]]; then
      exit 1
    fi
  fi
}

# Main script

# Print banner
print_banner

# Initial validation
print_section "Performing initial validation"

# Check for required tools
validate_command kubectl
validate_command helm
validate_command jq
echo "${GREEN}✓${NC} Required tools are installed"

# Create or validate values file
create_default_values

# Check file exists
check_file_exists "vso-values.yaml"
echo "${GREEN}✓${NC} Configuration file vso-values.yaml exists"

# Add HashiCorp Helm repository
print_section "Adding HashiCorp Helm repository"
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update
echo "${GREEN}✓${NC} HashiCorp Helm repository added and updated"

# Check for pre-existing installation
print_section "Checking for existing installation"
VSO_NAMESPACE="vault-secrets-operator-system"

if check_helm_release_exists "vault-secrets-operator" "$VSO_NAMESPACE"; then
  echo "${YELLOW}Warning:${NC} Vault Secret Operator is already installed!"
  echo "Do you want to upgrade the existing installation? [y/N]"
  read upgrade_existing
  
  if [[ "$upgrade_existing" =~ ^[Yy]$ ]]; then
    print_section "Upgrading Vault Secret Operator"
    helm upgrade vault-secrets-operator hashicorp/vault-secrets-operator \
      -n $VSO_NAMESPACE \
      --values vso-values.yaml
    
    echo "${GREEN}✓${NC} Vault Secret Operator has been upgraded"
    exit 0
  else
    echo "Aborting installation. No changes were made."
    exit 0
  fi
fi

# Check if namespace exists, create if it doesn't
if ! check_namespace_exists "$VSO_NAMESPACE"; then
  print_section "Creating namespace $VSO_NAMESPACE"
  kubectl create namespace $VSO_NAMESPACE
  echo "${GREEN}✓${NC} Namespace $VSO_NAMESPACE created"
else
  echo "${BLUE}Namespace $VSO_NAMESPACE already exists${NC}"
fi

# Check Vault connectivity
check_vault_connectivity

# Install Vault Secret Operator
print_section "Installing Vault Secret Operator"
helm install vault-secrets-operator hashicorp/vault-secrets-operator \
  -n $VSO_NAMESPACE \
  --values vso-values.yaml

echo "${GREEN}✓${NC} Vault Secret Operator installed successfully"

# Verify installation
print_section "Verifying installation"

# Wait for the deployment to be ready
echo "Waiting for deployment to be ready..."
kubectl wait --for=condition=available --timeout=120s deployment/vault-secrets-operator-controller-manager -n $VSO_NAMESPACE || {
  echo "${RED}Error:${NC} Deployment did not become ready within the timeout period."
  echo "Please check the logs with: kubectl logs -n $VSO_NAMESPACE deploy/vault-secrets-operator-controller-manager"
  exit 1
}

# Check for CRDs
echo "Checking for Custom Resource Definitions..."
for CRD in vaultauths vaultconnections vaultdynamicsecrets vaultpkisecrets vaultstaticsecrets; do
  if kubectl get crd ${CRD}.secrets.hashicorp.com &> /dev/null; then
    echo "${GREEN}✓${NC} CRD ${CRD}.secrets.hashicorp.com is installed"
  else
    echo "${RED}✗${NC} CRD ${CRD}.secrets.hashicorp.com is not installed"
    MISSING_CRDS=true
  fi
done

if [[ $MISSING_CRDS == true ]]; then
  echo "${YELLOW}Warning:${NC} Some CRDs are missing. The installation may not be complete."
else
  echo "${GREEN}✓${NC} All required CRDs are installed"
fi

# Print post-installation information
print_section "Post-Installation Information"
echo "Vault Secret Operator has been installed in the $VSO_NAMESPACE namespace."
echo ""
echo "To check the status of the installation:"
echo "  kubectl get all -n $VSO_NAMESPACE"
echo ""
echo "To check the operator logs:"
echo "  kubectl logs -n $VSO_NAMESPACE deploy/vault-secrets-operator-controller-manager"
echo ""
echo "To uninstall the operator:"
echo "  helm uninstall vault-secrets-operator -n $VSO_NAMESPACE"
echo ""
echo "${GREEN}Installation complete!${NC}"