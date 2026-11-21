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
import '../../widgets/ui.dart';
import 'report_text.dart';

const _green = PdfColor.fromInt(0xFF22A35A);
const _red = PdfColor.fromInt(0xFFE5484D);
const _yellow = PdfColor.fromInt(0xFFF2B632);
const _navy = PdfColor.fromInt(0xFF22356E);
const _gold = PdfColor.fromInt(0xFFD4A84B);
const _accent = PdfColor.fromInt(0xFF2F6FD6);
const _line = PdfColor.fromInt(0xFFD9DEE7);
const _muted = PdfColor.fromInt(0xFF6B7385);
const _soft = PdfColor.fromInt(0xFFC9D3E6);

/// أرقام عضو واحد في المدة المختارة.
class MemberStats {
  MemberStats(this.uid);
  final String uid;

  /// عدد الدورات اللي كان ليه فيها ورد (من الدورات اللي خلصت).
  int turns = 0;
  int onTime = 0;
  int late = 0;

  /// أوراد متأخرة لغيره خدها وخلّصها أو لسه معاه.
  int volunteered = 0;
  int volunteeredQuarters = 0;

  double get commitment => turns == 0 ? 0 : onTime / turns;
}

/// حسابات التقرير الشامل (من غير واجهة، عشان تتختبر لوحدها).
class GroupSummary {
  GroupSummary._();

  late final DateTime? from;
  late final DateTime to;
  /// بداية أول دورة (لعنوان "من أول المجموعة").
  DateTime? firstStart;
  int khatmas = 0;
  int cyclesEnded = 0;
  int quartersRead = 0;
  int assignedTurns = 0;
  int onTimeTurns = 0;
  double? avgKhatmaDays;
  double? fastestKhatmaDays;
  int bestKhatmaStreak = 0;

  /// (رقم الدورة، نسبة الالتزام ٠–١، الختمة اكتملت؟) لآخر الدورات اللي خلصت.
  final perCycle = <(int, double, bool)>[];
  final members = <String, MemberStats>{};
  int newMembers = 0;

  double get commitment => assignedTurns == 0 ? 0 : onTimeTurns / assignedTurns;

  static GroupSummary compute({
    required Group group,
    required List<Member> memberList,
    required List<Cycle> cycles,
    required List<Portion> portions,
    required Map<int, DateTime> khatmaDates,
    required DateTime? from,
    DateTime? now,
  }) {
    final r = GroupSummary._();
    r.from = from;
    r.to = now ?? DateTime.now();
    bool inRange(DateTime? d) => d != null && (from == null || !d.isBefore(from));
    for (final m in memberList) {
      r.members[m.uid] = MemberStats(m.uid);
      if (from != null && m.joinedAt != null && !m.joinedAt!.isBefore(from)) r.newMembers++;
    }

    for (final c in cycles) {
      final st = c.startedAt;
      if (st != null && (r.firstStart == null || st.isBefore(r.firstStart!))) r.firstStart = st;
    }
    final inPeriod = cycles.where((c) => inRange(c.startedAt)).toList()..sort((a, b) => a.number.compareTo(b.number));
    final numbers = {for (final c in inPeriod) c.number};
    final startOf = {for (final c in cycles) c.number: c.startedAt};

    // الختمات اللي خلصت في المدة، ومدة كل واحدة من بداية دورتها.
    final durations = <double>[];
    khatmaDates.forEach((n, at) {
      if (!inRange(at)) return;
      r.khatmas++;
      final st = startOf[n];
      if (st != null && at.isAfter(st)) durations.add(at.difference(st).inMinutes / 1440);
    });
    if (durations.isNotEmpty) {
      r.avgKhatmaDays = durations.reduce((a, b) => a + b) / durations.length;
      r.fastestKhatmaDays = durations.reduce((a, b) => a < b ? a : b);
    }

    var streak = 0;
    for (final c in inPeriod) {
      r.quartersRead += (240 - c.remainingQuarters).clamp(0, 240);
      final ended = c.number < group.currentCycle;
      if (!ended) continue;
      r.cyclesEnded++;
      var turns = 0, onTime = 0;
      for (final s in c.segments) {
        if (s.uid == null) continue;
        turns++;
        final ok = s.status == 'done';
        if (ok) onTime++;
        final m = r.members[s.uid];
        if (m != null) {
          m.turns++;
          if (ok) {
            m.onTime++;
          } else {
            m.late++;
          }
        }
      }
      r.assignedTurns += turns;
      r.onTimeTurns += onTime;
      final complete = c.khatmaComplete || khatmaDates.containsKey(c.number);
      streak = complete ? streak + 1 : 0;
      if (streak > r.bestKhatmaStreak) r.bestKhatmaStreak = streak;
      r.perCycle.add((c.number, turns == 0 ? 0 : onTime / turns, complete));
    }
    if (r.perCycle.length > 12) r.perCycle.removeRange(0, r.perCycle.length - 12);

    // التطوع: ورد إضافي من دورة في المدة، خده حد غير صاحبه الأصلي (الترحيل لصاحبه مش تطوع).
    // صاحب الورد الأصلي في دورته: لو هو اللي خد ورده المتأخر، ده مش تطوع (وهو محسوب عليه تأخير).
    final ownerOf = <int, Map<int, String?>>{
      for (final c in inPeriod) c.number: {for (final s in c.segments) s.seg: s.uid},
    };
    for (final p in portions) {
      if (!numbers.contains(p.cycle) || p.assignee == null || p.origin == 'carry') continue;
      final owner = ownerOf[p.cycle]?[(p.fromQuarter - 1) ~/ group.wardQuarters];
      if (owner != null && owner == p.assignee) continue;
      final m = r.members[p.assignee];
      if (m == null) continue;
      m.volunteered++;
      m.volunteeredQuarters += p.quarterCount;
    }
    return r;
  }

