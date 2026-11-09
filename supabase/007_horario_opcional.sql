-- O agendamento passa a ser só por turno (Manhã/Tarde); o horário fica opcional.
-- Registros antigos com horário continuam válidos; a regra de formato só vale quando há horário.
alter table public.ag_agendamentos alter column horario drop not null;
