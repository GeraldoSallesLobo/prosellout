# Validação com a amostra real

A pasta `.dev_files/dados-importacao` traz uma amostra real (um distribuidor, dados LGPD-mascarados). Usamos ela para (1) validar o sistema com números corretos e (2) corrigir lacunas do schema.

## Como carregar

O seed já foi gerado a partir da amostra (`src/database/supabase/seed.sql`). Para recarregar:

```bash
cd src/database
supabase db reset      # aplica migrations + seed real
```

Para regerar o seed a partir dos arquivos (se a amostra mudar):

```bash
python3 src/database/scripts/generate_seed_from_sample.py
```

## O que o seed carrega

| Entidade | Qtd | Origem |
|---|---|---|
| Distribuidor | 1 | CNPJ 83299743000130 |
| Canais | 7 | Layout Clientes (Canal do PDV) |
| Clusters | 2 | Base, Novos |
| Hierarquia produtos | 2 macro / 2 cat / 3 sub | Layout Produtos |
| Produtos (SKU) | 5 | Layout Produtos |
| Supervisores / Vendedores | 3 / 10 | Layout Vendedores |
| Clientes (PDVs) | ~6.122 | Layout Clientes (+ stubs de PDVs só vistos no Sell Out) |
| Sell Out | 3.057 | Layout SellOut + SellOut_aa (linhas sem volume/valor são ignoradas) |
| Sell In | 30 | Layout SellIn + SellIn_aa |
| Meta Sell Out | 1.436 | Layout SellOut_meta (agregada por cliente/produto/vendedor/data) |
| Meta Sell In | importação manual | Layout SellIn_meta (agregada por distribuidor/produto/mês) |

Números-âncora para conferir no Status MTD (Junho/2026): Sell Out R$ ≈ 1.000.563, Un ≈ 14.188, Cobertura ≈ 327 PDVs, Ticket Médio ≈ R$ 3.059, Preço Médio ≈ R$ 70,52.

## Lacunas de schema corrigidas (nas migrations base)

Ao cruzar a amostra com o schema, encontramos e corrigimos:

1. **Sell Out/Sell In sem número de NF** → `invoice_number` agora é opcional. Quando o upload não traz NF, o ETL sintetiza uma identificação por importação/linha para manter rastreabilidade.
2. **Identidade do cliente é (distribuidor, Cód. PDV)** — o CNPJ vem mascarado e não é único. Adicionadas colunas `pdv_code`, `distributor_id`, `trade_name`, `address`; `cnpj` virou opcional; nova unicidade `(distributor_id, pdv_code)`.
3. **Vendedor é transacional** (vem em cada linha de Sell Out), não é atributo fixo do cliente — o `sell_out.sales_rep_id` já cobre isso.
   A mesma regra vale para Meta Sell Out: `Layout SellOut_meta.xlsx` traz `Cód. Vendedor` e o sistema grava `sales_targets.sales_rep_id` para calcular metas por vendedor.
4. **Hierarquia comercial tem códigos e Gerente opcional** acima do Supervisor — adicionados `code`, `distributor_id`, `portfolio_size` (carteira) e `manager_id` em `sales_reps`.
5. **Produtos têm caixa/unidades e escopo por distribuidor** — adicionados `box_count` e `distributor_id`.
6. **EAN aparece em 13 e 14 dígitos** (DUN-14 com "1" na frente) — função `fn_ean_core` normaliza para o núcleo de 13 dígitos ao cruzar Sell In × Produtos.

## Decisões posteriores

