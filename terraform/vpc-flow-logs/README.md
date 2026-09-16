# IBM Cloud VPC Flow Logs — Terraform (All-VPC Centralized)

> Designed to run inside an **IBM Cloud Schematics** workspace.
> Generated from `IBM_Cloud_VPC_Flow_Logs_Guide_v1.docx`.

## O que faz

Ao ser executado, este Terraform:

1. **Descobre automaticamente todas as VPCs** em cada região listada em `var.regions`.
2. **Cria um bucket COS por região** (restrição IBM: bucket single-region = mesma região da VPC).
3. **Cria uma única autorização IAM** (account-level) para Flow Log Collector → COS Writer.
4. **Cria um Flow Log Collector por VPC descoberta**, apontando para o bucket da sua região.

```
IBM Cloud Account
│
├── COS Instance  (global, único)
│   ├── Bucket: enterprise-vpc-flowlogs-br-sao
│   └── Bucket: enterprise-vpc-flowlogs-us-south
│
├── IAM Authorization  (is/flow-log-collector → COS, Writer)
│
├── br-sao
│   ├── vpc-prod-sao  → flowlog-vpc-prod-sao  → bucket br-sao
│   └── vpc-dev-sao   → flowlog-vpc-dev-sao   → bucket br-sao
│
└── us-south
    └── vpc-shared    → flowlog-vpc-shared     → bucket us-south
```

## Autenticação

O provider IBM lê `IBMCLOUD_API_KEY` do ambiente automaticamente.  
**Não há uma variável Terraform `ibmcloud_api_key`** — configure a API key diretamente no Schematics como uma variável de ambiente segura (`IBMCLOUD_API_KEY`).

## Configuração no Schematics

| Campo | Valor |
|-------|-------|
| **Template URL** | URL do repositório Git |
| **Folder** | `terraform/vpc-flow-logs` |
| **Terraform version** | `terraform_v1.5` |
| **Environment variable** | `IBMCLOUD_API_KEY` = `<sua api key>` (marcar como sensitive) |

### Variáveis do workspace

| Nome | Tipo | Exemplo | Descrição |
|------|------|---------|-----------|
| `regions` | list(string) | `["br-sao","us-south"]` | Regiões a varrer |
| `resource_group_id` | string | `abc123...` | Resource group dos recursos |
| `create_cos_instance` | bool | `true` | Criar novo COS instance |
| `cos_instance_name` | string | `cos-vpc-flow-logs-central` | Nome do COS instance |
| `existing_cos_instance_id` | string | `crn:v1:...` | CRN de instância existente |
| `cos_bucket_name_prefix` | string | `enterprise-vpc-flowlogs` | Prefixo dos buckets por região |

## Regiões suportadas

`br-sao` · `us-south` · `us-east` · `ca-tor` · `eu-de` · `eu-gb` · `au-syd` · `jp-tok` · `jp-osa`

## Execução local (para testes)

```bash
# 1. Exporte a API key como variável de ambiente
export IBMCLOUD_API_KEY="<sua api key>"

# 2. Crie o arquivo de variáveis
cp terraform.tfvars.example terraform.tfvars
# Edite terraform.tfvars com resource_group_id e regiões desejadas

# 3. Inicialize e aplique
terraform init
terraform plan   # mostra VPCs descobertas e collectors a criar
terraform apply
```

## Outputs

| Nome | Descrição |
|------|-----------|
| `cos_instance_id` | CRN do COS instance central |
| `cos_buckets` | Mapa `region → bucket_name` |
| `iam_authorization_policy_id` | ID da autorização IAM |
| `flow_log_collectors` | Mapa `<region>/<vpc-id> → collector_id` |
| `flow_log_collectors_count` | Total de collectors criados |
| `vpcs_discovered` | Mapa `<region>/<vpc-id> → vpc_name` |

## Troubleshooting

| Sintoma | O que verificar |
|---------|----------------|
| Nenhum objeto no COS | Collector precisa estar **Active** (não só Stable); verifique IAM Writer e bucket same-region |
| Collector com status Failed | Revalide autorização IAM e alinhamento de região |
| `flow_logs` array vazio | Normal para intervalos sem tráfego; gere tráfego TCP/UDP e revalide |
| Tráfego ICMP ausente | ICMP não é coletado; use testes TCP/UDP |
| `state = skip data` | Collector perdeu dados; investigue altas taxas de rejeição |
