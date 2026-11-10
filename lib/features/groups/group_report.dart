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
import '../../widgets/ui.dart';
import 'group_board_screen.dart' show currentSegment, segmentStatusLabel;

const _green = PdfColor.fromInt(0xFF22A35A);
const _yellow = PdfColor.fromInt(0xFFF2B632);
const _grey = PdfColor.fromInt(0xFF8A94A6);
const _red = PdfColor.fromInt(0xFFE5484D);
const _navy = PdfColor.fromInt(0xFF22356E);
const _gold = PdfColor.fromInt(0xFFD4A84B);
const _line = PdfColor.fromInt(0xFFD9DEE7);
const _muted = PdfColor.fromInt(0xFF6B7385);

PdfColor _color(String st) => switch (st) {
      'done' || 'late_done' => _green,
      'in_progress' => _yellow,
      'late' => _red,
      'open' => PdfColors.white,
      _ => _grey,
    };

/// الأدمن أو المساعد: يختار بأسماء ولا من غير، وPDF ولا صورة، ويشارك (واتس اب أو غيره).
Future<void> shareGroupReport(BuildContext context, Group group) async {
  final t = AppLocalizations.of(context);
  var names = true;
  final kind = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => StatefulBuilder(
      builder: (context, set) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t.reportTitle, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
              const SizedBox(height: 4),
              Text(t.reportBody, style: const TextStyle(fontSize: 13)),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t.reportWithNames),
                subtitle: Text(names ? t.reportWithNamesOn : t.reportWithNamesOff, style: const TextStyle(fontSize: 12)),
                value: names,
                onChanged: (v) => set(() => names = v),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(context, 'image'),
                    icon: const Icon(Icons.image_outlined),
                    label: Text(t.reportAsImage),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context, 'pdf'),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: Text(t.reportAsPdf),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    ),
  );
  if (kind == null || !context.mounted) return;
  final locale = Localizations.localeOf(context).toLanguageTag();
  // الآيباد محتاج مكان تطلع منه قايمة المشاركة.
  final size = MediaQuery.sizeOf(context);
  final origin = Rect.fromLTWH(size.width / 2 - 1, size.height / 3, 2, 2);
  final rtl = Directionality.of(context).name == 'rtl';
  await runAction(context, () async {
    final svc = GroupsService.instance;
    final members = await svc.members(group.id).first;
    final cycle = group.isActive ? await svc.cycle(group.id, group.currentCycle).first : null;
    final portions = await svc.activePortions(group.id).first;
    final pdf = await buildGroupReport(t, locale, rtl, group, cycle, members, portions, names);
    final dir = await getTemporaryDirectory();
    final stamp = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final base = 'taawanu-${group.currentCycle}-$stamp';
    final files = <XFile>[];
    if (kind == 'pdf') {
      final f = File('${dir.path}/$base.pdf');
      await f.writeAsBytes(pdf);
      files.add(XFile(f.path, mimeType: 'application/pdf'));
    } else {
      var i = 0;
      await for (final page in Printing.raster(pdf, dpi: 160)) {
        i++;
        final f = File('${dir.path}/$base-$i.png');
        await f.writeAsBytes(await page.toPng());
        files.add(XFile(f.path, mimeType: 'image/png'));
      }
    }
    await Share.shareXFiles(files, text: t.reportShareText(group.name), sharePositionOrigin: origin);
  });
}

