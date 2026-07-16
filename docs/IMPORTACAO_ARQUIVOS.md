# Importação de Arquivos

Este documento define quais arquivos o portal aceita em **Arquivos › Importação** e o que cada tipo alimenta no sistema.

A importação não é um parser livre de qualquer planilha. Cada arquivo precisa ser enviado com um **tipo de arquivo** em **Arquivos › Importação**, e esse tipo aponta para uma tabela de destino e uma rotina de processamento cadastradas em **Arquivos › Configuração**.

O arquivo pode ser `.xlsx` ou `.csv`. A primeira linha deve conter os cabeçalhos. O `file-validator` aceita alguns aliases de cabeçalho, normaliza acentos/pontuação e rejeita a importação quando faltam colunas essenciais. Linhas com dados inválidos são registradas em `file_import_logs` e aparecem no log da tela de importação.

## Como funciona

1. O usuário escolhe o tipo de arquivo e envia o arquivo pelo portal.
2. O frontend cria uma linha em `file_imports`.
3. O frontend chama `NEXT_PUBLIC_UPLOAD_API_URL` para obter uma URL pré-assinada.
4. O navegador faz `PUT` do arquivo direto no S3.
5. A Lambda `file-validator` lê cabeçalhos e linhas, normaliza os dados e fatia o arquivo em partes CSV canônicas.
6. A Lambda `etl-loader` faz `COPY` para staging e chama `process_*_staging`.
7. A rotina cruza dados por distribuidor, PDV, EAN e vendedor, grava a tabela final e registra rejeições por linha.

## Logs de erro

A tela **Arquivos › Importação** mostra logs por linha quando uma importação falha
ou conclui com erros. Esses logs são texto para usuário final e devem indicar:

- o campo ou cadastro que falhou;
- o valor recebido no arquivo;
- a correção provável ou a base que precisa ser importada antes.

Exemplos de causas esperadas:

| Causa | Mensagem esperada no log |
|---|---|
| CNPJ/código do distribuidor não bate com a conta | Informa o valor recebido na planilha e o código/CNPJ esperado para o distribuidor da conta. |
| Colunas obrigatórias ausentes | Lista as colunas que faltaram e orienta conferir **Arquivos › Configuração**. |
| Cliente não encontrado | Em **Meta**, informa o PDV/CNPJ recebido e orienta importar ou ajustar **Clientes**. Em **Sell Out**, quando `Cód. PDV` existe no arquivo, o sistema cria um PDV mínimo automaticamente para preservar as vendas. |
| Produto não encontrado | Informa o EAN recebido e orienta importar ou ajustar **Hier. Produtos** antes de Sell In/Sell Out/Meta. |
| Vendedor não encontrado | Informa o código recebido e orienta importar ou ajustar **Vendedores** antes de Sell Out/Meta. |
| Data ou número inválido | Mostra o valor inválido e o formato esperado. |

## Ordem recomendada

Para uma base nova, importe nesta ordem:

1. `PRODUCTS` — produtos e hierarquia de produtos.
2. `SELLERS` — vendedores e supervisores.
3. `CUSTOMERS` — clientes/PDVs.
4. `TARGETS` — metas por cliente/SKU/vendedor/mês.
5. `SELL_IN` — compras/entrada por produto.
6. `SELL_OUT` — vendas para PDV por produto.

## Travas no frontend

A tela **Arquivos › Importação** mostra os layouts esperados e bloqueia o botão de envio quando o tipo escolhido depende de bases que ainda não têm importação concluída no histórico (`completed` ou `completed_with_errors` em `file_imports`).

Matriz de dependências:

| Tipo | Pode ser primeiro? | Pré-requisitos para enviar |
|---|---:|---|
| `PRODUCTS` | Sim | Nenhum |
| `SELLERS` | Sim | Nenhum |
| `CUSTOMERS` | Sim | Nenhum |
| `TARGETS` | Não | Hier. Produtos + Vendedores + Clientes |
| `SELL_IN` | Não | Hier. Produtos |
| `SELL_OUT` | Não | Hier. Produtos + Vendedores + Clientes |

`SELL_OUT` exige `SELLERS` no frontend para evitar vendas sem vínculo de vendedor, o que quebraria análises por vendedor/supervisor mesmo que a linha transacional pudesse ser gravada sem esse vínculo.

