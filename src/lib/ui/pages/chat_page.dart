// No arquivo src/lib/ui/pages/chat_page.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
// Certifique-se de que o import da intl está correto no seu arquivo:
// import 'package:intl/intl.dart';

final supabase = Supabase.instance.client;

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController messageController = TextEditingController();
  final ScrollController scrollController = ScrollController();

  // ⚠️ ATENÇÃO: SUBSTITUA ESTE VALOR pelo UUID de uma conversa EXISTENTE no seu Supabase.
  static const String CONVERSATION_ID = 'd0363f19-e924-448a-8a6f-b35c6e488668';

  // Removido get msg => null; que estava incorreto.

  @override
  void dispose() {
    messageController.dispose();
    scrollController.dispose();
    super.dispose();
  }

  // =======================================================================
  // FUNÇÃO DE ENVIO CORRIGIDA: Inclui sender_id, content_text e conversation_id
  // =======================================================================
  Future<void> _sendMessage() async {
    final text = messageController.text.trim();
    if (text.isEmpty) return;

    final currentUser = supabase.auth.currentUser;
    if (currentUser == null) return;

    try {
      await supabase.from('messages').insert({
        'sender_id': currentUser.id, // Coluna correta para o remetente
        'content_text': text, // Coluna correta para o texto
        'conversation_id': CONVERSATION_ID, // CRÍTICO: ID da conversa para RLS
      });

      messageController.clear();
      _scrollToBottom();
    } catch (e) {
      print('❌ FALHA NO ENVIO. ERRO FINAL: $e');
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
  // MÉTODO BUILD CORRIGIDO: Usa JOIN para perfis e FILTRO por conversation_id
  // =======================================================================
  @override
  Widget build(BuildContext context) {
    final currentUser = supabase.auth.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFF),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text("Chat", style: TextStyle(color: Colors.black)),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: supabase
                  .from('messages')
                  .select(
                    // SELECT: Colunas corretas do seu esquema (content_text e sender_id)
                    'id, content_text, created_at, sender_id, profiles!inner(full_name)',
                  )
                  // FILTRO CRÍTICO: Filtra apenas mensagens desta conversa
                  .eq('conversation_id', CONVERSATION_ID)
                  // CORREÇÃO CRÍTICA: Ordena os resultados corretamente
                  .order('created_at', ascending: true)
                  .limit(500)
                  .asStream(),
              builder: (_, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(
                    child: Text("Iniciando chat..."),
                  ); // Mensagem de carregamento
                }
                final messages = snapshot.data!;

                return ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 12,
                  ),
                  itemCount: messages.length,
                  itemBuilder: (_, i) {
                    final msg = messages[i];

                    // Lógica para obter o nome do perfil (via JOIN)
                    final userName = msg['profiles']?['full_name'] ?? 'Usuário';

                    final mine = msg['sender_id'] == currentUser?.id;

                    final initials = userName.isNotEmpty
                        ? userName.substring(0, 1).toUpperCase()
                        : '?';

                    // NOTE: Assumindo que DateFormat está corretamente importado
                    final time = DateFormat(
                      'HH:mm',
                    ).format(DateTime.parse(msg['created_at']));

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

extension on SupabaseStreamBuilder {
  select(String s) {}
}