  /// الأكثر التزامًا: اللي ليهم دورتين على الأقل لو فيه، بنسبة الالتزام ثم عدد الدورات.
  List<MemberStats> topCommitted(Map<String, int> points, {int n = 3}) {
    var pool = members.values.where((m) => m.turns >= 2 && m.onTime > 0).toList();
    if (pool.isEmpty) pool = members.values.where((m) => m.onTime > 0).toList();
    pool.sort((a, b) {
      final c = b.commitment.compareTo(a.commitment);
      if (c != 0) return c;
      final d = b.turns.compareTo(a.turns);
      return d != 0 ? d : (points[b.uid] ?? 0).compareTo(points[a.uid] ?? 0);
    });
    return pool.take(n).toList();
  }

  List<MemberStats> topVolunteers({int n = 3}) => (members.values.where((m) => m.volunteered > 0).toList()
        ..sort((a, b) {
          final c = b.volunteered.compareTo(a.volunteered);
          return c != 0 ? c : b.volunteeredQuarters.compareTo(a.volunteeredQuarters);
        }))
      .take(n)
      .toList();

  List<MemberStats> topLate({int n = 3}) => (members.values.where((m) => m.late > 0).toList()
        ..sort((a, b) {
          final c = b.late.compareTo(a.late);
          return c != 0 ? c : a.commitment.compareTo(b.commitment);
        }))
      .take(n)
      .toList();
}

/// الأدمن أو المساعد: تقرير شامل عن المجموعة في مدة يختارها.
Future<void> shareGroupSummary(BuildContext context, Group group) async {
  final t = AppLocalizations.of(context);
  var names = true;
  var showLate = false;
  var period = 'all';
  final kind = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, set) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t.sumTitle, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
              const SizedBox(height: 4),
              Text(t.sumBody, style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 12),
              Text(t.sumPeriod, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 6, children: [
                for (final (k, label) in [('30', t.sumLast30), ('90', t.sumLast90), ('all', t.sumAll)])
                  ChoiceChip(label: Text(label), selected: period == k, onSelected: (_) => set(() => period = k)),
              ]),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t.reportWithNames),
                subtitle: Text(names ? t.reportWithNamesOn : t.reportWithNamesOff, style: const TextStyle(fontSize: 12)),
                value: names,
                onChanged: (v) => set(() => names = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t.sumShowLate),
                subtitle: Text(showLate ? t.sumShowLateOn : t.sumShowLateOff, style: const TextStyle(fontSize: 12)),
                value: showLate,
                onChanged: (v) => set(() => showLate = v),
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
  final size = MediaQuery.sizeOf(context);
  final origin = Rect.fromLTWH(size.width / 2 - 1, size.height / 3, 2, 2);
  final rtl = Directionality.of(context).name == 'rtl';
  await runAction(context, () async {
    final svc = GroupsService.instance;
    final now = DateTime.now();
    final from = switch (period) {
      '30' => now.subtract(const Duration(days: 30)),
      '90' => now.subtract(const Duration(days: 90)),
      _ => null,
    };
    final results = await Future.wait([
      svc.members(group.id).first,
      svc.allCycles(group.id),
      svc.allPortions(group.id),
      svc.completedKhatmas(group.id),
    ]);
    final members = results[0] as List<Member>;
    final sum = GroupSummary.compute(
      group: group,
      memberList: members,
      cycles: results[1] as List<Cycle>,
      portions: results[2] as List<Portion>,
      khatmaDates: results[3] as Map<int, DateTime>,
      from: from,
      now: now,
    );
    final pdf = await buildGroupSummary(t, locale, rtl, group, members, sum, names: names, showLate: showLate);
    final dir = await getTemporaryDirectory();
    final base = 'taawanu-summary-${DateFormat('yyyy-MM-dd').format(now)}';
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
    await Share.shareXFiles(files, text: t.sumShareText(group.name), sharePositionOrigin: origin);
  });
}

