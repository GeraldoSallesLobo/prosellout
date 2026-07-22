# Plano de Desenvolvimento — API de Importação de Dados

## Objetivo

Criar uma API pública para empresas/distribuidores alimentarem o ProSellOut sem depender do envio manual de planilhas na tela **Arquivos > Importação**.

A API deve suportar tudo que hoje entra pelo fluxo manual:

- `PRODUCTS` — hierarquia de produtos;
- `SELLERS` — vendedores e supervisores;
- `CUSTOMERS` — clientes/PDVs;
- `TARGETS` — Meta Sell Out;
- `SELL_IN_TARGETS` — Meta Sell In;
- `SELL_IN` — compras/entrada;
- `SELL_OUT` — vendas para PDV.

`STOCK` permanece calculado por `Sell In acumulado - Sell Out acumulado`, como hoje. `PLANNER` continua fora do contrato ate existir amostra real e regra fechada.

## Estado atual

Hoje o fluxo manual funciona assim:

```text
Frontend
  cria file_imports
  pede URL pre-assinada
  envia arquivo para S3

AWS S3
  dispara file-validator

Lambda file-validator
  le xlsx/csv
  normaliza cabecalhos, datas e numeros
  gera CSV canonico em parts/
  envia mensagens para SQS

Lambda etl-loader
  faz COPY para staging_* UNLOGGED
  chama process_*_staging(import_id)
  finaliza file_imports
  chama refresh_report_views()

Supabase/Postgres
  valida FKs e regras de negocio
  grava tabelas finais
  registra rejeicoes em file_import_logs
```

As partes mais importantes a preservar sao:

- auditoria por importacao em `file_imports`;
- logs por linha em `file_import_logs`;
- validacao set-based nas funcoes `process_*_staging`;
- carga em lote via `COPY`, sem `INSERT` linha a linha;
- refresh das materialized views apos concluir a importacao;
- mesmas regras de dependencias entre tipos de dados.

## Decisao arquitetural recomendada

Nao criar um caminho paralelo que grave direto nas tabelas finais. A API deve alimentar o mesmo contrato canonico usado pelo pipeline atual.

Arquitetura recomendada:

```text
Empresa cliente
  POST /v1/imports
  PUT /v1/imports/{id}/batches
  POST /v1/imports/{id}/complete

Cloudflare Worker API
  autentica API key/HMAC
  aplica rate limit e CORS/API Shield/WAF
  valida contrato JSON
  cria/consulta importacoes no Supabase
  encaminha lotes canonicos para AWS

AWS ingestion
  grava partes canonicas em S3 parts/
  envia mensagens para SQS
  reutiliza etl-loader atual

Supabase
  file_imports + file_import_logs
  staging_* + process_*_staging
  tabelas finais + refresh_report_views()
```

Motivo: Cloudflare fica como borda publica e camada de protecao/documentacao da API; AWS continua responsavel pelo processamento pesado e pelo pipeline S3/SQS/Lambda ja existente; Supabase continua como fonte de verdade e motor das validacoes.

## Impacto por camada

### Cloudflare

Criar uma API publica separada do frontend, preferencialmente como Worker dedicado.

Responsabilidades:

- autenticar clientes por API key, HMAC ou ambos;
- aplicar rate limit por cliente/distribuidor;
- validar tamanho de payload e formato JSON antes de acionar AWS;
- retornar `202 Accepted` para cargas assincronas;
- expor endpoint de status/logs;
- gerar `request_id`/`correlation_id` para observabilidade;
- proteger a API com WAF/rules e, se necessario, allowlist de IP por cliente.

Observacao: o frontend ja tem configuracao OpenNext/Cloudflare (`wrangler.jsonc`). Este plano recomenda nao acoplar a API de integracao ao Worker do frontend, para evitar misturar deploy de portal com contrato externo de empresas.

### Supabase/Postgres

Manter `file_imports`, `file_import_logs`, `staging_*` e `process_*_staging` como base do contrato.

Mudancas recomendadas:

