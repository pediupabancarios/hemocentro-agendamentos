-- Hemocentro JP — Sistema de Agendamentos
-- Projeto Supabase compartilhado com outros apps: tudo aqui usa o prefixo ag_.
-- Sem acesso anônimo. O papel vem de app_metadata.ag_usuario, que só o servidor grava:
-- um cadastro feito direto pela API de Auth não ganha acesso.

create sequence public.ag_proto_seq;

create table public.ag_usuarios (
  usuario   text primary key check (usuario ~ '^[a-z0-9._-]{3,30}$'),
  nome      text not null check (length(trim(nome)) > 0),
  papel     text not null check (papel in ('gestor','recepcao','medico')),
  ativo     boolean not null default true,
  criado_em timestamptz not null default now()
);

-- Códigos de primeiro acesso. Sem nenhuma política: só as funções abaixo acessam.
create table public.ag_codigos (
  usuario     text primary key references public.ag_usuarios(usuario) on delete cascade,
  codigo_hash text not null,
  expira_em   timestamptz not null
);

create table public.ag_agendamentos (
  id             text primary key default gen_random_uuid()::text check (id ~ '^[A-Za-z0-9_-]+$'),
  proto          text,
  nome           text not null check (length(trim(nome)) > 0),
  nascimento     date,
  data           date not null,
  horario        text not null check (horario ~ '^[0-2][0-9]:[0-5][0-9]$'),
  servico        text not null check (servico in ('Transfusão','Pediátrica','Medicações','Sangria')),
  turno          text not null check (turno in ('Manhã','Tarde')),
  genero         text not null default '' check (genero in ('','Feminino','Masculino')),
  tipo_sanguineo text not null default '' check (tipo_sanguineo in ('','A+','A-','B+','B-','AB+','AB-','O+','O-')),
  status         text not null default 'Confirmado' check (status in ('Confirmado','Pendente','Cancelado')),
  info           text not null default '',
  telefone       text not null default '',
  obs            text not null default '',
  encaixe        boolean not null default false,
  criado_por     text,
  atualizado_por text,
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now()
);
create index ag_agendamentos_data_idx on public.ag_agendamentos (data, servico, turno);

create table public.ag_vagas (
  id   int primary key default 1 check (id = 1),
  caps jsonb not null check (jsonb_typeof(caps) = 'object')
);
insert into public.ag_vagas (caps) values
  ('{"T":{"fmanha":3,"ftarde":3,"mmanha":3,"mtarde":3},"P":{"manha":2,"tarde":2},"M":{"manha":5,"tarde":5},"S":{"fmanha":5,"ftarde":5,"mmanha":5,"mtarde":5}}');

-- Histórico: permite saber quem mudou o quê e recuperar um registro apagado.
create table public.ag_historico (
  id             bigint generated always as identity primary key,
  quando         timestamptz not null default now(),
  quem           text,
  acao           text not null,
  agendamento_id text not null,
  antes          jsonb,
  depois         jsonb
);
create index ag_historico_agendamento_idx on public.ag_historico (agendamento_id, quando desc);

-- ── Identidade ──
create function public.ag_usuario_atual() returns text
language sql stable security definer set search_path = public as $$
  select usuario from public.ag_usuarios
  where usuario = auth.jwt()->'app_metadata'->>'ag_usuario' and ativo
$$;

create function public.ag_papel() returns text
language sql stable security definer set search_path = public as $$
  select papel from public.ag_usuarios
  where usuario = auth.jwt()->'app_metadata'->>'ag_usuario' and ativo
$$;

create function public.ag_nome_atual() returns text
language sql stable security definer set search_path = public as $$
  select nome from public.ag_usuarios
  where usuario = auth.jwt()->'app_metadata'->>'ag_usuario' and ativo
$$;

-- ── Regras do agendamento: vagas por dia, com trava contra reserva simultânea ──
create function public.ag_agendamentos_antes() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_papel text := public.ag_papel();
  v_cod text; v_sub text; v_max int; v_usados int; v_checar boolean;
