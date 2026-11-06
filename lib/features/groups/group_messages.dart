import 'package:flutter/material.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../models/group_models.dart';
import '../../services/groups_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/ui.dart';

const maxMessageLength = 300;

/// شاشة كتابة رسالة. [presets]: رسايل جاهزة يختار منها (والأخيرة دايمًا "اكتب بنفسك").
/// [to]: uid أو قايمة، أو 'late' لتذكير المتأخرين.
Future<void> showComposeMessage(
  BuildContext context, {
  required String groupId,
  required Object to,
  required String title,
  String? subtitle,
  List<(String, String)> presets = const [],
}) async {
  final t = AppLocalizations.of(context);
  final text = TextEditingController(text: presets.isEmpty ? '' : presets.first.$2);
  var preset = presets.isEmpty ? -1 : 0;
  final send = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setSheet) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
              ],
              if (presets.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (var i = 0; i <= presets.length; i++)
                      ChoiceChip(
                        label: Text(i < presets.length ? presets[i].$1 : t.writeYourOwn),
                        selected: preset == i,
                        onSelected: (_) => setSheet(() {
                          preset = i;
                          text.text = i < presets.length ? presets[i].$2 : '';
                        }),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: text,
                autofocus: presets.isEmpty,
                minLines: 3,
                maxLines: 6,
                maxLength: maxMessageLength,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(hintText: t.messageHint, border: const OutlineInputBorder()),
                onChanged: (_) => setSheet(() {}),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: text.text.trim().isEmpty ? null : () => Navigator.pop(context, true),
                icon: const Icon(Icons.send),
                label: Text(to == 'late' ? t.sendReminder : t.send),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  final body = text.text.trim();
  text.dispose();
  if (send != true || body.isEmpty || !context.mounted) return;
  var sent = 0;
  final ok = await runAction(context, () async => sent = await GroupsService.instance.sendMessage(groupId, to, body));
  if (ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.messageSent(sent))));
  }
}

/// تذكير المتأخرين: رسايل جاهزة فيها الوقت الباقي.
Future<void> showLateReminder(BuildContext context, {required Group group, required int lateCount, DateTime? endsAt}) {
  final t = AppLocalizations.of(context);
  final left = endsAt?.difference(DateTime.now());
  final leftText = left == null || left.isNegative
      ? null
      : left.inDays >= 1
          ? t.daysLeft(left.inDays)
          : t.hoursLeft(left.inHours.clamp(1, 24));
  return showComposeMessage(
    context,
    groupId: group.id,
    to: 'late',
    title: t.remindLate,
    subtitle: t.remindLateTo(lateCount),
    presets: [
      (t.presetTimeShort, t.presetTimeShortBody(leftText ?? t.littleTime)),
      (t.presetEncourage, t.presetEncourageBody),
    ],
  );
}

/// العضو يراسل الإدارة: يختار الأدمن أو مساعد.
Future<void> showContactManagers(BuildContext context, {required Group group, required List<Member> members, required String? myUid}) async {
  final t = AppLocalizations.of(context);
  final managers = members.where((m) => m.isManager && m.uid != myUid).toList()
    ..sort((a, b) => (a.isAdmin ? 0 : 1).compareTo(b.isAdmin ? 0 : 1));
  if (managers.isEmpty) return;
  Member? target = managers.length == 1 ? managers.first : null;
  target ??= await showModalBottomSheet<Member>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(title: Text(t.contactManagers, style: const TextStyle(fontWeight: FontWeight.w700))),
          for (final m in managers)
            ListTile(
              leading: Avatar(name: m.name, photoUrl: m.photoUrl),
              title: Text(m.name),
              subtitle: Text(m.isAdmin ? t.roleAdmin : t.roleAssistant),
              onTap: () => Navigator.pop(context, m),
            ),
        ],
      ),
    ),
  );
  if (target == null || !context.mounted) return;
  await showComposeMessage(context, groupId: group.id, to: target.uid, title: t.messageTo(target.name));
}
