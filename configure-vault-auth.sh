#!/bin/bash
# This script properly configures Vault for Kubernetes authentication

# Exit on error
set -e

# Check for required parameters
if [ $# -lt 3 ]; then
    echo "Usage: $0 <db_username> <db_password> <rds_endpoint>"
    echo "Example: $0 vault vault123 postgres.example.com"
    exit 1
fi

# Get username and password from command line arguments
DB_USERNAME=$1
DB_PASSWORD=$2
RDS_ENDPOINT=$3

echo "Configuring Vault for Kubernetes authentication..."

# 1. Get Kubernetes API server address
API_SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
echo "Kubernetes API Server: $API_SERVER"

# 2. Create a service account token
if ! kubectl get serviceaccount vault-auth -n vault >/dev/null 2>&1; then
  echo "Creating vault-auth service account..."
  kubectl apply -f vault-auth-resources.yaml
fi

# 3. Get the service account token
echo "Obtaining token for vault-auth service account..."
TOKEN=$(kubectl create token vault-auth -n vault)

# 4. Get the Kubernetes CA certificate
echo "Extracting Kubernetes CA certificate..."
kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 --decode > ca.crt

# Enable Kubernetes auth backend
vault auth enable kubernetes

# 5. Configure Vault
echo "Configuring Vault Kubernetes auth method..."
vault write auth/kubernetes/config \
  token_reviewer_jwt="$TOKEN" \
  kubernetes_host="$API_SERVER" \
  kubernetes_ca_cert=@ca.crt \
  disable_local_ca_jwt=true

# 6. Create or update the role for the acme-demo service account
echo "Configuring Vault role for acme-demo-sa..."
vault write auth/kubernetes/role/acme-demo-role \
  bound_service_account_names=acme-demo-sa \
  bound_service_account_namespaces=acme-demo \
  policies=acme-demo-policy \
  ttl=1h

# 7. Create the necessary policy if it doesn't exist
if ! vault policy read acme-demo-policy >/dev/null 2>&1; then
  echo "Creating acme-demo-policy..."
  vault policy write acme-demo-policy - << EOF
path "database/creds/acme-demo-role" {
  capabilities = ["read"]
}
EOF
fi

# Configure PostgreSQL connection
vault write database/config/acme-demo-pg-db \
  plugin_name="postgresql-database-plugin" \
  allowed_roles="acme-demo-role" \
  connection_url="postgresql://{{username}}:{{password}}@$RDS_ENDPOINT:5432/acme-demo" \
  username="$DB_USERNAME" \
  password="$DB_PASSWORD"

# Create database role
vault write database/roles/acme-demo-role \
  db_name="acme-demo-pg-db" \
  creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; \
      GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
  default_ttl="15m" \
  max_ttl="30m"

echo "Vault configuration complete!"
echo "Testing authentication..."

# 8. Verify configuration by creating a test pod
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: vault-test
  namespace: acme-demo
spec:
  serviceAccountName: acme-demo-sa
  containers:
  - name: curl
    image: curlimages/curl
    command:
    - sleep
    - infinity
EOF

echo "Waiting for test pod to be ready..."
kubectl wait --for=condition=ready pod/vault-test -n acme-demo --timeout=60s

# 9. Test authentication
echo "Testing authentication from the pod..."
kubectl exec -it vault-test -n acme-demo -- sh -c "TOKEN=\$(cat /var/run/secrets/kubernetes.io/serviceaccount/token) && curl --silent --request POST --data '{\"jwt\": \"'\$TOKEN'\", \"role\": \"acme-demo-role\"}' http://vault-internal.vault.svc.cluster.local:8200/v1/auth/kubernetes/login | grep -q client_token && echo 'Authentication successful!' || echo 'Authentication failed!'"

echo "Configuration and testing complete. You can now apply your application manifests."