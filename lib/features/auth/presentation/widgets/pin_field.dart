import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Numeric, obscured PIN input with a 4-6 digit limit.
class PinField extends StatelessWidget {
  const PinField({
    super.key,
    required this.controller,
    required this.label,
    this.autofocus = false,
    this.enabled = true,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final bool autofocus;
  final bool enabled;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      enabled: enabled,
      obscureText: true,
      keyboardType: TextInputType.number,
      maxLength: 6,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(6),
      ],
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        counterText: '',
      ),
    );
  }
}