Future<Uint8List> buildGroupReport(
  AppLocalizations t,
  String locale,
  bool rtl,
  Group g,
  Cycle? c,
  List<Member> members,
  List<Portion> portions,
  bool names,
) async {
  final ar = pw.Font.ttf(await rootBundle.load('assets/fonts/report/NotoNaskhArabic-Regular.ttf'));
  final latin = pw.Font.ttf(await rootBundle.load('assets/fonts/report/Roboto-Regular.ttf'));
  final theme = pw.ThemeData.withFont(base: ar, bold: ar, fontFallback: [latin]);
  final dir = rtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;
  final df = DateFormat.yMMMd(locale);
  final now = DateTime.now();

  // فاضل أقل من ربع الدورة: اللي لسه مخلصش بيبان متأخر (زي الخريطة).
  var warn = false;
  if (c?.startedAt != null && c?.endsAt != null) {
    final total = c!.endsAt!.difference(c.startedAt!);
    warn = now.isAfter(c.endsAt!.subtract(total ~/ 4));
  }
  String shown(Segment s) => warn && s.uid != null && (s.status == 'pending' || s.status == 'in_progress') ? 'late' : s.status;
  final bySeg = {for (final s in c?.segments ?? const <Segment>[]) s.seg: s};

  final done = c == null ? 0 : (240 - c.remainingQuarters).clamp(0, 240);
  final percent = (done * 100 / 240).round();
  final counts = <String, int>{};
  for (final s in c?.segments ?? const <Segment>[]) {
    if (s.uid == null) continue;
    final st = shown(s);
    counts[st] = (counts[st] ?? 0) + 1;
  }
  final daysLeft = c?.endsAt == null ? null : c!.endsAt!.difference(now).inDays.clamp(0, 9999);

  // الأعضاء بترتيب الورد (الجزء ١ الأول).
  final rows = <(String, String, String, String, String)>[];
  final segOf = {for (final m in members) m.uid: currentSegment(g, m)};
  final sorted = [...members]..sort((a, b) => segOf[a.uid]!.compareTo(segOf[b.uid]!));
  for (var i = 0; i < sorted.length; i++) {
    final m = sorted[i];
    final seg = segOf[m.uid]!;
    final s = bySeg[seg];
    final st = s == null ? 'pending' : shown(s);
    final from = seg * g.wardQuarters + 1;
    rows.add((
      names ? (m.hasNoName ? t.noName : m.name) : t.reportMemberN(i + 1),
      rangeLabel(t, from, from + g.wardQuarters - 1),
      segmentStatusLabel(t, st),
      '${s?.read ?? (st == 'done' || st == 'late_done' ? g.wardQuarters : 0)} / ${g.wardQuarters}',
      st,
    ));
  }
  final open = portions.where((p) => p.status == 'open').toList()..sort((a, b) => a.fromQuarter.compareTo(b.fromQuarter));

  pw.Widget txt(String s, {double size = 11, PdfColor color = PdfColors.black, pw.TextAlign? align, bool ltr = false}) =>
      pw.Text(s, style: pw.TextStyle(fontSize: size, color: color), textDirection: ltr ? pw.TextDirection.ltr : dir, textAlign: align);

  List<pw.Widget> ordered(List<pw.Widget> cells) => rtl ? cells.reversed.toList() : cells;

  pw.Widget stat(String label, String value, PdfColor color) => pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 8),
          margin: const pw.EdgeInsets.symmetric(horizontal: 3),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: _line), borderRadius: pw.BorderRadius.circular(8)),
          child: pw.Column(children: [txt(value, size: 16, color: color), txt(label, size: 9, color: _muted)]),
        ),
      );

  // خريطة الأجزاء: كل جزء شريط مقسوم على الأوراد اللي فيه.
  pw.Widget juz(int j) {
    final parts = <pw.Widget>[];
    var q = j * 8;
    while (q < j * 8 + 8) {
      final seg = q ~/ g.wardQuarters;
      final end = ((seg + 1) * g.wardQuarters).clamp(0, j * 8 + 8);
      final len = end - q;
      final s = bySeg[seg];
      final st = s == null ? 'open' : shown(s);
      parts.add(pw.Expanded(
        flex: len,
        child: pw.Container(
          height: 7,
          margin: const pw.EdgeInsets.symmetric(horizontal: 0.6),
          decoration: pw.BoxDecoration(
            color: _color(st),
            borderRadius: pw.BorderRadius.circular(2),
            border: st == 'open' ? pw.Border.all(color: _grey, width: 0.6) : (st == 'late_done' ? pw.Border.all(color: _red, width: 1) : null),
          ),
        ),
      ));
      q = end;
    }
    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(4, 3, 4, 5),
      decoration: pw.BoxDecoration(border: pw.Border.all(color: _line), borderRadius: pw.BorderRadius.circular(6)),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        txt('${j + 1}', size: 10, align: pw.TextAlign.center),
        pw.SizedBox(height: 3),
        // الشريط بيتبني شمال ليمين صريح، وفي العربي أول الجزء على اليمين.
        pw.Directionality(
          textDirection: pw.TextDirection.ltr,
          child: pw.Row(children: dir == pw.TextDirection.rtl ? parts.reversed.toList() : parts),
        ),
      ]),
    );
  }

  pw.Widget legend(String st) => pw.Row(mainAxisSize: pw.MainAxisSize.min, children: [
        pw.Container(
          width: 10,
          height: 7,
          decoration: pw.BoxDecoration(
            color: _color(st),
            borderRadius: pw.BorderRadius.circular(2),
            border: st == 'open' ? pw.Border.all(color: _grey, width: 0.6) : (st == 'late_done' ? pw.Border.all(color: _red, width: 1) : null),
          ),
        ),
        pw.SizedBox(width: 3),
        txt(segmentStatusLabel(t, st), size: 8, color: _muted),
      ]);

  final doc = pw.Document(theme: theme, title: g.name, author: 'Taawanu');
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(28),
    textDirection: dir,
    footer: (ctx) => pw.Row(children: [
      txt(t.reportFooter, size: 8, color: _muted),
      pw.SizedBox(width: 4),
      txt('taawanu.app', size: 8, color: _muted, ltr: true),
      pw.Spacer(),
      txt('${ctx.pageNumber} / ${ctx.pagesCount}', size: 8, color: _muted, ltr: true),
    ]),
    build: (ctx) => [
      pw.Container(
        padding: const pw.EdgeInsets.all(14),
        decoration: pw.BoxDecoration(color: _navy, borderRadius: pw.BorderRadius.circular(10)),
        child: pw.Row(children: [
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              txt(g.name, size: 18, color: PdfColors.white),
              txt(
                c == null
                    ? t.reportNotStarted
                    : t.reportCycleLine(c.number, c.startedAt == null ? '—' : df.format(c.startedAt!), c.endsAt == null ? '—' : df.format(c.endsAt!)),
                size: 10,
                color: const PdfColor.fromInt(0xFFC9D3E6),
              ),
            ]),
          ),
          pw.Column(children: [
            txt('$percent%', size: 22, color: _gold, ltr: true),
            txt(t.reportRead, size: 9, color: const PdfColor.fromInt(0xFFC9D3E6)),
          ]),
        ]),
      ),
      pw.SizedBox(height: 10),
      pw.Row(children: [
        stat(t.statusDone, '${(counts['done'] ?? 0) + (counts['late_done'] ?? 0)}', _green),
        stat(t.statusInProgress, '${counts['in_progress'] ?? 0}', _yellow),
        stat(t.statusPending, '${counts['pending'] ?? 0}', _grey),
        stat(t.statusLate, '${counts['late'] ?? 0}', _red),
        if (daysLeft != null) stat(t.reportDaysLeft, '$daysLeft', _navy),
      ]),
      pw.SizedBox(height: 12),
      txt(t.reportMap, size: 13),
      pw.SizedBox(height: 6),
      for (var row = 0; row < 3; row++)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 5),
          child: pw.Row(children: [
            for (var j = row * 10; j < row * 10 + 10; j++)
              pw.Expanded(child: pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 2.5), child: juz(j))),
          ]),
        ),
      pw.SizedBox(height: 6),
      pw.Wrap(spacing: 10, runSpacing: 4, children: [for (final st in ['done', 'in_progress', 'pending', 'late', 'late_done', 'open']) legend(st)]),
      pw.SizedBox(height: 14),
      txt(t.reportMembers(members.length), size: 13),
      pw.SizedBox(height: 6),
      // الجدول بيترص شمال ليمين، ففي العربي الأعمدة بتتعكس (العضو على اليمين).
      pw.Table(
        border: pw.TableBorder(horizontalInside: pw.BorderSide(color: _line, width: 0.5), bottom: pw.BorderSide(color: _line, width: 0.5)),
        columnWidths: rtl
            ? const {0: pw.FlexColumnWidth(1.4), 1: pw.FlexColumnWidth(2), 2: pw.FlexColumnWidth(2), 3: pw.FlexColumnWidth(3)}
            : const {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(2), 2: pw.FlexColumnWidth(2), 3: pw.FlexColumnWidth(1.4)},
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF1F3F7)),
            children: ordered([for (final h in [t.reportColName, t.reportColWard, t.reportColStatus, t.reportColRead]) pw.Padding(padding: const pw.EdgeInsets.all(5), child: txt(h, size: 9, color: _muted))]),
          ),
          for (final r in rows)
            pw.TableRow(children: ordered([
              pw.Padding(padding: const pw.EdgeInsets.all(5), child: txt(r.$1, size: 10)),
              pw.Padding(padding: const pw.EdgeInsets.all(5), child: txt(r.$2, size: 10)),
              pw.Padding(
                padding: const pw.EdgeInsets.all(5),
                child: pw.Row(children: [
                  pw.Container(width: 7, height: 7, decoration: pw.BoxDecoration(color: _color(r.$5), shape: pw.BoxShape.circle)),
                  pw.SizedBox(width: 4),
                  txt(r.$3, size: 10),
                ]),
              ),
              pw.Padding(padding: const pw.EdgeInsets.all(5), child: txt(r.$4, size: 10, ltr: true, align: rtl ? pw.TextAlign.right : pw.TextAlign.left)),
            ])),
        ],
      ),
      if (open.isNotEmpty) ...[
        pw.SizedBox(height: 14),
        txt(t.reportOpenPortions(open.length), size: 13),
        pw.SizedBox(height: 4),
        txt(open.map((p) => rangeLabel(t, p.fromQuarter, p.toQuarter)).join(' · '), size: 10),
        txt(t.reportOpenHint, size: 9, color: _muted),
      ],
    ],
  ));
  return doc.save();
}
