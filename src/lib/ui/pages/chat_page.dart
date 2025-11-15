// lib/ui/pages/chat_page.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import '../../main.dart'; // Para acessar a instância global do Supabase
import '../../services/chat_service.dart';
import 'search_page.dart';
import 'profile_page.dart'; // Importar a página de perfil
import 'conversations_page.dart';

class ChatPage extends StatefulWidget {
  final String? conversationId;
  const ChatPage({super.key, this.conversationId});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController messageController = TextEditingController();
  final ScrollController scrollController = ScrollController();
  final ChatService _chatService = ChatService();

  // Presença / typing
  late RealtimeChannel _presenceChannel;
  Set<String> _onlineUsers = {};
  Set<String> _typingUsers = {};
  Timer? _typingTimer;
  bool _isStatusHidden = false;
  final Map<String, String> _userNames = {};

  // Valor padrão (exemplo). Recomendo passar `conversationId` via navegação.
  static const String _kDefaultConversationId =
      'd0363f19-e924-448a-8a6f-b35c6e488668';

  @override
  void dispose() {
    _removePresenceSubscription();
    // cancelar assinaturas de reações
    _cancelAllReactionSubscriptions();
    messageController.dispose();
    scrollController.dispose();
    super.dispose();
  }

  // --- Função Auxiliar de SnackBar para Feedback nesta tela ---
  void _showSnackBar(
    BuildContext context,
    String message, {
    bool isError = false,
  }) {
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
      final convId = widget.conversationId ?? _kDefaultConversationId;
      await supabase.from('messages').insert({
        'sender_id': currentUser.id,
        'content_text': text,
        'conversation_id': convId,
      });

      // Depois de enviar, informe que não está mais digitando
      _trackUserStatus(typing: false);

      messageController.clear();
      _scrollToBottom();
    } catch (e) {
      debugPrint('❌ FALHA NO ENVIO. ERRO: $e');
      if (mounted) {
        _showSnackBar(
          context,
          'Falha ao enviar mensagem. Verifique a tabela messages.',
          isError: true,
        );
      }
    }
  }

  Future<void> _pickAndUploadAttachment() async {
    try {
      final result = await FilePicker.platform.pickFiles(withData: true);
      if (result == null || result.files.isEmpty) return;

      final f = result.files.first;
      final size = f.size; // bytes
      const maxBytes = 20 * 1024 * 1024; // 20MB
      if (size > maxBytes) {
        if (mounted) {
          _showSnackBar(context, 'Arquivo maior que 20MB.', isError: true);
        }
        return;
      }

      final bytes = f.bytes;
      if (bytes == null) {
        if (mounted) {
          _showSnackBar(
            context,
            'Não foi possível ler o arquivo.',
            isError: true,
          );
        }
        return;
      }

      final filename = f.name;
      final url = await _chatService.uploadAttachment(bytes, filename);

      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) return;

      final convId = widget.conversationId ?? _kDefaultConversationId;
      await supabase.from('messages').insert({
        'sender_id': currentUser.id,
        'content_text': '',
        'conversation_id': convId,
        'attachment_url': url,
        'created_at': DateTime.now().toIso8601String(),
      });

      if (mounted) {
        _showSnackBar(context, 'Arquivo enviado com sucesso.');
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint('pickAndUploadAttachment error: $e');
      if (mounted) {
        _showSnackBar(context, 'Falha ao enviar anexo: $e', isError: true);
      }
    }
  }

  // ================= PRESENCE / TYPING HELPERS =================
  void _setupPresenceSubscription() {
    _presenceChannel = supabase.channel(kPresenceChannelName);
    final presence = _presenceChannel.presence;

    presence.onSync(() {
      final raw = (presence.state as dynamic);
      final online = <String>{};
      final typing = <String>{};

      try {
        if (raw is Map) {
          raw.forEach((key, value) {
            final userId = key.toString();
            final presList = (value is List) ? value : [value];
            for (final p in presList) {
              bool hidden = false;
              String? status;
              if (p is Map) {
                hidden = (p['hide_status'] as bool?) ?? false;
                status = p['status']?.toString();
              } else {
                status = p.toString();
              }

              if (!hidden) online.add(userId);
              if (status == 'typing') typing.add(userId);
              _loadUserName(userId);
            }
          });
        }
      } catch (e) {
        debugPrint('presence.onSync parse error: $e');
      }

      if (mounted) {
        setState(() {
          _onlineUsers = online;
          _typingUsers = typing;
        });
      }
    });

    _presenceChannel.subscribe((status, [error]) {
      if (status == RealtimeSubscribeStatus.subscribed) {
        _trackUserStatus(typing: false);
      }
    });
  }

  Future<void> _removePresenceSubscription() async {
    try {
      await (_presenceChannel.presence as dynamic).untrack();
    } catch (e) {
      debugPrint('untrack error: $e');
    }
    try {
      await supabase.removeChannel(_presenceChannel);
    } catch (e) {
      debugPrint('remove channel error: $e');
    }
  }

  Future<void> _trackUserStatus({required bool typing}) async {
    final currentUser = supabase.auth.currentUser;
    if (currentUser == null) return;

    try {
      if (_isStatusHidden) {
        await (_presenceChannel.presence as dynamic).untrack();
        return;
      }

      await (_presenceChannel.presence as dynamic).track({
        'user_id': currentUser.id,
        'status': typing ? 'typing' : 'online',
        'hide_status': _isStatusHidden,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('trackUserStatus error: $e');
    }
  }

  void _onMessageChanged(String v) {
    _typingTimer?.cancel();
    _trackUserStatus(typing: true);
    _typingTimer = Timer(kTypingDelay, () {
      _trackUserStatus(typing: false);
    });
  }

  Future<void> _loadUserName(String userId) async {
    if (_userNames.containsKey(userId)) return;
    try {
      final res = await supabase
          .from('profiles')
          .select('id, username, full_name')
          .eq('id', userId)
          .maybeSingle();
      if (res != null) {
        final name = (res['full_name'] ?? res['username'] ?? '').toString();
        _userNames[userId] = name.isNotEmpty ? name : userId;
        if (mounted) setState(() {});
      }
    } catch (e) {
      debugPrint('loadUserName error: $e');
    }
  }

  // Reactions cache
  final Map<String, Map<String, int>> _messageReactions = {};
  final Map<String, StreamSubscription> _reactionSubs = {};

  Future<void> _fetchReactions(String messageId) async {
    if (_messageReactions.containsKey(messageId)) return;
    try {
      final aggregated = await _chatService.getReactionsAggregated(messageId);
      _messageReactions[messageId] = aggregated;
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('getReactionsAggregated error: $e');
    }
  }

  void _ensureReactionSubscription(String messageId) {
    if (messageId.isEmpty) return;
    if (_reactionSubs.containsKey(messageId)) return;

    final sub = _chatService.streamReactions(messageId).listen((list) {
      final Map<String, int> agg = {};
      for (final row in list) {
        final r = (row['reaction'] ?? '').toString();
        if (r.isEmpty) continue;
        agg[r] = (agg[r] ?? 0) + 1;
      }
      _messageReactions[messageId] = agg;
      if (mounted) setState(() {});
    }, onError: (e) => debugPrint('reaction stream error: $e'));

    _reactionSubs[messageId] = sub;
  }

  Future<void> _cancelAllReactionSubscriptions() async {
    for (final s in _reactionSubs.values) {
      try {
        await s.cancel();
      } catch (_) {}
    }
    _reactionSubs.clear();
  }

  Future<void> _onReact(String messageId, String reaction) async {
    final currentUser = supabase.auth.currentUser;
    if (currentUser == null) return;

    try {
      await _chatService.addReaction(
        messageId: messageId,
        userId: currentUser.id,
        reaction: reaction,
      );
      // Atualiza cache local
      _messageReactions.remove(messageId);
      await _fetchReactions(messageId);
    } catch (e) {
      if (mounted) {
        _showSnackBar(context, 'Falha ao reagir: $e', isError: true);
      } else {
        debugPrint('reaction error: $e');
      }
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
        actions: [
          IconButton(
            tooltip: 'Buscar',
            icon: const Icon(Icons.search, color: Colors.white),
            onPressed: () async {
              await Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const SearchPage()));
            },
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: Text('${_onlineUsers.length} online')),
          ),
        ],
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
                  MaterialPageRoute(builder: (context) => const ProfilePage()),
                );
              },
            ),
            SwitchListTile(
              title: const Text('Ocultar meu status'),
              value: _isStatusHidden,
              onChanged: (v) async {
                await _persistHideStatus(v);
              },
              secondary: const Icon(Icons.visibility_off),
            ),
            ListTile(
              leading: const Icon(Icons.chat),
              title: const Text('Conversas'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ConversationsPage()),
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
                  // Filtra apenas mensagens desta conversa (usa param ou fallback)
                  .eq(
                    'conversation_id',
                    widget.conversationId ?? _kDefaultConversationId,
                  )
                  .order('created_at', ascending: true)
                  .limit(500)
                  .asStream(),
              builder: (_, snapshot) {
                if (snapshot.hasError) {
                  // Exibe erro do Supabase (ex: RLS, coluna faltando)
                  debugPrint('Stream Error: ${snapshot.error}');
                  return Center(
                    child: Text(
                      'Erro de carregamento: ${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  ); // Indicador de carregamento
                }

                final messages = snapshot.data!;

                // ⚠️ Se 'messages.isEmpty' mas há mensagens no DB, o problema é RLS ou CONVERSATION_ID.
                if (messages.isEmpty) {
                  return const Center(
                    child: Text(
                      "Nenhuma mensagem nesta conversa. Comece a digitar!",
                    ),
                  );
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
                    final userName =
                        msg['profiles']?['full_name'] ?? 'Usuário Desconhecido';
                    final mine = msg['sender_id'] == currentUser?.id;
                    final initials = userName.isNotEmpty
                        ? userName.substring(0, 1).toUpperCase()
                        : '?';

                    final time = DateFormat(
                      'HH:mm',
                    ).format(DateTime.parse(msg['created_at']));

                    // Carrega reações para esta mensagem (assíncrono/cache) e garante subscription em tempo real
                    final msgId = msg['id']?.toString() ?? '';
                    _fetchReactions(msgId);
                    _ensureReactionSubscription(msgId);

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
                                  child: GestureDetector(
                                    onLongPress: () {
                                      showModalBottomSheet(
                                        context: context,
                                        builder: (_) => MessageReactions(
                                          onReact: (r) {
                                            Navigator.pop(context);
                                            _onReact(msgId, r);
                                          },
                                        ),
                                      );
                                    },
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
                                ),
                                // Reactions row
                                if (_messageReactions.containsKey(msgId) &&
                                    _messageReactions[msgId]!.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: _messageReactions[msgId]!
                                          .entries
                                          .map((e) {
                                            return Container(
                                              margin: const EdgeInsets.only(
                                                right: 6,
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.grey.shade200,
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Row(
                                                children: [
                                                  Text(
                                                    e.key,
                                                    style: const TextStyle(
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    e.value.toString(),
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.black54,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          })
                                          .toList(),
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
                          // indicador online: um ponto verde ao lado do avatar
                          if (!mine)
                            Padding(
                              padding: const EdgeInsets.only(left: 8.0),
                              child: _onlineUsers.contains(msg['sender_id'])
                                  ? const Icon(
                                      Icons.circle,
                                      color: Colors.green,
                                      size: 10,
                                    )
                                  : const SizedBox(width: 10, height: 10),
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
                    onChanged: _onMessageChanged,
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
                const SizedBox(width: 8),
                // Botão para anexos
                GestureDetector(
                  onTap: _pickAndUploadAttachment,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.attach_file,
                      color: Colors.black54,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
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
          // Indicador 'digitando...'
          if (_typingUsers.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${_userNames[_typingUsers.first] ?? 'Alguém'} está digitando...'
                      .replaceAll('null', 'Alguém'),
                  style: const TextStyle(
                    color: Colors.black54,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _setupPresenceSubscription();
    _loadHideStatus();
  }

  Future<void> _loadHideStatus() async {
    final currentUser = supabase.auth.currentUser;
    if (currentUser == null) return;
    try {
      final res = await supabase
          .from('profiles')
          .select('hide_status')
          .eq('id', currentUser.id)
          .maybeSingle();
      if (res != null && res.containsKey('hide_status')) {
        final v = (res['hide_status'] as bool?) ?? false;
        setState(() {
          _isStatusHidden = v;
        });
      }
    } catch (_) {}
  }

  Future<void> _persistHideStatus(bool v) async {
    final currentUser = supabase.auth.currentUser;
    if (currentUser == null) return;
    try {
      await supabase
          .from('profiles')
          .update({'hide_status': v})
          .eq('id', currentUser.id);
      setState(() => _isStatusHidden = v);
      // Atualiza presença imediatamente
      await _trackUserStatus(typing: false);
    } catch (e) {
      if (mounted) {
        _showSnackBar(context, 'Erro ao salvar preferência: $e', isError: true);
      } else {
        debugPrint('persistHideStatus error: $e');
      }
    }
  }
}
