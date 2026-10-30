import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../models/group_models.dart';
import '../../models/group_options.dart';
import '../../services/groups_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/logo_mark.dart';
import '../../widgets/segment_picker.dart';
import '../../widgets/ui.dart';

/// الانضمام: برابط دعوة (code) لمجموعة خاصة، أو بمعرّف مجموعة عامة (publicGroupId).
class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key, this.code, this.publicGroupId});

  final String? code;
  final String? publicGroupId;

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  late Future<GroupPreview> _preview = _load();
  bool _busy = false;
  /// الجزء اللي العضو اختاره (null = أول جزء فاضي).
  int? _segment;

  Future<GroupPreview> _load() {
    final svc = GroupsService.instance;
    return widget.publicGroupId != null ? svc.previewPublic(widget.publicGroupId!) : svc.previewInvite(widget.code!);
  }

  Future<void> _pick(GroupPreview p) async {
    final seg = await showSegmentPicker(
      context,
      wardQuarters: p.wardQuarters,
      slots: p.slots,
      selected: _segment ?? p.firstFreeSegment,
      taken: p.takenSegments,
    );
    if (seg != null && mounted) setState(() => _segment = seg);
  }

  Future<void> _join(GroupPreview p) async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final segment = _segment ?? p.firstFreeSegment;
    setState(() => _busy = true);
    String? groupId;
    var ok = false;
    try {
      final svc = GroupsService.instance;
      groupId = widget.publicGroupId != null
          ? await svc.joinPublic(p.groupId, segment: segment)
          : await svc.join(widget.code!, segment: segment);
      ok = true;
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'already-exists') {
        // حد سبقه للجزء ده: نحدّث المحجوز ويختار تاني.
        messenger.showSnackBar(SnackBar(content: Text(t.segmentTaken)));
        if (mounted) {
          setState(() {
            _segment = null;
            _preview = _load();
          });
        }
      } else {
        messenger.showSnackBar(SnackBar(content: Text(t.actionFailed)));
      }
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(t.actionFailed)));
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok && groupId != null) {
      context.go('/groups');
      context.push('/group/$groupId');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(backgroundColor: AppColors.navy, foregroundColor: Colors.white),
      body: FutureBuilder<GroupPreview>(
        future: _preview,
        builder: (context, snap) {
          if (snap.hasError) {
            return _Message(
              text: t.inviteInvalid,
              action: TextButton(
                onPressed: () => setState(() => _preview = _load()),
                child: Text(t.retry, style: const TextStyle(color: Colors.white)),
              ),
            );
          }
          final p = snap.data;
          if (p == null) return const Center(child: CircularProgressIndicator(color: Colors.white));
          final unit = cycleUnitLabel(t, CycleUnit.values.byName(p.cycleUnit));
          final cycle = p.cycleCount == 1 ? unit : '${p.cycleCount} $unit';
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
                child: Column(
                  children: [
                    const LogoMark.onDark(size: 72),
                    const SizedBox(height: 14),
                    if (p.code != null)
                      Text(t.invitedBy(p.adminName), style: const TextStyle(color: Color(0xFFDBEAFE))),
                    const SizedBox(height: 6),
                    Text(p.name, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(p.type == 'private' ? Icons.lock_outline : Icons.public, size: 16, color: const Color(0xFFDBEAFE)),
                        const SizedBox(width: 6),
                        Text(p.type == 'private' ? t.groupTypePrivate : t.groupTypePublic, style: const TextStyle(color: Color(0xFFDBEAFE))),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: AppCard(child: StatTile(value: wardLabel(t, p.wardQuarters), label: t.wardWord))),
                          const SizedBox(width: 10),
                          Expanded(child: AppCard(child: StatTile(value: cycle, label: t.cycleWord))),
                          const SizedBox(width: 10),
                          Expanded(child: AppCard(child: StatTile(value: '${p.memberCount}/${p.slots}', label: t.membersWord))),
                        ],
                      ),
                      if (!p.alreadyMember && p.memberCount < p.slots) ...[
                        const SizedBox(height: 20),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(t.yourStartLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(height: 4),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            p.status == 'active' ? t.yourStartHintActive : t.yourStartHint,
                            style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SegmentChoiceTile(
                          label: segmentLabel(t, _segment ?? p.firstFreeSegment ?? 0, p.wardQuarters),
                          onTap: _busy ? null : () => _pick(p),
                        ),
                      ],
                      const Spacer(),
                      if (p.alreadyMember) ...[
                        Text(t.alreadyMember, style: const TextStyle(color: AppColors.textMuted)),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: () {
                            context.go('/groups');
                            context.push('/group/${p.groupId}');
                          },
                          child: Text(t.openGroup),
                        ),
                      ] else if (p.memberCount >= p.slots)
                        Text(t.groupFull, style: const TextStyle(color: AppColors.statusLate, fontWeight: FontWeight.w600))
                      else
                        FilledButton(onPressed: _busy ? null : () => _join(p), child: Text(t.joinGroup)),
                      const SizedBox(height: 8),
                      TextButton(onPressed: () => context.go('/home'), child: Text(t.notNow)),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, required this.action});

  final String text;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LogoMark.onDark(size: 64),
            const SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16)),
            const SizedBox(height: 12),
            action,
          ],
        ),
      ),
    );
  }
}

/// نافذة "انضم برابط أو كود" من تبويب مجموعاتي.
Future<void> showJoinWithCode(BuildContext context) async {
  final t = AppLocalizations.of(context);
  final controller = TextEditingController();
  final code = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(t.joinWithCode),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(hintText: t.pasteLinkHint),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
        TextButton(onPressed: () => Navigator.pop(context, controller.text), child: Text(t.continueText)),
      ],
    ),
  );
  final cleaned = _extractCode(code ?? '');
  if (cleaned == null || !context.mounted) return;
  context.push('/join/$cleaned');
}

/// بيطلّع الكود من الرابط كله أو من الكود نفسه.
String? _extractCode(String raw) {
  final last = raw.trim().split('/').where((s) => s.isNotEmpty).lastOrNull ?? '';
  final code = last.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
  return code.length == 8 ? code : null;
}