- **Estoque**: não existe planilha de estoque. A tela **Dados › Estoque** calcula a posição como `Sell In volume acumulado - Sell Out volume acumulado` até a data de referência. Saldo negativo deve ser exibido como alerta de inconsistência.
- **Meta Sell Out com PDV ausente em Clientes**: a regra validada é rejeitar a linha e registrar alerta no log. O usuário deve adicionar o PDV em **Clientes** ou ajustar a Meta Sell Out antes de importar novamente. Em 13/07/2026, `Layout SellOut_meta.xlsx` foi substituído por uma versão corrigida com 1.436 linhas e sem PDVs ausentes na base de Clientes. Reenvios de Meta Sell Out substituem as metas anteriores das datas presentes no arquivo.
- **Data da Meta Sell Out**: `Data Faturamento` é a data diária da meta, não apenas o mês. Relatórios e Fast Facts devem somar as linhas de Meta Sell Out no intervalo filtrado, com o mesmo racional usado para Sell Out realizado.
- **Sell Out com PDV ausente em Clientes**: o sistema cria um cliente mínimo `PDV <código>` quando o arquivo informa `Cód. PDV`, produto e vendedor válidos. Isso preserva o faturamento/volume real do Sell Out e deixa o cadastro disponível para enriquecimento posterior em **Dados › Clientes**.
- **Status MTD e Cobertura**: a planilha Excel de referência é mensal. Sem SKU específico, o Status MTD soma valor/volume no intervalo selecionado, mas calcula `Cobertura` e `Ticket Médio` usando os PDVs do mês inicial de cada período. Com um ou mais SKUs selecionados, a cobertura usa os PDVs únicos do intervalo selecionado.
- **Mark Up**: a regra validada é `Preço Médio Sell Out / Preço Médio Sell In - 1`, exibida como percentual.
- **Meta Sell In**: `Layout SellIn_meta.xlsx` é um tipo próprio (`SELL_IN_TARGETS`) e não deve ser importado como `SELL_IN` nem como `TARGETS`. Ele alimenta a coluna **Meta** de `Mark Up %`, `Margem %`, `Giro Médio` e `Cobertura Média` no **Status MTD**, comparando Meta Sell Out contra Meta Sell In.
- **Filtros múltiplos**: Categoria, Subcategoria, SKU, Canal e Cluster aceitam múltipla seleção nos relatórios. Seleção vazia equivale a "todos".
- **Drop Size**: a regra validada em 19/07/2026 é `Volume Sell Out / Cobertura`, não volume por nota. Isso vale para atual, meta e ano anterior.
- **Probabilidade Cobertura**: usa `Cobertura Atual / Cobertura Meta`, capada em 100%. As probabilidades de Sell Out R$ e Ticket Médio também são capadas em 100%.
- **Fast Facts sem meta**: quando uma dimensão tem Sell Out realizado no período, mas não tem Meta Sell Out, ela entra no donut como **na meta**. O comparativo **vs Meta** permanece vazio porque não há denominador para percentual.
- **Fast Facts por Canais**: usa o canal transacional informado em Sell Out/Meta Sell Out quando ele existir; se o arquivo não trouxer canal, usa o canal cadastrado em **Clientes** como fallback.
- **Ano anterior nos relatórios**: o filtro padrão usa o mesmo intervalo de dia/mês no ano anterior. Estados antigos salvos no navegador em que "Ano Anterior" era igual ao período atual são normalizados para o ano anterior.
- **Indústria/Marca**: foi confirmado que a próxima estrutura terá `Marca` obrigatória em todos os layouts, vínculo por marca e visão "todas as marcas" somada por distribuidor. Para o QA atual, a estrutura permanece sem `Marca`, assumindo uma indústria padrão.

## Follow-ups (não feitos ainda)

- **Indústria/Marca**: a próxima versão precisa criar a dimensão de indústria/marca, adicionar seletor ao acesso/portal e consumir a nova coluna `Marca` nos layouts. Ainda faltam a lista de marcas, o nome/código exato, exemplos atualizados dos layouts e a confirmação sobre repetição de Clientes/Vendedores entre marcas.
- **Multi-distribuidor**: a amostra tem 1 distribuidor; produto/EAN globalmente único ainda vale. Para vários distribuidores, revisar unicidade de EAN por distribuidor.
