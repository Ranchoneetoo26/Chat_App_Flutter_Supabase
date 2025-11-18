import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  String? _avatarUrl;
  String _userName = "Carregando...";
  String _userEmail = "";

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    setState(() {
      _userEmail = user.email ?? "";
    });

    try {
      final data = await supabase
          .from('profiles')
          .select('full_name, avatar_url')
          .eq('id', user.id)
          .maybeSingle();

      if (data == null) return;

      setState(() {
        _userName = data['full_name'] ?? "Usuário";
      });

      final avatarPath = data['avatar_url'] as String?;
      if (avatarPath != null && avatarPath.isNotEmpty) {
        final url = await supabase.storage
            .from('profile_pictures')
            .createSignedUrl(avatarPath, 3600);

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
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          UserAccountsDrawerHeader(
            decoration: const BoxDecoration(color: Colors.blue),
            accountName: Text(
              _userName,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            accountEmail: Text(_userEmail),
            currentAccountPicture: CircleAvatar(
              backgroundColor: Colors.white,

              backgroundImage: _avatarUrl != null && _avatarUrl!.isNotEmpty
                  ? NetworkImage(_avatarUrl!)
                  : null,
              child: (_avatarUrl == null || _avatarUrl!.isEmpty)
                  ? const Icon(Icons.person, size: 40, color: Colors.blue)
                  : null,
            ),
          ),

          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('Meu Perfil'),
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const ProfilePage()),
              );
            },
          ),

          ListTile(
            leading: const Icon(Icons.chat_bubble),
            title: const Text('Conversas'),
            onTap: () {
              Navigator.pop(context);

              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const ConversationsPage()),
              );
            },
          ),

          const Divider(),

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

          ListTile(
            leading: const Icon(Icons.exit_to_app, color: Colors.redAccent),
            title: const Text(
              'Sair',
              style: TextStyle(color: Colors.redAccent),
            ),
            onTap: () async {
              Navigator.pop(context);

              Navigator.of(context).popUntil((route) => route.isFirst);

              await supabase.auth.signOut();
            },
          ),
        ],
      ),
    );
  }
}
