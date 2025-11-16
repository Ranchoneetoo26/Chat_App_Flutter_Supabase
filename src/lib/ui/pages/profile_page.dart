// lib/ui/pages/profile_page.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// import removed: use Supabase.instance.client directly

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  // Removido 'final' para permitir inicialização no initState
  late SupabaseClient supabase;
  late String currentUserId; // Removido 'final'

  // Controllers para editar o nome
  final _usernameController = TextEditingController();
  final _fullNameController = TextEditingController();

  bool _isLoading = true;
  String _profileImageUrl = '';
  String _initialUsername = '';
  String _initialFullName = '';

  @override
  void initState() {
    super.initState();
    // 1. Inicializa o membro 'supabase' e 'currentUserId' aqui.
    supabase = Supabase.instance.client;
    currentUserId = supabase.auth.currentUser!.id;

    // Agora que o ID está inicializado, carregamos o perfil
    _loadProfile();
  }

  // --- Funções de Lógica ---
  Future<void> _loadProfile() async {
    // 1. Buscar o nome completo e username do Supabase Postgres
    // (A tabela deve ser 'profiles' conforme o escopo do projeto)
    try {
      final response = await supabase
      .from('profiles')
      .select('username, full_name, avatar_url')
      .eq('id', currentUserId)
      .single();

  _initialUsername = response['username'] ?? '';
  _initialFullName = response['full_name'] ?? '';
  _profileImageUrl = response['avatar_url'] ?? '';

  _usernameController.text = _initialUsername;

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('loadProfile error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _showSnackBar(context, 'Erro ao carregar perfil: $e', isError: true);
      }
    }
  }

  Future<void> _updateProfile() async {
    // 2. Atualizar o nome completo e username no Supabase Postgres
    if (_usernameController.text.isEmpty || _fullNameController.text.isEmpty) {
      _showSnackBar(
        context,
        'Nome de usuário e nome completo são obrigatórios.',
        isError: true,
      );
      return;
    }

    try {
      await supabase
          .from('profiles')
          .update({
            'username': _usernameController.text.trim(),
            'full_name': _fullNameController.text.trim(),
          })
          .eq('id', currentUserId);

      if (!mounted) return;
      _showSnackBar(context, 'Perfil atualizado com sucesso!', isError: false);
    } catch (e) {
      debugPrint('updateProfile error: $e');
      if (mounted) {
        _showSnackBar(context, 'Erro ao atualizar perfil: $e', isError: true);
      }
    }
  }

  // Função auxiliar de SnackBar (simplificada)
  void _showSnackBar(
    BuildContext context,
    String message, {
    bool isError = false,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Meu Perfil')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 3. Imagem do Perfil (futuro upload)
                  _buildProfileImage(),
                  const SizedBox(height: 30),

                  // 4. Campo para NOME DE USUÁRIO
                  TextFormField(
                    controller: _usernameController,
                    decoration: const InputDecoration(
                      labelText: 'Nome de Usuário',
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 5. Campo para NOME COMPLETO
                  TextFormField(
                    controller: _fullNameController,
                    decoration: const InputDecoration(
                      labelText: 'Nome Completo',
                    ),
                  ),
                  const SizedBox(height: 30),

                  // 6. Botão de Salvar
                  ElevatedButton(
                    onPressed: _updateProfile,
                    child: const Text('Salvar Alterações'),
                  ),
                ],
              ),
            ),
    );
  }

  // Widget para Imagem de Perfil (futuramente com lógica de upload)
  Widget _buildProfileImage() {
    final hasImage = _profileImageUrl.isNotEmpty;
    final initials = (_initialUsername.isNotEmpty ? _initialUsername[0] : '?')
        .toUpperCase();

    return Stack(
      alignment: Alignment.center,
      children: [
        CircleAvatar(
          radius: 60,
          backgroundColor: Colors.blueGrey,
          backgroundImage: hasImage ? NetworkImage(_profileImageUrl) : null,
          child: hasImage
              ? null
              : Text(
                  initials,
                  style: const TextStyle(fontSize: 40, color: Colors.white),
                ),
        ),
        // Ícone de Câmera/Edição (para o próximo passo de upload)
        Positioned(
          bottom: 0,
          right: 0,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.blue,
              borderRadius: BorderRadius.circular(15),
            ),
            child: IconButton(
              icon: const Icon(Icons.edit, color: Colors.white, size: 20),
              onPressed: () {
                // TODO: Implementar upload de imagem (Próxima tarefa)
                _showSnackBar(
                  context,
                  'Funcionalidade de upload será implementada a seguir.',
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
