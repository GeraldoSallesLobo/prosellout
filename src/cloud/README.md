# prosellout-cloud

Pipeline AWS de ingestão de arquivos de alto volume (Terraform + Lambda Node 20).

Guia operacional completo: `../../docs/DEPLOY_AWS_IMPORTACAO.md`.

## Fluxo

```
portal ──(1) registra import no Supabase (file_imports)
       ──(2) POST /upload-url ──▶ Lambda upload-url ──▶ URL pré-assinada
       ──(3) PUT direto no S3 (uploads/{importId}/arquivo.xlsx)

S3 uploads/ ──evento──▶ Lambda file-validator
  · status → validating
  · streama o arquivo (xlsx via ExcelJS streaming, csv via csv-parse)
  · normaliza cabeçalhos (aliases pt-BR), datas (DD/MM/AAAA) e números (vírgula)
  · fatia em partes CSV canônicas de até PART_MAX_ROWS (50k) em parts/
  · status → processing, total_records; 1 mensagem SQS por parte

SQS ──(até 8 em paralelo)──▶ Lambda etl-loader
  · COPY da parte direto do S3 para staging_* (UNLOGGED, sem WAL)
  · chama process_*_staging(import_id): valida em lote, resolve FKs,
    insere na tabela particionada, loga rejeições
  · quando processed+errors == total → finish_file_import + refresh das MVs
  · falhas → retry (3x) → DLQ + alarme CloudWatch/SNS
```

Por que aguenta volume: o portal nunca processa arquivo; cada parte é uma unidade de trabalho limitada e re-tentável; `COPY` em staging UNLOGGED elimina inserts linha a linha; a concorrência do loader é limitada (`maximum_concurrency = 8`) para não saturar o Postgres; partições mensais são criadas antes da carga.

## Deploy

Pré-requisitos rápidos:

- `AWS_PROFILE=prosellout` e `AWS_REGION=sa-east-1` exportados na sessão.
- Supabase cloud com migrations aplicadas.
- `database_url` em conexão direta ou pooler session mode na porta `5432`.
- `supabase_url` e `supabase_anon_key` do mesmo projeto usado pelo frontend.

```bash
./build.sh                      # npm install nas lambdas
cd terraform
terraform init
terraform apply \
  -var 'database_url=postgresql://postgres:...@db.<ref>.supabase.co:5432/postgres' \
  -var 'supabase_url=https://<ref>.supabase.co' \
  -var 'supabase_anon_key=<anon-key>' \
  -var 'portal_origins=["https://prosellout.com.br","https://www.prosellout.com.br","https://prosellout.vercel.app","http://localhost:3000"]' \
  -var 'alarm_email=ops@empresa.com.br'
```

Importante: use a conexão **direta ou pooler em session mode (porta 5432)** do Supabase — o pooler em transaction mode (6543) não suporta `COPY` streaming.

Saída `upload_api_url` → configure como `NEXT_PUBLIC_UPLOAD_API_URL` no frontend/Vercel e faça redeploy. O endpoint `/upload-url` exige `Authorization: Bearer <access_token>` e só emite URL para importações `pending` pertencentes ao usuário autenticado e ao distribuidor ativo dele.

## Vercel

Configure no projeto Vercel:

```env
NEXT_PUBLIC_UPLOAD_API_URL=<terraform output upload_api_url>
```

Confirme que `NEXT_PUBLIC_SUPABASE_URL` e `NEXT_PUBLIC_SUPABASE_ANON_KEY` apontam
para o mesmo Supabase cloud configurado nas Lambdas. Após alterar variável
`NEXT_PUBLIC_*`, faça redeploy.

## QA rápido

Depois do deploy:

1. Confirmar o e-mail de subscription SNS.
2. Importar pela UI na ordem: `Hier. Produtos`, `Vendedores`, `Clientes`, `Meta`, `Sell In`, `Sell Out`.
3. Acompanhar status em **Arquivos › Importação**.
4. Se falhar, checar CloudWatch:

```bash
AWS_PROFILE=prosellout AWS_REGION=sa-east-1 aws logs tail /aws/lambda/prosellout-prod-upload-url --follow
AWS_PROFILE=prosellout AWS_REGION=sa-east-1 aws logs tail /aws/lambda/prosellout-prod-file-validator --follow
AWS_PROFILE=prosellout AWS_REGION=sa-east-1 aws logs tail /aws/lambda/prosellout-prod-etl-loader --follow
```

## Estrutura

```
terraform/          # S3, SQS+DLQ, 3 Lambdas, IAM mínimo, alarmes
lambdas/
├── upload-url/     # URL pré-assinada de upload (Function URL)
├── file-validator/ # valida, normaliza e fatia arquivos
└── etl-loader/     # COPY para staging + merge set-based
```

## Tipos de arquivo

Hoje o ETL processa os layouts reais de clientes, produtos, vendedores, metas, sell-out e sell-in: `customers`, `products`, `sales_reps`, `sales_targets`, `sell_out` e `sell_in`.

Estoque não tem arquivo próprio no contrato atual: a tela calcula a posição como
Sell In acumulado menos Sell Out acumulado até a data de referência. Para um
novo tipo futuro (ex.: planificador ou uma base física de estoque caso a regra
de negócio mude):

1. No `database/`: criar tabela `staging_*` + função `process_*_staging` (migration) e registrar em `file_type_configs`.
2. Aqui: adicionar a entrada em `TABLE_SPECS` no `file-validator/index.mjs` (colunas canônicas + aliases de cabeçalho pt-BR) **e** no `etl-loader/index.mjs` (mesmas colunas, **na mesma ordem** — o COPY é posicional).
3. Redeployar: `./build.sh && terraform apply`.

## Custos (ordem de grandeza)

Uso serverless puro: sem tráfego = ~R$ 0. Um arquivo de 1M de linhas ≈ 20 partes × poucos segundos de Lambda + S3/SQS — centavos por importação.
