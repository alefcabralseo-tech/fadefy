-- ================================================================
-- FADEFY · Funções RPC (server-side, SECURITY DEFINER)
-- ----------------------------------------------------------------
-- Rode DEPOIS dos scripts de setup (base + dono + saas).
-- Estas funções substituem a necessidade de Edge Functions:
--   • criar_dono        -> admin cria o login do dono (item 1)
--   • agendar_dados     -> app público carrega barbearia/serviços (item 3)
--   • agendar_cliente   -> reconhece cliente pelo telefone (item 3)
--   • agendar_horarios  -> horários ocupados de um barbeiro/dia (item 3)
--   • agendar_confirmar -> cria cliente (se preciso) + agendamento (item 3)
-- ================================================================

-- Cliente agora é único POR BARBEARIA (e não global), para o
-- mesmo telefone poder existir em barbearias diferentes.
alter table clientes drop constraint if exists clientes_telefone_key;
create unique index if not exists clientes_barbearia_telefone_key
  on clientes (barbearia_id, telefone);


-- ================================================================
-- ITEM 1 · criar_dono  (somente ADMIN)
-- Cria o usuário no Supabase Auth + identidade + perfil 'dono'
-- e vincula o user à barbearia. Roda com privilégios elevados,
-- mas só executa se quem chamou for admin.
-- ================================================================
create or replace function criar_dono(
  p_email text, p_senha text, p_nome text, p_barbearia_id bigint
) returns json
language plpgsql security definer
set search_path = public, auth, extensions
as $$
declare uid uuid := gen_random_uuid();
begin
  if coalesce(meu_role(), '') <> 'admin' then
    raise exception 'Apenas administradores podem criar donos';
  end if;
  if exists (select 1 from auth.users where email = lower(p_email)) then
    raise exception 'Já existe um usuário com o e-mail %', p_email;
  end if;

  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at,
    raw_app_meta_data, raw_user_meta_data,
    confirmation_token, recovery_token, email_change_token_new, email_change
  ) values (
    '00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated',
    lower(p_email), extensions.crypt(p_senha, extensions.gen_salt('bf')),
    now(), now(), now(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
    '', '', '', ''
  );

  insert into auth.identities (
    provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at
  ) values (
    uid::text, uid,
    jsonb_build_object('sub', uid::text, 'email', lower(p_email), 'email_verified', true, 'phone_verified', false),
    'email', now(), now(), now()
  );

  insert into perfis (id, nome, role, barbearia_id) values (uid, p_nome, 'dono', p_barbearia_id);
  update barbearias set dono_user_id = uid where id = p_barbearia_id;

  return json_build_object('ok', true, 'user_id', uid);
end $$;

revoke all on function criar_dono(text,text,text,bigint) from public, anon;
grant execute on function criar_dono(text,text,text,bigint) to authenticated;


-- ================================================================
-- ITEM 3 · Agendamento público (chamável por ANON, escopo por slug)
-- ================================================================

-- carrega barbearia + serviços + barbeiros + funcionamento pelo slug
create or replace function agendar_dados(p_slug text)
returns json
language plpgsql security definer stable
set search_path = public
as $$
declare b record;
begin
  select id, nome into b from barbearias
    where slug = p_slug and status <> 'suspenso';
  if not found then raise exception 'Barbearia não encontrada ou indisponível'; end if;

  return json_build_object(
    'barbearia', json_build_object('id', b.id, 'nome', b.nome),
    'servicos', coalesce((
      select json_agg(json_build_object('id',id,'nome',nome,'preco',preco,'duracao_min',duracao_min) order by id)
      from servicos where barbearia_id = b.id and ativo), '[]'::json),
    'barbeiros', coalesce((
      select json_agg(json_build_object('id',id,'nome',nome) order by id)
      from barbeiros where barbearia_id = b.id and ativo), '[]'::json),
    'funcionamento', coalesce((
      select json_agg(json_build_object('dia_semana',dia_semana,'aberto',aberto,
        'hora_inicio',to_char(hora_inicio,'HH24:MI'),'hora_fim',to_char(hora_fim,'HH24:MI')) order by dia_semana)
      from funcionamento), '[]'::json)
  );
end $$;
grant execute on function agendar_dados(text) to anon, authenticated;

-- reconhece o cliente pelo telefone (dentro da barbearia do slug)
create or replace function agendar_cliente(p_slug text, p_telefone text)
returns json
language plpgsql security definer stable
set search_path = public
as $$
declare v_bid bigint; c record;
begin
  select id into v_bid from barbearias where slug = p_slug;
  if v_bid is null then raise exception 'Barbearia não encontrada'; end if;
  select id, nome into c from clientes where barbearia_id = v_bid and telefone = p_telefone;
  if found then return json_build_object('encontrado', true, 'id', c.id, 'nome', c.nome);
  end if;
  return json_build_object('encontrado', false);
end $$;
grant execute on function agendar_cliente(text,text) to anon, authenticated;

-- horários já ocupados de um barbeiro num dia
create or replace function agendar_horarios(p_slug text, p_barbeiro_id bigint, p_data date)
returns json
language plpgsql security definer stable
set search_path = public
as $$
declare v_bid bigint;
begin
  select id into v_bid from barbearias where slug = p_slug;
  if v_bid is null then raise exception 'Barbearia não encontrada'; end if;
  return coalesce((
    select json_agg(to_char(hora,'HH24:MI'))
    from agendamentos
    where barbearia_id = v_bid and barbeiro_id = p_barbeiro_id
      and data = p_data and status = 'confirmado'), '[]'::json);
end $$;
grant execute on function agendar_horarios(text,bigint,date) to anon, authenticated;

-- cria o cliente (se preciso) e grava o agendamento
create or replace function agendar_confirmar(
  p_slug text, p_nome text, p_telefone text,
  p_servico_id bigint, p_barbeiro_id bigint, p_data date, p_hora time
) returns json
language plpgsql security definer
set search_path = public
as $$
declare v_bid bigint; v_cliente_id bigint;
begin
  select id into v_bid from barbearias where slug = p_slug;
  if v_bid is null then raise exception 'Barbearia não encontrada'; end if;

  if not exists (select 1 from servicos where id = p_servico_id and barbearia_id = v_bid and ativo) then
    raise exception 'Serviço inválido';
  end if;
  if not exists (select 1 from barbeiros where id = p_barbeiro_id and barbearia_id = v_bid and ativo) then
    raise exception 'Barbeiro inválido';
  end if;

  select id into v_cliente_id from clientes where barbearia_id = v_bid and telefone = p_telefone;
  if v_cliente_id is null then
    insert into clientes (nome, telefone, barbearia_id)
    values (p_nome, p_telefone, v_bid) returning id into v_cliente_id;
  end if;

  begin
    insert into agendamentos (cliente_id, servico_id, barbeiro_id, data, hora, status, barbearia_id)
    values (v_cliente_id, p_servico_id, p_barbeiro_id, p_data, p_hora, 'confirmado', v_bid);
  exception when unique_violation then
    return json_build_object('ok', false, 'erro', 'horario_ocupado');
  end;

  return json_build_object('ok', true, 'cliente_id', v_cliente_id);
end $$;
grant execute on function agendar_confirmar(text,text,text,bigint,bigint,date,time) to anon, authenticated;
