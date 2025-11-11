// lib/main.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:app/ui/widgets/custom_button.dart';
import 'package:app/ui/widgets/custom_input.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app/ui/pages/chat_page.dart';
import 'package:app/ui/widgets/user_presence_tile.dart';

final supabase = Supabase.instance.client;
const String kPresenceChannelName = 'online_users';
const Duration kTypingDelay = Duration(seconds: 3);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'COLOQUE SUA URL AQUI', // <- substitua
    anonKey: 'COLOQUE SUA ANON KEY AQUI', // <- substitua
  );

  runApp(const MainApp());
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  // controllers
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController searchController = TextEditingController();

  // presence
  late RealtimeChannel _presenceChannel;
  String? _currentUserId;
  Set<String> _onlineUsers = {};
  String? _typingUserId;
  bool _isTyping = false;
  Timer? _typingTimer;
  bool _isStatusHidden = false;

  // search results
  List<Map<String, dynamic>> _userSearchResults = [];
  List<Map<String, dynamic>> _groupSearchResults = [];

  // cache de nomes (id -> username/full_name)
  final Map<String, Map<String, String>> _userNames = {};

  @override
  void initState() {
    super.initState();
    _initSupabaseAuthListener();
    _setupPresenceSubscription(); // já existe
  }

  void _initSupabaseAuthListener() {
    // if already logged
    if (supabase.auth.currentUser != null) {
      _currentUserId = supabase.auth.currentUser!.id;
      _setupPresenceSubscription();
    }

    // listen auth changes
    supabase.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      final session = data.session;

      if (event == AuthChangeEvent.signedIn && session != null) {
        _currentUserId = session.user.id;
        _setupPresenceSubscription();
      } else if (event == AuthChangeEvent.signedOut) {
        _removePresenceSubscription();
        _currentUserId = null;
        setState(() {
          _onlineUsers = {};
          _typingUserId = null;
          _userSearchResults = [];
          _groupSearchResults = [];
        });
      }
    });
  }

  // -------------------------
  // PRESENCE: setup / track / remove
  // -------------------------
  void _setupPresenceSubscription() {
    if (_currentUserId == null) return;

    _presenceChannel = supabase.channel(kPresenceChannelName);
    final presence = _presenceChannel.presence;

    presence.onSync(() {
      final dynamic rawState = presence.state;
      final onlineUsers = <String>{};
      String? typingUser;

      if (rawState is Map) {
        rawState.forEach((key, value) {
          final userId = key.toString();
          final presences = (value is List) ? value : [value];
          for (final p in presences) {
            bool hidden = false;
            String? status;

            if (p is Map) {
              hidden = (p['hide_status'] as bool?) ?? false;
              status = p['status']?.toString();
            } else {
              status = p?.toString();
            }

            _loadUserName(userId);

            if (!hidden) onlineUsers.add(userId);
            if (status == 'typing' && userId != _currentUserId) {
              typingUser = userId;
            }
          }
        });
      }

      setState(() {
        _onlineUsers = onlineUsers;
        _typingUserId = typingUser;
      });
    });

    _presenceChannel.subscribe((status, [error]) {
      if (status == RealtimeSubscribeStatus.subscribed) {
        _trackUserStatus();
      }
    });
  }

  Future<void> _trackUserStatus() async {
    if (_currentUserId == null) return;

    try {
      if (_isStatusHidden) {
        await _presenceChannel.presence.untrack();
        return;
      }

      await _presenceChannel.presence.track({
        'user_id': _currentUserId,
        'status': _isTyping ? 'typing' : 'online',
        'hide_status': _isStatusHidden,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {}
  }

  Future<void> _removePresenceSubscription() async {
    try {
      await _presenceChannel.presence.untrack();
    } catch (_) {}

    try {
      await supabase.removeChannel(_presenceChannel);
    } catch (_) {}
  }

  // -------------------------
  // Typing indicator handler
  // -------------------------
  void _onChatInputChanged(String text) {
    if (text.isEmpty) {
      if (_isTyping) {
        _typingTimer?.cancel();
        setState(() => _isTyping = false);
        _trackUserStatus();
      }
      return;
    }

    if (!_isTyping) {
      setState(() => _isTyping = true);
      _trackUserStatus();
    }

    _typingTimer?.cancel();
    _typingTimer = Timer(kTypingDelay, () {
      setState(() => _isTyping = false);
      _trackUserStatus();
    });
  }

  // -------------------------
  // Busca (profiles e groups) - mais precisa
  // -------------------------
  Future<List<Map<String, dynamic>>> _searchUsers(String query) async {
    if (query.isEmpty) return [];
    try {
      final res = await supabase
          .from('profiles')
          .select('id, username, full_name, created_at')
          .ilike('username', '%$query%')
          .or('full_name.ilike.%$query%')
          .limit(20);
      return (res as List<dynamic>).cast<Map<String, dynamic>>();
    } catch (e) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _searchGroups(String query) async {
    if (query.isEmpty) return [];
    try {
      final res = await supabase
          .from('groups')
          .select('id, name')
          .eq('is_public', true)
          .ilike('name', '%$query%')
          .limit(20);
      return (res as List<dynamic>).cast<Map<String, dynamic>>();
    } catch (e) {
      return [];
    }
  }

  void _runSearch(String query) async {
    if (query.isEmpty) {
      setState(() {
        _userSearchResults = [];
        _groupSearchResults = [];
      });
      return;
    }

    final users = await _searchUsers(query);
    final groups = await _searchGroups(query);

    setState(() {
      _userSearchResults = users;
      _groupSearchResults = groups;
    });
  }

  // -------------------------
  // Auth helpers
  // -------------------------
  void _cadastrarUsuario() async {
    final email = emailController.text.trim();
    final pass = passwordController.text.trim();
    if (email.isEmpty || pass.isEmpty) return;

    try {
      await supabase.auth.signUp(email: email, password: pass);
    } catch (e) {}
  }

  void _logout() async {
    try {
      await supabase.auth.signOut();
    } catch (e) {}
  }

  // -------------------------
  // UI
  // -------------------------
  @override
  void dispose() {
    _removePresenceSubscription();
    emailController.dispose();
    passwordController.dispose();
    searchController.dispose();
    _typingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: supabase.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final loggedIn = snapshot.data?.session != null;

        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            primarySwatch: Colors.blue,
            scaffoldBackgroundColor: const Color(0xFFF1F4FF),
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              elevation: 2,
            ),
          ),
          home: loggedIn ? _buildChatScreen() : _buildLoginScreen(),
        );
      },
    );
  }

  Widget _buildLoginScreen() {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CustomInput(
                  label: "Email",
                  controller: emailController,
                  hint: 'seu@email.com',
                ),
                const SizedBox(height: 12),
                CustomInput(
                  label: "Senha",
                  controller: passwordController,
                  hint: 'senha',
                ),
                const SizedBox(height: 20),
                CustomButton(
                  buttonText: "Entrar",
                  onPressed: () {
                    supabase.auth.signInWithPassword(
                      email: emailController.text.trim(),
                      password: passwordController.text.trim(),
                    );
                  },
                  backgroundColor: Colors.blue,
                ),
                const SizedBox(height: 12),
                CustomTextButton(
                  buttonText: "Cadastrar",
                  onPressed: _cadastrarUsuario,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChatScreen() {
    return const ChatPage();
  }

  Widget _buildPresenceTab() {
    final userId = _currentUserId;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _typingUserId != null
                    ? "Usuário ${_displayName(_typingUserId!)} está digitando..."
                    : "Ninguém digitando no momento",
                style: const TextStyle(fontSize: 14, color: Colors.blue),
              ),
            ),
            Switch(
              value: _isStatusHidden,
              onChanged: (v) {
                setState(() => _isStatusHidden = v);
                _trackUserStatus();
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        CustomInput(
          onChanged: _onChatInputChanged,
          label: "Mensagem",
          hint: "Escreva algo para testar 'digitando'...",
          controller: TextEditingController(),
        ),
        const SizedBox(height: 24),
        Text(
          "Usuários online (${_onlineUsers.length}):",
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        ..._onlineUsers.map((u) {
          final display = _displayName(u);
          return UserPresenceTile(
            displayName: u == userId ? "Você ($display)" : display,
            isOnline: true,
            onTap: () {},
          );
        }),
        const SizedBox(height: 24),
        CustomButton(
          buttonText: "Logout",
          backgroundColor: Colors.red,
          onPressed: _logout,
        ),
      ],
    );
  }

  Widget _buildSearchTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: CustomInput(
            controller: searchController,
            onChanged: _runSearch,
            label: "Buscar usuários ou grupos",
            hint: "Digite um nome...",
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              if (_userSearchResults.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'Usuários (${_userSearchResults.length})',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ..._userSearchResults.map((u) {
                final name = u['username'] ?? u['full_name'] ?? u['id'];
                return ListTile(
                  leading: CircleAvatar(
                    child: Text((name as String).isNotEmpty ? name[0] : '?'),
                  ),
                  title: Text(name),
                  subtitle: Text(
                    'ID: ${u['id']} • criado: ${u['created_at'] ?? '-'}',
                  ),
                );
              }),
              if (_groupSearchResults.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'Grupos (${_groupSearchResults.length})',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ..._groupSearchResults.map((g) {
                return ListTile(
                  leading: const Icon(Icons.group),
                  title: Text(g['name'] ?? 'Grupo'),
                  subtitle: Text('ID: ${g['id']}'),
                );
              }),
              if (_userSearchResults.isEmpty && _groupSearchResults.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('Nenhum resultado')),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReactionsTab() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Reaja a uma mensagem:'),
          const SizedBox(height: 12),
          MessageReactions(
            onReact: (reaction) {
              print('Reação selecionada: $reaction');
              // Aqui pode integrar com backend
            },
          ),
        ],
      ),
    );
  }

  // -------------------------
  // Helpers
  // -------------------------
  Future<void> _loadUserName(String userId) async {
    if (_userNames.containsKey(userId)) return;

    try {
      final res = await supabase
          .from('profiles')
          .select('id, username, full_name')
          .eq('id', userId)
          .maybeSingle();
      if (res != null) {
        _userNames[userId] = {
          'username': (res['username'] ?? '').toString(),
          'full_name': (res['full_name'] ?? '').toString(),
        };
        if (mounted) setState(() {});
      }
    } catch (e) {}
  }

  String _displayName(String userId) {
    final info = _userNames[userId];
    if (info == null) return userId;
    final fullName = info['full_name']?.toString().trim();
    final username = info['username']?.toString().trim();

    if (fullName != null && fullName.isNotEmpty) return fullName;
    if (username != null && username.isNotEmpty) return username;

    return userId;
  }
}

