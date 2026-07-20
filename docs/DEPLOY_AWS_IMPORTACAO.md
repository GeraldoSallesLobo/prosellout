# Deploy AWS da Importação

Guia operacional para subir e validar o pipeline de importação de arquivos:
frontend/Vercel -> Lambda `upload-url` -> S3 -> Lambda `file-validator` -> SQS
-> Lambda `etl-loader` -> Supabase Postgres.

## Estado atual

O pipeline AWS foi criado em produção na conta `071604987536`, região
`sa-east-1`, com recursos prefixados por `prosellout-prod-*`.

Outputs do Terraform:

| Output | Uso |
|---|---|
| `upload_api_url` | Configurar em `NEXT_PUBLIC_UPLOAD_API_URL` na Vercel/frontend |
| `imports_bucket` | Bucket S3 de arquivos brutos e partes canônicas |
| `etl_queue_url` | Fila SQS entre validator e loader |

O Terraform está usando state local em `src/cloud/terraform/terraform.tfstate`.
Esse arquivo é ignorado pelo Git e não deve ser commitado. Antes de múltiplas
pessoas operarem a infraestrutura, migrar o backend para S3/DynamoDB ou
Terraform Cloud.

## Pré-requisitos

- AWS CLI autenticado no profile `prosellout`.
- Terraform instalado (`>= 1.6`; validado com `1.15.8`).
- AWS CLI disponível no ambiente que roda Terraform. O deploy usa um
  `terraform_data` idempotente para aplicar a policy `lambda:InvokeFunction`
  exigida por Function URLs novas.
- Supabase cloud com migrations aplicadas, incluindo
  `20260709015704_align_real_import_layout`.
- Connection string Postgres do Supabase em conexão direta ou pooler session
  mode na porta `5432`.
- Anon key e URL do Supabase cloud.
- Acesso ao projeto Vercel para configurar env vars e redeploy.

Nunca use o pooler transaction mode na porta `6543`: o loader usa `COPY`
streaming e esse modo não suporta a operação.

## Autenticação AWS

Use profile separado para não misturar com outras contas AWS:

```bash
aws configure --profile prosellout
```

Na sessão do deploy:

```bash
export AWS_PROFILE=prosellout
export AWS_REGION=sa-east-1

aws sts get-caller-identity
```

Confirme que a conta retornada é `071604987536`.

Se uma access key for exposta em conversa, commit, print ou log, revogue a key no
IAM e crie outra.

## Deploy ou atualização da AWS

```bash
cd /Users/geraldojunior/Projects/prosellout/src/cloud
./build.sh

cd terraform
terraform init
```

Exporte as variáveis sensíveis na sessão do terminal. Não grave essas variáveis
em arquivo versionado:

```bash
export TF_VAR_supabase_url='https://<ref>.supabase.co'
export TF_VAR_supabase_anon_key='<anon-key>'
export TF_VAR_database_url='postgresql://postgres.<ref>:<password>@aws-0-sa-east-1.pooler.supabase.com:5432/postgres'
export TF_VAR_alarm_email='ops@empresa.com.br'
```

As origens permitidas para upload já têm defaults em Terraform:

- `https://prosellout.com.br`
- `https://www.prosellout.com.br`
- `https://prosellout.vercel.app`
- `http://localhost:3000`

Para sobrescrever em algum ambiente:

```bash
export TF_VAR_portal_origins='["https://prosellout.com.br","https://prosellout.vercel.app"]'
```

Planeje e aplique:

```bash
terraform plan
terraform apply
```

Após o apply, copie o output `upload_api_url`.

## Configuração da Vercel

No projeto Vercel, configure:

```env
NEXT_PUBLIC_UPLOAD_API_URL=<upload_api_url do terraform>
```

Confirme também que o frontend usa o mesmo Supabase cloud configurado nas
Lambdas:

```env
NEXT_PUBLIC_SUPABASE_URL=https://<ref>.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=<anon-key>
```

Variáveis `NEXT_PUBLIC_*` são embutidas no bundle do Next.js. Depois de alterar
qualquer uma delas, faça um novo deploy/redeploy na Vercel.

## QA end-to-end

Antes do teste:

1. Confirmar o e-mail de subscription SNS enviado para `TF_VAR_alarm_email`.
2. Garantir que o usuário distribuidor existe e está vinculado em
   `distributor_users`.
3. Garantir que `file_type_configs` tem os sete tipos ativos.

Ordem de importação recomendada em **Arquivos > Importação**:

