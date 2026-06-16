-- ============================================================
-- FADEFY · Camada SaaS (multi-tenant)
-- ------------------------------------------------------------
-- Rode este script no SQL Editor do Supabase DEPOIS dos
-- scripts fadefy-supabase.sql e fadefy-supabase-dono.sql.
--
-- O que ele faz:
--   1. Cria a tabela de barbearias (os "tenants" / clientes do SaaS)
--   2. Cria a tabela de pagamentos/assinaturas
--   3. Cria a tabela de perfis (liga o login do Supabase Auth a um papel)
--   4. Adiciona barbearia_id nas tabelas operacionais (isolamento)
--   5. Define as políticas de segurança (RLS) multi-tenant
-- ============================================================


-- ============================================================
-- 1. PERFIS — liga cada usuário do Auth a um papel e a uma barbearia
-- ------------------------------------------------------------
-- role: 'admin'  -> você (dono do SaaS), vê tudo
--       'dono'   -> dono de uma barbearia, vê só a dele
-- ============================================================
create table if not exists perfis (
  id            uuid primary key references auth.users(id) on delete cascade,
  nome          text,
  role          text not null default 'dono',   -- 'admin' | 'dono'
  barbearia_id  bigint,                          -- null para admin
  criado_em     timestamptz not null default now()
);

-- função auxiliar: retorna o papel do usuário logado
create or replace function meu_role() returns text
language sql stable security definer as $$
  select role from perfis where id = auth.uid()
$$;

-- função auxiliar: retorna a barbearia do usuário logado
create or replace function minha_barbearia() returns bigint
language sql stable security definer as $$
  select barbearia_id from perfis where id = auth.uid()
$$;


-- ============================================================
-- 2. BARBEARIAS — os clientes do SaaS (tenants)
-- ============================================================
create table if not exists barbearias (
  id              bigint generated always as identity primary key,
  nome            text not null,
  slug            text not null unique,          -- usado no link: /agendar?b=slug
  dono_nome       text,
  dono_email      text,
  dono_user_id    uuid references auth.users(id) on delete set null,
  telefone        text,
  plano           text not null default 'mensal', -- mensal | trimestral | anual
  valor_mensal    numeric(10,2) not null default 0,
  status          text not null default 'ativo',  -- ativo | inadimplente | suspenso | teste
  proximo_pagamento date,                          -- data em que o barbeiro deve pagar
  criado_em       timestamptz not null default now(),
  atualizado_em   timestamptz not null default now()
);
create index if not exists idx_barbearias_status on barbearias (status);
create index if not exists idx_barbearias_slug on barbearias (slug);


-- ============================================================
-- 3. PAGAMENTOS — histórico de pagamentos por barbearia
-- ============================================================
create table if not exists pagamentos (
  id              bigint generated always as identity primary key,
  barbearia_id    bigint not null references barbearias(id) on delete cascade,
  valor           numeric(10,2) not null,
  competencia     date not null,                  -- mês de referência
  pago_em         date,                           -- null = ainda não pago
  status          text not null default 'pendente',-- pendente | pago | atrasado
  metodo          text,                            -- pix | cartao | boleto
  criado_em       timestamptz not null default now()
);
create index if not exists idx_pagamentos_barbearia on pagamentos (barbearia_id);
create index if not exists idx_pagamentos_status on pagamentos (status);


-- ============================================================
-- 4. ISOLAMENTO — adiciona barbearia_id nas tabelas operacionais
-- ------------------------------------------------------------
-- Assim os dados de cada barbearia ficam separados.
-- (Os dados antigos ficam com barbearia_id nulo até serem migrados.)
-- ============================================================
alter table clientes        add column if not exists barbearia_id bigint references barbearias(id) on delete cascade;
alter table servicos        add column if not exists barbearia_id bigint references barbearias(id) on delete cascade;
alter table barbeiros       add column if not exists barbearia_id bigint references barbearias(id) on delete cascade;
alter table agendamentos    add column if not exists barbearia_id bigint references barbearias(id) on delete cascade;
alter table clientes_pacote add column if not exists barbearia_id bigint references barbearias(id) on delete cascade;

create index if not exists idx_clientes_barbearia       on clientes (barbearia_id);
create index if not exists idx_servicos_barbearia       on servicos (barbearia_id);
create index if not exists idx_barbeiros_barbearia      on barbeiros (barbearia_id);
create index if not exists idx_agendamentos_barbearia   on agendamentos (barbearia_id);


-- ============================================================
-- 5. RLS — políticas de segurança multi-tenant
-- ============================================================
alter table perfis      enable row level security;
alter table barbearias  enable row level security;
alter table pagamentos  enable row level security;

