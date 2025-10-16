# Chat_App_Flutter_Supabase

📱 Chat App em Tempo Real (Flutter + Supabase)
Bem-vindo ao nosso projeto de chat em tempo real! Este é um aplicativo de mensagens instantâneas desenvolvido para a disciplina de Programação para Dispositivos Móveis.

O objetivo principal é criar um app de comunicação funcional e moderno, demonstrando como as tecnologias atuais, como Flutter e Supabase, podem ser usadas para construir aplicações poderosas e em tempo real de forma eficiente.

✨ O que o aplicativo faz?
De forma simples, este app permite que os usuários se comuniquem uns com os outros, seja em conversas privadas ou em grupos. É como uma versão simplificada dos aplicativos de mensagens que todos nós usamos no dia a dia.

Principais Funcionalidades:

Contas de Usuário: Você pode se cadastrar e fazer login de forma segura.

Perfil Personalizado: Cada usuário tem seu próprio perfil, com nome e foto.

Conversas Individuais e em Grupo: Chame um amigo para uma conversa particular ou crie um grupo para falar com várias pessoas ao mesmo tempo.

Mensagens Instantâneas: Envie mensagens de texto, imagens ou arquivos leves e veja-os chegar ao destino em tempo real.

Status de Atividade: Saiba quando alguém está online ou digitando uma mensagem.

Busca Inteligente: Encontre facilmente outros usuários ou grupos públicos para iniciar uma conversa.

Reações: Reaja às mensagens com emojis para se expressar melhor.

🛠️ Tecnologias Utilizadas
Para dar vida a este projeto, combinamos duas tecnologias principais:

Flutter (Front-end): É o framework que usamos para construir a interface do aplicativo, ou seja, tudo o que você vê e com o que interage na tela. A grande vantagem do Flutter é que, com um único código, o app funciona tanto em Android quanto em iOS.

Supabase (Back-end): É o "cérebro" por trás do aplicativo. Ele cuida de toda a parte complexa nos bastidores e nos oferece um conjunto de ferramentas prontas para usar:

Autenticação: Gerencia o login e o cadastro dos usuários, garantindo que tudo seja seguro.

Banco de Dados (Postgres): É onde todas as informações, como perfis, mensagens e conversas, ficam guardadas de forma organizada.

Realtime: A "mágica" que faz as mensagens aparecerem instantaneamente na tela, sem que você precise atualizá-la.

Storage: Um espaço para guardar as imagens e os arquivos que os usuários enviam.

⚙️ Como Tudo se Conecta (Arquitetura Simplificada)
O Usuário e o App (Flutter): O usuário abre o aplicativo no celular. Todas as telas, botões e campos de texto foram criados com Flutter.

A Ponte para a Nuvem (Supabase): Quando o usuário faz login, envia uma mensagem ou troca a foto de perfil, o Flutter se comunica com o Supabase.

O Trabalho do Supabase:

A Autenticação verifica se o usuário e a senha estão corretos.

O Banco de Dados salva a nova mensagem na conversa certa.

O Realtime percebe que uma nova mensagem foi salva e avisa imediatamente todos os outros participantes da conversa.

Se a mensagem tiver uma foto, ela é enviada para o Storage.

A Resposta (De Volta para o App): O aplicativo, que está "ouvindo" as novidades do Realtime, recebe a nova mensagem e a exibe na tela para todos os envolvidos. Isso acontece em menos de 2 segundos!

🔒 Segurança em Primeiro Lugar
A privacidade dos dados é fundamental. Utilizamos um recurso do Supabase chamado Row Level Security (RLS). Isso funciona como uma regra de segurança superinteligente que garante que um usuário só pode ver e acessar as suas próprias conversas e informações. Ninguém consegue espiar as mensagens de outra pessoa.

🚀 Desafios e Aprendizados
Este projeto não é apenas sobre programar, mas também sobre resolver desafios do mundo real:

Manter a velocidade: Garantir que as mensagens cheguem rápido, otimizando as consultas ao banco de dados.

Funcionar offline: Fazer o app funcionar mesmo se a conexão com a internet cair por um instante e sincronizar tudo quando ela voltar.

Uso consciente de recursos: Limitar o tamanho dos arquivos para não sobrecarregar o armazenamento.

É um projeto completo que nos permite praticar desde a criação da interface até a configuração de um back-end moderno e seguro na nuvem.
