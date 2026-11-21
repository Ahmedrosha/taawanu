import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../models/group_models.dart';
import '../../services/groups_service.dart';
import '../../services/quran_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/ui.dart';

/// عضو لسه مخلصش ورده في الدورة.
class NotReadEntry {
  const NotReadEntry({required this.name, required this.range, required this.read, required this.total, this.volunteer});
  final String name;
  final String range;
  final int read;
  final int total;

  /// دورة فاتت: اسم اللي اتطوع بالورد بداله.
  final String? volunteer;
}

/// اللي لسه مخلصوش (الدورة الحالية) أو اللي اتأخروا (دورة فاتت)، بترتيب أوراده.
List<NotReadEntry> notReadEntries(AppLocalizations t, Group g, Cycle c, List<Member> members, List<Portion> portions) {
  final past = c.number < g.currentCycle;
  final byUid = {for (final m in members) m.uid: m};
  String nameOf(String uid) {
    final m = byUid[uid];
    if (m != null) return m.hasNoName ? t.noName : m.name;
    final f = g.formerNames[uid];
    return f == null ? t.noName : t.formerName(f);
  }

  final w = g.wardQuarters;
  final out = <NotReadEntry>[];
  for (final s in [...c.segments]..sort((a, b) => a.seg.compareTo(b.seg))) {
    if (s.uid == null) continue;
    final missing = past ? s.status == 'late' : (s.status == 'pending' || s.status == 'in_progress' || s.status == 'late');
    if (!missing) continue;
    final from = s.seg * w + 1, to = (s.seg + 1) * w;
    String? vol;
    if (past) {
      for (final p in portions) {
        if (p.cycle == c.number && p.fromQuarter >= from && p.fromQuarter <= to && p.assignee != null && p.assignee != s.uid) {
          vol = nameOf(p.assignee!);
        }
      }
    }
    out.add(NotReadEntry(name: nameOf(s.uid!), range: rangeLabel(t, from, to), read: (s.read ?? 0).clamp(0, w), total: w, volunteer: vol));
  }
  return out;
}

String _when(AppLocalizations t, DateTime? end) {
  if (end == null) return '';
  final left = end.difference(DateTime.now());
  if (left.isNegative) return t.cycleEnded;
  return left.inDays >= 1 ? t.daysLeft(left.inDays) : t.hoursLeft(left.inHours.clamp(1, 24));
}

/// نص الرسالة اللي بتتبعت على الواتس اب.
String notReadText(AppLocalizations t, String locale, Group g, Cycle c, List<NotReadEntry> list) {
  final past = c.number < g.currentCycle;
  final df = DateFormat.MMMd(locale);
  final dates = c.startedAt == null || c.endsAt == null ? '' : ' (${df.format(c.startedAt!)} – ${df.format(c.endsAt!)})';
  final assigned = c.segments.where((s) => s.uid != null).length;
  final b = StringBuffer()
    ..writeln('📋 ${t.notReadHeader(g.name, c.number)}$dates')
    ..writeln(past ? t.notReadCountPast(list.length, assigned) : t.notReadCount(list.length, assigned))
    ..writeln();
  for (var i = 0; i < list.length; i++) {
    final e = list[i];
    final extra = [
      if (e.read > 0) t.quartersProgress(e.read, e.total),
      if (e.volunteer != null) t.volunteeredBy(e.volunteer!),
    ];
    b.writeln('${i + 1}. ${e.name} — ${e.range}${extra.isEmpty ? '' : ' (${extra.join(' · ')})'}');
  }
  b.writeln();
  if (!past && c.endsAt != null) b.writeln('⏳ ${_when(t, c.endsAt)}');
  b.write(past ? t.notReadClosingPast : t.notReadClosing);
  return b.toString();
}

/// الأدمن أو المساعد: قايمة اللي ما قرؤش في الدورة اللي قدامه، نص أو صورة.
Future<void> shareNotRead(BuildContext context, Group group, Cycle cycle) async {
  final t = AppLocalizations.of(context);
  final locale = Localizations.localeOf(context).toLanguageTag();
  final size = MediaQuery.sizeOf(context);
  final origin = Rect.fromLTWH(size.width / 2 - 1, size.height / 3, 2, 2);
  final rtl = Directionality.of(context).name == 'rtl';
  final svc = GroupsService.instance;
  final past = cycle.number < group.currentCycle;

  List<NotReadEntry>? list;
  String text = '';
  final loaded = await runAction(context, () async {
    final members = await svc.members(group.id).first;
    final portions = past ? await svc.cyclePortions(group.id, cycle.number) : const <Portion>[];
    list = notReadEntries(t, group, cycle, members, portions);
    text = notReadText(t, locale, group, cycle, list!);
  });
  if (!loaded || !context.mounted || list == null) return;
  if (list!.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.notReadNone)));
    return;
  }

  final kind = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t.notReadTitle, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
            const SizedBox(height: 4),
            Text(t.notReadBody, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 10),
            // معاينة الرسالة زي ما هتتبعت.
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.4),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.background, border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(12)),
                child: SingleChildScrollView(child: SelectableText(text, style: const TextStyle(fontSize: 13, height: 1.5))),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(context, 'text'),
                  icon: const Icon(Icons.chat_outlined),
                  label: Text(t.notReadAsText),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context, 'image'),
                  icon: const Icon(Icons.image_outlined),
                  label: Text(t.reportAsImage),
                ),
              ),
            ]),
            TextButton.icon(
              onPressed: () => Navigator.pop(context, 'copy'),
              icon: const Icon(Icons.copy, size: 18),
              label: Text(t.notReadCopy),
            ),
          ],
        ),
      ),
    ),
  );
  if (kind == null || !context.mounted) return;
  if (kind == 'copy') {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.notReadCopied)));
    return;
  }
  if (kind == 'text') {
    await Share.share(text, sharePositionOrigin: origin);
    return;
  }
  await runAction(context, () async {
    final pdf = await buildNotReadImage(t, locale, rtl, group, cycle, list!);
    final dir = await getTemporaryDirectory();
    final files = <XFile>[];
    var i = 0;
    await for (final page in Printing.raster(pdf, dpi: 170)) {
      i++;
      final f = File('${dir.path}/taawanu-notread-${cycle.number}-$i.png');
      await f.writeAsBytes(await page.toPng());
      files.add(XFile(f.path, mimeType: 'image/png'));
    }
    await Share.shareXFiles(files, text: t.notReadShare(group.name), sharePositionOrigin: origin);
  });
}

