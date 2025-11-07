import 'package:flutter/material.dart';
import 'package:app/ui/widgets/custom_button.dart';
import 'package:app/ui/widgets/custom_input.dart';
import 'package:app/ui/widgets/custom_text_button.dart';
import 'package:supabase_flutter/supabase_flutter.dart'; // 1. Pacote importado

// TODO: Implementar sistema de rotas das páginas
// TODO: Extrair o código para a login_screen
// TODO:Implementar a register screen
// TODO: Integrar com o Supabase
// TODO: Login Social
// TODO: Implementar awesome_lints

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(

    url: 'COLE_SUA_URL_AQUI', 
    anonKey: 'COLE_SUA_CHAVE_ANON_PUBLIC_AQUI', 
  );

  runApp(MainApp());
}

final supabase = Supabase.instance.client;

class MainApp extends StatelessWidget {
  MainApp({super.key});

  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  void _cadastrarUsuario() async {
    final String email = emailController.text.trim();
    final String password = passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      print("Email ou senha vazios");
      return;
    }

    try {
      
      final AuthResponse res = await supabase.auth.signUp(
        email: email,
        password: password,
      );

      if (res.user != null) {
        print("Usuário cadastrado com sucesso! ID: ${res.user!.id}");
        print("VÁ ATÉ O PAINEL DO SUPABASE > AUTHENTICATION PARA VERIFICAR.");
      }
    } catch (error) {
      print("Erro no cadastro: ${error.toString()}");
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SafeArea(
                child: Padding(
                  padding: EdgeInsets.all(24.0),
                  child: SizedBox(
                    width: constraints.maxWidth > 768
                        ? 768
                        : constraints.maxWidth,
                    child: Column(
                      children: [
                        Image(
                          image: AssetImage('assets/logos/logo_login.png'),
                          height: 280,
                        ),
                        SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: Text('Login', style: TextStyle(fontSize: 20)),
                        ),
                        SizedBox(height: 18),
                        CustomInput(
                          hint: 'Digite seu email',
                          label: 'Email',
                          controller: emailController,
                        ),
                        SizedBox(height: 18),
                        CustomInput(
                          hint: 'Digite sua senha',
                          label: 'Senha',
                          controller: passwordController,
                        ),
                        Align(
                          alignment: AlignmentGeometry.centerRight,
                          child: CustomTextButton(
                            buttonText: 'Esqueci minha senha',
                            onPressed: () {}, // Deixamos vazio por enquanto
                          ),
                        ),
                        SizedBox(height: 18),
                        CustomButton(
                          buttonText: 'Entrar',
                          backgroundColor: Color(0xFF03A9F4),
                          // onPressed: () {}, // AINDA NÃO IMPLEMENTADO
                        ),
                        SizedBox(height: 18),
                        CustomTextButton(
                          buttonText: 'Não tem uma conta? Cadastre-se',
                          onPressed:
                              _cadastrarUsuario, // 5. Chama a função de cadastro
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
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