1. `Hier. Produtos` (`PRODUCTS`)
2. `Vendedores` (`SELLERS`)
3. `Clientes` (`CUSTOMERS`)
4. `Meta Sell Out` (`TARGETS`) — use `Layout SellOut_meta.xlsx`
5. `Meta Sell In` (`SELL_IN_TARGETS`) — use `Layout SellIn_meta.xlsx`
6. `Sell In` (`SELL_IN`)
7. `Sell Out` (`SELL_OUT`)

Para a amostra completa em `.dev_files/dados-importacao`, importe também os
arquivos sufixados com `_aa` quando existirem (`SellIn_aa`, `SellOut_aa`).
`Layout SellOut_meta.xlsx` deve ser importado como `Meta Sell Out`.
`Layout SellIn_meta.xlsx` deve ser importado como `Meta Sell In`, nunca como
`Sell In` ou `Meta Sell Out`.

Durante o teste, a tela deve evoluir por status como `pending`, `validating`,
`processing` e `completed` ou `completed_with_errors`. Se houver erros de linha,
eles devem aparecer no log da importação via `file_import_logs`.

## Monitoramento

Logs das Lambdas:

```bash
AWS_PROFILE=prosellout AWS_REGION=sa-east-1 aws logs tail /aws/lambda/prosellout-prod-upload-url --follow
AWS_PROFILE=prosellout AWS_REGION=sa-east-1 aws logs tail /aws/lambda/prosellout-prod-file-validator --follow
AWS_PROFILE=prosellout AWS_REGION=sa-east-1 aws logs tail /aws/lambda/prosellout-prod-etl-loader --follow
```

Filas:

```bash
AWS_PROFILE=prosellout AWS_REGION=sa-east-1 aws sqs get-queue-attributes \
  --queue-url 'https://sqs.sa-east-1.amazonaws.com/071604987536/prosellout-prod-etl' \
  --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible ApproximateNumberOfMessagesDelayed
```

DLQ:

```bash
DLQ_URL=$(AWS_PROFILE=prosellout AWS_REGION=sa-east-1 aws sqs get-queue-url \
  --queue-name prosellout-prod-etl-dlq \
  --query QueueUrl \
  --output text)

AWS_PROFILE=prosellout AWS_REGION=sa-east-1 aws sqs get-queue-attributes \
  --queue-url "$DLQ_URL" \
  --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible ApproximateNumberOfMessagesDelayed
```

S3:

```bash
AWS_PROFILE=prosellout AWS_REGION=sa-east-1 aws s3 ls s3://prosellout-prod-imports/uploads/ --recursive
AWS_PROFILE=prosellout AWS_REGION=sa-east-1 aws s3 ls s3://prosellout-prod-imports/parts/ --recursive
```

## Problemas comuns

| Sintoma | Causa provável | Ação |
|---|---|---|
| POST para `upload-url` retorna 401/403 | Token do frontend pertence a outro Supabase ou usuário não tem distribuidor | Conferir `NEXT_PUBLIC_SUPABASE_URL`, `SUPABASE_URL` da Lambda e vínculo em `distributor_users` |
| POST retorna `Forbidden` com `x-amzn-errortype: AccessDeniedException` | Function URL sem resource policy completa | Garantir que Terraform aplicou a permissão `lambda:InvokeFunction` para a Lambda `upload-url` |
| Erro de CORS no POST | Origem não está em `portal_origins` | Ajustar `TF_VAR_portal_origins` ou defaults e rodar `terraform apply` |
| Erro de CORS no PUT S3 | Bucket CORS não tem a origem | Conferir `aws s3api get-bucket-cors` e reaplicar Terraform |
| Importação fica `pending` | Frontend não chamou `upload-url` ou Vercel não foi redeployada após env var | Redeploy Vercel e verificar Network no browser |
| Importação fica `validating` | `file-validator` falhou antes de enfileirar partes | Checar CloudWatch da Lambda e `file_import_logs` |
| Partes vão para DLQ | `etl-loader` falhou após retries | Checar CloudWatch do loader, DLQ e conexão `DATABASE_URL` |
| Erro de `COPY`/conexão | Usou pooler transaction mode (`6543`) | Trocar para conexão direta/session mode (`5432`) |

## Local vs. produção

A AWS de produção valida o JWT e grava no Supabase cloud configurado nas
variáveis das Lambdas. Portanto, frontend local apontando para Supabase local
(`http://127.0.0.1:54321`) não deve usar `NEXT_PUBLIC_UPLOAD_API_URL` da AWS
prod para QA end-to-end.

Para testar upload AWS com frontend local, aponte o frontend local para o mesmo
Supabase cloud da AWS. Para validar banco local limpo sem acionar AWS prod, use:

```bash
cd src/database
supabase db reset --sql-paths ./seeds/admin-only.sql
```