Future<Uint8List> buildGroupSummary(
  AppLocalizations t,
  String locale,
  bool rtl,
  Group g,
  List<Member> memberList,
  GroupSummary sum, {
  required bool names,
  required bool showLate,
}) async {
  final ar = pw.Font.ttf(await rootBundle.load('assets/fonts/report/NotoNaskhArabic-Regular.ttf'));
  final latin = pw.Font.ttf(await rootBundle.load('assets/fonts/report/Roboto-Regular.ttf'));
  final theme = pw.ThemeData.withFont(base: ar, bold: ar, fontFallback: [latin]);
  final dir = rtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;
  final df = DateFormat.yMMMd(locale);
  final num1 = NumberFormat('0.#', 'en');

  final points = {for (final m in memberList) m.uid: m.points};
  // الجدول بالنقاط، ورقم كل عضو فيه هو اللي بيظهر لو التقرير من غير أسماء.
  final table = [...memberList]..sort((a, b) => b.points.compareTo(a.points));
  final index = {for (var i = 0; i < table.length; i++) table[i].uid: i + 1};
  final byUid = {for (final m in memberList) m.uid: m};
  String nameOf(String uid) {
    if (!names) return t.reportMemberN(index[uid] ?? 0);
    final m = byUid[uid];
    return m == null || m.hasNoName ? t.noName : m.name;
  }

  String pct(double v) => '${(v * 100).round()}%';

  final arabic = RegExp(r'[؀-ۿݐ-ݿࢠ-ࣿﭐ-﷿ﹰ-﻿]');
  pw.Widget txt(String s, {double size = 11, PdfColor color = PdfColors.black, pw.TextAlign? align, bool ltr = false}) {
    final d = ltr || !arabic.hasMatch(s) ? pw.TextDirection.ltr : dir;
    final a = align ?? (rtl && d == pw.TextDirection.ltr ? pw.TextAlign.right : null);
    return pw.Text(rtl ? arDigits(d == pw.TextDirection.rtl ? _mirrorBrackets(s) : s) : s, style: pw.TextStyle(fontSize: size, color: color), textDirection: d, textAlign: a);
  }

  List<pw.Widget> ordered(List<pw.Widget> cells) => rtl ? cells.reversed.toList() : cells;

  pw.Widget stat(String label, String value, PdfColor color) => pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 4),
          margin: const pw.EdgeInsets.symmetric(horizontal: 3),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: _line), borderRadius: pw.BorderRadius.circular(8)),
          child: pw.Column(children: [
            txt(value, size: 15, color: color, ltr: true, align: pw.TextAlign.center),
            txt(label, size: 8, color: _muted, align: pw.TextAlign.center),
          ]),
        ),
      );

  pw.Widget section(String title) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 8, bottom: 3),
        child: txt(title, size: 11.5, color: _navy),
      );

  // عمود في الرسم لكل دورة: النسبة فوق، والعمود أخضر لو الختمة اكتملت.
  pw.Widget chart() {
    const h = 60.0;
    final bars = [
      for (final (n, v, complete) in sum.perCycle)
        pw.Expanded(
          child: pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 3),
            child: pw.Column(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
              txt(pct(v), size: 7, color: _muted, ltr: true, align: pw.TextAlign.center),
              pw.SizedBox(height: 1),
              pw.Container(
                height: (h * v).clamp(2.0, h),
                decoration: pw.BoxDecoration(
                  color: complete ? _green : (v >= 0.5 ? _yellow : _red),
                  borderRadius: const pw.BorderRadius.vertical(top: pw.Radius.circular(3)),
                ),
              ),
              pw.SizedBox(height: 2),
              txt('$n', size: 7.5, ltr: true, align: pw.TextAlign.center),
            ]),
          ),
        ),
    ];
    return pw.Container(
      height: h + 30,
      padding: const pw.EdgeInsets.fromLTRB(4, 4, 4, 2),
      decoration: pw.BoxDecoration(border: pw.Border.all(color: _line), borderRadius: pw.BorderRadius.circular(8)),
      child: pw.Directionality(
        textDirection: pw.TextDirection.ltr,
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: ordered(bars)),
      ),
    );
  }

  pw.Widget chartLegend() {
    pw.Widget one(PdfColor c, String label) => pw.Row(mainAxisSize: pw.MainAxisSize.min, children: [
          pw.Container(width: 9, height: 7, decoration: pw.BoxDecoration(color: c, borderRadius: pw.BorderRadius.circular(2))),
          pw.SizedBox(width: 3),
          txt(label, size: 8, color: _muted),
        ]);
    return pw.Wrap(spacing: 10, children: [one(_green, t.sumBarComplete), one(_yellow, t.sumBarHalf), one(_red, t.sumBarLow)]);
  }

  // كارت ترتيب: أول ٣ بأسمائهم والرقم اللي اتختاروا بيه.
  pw.Widget ranking(String title, PdfColor color, List<(String, String)> items) => pw.Expanded(
        child: pw.Container(
          margin: const pw.EdgeInsets.symmetric(horizontal: 3),
          padding: const pw.EdgeInsets.fromLTRB(8, 5, 8, 6),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: _line), borderRadius: pw.BorderRadius.circular(6)),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
            pw.Container(height: 3, decoration: pw.BoxDecoration(color: color, borderRadius: pw.BorderRadius.circular(2))),
            pw.SizedBox(height: 3),
            txt(title, size: 10, color: color),
            pw.SizedBox(height: 3),
            if (items.isEmpty) txt(t.sumNone, size: 9, color: _muted),
            for (var i = 0; i < items.length; i++)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 2),
                child: pw.Row(children: ordered([
                  pw.SizedBox(width: 12, child: txt('${i + 1}', size: 9, color: color, ltr: true)),
                  pw.Expanded(child: txt(items[i].$1, size: 9)),
                  pw.SizedBox(width: 4),
                  txt(items[i].$2, size: 8.5, color: _muted),
                ])),
              ),
          ]),
        ),
      );

  final committed = sum.topCommitted(points).map((m) => (nameOf(m.uid), '${pct(m.commitment)} · ${t.sumTurnsOf(m.onTime, m.turns)}')).toList();
  final volunteers = sum.topVolunteers().map((m) => (nameOf(m.uid), t.sumVolN(m.volunteered))).toList();
  final late = sum.topLate().map((m) => (nameOf(m.uid), t.sumTurnsOf(m.late, m.turns))).toList();

  pw.Widget membersTable() {
    const pad = pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2);
    final heads = [t.reportColName, t.sumColPoints, t.sumColOnTime, if (showLate) t.sumColLate, t.sumColVol, t.sumColCommit];
    final flex = [3.2, 1.2, 1.3, if (showLate) 1.1, 1.1, 1.3];
    final widths = {for (var i = 0; i < flex.length; i++) i: pw.FlexColumnWidth(rtl ? flex[flex.length - 1 - i] : flex[i])};
    return pw.Table(
      border: pw.TableBorder(horizontalInside: pw.BorderSide(color: _line, width: 0.5), bottom: pw.BorderSide(color: _line, width: 0.5)),
      columnWidths: widths,
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF1F3F7)),
          children: ordered([for (final h in heads) pw.Padding(padding: pad, child: txt(h, size: 8, color: _muted))]),
        ),
        for (final m in table)
          pw.TableRow(verticalAlignment: pw.TableCellVerticalAlignment.middle, children: ordered([
            pw.Padding(
              padding: pad,
              child: pw.Row(children: [
                pw.SizedBox(width: 14, child: txt('${index[m.uid]}', size: 8, color: _muted, ltr: true)),
                pw.Expanded(child: txt(nameOf(m.uid), size: 9)),
              ]),
            ),
            pw.Padding(padding: pad, child: txt('${m.points}', size: 9, color: _gold, ltr: true)),
            pw.Padding(padding: pad, child: txt('${sum.members[m.uid]?.onTime ?? 0}', size: 9, color: _green, ltr: true)),
            if (showLate) pw.Padding(padding: pad, child: txt('${sum.members[m.uid]?.late ?? 0}', size: 9, color: _red, ltr: true)),
            pw.Padding(padding: pad, child: txt('${sum.members[m.uid]?.volunteered ?? 0}', size: 9, color: _accent, ltr: true)),
            pw.Padding(
              padding: pad,
              child: txt((sum.members[m.uid]?.turns ?? 0) == 0 ? '—' : pct(sum.members[m.uid]!.commitment), size: 9, ltr: true),
            ),
          ])),
      ],
    );
  }

  final periodLine = sum.from == null ? t.sumSince(sum.firstStart == null ? '—' : df.format(sum.firstStart!)) : t.sumPeriodLine(df.format(sum.from!), df.format(sum.to));
  final doc = pw.Document(title: g.name, author: 'Taawanu');
  doc.addPage(pw.MultiPage(
    pageTheme: pw.PageTheme(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(26, 22, 26, 18),
      textDirection: dir,
      theme: theme,
      buildBackground: (ctx) => pw.FullPage(ignoreMargins: true, child: pw.Container(color: PdfColors.white)),
    ),
    footer: (ctx) => pw.Row(children: [
      txt(t.reportFooter, size: 8, color: _muted),
      pw.SizedBox(width: 4),
      txt('taawanu.app', size: 8, color: _muted, ltr: true),
      pw.Spacer(),
      txt('${ctx.pageNumber} / ${ctx.pagesCount}', size: 8, color: _muted, ltr: true),
    ]),
    build: (ctx) => [
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: pw.BoxDecoration(color: _navy, borderRadius: pw.BorderRadius.circular(10)),
        child: pw.Row(children: [
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              txt(g.name, size: 16, color: PdfColors.white),
              txt('${t.sumTitle} · $periodLine', size: 10, color: _soft),
            ]),
          ),
          pw.Column(children: [
            txt('${sum.khatmas}', size: 22, color: _gold, ltr: true),
            txt(t.sumKhatmas, size: 9, color: _soft),
          ]),
        ]),
      ),
      pw.SizedBox(height: 6),
      pw.Row(children: [
        stat(t.sumCycles, '${sum.cyclesEnded}', _navy),
        stat(t.sumJuz, num1.format(sum.quartersRead / 8), _green),
        stat(t.sumCommit, sum.assignedTurns == 0 ? '—' : pct(sum.commitment), _accent),
        stat(t.sumMembersN, '${memberList.length}', _navy),
      ]),
      pw.SizedBox(height: 5),
      pw.Row(children: [
        stat(t.sumAvgDays, sum.avgKhatmaDays == null ? '—' : num1.format(sum.avgKhatmaDays), _navy),
        stat(t.sumFastest, sum.fastestKhatmaDays == null ? '—' : num1.format(sum.fastestKhatmaDays), _green),
        stat(t.sumStreak, '${sum.bestKhatmaStreak}', _gold),
        stat(sum.from == null ? t.sumAllTimePoints : t.sumNewMembers, sum.from == null ? '${points.values.fold<int>(0, (a, b) => a + b)}' : '${sum.newMembers}', _accent),
      ]),
      if (sum.perCycle.isNotEmpty) ...[
        section(t.sumChart),
        chart(),
        pw.SizedBox(height: 3),
        chartLegend(),
      ] else ...[
        pw.SizedBox(height: 8),
        txt(t.sumNoCycles, size: 10, color: _muted),
      ],
      section(t.sumHonors),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        ranking(t.sumTopCommitted, _green, committed),
        ranking(t.sumTopVolunteers, _accent, volunteers),
        if (showLate) ranking(t.sumTopLate, _red, late),
      ]),
      section(t.reportMembers(memberList.length)),
      membersTable(),
      pw.SizedBox(height: 6),
      txt(t.sumNote, size: 8, color: _muted),
      if (sum.from != null) txt(t.sumPointsNote, size: 8, color: _muted),
    ],
  ));
  return doc.save();
}

/// مكتبة الـ PDF مش بتقلب الأقواس في النص العربي، فبنقلبها إحنا.
String _mirrorBrackets(String s) => s.replaceAllMapped(RegExp(r'[()\[\]]'), (m) => const {'(': ')', ')': '(', '[': ']', ']': '['}[m[0]]!);