- adicionar origem da importacao em `file_imports`, por exemplo `source = manual_upload | api`;
- adicionar `api_client_id` em `file_imports`;
- adicionar `external_reference` opcional para identificador do lado da empresa;
- adicionar `idempotency_key` com unicidade por cliente/tipo;
- adicionar `metadata jsonb` para payload resumido, versao da API, sistema de origem e contadores;
- criar tabelas de credenciais, por exemplo `api_clients` e `api_client_keys`, com chaves armazenadas apenas em hash;
- criar escopos por cliente: tipos permitidos, distribuidor permitido, status, limites e data de expiracao;
- manter funcoes de ETL revogadas de `anon`/`authenticated`; somente backend server-side deve chamar essas rotinas.

Pontos de atencao:

- `TARGETS` substitui metas de Sell Out por data importada; `SELL_IN_TARGETS` substitui metas de Sell In mensalmente. A API precisa documentar isso com destaque.
- `SELL_OUT` e `SELL_IN` dependem de particoes mensais. As funcoes atuais ja chamam `ensure_month_partition`.
- a dimensao futura **Marca/Industria** ainda nao esta implementada. Nao deve ser prometida na documentacao externa ate o contrato estar fechado.

### AWS

Reutilizar o `etl-loader` atual e criar uma entrada propria para cargas JSON/API.

Mudancas recomendadas:

- criar uma Lambda `api-ingest` ou adaptar uma Lambda nova no pacote `src/cloud/lambdas/`;
- receber lotes canonicos vindos da Cloudflare API;
- escrever CSV canonico em `s3://.../parts/{importId}/part-0001.csv`;
- enviar mensagem SQS no mesmo formato usado hoje: `importId`, `partKey`, `bucket`, `targetTable`;
- manter `etl-loader` como consumidor unico do SQS;
- mover `TABLE_SPECS` para modulo compartilhado entre `file-validator`, `etl-loader` e `api-ingest`, evitando divergencia de ordem de colunas;
- adicionar alarmes CloudWatch para falhas da nova Lambda e volume anormal de rejeicoes;
- manter DLQ e retry via SQS.

Alternativa possivel: Cloudflare Worker assinar chamadas AWS diretamente e gravar em S3/SQS. Isso reduz uma Lambda, mas aumenta complexidade de IAM/secrets na borda. Para MVP, a Lambda `api-ingest` tende a ser mais simples de operar.

### Frontend

O portal nao precisa ser o caminho principal da API, mas precisa ter uma area para o distribuidor administrar suas credenciais de integracao.

Impactos:

- criar tela **Configuracao > API** ou **Arquivos > Integracoes** para gerar tokens de API;
- permitir que o distribuidor gere um token por sistema externo, por exemplo ERP, BI ou integrador;
- exibir o token completo somente uma vez, no momento da criacao;
- depois da criacao, mostrar apenas prefixo/sufixo mascarado, nome, escopos, criador, data de criacao, ultimo uso e status;
- permitir revogar token imediatamente;
- permitir rotacionar token criando uma nova chave e desativando a antiga apos janela de transicao;
- permitir limitar escopos por tipo: `PRODUCTS`, `SELLERS`, `CUSTOMERS`, `TARGETS`, `SELL_IN_TARGETS`, `SELL_IN`, `SELL_OUT`;
- permitir definir limites por token, como registros por lote, requests por minuto e data de expiracao opcional;
- tela **Arquivos > Importacao** deve exibir importacoes `source = api`;
- logs e status devem funcionar do mesmo modo;
- tela de documentacao/credenciais deve indicar endpoint, ambiente, exemplos e link para OpenAPI;
- travas visuais de upload manual continuam existindo, mas a API precisa aplicar as mesmas regras no backend.

Modelo recomendado de UX:

1. Usuario administrador do distribuidor acessa **Configuracao > API**.
2. Clica em **Gerar token**.
3. Informa nome da integracao, escopos permitidos e validade opcional.
4. Portal mostra o token uma unica vez com botao de copiar.
5. O hash do token fica salvo no Supabase; o valor em texto puro nunca e persistido.
6. O distribuidor acompanha ultimo uso, volume importado, status e pode revogar a chave.

Permissoes:

- usuarios comuns nao devem criar tokens;
- administradores do distribuidor podem criar/revogar tokens do proprio distribuidor;
- administradores ProSellOut podem visualizar e revogar tokens de qualquer distribuidor, mas nao ver o segredo em texto puro;
- cada acao de criacao, rotacao e revogacao deve gerar auditoria.

### Documentacao externa

