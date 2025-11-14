import 'package:flutter/material.dart';

class CustomInput extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final TextInputType keyboardType;
  final bool obscureText;
  // 1. NOVO: Adicione o parâmetro validator
  final FormFieldValidator<String>? validator;

  const CustomInput({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    this.keyboardType = TextInputType.text,
    this.obscureText = false,
    this.validator, // 2. NOVO: Adicione ao construtor
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      // 3. Mude de TextField para TextFormField
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      // 4. Use o parâmetro validator aqui
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.0)),
        // Adicione um padding ou use contentPadding para melhor visual
        contentPadding: const EdgeInsets.symmetric(
          vertical: 16.0,
          horizontal: 12.0,
        ),
      ),
    );
  }
}
