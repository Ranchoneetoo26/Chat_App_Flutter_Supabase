import 'package:flutter/material.dart';
import '../pages/profile_page.dart'; // Import da página de perfil

class CustomDrawer extends StatefulWidget {
  const CustomDrawer({super.key});

  @override
  State<CustomDrawer> createState() => _CustomDrawerState();
}

class _CustomDrawerState extends State<CustomDrawer> {
  // Variável local para controlar o switch visualmente por enquanto
  bool isDarkMode = true;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFF1E1E1E), // Fundo escuro
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // --- CABEÇALHO ---
          UserAccountsDrawerHeader(
            decoration: const BoxDecoration(color: Colors.blue),
            accountName: const Text(
              "Bem-vindo",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            // Agora ele vai reconhecer o 'sup' por causa do import lá em cima
            accountEmail: Text(
              sup.auth.currentUser?.email ?? "usuario@email.com",
            ),
            currentAccountPicture: const CircleAvatar(
              backgroundColor: Colors.white,
              child: Icon(Icons.person, size: 40, color: Colors.blue),
            ),
          ),

          // --- MEU PERFIL ---
          ListTile(
            leading: const Icon(Icons.person, color: Colors.white),
            title: const Text(
              'Meu Perfil',
              style: TextStyle(color: Colors.white),
            ),
            onTap: () {
              Navigator.pop(context); // Fecha o menu
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const ProfilePage()),
              );
            },
          ),

          // --- CONVERSAS ---
          ListTile(
            leading: const Icon(Icons.chat_bubble, color: Colors.white),
            title: const Text(
              'Conversas',
              style: TextStyle(color: Colors.white),
            ),
            onTap: () {
              Navigator.pop(context);
              // Adicione navegação se necessário
            },
          ),

          const Divider(color: Colors.grey),

          // --- MODO ESCURO ---
          SwitchListTile(
            secondary: const Icon(Icons.dark_mode, color: Colors.white),
            title: const Text(
              "Modo Escuro",
              style: TextStyle(color: Colors.white),
            ),
            activeColor: Colors.deepPurpleAccent,
            activeTrackColor: Colors.deepPurpleAccent.withOpacity(0.5),
            value: isDarkMode,
            onChanged: (bool value) {
              setState(() {
                isDarkMode = value;
              });
              print("Modo escuro: $value");
            },
          ),

          // --- SAIR ---
          ListTile(
            leading: const Icon(Icons.exit_to_app, color: Colors.redAccent),
            title: const Text(
              'Sair',
              style: TextStyle(color: Colors.redAccent),
            ),
            onTap: () async {
              await sup.auth.signOut();
              if (mounted) {
                Navigator.of(context).pushReplacementNamed('/login');
              }
            },
          ),
        ],
      ),
    );
  }
}
