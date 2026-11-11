-- Lembretes da véspera (quem já foi avisado) e lista de espera para turnos lotados.

alter table public.ag_agendamentos
  add column lembrete_em  timestamptz,
  add column lembrete_por text;

create table public.ag_espera (
  id          text primary key default gen_random_uuid()::text check (id ~ '^[A-Za-z0-9_-]+$'),
  paciente_id text not null references public.ag_pacientes(id) on delete cascade,
  data        date not null,
  servico     text not null check (servico in ('Transfusão','Pediátrica','Medicações','Sangria')),
  turno       text not null check (turno in ('Manhã','Tarde')),
  genero      text not null default '' check (genero in ('','Feminino','Masculino')),
  obs         text not null default '',
  criado_por  text,
  criado_em   timestamptz not null default now()
);
create index ag_espera_data_idx on public.ag_espera (data, servico, turno);

create function public.ag_espera_antes() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.criado_em := now();
  new.criado_por := public.ag_nome_atual();
  return new;
end $$;
create trigger ag_espera_antes before insert on public.ag_espera
  for each row execute function public.ag_espera_antes();

alter table public.ag_espera enable row level security;
revoke all on public.ag_espera from anon, authenticated, public;
grant select, insert, delete on public.ag_espera to authenticated;
create policy ag_espera_select on public.ag_espera for select to authenticated
  using (public.ag_papel() is not null);
create policy ag_espera_insert on public.ag_espera for insert to authenticated
  with check (public.ag_papel() in ('gestor','recepcao'));
create policy ag_espera_delete on public.ag_espera for delete to authenticated
  using (public.ag_papel() in ('gestor','recepcao'));
revoke all on function public.ag_espera_antes() from public, anon, authenticated;

alter publication supabase_realtime add table public.ag_espera;

-- Backup e restauração passam a incluir a lista de espera.
create or replace function public.ag_fazer_backup(p_tipo text) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_id bigint; v_dados jsonb;
begin
  v_dados := jsonb_build_object(
    'versao', 2,
    'agendamentos', coalesce((select jsonb_agg(to_jsonb(a)) from public.ag_agendamentos a), '[]'),
    'pacientes',    coalesce((select jsonb_agg(to_jsonb(p)) from public.ag_pacientes p), '[]'),
    'vagas',        (select to_jsonb(v) from public.ag_vagas v where id = 1),
    'bloqueios',    coalesce((select jsonb_agg(to_jsonb(b)) from public.ag_bloqueios b), '[]'),
    'espera',       coalesce((select jsonb_agg(to_jsonb(e)) from public.ag_espera e), '[]'),
    'usuarios',     coalesce((select jsonb_agg(to_jsonb(u)) from public.ag_usuarios u), '[]'));
  insert into public.ag_backups (tipo, criado_por, resumo, dados)
  values (p_tipo, public.ag_nome_atual(),
          jsonb_build_object('agendamentos', jsonb_array_length(v_dados->'agendamentos'),
                             'pacientes', jsonb_array_length(v_dados->'pacientes'),
                             'bloqueios', jsonb_array_length(v_dados->'bloqueios'),
                             'espera', jsonb_array_length(v_dados->'espera')),
          v_dados)
  returning id into v_id;
  delete from public.ag_backups where tipo = 'auto' and id not in
    (select id from public.ag_backups where tipo = 'auto' order by criado_em desc limit 30);
  return v_id;
end $$;

create or replace function public.ag_restaurar_backup(p_id bigint, p_confirma text) returns text
language plpgsql security definer set search_path = public as $$
declare d jsonb;
begin
  if p_confirma is distinct from 'RESTAURAR' then raise exception 'Confirme com RESTAURAR'; end if;
  select dados into d from public.ag_backups where id = p_id;
  if d is null then raise exception 'Backup não encontrado'; end if;
  perform public.ag_fazer_backup('manual'); -- cópia do estado atual antes de restaurar
  alter table public.ag_agendamentos disable trigger ag_agendamentos_antes;
  alter table public.ag_agendamentos disable trigger ag_agendamentos_paciente;
  alter table public.ag_espera disable trigger ag_espera_antes;
  delete from public.ag_espera;
  delete from public.ag_agendamentos;
  delete from public.ag_pacientes;
  delete from public.ag_bloqueios;
  insert into public.ag_pacientes select * from jsonb_populate_recordset(null::public.ag_pacientes, d->'pacientes');
  insert into public.ag_agendamentos select * from jsonb_populate_recordset(null::public.ag_agendamentos, d->'agendamentos');
  insert into public.ag_bloqueios select * from jsonb_populate_recordset(null::public.ag_bloqueios, d->'bloqueios');
  insert into public.ag_espera select * from jsonb_populate_recordset(null::public.ag_espera, coalesce(d->'espera','[]'));
  update public.ag_vagas set caps = d->'vagas'->'caps',
    dias_semana = coalesce((select array_agg(x::int) from jsonb_array_elements_text(d->'vagas'->'dias_semana') x), dias_semana)
  where id = 1;
  alter table public.ag_agendamentos enable trigger ag_agendamentos_antes;
  alter table public.ag_agendamentos enable trigger ag_agendamentos_paciente;
  alter table public.ag_espera enable trigger ag_espera_antes;
  return 'Restaurado o backup ' || p_id;
end $$;
revoke all on function public.ag_fazer_backup(text), public.ag_restaurar_backup(bigint, text) from public, anon, authenticated;
