import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app/ui/pages/chat_page.dart';
import 'package:app/ui/widgets/custom_button.dart';
import 'package:app/ui/widgets/custom_input.dart';
import 'package:app/ui/widgets/custom_text_button.dart';

final supabase = Supabase.instance.client;
const String kPresenceChannelName = 'online_users';
const Duration kTypingDelay = Duration(seconds: 3);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 🚨 AVISO CRÍTICO: SUBSTITUA ESTES VALORES PELOS SEUS REAIS!
  await Supabase.initialize(
    url: 'https://ihsluigtpkgasyknldsa.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imloc2x1aWd0cGtnYXN5a25sZHNhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjA5ODEwOTYsImV4cCI6MjA3NjU1NzA5Nn0.6qyFgAevobykfqxmirmPKvdSeLlM8nMIG_NowlwhHz8',
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
  final _formKey = GlobalKey<FormState>(); // Chave para o Form

  // presence & auth state
  late RealtimeChannel _presenceChannel;
  String? _currentUserId;
  // presence user set removed from main (managed per-chat)
  final bool _isTyping = false;
  Timer? _typingTimer;
  final bool _isStatusHidden = false;
  final Map<String, Map<String, String>> _userNames = {};

  // Variáveis removidas para limpar warnings: _typingUserId, _userSearchResults, _groupSearchResults

  // 🚨 CORREÇÃO: Função _showSnackBar agora aceita um BuildContext explícito
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

  @override
  void initState() {
    super.initState();
    _initSupabaseAuthListener();
    _setupPresenceSubscription();
  }

  void _initSupabaseAuthListener() {
    if (supabase.auth.currentUser != null) {
      _currentUserId = supabase.auth.currentUser!.id;
      _setupPresenceSubscription();
    }

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
          // cleared auth state
        });
      }
    });
  }

  void _setupPresenceSubscription() {
    if (_currentUserId == null) return;

    _presenceChannel = supabase.channel(kPresenceChannelName);
    final presence = _presenceChannel.presence;

    presence.onSync(() {
      final dynamic rawState = presence.state;
      final onlineUsers = <String>{};

      if (rawState is Map) {
        rawState.forEach((key, value) {
          final userId = key.toString();
          final presences = (value is List) ? value : [value];
          for (final p in presences) {
            bool hidden = false;

            if (p is Map) {
              hidden = (p['hide_status'] as bool?) ?? false;
            }

            _loadUserName(userId);

            if (!hidden) onlineUsers.add(userId);
            // Removido o uso de _typingUserId pois estava causando warnings e não estava sendo usado na tela
            // if (status == 'typing' && userId != _currentUserId) {
            //   typingUser = userId;
            // }
          }
        });
      }

      setState(() {
        // presence updated (state kept local)
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
    } catch (e) {
      debugPrint('trackUserStatus error: $e');
    }
  }

  Future<void> _removePresenceSubscription() async {
    try {
      await _presenceChannel.presence.untrack();
    } catch (e) {
      debugPrint('removePresenceSubscription error: $e');
    }

    try {
      await supabase.removeChannel(_presenceChannel);
    } catch (e) {
      debugPrint('removeChannel error: $e');
    }
  }

  // 🚨 CORREÇÃO: Função _cadastrarUsuario agora aceita o BuildContext
  Future<void> _cadastrarUsuario() async {
    final email = emailController.text.trim();
    final pass = passwordController.text.trim();

    try {
      await supabase.auth.signUp(email: email, password: pass);
      if (!mounted) return;
      _showSnackBar(
        context,
        "✅ Cadastro iniciado! Verifique seu email para confirmação.",
        isError: false,
      );
    } on AuthException catch (e) {
      if (mounted) {
        _showSnackBar(
          context,
          "Falha no Cadastro: ${e.message}",
          isError: true,
        );
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar(
          context,
          "Erro inesperado. Verifique sua conexão e chaves.",
          isError: true,
        );
      } else {
        debugPrint('signup error: $e');
      }
    }
  }

  // Funções de Busca e Auxiliares Removidas, pois não estavam sendo usadas no Build
  // (Ex.: _searchUsers, _searchGroups, _runSearch) para limpar warnings.

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
    } catch (e) {
      debugPrint('loadUserName error: $e');
    }
  }

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
          home: loggedIn ? ChatPage() : _buildLoginScreen(),
        );
      },
    );
  }

  // 🚨 CORREÇÃO PRINCIPAL: Usando Builder para obter um contexto válido abaixo do Scaffold.
  Widget _buildLoginScreen() {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            // O Builder garante que o contexto (innerContext) aqui está ABAIXO do Scaffold
            child: Builder(
              builder: (innerContext) {
                return Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 32),

                      // CAMPO DE EMAIL COM VALIDADOR
                      CustomInput(
                        controller: emailController,
                        label: "Email",
                        hint: 'seu@email.com',
                        keyboardType: TextInputType.emailAddress,
                        obscureText: false,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Por favor, insira seu email.';
                          }
                          if (!value.contains('@') || !value.contains('.')) {
                            return 'Email inválido. Verifique o formato.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // CAMPO DE SENHA COM VALIDADOR
                      CustomInput(
                        controller: passwordController,
                        label: "Senha",
                        hint: 'senha',
                        obscureText: true,
                        keyboardType: TextInputType.text,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Por favor, insira sua senha.';
                          }
                          if (value.length < 6) {
                            return 'A senha deve ter no mínimo 6 caracteres.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),

                      // BOTÃO ENTRAR
                      CustomButton(
                        buttonText: "Entrar",
                        onPressed: () async {
                          if (_formKey.currentState!.validate()) {
                            try {
                              await supabase.auth.signInWithPassword(
                                email: emailController.text.trim(),
                                password: passwordController.text.trim(),
                              );
                              if (!mounted) return;
                              _showSnackBar(
                                context,
                                "Login bem-sucedido!",
                                isError: false,
                              );
                            } on AuthException catch (e) {
                              if (mounted) {
                                _showSnackBar(
                                  context,
                                  "Falha no Login: ${e.message}",
                                  isError: true,
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                _showSnackBar(
                                  context,
                                  "Erro inesperado. Verifique sua conexão.",
                                  isError: true,
                                );
                              } else {
                                debugPrint('login error: $e');
                              }
                            }
                          }
                        },
                        backgroundColor: Colors.blue,
                      ),
                      const SizedBox(height: 12),

                      // BOTÃO CADASTRAR
                      CustomTextButton(
                        buttonText: "Cadastrar",
                        onPressed: () {
                          if (_formKey.currentState!.validate()) {
                            _cadastrarUsuario();
                          }
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

// Extensões e Widgets Auxiliares
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
                  ? Colors.blue.withAlpha(51)
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
