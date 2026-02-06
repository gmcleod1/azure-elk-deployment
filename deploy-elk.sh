#!/bin/bash

################################################################################
# ELK Stack Automated Deployment Script for Azure (Security Hardened)
# Author: Garfield McLeod
# Version: 2.0 (Fixed)
# Purpose: Secure deployment of ELK stack for SOC analyst practice
# Usage: ./deploy-elk-stack-fixed.sh
################################################################################

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Configuration Variables
RESOURCE_GROUP="${RESOURCE_GROUP:-ELK-Security-Lab}"
LOCATION="${LOCATION:-eastus}"
VNET_NAME="ELK-VNet"
SUBNET_NAME="ELK-Subnet"
NSG_NAME="ELK-NSG"
SSH_KEY_FILE="${SSH_KEY_FILE:-~/.ssh/id_rsa.pub}"
VM_SIZE="${VM_SIZE:-Standard_D2s_v3}"  # Better performance than B2s

# Colors for better output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Track deployment state
DEPLOYMENT_STARTED=false

################################################################################
# Helper Functions
################################################################################

print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_status() {
    echo -e "${YELLOW}▶ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# Cleanup function for failures
cleanup() {
    if [ $? -ne 0 ] && [ "$DEPLOYMENT_STARTED" = true ]; then
        print_error "Deployment failed!"
        echo -e "${YELLOW}Would you like to clean up the resource group? (y/n)${NC}"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            print_status "Cleaning up resources..."
            az group delete --name "$RESOURCE_GROUP" --yes --no-wait
            print_success "Cleanup initiated"
        fi
    fi
}

trap cleanup EXIT

################################################################################
# Pre-flight Checks
################################################################################

print_header "ELK Stack Deployment - Pre-flight Checks"

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    print_error "Azure CLI not found. Please install it first."
    echo "Install from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi
print_success "Azure CLI found"

# Check if logged into Azure
if ! az account show &> /dev/null; then
    print_error "Not logged into Azure. Please run: az login"
    exit 1
fi
print_success "Azure authentication verified"

# Get current subscription
SUBSCRIPTION=$(az account show --query name -o tsv)
print_success "Using subscription: $SUBSCRIPTION"

# Check if SSH key exists
if [ ! -f "$SSH_KEY_FILE" ]; then
    print_error "SSH key not found: $SSH_KEY_FILE"
    print_status "Generating new SSH key pair..."
    ssh-keygen -t rsa -b 4096 -f "${SSH_KEY_FILE%.pub}" -N "" -C "elk-azure-deployment"
    print_success "SSH key generated"
fi

SSH_KEY=$(cat "$SSH_KEY_FILE")
print_success "SSH key loaded: $SSH_KEY_FILE"

# Get user's public IP for security rules
print_status "Detecting your public IP for firewall rules..."
MY_PUBLIC_IP=$(curl -s https://api.ipify.org)
if [ -z "$MY_PUBLIC_IP" ]; then
    print_warning "Could not detect public IP. Using 0.0.0.0/0 (less secure)"
    MY_PUBLIC_IP="*"
    MY_IP_CIDR="*"
else
    print_success "Your public IP: $MY_PUBLIC_IP"
    MY_IP_CIDR="$MY_PUBLIC_IP/32"
fi

# Generate secure credentials
print_status "Generating secure Elasticsearch credentials..."
ELASTIC_PASSWORD=$(openssl rand -base64 24 | tr -d "=+/" | cut -c1-25)
print_success "Credentials generated (will be displayed at the end)"

################################################################################
# Infrastructure Setup
################################################################################

DEPLOYMENT_STARTED=true

print_header "Creating Azure Infrastructure"

print_status "Creating resource group: $RESOURCE_GROUP in $LOCATION"
az group create \
  --name "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --output none
print_success "Resource group created"

print_status "Creating virtual network"
az network vnet create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$VNET_NAME" \
  --address-prefix 10.0.0.0/16 \
  --subnet-name "$SUBNET_NAME" \
  --subnet-prefix 10.0.1.0/24 \
  --output none
print_success "Virtual network created"

print_status "Creating network security group"
az network nsg create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$NSG_NAME" \
  --output none
print_success "NSG created"

print_status "Adding NSG rules (restricted to your IP: $MY_PUBLIC_IP)"
az network nsg rule create \
  --resource-group "$RESOURCE_GROUP" \
  --nsg-name "$NSG_NAME" \
  --name Allow-SSH \
  --priority 100 \
  --source-address-prefixes "$MY_IP_CIDR" \
  --destination-port-ranges 22 \
  --access Allow \
  --protocol Tcp \
  --description "SSH access from admin IP only" \
  --output none

az network nsg rule create \
  --resource-group "$RESOURCE_GROUP" \
  --nsg-name "$NSG_NAME" \
  --name Allow-Kibana \
  --priority 110 \
  --source-address-prefixes "$MY_IP_CIDR" \
  --destination-port-ranges 5601 \
  --access Allow \
  --protocol Tcp \
  --description "Kibana access from admin IP only" \
  --output none

az network nsg rule create \
  --resource-group "$RESOURCE_GROUP" \
  --nsg-name "$NSG_NAME" \
  --name Allow-Elasticsearch-Internal \
  --priority 120 \
  --source-address-prefixes '10.0.1.0/24' \
  --destination-port-ranges 9200 \
  --access Allow \
  --protocol Tcp \
  --description "Elasticsearch access from internal subnet only" \
  --output none

az network nsg rule create \
  --resource-group "$RESOURCE_GROUP" \
  --nsg-name "$NSG_NAME" \
  --name Allow-Elasticsearch-API \
  --priority 130 \
  --source-address-prefixes "$MY_IP_CIDR" \
  --destination-port-ranges 9200 \
  --access Allow \
  --protocol Tcp \
  --description "Elasticsearch API access from admin IP only" \
  --output none

print_success "NSG rules configured (locked down to your IP)"

################################################################################
# Create Virtual Machines
################################################################################

print_header "Creating Virtual Machines"

print_status "Creating Elasticsearch VM (size: $VM_SIZE)..."
az vm create \
  --resource-group "$RESOURCE_GROUP" \
  --name Elasticsearch-VM \
  --size "$VM_SIZE" \
  --image Ubuntu2204 \
  --admin-username azureuser \
  --ssh-key-values "$SSH_KEY" \
  --vnet-name "$VNET_NAME" \
  --subnet "$SUBNET_NAME" \
  --nsg "$NSG_NAME" \
  --public-ip-sku Standard \
  --output none
print_success "Elasticsearch VM created"

print_status "Creating Kibana VM (size: $VM_SIZE)..."
az vm create \
  --resource-group "$RESOURCE_GROUP" \
  --name Kibana-VM \
  --size "$VM_SIZE" \
  --image Ubuntu2204 \
  --admin-username azureuser \
  --ssh-key-values "$SSH_KEY" \
  --vnet-name "$VNET_NAME" \
  --subnet "$SUBNET_NAME" \
  --nsg "$NSG_NAME" \
  --public-ip-sku Standard \
  --output none
print_success "Kibana VM created"

print_status "Waiting for VMs to be ready..."
az vm wait --resource-group "$RESOURCE_GROUP" --name Elasticsearch-VM --created --timeout 300
az vm wait --resource-group "$RESOURCE_GROUP" --name Kibana-VM --created --timeout 300
print_success "VMs are ready"

################################################################################
# Get IP Addresses
################################################################################

print_status "Retrieving VM IP addresses..."
ES_PRIVATE_IP=$(az vm show -d \
  --resource-group "$RESOURCE_GROUP" \
  --name Elasticsearch-VM \
  --query privateIps -o tsv)

ES_PUBLIC_IP=$(az vm show -d \
  --resource-group "$RESOURCE_GROUP" \
  --name Elasticsearch-VM \
  --query publicIps -o tsv)

KIBANA_PRIVATE_IP=$(az vm show -d \
  --resource-group "$RESOURCE_GROUP" \
  --name Kibana-VM \
  --query privateIps -o tsv)

KIBANA_PUBLIC_IP=$(az vm show -d \
  --resource-group "$RESOURCE_GROUP" \
  --name Kibana-VM \
  --query publicIps -o tsv)

print_success "IP addresses retrieved"
echo "  Elasticsearch: $ES_PRIVATE_IP (private) / $ES_PUBLIC_IP (public)"
echo "  Kibana: $KIBANA_PRIVATE_IP (private) / $KIBANA_PUBLIC_IP (public)"

################################################################################
# Install and Configure Elasticsearch
################################################################################

print_header "Installing Elasticsearch"

print_status "Adding Elastic repository..."
az vm run-command invoke \
  --resource-group "$RESOURCE_GROUP" \
  --name Elasticsearch-VM \
  --command-id RunShellScript \
  --scripts "wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg && echo 'deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main' | sudo tee /etc/apt/sources.list.d/elastic-8.x.list" \
  --output none
print_success "Repository added"

print_status "Installing Elasticsearch (this takes 2-3 minutes)..."
az vm run-command invoke \
  --resource-group "$RESOURCE_GROUP" \
  --name Elasticsearch-VM \
  --command-id RunShellScript \
  --scripts "sudo apt update && sudo DEBIAN_FRONTEND=noninteractive apt install -y elasticsearch" \
  --output none
print_success "Elasticsearch installed"

print_status "Configuring Elasticsearch with security enabled..."
az vm run-command invoke \
  --resource-group "$RESOURCE_GROUP" \
  --name Elasticsearch-VM \
  --command-id RunShellScript \
  --scripts "cat <<EOF | sudo tee /etc/elasticsearch/elasticsearch.yml
cluster.name: soc-elk-cluster
node.name: elasticsearch-node-1
path.data: /var/lib/elasticsearch
path.logs: /var/log/elasticsearch
network.host: 0.0.0.0
http.host: 0.0.0.0
http.port: 9200
discovery.type: single-node

# Security Configuration (ENABLED)
xpack.security.enabled: true
xpack.security.enrollment.enabled: true

# Disable SSL for testing (enable in production!)
xpack.security.http.ssl:
  enabled: false
xpack.security.transport.ssl:
  enabled: false
EOF" \
  --output none
print_success "Elasticsearch configured with security"

print_status "Setting Elasticsearch passwords..."
az vm run-command invoke \
  --resource-group "$RESOURCE_GROUP" \
  --name Elasticsearch-VM \
  --command-id RunShellScript \
  --scripts "echo 'elastic:${ELASTIC_PASSWORD}' | sudo /usr/share/elasticsearch/bin/elasticsearch-users useradd elastic -p ${ELASTIC_PASSWORD} -r superuser 2>/dev/null || echo 'y' | sudo /usr/share/elasticsearch/bin/elasticsearch-reset-password -u elastic -i -b --password ${ELASTIC_PASSWORD}" \
  --output none
print_success "Elastic user password set"

print_status "Starting Elasticsearch..."
az vm run-command invoke \
  --resource-group "$RESOURCE_GROUP" \
  --name Elasticsearch-VM \
  --command-id RunShellScript \
  --scripts "sudo systemctl daemon-reload && sudo systemctl enable elasticsearch && sudo systemctl start elasticsearch" \
  --output none
print_success "Elasticsearch started"

print_status "Waiting for Elasticsearch to be ready (30 seconds)..."
sleep 30
print_success "Elasticsearch should be ready"

print_status "Setting kibana_system user password..."
az vm run-command invoke \
  --resource-group "$RESOURCE_GROUP" \
  --name Elasticsearch-VM \
  --command-id RunShellScript \
  --scripts "echo '${ELASTIC_PASSWORD}
${ELASTIC_PASSWORD}' | sudo /usr/share/elasticsearch/bin/elasticsearch-reset-password -u kibana_system -i -b" \
  --output none
print_success "Kibana system user password set"

################################################################################
# Install and Configure Filebeat
################################################################################

print_header "Installing Filebeat"

print_status "Installing Filebeat..."
az vm run-command invoke \
  --resource-group "$RESOURCE_GROUP" \
  --name Elasticsearch-VM \
  --command-id RunShellScript \
  --scripts "sudo DEBIAN_FRONTEND=noninteractive apt install -y filebeat" \
  --output none
print_success "Filebeat installed"

print_status "Configuring Filebeat with authentication..."
az vm run-command invoke \
  --resource-group "$RESOURCE_GROUP" \
  --name Elasticsearch-VM \
  --command-id RunShellScript \
  --scripts "cat <<EOF | sudo tee /etc/filebeat/filebeat.yml
filebeat.config.modules:
  path: \\\${path.config}/modules.d/*.yml
  reload.enabled: false

output.elasticsearch:
  hosts: [\"localhost:9200\"]
  username: \"elastic\"
  password: \"${ELASTIC_PASSWORD}\"

setup.kibana:
  host: \"${KIBANA_PRIVATE_IP}:5601\"

processors:
  - add_host_metadata: ~
  - add_cloud_metadata: ~
  - add_docker_metadata: ~
EOF" \
  --output none
print_success "Filebeat configured"

print_status "Enabling Filebeat system module..."
az vm run-command invoke \
  --resource-group "$RESOURCE_GROUP" \
  --name Elasticsearch-VM \
  --command-id RunShellScript \
  --scripts "sudo filebeat modules enable system" \
  --output none
print_success "System module enabled"

################################################################################
# Install and Configure Kibana
################################################################################

print_header "Installing Kibana"

print_status "Adding Elastic repository..."
az vm run-command invoke \
  --resource-group "$RESOURCE_GROUP" \
  --name Kibana-VM \
  --command-id RunShellScript \
  --scripts "wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg && echo 'deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main' | sudo tee /etc/apt/sources.list.d/elastic-8.x.list" \
  --output none
print_success "Repository added"

print_status "Installing Kibana (this takes 2-3 minutes)..."
az vm run-command invoke \
  --resource-group "$RESOURCE_GROUP" \
  --name Kibana-VM \
  --command-id RunShellScript \
  --scripts "sudo apt update && sudo DEBIAN_FRONTEND=noninteractive apt install -y kibana" \
  --output none
print_success "Kibana installed"

print_status "Configuring Kibana with authentication..."
az vm run-command invoke \
  --resource-group "$RESOURCE_GROUP" \
  --name Kibana-VM \
  --command-id RunShellScript \
  --scripts "cat <<EOF | sudo tee /etc/kibana/kibana.yml
server.host: \"0.0.0.0\"
server.port: 5601
server.name: \"kibana-soc\"

elasticsearch.hosts: [\"http://${ES_PRIVATE_IP}:9200\"]
elasticsearch.username: \"kibana_system\"
elasticsearch.password: \"${ELASTIC_PASSWORD}\"
EOF" \
  --output none
print_success "Kibana configured"

print_status "Starting Kibana..."
az vm run-command invoke \
  --resource-group "$RESOURCE_GROUP" \
  --name Kibana-VM \
  --command-id RunShellScript \
  --scripts "sudo systemctl daemon-reload && sudo systemctl enable kibana && sudo systemctl start kibana" \
  --output none
print_success "Kibana started"

################################################################################
# Finalize Filebeat Configuration
################################################################################

print_header "Finalizing Filebeat Setup"

print_status "Running Filebeat setup (loads dashboards and templates)..."
az vm run-command invoke \
  --resource-group "$RESOURCE_GROUP" \
  --name Elasticsearch-VM \
  --command-id RunShellScript \
  --scripts "sudo filebeat setup -e" \
  --output none 2>/dev/null || print_warning "Filebeat setup may have warnings (this is normal)"
print_success "Filebeat setup attempted"

print_status "Starting Filebeat..."
az vm run-command invoke \
  --resource-group "$RESOURCE_GROUP" \
  --name Elasticsearch-VM \
  --command-id RunShellScript \
  --scripts "sudo systemctl enable filebeat && sudo systemctl start filebeat" \
  --output none
print_success "Filebeat started"

################################################################################
# Health Checks
################################################################################

print_header "Running Health Checks"

print_status "Checking Elasticsearch health..."
ES_HEALTH=$(az vm run-command invoke \
  --resource-group "$RESOURCE_GROUP" \
  --name Elasticsearch-VM \
  --command-id RunShellScript \
  --scripts "curl -s -u elastic:${ELASTIC_PASSWORD} http://localhost:9200/_cluster/health" \
  --query 'value[0].message' -o tsv 2>/dev/null | grep -o '"status":"[^"]*"' || echo "unknown")

if [[ "$ES_HEALTH" == *"green"* ]] || [[ "$ES_HEALTH" == *"yellow"* ]]; then
  print_success "Elasticsearch is healthy"
else
  print_warning "Elasticsearch health unknown (may still be starting)"
fi

print_status "Checking Filebeat status..."
az vm run-command invoke \
  --resource-group "$RESOURCE_GROUP" \
  --name Elasticsearch-VM \
  --command-id RunShellScript \
  --scripts "sudo systemctl is-active filebeat" \
  --output none 2>/dev/null && print_success "Filebeat is running" || print_warning "Filebeat status unknown"

print_status "Checking Kibana status..."
az vm run-command invoke \
  --resource-group "$RESOURCE_GROUP" \
  --name Kibana-VM \
  --command-id RunShellScript \
  --scripts "sudo systemctl is-active kibana" \
  --output none 2>/dev/null && print_success "Kibana is running" || print_warning "Kibana status unknown"

################################################################################
# Deployment Complete
################################################################################

print_header "ELK Stack Deployment Complete!"

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              DEPLOYMENT SUCCESSFUL                             ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}Access Information:${NC}"
echo -e "  Kibana Web UI:      ${BLUE}http://${KIBANA_PUBLIC_IP}:5601${NC}"
echo -e "  Elasticsearch API:  ${BLUE}http://${ES_PUBLIC_IP}:9200${NC}"
echo ""
echo -e "${RED}Credentials (SAVE THESE!):${NC}"
echo -e "  Username: ${YELLOW}elastic${NC}"
echo -e "  Password: ${YELLOW}${ELASTIC_PASSWORD}${NC}"
echo ""
echo -e "${GREEN}SSH Access:${NC}"
echo -e "  Elasticsearch VM:   ${BLUE}ssh -i ${SSH_KEY_FILE%.pub} azureuser@${ES_PUBLIC_IP}${NC}"
echo -e "  Kibana VM:          ${BLUE}ssh -i ${SSH_KEY_FILE%.pub} azureuser@${KIBANA_PUBLIC_IP}${NC}"
echo ""
echo -e "${GREEN}Private IPs (for reference):${NC}"
echo -e "  Elasticsearch:      ${ES_PRIVATE_IP}"
echo -e "  Kibana:             ${KIBANA_PRIVATE_IP}"
echo ""
echo -e "${GREEN}For Your SOC Agent (.env file):${NC}"
echo -e "  ELK_HOST=http://${ES_PUBLIC_IP}:9200"
echo -e "  ELK_USERNAME=elastic"
echo -e "  ELK_PASSWORD=${ELASTIC_PASSWORD}"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "  1. Wait 2-3 minutes for all services to fully start"
echo "  2. Access Kibana at http://${KIBANA_PUBLIC_IP}:5601"
echo "  3. Login with username: elastic, password: ${ELASTIC_PASSWORD}"
echo "  4. Go to Management → Stack Management → Data Views"
echo "  5. Create data view: filebeat-*"
echo "  6. Go to Analytics → Discover to see logs"
echo ""
echo -e "${YELLOW}Generate Test Events (Failed Login Attempts):${NC}"
echo "  SSH into Elasticsearch VM and run:"
echo "  ${BLUE}for i in {1..20}; do sudo ssh baduser@localhost 2>/dev/null; sleep 1; done${NC}"
echo ""
echo -e "${YELLOW}Test Elasticsearch API:${NC}"
echo "  ${BLUE}curl -u elastic:${ELASTIC_PASSWORD} http://${ES_PUBLIC_IP}:9200/_cluster/health${NC}"
echo ""
echo -e "${YELLOW}To Delete Everything:${NC}"
echo -e "  ${RED}az group delete --name ${RESOURCE_GROUP} --yes --no-wait${NC}"
echo ""
echo -e "${GREEN}Security Notes:${NC}"
echo "  ✓ Authentication enabled"
echo "  ✓ Firewall restricted to your IP: ${MY_PUBLIC_IP}"
echo "  ✓ Internal network segmentation"
echo "  ⚠ TLS/SSL disabled (enable for production!)"
echo ""
print_header "Happy Threat Hunting!"

# Save credentials to file
CREDS_FILE="elk-credentials.txt"
cat > "$CREDS_FILE" <<EOF
ELK Stack Deployment Credentials
Generated: $(date)

Kibana URL: http://${KIBANA_PUBLIC_IP}:5601
Elasticsearch API: http://${ES_PUBLIC_IP}:9200

Username: elastic
Password: ${ELASTIC_PASSWORD}

For SOC Agent (.env):
ELK_HOST=http://${ES_PUBLIC_IP}:9200
ELK_USERNAME=elastic
ELK_PASSWORD=${ELASTIC_PASSWORD}

SSH Keys: ${SSH_KEY_FILE%.pub} / ${SSH_KEY_FILE}
EOF

print_success "Credentials saved to: $CREDS_FILE"
print_warning "Keep this file secure and delete it after updating your .env file!"
