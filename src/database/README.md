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
├── seeds/
│   ├── admin-only.sql                       # seed mínimo para QA de importação local
│   └── mtd-many-channels.sql                # complemento local para estressar gráfico de canais no MTD
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

Para testar importação em uma base limpa, sem carregar a amostra real:

```bash
cd src/database
supabase db reset --sql-paths ./seeds/admin-only.sql
supabase db reset --linked --sql-paths ./seeds/admin-only.sql
```

Esse comando aplica todas as migrations e roda apenas o seed mínimo. Ele cria
`admin@email.com` / `123321` em `admin_users`; depois entre no portal como admin
e crie o usuário distribuidor em **Admin › Usuários** para executar o QA de
importação.

Importante: o pipeline AWS deployado aponta para o Supabase cloud configurado nas
Lambdas. O seed mínimo local é útil para validar migrations, auth/admin e fluxos
locais; para QA end-to-end de upload S3/SQS/Lambda, rode o frontend contra o
Supabase cloud ou use a Vercel.

Serviços locais: API `http://127.0.0.1:54321` · Studio `http://127.0.0.1:54323` · Postgres `54322`.

Depois, no frontend (`src/frontend/.env.local`):

```
NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:54321
NEXT_PUBLIC_SUPABASE_ANON_KEY=<anon key impressa pelo supabase start — reveja com `supabase status`>
```

O seed padrão cria o admin local `admin@email.com` / `123321` em `admin_users` e o usuário distribuidor `distribuidora.83299743000130@email.com` / `123321` vinculado ao distribuidor da amostra em `distributor_users`. Aí `npm run dev` no frontend usa o banco local com auth real e isolamento por distribuidor.

Para validar o gráfico de **Canais** em `/relatorio/status/mtd` com volume parecido com produção, rode o seed padrão junto do complemento de stress:

```bash
cd src/database
supabase db reset --sql-paths ./seed.sql --sql-paths ./seeds/mtd-many-channels.sql
```

Esse complemento adiciona 65 canais `Stress Channel XX`, cada um com cliente, Sell Out atual/anterior e meta em julho de 2026, e atualiza a materialized view de relatórios no final.

## Decisões para alto volume

- `sell_out`/`sell_in` **particionadas por mês** (`ensure_month_partition`); pg_cron cria partições futuras todo dia 25.
- Carga em lote: ETL faz `COPY` para `staging_*` (UNLOGGED) e chama `process_*_staging(import_id)` — validação set-based, rejeições em `file_import_logs`, insert em massa.
- Relatórios usam `mv_sell_out_daily` para somas; cobertura (distinct clientes) é calculada na partição com índices dedicados. No **Status MTD**, valor/volume somam o intervalo filtrado. Sem SKU específico, cobertura/ticket usam os PDVs do mês inicial do período; com um ou mais SKUs selecionados, usam os PDVs únicos do intervalo. Drop Size usa `volume / cobertura`, conforme validação de 19/07/2026. Mark Up usa `preço médio Sell Out / preço médio Sell In - 1`; na coluna Meta, Mark Up, Margem e Giro Médio usam `sell_in_targets` contra `sales_targets`.
- Filtros de Categoria, Subcategoria, SKU, Canal e Cluster aceitam múltiplos valores nas RPCs novas por arrays `p_*_ids`; seleção vazia significa "todos".
- `refresh_report_views()` roda após cada carga (chamada pelo ETL) e às 4h via pg_cron.



## Tipos de arquivo de importação

`file_type_configs` (seed) registra os tipos conhecidos pela tela de Arquivos. Os layouts reais de `CUSTOMERS`, `PRODUCTS`, `SELLERS`, `TARGETS`, `SELL_IN_TARGETS`, `SELL_OUT` e `SELL_IN` têm pipeline completo (staging + `process_*_staging` + spec nas Lambdas) e ficam ativos para upload. `TARGETS` representa `Layout SellOut_meta.xlsx` e grava metas diárias de Sell Out por cliente/produto/vendedor/data. `SELL_IN_TARGETS` representa `Layout SellIn_meta.xlsx` e grava metas de Sell In por distribuidor/produto/mês. Novos tipos futuros, como `STOCK` ou `PLANNER`, exigem criar tabela staging, função `process_*` e entrada em `TABLE_SPECS` nas Lambdas em `src/cloud` — ver contratos no `CLAUDE.md` da raiz.

## Restrições do seed

O Supabase CLI envia o `seed.sql` como lote de prepared statements: **todos os statements são parseados antes de qualquer um executar**. Não crie objetos (views, tabelas) no seed que sejam referenciados por statements seguintes — use CTEs. É por isso que o cálculo de preço por produto se repete como CTE nos inserts.

## Contratos de RPC (frontend)