extension on RealtimePresence {
  Future<void> untrack() async {}

  Future<void> track(Map<String, Object?> map) async {}
}

// -------------------------
// Widget de Reações
// -------------------------
class MessageReactions extends StatefulWidget {
  final void Function(String reaction)? onReact;

  const MessageReactions({super.key, this.onReact});

  @override
  State<MessageReactions> createState() => _MessageReactionsState();
}

class _MessageReactionsState extends State<MessageReactions> {
  String? selectedReaction;
  final List<String> reactions = ['👍', '❤️', '😂', '😮', '😢'];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: reactions.map((r) {
        final isSelected = r == selectedReaction;
        return GestureDetector(
          onTap: () {
            setState(() {
              selectedReaction = r;
            });
            if (widget.onReact != null) widget.onReact!(r);
          },
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: isSelected
                  ? Colors.blue.withOpacity(0.2)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(r, style: const TextStyle(fontSize: 20)),
          ),
        );
      }).toList(),
    );
  }
}

// --- MODIFICAÇÃO NO SEU WIDGET ---
// Adicionei o parâmetro onPressed ao seu CustomTextButton
// para que possamos clicar nele.

class CustomTextButton extends StatelessWidget {
  final String buttonText;
  final VoidCallback onPressed; // Adicione esta linha
  const CustomTextButton({
    super.key,
    required this.buttonText,
    required this.onPressed, // Adicione esta linha
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed, // Adicione esta linha
      child: Text(buttonText, style: TextStyle(color: Color(0xFF0F4888))),
    );
  }
}
