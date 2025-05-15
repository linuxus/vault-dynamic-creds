# Replace these values with your actual instance ID and RDS endpoint information
INSTANCE_ID="i-042ed745a6a219195"  # Your bastion EC2 instance ID
AWS_REGION="us-west-2"  # region to connect
RDS_ENDPOINT="acme-postgresql.cdci8e64uqvc.us-west-2.rds.amazonaws.com"
RDS_PORT=5432
LOCAL_PORT=5432  # Local port on your machine
aws ssm start-session \
    --target $INSTANCE_ID \
    --region $AWS_REGION \
    --document-name AWS-StartPortForwardingSessionToRemoteHost \
    --parameters "host=$RDS_ENDPOINT,portNumber=$RDS_PORT,localPortNumber=$LOCAL_PORT"
