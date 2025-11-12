// lib/main.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:app/ui/widgets/custom_button.dart';
import 'package:app/ui/widgets/custom_input.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app/ui/pages/chat_page.dart';
import 'package:app/ui/widgets/user_presence_tile.dart';
import 'package:app/ui/widgets/custom_text_button.dart'; // Importado corretamente

final supabase = Supabase.instance.client;
const String kPresenceChannelName = 'online_users';
const Duration kTypingDelay = Duration(seconds: 3);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 🚨 AVISO CRÍTICO: SUBSTITUA ESTES VALORES PELOS SEUS REAIS!
  await Supabase.initialize(
    url: 'https://ihsluigtpkgasyknldsa.supabase.co', // <- substitua
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imloc2x1aWd0cGtnYXN5a25sZHNhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjA5ODEwOTYsImV4cCI6MjA3NjU1NzA5Nn0.6qyFgAevobykfqxmirmPKvdSeLlM8nMIG_NowlwhHz8', // <- substitua
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

  // =========================================================================
  // FUNÇÃO AUXILIAR PARA MOSTRAR SNACKBAR
  // =========================================================================
  void _showSnackBar(String message, {bool isError = false}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red : Colors.green,
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _initSupabaseAuthListener();
    _setupPresenceSubscription();
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

  // -------------------------
  // Auth helpers (CORRIGIDO: Adicionado tratamento de erro)
  // -------------------------
  void _cadastrarUsuario() async {
    final email = emailController.text.trim();
    final pass = passwordController.text.trim();
    if (email.isEmpty || pass.isEmpty) {
      _showSnackBar("Por favor, preencha o e-mail e a senha.", isError: true);
      return;
    }

    try {
      // O await aqui é crucial
      await supabase.auth.signUp(email: email, password: pass);
      //ver pq isso esta acusano erro
      _showSnackBar(
        "✅ Cadastro iniciado! Verifique seu email para confirmação.",
        isError: false,
      );
    } on AuthException catch (e) {
      print('❌ Erro no Cadastro: ${e.message}');
      _showSnackBar("Falha no Cadastro: ${e.message}", isError: true);
    } catch (e) {
      print('❌ Erro inesperado no Cadastro: $e');
      _showSnackBar(
        "Erro inesperado. Verifique sua conexão e chaves.",
        isError: true,
      );
    }
  }

  void _logout() async {
    try {
      await supabase.auth.signOut();
    } catch (e) {}
  }

  // -------------------------
  // Outros helpers (Manter para integridade da classe)
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
    // O StreamBuilder é mantido, mas o redirecionamento é controlado.
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
          home: loggedIn ? const ChatPage() : _buildLoginScreen(),
        );
      },
    );
  }

  // =========================================================================
  // TELA DE LOGIN CORRIGIDA (CORRIGIDO: Parâmetros do CustomInput)
  // =========================================================================
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
                // Remova ou substitua esta linha se não tiver o logo em assets/logos/logo_login.png
                // Image.asset('assets/logos/logo_login.png', height: 100),
                const SizedBox(height: 32),

                // CAMPO DE EMAIL CORRIGIDO
                // CAMPO DE EMAIL CORRIGIDO
                // ... dentro de _buildLoginScreen()...

                // CAMPO DE EMAIL CORRIGIDO
                CustomInput(
                  controller: emailController,
                  label: "Email",
                  hint: 'seu@email.com',
                  keyboardType: TextInputType.emailAddress,
                  obscureText: false, // O email não deve ser ocultado
                ),
                const SizedBox(height: 16),

                // CAMPO DE SENHA CORRIGIDO
                CustomInput(
                  controller: passwordController,
                  label: "Senha",
                  hint: 'senha',
                  obscureText: true, // OBRIGATÓRIO: Oculta o texto
                  keyboardType: TextInputType
                      .text, // OBRIGATÓRIO: Tipo de teclado para senhas
                ),
                const SizedBox(height: 20),

                // ... continua com os botões Entrar e Cadastrar

                // BOTÃO ENTRAR (com a lógica de login corrigida)
                CustomButton(
                  buttonText: "Entrar",
                  onPressed: () async {
                    if (emailController.text.trim().isEmpty ||
                        passwordController.text.trim().isEmpty) {
                      _showSnackBar(
                        "Preencha o e-mail e a senha.",
                        isError: true,
                      );
                      return;
                    }
                    try {
                      await supabase.auth.signInWithPassword(
                        email: emailController.text.trim(),
                        password: passwordController.text.trim(),
                      );
                      _showSnackBar("Login bem-sucedido!", isError: false);
                    } on AuthException catch (e) {
                      print('❌ Erro no Login: ${e.message}');
                      _showSnackBar(
                        "Falha no Login: ${e.message}",
                        isError: true,
                      );
                    } catch (e) {
                      print('❌ Erro inesperado no Login: $e');
                      _showSnackBar(
                        "Erro inesperado. Verifique sua conexão e chaves.",
                        isError: true,
                      );
                    }
                  },
                  backgroundColor: Colors.blue,
                ),
                const SizedBox(height: 12),

                // BOTÃO CADASTRAR (Chama a função corrigida)
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
}

// Extensões e outros widgets auxiliares mantidos para integridade do código original
extension on RealtimePresence {
  Future<void> untrack() async {}
  Future<void> track(Map<String, Object?> map) async {}
}

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
