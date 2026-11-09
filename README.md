# Hemocentro JP — Sistema de Agendamentos

Agendamento de transfusão, transfusão pediátrica, medicações e sangria terapêutica do Hemocentro de João Pessoa.

## Arquivos

- `index.html` — o aplicativo inteiro (HTML, CSS e JS)
- `manifest.json`, `sw.js`, `icons/` — instalação como app
- `supabase/001_agendamentos.sql` — tabelas, regras e funções do banco
- `supabase/002_gestor_inicial.sql` — cria o gestor inicial (fora do git)
- `supabase/003_trava_vagas.sql` — ajuste da trava de reservas simultâneas
- `supabase/004_dias_e_comparecimento.sql` — dias de atendimento, datas bloqueadas e status Compareceu/Faltou
- `supabase/005_pacientes_e_series.sql` — cadastro único de pacientes e agendamentos em série
- `supabase/006_backup_automatico.sql` — cópia diária no servidor e função de restauração
- `supabase/007_horario_opcional.sql` — agendamento só por turno (horário opcional)

Não precisa de compilação. Qualquer hospedagem estática com HTTPS serve (GitHub Pages, Netlify).

## Banco de dados

Supabase `ohuaoncwgioawgptyqgz`, compartilhado com outros apps. Este usa só as tabelas com prefixo `ag_`:

| Tabela | Conteúdo |
| --- | --- |
| `ag_agendamentos` | Agendamentos |
| `ag_vagas` | Vagas por serviço e turno, e dias da semana com atendimento |
| `ag_bloqueios` | Feriados e outras datas sem atendimento |
| `ag_pacientes` | Cadastro único: nome, CPF, Cartão SUS, telefone, tipo sanguíneo, gênero |
| `ag_usuarios` | Quem tem acesso e com qual perfil |
| `ag_codigos` | Códigos de primeiro acesso (só o hash; ninguém lê pela API) |
| `ag_historico` | Quem mudou o quê, com o antes e o depois de cada registro |
| `ag_backups` | Cópias completas das tabelas `ag_*` (só o gestor lê) |

Sem login não se lê nem se grava nada. A agenda se atualiza sozinha nas outras telas e é preciso internet para usar.

## Acesso

O login é por nome de usuário. As contas ficam no Supabase Auth com e-mail técnico `<usuario>@ag.hemocentro.invalid`.

1. O gestor cadastra a pessoa em **Usuários** e recebe um código de uso único, válido por 7 dias.
2. A pessoa escolhe **Primeiro acesso ou esqueci a senha** no login e cria a própria senha.
3. Esqueceu a senha: o gestor gera um código novo no botão 🔑.

Primeiro gestor: usuário `gestor`, com o código do arquivo local `PRIMEIRO_ACESSO.txt`. Apague o arquivo depois de entrar.

## Dados da versão antiga

A versão anterior guardava tudo no navegador. Publique esta versão **no mesmo endereço antigo** e entre como gestor nesse
mesmo navegador: o **Painel do Gestor** mostra quantos agendamentos existem ali e oferece **Enviar para o banco**.
Depois do envio completo, ele oferece apagar a cópia local. Quem tiver um arquivo de backup pode usar **Importar backup**.

## Regras de negócio

- As vagas são **por dia**, por serviço e turno (e por gênero em Transfusão e Sangria).
  Ocupam vaga: Confirmado, Pendente e Compareceu. Cancelado e Faltou liberam.
- Só se agenda nos **dias de atendimento** (padrão: segunda a sexta) e fora das **datas bloqueadas**,
  ambos configurados no Painel do Gestor (`ag_vagas.dias_semana` e `ag_bloqueios`). O gestor pode encaixar fora deles.
- Marcar Compareceu/Faltou não reabre a checagem de vagas; reativar um cancelado ou faltoso, sim.
- Todo agendamento novo é de um paciente do cadastro. CPF e Cartão SUS são opcionais, mas únicos e validados.
  O agendamento copia nome, telefone e tipo sanguíneo do cadastro; editar o cadastro atualiza os agendamentos de hoje em diante.
- Série: de 2 a 12 repetições, a cada 1 a 90 dias. Cada data passa pelas mesmas regras de vagas e dias;
  as datas sem vaga são puladas (ou, para o gestor, viram encaixe se ele escolher).
- Importar backup restaura agendamentos, mas não o cadastro de pacientes.
- Quem garante as vagas é o banco, inclusive quando duas pessoas reservam ao mesmo tempo.
- Com o turno lotado, a recepção é bloqueada; o gestor pode autorizar um encaixe.
- O agendamento é por **turno** (Manhã 07h–12h, Tarde 12h–18h), sem horário. Dentro do turno, a ordem é a de agendamento (protocolo).
- Perfil médico: somente leitura. Painel do Gestor, Usuários e histórico de alterações: somente gestor.
- Tipo sanguíneo começa como "Não informado"; o sistema não presume um valor.

## Backup

- **Automático:** todo dia às 06:00 (horário de João Pessoa) o banco copia agendamentos, pacientes, vagas, feriados
  e usuários para `ag_backups` (job `ag-backup-diario` do `pg_cron`). Ficam as 30 últimas cópias automáticas.
- **Manual:** Painel do Gestor → Backup dos dados → **☁️ Fazer agora**. As cópias manuais não são apagadas sozinhas.
- **Fora do servidor:** baixe uma cópia (⬇️) de vez em quando; se o projeto Supabase for perdido, as cópias internas vão junto.
  O arquivo contém dados de pacientes (LGPD).
- **Restaurar:** só por SQL, como administrador: `select public.ag_restaurar_backup(<id>, 'RESTAURAR');`.
  Substitui agendamentos, pacientes, feriados, vagas e dias; não mexe em usuários. Antes, guarda uma cópia do estado atual.
- Um registro apagado por engano também pode ser recuperado de `ag_historico`.

## Testar localmente

```bash
cd ~/Downloads/hemocentro-agendamentos-projeto && python3 -m http.server 8870
```

Depois abra http://localhost:8870. **Atenção:** mesmo em localhost, o app usa o banco real.
