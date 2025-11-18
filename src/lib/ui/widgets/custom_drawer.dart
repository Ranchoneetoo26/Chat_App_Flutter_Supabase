import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Certifique-se que os caminhos dos imports estão corretos no seu projeto
import '../../main.dart';
import '../pages/profile_page.dart';
import '../pages/conversations_page.dart';

class CustomDrawer extends StatefulWidget {
  const CustomDrawer({super.key});

  @override
  State<CustomDrawer> createState() => _CustomDrawerState();
}

class _CustomDrawerState extends State<CustomDrawer> {
  final supabase = Supabase.instance.client;

  // Variáveis de estado para exibir na UI
  String? _avatarUrl;
  String _userName = "Carregando...";
  String _userEmail = "";

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  /// Busca os dados do perfil no Supabase para preencher o cabeçalho
  Future<void> _loadProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    setState(() {
      _userEmail = user.email ?? "";
    });

    try {
      // Busca nome e caminho da foto na tabela 'profiles'
      final data = await supabase
          .from('profiles')
          .select('full_name, avatar_url')
          .eq('id', user.id)
          .maybeSingle();

      if (data == null) return;

      setState(() {
        _userName = data['full_name'] ?? "Usuário";
      });

      // Se tiver foto, gera a URL assinada
      final avatarPath = data['avatar_url'] as String?;
      if (avatarPath != null && avatarPath.isNotEmpty) {
        final url = await supabase.storage
            .from('profile_pictures')
            .createSignedUrl(avatarPath, 3600); // URL válida por 1h

        if (mounted) {
          setState(() {
            _avatarUrl = url;
          });
        }
      }
    } catch (e) {
      debugPrint('Erro ao carregar perfil no drawer: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      // O Drawer agora respeita o tema do sistema (sem cor de fundo fixa)
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // --- CABEÇALHO AZUL ---
          UserAccountsDrawerHeader(
            decoration: const BoxDecoration(color: Colors.blue),
            accountName: Text(
              _userName,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            accountEmail: Text(_userEmail),
            currentAccountPicture: CircleAvatar(
              backgroundColor: Colors.white,
              // Se tiver URL, usa NetworkImage, senão usa ícone padrão
              backgroundImage: _avatarUrl != null && _avatarUrl!.isNotEmpty
                  ? NetworkImage(_avatarUrl!)
                  : null,
              child: (_avatarUrl == null || _avatarUrl!.isEmpty)
                  ? const Icon(Icons.person, size: 40, color: Colors.blue)
                  : null,
            ),
          ),

          // --- ITEM: MEU PERFIL ---
          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('Meu Perfil'),
            onTap: () {
              Navigator.pop(context); // Fecha o menu
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const ProfilePage()),
              );
            },
          ),

          // --- ITEM: CONVERSAS ---
          ListTile(
            leading: const Icon(Icons.chat_bubble),
            title: const Text('Conversas'),
            onTap: () {
              Navigator.pop(context);
              // Substitui a rota para não empilhar conversas sobre conversas
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const ConversationsPage()),
              );
            },
          ),

          const Divider(),

          // --- ITEM: MODO ESCURO ---
          ValueListenableBuilder<ThemeMode>(
            valueListenable: themeNotifier,
            builder: (_, mode, __) {
              return SwitchListTile(
                secondary: Icon(
                  mode == ThemeMode.dark ? Icons.dark_mode : Icons.light_mode,
                ),
                title: const Text("Modo Escuro"),
                value: mode == ThemeMode.dark,
                onChanged: (bool isDark) {
                  themeNotifier.value = isDark
                      ? ThemeMode.dark
                      : ThemeMode.light;
                },
              );
            },
          ),

          const Divider(),

          // --- ITEM: SAIR ---
          ListTile(
            leading: const Icon(Icons.exit_to_app, color: Colors.redAccent),
            title: const Text(
              'Sair',
              style: TextStyle(color: Colors.redAccent),
            ),
            onTap: () async {
              // 1. Fecha o Drawer visualmente
              Navigator.pop(context);

              // 2. Volta a navegação até a raiz (evita erro de tela vermelha)
              Navigator.of(context).popUntil((route) => route.isFirst);

              // 3. Desloga do Supabase
              await supabase.auth.signOut();
            },
          ),
        ],
      ),
    );
  }
}
