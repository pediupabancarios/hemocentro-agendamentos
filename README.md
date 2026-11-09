# Hemocentro JP — Sistema de Agendamentos

Agendamento de transfusão, transfusão pediátrica, medicações e sangria terapêutica do Hemocentro de João Pessoa.

## Arquivos

- `index.html` — o aplicativo inteiro (HTML, CSS e JS)
- `manifest.json`, `sw.js`, `icons/` — instalação como app
- `supabase/001_agendamentos.sql` — tabelas, regras e funções do banco
- `supabase/002_gestor_inicial.sql` — cria o gestor inicial (fora do git)
- `supabase/003_trava_vagas.sql` — ajuste da trava de reservas simultâneas

Não precisa de compilação. Qualquer hospedagem estática com HTTPS serve (GitHub Pages, Netlify).

## Banco de dados

Supabase `ohuaoncwgioawgptyqgz`, compartilhado com outros apps. Este usa só as tabelas com prefixo `ag_`:

| Tabela | Conteúdo |
| --- | --- |
| `ag_agendamentos` | Agendamentos |
| `ag_vagas` | Vagas por serviço e turno |
| `ag_usuarios` | Quem tem acesso e com qual perfil |
| `ag_codigos` | Códigos de primeiro acesso (só o hash; ninguém lê pela API) |
| `ag_historico` | Quem mudou o quê, com o antes e o depois de cada registro |

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

- As vagas são **por dia**, por serviço e turno (e por gênero em Transfusão e Sangria). Cancelados não contam.
- Quem garante as vagas é o banco, inclusive quando duas pessoas reservam ao mesmo tempo.
- Com o turno lotado, a recepção é bloqueada; o gestor pode autorizar um encaixe.
- Manhã aceita horários das 07:00 às 12:00; Tarde, das 12:00 às 18:00.
- Perfil médico: somente leitura. Painel do Gestor, Usuários e histórico de alterações: somente gestor.
- Tipo sanguíneo começa como "Não informado"; o sistema não presume um valor.

## Backup

O plano gratuito do Supabase não faz backup automático. Exporte com frequência em **Painel do Gestor → Backup dos dados**.
O arquivo contém dados de pacientes (LGPD). Registro apagado por engano pode ser recuperado de `ag_historico`.

## Testar localmente

```bash
cd ~/Downloads/hemocentro-agendamentos-projeto && python3 -m http.server 8870
```

Depois abra http://localhost:8870. **Atenção:** mesmo em localhost, o app usa o banco real.
