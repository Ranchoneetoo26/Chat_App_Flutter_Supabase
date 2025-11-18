import 'package:app/ui/widgets/custom_drawer.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'chat_page.dart';

class ConversationsPage extends StatefulWidget {
  const ConversationsPage({super.key});

  @override
  State<ConversationsPage> createState() => _ConversationsPageState();
}

class _ConversationsPageState extends State<ConversationsPage> {
  List<Map<String, dynamic>> _convs = [];
  bool _loading = false;
  final sup = Supabase.instance.client;

  StreamSubscription<List<Map<String, dynamic>>>? _membersSub;
  StreamSubscription<List<Map<String, dynamic>>>? _convsSub;

  @override
  void initState() {
    super.initState();
    _loadConversations();
    _setupRealtime();
  }

  @override
  void dispose() {
    try {
      _membersSub?.cancel();
    } catch (e) {
      debugPrint('cancel members sub error: $e');
    }
    try {
      _convsSub?.cancel();
    } catch (e) {
      debugPrint('cancel convs sub error: $e');
    }
    super.dispose();
  }

  void _setupRealtime() {
    final currentUser = sup.auth.currentUser;
    if (currentUser == null) return;
    try {
      _membersSub = sup
          .from('participants')
          .stream(primaryKey: ['id'])
          .eq('user_id', currentUser.id)
          .listen(
            (_) => _loadConversations(),
            onError: (e) => debugPrint('members stream error: $e'),
          );

      _convsSub = sup
          .from('conversations')
          .stream(primaryKey: ['id'])
          .listen(
            (_) => _loadConversations(),
            onError: (e) => debugPrint('conversations stream error: $e'),
          );
    } catch (e) {
      debugPrint('setupRealtime error: $e');
    }
  }

