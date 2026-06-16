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
