import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';

// --- SEUS IMPORTS ---
import '../../main.dart';
import '../../services/chat_service.dart';
import 'search_page.dart';
import '../widgets/custom_drawer.dart';
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
  final supabase = Supabase.instance.client;

  // Presença / typing
  late RealtimeChannel _presenceChannel;
  Set<String> _onlineUsers = {};
  Set<String> _typingUsers = {};
  Timer? _typingTimer;

  // Cache de dados de usuário
  final Map<String, String> _avatarUrls = {};
  final Map<String, String> _userNames = {};

  bool _isSending = false;
  String? _editingMessageId;

  // Cache de reações
  final Map<String, Map<String, int>> _messageReactions = {};
  final Map<String, StreamSubscription> _reactionSubs = {};

  @override
  void initState() {
    super.initState();
    _setupPresenceSubscription();
    _markMessagesAsRead(); // Marca mensagens como lidas ao entrar
  }

  @override
  void dispose() {
    _removePresenceSubscription();
    _cancelAllReactionSubscriptions();
    messageController.dispose();
    scrollController.dispose();
    super.dispose();
  }

  // --- FUNÇÃO: MARCAR COMO LIDO ---
  Future<void> _markMessagesAsRead() async {
    final currentUser = supabase.auth.currentUser;
    if (currentUser == null || widget.conversationId == null) return;

    try {
      // Atualiza todas as mensagens que NÃO são minhas para is_read = true
      await supabase
          .from('messages')
          .update({'is_read': true})
          .eq('conversation_id', widget.conversationId!)
          .neq('sender_id', currentUser.id)
          .eq('is_read', false);
    } catch (e) {
      debugPrint('Erro ao marcar lido: $e');
    }
  }

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

  // --- ENVIO DE MENSAGEM DE TEXTO ---
  Future<void> _sendMessage() async {
    final text = messageController.text.trim();
    if (text.isEmpty) return;

    final currentUser = supabase.auth.currentUser;
    if (currentUser == null) return;
    final convId = widget.conversationId!;

    // Lógica de Edição
    if (_editingMessageId != null) {
      final editId = _editingMessageId!;
      try {
        await _chatService.updateMessage(messageId: editId, newText: text);
        if (mounted) _showSnackBar(context, 'Mensagem editada.');
      } catch (e) {
        if (mounted) _showSnackBar(context, 'Falha ao editar.', isError: true);
      } finally {
        setState(() {
          _editingMessageId = null;
          messageController.clear();
        });
      }
      return;
    }

    // Envio Normal
    setState(() => _isSending = true);

    try {
      await _chatService
          .sendMessage(convId, currentUser.id, text)
          .timeout(const Duration(seconds: 2));
    } on TimeoutException {
      // Envio em background se demorar
      _chatService.sendMessage(convId, currentUser.id, text);
    } catch (e) {
      if (mounted) _showSnackBar(context, 'Erro no envio.', isError: true);
    } finally {
      if (mounted) setState(() => _isSending = false);
      messageController.clear();
      _trackUserStatus(typing: false);
      _scrollToBottom();
    }
  }

  // --- UPLOAD DE ARQUIVO ---
  Future<void> _pickAndUploadAttachment() async {
    try {
      final result = await FilePicker.platform.pickFiles(withData: true);
      if (result == null || result.files.isEmpty) return;

      final f = result.files.first;
      if (f.size > 20 * 1024 * 1024) {
        // 20MB limit
        if (mounted) _showSnackBar(context, 'Arquivo > 20MB.', isError: true);
        return;
      }

      final bytes = f.bytes;
      if (bytes == null) return;

      final url = await _chatService.uploadAttachment(bytes, f.name);
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) return;

      await supabase.from('messages').insert({
        'sender_id': currentUser.id,
        'content_text': '', // Vazio pois é imagem
        'conversation_id': widget.conversationId!,
        'media_url': url,
        'media_type': f.extension ?? 'file',
        'created_at': DateTime.now().toIso8601String(),
        'is_read': false,
      });

      if (mounted) {
        _showSnackBar(context, 'Arquivo enviado!');
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint('Erro upload: $e');
      if (mounted) _showSnackBar(context, 'Erro ao enviar.', isError: true);
    }
  }

  // --- PRESENÇA ---
  void _setupPresenceSubscription() {
    _presenceChannel = supabase.channel(kPresenceChannelName);
    final presence = _presenceChannel.presence;

    presence.onSync(() {
      final raw = (presence.state as dynamic);
      final online = <String>{};
      final typing = <String>{};

      if (raw is Map) {
        raw.forEach((key, value) {
          final userId = key.toString();
          final list = (value is List) ? value : [value];
          for (final p in list) {
            String? status;
            if (p is Map) status = p['status']?.toString();
            online.add(userId);
            if (status == 'typing') typing.add(userId);
            _loadUserName(userId);
          }
        });
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
      await _presenceChannel.untrack();
    } catch (_) {}
    try {
      await supabase.removeChannel(_presenceChannel);
    } catch (_) {}
  }

  Future<void> _trackUserStatus({required bool typing}) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      await _presenceChannel.track({
        'user_id': user.id,
        'status': typing ? 'typing' : 'online',
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
  }

  void _onMessageChanged(String v) {
    _typingTimer?.cancel();
    _trackUserStatus(typing: true);
    _typingTimer = Timer(kTypingDelay, () {
      _trackUserStatus(typing: false);
    });
  }

  // --- PERFIL E AVATAR ---
  Future<void> _loadUserName(String userId) async {
    if (_userNames.containsKey(userId)) return;

    try {
      final res = await supabase
          .from('profiles')
          .select('id, username, full_name, email, avatar_url')
          .eq('id', userId)
          .maybeSingle();

      if (res != null) {
        final name = (res['full_name'] ?? res['username'] ?? '').toString();
        _userNames[userId] = name.isNotEmpty ? name : "Usuário";

        final avatarPath = res['avatar_url'] as String?;
        if (avatarPath != null && avatarPath.isNotEmpty) {
          try {
            final signed = await supabase.storage
                .from('profile_pictures')
                .createSignedUrl(avatarPath, 3600);
            _avatarUrls[userId] = signed;
          } catch (_) {}
        }
        if (mounted) setState(() {});
      }
    } catch (_) {
      _userNames[userId] = 'Usuário';
    }
  }

  // --- CRUD MENSAGENS ---
  Future<void> _startEditing(String msgId, String text, String? created) async {
    if (created != null) {
      final dt = DateTime.tryParse(created);
      if (dt != null && DateTime.now().difference(dt).inMinutes > 15) {
        _showSnackBar(context, 'Tempo de edição expirou.', isError: true);
        return;
      }
    }
    setState(() {
      _editingMessageId = msgId;
      messageController.text = text;
    });
    FocusScope.of(context).requestFocus(FocusNode());
  }

  Future<void> _deleteMessage(String msgId) async {
    try {
      await _chatService.deleteMessage(messageId: msgId);
      if (mounted) _showSnackBar(context, 'Apagada.');
    } catch (_) {
      if (mounted) _showSnackBar(context, 'Erro ao apagar.', isError: true);
    }
  }

  // --- REAÇÕES ---
  Future<void> _onReact(String msgId, String reaction) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      await _chatService.addReaction(
        messageId: msgId,
        userId: user.id,
        reaction: reaction,
      );
      _messageReactions.remove(msgId);
      await _fetchReactions(msgId);
    } catch (_) {}
  }

  Future<void> _fetchReactions(String msgId) async {
    if (_messageReactions.containsKey(msgId)) return;
    try {
      final agg = await _chatService.getReactionsAggregated(msgId);
      if (mounted) setState(() => _messageReactions[msgId] = agg);
    } catch (_) {}
  }

  void _ensureReactionSubscription(String msgId) {
    if (msgId.isEmpty || _reactionSubs.containsKey(msgId)) return;
    _reactionSubs[msgId] = supabase
        .from('message_reactions')
        .stream(primaryKey: ['id'])
        .eq('message_id', msgId)
        .listen((list) {
          final Map<String, int> agg = {};
          for (final r in list) {
            final emoji = (r['reaction'] ?? '').toString();
            if (emoji.isNotEmpty) agg[emoji] = (agg[emoji] ?? 0) + 1;
          }
          if (mounted) setState(() => _messageReactions[msgId] = agg);
        });
  }

  Future<void> _cancelAllReactionSubscriptions() async {
    for (final s in _reactionSubs.values) await s.cancel();
    _reactionSubs.clear();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 300), () {
      if (scrollController.hasClients) {
        scrollController.animateTo(
          scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // =======================================================================
  //                                  BUILD
  // =======================================================================
  @override
  Widget build(BuildContext context) {
    final currentUser = supabase.auth.currentUser;

    // 1. PROTEÇÃO: Se usuário nulo, retorna loading para evitar crash
    if (currentUser == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      // Removido backgroundColor fixo para respeitar o tema
      appBar: AppBar(
        title: const Text("Chat"),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SearchPage()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: Text('${_onlineUsers.length} online')),
          ),
        ],
      ),

      drawer: const CustomDrawer(),

      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: supabase
                  .from('messages')
                  .stream(primaryKey: ['id'])
                  .eq('conversation_id', widget.conversationId!)
                  .order('created_at', ascending: true)
                  .map((data) => List<Map<String, dynamic>>.from(data)),
              builder: (_, snapshot) {
                if (snapshot.hasError)
                  return Center(child: Text('Erro: ${snapshot.error}'));
                if (!snapshot.hasData)
                  return const Center(child: CircularProgressIndicator());

                final messages = snapshot.data!;
                if (messages.isNotEmpty) _scrollToBottom();
                if (messages.isEmpty) {
                  return const Center(child: Text("Comece a conversar!"));
                }

                return ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (_, i) {
                    final msg = messages[i];
                    final senderId = msg['sender_id']?.toString();
                    if (senderId != null) _loadUserName(senderId);

                    final mine = senderId == currentUser.id;
                    final userName = _userNames[senderId] ?? '...';
                    final initials = userName.isNotEmpty
                        ? userName.substring(0, 1).toUpperCase()
                        : '?';

                    final msgId = msg['id'].toString();
                    final time = DateFormat(
                      'HH:mm',
                    ).format(DateTime.parse(msg['created_at']));

                    // Dados para imagem
                    final mediaUrl = msg['media_url']?.toString();
                    final isImage = mediaUrl != null && mediaUrl.isNotEmpty;

                    _ensureReactionSubscription(msgId);
                    _fetchReactions(msgId);

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: mine
                            ? MainAxisAlignment.end
                            : MainAxisAlignment.start,
                        children: [
                          // 2. AVATAR (Esquerda se for Outro)
                          if (!mine) ...[
                            _buildAvatar(senderId, initials),
                            const SizedBox(width: 8),
                          ],

                          Flexible(
                            child: Column(
                              crossAxisAlignment: mine
                                  ? CrossAxisAlignment.end
                                  : CrossAxisAlignment.start,
                              children: [
                                // Nome
                                Text(
                                  mine ? "Você" : userName,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    // 3. Cor ajustável ao tema
                                    color: isDarkMode
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                ),

                                // Balão da Mensagem
                                GestureDetector(
                                  onLongPress: () =>
                                      _showContextMenu(context, msg, mine),
                                  child: Container(
                                    margin: const EdgeInsets.only(top: 2),
                                    padding: isImage
                                        ? EdgeInsets.zero
                                        : const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 10,
                                          ),
                                    decoration: BoxDecoration(
                                      color: mine
                                          ? Colors.blue
                                          : Colors.grey.shade300,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    // 4. Lógica Imagem vs Texto
                                    child: isImage
                                        ? ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            child: Image.network(
                                              mediaUrl,
                                              height: 200,
                                              width: 200,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) =>
                                                  const Icon(
                                                    Icons.broken_image,
                                                  ),
                                              loadingBuilder: (_, child, p) =>
                                                  p == null
                                                  ? child
                                                  : const SizedBox(
                                                      height: 200,
                                                      width: 200,
                                                      child: Center(
                                                        child:
                                                            CircularProgressIndicator(
                                                              color:
                                                                  Colors.white,
                                                            ),
                                                      ),
                                                    ),
                                            ),
                                          )
                                        : Text(
                                            msg['content_text'] ?? '',
                                            style: TextStyle(
                                              fontSize: 16,
                                              color: mine
                                                  ? Colors.white
                                                  : Colors.black87,
                                            ),
                                          ),
                                  ),
                                ),

                                // Reações
                                if (_messageReactions[msgId]?.isNotEmpty ??
                                    false)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Wrap(
                                      children: _messageReactions[msgId]!
                                          .entries
                                          .map((e) {
                                            return Container(
                                              margin: const EdgeInsets.only(
                                                right: 4,
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.grey.shade200,
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              child: Text(
                                                "${e.key} ${e.value}",
                                                style: const TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.black,
                                                ),
                                              ),
                                            );
                                          })
                                          .toList(),
                                    ),
                                  ),

                                // Horário + Checks
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Text(
                                        time,
                                        style: TextStyle(
                                          fontSize: 10,
                                          // Cor ajustável ao tema
                                          color: isDarkMode
                                              ? Colors.white70
                                              : Colors.grey,
                                        ),
                                      ),
                                      // 5. CHECKS (Visto/Enviado) - Só se for MINHA
                                      if (mine) ...[
                                        const SizedBox(width: 4),
                                        Icon(
                                          msg['is_read'] == true
                                              ? Icons
                                                    .done_all // Dois riscos
                                              : Icons.check, // Um risco
                                          size: 14,
                                          // Azul se lido, Cor do tema se não
                                          color: msg['is_read'] == true
                                              ? Colors.blue
                                              : (isDarkMode
                                                    ? Colors.white70
                                                    : Colors.grey),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // 2. AVATAR (Direita se for Eu)
                          if (mine) ...[
                            const SizedBox(width: 8),
                            _buildAvatar(senderId, initials),
                          ],
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // INPUT AREA
          Container(
            padding: const EdgeInsets.all(8),
            color: isDarkMode ? Colors.black12 : Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: messageController,
                    onChanged: _onMessageChanged,
                    style: TextStyle(
                      color: isDarkMode ? Colors.white : Colors.black,
                    ),
                    decoration: InputDecoration(
                      hintText: "Mensagem...",
                      hintStyle: TextStyle(
                        color: isDarkMode ? Colors.grey : Colors.grey,
                      ),
                      filled: true,
                      fillColor: isDarkMode
                          ? Colors.grey[800]
                          : Colors.grey.shade100,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.attach_file,
                    color: isDarkMode ? Colors.white70 : Colors.grey,
                  ),
                  onPressed: _pickAndUploadAttachment,
                ),
                CircleAvatar(
                  backgroundColor: Colors.blue,
                  child: IconButton(
                    icon: _isSending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.send, color: Colors.white, size: 20),
                    onPressed: _isSending ? null : _sendMessage,
                  ),
                ),
              ],
            ),
          ),

          // "Digitando..."
          if (_typingUsers.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "${_userNames[_typingUsers.first] ?? 'Alguém'} digitando...",
                  style: const TextStyle(
                    color: Colors.grey,
                    fontStyle: FontStyle.italic,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Widget auxiliar do Avatar
  Widget _buildAvatar(String? userId, String initials) {
    final url = _avatarUrls[userId];
    return CircleAvatar(
      radius: 16,
      backgroundColor: Colors.blueGrey,
      backgroundImage: (url != null && url.isNotEmpty)
          ? NetworkImage(url)
          : null,
      child: (url == null || url.isEmpty)
          ? Text(
              initials,
              style: const TextStyle(fontSize: 12, color: Colors.white),
            )
          : null,
    );
  }

  void _showContextMenu(BuildContext ctx, Map<String, dynamic> msg, bool mine) {
    showModalBottomSheet(
      context: ctx,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.emoji_emotions),
              title: const Text('Reagir'),
              onTap: () {
                Navigator.pop(ctx);
                showModalBottomSheet(
                  context: ctx,
                  builder: (_) => MessageReactions(
                    onReact: (r) {
                      Navigator.pop(ctx);
                      _onReact(msg['id'].toString(), r);
                    },
                  ),
                );
              },
            ),
            if (mine && (msg['media_url'] == null))
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Editar'),
                onTap: () {
                  Navigator.pop(ctx);
                  _startEditing(
                    msg['id'].toString(),
                    msg['content_text'],
                    msg['created_at'],
                  );
                },
              ),
            if (mine)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text(
                  'Apagar',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteMessage(msg['id'].toString());
                },
              ),
          ],
        ),
      ),
    );
  }
}