Criar pacote de integracao para empresas:

- `docs/api/openapi.yaml`;
- guia `docs/API_IMPORTACAO.md`;
- exemplos `curl`;
- exemplos JSON por tipo;
- tabela de campos obrigatorios/opcionais;
- ordem recomendada de envio;
- regras de idempotencia;
- semantica de status;
- catalogo de erros;
- limites de lote;
- ambiente sandbox/homologacao;
- contato e procedimento de rotacao de chave.

## Impacto de custos da API

As estimativas abaixo complementam `docs/CUSTOS.md`. Elas consideram o desenho recomendado neste plano: Cloudflare como borda/API publica, AWS como pipeline assincrono de ingestao e Supabase como banco principal. Os valores sao ordem de grandeza, sem impostos e usando o mesmo cambio de referencia de `docs/CUSTOS.md`: **US$ 1 ~= R$ 5,40**.

Precos de nuvem mudam. Antes de fechar orcamento, validar novamente nas fontes oficiais: [Cloudflare Workers pricing](https://developers.cloudflare.com/workers/platform/pricing/), [Supabase pricing](https://supabase.com/pricing), [Supabase compute/disk](https://supabase.com/docs/guides/platform/compute-and-disk), [AWS Lambda pricing](https://aws.amazon.com/lambda/pricing/), [AWS S3 pricing](https://aws.amazon.com/s3/pricing/), [AWS SQS pricing](https://aws.amazon.com/sqs/pricing/) e [AWS CloudWatch pricing](https://aws.amazon.com/cloudwatch/pricing/).

### Resumo financeiro

A API nao muda o principal centro de custo do ProSellOut: os dados continuam indo para o mesmo Postgres, com a mesma retencao e os mesmos relatorios. Portanto:

- **Supabase continua sendo o custo dominante**: armazenamento, compute do Postgres, conexoes e refresh/consulta dos agregados.
- **AWS continua baixo**: a API reutiliza S3/SQS/Lambda e evita processamento sincrono no request.
- **Cloudflare entra como custo novo pequeno**: API Worker, logs e possivelmente plano de dominio/WAF.
- **O maior risco financeiro da API e granularidade ruim de lote**: muitos requests pequenos aumentam chamadas Cloudflare/AWS e podem pressionar conexoes no Supabase. Por isso o contrato deve exigir lotes.

### Custo incremental esperado

| Item | O que muda com a API | Estimativa mensal esperada |
|---|---|---:|
| Cloudflare Worker API | Worker dedicado para `/v1/imports`, autenticacao, validacao leve, status/logs | **US$ 5 a US$ 10** |
| Cloudflare seguranca | Rate limiting/WAF/regras no dominio, se o plano atual nao cobrir | **US$ 0 a US$ 20+** |
| AWS Lambda `api-ingest` | Normaliza JSON para CSV canonico e envia partes para S3/SQS | **centavos a poucos dolares** |
| AWS S3 | Armazena partes canonicas por poucos dias; uploads manuais continuam em `uploads/` | **centavos** |
| AWS SQS | Uma mensagem por parte; 1M requests/mes costuma cobrir piloto/fase inicial | **US$ 0 a US$ 1+** |
| AWS CloudWatch | Logs/metricas/alarmes da nova Lambda/API | **US$ 1 a US$ 5** |
| Supabase | Tabelas `api_clients`, idempotencia, metadados e logs extras | **quase zero no inicio** |
| Supabase Postgres | Volume final de dados importados e relatorios | **mesmo custo estrutural de `docs/CUSTOS.md`** |

Para MVP/piloto, o incremento realista da API sobre a infraestrutura atual deve ficar em **~US$ 6 a US$ 35/mes** (**~R$ 30 a R$ 190/mes**), antes de crescimento forte de volume. Em escala, o custo incremental de borda/processamento ainda tende a ser pequeno perto do banco.

### Comparativo com o custo total da plataforma

Usando as fases de `docs/CUSTOS.md`, o impacto provavel fica assim:

| Fase | Plataforma atual estimada | Incremento API | Total com API |
|---|---:|---:|---:|
| Piloto | ~R$ 220-250/mes | ~R$ 30-190/mes | **~R$ 250-440/mes** |
| Fase 1 | ~R$ 480-510/mes | ~R$ 30-220/mes | **~R$ 510-730/mes** |
| Break-even | ~R$ 1.300-1.330/mes | ~R$ 50-300/mes | **~R$ 1.350-1.630/mes** |
| Escala | ~R$ 9.500/mes | ~R$ 100-600+/mes | **~R$ 9.600-10.100+/mes** |

Esses numeros assumem que a API recebe lotes razoaveis e nao um request por linha. Se uma empresa enviar uma linha por request, o custo de borda/processamento sobe e a operacao fica pior; o contrato deve bloquear ou desencorajar esse padrao.

### Cloudflare

O Worker pago tem custo minimo mensal e inclui uma franquia de requests/CPU. O modelo atual do Workers Standard inclui 10M requests/mes, cobranca por requests adicionais e CPU acima da franquia, sem cobranca adicional de egress/banda no plano pago.

Impactos:

- custo base para a API publica: **US$ 5/mes**;
- overage so deve aparecer com muitos requests ou validacoes pesadas;
- logs do Workers tem franquia no plano pago, mas retencao/Logpush externo pode adicionar custo;
- Cloudflare Pro/Business/Enterprise pode entrar por seguranca, WAF, gestao de dominio ou regras mais avancadas, nao por necessidade tecnica da API em si;
- rate limiting e limites de CPU devem ser configurados para evitar custo acidental por abuso.

Controle recomendado:

- limitar tamanho maximo de lote;
- limitar requests por minuto por API key;
- exigir lote minimo recomendado para cargas grandes;
- rejeitar payloads gigantes antes de chamar AWS;
- configurar CPU limits no Worker;
- registrar metricas por `api_client_id`.

### AWS

A API deve manter AWS serverless. O custo cresce com numero de lotes, tamanho dos dados e quantidade de partes processadas.

Componentes:

- `api-ingest`: nova Lambda para receber lotes canonicos da Cloudflare ou endpoint interno equivalente;
- S3 `parts/`: armazenamento temporario dos CSVs canonicos;
- SQS: fila entre entrada API e `etl-loader`;
- `etl-loader`: continua fazendo `COPY` e chamando `process_*_staging`;
- CloudWatch: logs, metricas, alarmes e DLQ.

Pontos financeiros:

- o `file-validator` atual pode ser menos usado quando a empresa usa JSON/API, porque nao sera necessario parsear XLSX/CSV;
- o `etl-loader` continua sendo o custo principal de Lambda, mas ja e baixo no modelo atual;
- S3 e SQS continuam praticamente residuais se os lotes forem grandes;
- o egress AWS -> Supabase segue existindo porque o banco esta fora da AWS;
- alarmes e logs podem custar mais que o processamento em fases pequenas.

Controle recomendado:

- comprimir partes CSV quando fizer sentido;
- manter lifecycle curto em `parts/`;
- definir `maximum_concurrency` do SQS para proteger Postgres;
- adicionar AWS Budgets para a stack de importacao;
- alarmar DLQ, erro por cliente e custo mensal anormal.

### Supabase

A API adiciona pouca estrutura ao banco, mas todo dado aceito continua ocupando Postgres e alimentando relatorios.

Custos novos pequenos:

- tabelas `api_clients` e `api_client_keys`;
- colunas novas em `file_imports`;
- logs e metadados extras;
- consultas de status/logs pela API.

Custos que ja existem e continuam dominando:

- armazenamento de `sell_out`, `sell_in`, `sales_targets` e cadastros;
- indices e particoes;
- compute para `COPY`, funcoes `process_*_staging`, refresh de MVs e relatorios;
- disco acima da franquia do plano;
- eventual upgrade de compute conforme conexoes e volume aumentam.

Risco especifico da API:

- empresas podem enviar dados com frequencia maior que a rotina manual, aumentando picos de `COPY`, refresh de views e consultas de status;
- idempotencia mal definida pode duplicar dados e multiplicar storage;
- payloads pequenos demais podem gerar muitas importacoes e logs.

Controle recomendado:

- reter detalhe quente por 12 meses, conforme `docs/CUSTOS.md`;
- usar lotes por tipo/periodo em vez de streaming linha a linha;
- consolidar refresh de MVs ao final da importacao, nao a cada lote;
- manter `api_clients` com limites por distribuidor;
- monitorar crescimento mensal de tabelas e indices.

### Premissas de lote para controlar custo

Para a documentacao enviada as empresas, definir limites desde o primeiro dia:

- lote recomendado: **5.000 a 50.000 registros**;
- lote maximo por request: definir apos teste de payload real, com teto inicial conservador;
- uma importacao pode ter varios lotes;
- `/complete` fecha a importacao e libera finalizacao/refresh;
- nao aceitar uma linha por request para cargas transacionais;
- status/logs devem ter paginacao.

Essas regras protegem custo, estabilidade do Postgres e experiencia operacional.

## Contrato de API proposto

### Autenticacao

Header minimo:

```http
Authorization: Bearer pso_live_...
Idempotency-Key: empresa-abc-sellout-2026-07-14-001
```

Opcional recomendado para clientes com mais volume:

```http
X-PSO-Timestamp: 2026-07-14T12:00:00Z
X-PSO-Signature: sha256=...
```

### Endpoints

#### Criar importacao

```http
POST /v1/imports
```

```json
{
  "type": "SELL_OUT",
  "externalReference": "erp-abc-2026-07-14-sellout",
  "metadata": {
    "sourceSystem": "ERP ABC",
    "period": "2026-07"
  }
}
```

Resposta:

```json
{
  "importId": "uuid",
  "status": "pending",
  "type": "SELL_OUT"
}
```

#### Enviar lote

```http
PUT /v1/imports/{importId}/batches
```

```json
{
  "batchNumber": 1,
  "records": [
    {
      "distributorDocument": "00000000000000",
      "customerCode": "PDV-001",
      "sellerCode": "VEN-001",
      "productEan": "7890000000000",
      "invoiceNumber": "12345",
      "invoiceDate": "2026-07-14",
      "deliveryDate": "2026-07-15",
      "quantity": "10",
      "grossValue": "1234.56",
      "unitCost": "80.00"
    }
  ]
}
```

Resposta:

```json
{
  "importId": "uuid",
  "status": "processing",
  "acceptedRecords": 1
}
```

#### Concluir envio

```http
POST /v1/imports/{importId}/complete
```

Resposta:

```json
{
  "importId": "uuid",
  "status": "processing"
}
```

#### Consultar status

```http
GET /v1/imports/{importId}
```

Resposta:

```json
{
  "importId": "uuid",
  "status": "completed_with_errors",
  "totalRecords": 1000,
  "processedRecords": 990,
  "errorCount": 10,
  "createdAt": "2026-07-14T12:00:00Z",
  "finishedAt": "2026-07-14T12:03:00Z"
}
```

#### Consultar erros

```http
GET /v1/imports/{importId}/logs?level=error&limit=100
```

Resposta:

```json
{
  "logs": [
    {
      "lineNumber": 42,
      "level": "error",
      "message": "unknown product ean: 7890000000000"
    }
  ]
}
```

## Campos por tipo

Os nomes abaixo sao a proposta publica em JSON. Internamente eles devem ser normalizados para as colunas canonicas ja usadas pelo staging.

### `CUSTOMERS`

Obrigatorios:

- `distributorDocument`
- `customerCode`
- `legalName`

Opcionais:

- `customerDocument`
- `tradeName`
- `address`
- `district`
- `city`
- `state`
- `zipCode`
- `channelName`
- `clusterName`

### `PRODUCTS`

Obrigatorios:

- `distributorDocument`
- `productEan`
- `productName`
- `subcategoryName`
- `categoryName`
- `macroCategoryName`

Opcionais:

- `boxCount`
- `unitsPerPack`
- `skuCode`

### `SELLERS`

Obrigatorios:

- `distributorDocument`
- `sellerCode`
- `sellerName`
- `supervisorCode`

Opcionais:

- `portfolioSize`
- `supervisorName`
- `managerCode`
- `managerName`

### `TARGETS`

Obrigatorios:

- `distributorDocument`
- `customerCode`
- `productEan`
- `targetDate`
- `quantity` ou `grossValue`

Opcionais:

- `customerDocument`
- `sellerCode`
- `deliveryDate`

Regra critica: a carga de Meta Sell Out substitui metas anteriores das datas presentes no envio. A carga de Meta Sell In substitui metas anteriores dos meses presentes no envio.

### `SELL_IN`

Obrigatorios:

- `distributorDocument`
- `productEan`
- `invoiceDate`
- `quantity`
- `grossValue`

Opcionais:

- `invoiceNumber`
- `unitCost`

### `SELL_OUT`

Obrigatorios:

- `distributorDocument`
- `customerCode`
- `sellerCode`
- `productEan`
- `invoiceDate`
- `quantity`
- `grossValue`

Opcionais:

- `customerDocument`
- `invoiceNumber`
- `deliveryDate`
- `unitCost`

## Regras de validacao

A API deve aplicar validacoes leves antes de aceitar o lote:

- JSON valido;
- tipo conhecido;
- cliente autenticado e autorizado para o distribuidor;
- campos obrigatorios presentes;
- datas em `YYYY-MM-DD`;
- numeros como string decimal ou numero;
- limite de registros por lote;
- `batchNumber` sem repeticao dentro da mesma importacao;
- `Idempotency-Key` sem colisao indevida.

As validacoes de negocio continuam no Postgres:

- distribuidor do payload precisa bater com a conta;
- produto precisa existir para `SELL_IN`, `SELL_OUT` e `TARGETS`;
- cliente precisa existir para `SELL_OUT` e `TARGETS`;
- vendedor precisa existir para `SELL_OUT`;
- datas/numeros invalidos geram `file_import_logs`;
- rejeicoes por linha nao devem derrubar a importacao inteira quando houver linhas validas.

## Idempotencia

Sem idempotencia, uma empresa pode duplicar vendas ao repetir requests depois de timeout.

Regras recomendadas:

- exigir `Idempotency-Key` em `POST /v1/imports`;
- chave unica por `api_client_id + type + idempotency_key`;
- se a mesma chave for reenviada com mesmo payload, retornar a importacao existente;
- se a mesma chave vier com payload diferente, retornar `409 Conflict`;
- exigir `batchNumber` unico por importacao;
- para `SELL_OUT` e `SELL_IN`, avaliar uma chave natural futura para evitar duplicidade entre importacoes diferentes: distribuidor, produto, cliente quando aplicavel, NF, data e linha/origem.

## Status

Reutilizar o enum atual sempre que possivel:

- `pending` — importacao criada;
- `validating` — API/Lambda normalizando lotes;
- `processing` — partes enviadas ao SQS/loader;
- `completed` — sem rejeicoes;
- `completed_with_errors` — uma ou mais linhas rejeitadas;
- `failed` — nenhuma linha processada ou erro estrutural.

Para API multipart, pode ser necessario adicionar estado intermediario futuro, como `receiving`, mas o MVP pode usar `pending` enquanto os lotes chegam e `processing` apos `/complete`.

## Seguranca

Recomendacoes:

- nunca expor `service_role` ou `DATABASE_URL` ao cliente;
- gerar tokens pelo portal do ProSellOut, vinculados ao distribuidor e ao usuario que criou a credencial;
- armazenar API keys somente como hash;
- exibir o token completo somente uma vez, imediatamente apos a criacao;
- permitir rotacao de chave sem apagar historico;
- escopar chave por distribuidor e tipos permitidos;
- permitir revogacao imediata;
- aplicar rate limit por chave;
- registrar criacao, ultimo uso, rotacao e revogacao;
- registrar IP, user agent, request id e sistema de origem;
- opcional: HMAC por request para prevenir replay;
- opcional: allowlist de IP para clientes enterprise;
- mascarar documentos sensiveis em logs externos quando necessario.

## Observabilidade e operacao

Adicionar rastreabilidade fim a fim:

- `request_id` gerado na Cloudflare API;
- `import_id` em todos os logs Cloudflare/AWS/Supabase;
- metricas por cliente: importacoes, registros aceitos, rejeicoes, tempo ate conclusao;
- alerta para aumento de `failed` ou DLQ;
- alerta para rejeicao acima de um percentual configuravel;
- dashboard operacional com status das ultimas importacoes por origem;
- retencao de partes S3 igual ou menor que o fluxo atual.

## Plano de implementacao

### Fase 0 — Fechar decisoes de contrato

- confirmar se a API sera JSON-only no MVP;
- confirmar se a documentacao externa sera em PT-BR, EN ou ambos;
- confirmar limites de lote por request;
- confirmar politica de duplicidade para `SELL_IN` e `SELL_OUT`;
- confirmar se Marca/Industria entra no MVP ou fica explicitamente fora.

### Fase 1 — Banco e auditoria

- criar migration para `api_clients` e `api_client_keys`;
- adicionar colunas de origem/idempotencia em `file_imports`;
- criar indices e constraints de idempotencia;
- ajustar RLS/grants sem expor tabelas sensiveis;
- criar seed/homologacao para um cliente API;
- documentar o modelo em `src/database/README.md`.

### Fase 2 — Contrato compartilhado de importacao

- extrair `TABLE_SPECS` para modulo compartilhado em `src/cloud`;
- garantir que `file-validator`, `etl-loader` e nova entrada API usem a mesma ordem de colunas;
- criar testes de regressao para ordem de colunas;
- mapear nomes publicos JSON para colunas canonicas.

### Fase 3 — Entrada API

- criar Cloudflare Worker dedicado para `/v1/imports`;
- implementar autenticacao e idempotencia;
- implementar validacao leve de payload;
- criar Lambda `api-ingest` ou endpoint AWS interno para gravar partes canonicas e enviar SQS;
- retornar `202 Accepted` para processamento assincrono;
- implementar status/logs.

### Fase 4 — Portal/admin

- exibir origem `api` no historico de importacoes;
- adicionar filtros por origem;
- criar tela self-service para gerar, copiar uma unica vez, revogar e rotacionar API tokens;
- mostrar ultimo uso, escopos, status, expiracao e volume importado por token;
- criar trilha de auditoria para criacao, rotacao e revogacao de tokens;
- tela de saude da integracao por cliente.

### Fase 5 — Documentacao externa

- criar `docs/API_IMPORTACAO.md`;
- criar `docs/api/openapi.yaml`;
- criar exemplos JSON por tipo;
- criar colecao Postman/Insomnia se fizer sentido;
- criar guia de homologacao com ordem recomendada: `PRODUCTS`, `SELLERS`, `CUSTOMERS`, `TARGETS`, `SELL_IN_TARGETS`, `SELL_IN`, `SELL_OUT`;
- documentar erros comuns e como corrigir.

### Fase 6 — QA e rollout

- testar importacao API para os sete tipos;
- comparar resultados com importacao manual da mesma amostra;
- testar duplicidade/idempotencia;
- testar lote com erros parciais;
- testar falha estrutural;
- testar DLQ/retry;
- testar refresh de relatorios;
- liberar primeiro para um cliente piloto em sandbox;
- depois liberar producao com limites conservadores.

## Riscos e decisoes pendentes

| Tema | Risco | Decisao recomendada |
|---|---|---|
| Duplicidade de vendas | Retry externo pode duplicar `SELL_OUT`/`SELL_IN` | Exigir idempotencia e estudar chave natural por origem |
| Meta Sell Out / Meta Sell In | Meta Sell Out substitui datas importadas; Meta Sell In substitui meses inteiros | Documentar com destaque e exigir confirmacao no contrato |
| Marca/Industria | Requisito futuro ainda nao implementado | Nao incluir no MVP da API ate fechar contrato |
| Payload grande | Worker/API pode estourar limites ou timeout | Usar lotes e processamento assincrono |
| Divergencia de specs | `TABLE_SPECS` duplicado pode quebrar COPY posicional | Extrair modulo compartilhado e testar |
| Segurança | Chave vazada alimenta dados indevidos | Chaves com escopo, rate limit, revogacao e logs |
| Operacao | Empresa nao sabe se carga terminou | Endpoint de status, logs e webhooks futuros |

## Entregaveis finais

- API publica versionada `/v1`;
- importacao via API para `PRODUCTS`, `SELLERS`, `CUSTOMERS`, `TARGETS`, `SELL_IN_TARGETS`, `SELL_IN` e `SELL_OUT`;
- status e logs por importacao;
- tela no portal para gestao self-service de tokens por empresa/distribuidor;
- credenciais por empresa/distribuidor com escopos, expiracao opcional, revogacao e auditoria;
- OpenAPI e guia de integracao;
- exemplos JSON/cURL;
- historico no portal mostrando importacoes manuais e via API;
- monitoramento e alertas operacionais.
