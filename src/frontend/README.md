# prosellout-frontend

Portal web do ProSellOut — Next.js 14 (App Router) + Tailwind + TanStack Query + Recharts + Supabase.

## Rodando

```bash
npm install
cp .env.example .env.local   # opcional — sem env roda em modo demo
npm run dev                  # http://localhost:3000
npm run typecheck            # tsc --noEmit
```

**Modo demo**: sem `NEXT_PUBLIC_SUPABASE_URL`/`ANON_KEY`, todas as telas funcionam com dados de exemplo determinísticos (mesmos números do mockup aprovado). Login é liberado e a sidebar exibe o selo "modo demo". Com as envs preenchidas, o portal usa Supabase Auth (login obrigatório via middleware) e consome as RPCs do `src/database/`. Guia completo em `../../docs/LOCAL_SETUP.md`.

## Estrutura

```
src/
├── app/
│   ├── login/                       # autenticação
│   └── (portal)/                    # layout com sidebar + breadcrumb
│       ├── cadastros/{distribuidor, hierarquia-produtos, hierarquia-comercial}
│       ├── arquivos/{importacao, configuracao}
│       ├── dados/{clientes, estoque, meta, sell-in, sell-out, vendedores}
│       ├── relatorio/status/{mtd, analise, fast-facts}
│       ├── relatorio/evolucoes/{mensal, historico-3m, analise}
│       └── planificador/batalha-naval
├── components/
│   ├── layout/    # sidebar, breadcrumb
│   ├── ui/        # design system (KpiCard, DataTable, Modal, TreeView, Toast,
│   │              #   MultiSelectField, ThemeToggle...)
│   ├── charts/    # Recharts (comparativo, combo barra+linha, gauge)
│   ├── reports/   # filtros de relatório + tabela de análise com toggle
│   └── data/      # filtros das telas de dados
├── hooks/         # useReportFilters (filtros na sessão), useLocalStorageState
├── lib/
│   ├── data/      # repositórios: Supabase quando configurado, demo caso contrário
│   ├── supabase/  # client browser (middleware de auth fica na raiz)
│   ├── sort.ts    # ordenação client-side (pt-BR, numeric-aware)
│   ├── search.ts  # busca por coluna sem acentos/case
│   ├── theme.ts   # temas claro/escuro + paleta hex dos gráficos
│   └── format.ts  # moeda/número/percentual/data em pt-BR
└── types/         # contratos de domínio e relatórios
```

## Padrões

- **Camada de dados com fallback demo**: toda função de `lib/data/*` tem caminho Supabase e caminho demo com o mesmo contrato — as telas não sabem qual está ativo.
- **Cache por sessão**: o `AppProviders` escuta mudanças do Supabase Auth e limpa o TanStack Query quando o usuário muda ou desloga, evitando dados de uma sessão anterior após novo login.
- **Filtros persistentes**: seleção de período/dimensões fica em `sessionStorage` ao navegar entre relatórios.
- **Tabelas (`DataTable`)**: paginação no servidor (`range()`), tamanho de página configurável, ordenação e busca por coluna — server-side via PostgREST (`order`/`ilike`) no modo conectado, em memória no demo. Clientes suporta multi-seleção de canais.
- **Badge-toggle**: telas consolidadas (Análise Status e Análise Evolução) trocam o agrupamento sem recarregar.
- **Temas claro/escuro**: tokens CSS em `globals.css` + classe no `<html>` aplicada antes da hidratação (`THEME_INIT_SCRIPT`, sem flash); gráficos usam a paleta por tema de `lib/theme.ts` — mantenha os três em sincronia ao alterar cores.
- **Export com feedback**: CSV com toast de sucesso/erro respeitando os filtros ativos.
- **Segurança**: headers CSP/HSTS/etc. em `next.config.mjs`; o `connect-src` inclui a origem de `NEXT_PUBLIC_SUPABASE_URL` (necessário para o Supabase local). Mudanças ali exigem reiniciar o dev server.
- **Rotas em pt-BR** para casar com o design (`/relatorio/status/mtd`); código e identificadores em inglês.
