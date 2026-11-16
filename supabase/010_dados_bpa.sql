-- Dados do paciente exigidos pelo BPA-I (Boletim de Produção Ambulatorial individualizado).
alter table public.ag_pacientes
  add column nascimento    date,
  add column raca_cor      text not null default '' check (raca_cor in ('','Branca','Preta','Parda','Indígena','Amarela')),
  add column endereco      text not null default '',
  add column numero        text not null default '',
  add column complemento   text not null default '',
  add column bairro        text not null default '',
  add column municipio     text not null default '',
  add column cep           text check (cep ~ '^[0-9]{8}$'),
  add column cod_municipio text check (cod_municipio ~ '^[0-9]{6,7}$');
grant update (nascimento, raca_cor, endereco, numero, complemento, bairro, municipio, cep, cod_municipio)
  on public.ag_pacientes to authenticated;
