-- Cadastro único de pacientes (CPF / Cartão SUS) e agendamentos em série.
-- O agendamento guarda uma cópia de nome, telefone e tipo sanguíneo do cadastro;
-- quando o cadastro muda, os agendamentos de hoje em diante são atualizados.

create table public.ag_pacientes (
  id             text primary key default gen_random_uuid()::text check (id ~ '^[A-Za-z0-9_-]+$'),
  nome           text not null check (length(trim(nome)) > 0),
  cpf            text unique check (cpf ~ '^[0-9]{11}$'),
  cns            text unique check (cns ~ '^[0-9]{15}$'),
  telefone       text not null default '',
  tipo_sanguineo text not null default '' check (tipo_sanguineo in ('','A+','A-','B+','B-','AB+','AB-','O+','O-')),
  genero         text not null default '' check (genero in ('','Feminino','Masculino')),
  criado_por     text,
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now()
);
create index ag_pacientes_nome_idx on public.ag_pacientes (lower(nome));

alter table public.ag_agendamentos
  add column paciente_id text references public.ag_pacientes(id) on delete restrict,
  add column serie_id text check (serie_id ~ '^[A-Za-z0-9_-]+$');
create index ag_agendamentos_paciente_idx on public.ag_agendamentos (paciente_id);
create index ag_agendamentos_serie_idx on public.ag_agendamentos (serie_id);

create function public.ag_pacientes_antes() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.nome := trim(new.nome);
  new.cpf := nullif(new.cpf, '');
  new.cns := nullif(new.cns, '');
  new.atualizado_em := now();
  if tg_op = 'INSERT' then
    new.criado_em := now();
    new.criado_por := public.ag_nome_atual();
  else
    new.id := old.id; new.criado_em := old.criado_em; new.criado_por := old.criado_por;
  end if;
  return new;
end $$;
create trigger ag_pacientes_antes before insert or update on public.ag_pacientes
  for each row execute function public.ag_pacientes_antes();

create function public.ag_pacientes_depois() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' and (new.nome, new.telefone, new.tipo_sanguineo) is distinct from (old.nome, old.telefone, old.tipo_sanguineo) then
    update public.ag_agendamentos
       set nome = new.nome, telefone = new.telefone, tipo_sanguineo = new.tipo_sanguineo
     where paciente_id = new.id and data >= (now() at time zone 'America/Fortaleza')::date;
  end if;
  insert into public.ag_historico (quem, acao, agendamento_id, antes, depois)
  values (public.ag_nome_atual(), 'PACIENTE_' || tg_op, 'pac:' || new.id,
          case when tg_op = 'UPDATE' then to_jsonb(old) end, to_jsonb(new));
  return null;
end $$;
create trigger ag_pacientes_depois after insert or update on public.ag_pacientes
  for each row execute function public.ag_pacientes_depois();

-- O agendamento vinculado sempre copia os dados do cadastro, venha o que vier do app.
create function public.ag_agendamentos_paciente() returns trigger
language plpgsql security definer set search_path = public as $$
declare p public.ag_pacientes;
begin
  if new.paciente_id is not null and (tg_op = 'INSERT' or new.paciente_id is distinct from old.paciente_id) then
    select * into p from public.ag_pacientes where id = new.paciente_id;
    if found then
      new.nome := p.nome; new.telefone := p.telefone; new.tipo_sanguineo := p.tipo_sanguineo;
    end if;
  end if;
  return new;
end $$;
create trigger ag_agendamentos_paciente before insert or update on public.ag_agendamentos
  for each row execute function public.ag_agendamentos_paciente();

alter table public.ag_pacientes enable row level security;
revoke all on public.ag_pacientes from anon, authenticated, public;
grant select, insert, delete on public.ag_pacientes to authenticated;
grant update (nome, cpf, cns, telefone, tipo_sanguineo, genero) on public.ag_pacientes to authenticated;
create policy ag_pacientes_select on public.ag_pacientes for select to authenticated
  using (public.ag_papel() is not null);
create policy ag_pacientes_insert on public.ag_pacientes for insert to authenticated
  with check (public.ag_papel() in ('gestor','recepcao'));
create policy ag_pacientes_update on public.ag_pacientes for update to authenticated
  using (public.ag_papel() in ('gestor','recepcao')) with check (public.ag_papel() in ('gestor','recepcao'));
create policy ag_pacientes_delete on public.ag_pacientes for delete to authenticated
  using (public.ag_papel() = 'gestor');

revoke all on function public.ag_pacientes_antes(), public.ag_pacientes_depois(), public.ag_agendamentos_paciente()
  from public, anon, authenticated;

alter publication supabase_realtime add table public.ag_pacientes;