/// صورة القايمة: صفحة بطول المحتوى (مش A4) عشان تبان كويس على الموبايل.
Future<Uint8List> buildNotReadImage(AppLocalizations t, String locale, bool rtl, Group g, Cycle c, List<NotReadEntry> list) async {
  const navy = PdfColor.fromInt(0xFF22356E);
  const red = PdfColor.fromInt(0xFFE5484D);
  const yellow = PdfColor.fromInt(0xFFF2B632);
  const accent = PdfColor.fromInt(0xFF2F6FD6);
  const line = PdfColor.fromInt(0xFFD9DEE7);
  const muted = PdfColor.fromInt(0xFF6B7385);
  const soft = PdfColor.fromInt(0xFFC9D3E6);
  final ar = pw.Font.ttf(await rootBundle.load('assets/fonts/report/NotoNaskhArabic-Regular.ttf'));
  final latin = pw.Font.ttf(await rootBundle.load('assets/fonts/report/Roboto-Regular.ttf'));
  final theme = pw.ThemeData.withFont(base: ar, bold: ar, fontFallback: [latin]);
  final dir = rtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;
  final past = c.number < g.currentCycle;
  final df = DateFormat.yMMMd(locale);
  final assigned = c.segments.where((s) => s.uid != null).length;

  final arabic = RegExp(r'[؀-ۿݐ-ݿࢠ-ࣿﭐ-﷿ﹰ-﻿]');
  pw.Widget txt(String s, {double size = 11, PdfColor color = PdfColors.black, bool ltr = false}) {
    final d = ltr || !arabic.hasMatch(s) ? pw.TextDirection.ltr : dir;
    return pw.Text(s, style: pw.TextStyle(fontSize: size, color: color), textDirection: d, textAlign: rtl && d == pw.TextDirection.ltr ? pw.TextAlign.right : null);
  }

  List<pw.Widget> ordered(List<pw.Widget> cells) => rtl ? cells.reversed.toList() : cells;

  pw.Widget row(int i, NotReadEntry e) {
    final color = e.read > 0 ? yellow : red;
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 5),
      decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: line, width: 0.6))),
      child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: ordered([
        pw.Container(
          width: 18,
          height: 18,
          alignment: pw.Alignment.center,
          decoration: pw.BoxDecoration(color: color, shape: pw.BoxShape.circle),
          child: txt('${i + 1}', size: 8.5, color: PdfColors.white, ltr: true),
        ),
        pw.SizedBox(width: 8),
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            txt(e.name, size: 11.5),
            txt(e.range, size: 9, color: muted),
          ]),
        ),
        pw.SizedBox(width: 6),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          txt(e.read > 0 ? t.quartersProgress(e.read, e.total) : (past ? t.statusLate : t.statusPending), size: 9, color: color),
          if (e.volunteer != null) txt(t.volunteeredBy(e.volunteer!), size: 8.5, color: accent),
        ]),
      ])),
    );
  }

  final when = !past && c.endsAt != null ? _when(t, c.endsAt) : '';
  final doc = pw.Document(title: g.name, author: 'Taawanu');
  doc.addPage(pw.Page(
    pageTheme: pw.PageTheme(
      // عرض ثابت والطول على قد القايمة.
      pageFormat: PdfPageFormat(360, 150.0 + list.length * 34, marginAll: 16),
      textDirection: dir,
      theme: theme,
      buildBackground: (ctx) => pw.FullPage(ignoreMargins: true, child: pw.Container(color: PdfColors.white)),
    ),
    build: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: pw.BoxDecoration(color: navy, borderRadius: pw.BorderRadius.circular(10)),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          txt(t.notReadHeader(g.name, c.number), size: 13, color: PdfColors.white),
          if (c.startedAt != null && c.endsAt != null)
            txt(t.sumPeriodLine(df.format(c.startedAt!), df.format(c.endsAt!)), size: 9, color: soft),
        ]),
      ),
      pw.SizedBox(height: 8),
      txt(past ? t.notReadCountPast(list.length, assigned) : t.notReadCount(list.length, assigned), size: 11, color: navy),
      pw.SizedBox(height: 2),
      for (var i = 0; i < list.length; i++) row(i, list[i]),
      pw.Spacer(),
      if (when.isNotEmpty) txt(when, size: 9.5, color: red),
      txt(past ? t.notReadClosingPast : t.notReadClosing, size: 9.5, color: muted),
      pw.SizedBox(height: 2),
      txt('taawanu.app', size: 7.5, color: muted, ltr: true),
    ]),
  ));
  return doc.save();
}
