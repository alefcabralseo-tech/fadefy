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
