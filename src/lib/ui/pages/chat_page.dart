// lib/ui/pages/chat_page.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../../main.dart'; // Para acessar a instância global do Supabase
import 'profile_page.dart'; // Importar a página de perfil

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController messageController = TextEditingController();
  final ScrollController scrollController = ScrollController();

  // ⚠️ CRÍTICO: SUBSTITUA PELO ID REAL de uma conversa que o usuário logado participa.
  // Se esta conversa não existe ou o RLS a bloqueia, NENHUMA mensagem será exibida/enviada.
  static const String CONVERSATION_ID = 'd0363f19-e924-448a-8a6f-b35c6e488668';

  @override
  void dispose() {
    messageController.dispose();
    scrollController.dispose();
    super.dispose();
  }

  // --- Função Auxiliar de SnackBar para Feedback nesta tela ---
  void _showSnackBar(BuildContext context, String message, {bool isError = false}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red : Colors.green,
        ),
      );
    }
  }

  // =======================================================================
  // FUNÇÃO DE ENVIO DE MENSAGEM
  // =======================================================================
  Future<void> _sendMessage() async {
    final text = messageController.text.trim();
    if (text.isEmpty) return;

    final currentUser = supabase.auth.currentUser;
    if (currentUser == null) return;

    try {
      await supabase.from('messages').insert({
        'sender_id': currentUser.id,
        'content_text': text,
        'conversation_id': CONVERSATION_ID, 
      });

      messageController.clear();
      _scrollToBottom();
    } catch (e) {
      print('❌ FALHA NO ENVIO. ERRO: $e');
      _showSnackBar(context, 'Falha ao enviar mensagem. Verifique a tabela messages.', isError: true);
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!scrollController.hasClients) return;
      scrollController.animateTo(
        scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  // =======================================================================
  // MÉTODO BUILD: Inclui StreamBuilder e Drawer para navegação
  // =======================================================================
  @override
  Widget build(BuildContext context) {
    final currentUser = supabase.auth.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFF),
      appBar: AppBar(
        title: const Text("Chat", style: TextStyle(color: Colors.black)),
        // Adiciona o ícone de menu (hambúrguer)
      ),
      
      // 1. ADICIONANDO DRAWER (MENU LATERAL) PARA PERFIL E LOGOUT
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: <Widget>[
            const DrawerHeader(
              decoration: BoxDecoration(color: Colors.blue),
              child: Text(
                'Menu',
                style: TextStyle(color: Colors.white, fontSize: 24),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.person),
              title: const Text('Meu Perfil'),
              onTap: () {
                Navigator.pop(context); // Fecha o Drawer
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const ProfilePage(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Sair'),
              onTap: () async {
                Navigator.pop(context); // Fecha o Drawer
                await supabase.auth.signOut();
                // O main.dart cuida do redirecionamento
              },
            ),
          ],
        ),
      ),

      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: supabase
                  .from('messages')
                  .select(
                    'id, content_text, created_at, sender_id, profiles!inner(full_name)',
                  )
                  // CRÍTICO: Filtra apenas mensagens desta conversa
                  .eq('conversation_id', CONVERSATION_ID)
                  .order('created_at', ascending: true)
                  .limit(500)
                  .asStream(),
              builder: (_, snapshot) {
                if (snapshot.hasError) {
                   // Exibe erro do Supabase (ex: RLS, coluna faltando)
                   print('Stream Error: ${snapshot.error}');
                   return Center(child: Text('Erro de carregamento: ${snapshot.error}', textAlign: TextAlign.center));
                }
                
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator()); // Indicador de carregamento
                }
                
                final messages = snapshot.data!;
                
                // ⚠️ Se 'messages.isEmpty' mas há mensagens no DB, o problema é RLS ou CONVERSATION_ID.
                if (messages.isEmpty) {
                   return const Center(child: Text("Nenhuma mensagem nesta conversa. Comece a digitar!"));
                }

                return ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 12,
                  ),
                  itemCount: messages.length,
                  itemBuilder: (_, i) {
                    final msg = messages[i];
                    final userName = msg['profiles']?['full_name'] ?? 'Usuário Desconhecido';
                    final mine = msg['sender_id'] == currentUser?.id;
                    final initials = userName.isNotEmpty
                        ? userName.substring(0, 1).toUpperCase()
                        : '?';
                    
                    final time = DateFormat('HH:mm').format(DateTime.parse(msg['created_at']));

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: mine
                            ? MainAxisAlignment.end
                            : MainAxisAlignment.start,
                        children: [
                          if (!mine)
                            CircleAvatar(
                              backgroundColor: Colors.blueAccent,
                              child: Text(
                                initials,
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Column(
                              crossAxisAlignment: mine
                                  ? CrossAxisAlignment.end
                                  : CrossAxisAlignment.start,
                              children: [
                                Text(
                                  mine ? "Você" : userName,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                ),
                                Container(
                                  margin: const EdgeInsets.only(top: 2),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: mine
                                        ? Colors.blue
                                        : Colors.grey.shade300,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Text(
                                    msg['content_text'],
                                    style: TextStyle(
                                      color: mine
                                          ? Colors.white
                                          : Colors.black87,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    time,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (mine) const SizedBox(width: 8),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // CAMPO DE INPUT DE MENSAGEM
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: messageController,
                    decoration: InputDecoration(
                      hintText: "Digite uma mensagem...",
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(color: Colors.grey.shade400),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: const BorderSide(
                          color: Colors.blue,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _sendMessage,
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: const BoxDecoration(
                      color: Colors.blue,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.send, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}