## Status atual

Em código, os tipos `PRODUCTS`, `SELLERS`, `CUSTOMERS`, `TARGETS`, `SELL_IN` e `SELL_OUT` já têm contrato completo entre frontend, AWS Lambdas e Supabase:

- `file_type_configs` ativo;
- staging table;
- rotina `process_*_staging`;
- spec no `file-validator`;
- spec equivalente no `etl-loader`;
- layout exibido no frontend.

O deploy AWS de produção foi realizado com Terraform na conta `071604987536`
(`sa-east-1`). Para ativar no portal, configure o output `upload_api_url` em
`NEXT_PUBLIC_UPLOAD_API_URL` na Vercel e faça redeploy. O roteiro completo de
deploy/QA está em `docs/DEPLOY_AWS_IMPORTACAO.md`.

`STOCK` não é importado por arquivo próprio. A tela **Dados › Estoque** calcula
a posição por produto usando `Sell In` acumulado menos `Sell Out` acumulado até
a data de referência. `PLANNER` continua planejado até existir amostra real e
contrato fechado.

## Pendência estrutural: Indústria/Marca

A validação recebida em 12/07/2026 definiu que o usuário deverá escolher uma
**indústria/marca** ao acessar o ProSellOut e que os layouts passarão a trazer
uma coluna `Marca` à esquerda de `CNPJ Distribuidor`.

Em 13/07/2026 foi confirmado que a regra futura será:

- `Marca` obrigatória em Clientes, Hier. Produtos, Vendedores, Meta, Sell In e Sell Out;
- o mesmo nome/código de marca deve aparecer de forma consistente em todos os arquivos;
- clientes, produtos, vendedores, metas, Sell In e Sell Out serão vinculados a uma marca;
- a visão "todas as marcas" deverá somar os dados de todas as marcas do distribuidor.

Isso ainda não é um contrato implementado. Para o QA atual, a orientação validada
é manter a estrutura sem `Marca`, assumindo uma indústria padrão. Hoje o validador
ignora colunas extras não mapeadas, então um arquivo com `Marca` adicional pode
continuar sendo processado, mas o valor não segmenta dados nem aparece nos filtros.

Antes de implementar a dimensão, ainda falta receber:

- lista de marcas/indústrias válidas para os arquivos de teste;
- nome/código exato que virá na coluna `Marca`;
- exemplo atualizado de cada layout com a nova coluna;
- confirmação se Clientes e Vendedores podem se repetir em marcas diferentes;
- definição de cadastro/fonte das marcas válidas por distribuidor;
- regra de migração dos dados já importados para uma marca inicial.

## Tipos suportados

### CUSTOMERS — Clientes

- Tela alimentada: **Dados › Clientes**
- Tabela final: `customers`
- Rotina: `process_customers_staging`

Colunas obrigatórias:

- `CNPJ Distribuidor`
- `Cód. PDV`
- `Razão Social`

Colunas opcionais:

- `CNPJ/CPF`
- `Nome Fantasia`
- `Endereço`
- `Bairro`
- `Cidade`
- `UF`
- `CEP`
- `Canal do PDV`
- `CLUSTER`

Notas:

- O cliente é identificado por distribuidor + `Cód. PDV`.
- Canal e cluster são criados/reativados automaticamente quando informados.

### PRODUCTS — Hier. Produtos

- Tela alimentada: **Cadastros › Hierarquia de Produtos** e cruzamentos de relatórios
- Tabelas finais: `products`, `product_hierarchy`
- Rotina: `process_products_staging`

Colunas obrigatórias:

- `CNPJ Distribuidor`
- `EAN`
- `Descrição`
- `SubCategoria`
- `Categoria`
- `Macrocategoria`

Colunas opcionais:

- `Caixa`
- `Unidades`
- `CÓD SKU`

Notas:

- A hierarquia é criada como `Macrocategoria › Categoria › SubCategoria`.
- EAN de 13 e 14 dígitos é normalizado no cruzamento com sell-out/sell-in.
- Se `Unidades` vier vazio, o sistema assume 1.

### SELLERS — Vendedores

- Tela alimentada: **Dados › Vendedores** e hierarquia comercial
- Tabela final: `sales_reps`
- Rotina: `process_sellers_staging`

