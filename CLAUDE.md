# Hemocentro JP — Sistema de Agendamentos

App independente: não misturar com Triagem Clínica, MedEscala, Segunda Amostra, Prontuário ou Escala de plantões.
Regras de negócio, banco e acesso estão no `README.md`.

## Banco

O Supabase é de produção e compartilhado com outros apps: mexa só em objetos `ag_*`.
Alteração de esquema entra como novo arquivo em `supabase/` e precisa da autorização explícita do usuário.

## Ao editar `index.html`

- Todo texto digitado que vai para `innerHTML` passa por `esc()`/`escObj()`, inclusive nas janelas de impressão.
  Em `onclick`, passe só o `id`, nunca nome ou telefone (nomes como D'Ávila quebram a string).
- Datas: use `hoje()`/`todayStr()` (hora local). Não use `toISOString()`: após as 21h em João Pessoa ela dá o dia seguinte.
- Vagas são por dia: use `getUsed(chave, data)`. O aviso na tela é só conveniência; a regra real está no gatilho `ag_agendamentos_antes`.
- Gravações: em `update`/`delete`, use `.select()` e confira se voltou linha. RLS recusa sem erro, com zero linhas.
- Erros do servidor passam por `dbMsg()`. Toda alteração de dados termina em `refreshViews()`.
- Leitura de agendamentos sempre por `fetchPatients()`: o servidor limita a 1000 linhas por consulta.
- Dados de pacientes não ficam no `localStorage`. `hemo_*` existe só para migrar a versão antiga.
- Mudou ícones ou manifest: suba `CACHE` em `sw.js`.
- Responder em português do Brasil.

## Testes

O servidor de preview não lê `~/Downloads` (bloqueio do macOS): copie para o scratchpad e sirva de lá.
Não teste com dados fictícios no banco real sem combinar com o usuário.
