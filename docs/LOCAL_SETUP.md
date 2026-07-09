# Rodando o ProSellOut localmente

Guia para subir o sistema na sua máquina, criar o usuário de acesso e testar as funcionalidades. Existem dois modos:

| Modo | Para quê | Requisitos |
|---|---|---|
| **Demo** | Navegar pelas telas com dados de exemplo | Node 18+ |
| **Completo** | Banco real (Postgres + Auth + RPCs) com dados do seed | Node 18+, Docker Desktop, Supabase CLI |

---

## Modo Demo (2 minutos)

```bash
cd src/frontend
npm install
npm run dev
```

Abra `http://localhost:3000`. Sem `.env.local` preenchido o portal roda em **modo demo**: login aceita qualquer credencial, todas as telas funcionam com dados de exemplo e a sidebar mostra o selo "modo demo".

> Se você já tem um `.env.local` preenchido e quer voltar ao demo, basta esvaziar `NEXT_PUBLIC_SUPABASE_ANON_KEY` e reiniciar o `npm run dev`.

---

## Modo Completo (banco local)

### 1. Pré-requisitos

- **Docker Desktop** aberto e rodando
- **Supabase CLI**: `brew install supabase/tap/supabase`

### 2. Subir o banco

```bash
cd src/database
supabase start
```

Na primeira execução o Docker baixa as imagens (alguns minutos). Ao final o CLI imprime as URLs e chaves. As migrations e o seed (~4 meses de dados da amostra) são aplicados automaticamente.

Serviços locais:

| Serviço | URL |
|---|---|
| API (usada pelo frontend) | `http://127.0.0.1:54321` |
| Studio (admin do banco) | `http://127.0.0.1:54323` |
| Postgres direto | `postgresql://postgres:postgres@127.0.0.1:54322/postgres` |

Para recriar tudo do zero (reaplicar migrations + seed): `supabase db reset`.
Para parar os containers: `supabase stop`.

### 2.1 Aplicando novas migrations (banco já rodando)

Quando novas migrations forem adicionadas em `supabase/migrations/` (ex.: `20260705000900_rls_hardening.sql`), não é preciso recriar containers nem atualizar imagem Docker — basta aplicá-las no banco que já está de pé:

```bash
cd src/database
supabase migration up   # aplica apenas as migrations pendentes, preservando os dados
```

Se preferir um banco limpo (reaplica todas as migrations + seed, **apaga os dados atuais**):

```bash
supabase db reset
```

Para QA de importação com banco vazio, sem a amostra real, use o seed mínimo:

```bash
supabase db reset --sql-paths ./seeds/admin-only.sql
```

Esse reset cria apenas `admin@email.com` / `123321`. Depois entre no portal como
admin e crie o usuário distribuidor em **Admin › Usuários** antes de importar os
arquivos.

Para conferir o que já foi aplicado: `supabase migration list --local`.

### 3. Configurar o frontend

Crie/edite `src/frontend/.env.local`:

```
NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:54321
NEXT_PUBLIC_SUPABASE_ANON_KEY=<chave "Publishable" impressa pelo supabase start>
NEXT_PUBLIC_UPLOAD_API_URL=
```

Perdeu a chave? Rode `supabase status` dentro de `src/database/` que ela é reimpressa.

> Importante: a AWS de produção valida o token e grava usando o Supabase cloud
> configurado nas Lambdas. Portanto, `NEXT_PUBLIC_UPLOAD_API_URL` apontando para
> a AWS prod não funciona com `NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:54321`.
> Para QA end-to-end da importação AWS, use o frontend local apontando para o
> Supabase cloud, ou teste pela Vercel. O Supabase local é indicado para validar
> migrations, auth/admin e telas sem acionar o pipeline AWS prod.

### 4. Usuários de login

O seed cria automaticamente dois usuários locais:

| Perfil | E-mail | Senha |
|---|---|---|
| Admin | `admin@email.com` | `123321` |
| Usuário distribuidor | `distribuidora.83299743000130@email.com` | `123321` |

Crie novos usuários distribuidores pela tela **Admin › Usuários**. Criar apenas pelo Auth do Supabase não faz o vínculo automático em `distributor_users`; sem esse vínculo o banco não retorna dados por tabela nem por RPC.

### 5. Rodar o portal

```bash
cd src/frontend
npm install   # apenas na primeira vez
npm run dev
```

Abra `http://localhost:3000` → você será redirecionado para `/login` → entre com o usuário do passo 4.

---

## Roteiro de teste das melhorias

1. **Status MTD** (`/relatorio/status/mtd`) — tela principal: filtros de período/meta/anterior, 12 KPIs com variação vs. meta e vs. anterior, gauges de probabilidade, tabela com toggle Vendedores/Categorias/Canais e gráfico comparativo.
2. **Badge-toggle** — em Status › Análise e Evoluções › Análise, alterne o agrupamento sem recarregar a página (consolidação de 5 telas do sistema antigo em 2).
3. **Filtros persistentes** — configure um período no MTD, navegue para Fast Facts ou Evoluções: os filtros são mantidos na sessão.
4. **Tabelas** — nas telas de Dados (Sell Out, Clientes etc.): paginação no servidor, ordenação e busca por coluna.
5. **Export com feedback** — botão Exportar em qualquer relatório: gera CSV respeitando os filtros ativos e mostra toast de sucesso.
6. **Cadastros** — inclua um distribuidor ou um nó de hierarquia: modal + toast + atualização imediata (grava no banco local de verdade).
7. **Importação** (`/arquivos/importacao`) — histórico com status e log de erros por linha vindos do seed. *Novos uploads exigem `NEXT_PUBLIC_UPLOAD_API_URL` apontando para o deploy AWS do repo `cloud`; sem essa URL, a tela mantém o histórico, mas não processa arquivos novos. Os layouts esperados ficam em `docs/IMPORTACAO_ARQUIVOS.md`.*
8. **Skeleton loading** — recarregue qualquer relatório e observe os placeholders animados durante a consulta.

## Problemas comuns

| Sintoma | Causa/solução |
|---|---|
| `Cannot connect to the Docker daemon` | Abra o Docker Desktop antes do `supabase start` |
| Porta 54321/54322/54323 em uso | `supabase stop` (ou pare o outro projeto Supabase local) |
| Login falha com usuário seedado | Rode `cd src/database && supabase db reset` para recriar `admin@email.com` e `distribuidora.83299743000130@email.com` |
| "Não foi possível conectar ao Supabase" no login | `supabase start` parado, ou `.env.local`/`next.config.mjs` alterados sem reiniciar o `npm run dev` |
| Telas vazias no modo completo | Confira o `.env.local` e reinicie o `npm run dev` (env só carrega no boot) |
| Quero dados novos | `cd src/database && supabase db reset` regenera o seed |
