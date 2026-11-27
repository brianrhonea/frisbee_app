import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../themes/theme.dart';

/// The one text box (C10): always a visible [label] (a hint is not a label),
/// optional [hint] and [helper] text, and an [errorText] that says what is
/// wrong in words.
///
/// * The outline is the guide's input border (`border2`, 3:1 against the
///   page and card), thickening to the accent when focused and to the
///   error colour on an error.
/// * At least 48 px tall; multi-line boxes ([maxLines] above 1) grow.
/// * An error is announced to screen readers when it appears.
///
/// Website counterpart: `TextField` (apps/web).
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.label,
    this.controller,
    this.hint,
    this.helper,
    this.errorText,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.inputFormatters,
    this.maxLines = 1,
    this.maxLength,
    this.enabled = true,
    this.autofocus = false,
    this.focusNode,
    this.prefixIcon,
    this.suffix,
    this.onChanged,
    this.onSubmitted,
  });

  final String label;
  final TextEditingController? controller;
  final String? hint;
  final String? helper;

  /// Shown in the error colour with an icon; null for no error.
  final String? errorText;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;
  final int maxLines;
  final int? maxLength;
  final bool enabled;
  final bool autofocus;
  final FocusNode? focusNode;
  final IconData? prefixIcon;

  /// At the end of the box, e.g. a show/hide password button.
  final Widget? suffix;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  OutlineInputBorder _border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: BorderSide(color: color, width: width),
      );

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final field = TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      autofocus: autofocus,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      autofillHints: autofillHints,
      inputFormatters: inputFormatters,
      maxLines: maxLines,
      minLines: 1,
      maxLength: maxLength,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      style: TextStyle(fontSize: 15, color: c.ink),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helper,
        helperMaxLines: 3,
        // The words say it; the icon backs them up.
        error: errorText == null
            ? null
            : Row(
                children: [
                  Icon(Icons.error_outline, size: 16, color: c.error),
                  const SizedBox(width: AppSpace.xs),
                  Expanded(
                    child: Text(
                      errorText!,
                      style: TextStyle(color: c.error, fontSize: 12),
                    ),
                  ),
                ],
              ),
        prefixIcon: prefixIcon == null
            ? null
            : Icon(prefixIcon, size: 20, color: c.muted),
        suffixIcon: suffix,
        counterText: maxLength == null ? '' : null,
        constraints: const BoxConstraints(minHeight: 48),
        border: _border(c.border2),
        enabledBorder: _border(c.border2),
        disabledBorder: _border(c.border),
        focusedBorder: _border(c.accent, 2),
        errorBorder: _border(c.error, 1.5),
        focusedErrorBorder: _border(c.error, 2),
      ),
    );
    if (errorText == null) return field;
    return Semantics(liveRegion: true, child: field);
  }
}
