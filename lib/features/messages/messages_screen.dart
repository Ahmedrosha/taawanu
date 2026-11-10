import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../models/group_models.dart';
import '../../services/groups_service.dart';
import '../../services/messages_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/ui.dart';
import '../groups/group_messages.dart' show maxMessageLength;
import '../notifications/notifications_screen.dart' show relativeTime;

/// اسم المحادثة: الشخص، أو "إدارة المجموعة" للعضو العادي.
String conversationTitle(AppLocalizations t, ChatMessage m) =>
    m.withManagers ? t.chatManagersOf(m.groupName) : (m.peerName.isEmpty ? t.noName : m.peerName);

/// أيقونة الرسائل وعليها عدد اللي لسه متقراش.
class MessagesButton extends StatefulWidget {
  const MessagesButton({super.key});

  @override
  State<MessagesButton> createState() => _MessagesButtonState();
}

class _MessagesButtonState extends State<MessagesButton> {
  final _unread = MessagesService.instance.unreadCount();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return StreamBuilder<int>(
      stream: _unread,
      builder: (context, snap) {
        final n = snap.data ?? 0;
        return IconButton(
          tooltip: t.messages,
          onPressed: () => context.push('/messages'),
          icon: Badge(
            isLabelVisible: n > 0,
            label: Text(n >= 100 ? '99+' : '$n'),
            child: Icon(n > 0 ? Icons.chat_bubble : Icons.chat_bubble_outline),
          ),
        );
      },
    );
  }
}

/// قسم الرسائل: قايمة المحادثات، الأحدث فوق.
class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  final _recent = MessagesService.instance.recent();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.messages, style: const TextStyle(fontWeight: FontWeight.w700))),
      body: StreamBuilder<List<ChatMessage>>(
        stream: _recent,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final list = MessagesService.conversations(snap.data!);
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.chat_bubble_outline, size: 56, color: AppColors.textMuted),
                    const SizedBox(height: 12),
                    Text(t.messagesEmpty, textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted, height: 1.6)),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: list.length,
            separatorBuilder: (_, _) => Divider(height: 1, color: AppColors.border),
            itemBuilder: (context, i) {
              final c = list[i];
              final m = c.last;
              final title = conversationTitle(t, m);
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.accent.withValues(alpha: 0.12),
                  child: Icon(m.withManagers ? Icons.shield_outlined : Icons.person_outline, color: AppColors.accent, size: 20),
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 8),
                    Text(relativeTime(t, m.at), style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!m.withManagers) Text(m.groupName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            m.mine ? t.chatYouPrefix(m.text) : m.text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: c.unread > 0 ? FontWeight.w700 : FontWeight.w400),
                          ),
                        ),
                        if (c.unread > 0) ...[
                          const SizedBox(width: 8),
                          Badge(label: Text('${c.unread}')),
                        ],
                      ],
                    ),
                  ],
                ),
                onTap: () => context.push('/messages/${m.thread}'),
              );
            },
          );
        },
      ),
    );
  }
}

/// محادثة واحدة: الرسائل زي الشات، وخانة الرد تحت.
class ThreadScreen extends StatefulWidget {
  const ThreadScreen({super.key, required this.thread});

  final String thread;

  @override
  State<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends State<ThreadScreen> {
  final _recent = MessagesService.instance.recent();
  final _text = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send(ChatMessage ref) async {
    final text = _text.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final ok = await runAction(context, () async {
      final svc = GroupsService.instance;
      Object to = ref.peerUid;
      if (ref.withManagers) {
        // العضو العادي بيرد على الإدارة كلها.
        final List<Member> members = await svc.members(ref.groupId).first;
        to = [for (final m in members) if (m.isManager && m.uid != svc.uid) m.uid];
      }
      await svc.sendMessage(ref.groupId, to, text);
    });
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok) _text.clear();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return StreamBuilder<List<ChatMessage>>(
      stream: _recent,
      builder: (context, snap) {
        final all = snap.data ?? const <ChatMessage>[];
        final msgs = [for (final m in all) if (m.thread == widget.thread) m];
        if (msgs.isNotEmpty) MessagesService.instance.markRead(msgs);
        final ref = msgs.isEmpty ? null : msgs.first;
        return Scaffold(
          appBar: AppBar(
            title: ref == null
                ? Text(t.messages)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(conversationTitle(t, ref), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
                      if (!ref.withManagers) Text(ref.groupName, style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                    ],
                  ),
            actions: [
              if (ref != null)
                IconButton(
                  tooltip: t.openGroup,
                  icon: const Icon(Icons.groups_outlined),
                  onPressed: () => context.push('/group/${ref.groupId}'),
                ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: !snap.hasData
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                        itemCount: msgs.length,
                        itemBuilder: (context, i) => _Bubble(m: msgs[i], showSender: ref?.withManagers ?? false),
                      ),
              ),
              if (ref != null)
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _text,
                            minLines: 1,
                            maxLines: 4,
                            maxLength: maxMessageLength,
                            textInputAction: TextInputAction.newline,
                            decoration: InputDecoration(
                              hintText: ref.withManagers ? t.chatHintManagers : t.chatHint,
                              counterText: '',
                              isDense: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(22)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          tooltip: t.send,
                          onPressed: _sending ? null : () => _send(ref),
                          icon: _sending
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.send),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.m, required this.showSender});

  final ChatMessage m;

  /// في محادثة الإدارة: اسم اللي بعت فوق رسالته.
  final bool showSender;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final mine = m.mine;
    return Align(
      alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        decoration: BoxDecoration(
          color: mine ? AppColors.navy : AppColors.surface,
          border: mine ? null : Border.all(color: AppColors.border),
          borderRadius: BorderRadiusDirectional.only(
            topStart: const Radius.circular(16),
            topEnd: const Radius.circular(16),
            bottomStart: Radius.circular(mine ? 16 : 4),
            bottomEnd: Radius.circular(mine ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!mine && showSender && m.fromName.isNotEmpty)
              Text(m.fromName, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.accent)),
            if (m.type == 'reminder')
              Text(t.chatReminderTag, style: TextStyle(fontSize: 11, color: mine ? Colors.white70 : AppColors.textMuted)),
            Text(m.text, style: TextStyle(color: mine ? Colors.white : AppColors.text, height: 1.4)),
            const SizedBox(height: 2),
            Text(relativeTime(t, m.at), style: TextStyle(fontSize: 10, color: mine ? Colors.white70 : AppColors.textMuted)),
          ],
        ),
      ),
    );
  }
}
