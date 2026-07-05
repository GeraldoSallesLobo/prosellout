# ProSellOut 2.0

Sistema de gestão de Sell Out — substitui a planilha `ProSellout_sistema_excel.xlsx` e segue o design da proposta (`ProSellout_proposta_dev.html`, mockup `portal.prosellout.com.br/relatorio/status/mtd`).

## Estrutura (monorepo)

Repositório único com uma pasta por camada — deploys independentes, contratos compartilhados:

| Pasta | Stack | Responsabilidade |
|---|---|---|
| `frontend/` | Next.js 14 + Tailwind + Recharts | Portal web (21 telas, temas claro/escuro) |
| `database/` | Supabase (Postgres 17) | Schema, migrations, RLS, funções de relatório, seed |
| `cloud/` | Terraform + AWS Lambda (Node 20) | Ingestão de arquivos de alto volume (S3 → SQS → ETL) |

Documentação:

| Arquivo | Conteúdo |
|---|---|
| `LOCAL_SETUP.md` | Rodar localmente (modo demo e banco local), criar usuário, roteiro de teste |
| `CLAUDE.md` | Guia para agentes/devs: convenções, contratos entre camadas, regras de negócio, armadilhas |
| `*/README.md` | Detalhes de cada camada |

## Arquitetura

```
                        ┌─────────────────────────────┐
  usuário ── browser ──▶│  frontend (Next.js/Vercel)  │
                        └──────┬──────────────┬───────┘
                               │ auth + RPCs  │ upload (URL pré-assinada)
                               ▼              ▼
                    ┌────────────────┐   ┌─────────────┐
                    │    Supabase    │   │   AWS S3    │ arquivos brutos
                    │  Postgres 17   │   └──────┬──────┘
                    │  Auth + RLS    │          │ evento S3
                    │  MVs agregadas │   ┌──────▼──────┐
                    └───────▲────────┘   │   Lambda    │ valida + fatia em lotes
                            │            │  validator  │
                            │            └──────┬──────┘
                            │                   │ mensagens (lotes)
                            │            ┌──────▼──────┐      ┌─────┐
                            │            │     SQS     │─────▶│ DLQ │
                            │            └──────┬──────┘      └─────┘
                            │  COPY em staging  │
                            │            ┌──────▼──────┐
                            └────────────│   Lambda    │ parse + COPY + merge
                                         │  etl-loader │ refresh das MVs
                                         └─────────────┘
```

### Por que aguenta alto volume

1. **Ingestão fora do request**: o portal nunca processa arquivo — gera URL pré-assinada e o upload vai direto ao S3. Processamento é assíncrono (SQS), com retry e DLQ. Instabilidade no processamento não derruba o portal.
2. **Carga em lote no Postgres**: o Lambda usa `COPY` para tabela de staging `UNLOGGED` e depois `INSERT ... SELECT` na tabela final — ordens de magnitude mais rápido que INSERTs linha a linha.
3. **Particionamento mensal**: `sell_out` e `sell_in` são particionadas por mês. Consultas MTD tocam só a partição do mês; expurgo de dados antigos é `DROP PARTITION`.
4. **Relatórios lêem agregados, não linhas**: materialized views diárias (`mv_sell_out_daily`) alimentam os relatórios. A tela MTD agrega ~30 linhas/dia por dimensão em vez de milhões de itens.
5. **Frontend com cache**: TanStack Query + tabelas paginadas no servidor (`range()`), nunca carrega o dataset inteiro.

## Ordem de setup (produção)

1. `database/` — criar projeto no Supabase e aplicar migrations (ver `database/README.md`)
2. `cloud/` — `terraform apply` com as credenciais do banco (ver `cloud/README.md`)
3. `frontend/` — `cp .env.example .env.local`, preencher chaves e `npm run dev` (ver `frontend/README.md`)

Para desenvolvimento local (Supabase via Docker ou modo demo sem infraestrutura), siga o `LOCAL_SETUP.md`.
