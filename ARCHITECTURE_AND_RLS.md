# ARCHITECTURE_AND_RLS.md

### Arquitetura do Chat App (Flutter + Supabase) e Regras RLS

## 1. Arquitetura

### Frontend (Flutter)

-   UI
-   Navegação
-   Realtime (mensagens, presença, digitando)

### Backend (Supabase)

-   Auth
-   PostgreSQL
-   Realtime
-   Storage

## 2. RLS

### Políticas principais

**conversas** - INSERT (authenticated) - SELECT (authenticated)

**participantes** - INSERT, DELETE, SELECT (authenticated)

**mensagens** - INSERT, SELECT, UPDATE, DELETE (authenticated ---
somente mensagens próprias)

**perfis** - INSERT, UPDATE, SELECT (public + authenticated)
