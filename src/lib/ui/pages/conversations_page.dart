import 'package:flutter/material.dart';
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

// IMPORT CORRIGIDO: Aponta para a raiz onde está o main.dart e o themeNotifier
import '../../../main.dart';
import 'chat_page.dart';
import 'profile_page.dart';

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
          .from('conversation_members')
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
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final currentUser = sup.auth.currentUser;
      if (currentUser == null) {
        _convs = [];
        if (mounted) setState(() => _loading = false);
        return;
      }

      final members = await sup
          .from('conversation_members')
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
      // Filtro corrigido para funcionar com versões mais novas do Supabase
      final res = await sup
          .from('conversations')
          .select(
            'id, name, is_group, is_public, created_at, updated_at, created_by',
          )
          .filter('id', 'in', '(${idList.join(',')})')
          .order('updated_at', ascending: false);

      _convs = List<Map<String, dynamic>>.from(res as List);
    } catch (e) {
      debugPrint("Erro ao carregar conversas: $e");
    }
    if (mounted) setState(() => _loading = false);
  }

  void _openConversation(dynamic convId) {
    if (convId == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatPage(conversationId: convId.toString()),
      ),
    );
  }

  // --- Lógica Completa de Criar Conversa ---
  void _showCreateDialog() {
    final currentUser = sup.auth.currentUser;
    if (currentUser == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // Para o teclado não cobrir o modal
      builder: (ctx) {
        final TextEditingController searchController = TextEditingController();
        final TextEditingController nameController = TextEditingController();
        bool isGroup = false;
        bool isPublic = false;

        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom, // Ajuste teclado
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
                          if (query.isEmpty && !isGroup)
                            return; // Se não for grupo, precisa buscar alguém

                          // Lógica de busca
                          Map<String, dynamic>? otherUser;
                          if (query.isNotEmpty) {
                            final res = await sup
                                .from('profiles')
                                .select('id, email, username')
                                .or('email.eq.$query,username.eq.$query')
                                .maybeSingle();

                            if (res == null && !isGroup) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                  content: Text('Usuário não encontrado'),
                                ),
                              );
                              return;
                            }
                            otherUser = res;
                          }

                          final otherId = otherUser != null
                              ? otherUser['id']
                              : null;

                          // 1. Conversa Privada (1:1)
                          if (!isGroup) {
                            if (otherId == null) return;
                            // Verifica se já existe conversa
                            final convId =
                                await _findOrCreatePrivateConversation(
                                  currentUser.id,
                                  otherId,
                                );
                            if (!mounted) return;
                            Navigator.pop(ctx); // Fecha modal
                            _openConversation(convId);
                            return;
                          }

                          // 2. Criar Grupo
                          final created = await sup
                              .from('conversations')
                              .insert({
                                'name': nameController.text.trim().isEmpty
                                    ? 'Novo Grupo'
                                    : nameController.text.trim(),
                                'is_group': true,
                                'is_public': isPublic,
                                'created_by': currentUser.id,
                                'created_at': DateTime.now().toIso8601String(),
                              })
                              .select()
                              .maybeSingle();

                          if (created != null) {
                            final convId = created['id'];
                            // Adiciona o criador
                            await sup.from('conversation_members').insert([
                              {
                                'conversation_id': convId,
                                'user_id': currentUser.id,
                              },
                            ]);
                            // Adiciona o outro usuário se foi buscado
                            if (otherId != null) {
                              await sup.from('conversation_members').insert([
                                {'conversation_id': convId, 'user_id': otherId},
                              ]);
                            }
                            if (!mounted) return;
                            Navigator.pop(ctx);
                            _openConversation(convId);
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
      // Busca conversas do user A
      final resA = await sup
          .from('conversation_members')
          .select('conversation_id')
          .eq('user_id', a);
      // Busca conversas do user B
      final resB = await sup
          .from('conversation_members')
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

      // Acha a interseção (conversas em comum)
      final common = idsA.intersection(idsB);

      if (common.isNotEmpty) {
        final idList = common.toList();
        // Verifica qual delas NÃO é grupo
        final convs = await sup
            .from('conversations')
            .select('id')
            .filter('id', 'in', '(${idList.join(',')})')
            .eq('is_group', false);

        final convsList = convs as List? ?? [];
        if (convsList.isNotEmpty) {
          return convsList.first['id'].toString();
        }
      }
    } catch (e) {
      debugPrint('find conversation error: $e');
    }

    // Se não achou, cria nova
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

    await sup.from('conversation_members').insert([
      {'conversation_id': convId, 'user_id': a},
      {'conversation_id': convId, 'user_id': b},
    ]);
    return convId.toString();
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
            // --- SWITCH DE TEMA ---
            ValueListenableBuilder<ThemeMode>(
              valueListenable: themeNotifier,
              builder: (ctx, value, _) {
                return SwitchListTile(
                  secondary: Icon(
                    value == ThemeMode.dark
                        ? Icons.dark_mode
                        : Icons.light_mode,
                  ),
                  title: Text(
                    value == ThemeMode.dark ? "Modo Escuro" : "Modo Claro",
                  ),
                  value: value == ThemeMode.dark,
                  onChanged: (isDark) => themeNotifier.value = isDark
                      ? ThemeMode.dark
                      : ThemeMode.light,
                );
              },
            ),
            // ----------------------
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Sair'),
              onTap: () async {
                Navigator.pop(context); // Fecha o Drawer
                await sup.auth.signOut();
                // O main.dart vai detectar o logout e redirecionar
              },
            ),
          ],
        ),
      ),
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
                      ? (c['name'] ?? 'Grupo')
                      : (c['name'] ?? 'Conversa');
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
