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
| Metas | 1.469 | Layout SellOut_meta (agregadas por cliente/produto/mês) |

Números-âncora para conferir no Status MTD (Junho/2026): Sell Out R$ ≈ 1.000.563, Un ≈ 14.188, Cobertura ≈ 327 PDVs, Ticket Médio ≈ R$ 3.059, Preço Médio ≈ R$ 70,52.

## Lacunas de schema corrigidas (nas migrations base)

Ao cruzar a amostra com o schema, encontramos e corrigimos:

1. **Sell Out/Sell In sem número de NF** → `invoice_number` agora é opcional. Cada linha de Sell Out equivale a uma NF para Drop Size; quando o upload não traz NF, o ETL sintetiza uma identificação por importação/linha.
2. **Identidade do cliente é (distribuidor, Cód. PDV)** — o CNPJ vem mascarado e não é único. Adicionadas colunas `pdv_code`, `distributor_id`, `trade_name`, `address`; `cnpj` virou opcional; nova unicidade `(distributor_id, pdv_code)`.
3. **Vendedor é transacional** (vem em cada linha de Sell Out), não é atributo fixo do cliente — o `sell_out.sales_rep_id` já cobre isso.
4. **Hierarquia comercial tem códigos e Gerente opcional** acima do Supervisor — adicionados `code`, `distributor_id`, `portfolio_size` (carteira) e `manager_id` em `sales_reps`.
5. **Produtos têm caixa/unidades e escopo por distribuidor** — adicionados `box_count` e `distributor_id`.
6. **EAN aparece em 13 e 14 dígitos** (DUN-14 com "1" na frente) — função `fn_ean_core` normaliza para o núcleo de 13 dígitos ao cruzar Sell In × Produtos.

## Follow-ups (não feitos ainda)

- **Base de Estoque**: a regra de negócio define estoque como consequência de `Sell In volume - Sell Out volume`; se futuramente houver uma base física de estoque, revisar a Cobertura Média antes de trocar a fonte.
- **Multi-distribuidor**: a amostra tem 1 distribuidor; produto/EAN globalmente único ainda vale. Para vários distribuidores, revisar unicidade de EAN por distribuidor.
