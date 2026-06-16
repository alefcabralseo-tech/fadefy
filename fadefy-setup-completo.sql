-- ================================================================
-- FADEFY · SETUP COMPLETO — cole TUDO no SQL Editor e clique RUN
-- Ordem: base -> area do dono -> camada SaaS
-- ================================================================

-- ####### PARTE 1/3 : BASE #######
-- ============================================================
-- FADEFY · Script de criação do banco (Supabase / PostgreSQL)
-- ------------------------------------------------------------
-- Como usar:
-- 1. No painel do Supabase, abra "SQL Editor".
-- 2. Cole TODO este script e clique em "Run".
-- 3. As tabelas serão criadas e os dados de exemplo inseridos.
-- ============================================================

-- ----------------------------
-- TABELA: clientes
-- ----------------------------
create table if not exists clientes (
  id          bigint generated always as identity primary key,
  nome        text not null,
  telefone    text not null unique,           -- usado para reconhecer o cliente
  criado_em   timestamptz not null default now()
);

-- ----------------------------
-- TABELA: servicos
-- ----------------------------
create table if not exists servicos (
  id          bigint generated always as identity primary key,
  nome        text not null,
  preco       numeric(10,2) not null,
  duracao_min int not null default 30,        -- usado para calcular horários
  ativo       boolean not null default true
);

-- ----------------------------
-- TABELA: barbeiros
-- ----------------------------
create table if not exists barbeiros (
  id          bigint generated always as identity primary key,
  nome        text not null,
  ativo       boolean not null default true
);

-- ----------------------------
-- TABELA: agendamentos
-- ----------------------------
create table if not exists agendamentos (
  id            bigint generated always as identity primary key,
  cliente_id    bigint not null references clientes(id) on delete cascade,
  servico_id    bigint not null references servicos(id),
  barbeiro_id   bigint not null references barbeiros(id),
  data          date not null,
  hora          time not null,
  status        text not null default 'confirmado',  -- confirmado | cancelado
  criado_em     timestamptz not null default now(),
  -- impede dois agendamentos no mesmo barbeiro/dia/hora
  unique (barbeiro_id, data, hora)
);

-- índice para acelerar a busca de horários ocupados
create index if not exists idx_agend_barbeiro_data
  on agendamentos (barbeiro_id, data);

-- ============================================================
-- ROW LEVEL SECURITY (RLS)
-- ------------------------------------------------------------
-- O Supabase exige RLS para a anon key acessar as tabelas.
-- As políticas abaixo são PERMISSIVAS para o MVP do fluxo do
-- cliente (ler serviços/barbeiros, criar cliente e agendamento).
-- Em produção, restrinja conforme a necessidade.
-- ============================================================

alter table clientes      enable row level security;
alter table servicos      enable row level security;
alter table barbeiros     enable row level security;
alter table agendamentos  enable row level security;

-- serviços e barbeiros: leitura pública
create policy "servicos_leitura_publica"   on servicos     for select using (true);
create policy "barbeiros_leitura_publica"  on barbeiros    for select using (true);

-- clientes: o fluxo precisa procurar pelo telefone e cadastrar novos
create policy "clientes_leitura"   on clientes for select using (true);
create policy "clientes_insercao"  on clientes for insert with check (true);

-- agendamentos: ler (para checar horários) e inserir
create policy "agend_leitura"   on agendamentos for select using (true);
create policy "agend_insercao"  on agendamentos for insert with check (true);

-- ============================================================
-- DADOS DE EXEMPLO (POC)
-- ============================================================

insert into servicos (nome, preco, duracao_min) values
  ('Corte masculino', 40.00, 30),
  ('Barba',           30.00, 20),
  ('Corte + barba',   65.00, 50),
  ('Sobrancelha',     15.00, 10),
  ('Pezinho',         20.00, 15),
  ('Combo completo',  90.00, 70);

insert into barbeiros (nome) values
  ('Pedro'),
  ('Lucas'),
  ('Rafael');

-- ============================================================
-- Pronto! Agora copie em "Project Settings > API":
--   - Project URL   ->  SUPABASE_URL no app
--   - anon public   ->  SUPABASE_ANON_KEY no app
-- ============================================================

-- ####### PARTE 2/3 : AREA DO DONO #######
-- ============================================================
-- FADEFY · Complemento do banco para a ÁREA DO DONO
-- ------------------------------------------------------------
-- Rode este script DEPOIS do fadefy-supabase.sql.
-- Adiciona: bloqueios de horário, horários de funcionamento
-- e políticas para o dono gerenciar (update/delete/insert).
-- ============================================================

-- ----------------------------
-- TABELA: bloqueios
-- (dono bloqueia um horário ou um dia inteiro)
-- ----------------------------
create table if not exists bloqueios (
  id           bigint generated always as identity primary key,
  barbeiro_id  bigint references barbeiros(id) on delete cascade, -- null = todos
  data         date not null,
  hora         time,                       -- null = dia inteiro
  motivo       text,
  criado_em    timestamptz not null default now()
);
create index if not exists idx_bloq_data on bloqueios (data);

-- ----------------------------
-- TABELA: funcionamento
-- (dias e horários que a barbearia abre)
-- dia_semana: 0=Dom ... 6=Sáb
-- ----------------------------
create table if not exists funcionamento (
  id            bigint generated always as identity primary key,
  dia_semana    int not null unique check (dia_semana between 0 and 6),
  aberto        boolean not null default true,
  hora_inicio   time not null default '09:00',
  hora_fim      time not null default '19:00'
);

