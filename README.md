# Fadefy — Agendamentos inteligentes para barbearias

Aplicação web da Fadefy, composta por três páginas estáticas (HTML/CSS/JS) conectadas a um banco Supabase.

## Estrutura

```
fadefy-site/
├── index.html        # Landing page (home)
├── agendar.html      # App do cliente (fluxo de agendamento)
├── painel.html       # Painel do dono (agenda, dashboard, lembretes, etc.)
├── assets/
│   └── logotipo-fadefy.png
├── banco/            # Scripts SQL (rodar no Supabase, NÃO fazem parte do site)
│   ├── fadefy-supabase.sql        # tabelas base + dados de exemplo
│   └── fadefy-supabase-dono.sql   # bloqueios, funcionamento e lembretes
├── netlify.toml
└── README.md
```

## Navegação entre as páginas

- A **home** (`index.html`) tem botões que levam ao agendamento (`agendar.html`) e ao painel do dono (`painel.html`).
- O **app do cliente** tem o logo no topo que volta para a home.
- O **painel do dono** tem um link "Voltar ao site" na tela de login.

## Configuração do banco (Supabase)

Antes de usar de verdade, conecte o Supabase:

1. Crie um projeto gratuito em https://supabase.com
2. No **SQL Editor**, rode na ordem:
   - `banco/fadefy-supabase.sql`
   - `banco/fadefy-supabase-dono.sql`
3. Em **Project Settings → API**, copie a **Project URL** e a **anon public key**.
4. Cole essas duas informações no topo do `<script>` em `agendar.html` **e** em `painel.html`:
   ```js
   const SUPABASE_URL      = "https://seuprojeto.supabase.co";
   const SUPABASE_ANON_KEY = "sua-anon-key";
   ```

> Sem configurar, as páginas funcionam em **modo demonstração** (dados fictícios, sem gravar nada).

## Acesso do painel (demonstração)

- Senha: `fadefy123`
- ou Token: `FADEFY-DEMO-TOKEN`

> Para produção, migrar o login para o Supabase Auth (ver observações na entrega).

## Deploy no Netlify (via GitHub)

1. Suba esta pasta para um repositório no GitHub.
2. No Netlify: **Add new site → Import an existing project → GitHub**.
3. Selecione o repositório. Como é um site estático, deixe o **build command vazio** e o **publish directory** como `.` (o `netlify.toml` já cuida disso).
4. Clique em **Deploy**. O Netlify gera uma URL pública (ex.: `https://fadefy.netlify.app`).

A cada novo `git push`, o Netlify atualiza o site automaticamente.