begin
  new.atualizado_em := now();
  new.atualizado_por := coalesce(public.ag_nome_atual(), new.atualizado_por);
  if tg_op = 'INSERT' then
    new.criado_em := now();
    new.criado_por := coalesce(new.criado_por, public.ag_nome_atual());
    if coalesce(new.proto,'') = '' then
      new.proto := to_char(now() at time zone 'America/Fortaleza','YYYY') || '-' || lpad(nextval('public.ag_proto_seq')::text, 3, '0');
    end if;
    v_checar := true;
  else
    new.id := old.id; new.proto := old.proto;
    new.criado_em := old.criado_em; new.criado_por := old.criado_por;
    v_checar := new.data is distinct from old.data or new.servico is distinct from old.servico
             or new.turno is distinct from old.turno or new.genero is distinct from old.genero
             or (old.status = 'Cancelado' and new.status <> 'Cancelado');
  end if;

  -- Só o gestor autoriza encaixe
  if new.encaixe and v_papel is distinct from 'gestor' and (tg_op = 'INSERT' or v_checar) then
    new.encaixe := false;
  end if;

  if new.status <> 'Cancelado' and v_checar then
    perform pg_advisory_xact_lock(hashtext('ag|' || new.data || '|' || new.servico || '|' || new.turno || '|' || new.genero));
    v_cod := case new.servico when 'Transfusão' then 'T' when 'Pediátrica' then 'P' when 'Medicações' then 'M' else 'S' end;
    v_sub := case new.turno when 'Manhã' then 'manha' else 'tarde' end;
    if v_cod in ('T','S') then
      v_sub := case when new.genero = 'Feminino' then 'f' else 'm' end || v_sub;
    end if;
    select (caps->v_cod->>v_sub)::int into v_max from public.ag_vagas where id = 1;
    select count(*) into v_usados from public.ag_agendamentos a
      where a.data = new.data and a.servico = new.servico and a.turno = new.turno
        and a.status <> 'Cancelado' and a.id <> new.id
        and (v_cod in ('P','M') or (a.genero = 'Feminino') = (new.genero = 'Feminino'));
    if v_usados >= coalesce(v_max, 0) and not new.encaixe then
      raise exception 'LOTADO:%:%', v_usados, coalesce(v_max, 0) using errcode = 'P0001';
    end if;
  end if;
  return new;
end $$;
create trigger ag_agendamentos_antes before insert or update on public.ag_agendamentos
  for each row execute function public.ag_agendamentos_antes();

create function public.ag_agendamentos_depois() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.ag_historico (quem, acao, agendamento_id, antes, depois)
  values (public.ag_nome_atual(), tg_op, coalesce(new.id, old.id),
          case when tg_op <> 'INSERT' then to_jsonb(old) end,
          case when tg_op <> 'DELETE' then to_jsonb(new) end);
  return null;
end $$;
create trigger ag_agendamentos_depois after insert or update or delete on public.ag_agendamentos
  for each row execute function public.ag_agendamentos_depois();

-- O sistema nunca fica sem gestor
create function public.ag_usuarios_antes() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if old.papel = 'gestor' and old.ativo and (new.papel <> 'gestor' or not new.ativo)
     and not exists (select 1 from public.ag_usuarios u where u.papel = 'gestor' and u.ativo and u.usuario <> old.usuario) then
    raise exception 'O sistema precisa de ao menos um gestor';
  end if;
  return new;
end $$;
create trigger ag_usuarios_antes before update on public.ag_usuarios
  for each row execute function public.ag_usuarios_antes();

-- ── Contas ──
create function public.ag_gerar_codigo(p_usuario text) returns text
language plpgsql security definer set search_path = public, extensions as $$
declare v_hex text := upper(encode(gen_random_bytes(8), 'hex')); v_codigo text;
begin
  v_codigo := substr(v_hex,1,4) || '-' || substr(v_hex,5,4) || '-' || substr(v_hex,9,4) || '-' || substr(v_hex,13,4);
  insert into public.ag_codigos (usuario, codigo_hash, expira_em)
  values (p_usuario, encode(digest(v_codigo,'sha256'),'hex'), now() + interval '7 days')
  on conflict (usuario) do update set codigo_hash = excluded.codigo_hash, expira_em = excluded.expira_em;
  return v_codigo;
end $$;

