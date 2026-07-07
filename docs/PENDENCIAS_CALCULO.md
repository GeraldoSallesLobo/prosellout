# Pendências de cálculo — perguntas para o CEO

Pontos que nem o gabarito nem o Excel de referência (`ProSellout_sistema_excel.xlsx`) resolvem — os valores lá são digitados à mão ou usam escalas de mockup. Precisamos da definição do negócio para implementar.

## 1. Mark Up — razão ou percentual?

O gabarito define `Markup = Preço Médio Sell Out ÷ Preço Médio Sell In` (ex.: 1,25). No Excel o valor aparece como percentual (`0,25` = 25%) e a variação é `Atual/Meta − 1`.

- **Como exibir?** Razão/fator (1,25×) ou percentual (25% = razão − 1)?
- Isso define o rótulo: "Mark Up" (fator) vs "Mark Up %" (percentual).

## 2. Preço de Sell In nas dimensões de cliente

Markup, Margem e Giro Médio dependem do preço médio de Sell In. Mas o Sell In tem apenas **distribuidor + produto** — não tem canal, cluster nem vendedor (confirmado na amostra real). Como calcular nas telas agrupadas por Canal / Vendedor / Cluster?

- **Opção A** — usar o preço médio de Sell In do conjunto de produtos do recorte (ponderado pelo volume), em todas as telas.
- **Opção B** — mostrar Markup/Margem/Giro apenas nos níveis com ligação direta a produto (SKU/Categoria); ocultar nas telas por Canal/Vendedor/Cluster.

## 3. Fórmulas de Giro Médio e Cobertura Média

Serão adicionadas ao Status MTD e à Análise. Confirmar:

- **Giro Médio** = Fat R$ Sell Out ÷ (Fat R$ Sell Out − Fat R$ Sell In)
- **Cobertura Média** = Volume Estoque ÷ Volume Sell Out

Dependem da pergunta 2 (Sell In e Estoque só têm distribuidor + produto). Além disso, **não há arquivo de Estoque na amostra** → Cobertura Média não é validável sem a base de estoque.

## 4. Denominador da Probabilidade Cobertura

A fórmula (Cobertura ÷ total de PDVs) **já funciona automaticamente** — não é bloqueio técnico. A dúvida é apenas de **definição de negócio**: qual fonte deve ser o "total de PDVs", já que cada uma dá um resultado diferente.

Hoje o sistema usa a **contagem de clientes ativos** da base (filtrada por canal/cluster/vendedor). Confirmar se é essa a definição correta ou se deve ser outra:

| Fonte | Total na amostra | Prob. Cobertura resultante* |
|---|---|---|
| Clientes ativos da base (atual) | ~6.095 | menor (base maior) |
| Carteira dos vendedores ("Quantidade clientes") | 3.000 | ~2× maior |
| Coluna A do Layout Planificador (citada no gabarito) | não importado | a definir |

*Para uma mesma cobertura realizada, quanto menor o denominador, maior a probabilidade.

**Pergunta ao CEO:** o "total de PDVs" da Prob. Cobertura é a base total de clientes cadastrados, a soma das carteiras dos vendedores, ou a lista do Planificador? (Se for a base de clientes, nada muda — já é o que o sistema faz.)

## 5. O que conta como "nota" (Drop Size)

O Sell Out real **não tem número de NF**. Drop Size = Sell Out Un ÷ nº de notas. Como definir "nota"?

- Uma nota por PDV/dia (aproximação usada hoje no seed: `invoice_number = pdv-data`), ou
- Outro critério (por PDV/vendedor/dia, etc.).
