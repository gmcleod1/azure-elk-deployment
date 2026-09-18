# Azure ELK Stack Deployment

Automated deployment of the ELK stack (Elasticsearch, Logstash, Kibana) on Azure for SOC analyst training, security monitoring, and log analysis. One script stands up two Ubuntu VMs, installs Elasticsearch + Kibana + Filebeat, and locks the deployment down to your IP.

## What it does

- Deploys a resource group, VNet, NSG, and two Ubuntu 22.04 VMs (Elasticsearch + Kibana)
- Installs and configures Elasticsearch 8.x, Kibana 8.x, and Filebeat (system module enabled)
- Auto-detects your public IP and restricts the NSG to it
- Generates random Elasticsearch credentials instead of hardcoding any
- Writes credentials to `elk-credentials.txt` on completion

TLS is off by default — this is built for a training/lab environment, not production. See **Security Notes** below for what to add if you push it further.

## Prerequisites

- Azure CLI, logged in (`az login`)
- Bash (native on Linux/macOS, Git Bash or WSL on Windows)
- An Azure subscription (free trial's $200 credit covers this comfortably)
- SSH key (the script generates one if it doesn't find `~/.ssh/id_rsa`)

## Quick start

```bash
az login
chmod +x deploy-elk.sh
./deploy-elk.sh
```

Deployment takes about 15 minutes. Output includes the Kibana URL, Elasticsearch API endpoint, and generated credentials.

## Configuration

Override defaults with environment variables:

```bash
LOCATION=westus2 ./deploy-elk.sh
VM_SIZE=Standard_D4s_v3 ./deploy-elk.sh
RESOURCE_GROUP=MySOC-Lab ./deploy-elk.sh
SSH_KEY_FILE=/path/to/key.pub ./deploy-elk.sh
```

| Size | vCPUs | RAM | Notes | ~Cost/mo |
|---|---|---|---|---|
| Standard_B2s | 2 | 4 GB | Testing only | ~$30 |
| Standard_D2s_v3 (default) | 2 | 8 GB | Recommended | ~$70 |
| Standard_D4s_v3 | 4 | 16 GB | Heavier workloads | ~$140 |
| Standard_D8s_v3 | 8 | 32 GB | Heavy workloads | ~$280 |

Two VMs at the default size runs roughly $150/month all-in (compute + public IPs + storage). Deallocate when not in use to stop compute billing:

```bash
az vm deallocate --resource-group ELK-Security-Lab --name Elasticsearch-VM
az vm deallocate --resource-group ELK-Security-Lab --name Kibana-VM
```

Full teardown:

```bash
az group delete --name ELK-Security-Lab --yes --no-wait
```

## Using it

Wait 2-3 minutes after deployment for services to start, then open Kibana at `http://<kibana-ip>:5601` with the credentials from the deployment output.

To create the first data view: **Stack Management → Data Views → Create data view**, index pattern `filebeat-*`, timestamp field `@timestamp`. Then **Discover** shows system logs coming in.

To generate test events for a threat-hunting exercise, SSH into the Elasticsearch VM and throw some bad logins at it:

```bash
ssh -i ~/.ssh/id_rsa azureuser@<es-ip>
for i in {1..20}; do sudo ssh baduser@localhost 2>/dev/null; sleep 1; done
```

Those show up in Kibana as failed-auth events within a few seconds.

## Querying

```bash
# cluster health
curl -u elastic:PASSWORD http://<es-ip>:9200/_cluster/health?pretty

# failed logins
curl -u elastic:PASSWORD "http://<es-ip>:9200/filebeat-*/_search?q=event.outcome:failure&pretty"
```

Same query in Kibana Dev Tools:

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

## Troubleshooting

**Can't reach Kibana** — wait a few more minutes for services to finish starting, and check whether your IP changed (`curl ifconfig.me`) since the NSG is locked to the IP you had at deploy time. Update it with:

```bash
MY_IP=$(curl -s ifconfig.me)
az network nsg rule update --resource-group ELK-Security-Lab --nsg-name ELK-NSG --name Allow-Kibana --source-address-prefixes "$MY_IP/32"
```

**Services not starting** — check `sudo journalctl -u elasticsearch -n 100 --no-pager` on the ES VM. Yellow cluster health is normal for a single-node cluster; red means something's actually broken.

**Filebeat not shipping logs** — `sudo filebeat test config && sudo filebeat test output`, then `sudo systemctl restart filebeat`.

## Security notes

Already in place: auth required, NSG locked to your IP, no hardcoded secrets, SSH key auth only.

Not in place, and worth knowing before you treat this as anything beyond a lab: no TLS (traffic between Filebeat/Kibana/Elasticsearch is unencrypted), no Key Vault for credential storage, no backups, public IPs on both VMs instead of a private endpoint + bastion. Fine for a throwaway lab that gets torn down after use; not fine for anything with real data in it.

## License

MIT — see [LICENSE](LICENSE).

**Garfield McLeod** — [@gmcleod1](https://github.com/gmcleod1)
