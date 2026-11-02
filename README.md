# Caren Bragagnollo · Estética Facial

Site de agendamento online e painel de gestão da Caren Bragagnollo (Guaíra/PR).

- **Site:** https://bazzuka-root.github.io/caren-bragagnollo/
- **Painel da Caren:** https://bazzuka-root.github.io/caren-bragagnollo/#painel

## Como funciona

Um único arquivo (`index.html`) publicado no GitHub Pages, ligado a um banco no Supabase (projeto `caren-bragagnollo`, região São Paulo).

| Parte | O que faz |
|---|---|
| Site público | Páginas Início, Procedimentos, Agendar, Meus horários, Sobre, Dúvidas e Contato. Lê horários livres e agenda pelas funções do banco. |
| Meus horários | A cliente consulta, remarca ou cancela com telefone + código do agendamento. |
| Painel (`#painel`) | Login da Caren (Supabase Auth). Hoje, Agenda (dia/semana/lista), Clientes, Financeiro, Procedimentos, Horários e folgas, Mensagens, Configurações. Atualiza em tempo real quando chega agendamento. |

## Segurança

- Todas as tabelas têm RLS. Visitantes não leem agendamentos nem dados de clientes.
- O site público só usa as funções `busy_slots`, `book_appointment`, `my_appointments`, `client_cancel`, `client_reschedule` e `send_message`, que validam horário, expediente, bloqueios e conflitos no servidor.
- Só usuários na tabela `admins` acessam o painel.
- A chave no `index.html` é a chave pública (publishable) do Supabase. Nunca coloque a `service_role` no site.

## Banco

Os scripts estão em `supabase/` (`01_schema.sql`, `02_funcoes.sql`) para recriar o banco se precisar.

## Ajustes no painel do Supabase

1. **Authentication → URL Configuration:** Site URL = `https://bazzuka-root.github.io/caren-bragagnollo/` e o mesmo endereço em Redirect URLs (para o link de "Esqueci a senha").
2. **Authentication → Providers → Email:** desligar "Allow new users to sign up".
3. **Authentication → Password security:** ligar a proteção contra senhas vazadas.