-- Pública: é a única porta sem login e exige o código de uso único dado pelo gestor.
create function public.ag_primeiro_acesso(p_usuario text, p_codigo text, p_senha text) returns text
language plpgsql security definer set search_path = public, extensions, auth as $$
declare v_id uuid := gen_random_uuid(); v_email text;
begin
  p_usuario := lower(trim(p_usuario));
  if length(coalesce(p_senha,'')) < 8 then raise exception 'A senha precisa ter pelo menos 8 caracteres'; end if;
  if not exists (
    select 1 from public.ag_codigos c join public.ag_usuarios u using (usuario)
    where c.usuario = p_usuario and u.ativo and c.expira_em > now()
      and c.codigo_hash = encode(digest(upper(trim(p_codigo)),'sha256'),'hex')
  ) then
    raise exception 'Usuário ou código inválido, ou código vencido';
  end if;
  v_email := p_usuario || '@ag.hemocentro.invalid';
  delete from auth.users where email = v_email; -- código novo = redefinição de senha
  insert into auth.users (instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
    raw_app_meta_data,raw_user_meta_data,created_at,updated_at,
    confirmation_token,recovery_token,email_change_token_new,email_change,email_change_token_current,reauthentication_token)
  values ('00000000-0000-0000-0000-000000000000',v_id,'authenticated','authenticated',v_email,
    crypt(p_senha, gen_salt('bf')),now(),
    jsonb_build_object('provider','email','providers',jsonb_build_array('email'),'ag_usuario',p_usuario),
    '{}',now(),now(),'','','','','','');
  insert into auth.identities (id,user_id,provider_id,provider,identity_data,last_sign_in_at,created_at,updated_at)
  values (gen_random_uuid(),v_id,v_id::text,'email',
    jsonb_build_object('sub',v_id::text,'email',v_email,'email_verified',true),now(),now(),now());
  delete from public.ag_codigos where usuario = p_usuario;
  return 'ok';
end $$;

create function public.ag_liberar_usuario(p_usuario text, p_nome text, p_papel text) returns text
language plpgsql security definer set search_path = public as $$
begin
  if public.ag_papel() is distinct from 'gestor' then raise exception 'Apenas o gestor'; end if;
  p_usuario := lower(trim(p_usuario));
  if exists (select 1 from public.ag_usuarios where usuario = p_usuario) then raise exception 'Usuário já existe'; end if;
  insert into public.ag_usuarios (usuario, nome, papel) values (p_usuario, trim(p_nome), p_papel);
  return public.ag_gerar_codigo(p_usuario);
end $$;

create function public.ag_novo_codigo(p_usuario text) returns text
language plpgsql security definer set search_path = public as $$
begin
  if public.ag_papel() is distinct from 'gestor' then raise exception 'Apenas o gestor'; end if;
  if not exists (select 1 from public.ag_usuarios where usuario = p_usuario) then raise exception 'Usuário não encontrado'; end if;
  return public.ag_gerar_codigo(p_usuario);
end $$;

create function public.ag_remover_usuario(p_usuario text) returns void
language plpgsql security definer set search_path = public, auth as $$
begin
  if public.ag_papel() is distinct from 'gestor' then raise exception 'Apenas o gestor'; end if;
  if p_usuario = public.ag_usuario_atual() then raise exception 'Você não pode remover a si mesmo'; end if;
  delete from auth.users where email = p_usuario || '@ag.hemocentro.invalid';
  delete from public.ag_usuarios where usuario = p_usuario;
end $$;

create function public.ag_contas() returns table (usuario text, tem_conta boolean)
language sql stable security definer set search_path = public, auth as $$
  select s.usuario, exists (select 1 from auth.users a where a.email = s.usuario || '@ag.hemocentro.invalid')
  from public.ag_usuarios s where public.ag_papel() = 'gestor'
$$;

