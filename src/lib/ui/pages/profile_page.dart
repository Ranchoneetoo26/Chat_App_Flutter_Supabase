// lib/ui/pages/profile_page.dart

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late SupabaseClient supabase;
  late String currentUserId;

  final _usernameController = TextEditingController();
  final _fullNameController = TextEditingController();

  bool _isLoading = true;
  String _profileImageUrl = ''; // Guarda a URL assinada
  String _initialUsername = '';
  String _initialFullName = '';

  XFile? _selectedImage;

  @override
  void initState() {
    super.initState();
    supabase = Supabase.instance.client;
    currentUserId = supabase.auth.currentUser!.id;
    _loadProfile();
  }

  // --- Funções de Lógica ---

  Future<void> _loadProfile() async {
    // Garante que o estado de loading esteja ativo ao carregar
    if (!_isLoading) {
      if (mounted) setState(() => _isLoading = true);
    }

    try {
      final response = await supabase
          .from('profiles')
          .select('username, full_name, avatar_url') // avatar_url é o CAMINHO
          .eq('id', currentUserId)
          .single();

      _initialUsername = response['username'] ?? '';
      _initialFullName = response['full_name'] ?? '';
      _usernameController.text = _initialUsername;
      _fullNameController.text = _initialFullName;

      final avatarPath = response['avatar_url'] as String?;

      // Limpa a URL antiga antes de buscar uma nova
      if (mounted) setState(() => _profileImageUrl = '');

      if (avatarPath != null && avatarPath.isNotEmpty) {
        try {
          // Gera a URL assinada (válida por 1 hora)
          final signedUrl = await supabase.storage
              .from('profile_pictures')
              .createSignedUrl(avatarPath, 3600);

          if (mounted) {
            setState(() {
              _profileImageUrl = signedUrl; // Salva a URL assinada
            });
          }
        } catch (e) {
          debugPrint('Erro ao gerar URL assinada: $e');
          if (mounted) {
            _showSnackBar(context, 'Falha ao carregar imagem', isError: true);
          }
        }
      }
    } catch (e) {
      debugPrint('loadProfile error: $e');
      if (mounted) {
        _showSnackBar(context, 'Erro ao carregar perfil: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 50,
    );

    if (pickedFile != null) {
      setState(() {
        _selectedImage = pickedFile;
      });
    }
  }

  Future<void> _updateProfile() async {
    if (_usernameController.text.isEmpty || _fullNameController.text.isEmpty) {
      _showSnackBar(context, 'Nome de usuário e nome completo são obrigatórios.',
          isError: true);
      return;
    }

    setState(() => _isLoading = true);
    String? newAvatarPath;

    try {
      if (_selectedImage != null) {
        final imageFile = _selectedImage!;
        final fileExtension = imageFile.name.split('.').last;
        newAvatarPath = '$currentUserId/profile.$fileExtension';
        final imageBytes = await imageFile.readAsBytes();

        await supabase.storage.from('profile_pictures').uploadBinary(
              newAvatarPath,
              imageBytes,
              fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
            );
      }

      final username = _usernameController.text.trim();
      final fullName = _fullNameController.text.trim();

      final updates = {
        'username': username,
        'full_name': fullName,
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (newAvatarPath != null) {
        updates['avatar_url'] = newAvatarPath;
      }

      await supabase.from('profiles').update(updates).eq('id', currentUserId);

      if (!mounted) return;
      _showSnackBar(context, 'Perfil atualizado com sucesso!', isError: false);

      // Limpa a imagem local para forçar o recarregamento
      setState(() {
        _selectedImage = null;
      });

      // Recarrega o perfil para obter a *nova* URL assinada
      await _loadProfile();
    } catch (e) {
      debugPrint('updateProfile error: $e');
      if (mounted) {
        _showSnackBar(context, 'Erro ao atualizar perfil: $e', isError: true);
      }
      setState(() => _isLoading = false); // Garante que o loading pare em caso de erro
    }
  }

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

  // --- Métodos de Build ---

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
                  _buildProfileImage(), // O widget do avatar
                  const SizedBox(height: 30),
                  TextFormField(
                    controller: _usernameController,
                    decoration: const InputDecoration(
                      labelText: 'Nome de Usuário',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _fullNameController,
                    decoration: const InputDecoration(
                      labelText: 'Nome Completo',
                    ),
                  ),
                  const SizedBox(height: 30),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _updateProfile, // Desativa se estiver carregando
                    child: const Text('Salvar Alterações'),
                  ),
                ],
              ),
            ),
    );
  }

  /// Widget para Imagem de Perfil (Versão com correção da Asserção)
  Widget _buildProfileImage() {
    final hasLocalImage = _selectedImage != null;
    final hasRemoteImage = _profileImageUrl.isNotEmpty;

    final initials = (_initialUsername.isNotEmpty ? _initialUsername[0] : '?')
        .toUpperCase();

    ImageProvider? backgroundImage;
    String? imageKey;

    if (hasLocalImage) {
      backgroundImage = NetworkImage(_selectedImage!.path); // Blob local
      imageKey = _selectedImage!.path;
    } else if (hasRemoteImage) {
      backgroundImage = NetworkImage(_profileImageUrl); // URL Assinada do Supabase
      imageKey = _profileImageUrl;
    } else {
      backgroundImage = null;
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        CircleAvatar(
          // A Key força o Flutter a recriar este widget quando a URL mudar,
          // vencendo o cache do navegador.
          key: ValueKey<String>(imageKey ?? 'no_image'),
          radius: 60,
          backgroundColor: Colors.blueGrey,
          backgroundImage: backgroundImage,

          // CORREÇÃO: Só adiciona o manipulador de erro SE houver uma imagem
          onBackgroundImageError: backgroundImage != null
              ? (exception, stackTrace) {
                  debugPrint("Erro ao carregar imagem: $exception");
                  if (mounted) {
                    setState(() => _profileImageUrl = '');
                  }
                }
              : null, // Se não há imagem, não há manipulador de erro

          // O 'child' (iniciais) só aparece se o 'backgroundImage' for nulo
          child: (backgroundImage == null)
              ? Text(
                  initials,
                  style: const TextStyle(fontSize: 40, color: Colors.white),
                )
              : null,
        ),
        // Ícone de Câmera/Edição
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
              onPressed: _pickImage,
            ),
          ),
        ),
      ],
    );
  }
}