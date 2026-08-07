# PLANNER_SPEC.md — Especificação do módulo Planner (Planificador)

> Spec-driven development: este documento é a fonte de verdade do módulo Planner.
> Origem: reunião de alinhamento Eduardo Clement × Geraldo (05/08/2026, transcrição completa em
> `.dev_files/planner/transcricao-reuniao-planner.md`) + material `Planificador.xlsx` + bases de
> teste `Layout SellOut_set25.xlsx` (realizado set/2025) e `Layout SellOut_meta_set26.xlsx` (meta set/2026).
> Ao alterar comportamento do Planner, atualize esta spec no mesmo PR.

## 1. Visão geral

O Planner ajuda o distribuidor a **desdobrar a meta mensal de Sell Out em planos operacionais
por PDV/semana/SKU**, gerando uma base exportável para o sistema de roteirização dele, e depois
**avaliar o que foi planejado × realizado**.

São **5 modelos (planificadores) com regras distintas** + 1 etapa comum de parametrização + 1
dashboard de avaliação. Cada modelo vira um item de menu na seção "Planner" do sistema:

| # | Módulo | O que faz |
|---|---|---|
| 0 | Parametrização do Roteirizador | Config comum: semanas do mês (3/4/5) + importação do roteiro de visitas |
| 1 | Automático | Distribui a meta de volume por SKU×PDV×semana com peso histórico |
| 2 | Batalha Naval Volume | Usa a participação de volume de um SKU referência para desdobrar a meta |
| 3 | Batalha Naval Positivação | Como o 2, mas ranqueia por positivação e distribui linearmente |
| 4 | Cobertura | Meta (R$ ou volume) distribuída linearmente entre PDVs não cobertos |
| 5 | Rentabilidade | Receita não capturada por PDVs com margem abaixo da margem objetivo |
| 6 | Dashboard | Avaliação planejado × realizado por planificador (estilo Fast Facts) |

**Nomes são provisórios** (decisão da reunião: Marcelo vai renomear depois; usar estes termos por
enquanto). UI em pt-BR, rotas em pt-BR, código em inglês.

### Glossário

- **PDV** — ponto de venda (cliente do distribuidor; `customers`).
- **Positivação** — nº de PDVs distintos com venda (de um SKU) no período.
- **Cobertura** — PDV coberto = PDV com venda no período; descoberto = sem venda.
- **Planificador (plano)** — resultado gerado por um modelo: conjunto de linhas SKU×PDV(×semana)
  com volume/valor objetivo. Cada geração recebe um **código sequencial** (ex.: `PLN-001`).
- **Roteiro de visitas** — planejamento de visitas por PDV×vendedor×semana importado do distribuidor.
- **Indústria/Marca** — no sistema atual há 1 indústria por base; o cross-industry é um "plus" futuro
  (seção 12).

## 2. Regras de negócio — Parametrização do Roteirizador

Etapa inicial **comum a todos os modelos** (é pré-requisito para gerar plano com abertura semanal).

1. **Passo 1 — semanas**: usuário escolhe em quantas semanas a meta do mês será distribuída:
   **3, 4 ou 5** (select). Motivação: setembro pode ter 5 semanas de calendário, mas o distribuidor
   pode concentrar a venda em 3.
2. **Passo 2 — importação do roteiro**: o distribuidor importa um Excel/CSV no layout correspondente
   à opção escolhida (o número de colunas `Semana N` deve bater com o passo 1):

   | Coluna | Tipo | Obrigatória | Observação |
   |---|---|---|---|
   | Marca | texto | não | indústria; hoje ignorada (base é mono-indústria) |
   | CNPJ Distribuidor | texto (14 dígitos) | sim | precisa existir em `distributors` |
   | CNPJ/CPF Cliente | texto (11/14 dígitos) | sim | precisa existir em `customers` |
   | Cód. Vendedor | texto | sim | precisa existir em `sales_reps` |
   | Semana 1..N | `x` ou vazio | — | `x` = visita naquela semana |

3. **Regras de visita**:
   - Mais de um `x` (ou repetição do PDV) na mesma semana conta como **1 visita/semana**
     ("se ele vai lá duas ou três vezes, a gente só controla uma vez na semana").
   - O mesmo PDV **pode** ser visitado em mais de uma semana (ex.: semana 1 e semana 3).
4. **Ponto de atenção (Marcelo)**: criar vídeo/tutorial do passo a passo da importação para deixar
   na plataforma; se restar dúvida, agenda ProSellOut × cliente como parte do setup. (Não é escopo
   de código; registrar na UI um texto de ajuda + link placeholder.)

## 3. Regras de negócio — Modelo Automático

1. **Passo 1 — mês de referência da meta**: grid/select listando os meses **com meta de Sell Out
   cadastrada no sistema, do mês atual em diante**. Se o mês escolhido não tiver meta → **alerta
   bloqueante** ("não há meta de Sell Out para <mês>").