-- Importação atômica: ou entra tudo, ou nada. Não sobrescreve registros que já existem.
create function public.ag_importar(p_itens jsonb, p_caps jsonb, p_pidc int) returns int
language plpgsql security definer set search_path = public as $$
declare v_n int;
begin
  if public.ag_papel() is distinct from 'gestor' then raise exception 'Apenas o gestor'; end if;
  with novos as (
    insert into public.ag_agendamentos (id,proto,nome,nascimento,data,horario,servico,turno,genero,tipo_sanguineo,status,info,telefone,obs,encaixe,criado_por)
    select x.id, x.proto, x.nome, x.nascimento, x.data, x.horario, x.servico, x.turno, coalesce(x.genero,''), coalesce(x.tipo_sanguineo,''),
           x.status, coalesce(x.info,''), coalesce(x.telefone,''), coalesce(x.obs,''), true, x.criado_por
    from jsonb_to_recordset(p_itens) as x(id text, proto text, nome text, nascimento date, data date, horario text, servico text, turno text,
           genero text, tipo_sanguineo text, status text, info text, telefone text, obs text, criado_por text)
    on conflict (id) do nothing
    returning 1
  ) select count(*) into v_n from novos;
  if p_caps is not null then update public.ag_vagas set caps = p_caps where id = 1; end if;
  if coalesce(p_pidc,0) > 0 then perform setval('public.ag_proto_seq', greatest(p_pidc, (select last_value from public.ag_proto_seq))); end if;
  return v_n;
end $$;

-- ── Acesso ──
alter table public.ag_usuarios     enable row level security;
alter table public.ag_codigos      enable row level security;
alter table public.ag_agendamentos enable row level security;
alter table public.ag_vagas        enable row level security;
alter table public.ag_historico    enable row level security;

revoke all on public.ag_usuarios, public.ag_codigos, public.ag_agendamentos, public.ag_vagas, public.ag_historico from anon, authenticated, public;
revoke all on sequence public.ag_proto_seq from anon, authenticated, public;
grant select on public.ag_usuarios to authenticated;
grant update (nome, papel, ativo) on public.ag_usuarios to authenticated;
grant select, insert, update, delete on public.ag_agendamentos to authenticated;
grant select on public.ag_vagas to authenticated;
grant update (caps) on public.ag_vagas to authenticated;
grant select on public.ag_historico to authenticated;

create policy ag_usuarios_select on public.ag_usuarios for select to authenticated
  using (usuario = public.ag_usuario_atual() or public.ag_papel() = 'gestor');
create policy ag_usuarios_update on public.ag_usuarios for update to authenticated
  using (public.ag_papel() = 'gestor') with check (public.ag_papel() = 'gestor');

create policy ag_agendamentos_select on public.ag_agendamentos for select to authenticated
  using (public.ag_papel() is not null);
create policy ag_agendamentos_insert on public.ag_agendamentos for insert to authenticated
  with check (public.ag_papel() in ('gestor','recepcao'));
create policy ag_agendamentos_update on public.ag_agendamentos for update to authenticated
  using (public.ag_papel() in ('gestor','recepcao')) with check (public.ag_papel() in ('gestor','recepcao'));
create policy ag_agendamentos_delete on public.ag_agendamentos for delete to authenticated
  using (public.ag_papel() in ('gestor','recepcao'));

create policy ag_vagas_select on public.ag_vagas for select to authenticated
  using (public.ag_papel() is not null);
create policy ag_vagas_update on public.ag_vagas for update to authenticated
  using (public.ag_papel() = 'gestor') with check (public.ag_papel() = 'gestor');

create policy ag_historico_select on public.ag_historico for select to authenticated
  using (public.ag_papel() = 'gestor');

revoke all on function public.ag_usuario_atual(), public.ag_papel(), public.ag_nome_atual(),
  public.ag_agendamentos_antes(), public.ag_agendamentos_depois(), public.ag_usuarios_antes(),
  public.ag_gerar_codigo(text), public.ag_primeiro_acesso(text,text,text), public.ag_liberar_usuario(text,text,text),
  public.ag_novo_codigo(text), public.ag_remover_usuario(text), public.ag_contas(), public.ag_importar(jsonb,jsonb,int)
  from public, anon, authenticated;
grant execute on function public.ag_usuario_atual(), public.ag_papel(), public.ag_nome_atual(),
  public.ag_liberar_usuario(text,text,text), public.ag_novo_codigo(text), public.ag_remover_usuario(text),
  public.ag_contas(), public.ag_importar(jsonb,jsonb,int) to authenticated;
grant execute on function public.ag_primeiro_acesso(text,text,text) to anon, authenticated;

-- Avisa as outras telas quando algo muda
do $$ begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
end $$;
alter publication supabase_realtime add table public.ag_agendamentos, public.ag_vagas;
