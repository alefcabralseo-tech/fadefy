# Fadefy · Guia do Admin SaaS

Este guia explica como colocar o painel admin (`admin.html`) para funcionar de verdade, com Supabase Auth e isolamento de dados por barbearia.

## Visão geral da arquitetura

- **Multi-tenant:** um único banco, com os dados separados por `barbearia_id`. Cada barbearia é um "tenant".
- **Papéis (roles):** `admin` (você, dono do SaaS — vê tudo) e `dono` (dono de uma barbearia — vê só a dele). Ficam na tabela `perfis`, ligada ao Supabase Auth.
- **Link por barbearia:** cada barbearia tem um `slug`. O link entregue ao cliente fica `…/agendar.html?b=slug`.

## Passo 1 — Banco

No SQL Editor do Supabase, rode em ordem:
1. `fadefy-supabase.sql`
2. `fadefy-supabase-dono.sql`
3. `fadefy-supabase-saas.sql`  ← a camada SaaS

## Passo 2 — Criar seu usuário admin

1. Em **Authentication → Users → Add user**, crie seu usuário (e-mail + senha).
2. Copie o **UUID** dele (aparece na lista de usuários).
3. No SQL Editor, rode (trocando o UUID):
   ```sql
   insert into perfis (id, nome, role) values ('SEU-UUID-AQUI', 'Seu Nome', 'admin');
   ```
4. Pronto: ao logar no `admin.html` com esse e-mail/senha, você entra como administrador.

## Passo 3 — Configurar o admin.html

No topo do `<script>` de `admin.html`, preencha:
```js
const SUPABASE_URL      = "https://seuprojeto.supabase.co";
const SUPABASE_ANON_KEY = "sua-anon-key";
const BASE_AGENDAMENTO  = "https://SEUSITE.netlify.app/agendar.html";
```

## Passo 4 — Edge Function: criar o login do dono (IMPORTANTE)

Quando você cadastra uma barbearia no admin e define a senha do dono, o sistema precisa **criar um usuário no Supabase Auth**. Isso **só pode ser feito no servidor**, porque exige a chave secreta `service_role` — que **nunca** pode ficar no `admin.html` (qualquer um veria).

A solução é uma **Edge Function** chamada `criar-dono`. O `admin.html` já a chama automaticamente; você só precisa publicá-la.

### Código da função

Crie o arquivo `supabase/functions/criar-dono/index.ts`:

```ts
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

Deno.serve(async (req) => {
  // CORS básico
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors() });
  }
  try {
    const { email, senha, nome, barbearia_id } = await req.json();

    // cliente com a chave SECRETA (só existe no servidor)
    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // 1) cria o usuário (login do dono)
    const { data: user, error: e1 } = await admin.auth.admin.createUser({
      email,
      password: senha,
      email_confirm: true,
    });
    if (e1) throw e1;

    // 2) cria o perfil ligado à barbearia, com papel "dono"
    const { error: e2 } = await admin.from("perfis").insert({
      id: user.user.id,
      nome,
      role: "dono",
      barbearia_id,
    });
    if (e2) throw e2;

    // 3) vincula o user_id na barbearia
    await admin.from("barbearias")
      .update({ dono_user_id: user.user.id })
      .eq("id", barbearia_id);

    return new Response(JSON.stringify({ ok: true }), {
      headers: { ...cors(), "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err.message || err) }), {
      status: 400,
      headers: { ...cors(), "Content-Type": "application/json" },
    });
  }
});

function cors() {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, content-type",
  };
}
```

### Publicar

Com a CLI do Supabase instalada:
```bash
supabase functions deploy criar-dono
```
A `service_role key` já existe nas variáveis de ambiente do projeto, então a função tem acesso a ela sem você precisar colá-la em lugar nenhum.

> **Enquanto a função não estiver publicada:** o admin ainda cadastra a barbearia normalmente; ele só mostra um aviso dizendo que o login do dono não pôde ser criado automaticamente. Você pode, nesse meio-tempo, criar o login manualmente em Authentication → Users e inserir o perfil via SQL.

## Passo 5 — Login do dono no painel (painel.html)

Hoje o `painel.html` usa uma senha fixa no código (modo MVP). Para o SaaS, o ideal é trocar esse login pelo **Supabase Auth** (o mesmo do admin), e o painel passa a:
1. Logar via `supabase.auth.signInWithPassword`.
2. Ler o `perfis` para descobrir a `barbearia_id` do dono.
3. Filtrar todos os dados por essa barbearia.

Isso é um próximo passo de desenvolvimento (posso fazer quando quiser). Com as políticas RLS já criadas no `fadefy-supabase-saas.sql`, o isolamento de dados já fica garantido pelo banco.

## Passo 6 — App de agendamento por barbearia

O `agendar.html` deve ler o `slug` da URL (`?b=barbearia-navalha`) e carregar os serviços/barbeiros daquela barbearia. Como o cliente final agenda **sem login**, o caminho mais seguro é uma Edge Function pública que recebe o slug e devolve os dados / grava o agendamento. Também é um próximo passo — me avise para implementar.

## Arquitetura final (sem Edge Function)

A criação do login do dono e o agendamento público são feitos por **funções RPC no Postgres** (`SECURITY DEFINER`), definidas em `fadefy-funcoes.sql`. Isso substitui a Edge Function `criar-dono` (o arquivo em `supabase/functions/criar-dono/` fica como alternativa opcional). Para aplicar, rode `fadefy-funcoes.sql` no SQL Editor **depois** dos scripts de setup.

Funções criadas:
- `criar_dono(email, senha, nome, barbearia_id)` — só admin. Cria usuário no Auth + perfil 'dono' + vincula à barbearia. Chamada por `admin.html`.
- `agendar_dados(slug)` / `agendar_cliente(slug, tel)` / `agendar_horarios(slug, barbeiro, data)` / `agendar_confirmar(...)` — públicas (anon), escopadas pelo slug. Usadas por `agendar.html`.

## Resumo do que está pronto x próximos passos

| Item | Estado |
|---|---|
| Tela admin (listar, cadastrar, editar, excluir barbearias) | ✅ Pronto |
| Controle de pagamento e datas de vencimento | ✅ Pronto |
| Visão geral (MRR, inadimplentes, vencimentos) | ✅ Pronto |
| Login admin via Supabase Auth | ✅ Pronto |
| Estrutura de banco multi-tenant + RLS | ✅ Pronto |
| Criar login do dono automaticamente | ✅ Pronto (RPC `criar_dono`) |
| Painel do dono logar via Auth e filtrar por barbearia | ✅ Pronto |
| App de agendamento por slug da barbearia | ✅ Pronto (RPCs públicas) |
| Funcionamento/lembretes por barbearia (hoje globais) | 🔜 Melhoria futura |
