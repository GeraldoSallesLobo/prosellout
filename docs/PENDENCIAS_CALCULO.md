# Decisões de cálculo

Decisões recebidas da equipe ProSellOut para fechar as lacunas do gabarito/Excel de referência (`ProSellout_sistema_excel.xlsx`).

## 1. Mark Up

Mark Up é percentual: `Preço Médio Sell Out ÷ Preço Médio Sell In − 1`.

## 2. Preço de Sell In nas dimensões de cliente

Markup, Margem, Giro Médio e os desdobramentos Canal, Vendedor e Cluster são calculados na visão Sell Out. O Sell In entra apenas como base de preço médio por distribuidor/produto dentro do recorte de Sell Out.

## 3. Fórmulas de Giro Médio e Cobertura Média

Atualização de 13/08/2026 (`Memória de Cálculo_2.docx`):

- **Giro Médio** = Volume Estoque ÷ Volume Sell Out — a fórmula que antes alimentava Cobertura Média. Para a meta: `(Meta Sell In Un − Meta Sell Out Un) ÷ Meta Sell Out Un`. A fórmula financeira anterior (`Fat R$ Sell Out ÷ (Fat R$ Sell Out − Fat R$ Sell In)`) deixou de ser usada.
- **Cobertura Média** = Volume Estoque ÷ número de dias corridos do período (inclusivo: `data final − data inicial + 1`). Atual, Meta e Ano Anterior usam a quantidade de dias de seus respectivos intervalos.
- **Volume Estoque (nestes indicadores)** = Volume Sell In do período − Volume Sell Out do período. Não usa a posição acumulada desde o D0 exibida em **Dados › Estoque**.

## 4. Estoque

Não existe layout/importação de estoque. A tela **Dados › Estoque** deve mostrar
posição por distribuidora/produto, sem cliente/vendedor, calculada até a data de
referência selecionada.

Saldo negativo não deve ser travado em zero; ele deve aparecer em vermelho como
alerta de inconsistência nos dados de Sell In/Sell Out.

## 5. Denominador da Probabilidade Cobertura

Regra atual validada em 19/07/2026: `Cobertura Atual / Cobertura Meta`, com resultado capado em 100%.

## 6. O que conta como "pedido/entrega" (Drop Size)

Atualização de 13/08/2026: **Drop Size = Faturamento R$ Sell Out ÷ número de pedidos/entregas do período**, exibido como moeda (R$). A regra anterior (`Volume Sell Out ÷ Cobertura`, validada em 19/07/2026) deixou de ser usada.

- Cada registro elegível de Sell Out conta uma vez (`count(*)` após filtros); `invoice_number` não agrupa nem deduplica o denominador, pois o ETL sintetiza um identificador por linha.
- O recorte temporal usa exclusivamente a Data Faturamento (`invoice_date`); a Data Entrega não move o registro de período, e registro sem Data Entrega continua contando.
- Para a meta, o denominador é `count(*)` dos registros de `sales_targets` no período de meta.

Para prazo/lead time, o conceito segue sendo a quantidade de dias entre faturamento e entrega (colunas G e H das planilhas de Sell Out).
