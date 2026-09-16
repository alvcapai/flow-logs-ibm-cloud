# IBM Cloud VPC Flow Logs — Terraform / Schematics (All-VPC Centralized)

> Gerado a partir de **IBM_Cloud_VPC_Flow_Logs_Guide_v1.docx**.

## O que faz

Ao ser executado, este Terraform:

1. **Descobre automaticamente todas as VPCs** em cada região listada em `var.regions` — sem precisar informar IDs de VPC manualmente.
2. **Cria um bucket COS por região** (restrição IBM: bucket single-region = mesma região da VPC).
3. **Cria uma única autorização IAM** (account-level) que permite a qualquer Flow Log Collector da conta escrever no COS.
4. **Cria um Flow Log Collector por VPC descoberta**, apontando para o bucket da região correspondente — todos os logs centralizam no mesmo COS instance.
5. **Cria um Schematics workspace** que gerencia o ciclo de vida completo via Git.

```
IBM Cloud Account
│
├── COS Instance  (global, único)
│   ├── Bucket: enterprise-vpc-flowlogs-br-sao     ← VPCs em br-sao
│   ├── Bucket: enterprise-vpc-flowlogs-us-south   ← VPCs em us-south
│   └── Bucket: enterprise-vpc-flowlogs-eu-de      ← VPCs em eu-de
│
├── IAM Authorization  (is/flow-log-collector → COS, Writer)
│
├── br-sao
│   ├── vpc-prod-sao  → FlowLogCollector → bucket br-sao
│   └── vpc-dev-sao   → FlowLogCollector → bucket br-sao
│
└── us-south
    └── vpc-shared    → FlowLogCollector → bucket us-south
```

## Regiões suportadas

`br-sao` · `us-south` · `us-east` · `ca-tor` · `eu-de` · `eu-gb` · `au-syd` · `jp-tok` · `jp-osa`

Para adicionar uma nova região: inclua-a em `var.regions`. O provider alias e o data source correspondente já estão declarados no `main.tf` para todas as regiões acima.

## Quick start

```bash
# 1. Coloque este código em um repositório Git acessível pelo Schematics.

# 2. Crie o arquivo de variáveis.
cp terraform.tfvars.example terraform.tfvars
# Edite terraform.tfvars — preencha api key, regions, resource_group_id, git_repo_url

# 3. Inicialize e aplique (localmente para teste).
terraform init
terraform plan   # mostra quantas VPCs foram descobertas e quantos collectors serão criados
terraform apply

# 4. Via Schematics (após o apply criar o workspace):
ibmcloud schematics plan  --id <workspace_id>
ibmcloud schematics apply --id <workspace_id>
```

## Variáveis

| Nome | Obrigatório | Padrão | Descrição |
|------|-------------|--------|-----------|
| `ibmcloud_api_key` | ✅ | — | IBM Cloud API key (sensitive) |
| `regions` | | `["br-sao","us-south"]` | Regiões a varrer. Collector criado para cada VPC encontrada. |
| `resource_group_id` | ✅ | — | Resource group para todos os recursos |
| `git_repo_url` | ✅ | — | URL HTTPS do repo Git usado pelo Schematics |
| `create_cos_instance` | | `true` | Criar novo COS instance ou reusar existente |
| `cos_instance_name` | | `cos-vpc-flow-logs-central` | Nome do novo COS instance |
| `existing_cos_instance_id` | | `""` | CRN do COS instance existente (se `create_cos_instance = false`) |
| `cos_bucket_name_prefix` | | `enterprise-vpc-flowlogs` | Prefixo dos buckets; cada bucket é nomeado `<prefix>-<region>` |
| `schematics_workspace_name` | | `vpc-flow-logs-central` | Nome do Schematics workspace |
| `schematics_location` | | `us-south` | Localização do metadata do workspace |
| `git_repo_branch` | | `main` | Branch do Git |
| `git_repo_folder` | | `terraform/vpc-flow-logs` | Subpasta no repo |
| `tags` | | `["vpc-flow-logs",...]` | Tags do workspace |

## Outputs

| Nome | Descrição |
|------|-----------|
| `cos_instance_id` | CRN do COS instance central |
| `cos_buckets` | Mapa `region → bucket_name` |
| `iam_authorization_policy_id` | ID da autorização IAM |
| `flow_log_collectors` | Mapa `<region>/<vpc-id> → collector_id` |
| `flow_log_collectors_count` | Total de collectors criados |
| `vpcs_discovered` | Mapa `<region>/<vpc-id> → vpc_name` de todas as VPCs encontradas |
| `schematics_workspace_id` | ID do Schematics workspace |
| `schematics_workspace_crn` | CRN do Schematics workspace |

## Validando que os logs estão funcionando

```bash
# Verificar status de todos os collectors
ibmcloud target -r br-sao
ibmcloud is flow-logs

# Inspecionar um collector específico — deve mostrar Status=stable, Active=on
ibmcloud is flow-log flowlog-<vpc-name>

# Aguardar ~5 min e inspecionar objeto .gz no bucket
ibmcloud cos object-get --bucket enterprise-vpc-flowlogs-br-sao --key <object_key> flowlog.gz
gzip -dc flowlog.gz | jq .

# Filtrar apenas tráfego rejeitado
gzip -dc flowlog.gz | jq '.flow_logs[] | select(.action == "rejected")'
```

## Troubleshooting

| Sintoma | O que verificar |
|---------|----------------|
| Nenhum objeto no COS | Collector precisa estar **Active** (não só Stable); verifique bucket same-region e IAM Writer |
| Collector com status Failed | Revalide IAM authorization e alinhamento de região |
| `flow_logs` array vazio | Normal para intervalos sem tráfego; gere tráfego TCP/UDP e revalide |
| Tráfego ICMP ausente | ICMP não é coletado; use testes TCP/UDP |
| `state = skip data` | Collector perdeu dados; investigue altas taxas de rejeição |

## Notas de segurança

- `terraform.tfvars` contém a API key — adicione ao `.gitignore`.
- O Schematics workspace armazena `ibmcloud_api_key` como variável **secure** (criptografada em repouso).
- A autorização IAM é criada no escopo da conta mas restrita à instância COS específica (`target_resource_instance_id`).
- A constraint same-region é garantida pela combinação `single_site_location = each.key` no bucket + `storage_bucket = ibm_cos_bucket.flow_logs[each.value.region].bucket_name` no collector.
