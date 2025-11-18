import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app/ui/pages/update_password_page.dart';
import 'package:app/ui/widgets/custom_button.dart';
import 'package:app/ui/widgets/custom_input.dart';
import 'package:app/ui/widgets/custom_text_button.dart';
import 'package:app/ui/pages/conversations_page.dart';

final themeNotifier = ValueNotifier<ThemeMode>(ThemeMode.dark);

final supabase = Supabase.instance.client;

final navigatorKey = GlobalKey<NavigatorState>();

const String kPresenceChannelName = 'online_users';
const Duration kTypingDelay = Duration(seconds: 3);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  late RealtimeChannel _presenceChannel;
  String? _currentUserId;

  final bool _isTyping = false;
  Timer? _typingTimer;
  final bool _isStatusHidden = false;
  final Map<String, Map<String, String>> _userNames = {};

  @override
  void initState() {
    super.initState();
    _initSupabaseAuthListener();

    if (supabase.auth.currentUser != null) {
      _currentUserId = supabase.auth.currentUser!.id;
      _setupPresenceSubscription();
    }
  }

  @override
  void dispose() {
    _removePresenceSubscription();
    emailController.dispose();
    passwordController.dispose();
    _typingTimer?.cancel();
    super.dispose();
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

  void _initSupabaseAuthListener() {
    supabase.auth.onAuthStateChange.listen((data) async {
      final event = data.event;
      final session = data.session;

      if (event == AuthChangeEvent.passwordRecovery) {
        await Future.delayed(const Duration(seconds: 1));

        navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => const UpdatePasswordPage()),
        );
        return;
      }

      if (event == AuthChangeEvent.signedIn && session != null) {
        _currentUserId = session.user.id;
        _setupPresenceSubscription();
      } else if (event == AuthChangeEvent.signedOut) {
        _removePresenceSubscription();
        _currentUserId = null;
        if (mounted) setState(() {});
      }
    });
  }

  void _setupPresenceSubscription() {
    if (_currentUserId == null) return;

    _presenceChannel = supabase.channel(kPresenceChannelName);
    final presence = _presenceChannel.presence;

    presence.onSync(() {
      final dynamic rawState = presence.state;
      if (rawState is Map) {
        rawState.forEach((key, value) {
          final userId = key.toString();
          final presences = (value is List) ? value : [value];
          for (final p in presences) {
            _loadUserName(userId);
          }
        });
      }
      if (mounted) setState(() {});
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
      await _presenceChannel.track({
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
    } catch (_) {}
    try {
      await supabase.removeChannel(_presenceChannel);
    } catch (_) {}
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
    } catch (e) {
      debugPrint('loadUserName error: $e');
    }
  }

  Future<void> _cadastrarUsuario(BuildContext context) async {
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
        _showSnackBar(context, "Erro inesperado: $e", isError: true);
      }
    }
  }

  Future<void> _resetPassword(BuildContext context) async {
    final email = emailController.text.trim();
    if (email.isEmpty) {
      _showSnackBar(
        context,
        'Por favor, digite seu email no campo acima para recuperar a senha.',
        isError: true,
      );
      return;
    }

    try {
      await supabase.auth.resetPasswordForEmail(
        email,
        redirectTo: 'http://localhost:3000',
      );

      if (!mounted) return;
      _showSnackBar(
        context,
        'Email de recuperação enviado! Verifique sua caixa de entrada.',
        isError: false,
      );
    } catch (e) {
      if (!mounted) return;
      _showSnackBar(context, 'Erro ao enviar email: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, currentMode, _) {
        return StreamBuilder<AuthState>(
          // ...
          stream: supabase.auth.onAuthStateChange,
          builder: (context, snapshot) {
            final authState = snapshot.data;

            if (authState?.event == AuthChangeEvent.passwordRecovery) {
              return MaterialApp(
                navigatorKey: navigatorKey,
                debugShowCheckedModeBanner: false,
                themeMode: currentMode,
                theme: ThemeData(),
                darkTheme: ThemeData(),
                home: const UpdatePasswordPage(),
              );
            }

            final loggedIn = authState?.session != null;

            return MaterialApp(
              navigatorKey: navigatorKey,
              debugShowCheckedModeBanner: false,

              themeMode: currentMode,

              theme: ThemeData(
                brightness: Brightness.light,
                primarySwatch: Colors.blue,
                scaffoldBackgroundColor: const Color(0xFFF1F4FF),
                appBarTheme: const AppBarTheme(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  elevation: 2,
                ),
                inputDecorationTheme: InputDecorationTheme(
                  fillColor: Colors.white,
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),

              darkTheme: ThemeData(
                brightness: Brightness.dark,
                primarySwatch: Colors.blue,
                scaffoldBackgroundColor: const Color(0xFF121212),
                appBarTheme: AppBarTheme(
                  backgroundColor: Colors.grey[900],
                  foregroundColor: Colors.white,
                  elevation: 0,
                ),
                inputDecorationTheme: InputDecorationTheme(
                  fillColor: Colors.grey[800],
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  labelStyle: const TextStyle(color: Colors.grey),
                ),
                textTheme: const TextTheme(
                  bodyMedium: TextStyle(color: Colors.white),
                ),
              ),

              home: loggedIn ? const ConversationsPage() : _buildLoginScreen(),
            );
          },
          // ...
        );
      },
    );
  }

  Widget _buildLoginScreen() {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Icon(
          themeNotifier.value == ThemeMode.dark
              ? Icons.light_mode
              : Icons.dark_mode,
          color: Colors.grey,
        ),
        onPressed: () {
          themeNotifier.value = themeNotifier.value == ThemeMode.dark
              ? ThemeMode.light
              : ThemeMode.dark;
        },
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endTop,

      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Builder(
              builder: (innerContext) {
                final isDark =
                    Theme.of(innerContext).brightness == Brightness.dark;

                return Form(
                  key: _formKey,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.chat_bubble_outline,
                        size: 100,
                        color: Colors.blue,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        "Bem-vindo!",
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 40),

                      CustomInput(
                        controller: emailController,
                        label: "Email",
                        hint: 'seu@email.com',
                        keyboardType: TextInputType.emailAddress,
                        obscureText: false,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'O e-mail não pode ser vazio.';
                          }
                          if (!value.contains('@') || !value.contains('.')) {
                            return 'Formato de e-mail inválido.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      CustomInput(
                        controller: passwordController,
                        label: "Senha",
                        hint: '******',
                        obscureText: true,
                        keyboardType: TextInputType.text,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'A senha não pode ser vazia.';
                          }
                          if (value.length < 6) {
                            return 'A senha deve ter pelo menos 6 caracteres.';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => _resetPassword(innerContext),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(50, 30),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text(
                            'Esqueceu a senha?',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      CustomButton(
                        buttonText: "Entrar",
                        backgroundColor: Colors.blue,
                        onPressed: () async {
                          if (_formKey.currentState!.validate()) {
                            try {
                              await supabase.auth.signInWithPassword(
                                email: emailController.text.trim(),
                                password: passwordController.text.trim(),
                              );
                              if (!mounted) return;
                              _showSnackBar(
                                innerContext,
                                "Login realizado!",
                                isError: false,
                              );
                            } on AuthException catch (e) {
                              if (mounted) {
                                _showSnackBar(
                                  innerContext,
                                  "Erro: ${e.message}",
                                  isError: true,
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                _showSnackBar(
                                  innerContext,
                                  "Erro inesperado.",
                                  isError: true,
                                );
                              }
                            }
                          }
                        },
                      ),

                      const SizedBox(height: 16),

                      CustomTextButton(
                        buttonText: "Criar nova conta",
                        onPressed: () {
                          if (_formKey.currentState!.validate()) {
                            _cadastrarUsuario(innerContext);
                          } else {
                            if (emailController.text.isEmpty ||
                                passwordController.text.isEmpty) {
                              _showSnackBar(
                                innerContext,
                                "Preencha os campos para cadastrar.",
                                isError: true,
                              );
                            }
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

extension on RealtimePresence {
  Future<void> untrack() async {}
  Future<void> track(Map<String, Object?> map) async {}
}
