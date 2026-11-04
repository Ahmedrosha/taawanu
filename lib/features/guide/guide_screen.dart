import 'package:flutter/material.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../theme/app_colors.dart';
import '../groups/group_board_screen.dart' show segmentSwatch;
import 'guide_content.dart';

/// دليل الاستخدام: أقسام بتتفتح وتتقفل، بالعربي أو الإنجليزي حسب لغة التطبيق.
class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final sections = Localizations.localeOf(context).languageCode == 'en' ? guideEn : guideAr;
    return Scaffold(
      appBar: AppBar(title: Text(t.guideTitle, style: const TextStyle(fontWeight: FontWeight.w700))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
            child: Text(t.guideIntro, style: TextStyle(color: AppColors.textMuted, height: 1.5)),
          ),
          for (final s in sections) _Section(section: s),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.section});

  final GuideSection section;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: AppColors.border)),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Icon(section.icon, color: AppColors.accent),
        title: Text(section.title, style: const TextStyle(fontWeight: FontWeight.w700)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final b in section.blocks) Padding(padding: const EdgeInsets.only(top: 8), child: _block(context, b)),
        ],
      ),
    );
  }

  Widget _block(BuildContext context, GuideBlock b) {
    final base = DefaultTextStyle.of(context).style.copyWith(height: 1.6, fontSize: 14.5);
    switch (b) {
      case GText(:final text):
        return Text.rich(guideSpans(text, base));
      case GNote(:final text):
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColors.goldTint, borderRadius: BorderRadius.circular(12)),
          child: Text.rich(guideSpans(text, base)),
        );
      case GBullets(:final items):
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final i in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsetsDirectional.only(top: 9, end: 8),
                      child: Container(width: 5, height: 5, decoration: BoxDecoration(color: AppColors.accent, shape: BoxShape.circle)),
                    ),
                    Expanded(child: Text.rich(guideSpans(i, base))),
                  ],
                ),
              ),
          ],
        );
      case GTable(:final rows):
        return Container(
          decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(12)),
          child: Column(
            children: [
              for (var k = 0; k < rows.length; k++)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    border: k == 0 ? null : Border(top: BorderSide(color: AppColors.border)),
                  ),
                  child: Row(
                    children: [
                      Expanded(child: Text(rows[k].$1, style: base)),
                      const SizedBox(width: 8),
                      Text(rows[k].$2, style: base.copyWith(fontWeight: FontWeight.w700, color: AppColors.accent)),
                    ],
                  ),
                ),
            ],
          ),
        );
      case GLegend(:final items):
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (status, label) in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    segmentSwatch(status, width: 34, height: 12, fill: status == 'in_progress' ? 0.5 : 1),
                    const SizedBox(width: 10),
                    Expanded(child: Text(label, style: base)),
                  ],
                ),
              ),
          ],
        );
    }
  }
}

/// بيحوّل **عريض** و{i:اسم} لـspans.
TextSpan guideSpans(String text, TextStyle base) {
  final spans = <InlineSpan>[];
  final re = RegExp(r'\*\*(.+?)\*\*|\{i:(\w+)\}');
  var last = 0;
  for (final m in re.allMatches(text)) {
    if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
    if (m.group(1) != null) {
      spans.add(guideSpans(m.group(1)!, base.copyWith(fontWeight: FontWeight.w700)));
    } else {
      final icon = guideIcons[m.group(2)];
      if (icon != null) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Icon(icon, size: 18, color: AppColors.accent),
          ),
        ));
      }
    }
    last = m.end;
  }
  if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
  return TextSpan(style: base, children: spans);
}
