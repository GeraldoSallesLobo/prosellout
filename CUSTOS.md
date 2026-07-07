# Estimativa de custos de nuvem — ProSellOut

> **Aviso**: estimativas de ordem de grandeza a **preço cheio** (sem free tier / sem créditos promocionais), região **São Paulo (sa-east-1)**, sem impostos (IOF/ICMS incidem sobre a fatura em dólar). Preços de nuvem mudam — valide no [AWS Pricing Calculator](https://calculator.aws) e no [pricing do Supabase](https://supabase.com/pricing) antes de decisão orçamentária. Câmbio: **US$ 1 ≈ R$ 5,40**.
>
> **Escopo**: AWS (ingestão de arquivos, repo `cloud/`) + Supabase (banco/Auth). **Não inclui** Vercel (frontend — plano Hobby grátis atende o início; Pro ~US$ 20/mês se precisar).



## TL;DR


| Fase           | Distribuidores | AWS/mês | Supabase/mês | **Total nuvem/mês** |
| -------------- | -------------- | ------- | ------------ | ------------------- |
| **Piloto**     | 10–20          | ~R$ 2   | ~R$ 220      | **~R$ 220**         |
| **Fase 1**     | 50             | ~R$ 3   | ~R$ 475      | **~R$ 480**         |
| **Break-even** | 150            | ~R$ 6   | ~R$ 1.300    | **~R$ 1.300**       |
| **Escala**     | 2.500          | ~R$ 75  | ~R$ 9.400¹   | **~R$ 9.500¹**      |


¹ Sem arquivamento de dados. Arquivando partições antigas (manter 6 meses quentes) o Supabase cai para **~R$ 5.000/mês**. 

**A AWS é irrelevante no orçamento** (< 1% do total em todas as fases). O custo de nuvem é praticamente todo **Supabase** — armazenamento e compute do Postgres. É esse plano que precisa subir de degrau por fase.

### O que "12 meses" significa nestes números

Os totais mensais são o **regime estável, depois de ~1 ano de dados acumulados** no banco. Só **um item depende da retenção**: o **armazenamento do Supabase**, que empilha mês a mês (12 meses de sell-out = ~1,5 TB na escala). Todo o resto — AWS inteira, plano base e compute do Supabase — é **custo por mês, independente de retenção** (não muda se você guarda 1 mês ou 5 anos de histórico).

Duas implicações:

- Nos **primeiros meses** de cada fase o custo é **menor** que o da tabela, porque o banco ainda está enchendo (o storage cresce até estabilizar em ~12 meses). No piloto isso nem aparece — cabe nos 8 GB inclusos.
- A tabela assume **janela móvel de 12 meses** (ao entrar o mês 13, arquiva-se o mês 1 via `DROP`/`DETACH` de partição). **Se nunca arquivar**, o armazenamento cresce indefinidamente além de 1,5 TB e a conta do Supabase sobe junto — por isso o arquivamento é a principal alavanca de custo.

## Premissas de volume (dos targets do negócio)


| Parâmetro                                   | Valor                   |
| ------------------------------------------- | ----------------------- |
| PDVs por distribuidor                       | 5.000                   |
| Vendedores por distribuidor                 | ~33 (150 PDVs/vendedor) |
| Faturamento por distribuidor                | ~R$ 7 mi/mês            |
| SKUs                                        | ~500                    |
| **Linhas de sell-out/mês por distribuidor** | **~200.000**²           |


² Derivado: 5.000 PDVs × ~40 linhas/mês (≈4 pedidos × 10 SKUs). Sanity check: R$ 7 mi ÷ 200 mil = R$ 35/linha, plausível. Sell-out domina o volume; sell-in/estoque/metas somam uma fração. **É o parâmetro que mais move a conta — ajuste se o padrão real for outro.**


| Fase       | Distribuidores | Linhas sell-out/mês | Postgres em 12 meses³ |
| ---------- | -------------- | ------------------- | --------------------- |
| Piloto     | 15             | 3 mi                | ~9 GB                 |
| Fase 1     | 50             | 10 mi               | ~30 GB                |
| Break-even | 150            | 30 mi               | ~90 GB                |
| Escala     | 2.500          | 500 mi              | **~1,5 TB**           |


³ Valor **acumulado** após reter 12 meses de sell-out no banco quente (~250 bytes/linha com índices). É o único número que depende da retenção — ver "O que 12 meses significa" acima.

## AWS — detalhamento (preço cheio)

100% serverless (paga por uso). Itens por fase, em US$/mês:


| Fase       | Lambda (compute) | Egress → Supabase | S3 (storage+ops) | SQS | Alarmes CW | **Total US$** | **Total R$** |
| ---------- | ---------------- | ----------------- | ---------------- | --- | ---------- | ------------- | ------------ |
| Piloto     | 0,02             | 0,04              | 0,02             | ~0  | 0,33       | **0,42**      | **~R$ 2**    |
| Fase 1     | 0,08             | 0,14              | 0,06             | ~0  | 0,33       | **0,61**      | **~R$ 3**    |
| Break-even | 0,23             | 0,41              | 0,19             | ~0  | 0,33       | **1,16**      | **~R$ 6**    |
| Escala     | 3,87             | 6,75              | 3,09             | ~0  | 0,33       | **14,05**     | **~R$ 76**   |


Preços unitários usados (sa-east-1): Lambda ARM US$ 0,0000133/GB-s + US$ 0,20/1M req; egress US$ 0,15/GB; S3 Standard US$ 0,0405/GB-mês + US$ 0,005/1k PUT; SQS US$ 0,40/1M; CloudWatch US$ 0,10/alarme. O lifecycle do S3 (uploads 30 d, parts 7 d) impede o storage de crescer.

Mesmo na escala a AWS fica em ~R$ 75/mês porque o processamento é leve e o egress é pequeno (45 GB/mês).

## Supabase — detalhamento (preço cheio)


| Fase       | Plano base     | Instância de compute | Armazenamento (acima de 8 GB)⁴ | **Total US$** | **Total R$**  |
| ---------- | -------------- | -------------------- | ------------------------------ | ------------- | ------------- |
| Piloto     | Pro (US$ 25)   | Small (US$ 15)       | ~US$ 0                         | **~40**       | **~R$ 217**   |
| Fase 1     | Pro (US$ 25)   | Medium (US$ 60)      | ~US$ 3                         | **~88**       | **~R$ 474**   |
| Break-even | Pro (US$ 25)   | XL (US$ 210)         | ~US$ 10                        | **~245**      | **~R$ 1.324** |
| Escala     | Team (US$ 599) | 4XL (US$ 960)        | ~US$ 187                       | **~1.746**    | **~R$ 9.426** |


⁴ Disco provisionado ~US$ 0,125/GB-mês acima dos 8 GB incluídos no Pro; IOPS/throughput extras podem somar em disco grande. A instância de compute é dimensionada pela carga dos relatórios (RAM), não só pelo tamanho do banco — números acima são estimativas; valide o tamanho real com carga de teste.

Na fase de escala, a conta é dominada por **armazenamento (1,5 TB)** e por uma instância grande de compute. É aqui que o "calcanhar de Aquiles" da nuvem realmente aparece — e onde o crescimento progressivo por distribuidor precisa ser acompanhado de perto.

## Onde o custo mora e como controlá-lo

1. **Arquivar partições antigas** (maior alavanca): o particionamento mensal de `sell_out`/`sell_in` permite `DROP`/`DETACH` de meses frios. Manter 6 meses quentes em vez de 12 corta o storage do banco pela metade — na escala, de ~R$ 9.400 para ~R$ 5.000/mês.
2. **Relatórios lêem agregados** (`mv_sell_out_daily`), não linhas cruas — segura a necessidade de compute do banco conforme o volume sobe.
3. **Comprimir (gzip) as partes CSV** antes do COPY — reduz egress e S3 na AWS (já pequenos).
4. **AWS Budgets + billing alerts no Supabase**: alertas de orçamento para não haver surpresa. Sugiro adicionar `aws_budgets_budget` ao Terraform.
5. **Escala (500+ distribuidores)**: negociar Supabase **Enterprise** ou migrar para **Postgres dedicado**; nessa faixa o preço de tabela deixa de valer e vira contrato.



## Estratégia progressiva recomendada


| Momento                      | Ação                                                 | Nuvem/mês (aprox.)       |
| ---------------------------- | ---------------------------------------------------- | ------------------------ |
| Piloto (10–50)               | Supabase Pro + compute pequeno; AWS quase zero       | **R$ 220–480**           |
| Aproximando break-even (150) | Subir compute (XL) e ligar arquivamento de partições | **R$ 1.000–1.300**       |
| Escala (500+)                | Enterprise/dedicado + arquivamento agressivo         | **R$ 5.000+** (negociar) |


Comparativo: manter o mesmo ETL num servidor/EC2 ligado 24/7 custaria facilmente R$ 150–400/mês fixos **só de ingestão**, com ou sem uso. O modelo serverless da AWS torna essa parte desprezível; o investimento de nuvem se concentra no banco, que é onde o valor (relatórios, histórico) efetivamente está.

---

*Estimativas a preço cheio, baseadas nos targets de negócio informados. Revalide os preços unitários (AWS + Supabase) e o dimensionamento de compute com carga real antes de fechar orçamento.*