# PostgreSQL Vault Dynamic Credentials Demo

This repository contains an application that demonstrates using HashiCorp Vault's dynamic secrets for PostgreSQL database access in a Kubernetes environment.

## Prerequisites

- Kubernetes cluster (e.g., AWS EKS)
- HashiCorp Vault server already deployed
- PostgreSQL database (e.g., AWS RDS)

## Architecture

The application uses the following components:

1. **HashiCorp Vault**: Generates dynamic, time-limited PostgreSQL credentials
2. **Vault Secret Operator (VSO)**: Requests credentials from Vault and creates Kubernetes secrets
3. **Kubernetes Secrets**: Store the dynamic credentials
4. **Python Application**: Uses credentials to connect to PostgreSQL
5. **Streamlit UI**: Displays the connection status and credential information

## Setup Instructions

### 1. Installing Vault Secret Operator CRDs

Before deploying the application, you need to install the Vault Secret Operator Custom Resource Definitions (CRDs) in your Kubernetes cluster:

#### Helm Installation (Recommended Method)

The primary method to install Vault Secret Operator with its CRDs is using Helm:

```bash
# Add the HashiCorp Helm repository
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

# Create the namespace for VSO
kubectl create namespace vault-secrets-operator-system

# Install Vault Secret Operator with your vso-values.yaml
helm install vault-secrets-operator hashicorp/vault-secrets-operator \
    -n vault-secrets-operator-system \
    --create-namespace \
    --values vso-values.yaml
```

#### Verification Steps

After installation, verify that the CRDs are properly installed:

```bash
kubectl get crds | grep vault
```

You should see CRDs like:
```
vaultauths.secrets.hashicorp.com                     2025-05-15T04:54:33Z
vaultconnections.secrets.hashicorp.com               2025-05-15T04:54:33Z
vaultdynamicsecrets.secrets.hashicorp.com            2025-05-15T04:54:33Z
vaultpkisecrets.secrets.hashicorp.com                2025-05-15T04:54:33Z
vaultstaticsecrets.secrets.hashicorp.com             2025-05-15T04:54:33Z
```

Also check that the operator pods are running:

```bash
kubectl get pods -n vault-secrets-operator-system
```

You should see output like:
```
NAME                                                        READY   STATUS    RESTARTS   AGE
vault-secrets-operator-controller-manager-d6f5df6c7-xj5jf   2/2     Running   0          5m
```

#### Manual Installation (Alternative Method)

If the Helm installation doesn't work, you can install the CRDs manually:

```bash
# Clone the Vault Secret Operator repository
git clone https://github.com/hashicorp/vault-secrets-operator.git
cd vault-secrets-operator

# Install the CRDs directly
kubectl apply -f config/crd/bases/
```

Then install the operator without CRDs:

```bash
helm install vault-secrets-operator hashicorp/vault-secrets-operator \
    -n vault-secrets-operator-system \
    --create-namespace \
    --set "installCRDs=false" \
    --values vso-values.yaml
```

#### Troubleshooting Installation

If you encounter issues:

1. Check Helm installation status:
   ```bash
   helm list -n vault-secrets-operator-system
   ```

2. Check for errors in the operator logs:
   ```bash
   kubectl logs -n vault-secrets-operator-system -l app.kubernetes.io/name=vault-secrets-operator
   ```

3. Verify CRD installation:
   ```bash
   kubectl api-resources | grep vault
   ```

### 2. Set up Vault Authentication

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

### 3. Set up Database Secrets Engine

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

### 4. Deploy the Application

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

### 5. Access the Application

The application will be available via:

- LoadBalancer service (if using AWS EKS)
- Ingress (if configured with your domain)

You can access the UI and test the PostgreSQL connection.

## How It Works

1. The VaultDynamicSecret resource requests credentials from Vault
2. Vault generates time-limited PostgreSQL credentials
3. VSO creates a Kubernetes Secret with these credentials
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

### Viewing Logs

```bash
# View Vault Secret Operator logs
kubectl logs -n vault-secrets-operator-system deploy/vault-secrets-operator-controller-manager

# View application logs
kubectl logs -n acme-demo deploy/acme-demo
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