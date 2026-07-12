# Decisões de cálculo

Decisões recebidas da equipe ProSellOut para fechar as lacunas do gabarito/Excel de referência (`ProSellout_sistema_excel.xlsx`).

## 1. Mark Up

Mark Up é percentual: `Preço Médio Sell Out ÷ Preço Médio Sell In − 1`.

## 2. Preço de Sell In nas dimensões de cliente

Markup, Margem, Giro Médio e os desdobramentos Canal, Vendedor e Cluster são calculados na visão Sell Out. O Sell In entra apenas como base de preço médio por distribuidor/produto dentro do recorte de Sell Out.

## 3. Fórmulas de Giro Médio e Cobertura Média

- **Giro Médio** = Fat R$ Sell Out ÷ (Fat R$ Sell Out − Fat R$ Sell In)
- **Cobertura Média** = Volume Estoque ÷ Volume Sell Out
- **Volume Estoque** = Volume Sell In acumulado desde o D0 − Volume Sell Out acumulado desde o D0 até a data de referência.

## 4. Estoque

Não existe layout/importação de estoque. A tela **Dados › Estoque** deve mostrar
posição por distribuidora/produto, sem cliente/vendedor, calculada até a data de
referência selecionada.

Saldo negativo não deve ser travado em zero; ele deve aparecer em vermelho como
alerta de inconsistência nos dados de Sell In/Sell Out.

## 5. Denominador da Probabilidade Cobertura

Quando a hierarquia de vendas estiver em **Todos**, o denominador é a base total de clientes cadastrados. Quando houver recorte por vendedor ou supervisor, o denominador é a quantidade de clientes da respectiva carteira na planilha "Layout Vendedores".

## 6. O que conta como "nota" (Drop Size)

Cada linha das planilhas `SellOut...` equivale a uma NF. Para prazo/lead time, o conceito é a quantidade de dias entre faturamento e entrega (colunas G e H das planilhas de Sell Out).
