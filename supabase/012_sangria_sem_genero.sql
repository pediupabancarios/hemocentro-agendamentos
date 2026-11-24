-- 012: Sangria passa a ter vagas só por turno (homens e mulheres juntos).
-- Tarde: 10 vagas. Manhã: mantém o total que já existia (fem. + masc.).
-- As chaves antigas (fmanha/ftarde/mmanha/mtarde) ficam no JSON até a nova versão do app estar no ar.

update public.ag_vagas
   set caps = jsonb_set(caps, '{S}',
         (caps->'S') || jsonb_build_object(
           'manha', coalesce((caps->'S'->>'fmanha')::int,0) + coalesce((caps->'S'->>'mmanha')::int,0),
           'tarde', 10))
 where id = 1;

create or replace function public.ag_agendamentos_antes()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
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
    -- Só a Transfusão separa vagas por gênero.
    if v_cod = 'T' then
      v_sub := case when new.genero = 'Feminino' then 'f' else 'm' end || v_sub;
    end if;
    perform pg_advisory_xact_lock(hashtext('ag|' || new.data || '|' || v_cod || '|' || v_sub));
    select (caps->v_cod->>v_sub)::int into v_max from public.ag_vagas where id = 1;
    select count(*) into v_usados from public.ag_agendamentos a
      where a.data = new.data and a.servico = new.servico and a.turno = new.turno
        and a.status in ('Confirmado','Pendente','Compareceu') and a.id <> new.id
        and (v_cod <> 'T' or (a.genero = 'Feminino') = (new.genero = 'Feminino'));
    if v_usados >= coalesce(v_max, 0) and not new.encaixe then
      raise exception 'LOTADO:%:%', v_usados, coalesce(v_max, 0) using errcode = 'P0001';
    end if;
  end if;
  return new;
end $function$;
