import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';

/// خانة كتابة اسم (اسمي أو اسم عضو). بترجع الاسم بعد تنضيفه، أو null لو اتلغى أو مفيش تغيير.
Future<String?> showNameDialog(BuildContext context, {required String title, String current = '', String? hint}) async {
  final t = AppLocalizations.of(context);
  final controller = TextEditingController(text: current);
  final value = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 60,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(hintText: hint ?? t.yourNameHint),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
        TextButton(onPressed: () => Navigator.pop(context, controller.text), child: Text(t.save)),
      ],
    ),
  );
  controller.dispose();
  final name = value?.trim().replaceAll(RegExp(r'\s+'), ' ') ?? '';
  if (name.isEmpty || name == current.trim()) return null;
  return name;
}
