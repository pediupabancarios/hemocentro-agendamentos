-- A trava de reserva simultânea precisa cobrir exatamente o conjunto de vagas contado:
-- em Pediátrica e Medicações o gênero não divide vagas; em Transfusão e Sangria, vazio conta como Masculino.
create or replace function public.ag_agendamentos_antes() returns trigger
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

  if new.encaixe and v_papel is distinct from 'gestor' and (tg_op = 'INSERT' or v_checar) then
    new.encaixe := false;
  end if;

  if new.status <> 'Cancelado' and v_checar then
    v_cod := case new.servico when 'Transfusão' then 'T' when 'Pediátrica' then 'P' when 'Medicações' then 'M' else 'S' end;
    v_sub := case new.turno when 'Manhã' then 'manha' else 'tarde' end;
    if v_cod in ('T','S') then
      v_sub := case when new.genero = 'Feminino' then 'f' else 'm' end || v_sub;
    end if;
    perform pg_advisory_xact_lock(hashtext('ag|' || new.data || '|' || v_cod || '|' || v_sub));
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
revoke all on function public.ag_agendamentos_antes() from public, anon, authenticated;
