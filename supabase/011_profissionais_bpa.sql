-- Profissionais que assinam o BPA-I (escolhidos numa lista na tela do BPA).
create table public.ag_profissionais (
  id        text primary key default gen_random_uuid()::text check (id ~ '^[A-Za-z0-9_-]+$'),
  nome      text not null check (length(trim(nome)) > 0),
  cns       text check (cns ~ '^[0-9]{15}$'),
  cbo       text not null default '223505' check (cbo ~ '^[0-9]{6}$'),
  ativo     boolean not null default true,
  criado_em timestamptz not null default now()
);
alter table public.ag_profissionais enable row level security;
revoke all on public.ag_profissionais from anon, authenticated, public;
grant select, insert, update, delete on public.ag_profissionais to authenticated;
create policy ag_profissionais_select on public.ag_profissionais for select to authenticated
  using (public.ag_papel() is not null);
create policy ag_profissionais_insert on public.ag_profissionais for insert to authenticated
  with check (public.ag_papel() = 'gestor');
create policy ag_profissionais_update on public.ag_profissionais for update to authenticated
  using (public.ag_papel() = 'gestor') with check (public.ag_papel() = 'gestor');
create policy ag_profissionais_delete on public.ag_profissionais for delete to authenticated
  using (public.ag_papel() = 'gestor');

insert into public.ag_profissionais (nome, cns, cbo) values ('MARIA DO SOCORRO DE MELO', '898003784303946', '223505');
