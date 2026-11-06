import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../services/inbox_service.dart';
import '../groups/group_messages.dart';
import '../../theme/app_colors.dart';

/// "من ساعتين" وهكذا.
String relativeTime(AppLocalizations t, DateTime? at) {
  if (at == null) return t.timeJustNow;
  final d = DateTime.now().difference(at);
  if (d.inMinutes < 1) return t.timeJustNow;
  if (d.inHours < 1) return t.timeMinutesAgo(d.inMinutes);
  if (d.inDays < 1) return t.timeHoursAgo(d.inHours);
  return t.timeDaysAgo(d.inDays);
}

/// أيقونة الجرس وعليها عدد الإشعارات الجديدة.
class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  final _unread = InboxService.instance.unreadCount();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return StreamBuilder<int>(
      stream: _unread,
      builder: (context, snap) {
        final n = snap.data ?? 0;
        return IconButton(
          tooltip: t.notifications,
          onPressed: () => context.push('/notifications'),
          icon: Badge(
            isLabelVisible: n > 0,
            label: Text(n >= InboxService.limit ? '99+' : '$n'),
            child: Icon(n > 0 ? Icons.notifications : Icons.notifications_none),
          ),
        );
      },
    );
  }
}

/// صفحة الإشعارات: الأحدث فوق، والجديد من آخر فتح بخلفية مختلفة.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _items = InboxService.instance.items();

  /// وقت آخر فتح قبل الفتحة دي (عشان نميّز الجديد حتى بعد ما نعلّمه مقروء).
  DateTime? _seenBefore;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    InboxService.instance.seenAt().first.then((seen) {
      if (!mounted) return;
      setState(() {
        _seenBefore = seen;
        _ready = true;
      });
      InboxService.instance.markSeen();
    }, onError: (_) {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    return Scaffold(
      appBar: AppBar(title: Text(t.notifications, style: const TextStyle(fontWeight: FontWeight.w700))),
      body: StreamBuilder<List<InboxItem>>(
        stream: _items,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('${snap.error}'));
          if (!snap.hasData || !_ready) return const Center(child: CircularProgressIndicator());
          final items = snap.data!;
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.notifications_none, size: 56, color: AppColors.textMuted),
                    const SizedBox(height: 12),
                    Text(t.notificationsEmpty, textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted, height: 1.6)),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: items.length + 1,
            separatorBuilder: (_, i) => i < items.length - 1 ? Divider(height: 1, color: AppColors.border) : const SizedBox.shrink(),
            itemBuilder: (context, i) {
              if (i == items.length) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(t.notificationsKeepNote, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                );
              }
              final n = items[i];
              final isNew = n.createdAt == null || _seenBefore == null || n.createdAt!.isAfter(_seenBefore!);
              return Material(
                color: isNew ? AppColors.goldTint : Colors.transparent,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.accent.withValues(alpha: 0.12),
                    child: Icon(_icon(n.type), color: AppColors.accent, size: 20),
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(n.title(lang),
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 8),
                      Text(relativeTime(t, n.createdAt), style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                    ],
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(n.body(lang), style: TextStyle(color: AppColors.text, height: 1.4)),
                        // رسالة من حد: زرار رد لنفس الشخص.
                        if (n.fromUid != null && n.groupId != null)
                          Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: TextButton.icon(
                              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                              onPressed: () => showComposeMessage(
                                context,
                                groupId: n.groupId!,
                                to: n.fromUid!,
                                title: t.replyTo(n.fromName ?? ''),
                              ),
                              icon: const Icon(Icons.reply, size: 18),
                              label: Text(t.reply),
                            ),
                          ),
                      ],
                    ),
                  ),
                  onTap: n.groupId == null ? null : () => context.push('/group/${n.groupId}'),
                ),
              );
            },
          );
        },
      ),
    );
  }

  IconData _icon(String? type) => switch (type) {
        'joined' => Icons.person_add_alt_1,
        'cycle_start' => Icons.autorenew,
        'reminder' => Icons.schedule,
        'late' => Icons.volunteer_activism,
        'khatma' => Icons.celebration,
        'portion' => Icons.add_task,
        'moved' => Icons.swap_horiz,
        'recorded' => Icons.edit_note,
        'message' => Icons.mail_outline,
        _ => Icons.notifications,
      };
}
