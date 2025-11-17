import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';

// Imports Corrigidos
import '../../main.dart';
import '../../services/chat_service.dart';
import 'search_page.dart';
import 'profile_page.dart';
import 'conversations_page.dart';
// Importa o widget de reações (necessário para o pop-up)
import '../widgets/message_reactions.dart'; 

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
  // bool _isStatusHidden = false; // REMOVIDO
  final Map<String, String> _userNames = {};
  bool _isSending = false;
  String? _editingMessageId;

  // static const String _kDefaultConversationId = ... // REMOVIDO

  @override
  void initState() {
    super.initState();
    _setupPresenceSubscription();
    // _loadHideStatus(); // REMOVIDO
  }

  @override
  void dispose() {
    _removePresenceSubscription();
    _cancelAllReactionSubscriptions();
    messageController.dispose();
    scrollController.dispose();
    super.dispose();
  }

  // --- Função Auxiliar de SnackBar ---
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

    // CORREÇÃO: Usa o ID obrigatório
    final convId = widget.conversationId!;

    // Editando
    if (_editingMessageId != null) {
      final editId = _editingMessageId!;
      try {
        await _chatService.updateMessage(messageId: editId, newText: text);
        if (mounted) _showSnackBar(context, 'Mensagem editada.');
      } catch (e) {
        debugPrint('update message error: $e');
        if (mounted)
          _showSnackBar(context, 'Falha ao editar: $e', isError: true);
      } finally {
        _editingMessageId = null;
        messageController.clear();
      }
      return;
    }

    // Enviando nova
    _isSending = true;
    if (mounted) setState(() {});

    try {
      await _chatService
          .sendMessage(convId, currentUser.id, text)
          .timeout(const Duration(seconds: 2));

      if (mounted) _showSnackBar(context, 'Enviado');
    } on TimeoutException {
      if (mounted) _showSnackBar(context, 'Envio pendente...');
      _chatService.sendMessage(convId, currentUser.id, text).catchError((e) {
        debugPrint('background send error: $e');
        if (mounted)
          _showSnackBar(context, 'Falha no envio: $e', isError: true);
      });
    } catch (e) {
      debugPrint('❌ FALHA NO ENVIO. ERRO: $e');
      if (mounted) {
        _showSnackBar(context, 'Falha ao enviar mensagem: $e', isError: true);
      }
    } finally {
      _isSending = false;
      if (mounted) setState(() {});
      messageController.clear();
      _trackUserStatus(typing: false);
      _scrollToBottom();
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

      // CORREÇÃO: Usa o ID obrigatório
      final convId = widget.conversationId!;
      // ##### CORREÇÃO: Usando 'media_url' e 'media_type' (do seu banco) #####
      await supabase.from('messages').insert({
        'sender_id': currentUser.id,
        'content_text': '',
        'conversation_id': convId,
        'media_url': url, // 
        'media_type': f.extension ?? 'file', // 
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
              // bool hidden = false; // REMOVIDO
              String? status;
              if (p is Map) {
                // hidden = (p['hide_status'] as bool?) ?? false; // REMOVIDO
                status = p['status']?.toString();
              } else {
                status = p.toString();
              }

              online.add(userId); // CORRIGIDO (removido 'if !hidden')
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
      // ##### CORREÇÃO: Chamada no canal, não no presence #####
      await _presenceChannel.untrack(); // 
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
      // if (_isStatusHidden) { // REMOVIDO
      //   await _presenceChannel.untrack();
      //   return; 
      // } 

      // ##### CORREÇÃO: Chamada no canal e remoção de 'hide_status' #####
      await _presenceChannel.track({ // 
        'user_id': currentUser.id,
        'status': typing ? 'typing' : 'online',
        // 'hide_status': _isStatusHidden, // REMOVIDO
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('trackUserStatus error: $e');
    }
  }

  void _onMessageChanged(String v) {
    _typingTimer?.cancel();
    _trackUserStatus(typing: true);
    // ##### CORREÇÃO: kTypDelay -> kTypingDelay #####
    _typingTimer = Timer(kTypingDelay, () { 
      _trackUserStatus(typing: false);
    });
  }

  Future<void> _loadUserName(String userId) async {
    if (_userNames.containsKey(userId)) return;
    try {
      final res = await supabase
          .from('profiles')
          .select('id, username, full_name, email') // CORREÇÃO: Adicionado email
          .eq('id', userId)
          .maybeSingle();
      if (res != null) {
        // CORREÇÃO: Adicionado email como fallback
        final name = (res['full_name'] ?? res['username'] ?? res['email'] ?? '').toString(); 
        _userNames[userId] = name.isNotEmpty ? name : userId;
        if (mounted) setState(() {});
      }
    } catch (e) {
      debugPrint('loadUserName error: $e');
    }
  }

  Future<void> _startEditing(
    String messageId,
    String currentText,
    String? createdAtStr,
  ) async {
    try {
      if (createdAtStr != null) {
        final created = DateTime.tryParse(createdAtStr);
        if (created != null) {
          final diff = DateTime.now().difference(created);
          if (diff > const Duration(minutes: 15)) {
            if (mounted)
              _showSnackBar(
                context,
                'Tempo de edição expirado.',
                isError: true,
              );
            return;
          }
        }
      }

      _editingMessageId = messageId;
      messageController.text = currentText;
      if (mounted) {
        setState(() {});
        FocusScope.of(context).requestFocus(FocusNode());
        _showSnackBar(
          context,
          'Modo edição ativado. Faça suas alterações e envie.',
        );
      }
    } catch (e) {
      debugPrint('startEditing error: $e');
    }
  }

  Future<void> _deleteMessage(String messageId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar'),
        content: const Text('Deseja apagar esta mensagem?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await _chatService.deleteMessage(messageId: messageId);
      if (mounted) {
        _showSnackBar(context, 'Mensagem apagada.');
      }
    } catch (e) {
      debugPrint('delete message error: $e');
      if (mounted) _showSnackBar(context, 'Falha ao apagar: $e', isError: true);
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

    // ##### CORREÇÃO: Sintaxe do .stream() #####
    final sub = supabase
        .from('message_reactions') // 1. Tabela
        .stream(primaryKey: ['id']) // 2. Stream
        .eq('message_id', messageId) // 3. Filtro
        .listen((list) { // 4. Listen
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
      ),

      // 1. ADICIONANDO DRAWER (MENU LATERAL)
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
            // ##### REMOVIDO SwitchListTile para 'hide_status' #####
            ListTile(
              leading: const Icon(Icons.chat),
              title: const Text('Conversas'),
              onTap: () {
                Navigator.pop(context);
                // Evita empilhar a mesma tela
                Navigator.of(context).pushReplacement(
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
              
              // ########## INÍCIO DA CORREÇÃO (ORDEM DO STREAM) ##########
              // A sintaxe correta para stream COM join é diferente
              stream: supabase
                  .from('messages')
                  .stream(primaryKey: ['id'])
                  .eq(
                    'conversation_id',
                    widget.conversationId!,
                  )
                  .order('created_at', ascending: true)
                  .map((data) => List<Map<String, dynamic>>.from(data as List)),
              // ########## FIM DA CORREÇÃO ##########

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
                _scrollToBottom(); // Rola para o fim

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
                    
                    // CORREÇÃO: Pega o nome do cache _userNames
                    // A função _loadUserName é chamada no onSync da presença
                    final userName =
                        _userNames[msg['sender_id']] ?? 'Usuário...';
                    
                    final mine = msg['sender_id'] == currentUser?.id;
                    final initials = userName.isNotEmpty
                        ? userName.substring(0, 1).toUpperCase()
                        : '?';

                    final time = DateFormat(
                      'HH:mm',
                    ).format(DateTime.parse(msg['created_at']));

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
                                    onLongPress: () async {
                                      if (mine) {
                                        showModalBottomSheet(
                                          context: context,
                                          builder: (ctx) {
                                            final createdAt = msg['created_at']
                                                ?.toString();
                                            return SafeArea(
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  ListTile(
                                                    leading: const Icon(
                                                      Icons.emoji_emotions,
                                                    ),
                                                    title: const Text('Reagir'),
                                                    onTap: () {
                                                      Navigator.pop(ctx);
                                                      showModalBottomSheet(
                                                        context: context,
                                                        builder: (_) =>
                                                            MessageReactions(
                                                              onReact: (r) {
                                                                Navigator.pop(
                                                                  context,
                                                                );
                                                                _onReact(
                                                                  msgId,
                                                                  r,
                                                                );
                                                              },
                                                            ),
                                                      );
                                                    },
                                                  ),
                                                  ListTile(
                                                    leading: const Icon(
                                                      Icons.edit,
                                                    ),
                                                    title: const Text('Editar'),
                                                    onTap: () {
                                                      Navigator.pop(ctx);
                                                      _startEditing(
                                                        msgId,
                                                        msg['content_text'] ??
                                                            '',
                                                        createdAt,
                                                      );
                                                    },
                                                  ),
                                                  ListTile(
                                                    leading: const Icon(
                                                      Icons.delete,
                                                    ),
                                                    title: const Text('Apagar'),
                                                    onTap: () async {
                                                      Navigator.pop(ctx);
                                                      await _deleteMessage(
                                                        msgId,
                                                      );
                                                    },
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                        );
                                      } else {
                                        showModalBottomSheet(
                                          context: context,
                                          builder: (_) => MessageReactions(
                                            onReact: (r) {
                                              Navigator.pop(context);
                                              _onReact(msgId, r);
                                            },
                                          ),
                                        );
                                      }
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
                  onTap: _isSending ? null : _sendMessage,
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: const BoxDecoration(
                      color: Colors.blue,
                      shape: BoxShape.circle,
                    ),
                    child: _isSending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send, color: Colors.white),
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
  
  // ##### FUNÇÕES DE 'hide_status' REMOVIDAS #####
}