-- ============================================================
-- RLS para as novas tabelas
-- ============================================================
alter table bloqueios     enable row level security;
alter table funcionamento enable row level security;

create policy "bloqueios_tudo"     on bloqueios     for all using (true) with check (true);
create policy "funcionamento_tudo" on funcionamento for all using (true) with check (true);

-- ============================================================
-- Políticas extras nas tabelas existentes para o DONO gerenciar
-- (o script anterior só permitia leitura/inserção)
-- ============================================================

-- agendamentos: permitir confirmar / cancelar / reagendar
create policy "agend_update" on agendamentos for update using (true) with check (true);

-- serviços: cadastrar/editar
create policy "servicos_insert" on servicos for insert with check (true);
create policy "servicos_update" on servicos for update using (true) with check (true);

-- barbeiros: cadastrar/editar
create policy "barbeiros_insert" on barbeiros for insert with check (true);
create policy "barbeiros_update" on barbeiros for update using (true) with check (true);

-- ============================================================
-- DADOS DE EXEMPLO: funcionamento (Seg–Sáb 09–19, Dom fechado)
-- ============================================================
insert into funcionamento (dia_semana, aberto, hora_inicio, hora_fim) values
  (0, false, '09:00', '19:00'),  -- Domingo
  (1, true,  '09:00', '19:00'),
  (2, true,  '09:00', '19:00'),
  (3, true,  '09:00', '19:00'),
  (4, true,  '09:00', '19:00'),
  (5, true,  '09:00', '20:00'),  -- Sexta até 20h
  (6, true,  '08:00', '18:00')   -- Sábado 08–18
on conflict (dia_semana) do nothing;

-- ============================================================
-- Pronto! O painel do dono já pode ler/gravar essas tabelas.
-- ============================================================

-- ============================================================
-- LEMBRETES (adicionado posteriormente)
-- ------------------------------------------------------------
-- Rode este trecho para habilitar a configuração de lembretes
-- e o acompanhamento de status de envio no painel do dono.
-- ============================================================

-- ----------------------------
-- TABELA: config_lembretes  (uma linha só, configuração geral)
-- ----------------------------
create table if not exists config_lembretes (
  id              int primary key default 1,
  ativo           boolean not null default true,
  antecedencia    int not null default 30,        -- minutos: 30, 60 ou 120
  canal           text not null default 'whatsapp',-- whatsapp | sms
  check (id = 1)                                   -- garante linha única
);

-- ----------------------------
-- TABELA: lembretes  (log de envios, status por agendamento)
-- ----------------------------
create table if not exists lembretes (
  id              bigint generated always as identity primary key,
  agendamento_id  bigint references agendamentos(id) on delete cascade,
  canal           text not null,                  -- whatsapp | sms
  status          text not null default 'pendente',-- pendente | enviado | falhou
  enviar_em       timestamptz,                    -- horário previsto do envio
  enviado_em      timestamptz,
  criado_em       timestamptz not null default now()
);
create index if not exists idx_lembretes_status on lembretes (status);

-- RLS
alter table config_lembretes enable row level security;
alter table lembretes        enable row level security;
create policy "config_lembretes_tudo" on config_lembretes for all using (true) with check (true);
create policy "lembretes_tudo"        on lembretes        for all using (true) with check (true);

-- configuração inicial (MVP: WhatsApp, 30 min antes, ativo)
insert into config_lembretes (id, ativo, antecedencia, canal)
values (1, true, 30, 'whatsapp')
on conflict (id) do nothing;

-- ============================================================
-- Pronto! O painel já pode ler/gravar a config e listar status.
-- ============================================================

-- ============================================================
-- CLIENTES (PACOTE) — adicionado posteriormente
-- ------------------------------------------------------------
-- Clientes que pagam um pacote mensal de cortes (2/4/6/8).
-- O dono controla o saldo manualmente (debitar / editar / renovar).
-- ============================================================

create table if not exists clientes_pacote (
  id              bigint generated always as identity primary key,
  cliente_id      bigint references clientes(id) on delete set null, -- opcional: vincula ao cliente já existente
  nome            text not null,
  telefone        text,
  cota_mensal     int not null default 4,        -- 2, 4, 6 ou 8
  cortes_usados   int not null default 0,        -- quantos já cortou no mês
  ativo           boolean not null default true,
  atualizado_em   timestamptz not null default now(),
  criado_em       timestamptz not null default now()
);
create index if not exists idx_clientes_pacote_ativo on clientes_pacote (ativo);

alter table clientes_pacote enable row level security;
create policy "clientes_pacote_tudo" on clientes_pacote for all using (true) with check (true);

-- dados de exemplo
insert into clientes_pacote (nome, telefone, cota_mensal, cortes_usados) values
  ('João Silva',   '11999990001', 4, 1),
  ('Marcos Lima',  '11999990002', 8, 3),
  ('Bruno Alves',  '11999990003', 2, 2);

-- ============================================================
-- Pronto! O painel já pode ler/gravar os clientes de pacote.
-- ============================================================

-- ####### PARTE 3/3 : CAMADA SAAS #######
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
