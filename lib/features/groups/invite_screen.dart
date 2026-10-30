import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../models/group_models.dart';
import '../../models/group_options.dart';
import '../../services/groups_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/ui.dart';

class InviteScreen extends StatefulWidget {
  const InviteScreen({super.key, required this.group});

  final Group group;

  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  int _days = 7;
  int? _maxUses; // null = على قد الخانات
  String? _link;
  bool _busy = false;

  Future<void> _create() async {
    setState(() => _busy = true);
    await runAction(context, () async {
      final url = await GroupsService.instance.createInvite(widget.group.id, days: _days, maxUses: _maxUses);
      if (mounted) setState(() => _link = url);
    });
    if (mounted) setState(() => _busy = false);
  }

  String _message(AppLocalizations t) =>
      t.inviteMessage(widget.group.name, wardLabel(t, widget.group.wardQuarters), _link ?? '');

  Future<void> _whatsApp(AppLocalizations t) async {
    final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(_message(t))}');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      await _copy(t);
    }
  }

  Future<void> _copy(AppLocalizations t) async {
    await Clipboard.setData(ClipboardData(text: _message(t)));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.copied)));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final g = widget.group;
    final free = g.slots - g.memberCount;
    return Scaffold(
      appBar: AppBar(title: Text(t.inviteTitle, style: const TextStyle(fontWeight: FontWeight.w700))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          AppCard(
            child: Row(
              children: [
                Expanded(child: Text(g.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17))),
                StatusPill(label: t.freeSlots(free), color: AppColors.navy, light: true),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(t.linkValidity, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: 1, label: Text(t.days1)),
              ButtonSegment(value: 7, label: Text(t.days7)),
              ButtonSegment(value: 30, label: Text(t.days30)),
            ],
            selected: {_days},
            onSelectionChanged: (s) => setState(() {
              _days = s.first;
              _link = null;
            }),
          ),
          const SizedBox(height: 16),
          Text(t.maxUses, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: 1, label: Text(t.usesOne)),
              ButtonSegment(value: 5, label: Text(t.usesFive)),
              ButtonSegment(value: 0, label: Text(t.usesSlots)),
            ],
            selected: {_maxUses ?? 0},
            onSelectionChanged: (s) => setState(() {
              _maxUses = s.first == 0 ? null : s.first;
              _link = null;
            }),
          ),
          const SizedBox(height: 24),
          if (_link == null)
            FilledButton(onPressed: _busy ? null : _create, child: Text(t.createLink))
          else ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFDCF8C6),
                borderRadius: BorderRadius.circular(16),
              ),
              child: SelectableText(_message(t), style: const TextStyle(height: 1.7)),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _whatsApp(t),
              icon: const Icon(Icons.send),
              label: Text(t.sendWhatsApp),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(onPressed: () => _copy(t), icon: const Icon(Icons.copy), label: Text(t.copyLink)),
          ],
          const SizedBox(height: 20),
          if (g.isPrivate)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.sky, borderRadius: BorderRadius.circular(14)),
              child: Text(t.privateInviteNote, style: const TextStyle(color: AppColors.navy)),
            ),
        ],
      ),
    );
  }
}