Colunas obrigatórias:

- `CNPJ Distribuidor`
- `Cód. Vendedor`
- `Nome Vendedor`
- `Cód. Supervisor`

Colunas opcionais:

- `Quantidade clientes (carteira)`
- `Nome Supervisor`
- `Cód. Gerente`
- `Nome Gerente`

Notas:

- Supervisores são criados automaticamente pelo código informado.
- Gerente é preservado no layout, mas ainda não alimenta uma hierarquia própria.

### TARGETS — Meta

- Tela alimentada: **Dados › Meta**
- Tabela final: `sales_targets`
- Rotina: `process_targets_staging`

Colunas obrigatórias:

- `CNPJ Distribuidor`
- `EAN`
- `Cód. PDV`
- `Cód. Vendedor`
- `Volume Total de Unidades NF`
- `Valor Total R$ NF`
- `Data Faturamento`

Colunas opcionais:

- `Data Entrega`
- `CNPJ/CPF`

Notas:

- `Data Faturamento` define o mês da meta.
- A meta é vinculada ao cliente, produto, vendedor e mês.
- Linhas repetidas no mesmo cliente + SKU + vendedor + mês são somadas dentro da importação.
- Uma nova importação de Meta substitui as metas anteriores dos meses presentes no arquivo. Isso permite reenviar uma base corrigida sem manter metas que foram removidas da planilha.

### SELL_OUT — Sell Out

- Tela alimentada: **Dados › Sell Out**
- Tabela final: `sell_out`
- Rotina: `process_sell_out_staging`

Colunas obrigatórias:

- `CNPJ Distribuidor`
- `EAN`
- `Cód. PDV`
- `Cód. Vendedor`
- `Volume Total de Unidades NF`
- `Valor Total R$ NF`
- `Data Faturamento`

Colunas opcionais:

- `Data Entrega`
- `NF`
- `Custo Unitário`
- `CNPJ/CPF`

Notas:

- Produto e vendedor precisam existir para alimentar os relatórios corretamente.
- Quando o `Cód. PDV` não existe em **Clientes**, o Sell Out cria um cadastro mínimo `PDV <código>` para que a venda entre nos totais; depois o usuário pode completar canal, cluster e demais dados cadastrais em **Clientes**.
- Quando `NF` não vem no arquivo, o sistema cria um número técnico por linha importada.

### SELL_IN — Sell In

- Tela alimentada: **Dados › Sell In**
- Tabela final: `sell_in`
- Rotina: `process_sell_in_staging`

Colunas obrigatórias:

- `CNPJ Distribuidor`
- `EAN`
- `Volume Total de Unidades NF`
- `Valor Total R$ NF`
- `Data de Faturamento`

Colunas opcionais:

- `NF`
- `Custo Unitário`

Notas:

- Produto precisa existir em **Hier. Produtos**.
- Quando `NF` não vem no arquivo, o sistema cria um número técnico por linha importada.

## Tipos calculados

### STOCK — Estoque

- Tela alimentada: **Dados › Estoque**
- Fonte: `sell_in` e `sell_out`
- Rotina: `fetch_stock_position`

Regras:

- Quantidade = `Sell In` acumulado − `Sell Out` acumulado até a data de referência.
- Saldo negativo é exibido em vermelho como alerta de inconsistência de dados.
- Valor Sell In = soma acumulada do valor informado nos arquivos de Sell In.

Se no futuro uma base física de estoque virar fonte oficial, será necessário
reabrir o contrato e revisar a Cobertura Média antes de trocar a fonte.

## Tipos planejados

### PLANNER — Batalha Naval

- Tela prevista: **Planificador › Batalha Naval**
- Tabela final prevista: ainda não definida.
- Status: aguardando amostra real para decidir se será importação própria ou cálculo derivado.

Contrato sugerido para amostra:

- `Cód. PDV`
- `EAN`
- `Cód. Vendedor`
- `Prioridade` ou `Recomendação`
- `Volume Sugerido` opcional
- `Valor Sugerido` opcional
- `Motivo` opcional
- `Data Referência` opcional

Observação: a tela atual usa uma matriz demo cliente × SKU. A amostra real vai definir se `PLANNER` vira tabela própria ou uma RPC calculada a partir de clientes, produtos, vendedores, metas e sell-out.
