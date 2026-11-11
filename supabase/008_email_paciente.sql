-- E-mail no cadastro do paciente, para enviar a lista de agendamentos por e-mail.
alter table public.ag_pacientes add column email text
  check (email is null or email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$');
grant update (email) on public.ag_pacientes to authenticated;

create or replace function public.ag_pacientes_antes() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.nome := trim(new.nome);
  new.cpf := nullif(new.cpf, '');
  new.cns := nullif(new.cns, '');
  new.email := nullif(lower(trim(new.email)), '');
  new.atualizado_em := now();
  if tg_op = 'INSERT' then
    new.criado_em := now();
    new.criado_por := public.ag_nome_atual();
  else
    new.id := old.id; new.criado_em := old.criado_em; new.criado_por := old.criado_por;
  end if;
  return new;
end $$;
revoke all on function public.ag_pacientes_antes() from public, anon, authenticated;
