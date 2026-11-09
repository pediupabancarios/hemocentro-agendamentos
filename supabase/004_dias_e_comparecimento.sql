-- Dias de atendimento, datas bloqueadas (feriados) e status Compareceu/Faltou.
-- Ocupam vaga: Confirmado, Pendente e Compareceu. Cancelado e Faltou liberam.

alter table public.ag_vagas
  add column dias_semana int[] not null default '{1,2,3,4,5}'
  check (dias_semana <@ '{0,1,2,3,4,5,6}'::int[]); -- 0 = domingo
grant update (dias_semana) on public.ag_vagas to authenticated;

create table public.ag_bloqueios (
  data       date primary key,
  motivo     text not null default '' check (length(motivo) <= 100),
  criado_por text,
  criado_em  timestamptz not null default now()
);
alter table public.ag_bloqueios enable row level security;
revoke all on public.ag_bloqueios from anon, authenticated, public;
grant select, insert, update, delete on public.ag_bloqueios to authenticated;
create policy ag_bloqueios_select on public.ag_bloqueios for select to authenticated
  using (public.ag_papel() is not null);
create policy ag_bloqueios_insert on public.ag_bloqueios for insert to authenticated
  with check (public.ag_papel() = 'gestor');
create policy ag_bloqueios_update on public.ag_bloqueios for update to authenticated
  using (public.ag_papel() = 'gestor') with check (public.ag_papel() = 'gestor');
create policy ag_bloqueios_delete on public.ag_bloqueios for delete to authenticated
  using (public.ag_papel() = 'gestor');

alter table public.ag_agendamentos drop constraint if exists ag_agendamentos_status_check;
alter table public.ag_agendamentos add constraint ag_agendamentos_status_check
  check (status in ('Confirmado','Pendente','Cancelado','Compareceu','Faltou'));

create or replace function public.ag_agendamentos_antes() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_papel text := public.ag_papel();
  v_cod text; v_sub text; v_max int; v_usados int; v_checar boolean;
  v_dias int[]; v_motivo text;
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
    -- Marcar Compareceu/Faltou não reabre a checagem; reativar um cancelado ou faltoso, sim.
    v_checar := new.data is distinct from old.data or new.servico is distinct from old.servico
             or new.turno is distinct from old.turno or new.genero is distinct from old.genero
             or (old.status in ('Cancelado','Faltou') and new.status in ('Confirmado','Pendente'));
  end if;

  if new.encaixe and v_papel is distinct from 'gestor' and (tg_op = 'INSERT' or v_checar) then
    new.encaixe := false;
  end if;

  if new.status in ('Confirmado','Pendente','Compareceu') and v_checar then
    if not new.encaixe then
      select dias_semana into v_dias from public.ag_vagas where id = 1;
      if not (extract(dow from new.data)::int = any(v_dias)) then
        raise exception 'FECHADO:Sem atendimento neste dia da semana' using errcode = 'P0001';
      end if;
      select motivo into v_motivo from public.ag_bloqueios where data = new.data;
      if found then
        raise exception 'FECHADO:%', coalesce(nullif(v_motivo,''), 'Data bloqueada') using errcode = 'P0001';
      end if;
    end if;
    v_cod := case new.servico when 'Transfusão' then 'T' when 'Pediátrica' then 'P' when 'Medicações' then 'M' else 'S' end;
    v_sub := case new.turno when 'Manhã' then 'manha' else 'tarde' end;
    if v_cod in ('T','S') then
      v_sub := case when new.genero = 'Feminino' then 'f' else 'm' end || v_sub;
    end if;
    perform pg_advisory_xact_lock(hashtext('ag|' || new.data || '|' || v_cod || '|' || v_sub));
    select (caps->v_cod->>v_sub)::int into v_max from public.ag_vagas where id = 1;
    select count(*) into v_usados from public.ag_agendamentos a
      where a.data = new.data and a.servico = new.servico and a.turno = new.turno
        and a.status in ('Confirmado','Pendente','Compareceu') and a.id <> new.id
        and (v_cod in ('P','M') or (a.genero = 'Feminino') = (new.genero = 'Feminino'));
    if v_usados >= coalesce(v_max, 0) and not new.encaixe then
      raise exception 'LOTADO:%:%', v_usados, coalesce(v_max, 0) using errcode = 'P0001';
    end if;
  end if;
  return new;
end $$;
revoke all on function public.ag_agendamentos_antes() from public, anon, authenticated;

alter publication supabase_realtime add table public.ag_bloqueios;
