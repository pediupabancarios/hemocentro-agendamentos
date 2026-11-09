-- Backup automático diário das tabelas ag_* dentro do próprio banco (o plano gratuito não tem backup).
-- Guarda 30 cópias automáticas; as manuais ficam até alguém apagar por SQL.
-- Restauração: só por SQL, com public.ag_restaurar_backup(id, 'RESTAURAR'), que não é exposta à API.

create extension if not exists pg_cron;

create table public.ag_backups (
  id        bigint generated always as identity primary key,
  criado_em timestamptz not null default now(),
  tipo      text not null check (tipo in ('auto','manual')),
  criado_por text,
  resumo    jsonb not null,
  dados     jsonb not null
);
alter table public.ag_backups enable row level security;
revoke all on public.ag_backups from anon, authenticated, public;
grant select on public.ag_backups to authenticated;
create policy ag_backups_select on public.ag_backups for select to authenticated
  using (public.ag_papel() = 'gestor');

create function public.ag_fazer_backup(p_tipo text) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_id bigint; v_dados jsonb;
begin
  v_dados := jsonb_build_object(
    'versao', 1,
    'agendamentos', coalesce((select jsonb_agg(to_jsonb(a)) from public.ag_agendamentos a), '[]'),
    'pacientes',    coalesce((select jsonb_agg(to_jsonb(p)) from public.ag_pacientes p), '[]'),
    'vagas',        (select to_jsonb(v) from public.ag_vagas v where id = 1),
    'bloqueios',    coalesce((select jsonb_agg(to_jsonb(b)) from public.ag_bloqueios b), '[]'),
    'usuarios',     coalesce((select jsonb_agg(to_jsonb(u)) from public.ag_usuarios u), '[]'));
  insert into public.ag_backups (tipo, criado_por, resumo, dados)
  values (p_tipo, public.ag_nome_atual(),
          jsonb_build_object('agendamentos', jsonb_array_length(v_dados->'agendamentos'),
                             'pacientes', jsonb_array_length(v_dados->'pacientes'),
                             'bloqueios', jsonb_array_length(v_dados->'bloqueios')),
          v_dados)
  returning id into v_id;
  delete from public.ag_backups where tipo = 'auto' and id not in
    (select id from public.ag_backups where tipo = 'auto' order by criado_em desc limit 30);
  return v_id;
end $$;

create function public.ag_backup_manual() returns bigint
language plpgsql security definer set search_path = public as $$
begin
  if public.ag_papel() is distinct from 'gestor' then raise exception 'Apenas o gestor'; end if;
  if exists (select 1 from public.ag_backups where tipo = 'manual' and criado_em > now() - interval '1 minute') then
    raise exception 'Já foi feito um backup há menos de 1 minuto';
  end if;
  return public.ag_fazer_backup('manual');
end $$;

-- Substitui os dados das tabelas ag_* pelo conteúdo do backup. Usuários e códigos não são tocados.
create function public.ag_restaurar_backup(p_id bigint, p_confirma text) returns text
language plpgsql security definer set search_path = public as $$
declare d jsonb;
begin
  if p_confirma is distinct from 'RESTAURAR' then raise exception 'Confirme com RESTAURAR'; end if;
  select dados into d from public.ag_backups where id = p_id;
  if d is null then raise exception 'Backup não encontrado'; end if;
  perform public.ag_fazer_backup('manual'); -- cópia do estado atual antes de restaurar
  alter table public.ag_agendamentos disable trigger ag_agendamentos_antes;
  alter table public.ag_agendamentos disable trigger ag_agendamentos_paciente;
  delete from public.ag_agendamentos;
  delete from public.ag_pacientes;
  delete from public.ag_bloqueios;
  insert into public.ag_pacientes select * from jsonb_populate_recordset(null::public.ag_pacientes, d->'pacientes');
  insert into public.ag_agendamentos select * from jsonb_populate_recordset(null::public.ag_agendamentos, d->'agendamentos');
  insert into public.ag_bloqueios select * from jsonb_populate_recordset(null::public.ag_bloqueios, d->'bloqueios');
  update public.ag_vagas set caps = d->'vagas'->'caps',
    dias_semana = coalesce((select array_agg(x::int) from jsonb_array_elements_text(d->'vagas'->'dias_semana') x), dias_semana)
  where id = 1;
  alter table public.ag_agendamentos enable trigger ag_agendamentos_antes;
  alter table public.ag_agendamentos enable trigger ag_agendamentos_paciente;
  return 'Restaurado o backup ' || p_id;
end $$;

revoke all on function public.ag_fazer_backup(text), public.ag_backup_manual(), public.ag_restaurar_backup(bigint, text)
  from public, anon, authenticated;
grant execute on function public.ag_backup_manual() to authenticated;

-- Todo dia às 06:00 de João Pessoa (09:00 UTC)
select cron.schedule('ag-backup-diario', '0 9 * * *', $$select public.ag_fazer_backup('auto')$$);
