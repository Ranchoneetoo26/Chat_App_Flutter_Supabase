import 'package:flutter/material.dart';
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'chat_page.dart';
import 'profile_page.dart'; // Importação do Perfil

class ConversationsPage extends StatefulWidget {
  const ConversationsPage({super.key});

  @override
  State<ConversationsPage> createState() => _ConversationsPageState();
}

class _ConversationsPageState extends State<ConversationsPage> {
  List<Map<String, dynamic>> _convs = [];
  bool _loading = false;
  final sup = Supabase.instance.client;
  // Subscriptions usando streams
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
      // ##### CORREÇÃO: Usando a tabela 'participants' #####
      _membersSub = sup
          .from('participants') // 
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
        setState(() => _loading = false);
        return;
      }

      // ##### CORREÇÃO: Usando a tabela 'participants' #####
      final members = await sup
          .from('participants') // 
          .select('conversation_id')
          .eq('user_id', currentUser.id);

      final ids = (members as List)
          .map((e) => e['conversation_id'])
          .where((e) => e != null)
          .toList();

      if (ids.isEmpty) {
        _convs = [];
        setState(() => _loading = false);
        return;
      }

      final idList = ids.map((e) => e.toString()).toList();

      // ##### CORREÇÃO: Usando a coluna 'group_name' #####
      final res = await sup
          .from('conversations')
          .select(
            'id, group_name, is_group, is_public, created_at, updated_at, created_by', // 
          )
          .filter('id', 'in', idList)
          .order('updated_at', ascending: false);

      _convs = List<Map<String, dynamic>>.from(res as List);

    } catch (e) {
      debugPrint('Erro ao carregar conversas: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erro ao carregar conversas: $e'),
          backgroundColor: Colors.red,
        ));
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Conversas')),

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
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Sair'),
              onTap: () async {
                Navigator.pop(context); // Fecha o Drawer
                await sup.auth.signOut();
              },
            ),
          ],
        ),
      ),

      body: RefreshIndicator(
        onRefresh: _loadConversations,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView.builder(
                itemCount: _convs.length,
                itemBuilder: (_, i) {
                  final c = _convs[i];
                  // ##### CORREÇÃO: Usando a coluna 'group_name' #####
                  final title = (c['is_group'] == true)
                      ? (c['group_name'] ?? 'Grupo') // 
                      : (c['group_name'] ?? 'Conversa'); // 

                  return ListTile(
                    leading: const Icon(Icons.chat_bubble_outline),
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

  void _showCreateDialog() {
    final currentUser = sup.auth.currentUser;
    if (currentUser == null) return;

    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        final TextEditingController searchController = TextEditingController();
        final TextEditingController nameController = TextEditingController();
        bool isGroup = false;
        bool isPublic = false;

        return StatefulBuilder(
          builder: (ctx, setState) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Checkbox(
                        value: isGroup,
                        onChanged: (v) => setState(() => isGroup = v ?? false),
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
                      ),
                    ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: searchController,
                    decoration: const InputDecoration(
                      labelText: 'Buscar usuário por email ou username',
                    ),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () async {
                      final query = searchController.text.trim();
                      if (query.isEmpty) return;

                      // search by email or username
                      final res = await sup
                          .from('profiles')
                          .select('id, email, username')
                          .or('email.eq.$query,username.eq.$query')
                          .maybeSingle();

                      if (res == null && !isGroup) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                            content: Text('Usuário não encontrado'),
                          ),
                        );
                        return;
                      }

                      final otherId = res != null ? res['id'] : null;

                      if (!isGroup) {
                        if (otherId == null) return;
                        // find existing 1:1 conversation between current user and otherId
                        final convId = await _findOrCreatePrivateConversation(
                          currentUser.id,
                          otherId,
                        );
                        if (!mounted) return;
                        Navigator.of(context).pop();
                        _openConversation(convId);
                        return;
                      }

                      // ##### CORREÇÃO: Usando 'group_name' #####
                      final created = await sup
                          .from('conversations')
                          .insert({
                            'group_name': nameController.text.trim(), // 
                            'is_group': true,
                            'is_public': isPublic,
                            'created_by': currentUser.id,
                            'created_at': DateTime.now().toIso8601String(),
                          })
                          .select()
                          .maybeSingle();

                      if (created != null) {
                        final convId = created['id'];
                        // ##### CORREÇÃO: Usando 'participants' #####
                        await sup.from('participants').insert([ // 
                          {
                            'conversation_id': convId,
                            'user_id': currentUser.id,
                          },
                        ]);
                        if (otherId != null) {
                          // ##### CORREÇÃO: Usando 'participants' #####
                          await sup.from('participants').insert([ // 
                            {'conversation_id': convId, 'user_id': otherId},
                          ]);
                        }
                        if (!mounted) return;
                        Navigator.of(context).pop();
                        _openConversation(convId);
                      }
                    },
                    child: const Text('Criar'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<String> _findOrCreatePrivateConversation(String a, String b) async {
    try {
      // ##### CORREÇÃO: Usando 'participants' #####
      final resA = await sup
          .from('participants') // 
          .select('conversation_id')
          .eq('user_id', a);
      final resB = await sup
          .from('participants') // 
          .select('conversation_id')
          .eq('user_id', b);
      // ##### FIM DA CORREÇÃO #####

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
        // verify any common conversation is not a group
        final idList = common.toList();
        
        final convs = await sup
            .from('conversations')
            .select('id')
            .filter('id', 'in', idList)
            .eq('is_group', false);

        final convsList = convs as List? ?? <dynamic>[];
        if (convsList.isNotEmpty) {
          return convsList.first['id'].toString();
        }
      }
    } catch (e) {
      debugPrint('find conversation error: $e');
    }

    // create new private conversation
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
    
    // ##### CORREÇÃO: Usando 'participants' #####
    await sup.from('participants').insert([ // 
      {'conversation_id': convId, 'user_id': a},
      {'conversation_id': convId, 'user_id': b},
    ]);
    return convId.toString();
  }
}