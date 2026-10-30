import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../services/quran_repository.dart';
import '../theme/app_colors.dart';

/// عناصر واجهة مشتركة بين الشاشات.

class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(16)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700));
  }
}

class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.value, required this.label, this.onDark = false});

  final String value;
  final String label;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: onDark ? Colors.white : AppColors.navy),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: onDark ? const Color(0xFFDBEAFE) : AppColors.textMuted),
        ),
      ],
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.color, this.light = false});

  final String label;
  final Color color;
  final bool light;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: light ? AppColors.sky : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

class ProgressLine extends StatelessWidget {
  const ProgressLine({super.key, required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: value.clamp(0, 1),
        minHeight: 8,
        backgroundColor: const Color(0xFFE2E8F0),
        color: AppColors.blue,
      ),
    );
  }
}

class InfoBanner extends StatelessWidget {
  const InfoBanner({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFDF6E3),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.gold),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, color: Color(0xFF8A6A14)),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF5C4708)))),
        ],
      ),
    );
  }
}

class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, this.photoUrl, this.size = 40});

  final String name;
  final String? photoUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '؟' : name.trim().characters.first;
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: AppColors.sky,
      foregroundImage: photoUrl != null ? NetworkImage(photoUrl!) : null,
      child: Text(initial, style: TextStyle(color: AppColors.navy, fontWeight: FontWeight.w700, fontSize: size * 0.4)),
    );
  }
}

/// "من البقرة ١ لحد البقرة ١٤١" تحت اسم الورد.
class RangeAyahsText extends StatelessWidget {
  const RangeAyahsText({super.key, required this.from, required this.to});

  final int from;
  final int to;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    return FutureBuilder<QuranData>(
      future: QuranRepository.instance.load(),
      builder: (context, snap) {
        final q = snap.data;
        if (q == null) return const SizedBox(height: 18);
        return Text(rangeAyahs(t, q, locale, from, to), style: const TextStyle(fontSize: 13, color: AppColors.textMuted));
      },
    );
  }
}

class LoadingScaffold extends StatelessWidget {
  const LoadingScaffold({super.key});

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class ErrorScaffold extends StatelessWidget {
  const ErrorScaffold({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(message, textAlign: TextAlign.center))),
      );
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String body,
  bool destructive = false,
}) async {
  final t = AppLocalizations.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.cancel)),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(t.confirm, style: TextStyle(color: destructive ? AppColors.statusLate : AppColors.navy, fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// بينفذ عملية على السيرفر، وبيعرض رسالة لو فشلت. بيرجّع true لو نجحت.
Future<bool> runAction(BuildContext context, Future<void> Function() action, {String? success}) async {
  final t = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
    if (success != null) messenger.showSnackBar(SnackBar(content: Text(success)));
    return true;
  } on FirebaseFunctionsException catch (e) {
    debugPrint('Action failed: ${e.code} ${e.message}');
    messenger.showSnackBar(SnackBar(content: Text(_friendly(t, e.code))));
  } catch (e) {
    debugPrint('Action failed: $e');
    messenger.showSnackBar(SnackBar(content: Text(t.actionFailed)));
  }
  return false;
}

String _friendly(AppLocalizations t, String code) => switch (code) {
      'not-found' || 'deadline-exceeded' => t.inviteInvalid,
      'resource-exhausted' => t.groupFull,
      _ => t.actionFailed,
    };