2. **Passo 2 — semanas do mês**: a partir da parametrização (3/4/5), o usuário informa **data de
   início e fim de cada semana** (calendário). Motivo: distribuidores trabalham seg–sex, seg–sáb ou
   dom–sáb; e a meta existe **por dia**, então os intervalos permitem cruzar meta×semana e, depois,
   planejado×realizado no dashboard. **As datas nunca saem do mês da meta** (Eduardo, 06/08/2026:
   selecionado setembro, só aparecem datas de setembro — a 1ª semana pode ser, por ex., terça 01 a
   sábado 05); os pickers limitam ao mês e a geração rejeita semana fora dele (`INVALID_WEEKS`).
   Sugestão padrão de semanas: segmentos de calendário domingo–sábado recortados no mês.
3. **Passo 3 — distribuição**: distribuir a **meta de Sell Out VOLUME de cada SKU por CNPJ (PDV)**,
   por semana, gerando a base `CNPJ Distribuidor | EAN | Cód. PDV | Semana | Volume`:
   - **Peso primário**: participação (%) do PDV no volume do SKU na **mesma semana do ano
     anterior**. Interpretação adotada: mesma **semana ISO do ano** (o exemplo falado na reunião
     — "semana 37, do dia 7 ao dia 11" — usa numeração de semana do calendário). Para cada semana
     configurada no passo 2, a semana de referência é a de mesmo número ISO no ano anterior.
   - **Fallback (PDV sem histórico na semana do ano anterior — ex.: cliente novo)**: **média
     simples da participação mensal do PDV nos últimos 3 meses** fechados (ex.: para set/26 →
     jun, jul, ago/26). Nunca usar a soma do trimestre — enviesaria o peso ("não pode ser a
     somatória; tem que trazer a média do trimestre").
   - **Caso misto** (parte dos PDVs com histórico anual, parte só com recência): montar **uma base
     única** com o peso de cada PDV vindo da sua fonte (ano anterior ou média 3m) e **renormalizar**
     para que a soma dos pesos = 100% antes de aplicar sobre a meta.
   - A distribuição respeita o **roteiro de visitas**: o volume de um PDV numa semana só é alocado
     se o PDV tem visita (`x`) naquela semana; PDVs do roteiro sem histórico algum entram pelo
     fallback (e, se ainda assim sem histórico nos 3 meses, peso 0 — **não geram linha**; o gap
     aparece na resposta da geração e a UI alerta, ver §14).
4. **Exportação**: a base gerada deve ser exportável (Excel/CSV) para o cliente importar no sistema
   de roteirização dele. Exportações devem indicar os filtros/parâmetros usados (padrão do sistema).
5. **Passo 4 — RECALCULAR ROTA (optativo)**: disponível após o fim da 1ª semana e sucessivamente
   até o início da última semana do mês:
   - saldo = meta do mês − realizado acumulado até a data;
   - redistribuir o **saldo** pelas **semanas restantes** com a mesma regra de pesos;
   - o resultado **substitui os valores-objetivo** das semanas seguintes do planificador
     (**as visitas não mudam**, só o volume/valor objetivo);
   - gera novo relatório no mesmo layout.

## 4. Regras de negócio — Batalha Naval Volume

1. **Passo 1 — mês de referência do comportamento**: qualquer mês do **ano anterior** ou mês **já
   ocorrido do ano corrente** (ex.: junho/26 — "o que aconteceu em junho/26 será replicado").
2. **Passo 2 — gráfico top SKUs**: gráfico de **colunas** com os **5 SKUs de melhor positivação**
   no mês escolhido, ordem decrescente (critério da planilha, **confirmado pelo Eduardo em
   06/08/2026** — na call ele havia dito "os que mais vendem", mas vale a planilha: positivação
   também no BN Volume). Filtro por **canal** (Todos ou um canal específico; o gráfico atualiza).
   **Opcional (pedido do Marcelo)**: adicionar SKUs extras ao gráfico (6º, 7º… **sem limite**)
   para considerar demandas da indústria.
3. **Passo 3 — SKU de referência**: usuário seleciona **1 SKU** do gráfico; ele será o referencial
   para desdobrar a meta.
4. **Passo 4 — base de participação**: gerar `CNPJ Distribuidor | EAN | Cód. PDV | Canal | % Volume`
   com a **participação de volume de cada PDV sobre o total de sell out** do SKU de referência no
   mês de referência, segmentado por canal (respeitando o filtro do passo 2). Com canal "Todos",
   o % é **sobre o total geral** de vendas do SKU, não sobre o total do canal de cada PDV
   (**confirmado pelo Eduardo em 06/08/2026**). Essa participação é o peso aplicado sobre a meta.
5. **Passo 5** — "a partir dessa etapa, repete o passo 1 ao 4 do modelo Automático": escolhe o mês
   da meta, configura semanas, e distribui a meta usando **os pesos do passo 4** (no lugar do peso
   histórico do Automático), respeitando o roteiro de visitas. Exportação idem.
6. **Conceito**: aqui a meta base é **volume** ("quero vender X"), distribuída conforme o padrão de
   compra de um SKU que já performa.

## 5. Regras de negócio — Batalha Naval Positivação

Igual ao Batalha Naval Volume, com duas diferenças:

1. O ranking do passo 2 é por **positivação** (nº de PDVs distintos que compraram o SKU) — mesmo
   critério do BN Volume.
2. A distribuição da meta entre os PDVs é **linear** (partes iguais) — e o universo são **os PDVs
   que já compram o SKU de referência** no mês de referência (**confirmado pelo Eduardo em
   06/08/2026**: "o objetivo é replicar a positivação do SKU case, pois apresentará melhor
   resultado do que está em prática"). Conceito: "independente do volume, eu quero positivar"
   (ex.: positivo em 2.000 PDVs e quero 2.500 — não interessa o volume).

Layout do passo 4: `CNPJ Distribuidor | EAN | Cód. PDV` (sem % Volume — a distribuição é linear).
O passo 5 repete os passos 1–4 do Automático, idem ao modelo anterior.

## 6. Regras de negócio — Cobertura

1. **Passo 1 — SKU** de referência.
2. **Passo 2 — canal** (optativo; default **Todos**).
3. **Passo 3 — período** com **data início e data fim** livres (sem mês/semana). O período é
   **passado**: serve para identificar quem não foi coberto (ex.: "nos últimos 3 meses, quem eu
   não positivei?").
4. **Passo 4 — PDVs descobertos**: tabela `CNPJ Distribuidor | Cód. PDV` com os PDVs **sem venda**
   (do SKU/canal escolhidos) no período.
5. **Passo 5 — meta a buscar**: dois campos — primeiro a **variável** (`R$` **ou** `volume`,
   exclusivo: "nunca vai rodar as duas"), depois o **valor** — e o **prazo de execução** (data
   início/fim em que a meta deve ser buscada; **decidido pelo Eduardo em 06/08/2026**: o
   distribuidor escolhe o período, no mesmo formato do passo 3). O Dashboard avalia o plano
   dentro desse prazo.
6. **Passo 6 — distribuição linear**: dividir a meta igualmente entre os PDVs do passo 4
   (ex.: R$ 1.000.000 ÷ 200 clientes), gerando
   `CNPJ Distribuidor | EAN | Cód. PDV | Volume / R$`.

Sem abertura semanal e sem dependência do roteiro de visitas (não há passo 5 do Automático aqui).

## 7. Regras de negócio — Rentabilidade

(Pedido do Marcelo na última conversa com Eduardo.)

1. **Passo 1 — SKU**; **Passo 2 — canal** (optativo, Todos); **Passo 3 — período** início/fim
   (igual Cobertura).
2. **Passo 4 — margem objetivo**: campo % (ex.: 20%). Resultado: lista
   `CNPJ Distribuidor | Cód. PDV` dos PDVs cuja **margem praticada** no período ficou **abaixo**
   da margem objetivo.
3. **Passo 5 — gap de receita**: para cada PDV listado:
   `gap% = margem objetivo − margem praticada` (ex.: 20% − 18% = 2 p.p.);
   `receita não capturada = gap% × preço médio praticado × volume realizado` — "esses 2%,
   aplicados ao preço médio, quanto daria de receita, com base no realizado de sell out".
4. **Passo 6 — resultado por PDV**: `CNPJ Distribuidor | EAN | Cód. PDV | Volume / R$` com o valor
   do passo 5. Na geração o distribuidor também informa o **prazo de execução** (data início/fim
   para recuperar a receita — mesma regra da Cobertura, decidida em 06/08/2026).

**Base de custo (decidido em 06/08/2026)**: a margem praticada usa o **preço médio de compra do
Sell In** do SKU como custo — mesma regra de margem do Status MTD (`docs/PENDENCIAS_CALCULO.md`).
`margem do PDV = (preço médio de venda ao PDV − preço médio Sell In) ÷ preço médio de venda`.
Se não houver compra de Sell In **dentro do período analisado**, usar a média dos **3 meses
anteriores** ao início do período; sem Sell In em nenhuma das duas janelas → erro `NO_COST_DATA`
(aviso na UI, nunca lista vazia silenciosa). O layout real de Sell Out não traz custo unitário —
com essa regra o modelo funciona com a base real, que sempre traz Sell In.

## 8. Identificação de planificadores (decisão da reunião)

Problema levantado: o distribuidor pode rodar **4–5 planificadores simultâneos** (estratégias
diferentes) e depois precisa avaliar cada um separadamente.

- Todo plano **gerado** (= salvo) recebe **código sequencial** por distribuidor: `PLN-001`,
  `PLN-002`… (contador no sistema) + o **modelo** que o gerou + parâmetros usados + data/usuário.
- A listagem de planos permite **reconsultar** qualquer plano gerado (parâmetros + linhas).
- Exportações incluem código do plano e parâmetros/filtros usados (padrão das outras telas).
- Ciclo de vida: `draft` (parâmetros escolhidos, ainda não gerado) → `generated` (linhas geradas,
  código atribuído) → `replaced` (linhas substituídas por um Recalcular Rota posterior). O
  Recalcular Rota cria nova **versão** do plano (histórico preservado; a versão vigente é a última).

## 9. Regras de negócio — Dashboard de avaliação

Template visual final ainda **pendente com o Eduardo** (será similar ao Fast Facts). O combinado:

1. **Seleção do planificador** a avaliar (pelo código/lista — ver seção 8).
2. **Resumo estilo Fast Facts**:
   - total de planos (cada **linha** do planificador = 1 plano), quantos **atingidos × não
     atingidos** (gráfico de pizza);
   - melhor/pior por **vendedor** (quem atingiu o planificador proposto);
   - mesmas variáveis do Fast Facts, trocando "bateu a meta" por "**executou/atingiu o
     planificador proposto**".
3. **Relatório analítico (para o vendedor)**: tabela com visão alternável **por cliente / canal /
   vendedor** (padrão de toggle já usado no sistema): **planejado, realizado, variação** e o
   **valor financeiro e volume que deixou de ser realizado**.
4. **Ambos exportáveis para Excel**.
5. Critério de "atingido" (linha): realizado ≥ planejado no recorte da linha (SKU×PDV×semana quando
   houver semana; senão SKU×PDV no período do plano).

## 10. Bases de teste e importação

Arquivos enviados pelo Eduardo (`.dev_files/planner/`):

| Arquivo | Conteúdo | Papel no teste |
|---|---|---|
| `Layout SellOut_set25.xlsx` | Realizado de set/2025 (413 linhas, 5 EANs, 10 vendedores, 258 PDVs, 5 segundas-feiras: 01, 08, 15, 22, 29/09) | Histórico "mesma semana do ano anterior" |
| `Layout SellOut_meta_set26.xlsx` | Meta de set/2026 (131 linhas, mesmos EANs/vendedores, 78 PDVs, 5 quartas-feiras: 02, 09, 16, 23, 30/09 — 1 data por semana) | Meta mensal/semanal a distribuir |

- Layout canônico (8 colunas): `CNPJ Distribuidor | EAN | Cód. PDV | Cód. Vendedor | Volume Total
  de Unidades NF | Valor Total R$ NF | Data Faturamento | Data Entrega`. As colunas extras
  (Produto/Canal/Cluster/Semana/Mês) são VLOOKUPs auxiliares do Eduardo — **ignorar na importação**.
- **Tipo de importação**: `Layout SellOut_set25.xlsx` → tipo **Sell Out** (tabela `sell_out`);
  `Layout SellOut_meta_set26.xlsx` → tipo **Meta de Sell Out** (tabela `sales_targets`), com as
  datas semanais preservadas (a meta é diária/semanal — 1 registro por semana).
- Observação da reunião: para o fallback de 3 meses "dá para usar a base atual" — o teste do
  caminho primário usa set/25 × set/26; o do fallback usa os meses já existentes no seed.

## 11. Problemas e riscos identificados na reunião

1. **Base sem ano anterior** → fallback 3 meses (seção 3). Caso misto → base única renormalizada.
2. **Viés do trimestre**: usar média, nunca soma, na participação de 3 meses.
3. **Vários planificadores simultâneos** → código sequencial + modelo + parâmetros (seção 8).
4. **Importação manual do roteiro depende do distribuidor** → vídeo/tutorial (fora do escopo de
   código; texto de ajuda na tela).
5. **Meta é por dia; semanas são configuráveis** → sem os intervalos de semana informados não há
   como cruzar meta×semana (por isso o passo 2 do Automático é obrigatório).
6. **Rentabilidade sem custo na base** → aviso explícito (seção 7).
7. **Nomes provisórios** → centralizar labels dos modelos para facilitar renomeação futura.

## 12. Fora de escopo desta entrega (registrado para o futuro)

- **Cross-industry (plus do Marcelo)**: usar outra indústria como base de referência nos modelos
  Batalha Naval (ex.: planificar "Pullman" com o padrão de positivação de "Red Bull"). Sugestão do
  Geraldo na reunião: essa escolha viraria o **primeiro passo** do fluxo. Hoje a base é
  mono-indústria; implementar quando houver multi-indústria.
- **Template visual definitivo do Dashboard** (Eduardo envia; construiremos uma 1ª versão própria).
- **Renomeação dos modelos** (Marcelo).
- **Vídeo/tutorial de importação** do roteiro.

---

## 13. Modelo de dados (src/database)

Todas as tabelas com `distributor_id` (tenancy padrão), RLS habilitada, `SELECT` liberado para
`authenticated` via `current_user_distributor_ids()`; **escrita somente via RPCs `security
definer`** (mantém a regra "sem escrita transacional direta do portal").

### `planner_route_plans` — roteiro de visitas (cabeçalho)

| Coluna | Tipo | Notas |
|---|---|---|
| `id` | `uuid pk default gen_random_uuid()` | |
| `distributor_id` | `uuid not null → distributors` | |
| `week_count` | `smallint not null check (between 3 and 5)` | inferido na importação: maior semana com visita (mínimo 3) |
| `import_id` | `uuid → file_imports` | origem |
| `created_at` | `timestamptz default now()` | |

Nova importação cria novo cabeçalho; o vigente é o mais recente (`created_at desc`).

### `planner_route_visits` — visitas planejadas

| Coluna | Tipo | Notas |
|---|---|---|
| `id` | `bigint identity pk` | |
| `route_plan_id` | `uuid not null → planner_route_plans on delete cascade` | |
| `customer_id` | `uuid not null → customers` | resolvido por `pdv_code` **ou** `cnpj` (dígitos de "CNPJ/CPF Cliente") |
| `sales_rep_id` | `uuid → sales_reps` | |
| `week_number` | `smallint not null check (between 1 and 5)` | |

Unique `(route_plan_id, customer_id, week_number)` — repetições no arquivo = 1 visita/semana.

### `planner_plans` — planificadores gerados

| Coluna | Tipo | Notas |
|---|---|---|
| `id` | `uuid pk` | |
| `distributor_id` | `uuid not null` | |
| `code` | `integer not null` | sequencial por distribuidor (`PLN-001` na UI); unique `(distributor_id, code)` |
| `model` | `planner_model` enum: `automatic`, `battleship_volume`, `battleship_positivation`, `coverage`, `profitability` | |
| `version` | `integer not null default 1` | incrementa a cada Recalcular Rota |
| `status` | `planner_plan_status` enum: `generated`, `replaced` | `replaced` = há versão mais nova do mesmo código |
| `params` | `jsonb not null` | todos os inputs do usuário (mês da meta, semanas com datas, mês/SKU/canal de referência, margem etc.) |
| `route_plan_id` | `uuid → planner_route_plans` | modelos com abertura semanal |
| `created_by` | `uuid → auth.users` | |
| `created_at` | `timestamptz` | |

### `planner_plan_weeks` — semanas do plano

`plan_id uuid → planner_plans on delete cascade` · `week_number smallint` · `start_date date` ·
`end_date date`; unique `(plan_id, week_number)`. Base do cruzamento meta×semana no dashboard.

### `planner_plan_lines` — linhas do plano (cada linha = 1 "plano" no dashboard)

| Coluna | Tipo | Notas |
|---|---|---|
| `id` | `bigint identity pk` | |
| `plan_id` | `uuid not null → planner_plans on delete cascade` | |
| `product_id` | `uuid not null` | |
| `customer_id` | `uuid not null` | |
| `sales_rep_id` | `uuid` | do roteiro (semanal) ou carteira do cliente |
| `channel_id` | `uuid` | segmentação (Batalha Naval/Cobertura/Rentabilidade) |
| `week_number` | `smallint` | null nos modelos sem semana (Cobertura/Rentabilidade) |
| `quantity` | `numeric(14,3)` | volume objetivo (null quando meta é R$) |
| `gross_value` | `numeric(14,2)` | valor objetivo (null quando meta é volume) |

## 14. RPCs (`planner_*`)

Padrão `report_*`: `security definer`, `set search_path = public`, params `p_snake_case`, tenancy
via `authorized_distributor_ids(p_distributor_id)`. Leituras `stable`; gerações `volatile`.
`grant execute` para `authenticated` (exceto `process_route_plans_staging`, que segue o padrão ETL
e é revogada).

Parâmetros com default (`p_channel_ids`, `p_extra_product_ids`, `p_distributor_id`) ficam **por
último** nas assinaturas SQL; `p_distributor_id = null` resolve o distribuidor do usuário.

| RPC | Tipo | Retorno | Uso |
|---|---|---|---|
| `planner_list_target_months(p_distributor_id)` | leitura | `table(month_start, total_quantity, total_value)` | meses com meta ≥ mês atual (passo 1 Automático) |
| `planner_route_plan_summary(p_distributor_id)` | leitura | `jsonb` | roteiro vigente: semanas, visitas por semana, vendedores, data de importação |
| `planner_top_skus(p_reference_month, p_metric volume\|positivation, p_channel_ids, p_extra_product_ids, p_distributor_id)` | leitura | `table(product_id, product_name, ean, positivation, total_quantity, is_extra)` | gráfico top 5 + SKUs extras |
| `planner_sku_participation(p_reference_month, p_reference_product_id, p_channel_ids, p_distributor_id)` | leitura | `table(customer_id, pdv_code, customer_name, channel_id, channel_name, total_quantity, volume_share)` | passo 4 Batalha Naval (preview) |
| `planner_uncovered_customers(p_product_id, p_start_date, p_end_date, p_channel_ids, p_distributor_id)` | leitura | `table(customer_id, pdv_code, customer_name, channel_id, channel_name, sales_rep_id)` | passo 4 Cobertura (preview) |
| `planner_low_margin_customers(p_product_id, p_start_date, p_end_date, p_target_margin, p_channel_ids, p_distributor_id)` | leitura | `table(customer_id, pdv_code, customer_name, channel_id, channel_name, realized_value, realized_quantity, realized_margin, margin_gap, revenue_gap)` | passo 4–5 Rentabilidade (preview); `NO_COST_DATA` sem Sell In no período/fallback |
| `planner_generate_automatic(p_target_month, p_weeks jsonb, p_distributor_id)` | geração | `jsonb {plan_id, code, version, line_count, allocated_quantity, week_target_quantity}` | passos 1–3 Automático |
| `planner_recalculate_route(p_plan_id)` | geração | `jsonb` | Recalcular Rota: nova versão redistribuindo o saldo nas semanas restantes |
| `planner_generate_battleship(p_mode, p_reference_month, p_reference_product_id, p_target_month, p_weeks, p_channel_ids, p_distributor_id)` | geração | `jsonb` (inclui `week_target_quantity`) | BN Volume (`p_mode='volume'`) e BN Positivação (`'positivation'`) |
| `planner_generate_coverage(p_product_id, p_start_date, p_end_date, p_target_kind value\|quantity, p_target_amount, p_execution_start, p_execution_end, p_channel_ids, p_distributor_id)` | geração | `jsonb` | Cobertura (prazo de execução obrigatório) |
| `planner_generate_profitability(p_product_id, p_start_date, p_end_date, p_target_margin, p_execution_start, p_execution_end, p_channel_ids, p_distributor_id)` | geração | `jsonb` | Rentabilidade (prazo de execução obrigatório) |
| `planner_list_plans(p_distributor_id)` | leitura | `table(...)` | listagem/reconsulta (código, modelo, versão, params, autor, data) |
| `planner_plan_lines_page(p_plan_id, p_limit, p_offset)` | leitura | `table(..., distributor_cnpj, total_count)` | linhas paginadas p/ tela e exportações (ordem determinística com tiebreaker `id`) |
| `planner_dashboard(p_plan_id, p_eval_start, p_eval_end)` | leitura | `jsonb` | planejado×realizado: pizza atingido/não, melhor/pior vendedor, quebras por vendedor/cliente/canal/SKU |

### Algoritmos (detalhe)

**Peso histórico (Automático)** — por SKU `p` × semana `w` (universo = PDVs com visita em `w`):
1. semana de referência = mesma semana ISO (`extract(week …)`) do ano anterior;
2. `raw_weight(c) = volume(c,p,ref_week) / volume_total(p,ref_week)` quando o PDV tem venda na
   semana de referência; senão **fallback**: média simples de
   `volume(c,p,mês_i)/volume_total(p,mês_i)` nos 3 meses fechados anteriores ao mês da meta
   (meses sem venda total do SKU não entram na média);
3. renormaliza sobre o universo: `weight(c) = raw(c)/Σ raw` (base única, soma 100%);
4. `quantity(c,p,w) = meta_volume(p,w) × weight(c)` onde
   `meta_volume(p,w) = Σ sales_targets.quantity` com `target_date` dentro da semana `w`.
   Se `Σ raw = 0` (ninguém tem histórico), aquele SKU×semana fica **sem alocação**: linhas
   com volume 0 não são gravadas e a resposta da geração expõe
   `allocated_quantity` × `week_target_quantity` — a UI alerta quando há gap.

**Recalcular Rota** — semanas cujo `end_date < hoje` são "fechadas"; por SKU:
`saldo = max(meta_mês − realizado(mês até hoje), 0)`; redistribui `saldo` entre **todas** as
semanas restantes, proporcionalmente à meta original de cada uma (**confirmado pelo Eduardo em
06/08/2026**; sem meta original nas restantes → divisão igual); dentro da semana aplica a mesma
regra de pesos. Gera **nova versão**
do plano (linhas das semanas fechadas são copiadas como registro histórico; as restantes
substituídas); versão anterior vira `replaced`. Nota: a soma das linhas da nova versão pode
exceder a meta do mês — as semanas fechadas preservam o que foi planejado à época, e o saldo
redistribuído é calculado sobre o realizado, não sobre o plano antigo.

**Batalha Naval Volume** — peso = `% volume` do PDV no SKU de referência no mês de referência
(filtro de canal aplicado); universo = PDVs que positivaram o SKU de referência. Nos passos do
Automático, o peso substitui o histórico (renormalizado por semana sobre os visitados).

**Batalha Naval Positivação** — universo idem (ranqueado por positivação); peso **linear**
(`1/n` por semana, sobre os PDVs do universo visitados na semana).

**Cobertura** — descoberto = cliente ativo do distribuidor **sem** `sell_out` do SKU no período
(canal filtrado via `coalesce(so.channel_id, c.channel_id)` na venda; cadastro do cliente para o
universo); distribuição `p_target_amount / n` por PDV (R$ **ou** volume).

**Rentabilidade** — custo do SKU = preço médio Sell In no período analisado (fallback: média dos
3 meses anteriores ao início; sem Sell In nas duas janelas → `NO_COST_DATA`). Por PDV com venda
do SKU no período: `margem = (preço médio de venda − custo) ÷ preço médio de venda`; abaixo do
objetivo → `receita não capturada = (margem_objetivo − margem) × Σ valor`.

**Dashboard** — realizado por linha: `Σ sell_out` do SKU×PDV no intervalo da semana da linha
(planos semanais) ou, para Cobertura/Rentabilidade, no **prazo de execução gravado no plano**
(escolhido na geração; a tela permite sobrescrever com outro intervalo; mês corrente é o último
fallback para planos antigos sem o campo). Linha atingida = realizado ≥ planejado (na unidade da
linha).

## 15. Importação — tipo novo `ROUTE_PLAN` (Roteiro de Visitas)

Segue o contrato completo de novo tipo (staging + `process_*` + `TABLE_SPECS` nas 2 lambdas +
`file_type_configs` + `lib/import-layouts.ts`):

- `file_type_configs`: código **`ROUTE_PLAN`**, nome "Roteiro de Visitas (Planner)",
  `target_table='planner_route_visits'`, `processing_routine='process_route_plans_staging'`.
- `staging_route_plans` (UNLOGGED): `import_id, line_number, brand_name, distributor_code,
  customer_key, sales_rep_code, week_1..week_5` (todas `text`).
- Aliases: `Marca→brand_name` (ignorada por ora), `CNPJ Distribuidor→distributor_code`,
  `CNPJ/CPF Cliente→customer_key`, `Cód. Vendedor→sales_rep_code`, `Semana N→week_N`
  (`week_4`/`week_5` opcionais, como `Semana 4/5` só existem nos layouts 4/5 semanas).
- `process_route_plans_staging`: resolve cliente por `pdv_code` = dígitos de `customer_key` **ou**
  `cnpj`; vendedor por `code`; célula com qualquer conteúdo (`x`, `X`…) = visita; duplicatas na
  mesma semana colapsam (1 visita/semana); cria `planner_route_plans` com
  `week_count = greatest(3, maior semana com visita)`; rejeições logadas em `file_import_logs`.
- Na amostra atual, `Cód. PDV` dos clientes **é** o CNPJ → o match por dígitos funciona; o risco
  de CNPJ mascarado/não único fica registrado (seção 11).

## 16. Frontend (src/frontend)

Rotas novas sob `app/(portal)/planner/` (UI pt-BR, labels dos modelos centralizados em
`lib/planner.ts` para facilitar a renomeação do Marcelo):

| Rota | Tela |
|---|---|
| `/planner/parametrizacao` | Passo 1 (3/4/5 semanas) + download do modelo + upload do roteiro (pipeline de importação) + resumo do roteiro vigente + texto de ajuda (tutorial) |
| `/planner/automatico` | Wizard: mês da meta → datas das semanas → gerar → resultado + exportação + Recalcular Rota |
| `/planner/batalha-naval-volume` | Wizard: mês/canal de referência → gráfico top SKUs (+ SKUs extras) → SKU referência → participação → passos do Automático |
| `/planner/batalha-naval-positivacao` | Idem, ranqueado por positivação, distribuição linear |
| `/planner/cobertura` | Wizard: SKU/canal/período → PDVs descobertos → meta R$ ou volume → gerar |
| `/planner/rentabilidade` | Wizard: SKU/canal/período → margem objetivo → PDVs abaixo → gerar |
| `/planner/planos` | Listagem dos planificadores gerados (código, modelo, versão, parâmetros) + detalhe com linhas paginadas + exportação |
| `/planner/dashboard` | Seleção do plano → resumo (pizza atingido/não, melhor/pior) + tabela planejado×realizado×variação com toggle vendedor/cliente/canal + exportação |

- A rota antiga `/planner/batalha-naval` (heatmap demo da fase 1) é **substituída** pelos módulos
  acima.
- Repositório `lib/data/planner.ts` com caminho Supabase (RPCs) **e** demo (fixtures em
  `lib/data/demo/planner.ts`; gerações em demo persistem em memória na sessão).
- Tipos em `types/planner.ts` (espelham os retornos das RPCs; mapeamento snake→camel no
  repositório, padrão do projeto).
- Gráficos com `CHART_COLORS` (`lib/theme.ts`); números/datas via `lib/format.ts`; exportações via
  `ExportButton`/`lib/report-export.ts` incluindo código do plano e parâmetros.

## 17. Status da implementação (05/08/2026)

Implementado e validado localmente:

- **Banco**: migrations `20260805170000_add_planner_route_plans.sql` (tabelas, RLS,
  staging, `process_route_plans_staging`, tipo `ROUTE_PLAN`) e
  `20260805170100_add_planner_functions.sql` (todas as RPCs `planner_*`).
- **Cloud**: spec `planner_route_visits` adicionada em `file-validator` e `etl-loader`
  (**pendente** `./build.sh` + `terraform apply` para valer em produção).
- **Frontend**: 8 telas em `/planner/*`, repositório `lib/data/planner.ts` (Supabase +
  demo), `types/planner.ts`, componentes em `components/planner/`, navegação atualizada.
  A tela demo antiga `/planner/batalha-naval` (heatmap fase 1) foi substituída.
- **Evidências** (bases de teste set/25 × meta set/26 + roteiro sintético de 320 PDVs):
  importações sem rejeição; Automático alocou 10.187,59 de 10.187,60 un (arredondamento
  por linha); correlação 1,0 entre pesos da semana 2 e o realizado da semana ISO 37/2025;
  Recalcular Rota criou v2 preservando semanas fechadas; Cobertura distribuiu R$ 1M entre
  5.776 PDVs descobertos; Rentabilidade acusou `NO_COST_DATA` (base sem custo);
  RPCs testadas também via PostgREST com JWT do usuário distribuidor.

**Validação por revisão independente (05/08/2026)**: duas revisões `claude -p` (banco/ETL e
frontend), ambas **aprovado com ressalvas**; todas as ressalvas médias foram corrigidas:

- Importação do roteiro idempotente por `import_id` (arquivos multi-part e redelivery do SQS
  não duplicam mais o cabeçalho) e importação sem visita alguma não cria mais roteiro vigente
  vazio (gera warning no log).
- `Cód. Vendedor` vazio agora rejeita a linha (layout o define como obrigatório).
- Cobertura: filtro de canal aplicado também à venda no `NOT EXISTS` (venda de outro canal não
  conta mais como cobertura). (A checagem de custo por canal na Rentabilidade citada nesta rodada
  foi superada em 06/08: o custo passou a vir do Sell In, que é por SKU, sem canal.)
- `fn_planner_parse_weeks` valida sobreposição de semanas e converte erros de cast em
  `INVALID_WEEKS`; Recalcular Rota concorrente serializado por advisory lock.
- Batalha Naval passou a devolver `week_target_quantity` (alerta de gap na UI, como no
  Automático).
- Frontend: exportações agora usam um snapshot dos parâmetros usados na geração (edições
  posteriores do formulário não vazam); exportar é bloqueado até todas as linhas carregarem;
  trocar canal na Batalha Naval reseta o SKU de referência; labels de modelo 100% via
  `PLANNER_MODEL_LABELS` (menu e exportações); troca de distribuidora (admin) reseta plano
  selecionado no Dashboard/Planificadores; meses de referência excluem o mês corrente.

Limitações conhecidas e aceitas (documentadas):

- **Semana ISO 53**: se o ano anterior não tiver semana 53, a referência desliza para a semana
  seguinte (~1 ano antes); impacto raro e pequeno.
- **Dashboard por cliente**: limitado aos 50 clientes de maior valor planejado
  (`customer_group_limit`); a UI indica o corte e o detalhamento completo sai pela exportação
  de linhas do plano.
- **Recalcular Rota em modo demo** sempre responde `NO_CLOSED_WEEKS` (planos demo não têm
  semana fechada).

**Dúvidas respondidas pelo Eduardo em 06/08/2026** (implementação ajustada no mesmo dia):

- Gráfico top 5 nos dois Batalha Naval: ranquear por **positivação** (vale a planilha, não a
  fala da call) → frontend ajustado (antes o BN Volume ranqueava por volume).
- % de participação com canal "Todos": sobre o **total geral** de vendas do SKU → já era o
  comportamento implementado, confirmado.
- Universo do BN Positivação: **só os PDVs que já compram o SKU de referência** ("replicar a
  positivação do SKU case") → já era o comportamento implementado, confirmado.
- Prazo da meta de Cobertura/Rentabilidade: **o distribuidor escolhe data início/fim na
  geração** → adicionados `p_execution_start`/`p_execution_end` obrigatórios nas duas
  gerações (gravados em `params`); o Dashboard avalia nesse prazo por padrão (tela permite
  sobrescrever; mês corrente é fallback só para planos antigos sem o campo).

**Segunda rodada de respostas do Eduardo (06/08/2026)**:

- Roteiro de visitas: layout confirmado (Marca + CNPJ Distribuidor + Cliente + Vendedor +
  Semana 1..3, podendo ter Semana 4/5; Marca vem na planilha e é desconsiderada por ora) —
  já era o contrato implementado. Um único roteiro serve todos os planificadores simultâneos.
- Recalcular Rota: redistribui entre **todas** as semanas restantes, proporcional ao peso de
  meta de cada semana — confirmou a implementação.
- Semanas sempre dentro do mês da meta → pickers limitados ao mês + validação `INVALID_WEEKS`
  na geração; sugestão padrão de semanas virou segmentos de calendário dom–sáb recortados no mês.
- Custo da Rentabilidade: **preço médio do Sell In** (mesma regra do Status MTD), com fallback
  da média dos 3 meses anteriores quando não há compra no período → `planner_low_margin_customers`
  reescrita; o modelo passou a funcionar com a base real (que não traz custo unitário no Sell Out,
  mas sempre traz Sell In).
- Exportação: além da detalhada, cada plano ganhou **"Exportar p/ roteirização"** no layout
  estrito da planilha (`CNPJ Distribuidor | EAN | Cód. PDV | Semana | Volume`; modelos sem semana:
  `Volume / R$`), garantindo importação limpa no sistema de roteirização do distribuidor.

Decisões de implementação registradas:

- `week_count` do roteiro é inferido da maior semana com visita (mín. 3), pois a
  importação não carrega a escolha do passo 1.

## 18. Plano de validação

1. `supabase db reset` (migrations + seed) sem erro; `npm run typecheck` limpo.
2. Importar (local, via staging/process) `Layout SellOut_set25.xlsx` como `SELL_OUT` e
   `Layout SellOut_meta_set26.xlsx` como `TARGETS`; conferir totais (set/25: 413 linhas válidas,
   Σvol 10.546,81; set/26: 131 linhas, Σvol 10.187,60 — colunas auxiliares ignoradas).
3. Roteiro de visitas de teste → `ROUTE_PLAN` → visitas resolvidas por CNPJ.
4. Gerar Automático set/26: Σ volume das linhas ≈ Σ meta das semanas configuradas; PDV com
   histórico em set/25 recebe peso da semana ISO correspondente; PDV novo cai no fallback 3m.
5. Recalcular Rota: saldo = meta − realizado; semanas fechadas preservadas.
6. BN Volume/Positivação: top 5 por positivação confere com contagem manual; pesos somam 100%.
7. Cobertura: PDV com venda no período não aparece; linear = valor/n.
8. Rentabilidade: com seed sem custo → `NO_COST_DATA`; com custo sintético → gap correto.
9. Navegar todas as telas em modo demo (`npm run dev` sem `.env.local`) e modo completo.
