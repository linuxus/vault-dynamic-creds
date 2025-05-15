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

# Configure Kubernetes endpoint
vault write auth/kubernetes/config \
  kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443"

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
  connection_url="postgresql://{{username}}:{{password}}@postgres-postgresql.postgres:5432/acme-demo" \
  username="vault" \
  password="vault"

# Create database role
vault write database/roles/acme-demo-role \
  db_name="acme-demo-pg-db" \
  creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; \
      GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
  default_ttl="1h" \
  max_ttl="24h"
```

### 3. Deploy the Application

Once Vault and the Vault Secret Operator are properly configured, deploy the application:

```bash
# Apply all Kubernetes manifests
kubectl apply -f kubernetes-manifests.yaml
```

Verify the deployment:

```bash
# Check if the VaultAuth and VaultDynamicSecret resources were created
kubectl get vaultauth -n acme-demo
kubectl get vaultdynamicsecret -n acme-demo

# Check if the Kubernetes Secret is populated
kubectl get secret postgres -n acme-demo

# Check if the pod is running
kubectl get pods -n acme-demo

# Check pod logs for any issues
kubectl logs -n acme-demo -l app=acme-demo
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

#### "No matches for kind" Error when Applying Manifests

If you see errors like:
```
resource mapping not found for name: "default" namespace: "acme-demo" from "kubernetes-manifests.yaml": no matches for kind "VaultAuth" in version "secrets.hashicorp.com/v1beta1"
ensure CRDs are installed first
```

This means the Custom Resource Definitions for Vault Secret Operator are not installed. Follow the installation instructions in Step 1.

#### Connection Failures

If the application can't connect to PostgreSQL:

1. Verify the Vault Secret Operator logs:
   ```bash
   kubectl logs -n vault-secrets-operator-system -l app.kubernetes.io/name=vault-secrets-operator
   ```

2. Check if the Secret was created and contains credentials:
   ```bash
   kubectl get secret postgres -n acme-demo -o yaml
   ```

3. Verify the bastion host can reach the RDS instance:
   ```bash
   # Get into a pod
   kubectl exec -it -n acme-demo <pod-name> -- bash
   
   # Test connection
   apt-get update && apt-get install -y netcat
   nc -zv <rds-endpoint> 5432
   ```

## Working with Private Subnets

If your RDS instance is in a private subnet (as it should be for security), you have several options to access it for initial setup:

### Option 1: Use an EC2 Instance as a Bastion Host

1. Launch an EC2 instance in the same VPC as your RDS
2. Set up the necessary security groups to allow access to RDS
3. Use the EC2 instance to create the vault user in PostgreSQL:

```bash
# Connect to the EC2 instance
ssh ec2-user@<bastion-ip>

# Install PostgreSQL client
sudo yum install -y postgresql

# Create the vault user
psql --host=<rds-endpoint> --port=5432 --username=<admin-user> --dbname=<db-name>
# Once connected, run:
CREATE ROLE vault WITH SUPERUSER LOGIN ENCRYPTED PASSWORD 'vault';
```

### Option 2: Use AWS Systems Manager Session Manager

If your EC2 instances are set up with SSM:

1. Configure VPC endpoints for SSM (ssm, ec2messages, ssmmessages)
2. Connect to an EC2 instance in the same VPC as RDS:

```bash
aws ssm start-session --target <instance-id>

# Then create the vault user as shown above
```

### Option 3: Use Port Forwarding through SSM

For direct access from your local machine:

```bash
# Start port forwarding
aws ssm start-session \
    --target <instance-id> \
    --document-name AWS-StartPortForwardingSessionToRemoteHost \
    --parameters "host=<rds-endpoint>,portNumber=5432,localPortNumber=5432"

# In another terminal:
psql --host=localhost --port=5432 --username=<admin-user> --dbname=<db-name>
```

### Viewing Logs

```bash
# View Vault Secret Operator logs
kubectl logs -n vault-secrets-operator-system deploy/vault-secrets-operator-controller-manager

# View application logs
kubectl logs -n acme-demo deploy/acme-demo
```

## Security Considerations

- **Credentials Management**: The vault user created in PostgreSQL should have minimal permissions needed
- **Network Security**: Keep your RDS in a private subnet and restrict access
- **Secrets TTL**: Configure appropriate TTL values for credentials (default is 1h in this demo)
- **IAM Permissions**: Ensure the EC2 instances have only the necessary IAM permissions
- **Audit Logging**: Enable audit logging in Vault to track credential generation and usage

## References

- [HashiCorp Vault Documentation](https://www.vaultproject.io/docs)
- [Vault Secret Operator Documentation](https://developer.hashicorp.com/vault/docs/platform/k8s/vso)
- [Kubernetes Secrets Documentation](https://kubernetes.io/docs/concepts/configuration/secret/)
- [Streamlit Documentation](https://docs.streamlit.io/)