-- PERFIS: cada um lê o próprio; admin lê todos
create policy "perfis_self"  on perfis for select using (id = auth.uid() or meu_role() = 'admin');
create policy "perfis_admin" on perfis for all    using (meu_role() = 'admin') with check (meu_role() = 'admin');

-- BARBEARIAS: admin gerencia tudo; dono vê só a própria
create policy "barbearias_admin" on barbearias for all
  using (meu_role() = 'admin') with check (meu_role() = 'admin');
create policy "barbearias_dono"  on barbearias for select
  using (id = minha_barbearia());

-- PAGAMENTOS: só o admin
create policy "pagamentos_admin" on pagamentos for all
  using (meu_role() = 'admin') with check (meu_role() = 'admin');
create policy "pagamentos_dono"  on pagamentos for select
  using (barbearia_id = minha_barbearia());

-- ------------------------------------------------------------
-- Tabelas operacionais: cada dono só acessa a SUA barbearia.
-- Substitua as políticas permissivas anteriores por estas.
-- (Se as antigas existirem, rode os DROP antes.)
-- ------------------------------------------------------------
-- Exemplo para AGENDAMENTOS (replique o padrão para as demais):
drop policy if exists "agend_leitura"  on agendamentos;
drop policy if exists "agend_insercao" on agendamentos;
drop policy if exists "agend_update"   on agendamentos;

create policy "agend_tenant" on agendamentos for all
  using (barbearia_id = minha_barbearia() or meu_role() = 'admin')
  with check (barbearia_id = minha_barbearia() or meu_role() = 'admin');

-- Repita o mesmo padrão para clientes, servicos, barbeiros, clientes_pacote:
drop policy if exists "servicos_leitura_publica" on servicos;
drop policy if exists "servicos_insert" on servicos;
drop policy if exists "servicos_update" on servicos;
create policy "servicos_tenant" on servicos for all
  using (barbearia_id = minha_barbearia() or meu_role() = 'admin')
  with check (barbearia_id = minha_barbearia() or meu_role() = 'admin');

drop policy if exists "barbeiros_leitura_publica" on barbeiros;
drop policy if exists "barbeiros_insert" on barbeiros;
drop policy if exists "barbeiros_update" on barbeiros;
create policy "barbeiros_tenant" on barbeiros for all
  using (barbearia_id = minha_barbearia() or meu_role() = 'admin')
  with check (barbearia_id = minha_barbearia() or meu_role() = 'admin');

drop policy if exists "clientes_leitura" on clientes;
drop policy if exists "clientes_insercao" on clientes;
create policy "clientes_tenant" on clientes for all
  using (barbearia_id = minha_barbearia() or meu_role() = 'admin')
  with check (barbearia_id = minha_barbearia() or meu_role() = 'admin');

drop policy if exists "clientes_pacote_tudo" on clientes_pacote;
create policy "clientes_pacote_tenant" on clientes_pacote for all
  using (barbearia_id = minha_barbearia() or meu_role() = 'admin')
  with check (barbearia_id = minha_barbearia() or meu_role() = 'admin');

-- ATENÇÃO sobre o app público de agendamento:
-- O cliente final agenda SEM login. Para isso funcionar com RLS,
-- a leitura de servicos/barbeiros e a criação de cliente/agendamento
-- daquela barbearia precisam ser liberadas para o papel "anon"
-- filtrando por barbearia_id. Isso é feito por uma policy específica
-- OU (recomendado) por uma Edge Function que recebe o slug e grava
-- com a service_role. Ver guia ADMIN-SAAS-GUIA.md.


-- ============================================================
-- 6. DADOS DE EXEMPLO (para o painel admin em modo demo)
-- ============================================================
insert into barbearias (nome, slug, dono_nome, dono_email, telefone, plano, valor_mensal, status, proximo_pagamento) values
  ('Barbearia Navalha',   'barbearia-navalha',   'Pedro Santos',  'pedro@navalha.com',   '11999990001', 'mensal', 79.90,  'ativo',         current_date + 12),
  ('Corte Fino',          'corte-fino',          'Lucas Oliveira','lucas@cortefino.com', '11999990002', 'mensal', 79.90,  'inadimplente',  current_date - 5),
  ('Barber King',         'barber-king',         'Rafael Souza',  'rafa@barberking.com', '11999990003', 'anual',  799.00, 'ativo',         current_date + 40),
  ('Studio Barba & Cia',  'studio-barba-cia',    'André Lima',    'andre@barbacia.com',  '11999990004', 'mensal', 59.90,  'teste',         current_date + 7);

-- ============================================================
-- Pronto! Agora crie seu usuário admin:
--   1. Em Authentication > Users, crie seu usuário (e-mail + senha).
--   2. Pegue o UUID dele e rode:
--      insert into perfis (id, nome, role) values ('SEU-UUID', 'Seu Nome', 'admin');
-- ============================================================
