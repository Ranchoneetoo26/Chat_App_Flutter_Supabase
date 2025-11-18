# SUPABASE_CONFIGURATION.md

### Configuração Final do Banco de Dados Supabase

Este documento detalha o esquema final do banco de dados PostgreSQL e as
configurações de Storage necessárias para o funcionamento da aplicação
de Chat em Tempo Real (Flutter + Supabase).

## 1. Configurações de Conexão

---

Configuração Valor (Genérico/Padrão) Observação

---

URL do Projeto https://ihsluigtpkgasyknldsa.supabase.co Configurar em
`src/lib/utils/constants.dart` e
`src/lib/main.dart`.

Anon Key (Chave eyJhbGciOiJIUzI1NiI...lwhHz8 Configurar nos mesmos
Pública) arquivos.

Autenticação Ativada (e-mail/senha) Utiliza o módulo Auth nativo
do Supabase.

Realtime Ativado Para tabelas: mensagens,
participantes,
reações_da_mensagem. Canal
de Presença:
**online_users**.

---

## 2. Esquema das Tabelas (PostgreSQL)

RLS ativo em todas as tabelas.

### 2.1. Tabela perfis

(id, nome_de_usuario, nome_completo, avatar_url, status_online,
atualizado_em, email, criado_em)

### 2.2. Tabela conversas

(id, nome_do_grupo, é_grupo, é_público, criado_por, criado_em,
atualizado_em, URL_do_avatar_do_grupo)

### 2.3. Tabela participantes

(id, id_da_conversa, id_do_usuario, entrou_em)

### 2.4. Tabela mensagens

(id, id_da_conversa, id_do_remetente, texto_conteúdo, url_da_mídia,
tipo_de_mídia, criado_em, atualizado_em, é_lido)

### 2.5. Tabela reações_da_mensagem

(id, id_da_mensagem, id_do_usuario, reação, criado_em)

## 3. Storage

- profile_pictures → avatares\
- attachments → anexos (limite 20MB)