  Future<void> _loadConversations() async {
    if (mounted && _convs.isEmpty) {
      setState(() => _loading = true);
    }

    try {
      final currentUser = sup.auth.currentUser;
      if (currentUser == null) {
        _convs = [];
        if (mounted) setState(() => _loading = false);
        return;
      }

      final members = await sup
          .from('participants')
          .select('conversation_id')
          .eq('user_id', currentUser.id);

      final ids = (members as List)
          .map((e) => e['conversation_id'])
          .where((e) => e != null)
          .toList();

      if (ids.isEmpty) {
        _convs = [];
        if (mounted) setState(() => _loading = false);
        return;
      }

      final idList = ids.map((e) => e.toString()).toList();
      final res = await sup
          .from('conversations')
          .select(
            'id, group_name, is_group, is_public, created_at, updated_at, created_by',
          )
          .filter('id', 'in', idList)
          .order('updated_at', ascending: false);

      _convs = List<Map<String, dynamic>>.from(res as List);
    } catch (e) {
      debugPrint('Erro ao carregar conversas: $e');
      if (mounted) {
        String errorMessage = 'Erro ao carregar: $e';
        if (e is PostgrestException) {
          errorMessage = 'Erro do Banco: ${e.message}';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage), backgroundColor: Colors.red),
        );
      }
    }

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  void _openConversation(dynamic convId) {
    if (convId == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatPage(conversationId: convId.toString()),
      ),
    );
  }

  void _showCreateDialog() {
    final currentUser = sup.auth.currentUser;
    if (currentUser == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final TextEditingController searchController = TextEditingController();
        final TextEditingController nameController = TextEditingController();
        bool isGroup = false;
        bool isPublic = false;

        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: StatefulBuilder(
            builder: (ctx, setState) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "Nova Conversa",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Checkbox(
                          value: isGroup,
                          onChanged: (v) =>
                              setState(() => isGroup = v ?? false),
                        ),
                        const Text('Criar grupo'),
                        const Spacer(),
                        if (isGroup)
                          Row(
                            children: [
                              const Text('Público'),
                              Checkbox(
                                value: isPublic,
                                onChanged: (v) =>
                                    setState(() => isPublic = v ?? false),
                              ),
                            ],
                          ),
                      ],
                    ),
                    if (isGroup)
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Nome do grupo',
                          prefixIcon: Icon(Icons.group),
                        ),
                      ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: searchController,
                      decoration: const InputDecoration(
                        labelText: 'Buscar usuário (email ou username)',
                        prefixIcon: Icon(Icons.person_search),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 45,
                      child: ElevatedButton(
                        onPressed: () async {
                          final query = searchController.text.trim();
                          if (query.isEmpty && !isGroup) {
                            return;
                          }

                          try {
                            Map<String, dynamic>? otherUser;
                            if (query.isNotEmpty) {
                              final res = await sup
                                  .from('profiles')
                                  .select('id, email, username')
                                  .or('email.eq."$query",username.eq."$query"')
                                  .maybeSingle();

                              if (res == null && !isGroup) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(
                                    content: Text('Usuário não encontrado'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                                return;
                              }
                              otherUser = res;
                            }

                            final otherId = otherUser != null
                                ? otherUser['id']
                                : null;

                            if (!isGroup) {
                              if (otherId == null) return;
                              if (otherId == currentUser.id) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Você não pode criar uma conversa com você mesmo.',
                                    ),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                                return;
                              }

                              final convId =
                                  await _findOrCreatePrivateConversation(
                                    currentUser.id,
                                    otherId,
                                  );
                              if (!mounted) return;
                              Navigator.pop(ctx);
                              _openConversation(convId);
                              return;
                            }

                            final created = await sup
                                .from('conversations')
                                .insert({
                                  'group_name':
                                      nameController.text.trim().isEmpty
                                      ? 'Novo Grupo'
                                      : nameController.text.trim(),
                                  'is_group': true,
                                  'is_public': isPublic,
                                  'created_by': currentUser.id,
                                  'created_at': DateTime.now()
                                      .toIso8601String(),
                                })
                                .select()
                                .maybeSingle();

                            if (created != null) {
                              final convId = created['id'];
                              await sup.from('participants').insert([
                                {
                                  'conversation_id': convId,
                                  'user_id': currentUser.id,
                                },
                              ]);
                              if (otherId != null &&
                                  otherId != currentUser.id) {
                                await sup.from('participants').insert([
                                  {
                                    'conversation_id': convId,
                                    'user_id': otherId,
                                  },
                                ]);
                              }
                              if (!mounted) return;
                              Navigator.pop(ctx);
                              _openConversation(convId);
                            }
                          } catch (e) {
                            String errorMessage = 'Erro ao criar: $e';
                            if (e is PostgrestException) {
                              errorMessage = 'Erro do Banco: ${e.message}';
                            }
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(
                                content: Text(errorMessage),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        },
                        child: const Text('Iniciar'),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<String> _findOrCreatePrivateConversation(String a, String b) async {
    try {
      final resA = await sup
          .from('participants')
          .select('conversation_id')
          .eq('user_id', a);
      final resB = await sup
          .from('participants')
          .select('conversation_id')
          .eq('user_id', b);

      final idsA = (resA as List)
          .map((e) => e['conversation_id']?.toString())
          .where((e) => e != null)
          .toSet();
      final idsB = (resB as List)
          .map((e) => e['conversation_id']?.toString())
          .where((e) => e != null)
          .toSet();

      final common = idsA.intersection(idsB);

      if (common.isNotEmpty) {
        final idList = common.toList();
        final convs = await sup
            .from('conversations')
            .select('id')
            .filter('id', 'in', idList)
            .eq('is_group', false);

        final convsList = convs as List? ?? [];
        if (convsList.isNotEmpty) {
          return convsList.first['id'].toString();
        }
      }
    } catch (e) {
      debugPrint('find conversation error: $e');
      throw Exception('Falha ao buscar conversas existentes: $e');
    }

    try {
      final created = await sup
          .from('conversations')
          .insert({
            'is_group': false,
            'created_at': DateTime.now().toIso8601String(),
          })
          .select()
          .maybeSingle();

      final convId = created == null ? null : created['id'];
      if (convId == null) throw Exception('Failed to create conversation');

      await sup.from('participants').insert([
        {'conversation_id': convId, 'user_id': a},
        {'conversation_id': convId, 'user_id': b},
      ]);
      return convId.toString();
    } catch (e) {
      debugPrint('create conversation error: $e');
      throw Exception('Falha ao criar nova conversa: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Conversas')),

      drawer: const CustomDrawer(),

      body: RefreshIndicator(
        onRefresh: _loadConversations,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _convs.isEmpty
            ? const Center(child: Text("Nenhuma conversa ainda."))
            : ListView.builder(
                itemCount: _convs.length,
                itemBuilder: (_, i) {
                  final c = _convs[i];
                  final title = (c['is_group'] == true)
                      ? (c['group_name'] ?? 'Grupo')
                      : (c['group_name'] ?? 'Conversa');

                  return ListTile(
                    leading: Icon(
                      c['is_group'] == true ? Icons.group : Icons.person,
                    ),
                    title: Text(title),
                    subtitle: Text(
                      (c['is_public'] == true) ? 'Público' : 'Privado',
                    ),
                    onTap: () => _openConversation(c['id']),
                  );
                },
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}
