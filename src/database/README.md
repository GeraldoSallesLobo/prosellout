# prosellout-database

Schema, migrations e funções de relatório do ProSellOut (Supabase / Postgres 17).

## Estrutura

```
supabase/
├── migrations/
│   ├── 20260705000100_extensions.sql        # pg_cron, pgcrypto
│   ├── 20260705000200_reference_tables.sql  # distribuidores, hierarquias, clientes
│   ├── 20260705000300_import_pipeline.sql   # tipos de arquivo, importações, logs
│   ├── 20260705000400_transactional_tables.sql # sell_out/sell_in particionadas por mês
│   ├── 20260705000500_staging_etl.sql       # staging UNLOGGED + funções de merge
│   ├── 20260705000600_aggregates.sql        # mv_sell_out_daily + refresh
│   ├── 20260705000700_report_functions.sql  # RPCs dos relatórios (KPIs, análises)
│   ├── 20260705000800_rls.sql               # políticas RLS + grants
│   └── 20260705000900_rls_hardening.sql     # revoga EXECUTE de public/anon, protege MV e partições
├── scripts/
│   └── generate_seed_from_sample.py         # gera o seed a partir de .dev_files/dados-importacao
└── seed.sql                                 # AUTO-GERADO da amostra real (ver docs/VALIDACAO_AMOSTRA.md)
```

> `seed.sql` é gerado pelo script a partir dos arquivos reais — **não editar à mão**; regenerar com `python3 scripts/generate_seed_from_sample.py` dentro de `src/database/`, ou `python3 src/database/scripts/generate_seed_from_sample.py` na raiz do repo.

## Setup

```bash
npm i -g supabase
supabase init                 # se ainda não houver config.toml local
supabase login
supabase link --project-ref <ref-do-projeto>
supabase db push              # aplica as migrations
psql "$DATABASE_URL" -f supabase/seed.sql   # opcional: dados de demo
```

## Rodando local (sem projeto na nuvem)

Pré-requisito: Docker Desktop rodando + Supabase CLI (`brew install supabase/tap/supabase`).

```bash
cd src/database
supabase start      # sobe Postgres/Auth/Studio locais e imprime a anon key
supabase db reset   # aplica migrations + seed (dados de demonstração)
```

Serviços locais: API `http://127.0.0.1:54321` · Studio `http://127.0.0.1:54323` · Postgres `54322`.

Depois, no frontend (`src/frontend/.env.local`):

```
NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:54321
NEXT_PUBLIC_SUPABASE_ANON_KEY=<anon key impressa pelo supabase start — reveja com `supabase status`>
```

O seed cria o login local `admin@email.com` / `admin123456` e vincula esse usuário ao distribuidor da amostra em `distributor_users`. Aí `npm run dev` no frontend usa o banco local com auth real e isolamento por distribuidor.

## Decisões para alto volume

- `sell_out`/`sell_in` **particionadas por mês** (`ensure_month_partition`); pg_cron cria partições futuras todo dia 25.
- Carga em lote: ETL faz `COPY` para `staging_*` (UNLOGGED) e chama `process_*_staging(import_id)` — validação set-based, rejeições em `file_import_logs`, insert em massa.
- Relatórios usam `mv_sell_out_daily` para somas; cobertura (distinct clientes) calculada na partição do período com índices dedicados.
- `refresh_report_views()` roda após cada carga (chamada pelo ETL) e às 4h via pg_cron.

## Tipos de arquivo de importação

`file_type_configs` (seed) registra os tipos aceitos pela tela de Importação. Hoje **apenas `SELL_OUT` e `SELL_IN` têm pipeline de ETL completo** (staging + `process_*_staging` + spec nas Lambdas). Os demais (`CUSTOMERS`, `TARGETS`, `STOCK`, `PLANNER`, `PRODUCTS`) estão cadastrados, mas processá-los exige criar: tabela staging, função `process_*` e entrada em `TABLE_SPECS` nas Lambdas em `src/cloud` — ver contratos no `CLAUDE.md` da raiz.

## Restrições do seed

O Supabase CLI envia o `seed.sql` como lote de prepared statements: **todos os statements são parseados antes de qualquer um executar**. Não crie objetos (views, tabelas) no seed que sejam referenciados por statements seguintes — use CTEs. É por isso que o cálculo de preço por produto se repete como CTE nos inserts.

## Contratos de RPC (frontend)

| Função | Retorno | Tela |
|---|---|---|
| `report_status_mtd(...)` | jsonb com 12 KPIs (atual/meta/anterior + variações) | Status MTD |
| `report_status_analysis(group_by, ...)` | tabela por vendedor/categoria/canal | Status › Análise |
| `report_fast_facts(...)` | jsonb por dimensão (atingiram meta, melhor/pior, probabilidade) | Fast Facts |
| `report_evolution_weekly(...)` | buckets semanais | Evoluções › Mensal |
| `report_three_month_history(...)` | 3 linhas mensais | Evoluções › 3M |
| `report_evolution_analysis(group_by, ...)` | atual × anterior por grupo | Evoluções › Análise |

Todas `security definer` com `search_path = public`; execução liberada apenas para `authenticated`. Funções de ETL são exclusivas do service role.

## Segurança

RLS habilitado em todas as tabelas. Perfis atuais: `authenticated` lê tudo e mantém cadastros; escrita transacional só pelo service role (ETL). A migration `000900_rls_hardening` fecha três brechas: revoga o EXECUTE default de `public`/`anon` nas RPCs (security definer), remove acesso direto de API à `mv_sell_out_daily` e habilita RLS nas partições (existentes e futuras — `ensure_month_partition` foi recriada para que partições novas já nasçam bloqueadas; **nunca crie partições manualmente**, sempre via essa função). Para papéis mais finos (ex.: vendedor vê só a própria carteira), adicionar claim de role no JWT e refinar as políticas.
