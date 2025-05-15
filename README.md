# PostgreSQL Vault Dynamic Credentials Demo

This repository contains an application that demonstrates using HashiCorp Vault's dynamic secrets for PostgreSQL database access in a Kubernetes environment.

## Prerequisites

- Kubernetes cluster (e.g., AWS EKS)
- HashiCorp Vault server already deployed
- Vault Secret Operator installed
- PostgreSQL database (e.g., AWS RDS)

## Architecture

The application uses the following components:

1. **HashiCorp Vault**: Generates dynamic, time-limited PostgreSQL credentials
2. **Vault Secret Operator (VSO)**: Requests credentials from Vault and creates Kubernetes secrets
3. **Kubernetes Secrets**: Store the dynamic credentials
4. **Python Application**: Uses credentials to connect to PostgreSQL
5. **Streamlit UI**: Displays the connection status and credential information

## Features

- Dynamic credential generation with automatic rotation
- Real-time monitoring of credential status and expiration
- Visual feedback when credentials are rotated
- Kubernetes-native deployment
- Streamlit web interface

## Setup Instructions

### 1. Set up Vault Authentication

Configure Vault's Kubernetes authentication:

```bash
# Enable Kubernetes auth backend
vault auth enable kubernetes

# Get the Kubernetes API server address
# Make sure you're authenticated against your EKS cluster
API_SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')

# Configure Vault
vault write auth/kubernetes/config \
  kubernetes_host="$API_SERVER"

# Create a Vault policy for database access
vault policy write acme-demo-policy - <<EOF
path "database/creds/acme-demo-role" {
  capabilities = ["read"]
}
EOF

# Create a role for the Kubernetes service account
vault write auth/kubernetes/role/acme-demo-role \
  bound_service_account_names=acme-demo-sa \
  bound_service_account_namespaces=acme-demo \
  policies=acme-demo-policy \
  ttl=1h
```

### 2. Set up Database Secrets Engine

```bash
# Enable database secrets engine
vault secrets enable database

# Configure PostgreSQL connection
vault write database/config/acme-demo-pg-db \
  plugin_name="postgresql-database-plugin" \
  allowed_roles="acme-demo-role" \
  connection_url="postgresql://{{username}}:{{password}}@postgres-postgresql.postgres:5432/acmedemo" \
  username="vault" \
  password="vault"

# Create database role
# Note that ttl and max_ttl are set to 1m for testing purposes but should be set something 1h and 24h respectively.
vault write database/roles/acme-demo-role \
  db_name="acme-demo-pg-db" \
  creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; \
      GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
  default_ttl="1m" \
  max_ttl="1m"
```

### 3. Deploy the Application

```bash
# Apply all Kubernetes manifests
kubectl apply -f kubernetes-manifests.yaml
```

### 4. Access the Application

The application will be available via:

- LoadBalancer service (if using AWS EKS)
- Ingress (if configured with your domain)

You can access the UI and test the PostgreSQL connection.

## Docker Image

The repository includes a Dockerfile to build your own image:

```bash
docker build -t your-repo/postgres-vault-app:latest .
```

Or use the provided base image:

```yaml
image: amancevice/pandas:1.3.0-slim
```

## How It Works

1. The VaultDynamicSecret resource requests credentials from Vault
2. Vault generates time-limited PostgreSQL credentials
3. Vault Secret Operator creates/updates a Kubernetes Secret
4. The application pod uses these credentials to connect to PostgreSQL
5. Before credentials expire, VSO requests new credentials
6. When credentials are updated, the deployment is automatically restarted

## Troubleshooting

### Common Issues

1. **Connection Failure**: Check that the PostgreSQL host is correctly configured and accessible
2. **Authentication Error**: Ensure the Vault role and policy are properly configured
3. **Secret Not Found**: Verify that the VaultDynamicSecret resource is correctly configured
4. **Permission Error**: Check that the service account has the necessary permissions

### Viewing Logs

```bash
# View Vault Secret Operator logs
kubectl logs -n vault-secrets-operator-system deploy/vault-secrets-operator-controller-manager

# View application logs
kubectl logs -n acme-demo deploy/acme-demo
```

## Security Considerations

- This demo uses a simplified approach for illustration purposes
- In production:
  - Use proper secret management with encrypted secrets
  - Implement network policies to restrict access
  - Use a dedicated service account with minimal permissions
  - Configure more restrictive database permissions

## References

- [HashiCorp Vault Documentation](https://www.vaultproject.io/docs)
- [Vault Secret Operator Documentation](https://developer.hashicorp.com/vault/docs/platform/k8s/vso)
- [Kubernetes Secrets Documentation](https://kubernetes.io/docs/concepts/configuration/secret/)
- [Streamlit Documentation](https://docs.streamlit.io/)