| Função                                     | Retorno                                                         | Tela                |
| ------------------------------------------ | --------------------------------------------------------------- | ------------------- |
| `report_status_mtd(...)`                   | jsonb com 12 KPIs (atual/meta/anterior + variações)             | Status MTD          |
| `report_status_analysis(group_by, ...)`    | tabela por vendedor/categoria/canal                             | Status › Análise    |
| `report_fast_facts(...)`                   | jsonb por dimensão (atingiram/não atingiram meta, melhor/pior, Sell Out R$, vs meta e vs AA) | Fast Facts          |
| `report_evolution_weekly(...)`             | buckets semanais                                                | Evoluções › Mensal  |
| `report_three_month_history(...)`          | 3 linhas mensais                                                | Evoluções › 3M      |
| `report_evolution_analysis(group_by, ...)` | atual × anterior por grupo                                      | Evoluções › Análise |
| `delete_platform_data(...)`                | contagem de registros excluídos por IDs selecionados ou filtros, limitado a admins | Dados › Excluir     |
| `set_distributor_status(...)`              | contagem de distribuidores ativados/inativados, limitado a admins | Cadastros › Distribuidor |
| `inactivate_distributor(...)`              | wrapper compatível para inativação de distribuidor              | Cadastros › Distribuidor |
| `list_platform_data_deletion_logs(...)`    | histórico paginado das exclusões administrativas                | Admin › Logs        |


Todas `security definer` com `search_path = public`; execução liberada apenas para `authenticated`. Funções de ETL são exclusivas do service role. `delete_platform_data` valida `current_user_is_admin()` internamente antes de remover dados por `row_ids` selecionados ou pelos filtros do portal e registra a ação em `platform_data_deletion_logs`.

### Exclusão administrativa e relações entre dados

A exclusão admin não depende de `ON DELETE CASCADE` nas tabelas principais de negócio. As FKs preservam integridade e, quando uma exclusão precisa remover ou desvincular dados relacionados, a RPC `delete_platform_data` faz isso explicitamente em ordem controlada.

| Dataset excluído | Efeito nos dados relacionados |
| --- | --- |
| `customers` | Remove primeiro `sales_targets` e `sell_out` dos clientes selecionados/filtrados, depois remove os próprios clientes. Não remove `sell_in`, porque Sell In é ligado a distribuidora/produto, não a cliente. |
| `sales_reps` | Só remove vendedores (`role = 'seller'`). Antes do delete, limpa vínculos em `customers.sales_rep_id`, `sell_out.sales_rep_id`, `sales_targets.sales_rep_id`, `sales_reps.manager_id` e `sales_reps.supervisor_id`. Não remove clientes, vendas nem metas por causa do vendedor. |
| `product_hierarchy` | Remove o nó selecionado e seus filhos. Antes do delete, remove produtos vinculados às subcategorias do escopo e limpa `sales_targets`, `sell_in_targets`, `stock_snapshots`, `sell_out` e `sell_in` desses produtos. |
| `commercial_hierarchy` | Remove o supervisor/vendedor selecionado. Se o item for supervisor, remove também vendedores subordinados. Antes do delete, limpa vínculos em clientes, Sell Out, metas e relações internas de `sales_reps`. |
| `sell_out` | Remove diretamente os lançamentos selecionados ou filtrados e atualiza as views/materializações de relatório. |
| `sell_in` | Remove diretamente os lançamentos selecionados ou filtrados. |
| `sales_targets` | Remove diretamente as metas selecionadas ou filtradas. |
| `distributors` | Não faz delete físico. `set_distributor_status` alterna `distributors.status` e também `distributor_users.status`: inativar bloqueia usuários vinculados de acessar a plataforma; ativar libera o acesso novamente. O histórico é preservado e a ação entra no mesmo log administrativo. |

O log de auditoria guarda o dataset, a ação (`delete`, `activate` ou `inactivate`), o modo da operação (`selected_rows` ou `filters`), os filtros/IDs usados, os itens afetados em `filters.items`, o admin executor, `deleted_count` e as distribuidoras afetadas em `filters.distributors` com `id`, `code`, `name` e `cnpj`. Para `customers` e `sales_reps`, `deleted_count` representa a quantidade de registros principais removidos, não a soma de registros auxiliares apagados ou desvinculados pela limpeza relacional.

## Segurança

RLS habilitado em todas as tabelas. Perfis atuais: `authenticated` lê tudo e mantém cadastros; escrita transacional segue pelo service role (ETL), com exceção da exclusão administrativa filtrada via RPC `delete_platform_data`. A auditoria de exclusões fica em `platform_data_deletion_logs`, com leitura liberada apenas para admins. A migration `000900_rls_hardening` fecha três brechas: revoga o EXECUTE default de `public`/`anon` nas RPCs (security definer), remove acesso direto de API à `mv_sell_out_daily` e habilita RLS nas partições (existentes e futuras — `ensure_month_partition` foi recriada para que partições novas já nasçam bloqueadas; **nunca crie partições manualmente**, sempre via essa função). Para papéis mais finos (ex.: vendedor vê só a própria carteira), adicionar claim de role no JWT e refinar as políticas.
