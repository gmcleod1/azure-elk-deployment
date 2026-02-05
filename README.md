# Azure ELK Stack Deployment

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Azure](https://img.shields.io/badge/Azure-Cloud-blue)](https://azure.microsoft.com/)
[![ELK](https://img.shields.io/badge/ELK-8.x-005571)](https://www.elastic.co/)

Automated, security-hardened deployment of the ELK (Elasticsearch, Logstash, Kibana) stack on Azure for SOC analyst training, security monitoring, and log analysis.

## 🚀 Features

- **One-Command Deployment** - Fully automated setup in ~15 minutes
- **Security Hardened** - IP whitelisting, authentication, network segmentation
- **Production-Ready** - Configurable VM sizes and Azure regions
- **Auto-Configured** - Filebeat pre-configured for system log collection
- **Cost-Effective** - Easy to start/stop VMs to save costs
- **Clean Uninstall** - Single command to remove all resources

## 🔒 Security Features

✅ **Authentication Required** - Elasticsearch security enabled with auto-generated passwords
✅ **IP Whitelisting** - Firewall automatically restricted to your public IP
✅ **Network Segmentation** - Elasticsearch API only accessible from internal subnet
✅ **No Hardcoded Secrets** - Generates secure random passwords on deployment
✅ **SSH Key Authentication** - No password-based access
✅ **Automatic Cleanup** - Prompts for resource cleanup on failure

⚠️ **Note**: TLS/SSL is disabled by default for testing. Enable for production use.

## 📋 Prerequisites

- **Azure CLI** - [Installation Guide](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
- **Bash** - Linux/macOS native, Windows users use Git Bash or WSL
- **Azure Subscription** - [Free trial available](https://azure.microsoft.com/free/) ($200 credit)
- **SSH Key** - Auto-generated if not found

## ⚡ Quick Start

```bash
# 1. Login to Azure
az login

# 2. Run deployment
chmod +x deploy-elk.sh
./deploy-elk.sh
```

**That's it!** The script will:
- ✅ Verify prerequisites
- ✅ Auto-detect your public IP
- ✅ Generate secure credentials
- ✅ Deploy infrastructure (VMs, networking)
- ✅ Install and configure ELK stack
- ✅ Save credentials to `elk-credentials.txt`

**Deployment time**: ~15 minutes

## 📦 What Gets Deployed

### Infrastructure
- **Resource Group**: `ELK-Security-Lab`
- **Region**: East US (configurable)
- **Virtual Network**: 10.0.0.0/16
- **Subnet**: 10.0.1.0/24
- **Network Security Group** with firewall rules
- **2 Virtual Machines**: Ubuntu 22.04 LTS
  - Elasticsearch VM (Elasticsearch + Filebeat)
  - Kibana VM (Kibana dashboard)

### Software
- **Elasticsearch 8.x** - Search and analytics engine
- **Kibana 8.x** - Visualization and dashboard
- **Filebeat 8.x** - Log shipping (system module enabled)

## ⚙️ Configuration

Customize deployment with environment variables:

```bash
# Deploy to different region
LOCATION=westus2 ./deploy-elk.sh

# Use larger VMs
VM_SIZE=Standard_D4s_v3 ./deploy-elk.sh

# Custom resource group
RESOURCE_GROUP=MySOC-Lab ./deploy-elk.sh

# Use existing SSH key
SSH_KEY_FILE=/path/to/key.pub ./deploy-elk.sh

# Combine multiple options
LOCATION=westus2 VM_SIZE=Standard_D4s_v3 RESOURCE_GROUP=ProdELK ./deploy-elk.sh
```

### VM Size Options

| Size | vCPUs | RAM | Use Case | Approx. Cost/Month* |
|------|-------|-----|----------|---------------------|
| Standard_B2s | 2 | 4 GB | Testing only | ~$30 |
| **Standard_D2s_v3** | **2** | **8 GB** | **Default (Recommended)** | **~$70** |
| Standard_D4s_v3 | 4 | 16 GB | Production | ~$140 |
| Standard_D8s_v3 | 8 | 32 GB | Heavy workloads | ~$280 |

*Costs for East US region. [Azure Pricing Calculator](https://azure.microsoft.com/pricing/calculator/)

## 🎯 After Deployment

### Access Your Stack

You'll receive output like this:

```
╔════════════════════════════════════════════════════════╗
║          DEPLOYMENT SUCCESSFUL                         ║
╚════════════════════════════════════════════════════════╝

Access Information:
  Kibana Web UI:      http://YOUR-KIBANA-IP:5601
  Elasticsearch API:  http://YOUR-ES-IP:9200

Credentials (SAVE THESE!):
  Username: elastic
  Password: [auto-generated-password]

For Your Application (.env file):
  ELK_HOST=http://YOUR-ES-IP:9200
  ELK_USERNAME=elastic
  ELK_PASSWORD=[auto-generated-password]
```

**Credentials are saved to `elk-credentials.txt`** - keep this secure!

### 1. Access Kibana

Wait 2-3 minutes for services to start, then open:
```
http://YOUR-KIBANA-IP:5601
```

Login with the credentials from the deployment output.

### 2. Create Data View

1. Go to: **Management** → **Stack Management** → **Data Views**
2. Click **Create data view**
3. Index pattern: `filebeat-*`
4. Timestamp field: `@timestamp`
5. Click **Save**

### 3. View Logs

Navigate to **Analytics** → **Discover** to see system logs!

### 4. Generate Test Security Events

SSH into the Elasticsearch VM:
```bash
ssh -i ~/.ssh/id_rsa azureuser@YOUR-ES-IP

# Generate 20 failed SSH attempts
for i in {1..20}; do sudo ssh baduser@localhost 2>/dev/null; sleep 1; done

# Exit
exit
```

Check Kibana to see the failed authentication events appear in real-time!

## 🧪 Testing & Validation

### Test Elasticsearch API
```bash
# Cluster health
curl -u elastic:YOUR-PASSWORD http://YOUR-ES-IP:9200/_cluster/health?pretty

# Search for failed logins
curl -u elastic:YOUR-PASSWORD \
  "http://YOUR-ES-IP:9200/filebeat-*/_search?q=event.action:ssh_login&pretty"
```

### Check Service Status
```bash
# SSH into VMs
ssh -i ~/.ssh/id_rsa azureuser@YOUR-ES-IP

# Check services
sudo systemctl status elasticsearch
sudo systemctl status filebeat
```

## 💰 Cost Management

### Estimated Monthly Costs
- **2x Standard_D2s_v3 VMs**: ~$140/month
- **2x Public IPs**: ~$7/month
- **Storage**: ~$5/month
- **Total**: ~$150/month

### Save Money

**Stop VMs when not in use** (keeps data, stops compute charges):
```bash
# Stop both VMs
az vm deallocate --resource-group ELK-Security-Lab --name Elasticsearch-VM
az vm deallocate --resource-group ELK-Security-Lab --name Kibana-VM

# Start when needed
az vm start --resource-group ELK-Security-Lab --name Elasticsearch-VM
az vm start --resource-group ELK-Security-Lab --name Kibana-VM
```

**Delete everything when done**:
```bash
az group delete --name ELK-Security-Lab --yes --no-wait
```

### Cost Optimization Tips
1. Use smaller VMs for testing (Standard_B2s)
2. Deallocate VMs when not in use
3. Set up [Azure Budget Alerts](https://docs.microsoft.com/en-us/azure/cost-management-billing/costs/cost-mgt-alerts-monitor-usage-spending)
4. Delete resources when finished with training

## 🔧 Management

### View Logs
```bash
# Elasticsearch logs
sudo journalctl -u elasticsearch -f

# Kibana logs
sudo journalctl -u kibana -f

# Filebeat logs
sudo journalctl -u filebeat -f
```

### Restart Services
```bash
sudo systemctl restart elasticsearch
sudo systemctl restart kibana
sudo systemctl restart filebeat
```

### Update Firewall (if your IP changes)
```bash
# Get your new IP
MY_IP=$(curl -s ifconfig.me)

# Update NSG rules
az network nsg rule update \
  --resource-group ELK-Security-Lab \
  --nsg-name ELK-NSG \
  --name Allow-SSH \
  --source-address-prefixes "$MY_IP/32"

az network nsg rule update \
  --resource-group ELK-Security-Lab \
  --nsg-name ELK-NSG \
  --name Allow-Kibana \
  --source-address-prefixes "$MY_IP/32"
```

## 🐛 Troubleshooting

### Cannot Access Kibana
- **Wait 3-5 minutes** after deployment for services to start
- Verify your IP: `curl ifconfig.me`
- Check if your IP changed (see firewall update above)

### Services Not Starting
```bash
# Check if Elasticsearch is listening
sudo netstat -tlnp | grep 9200

# View detailed logs
sudo journalctl -u elasticsearch -n 100 --no-pager
```

### Elasticsearch Health Yellow
- **Yellow is normal** for single-node clusters
- Red indicates a problem - check logs

### Filebeat Not Collecting Logs
```bash
# Test configuration
sudo filebeat test config
sudo filebeat test output

# Restart
sudo systemctl restart filebeat
```

## 🔐 Security Best Practices

### ✅ Already Implemented
- Authentication required
- Firewall restricted to your IP
- Network segmentation
- Strong random passwords
- SSH key authentication

### ⚠️ For Production

1. **Enable TLS/SSL** - Encrypt all traffic
2. **Use Azure Key Vault** - Store credentials securely
3. **Enable Azure Monitor** - Log and alert on access
4. **Configure Backups** - Elasticsearch snapshots + VM backups
5. **Use Private Endpoints** - Remove public IPs, use Bastion/VPN
6. **Regular Updates** - `sudo apt update && sudo apt upgrade -y`
7. **Implement RBAC** - Use role-based access control
8. **Rotate Passwords** - Regular credential rotation

## 📚 Use Cases

This deployment is perfect for:

- **SOC Analyst Training** - Practice log analysis and threat hunting
- **Security Research** - Test detection rules and queries
- **Log Analysis** - Centralized logging for development/testing
- **SIEM Development** - Build security monitoring tools
- **CTF Challenges** - Security competition infrastructure
- **Educational Labs** - Learn Elasticsearch and Kibana

## 🔗 Integration Examples

### Python (Elasticsearch Client)
```python
from elasticsearch import Elasticsearch

es = Elasticsearch(
    ["http://YOUR-ES-IP:9200"],
    basic_auth=("elastic", "YOUR-PASSWORD")
)

# Search for failed logins
result = es.search(
    index="filebeat-*",
    query={"match": {"event.action": "ssh_login"}}
)
print(result)
```

### Curl
```bash
# Query with Lucene syntax
curl -u elastic:PASSWORD \
  "http://YOUR-ES-IP:9200/filebeat-*/_search?q=event.outcome:failure&pretty"
```

### Kibana Dev Tools
```json
GET filebeat-*/_search
{
  "query": {
    "bool": {
      "must": [
        { "match": { "event.action": "ssh_login" }},
        { "match": { "event.outcome": "failure" }}
      ]
    }
  }
}
```

## 📖 Documentation

- [Elasticsearch Reference](https://www.elastic.co/guide/en/elasticsearch/reference/current/index.html)
- [Kibana Guide](https://www.elastic.co/guide/en/kibana/current/index.html)
- [Filebeat Documentation](https://www.elastic.co/guide/en/beats/filebeat/current/index.html)
- [Azure CLI Reference](https://docs.microsoft.com/en-us/cli/azure/)

## 🤝 Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/improvement`)
3. Make your changes
4. Test thoroughly
5. Commit (`git commit -m 'Add improvement'`)
6. Push (`git push origin feature/improvement`)
7. Open a Pull Request

## 📝 Changelog

### v2.0 (Latest)
- ✅ Security hardening (authentication, IP whitelisting)
- ✅ Auto-generated credentials
- ✅ Improved error handling and cleanup
- ✅ Comprehensive health checks
- ✅ Better VM sizing defaults
- ✅ Credentials saved to file

### v1.0
- Initial release

## ⚠️ Disclaimer

This deployment is designed for **training, testing, and development purposes**.

For production environments:
- Enable TLS/SSL encryption
- Implement comprehensive backup strategies
- Follow your organization's security policies
- Consider managed services like [Elastic Cloud on Azure](https://www.elastic.co/azure)

**Use at your own risk. Always monitor your Azure costs.**

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details.

## 👤 Author

**Garfield McLeod**
- GitHub: [@gmcleod1](https://github.com/gmcleod1)

## 🙏 Acknowledgments

- [Elastic](https://www.elastic.co/) for the ELK Stack
- [Microsoft Azure](https://azure.microsoft.com/) for cloud infrastructure
- Security community for best practices

---

**Questions or Issues?** [Open an issue](https://github.com/gmcleod1/azure-elk-deployment/issues)

**Happy Log Hunting!** 🔍🛡️
