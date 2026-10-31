import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../services/quran_repository.dart';
import '../theme/app_colors.dart';

/// الخانة اللي بتقرا قطعة معينة في دورة معينة (زي السيرفر بالظبط).
int segmentForSlot(int slot, int cycle, int slots) => ((slot + cycle - 1) % slots + slots) % slots;

/// اسم القطعة: "الجزء 7"، "الأحزاب 3–4"... إلخ.
String segmentLabel(AppLocalizations t, int segment, int wardQuarters) =>
    rangeLabel(t, segment * wardQuarters + 1, (segment + 1) * wardQuarters);

/// جدول باختيار القطعة.
/// [taken]: القطع المحجوزة (مش متاحة) في وضع الانضمام.
/// [holders]: في وضع النقل، اسم صاحب كل قطعة؛ اختيار قطعة محجوزة معناه تبادل.
/// الأوراد الأصغر من جزء بتتعرض مقسمة: كل جزء لوحده، وتحته أحزابه وأرباعها.
Future<int?> showSegmentPicker(
  BuildContext context, {
  required int wardQuarters,
  required int slots,
  int? selected,
  Set<int> taken = const {},
  Map<int, String> holders = const {},
  String? note,
}) {
  final t = AppLocalizations.of(context);
  Widget cell(BuildContext context, int seg, String label) => _SegmentCell(
        label: label,
        tooltip: segmentLabel(t, seg, wardQuarters),
        selected: seg == selected,
        taken: taken.contains(seg),
        holder: holders[seg],
        onTap: () => Navigator.pop(context, seg),
      );
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.92,
      builder: (context, scroll) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t.chooseStartTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(note ?? t.chooseStartBody, style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
            const SizedBox(height: 12),
            Expanded(
              child: SegmentGrid(
                scroll: scroll,
                wardQuarters: wardQuarters,
                slots: slots,
                selected: selected,
                wide: holders.isNotEmpty,
                cell: (seg, label) => cell(context, seg, label),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// الأوراد كلها: جدول أرقام للجزء فأكبر، ومقسمة جزء جزء للأوراد الأصغر.
/// [cell] بيبني خانة كل ورد (رقمه واسمه المختصر).
class SegmentGrid extends StatelessWidget {
  const SegmentGrid({
    super.key,
    required this.scroll,
    required this.wardQuarters,
    required this.slots,
    required this.cell,
    this.selected,
    this.wide = false,
  });

  final ScrollController? scroll;
  final int wardQuarters;
  final int slots;
  final int? selected;
  final bool wide;
  final Widget Function(int seg, String label) cell;

  @override
  Widget build(BuildContext context) {
    if (wardQuarters < 8) {
      return _ByJuz(scroll: scroll, wardQuarters: wardQuarters, selected: selected, cell: cell, wide: wide);
    }
    return GridView.builder(
      controller: scroll,
      padding: const EdgeInsets.only(bottom: 24),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: wide ? 92 : 64,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: wide ? 0.95 : 1,
      ),
      itemCount: slots,
      itemBuilder: (context, seg) => cell(seg, '${seg + 1}'),
    );
  }
}

/// ٣٠ كارت (جزء لكل كارت). جوه كل جزء: الحزبين، وتحت كل حزب أرباعه أو نصّيه.
class _ByJuz extends StatefulWidget {
  const _ByJuz({required this.scroll, required this.wardQuarters, required this.selected, required this.cell, required this.wide});

  final ScrollController? scroll;
  final int wardQuarters; // ١ أو ٢ أو ٤
  final int? selected;
  final Widget Function(int seg, String label) cell;
  final bool wide;

  @override
  State<_ByJuz> createState() => _ByJuzState();
}

class _ByJuzState extends State<_ByJuz> {
  final _selectedKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // نفتح على الجزء اللي فيه الورد المختار.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _selectedKey.currentContext;
      if (ctx != null) Scrollable.ensureVisible(ctx, alignment: 0.1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final w = widget.wardQuarters;
    final selectedJuz = widget.selected == null ? null : widget.selected! * w ~/ 8;
    final cellSize = widget.wide ? 76.0 : 54.0;

    Widget sized(Widget c) => SizedBox(width: cellSize, height: widget.wide ? 62 : 48, child: c);

    return SingleChildScrollView(
      controller: widget.scroll,
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var juz = 0; juz < 30; juz++)
            Container(
              key: juz == selectedJuz ? _selectedKey : null,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: juz == selectedJuz ? AppColors.accent : AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.juzLabel(juz + 1), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.accent)),
                  const SizedBox(height: 8),
                  if (w == 4)
                    // ورد حزب: الحزبين جنب بعض.
                    Wrap(
                      spacing: 8,
                      children: [
                        for (var h = 0; h < 2; h++)
                          SizedBox(
                            width: widget.wide ? 120 : 110,
                            height: widget.wide ? 62 : 48,
                            child: widget.cell(juz * 2 + h, t.hizbLabel(juz * 2 + h + 1)),
                          ),
                      ],
                    )
                  else
                    for (var h = 0; h < 2; h++)
                      Padding(
                        padding: EdgeInsets.only(top: h == 0 ? 0 : 8),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 74,
                              child: Text(t.hizbLabel(juz * 2 + h + 1), style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
                            ),
                            Expanded(
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  // ربع حزب: ٤ أرباع. نص حزب: نصّين.
                                  for (var k = 0; k < 4 ~/ w; k++)
                                    sized(widget.cell((juz * 8 + h * 4) ~/ w + k, '${k + 1}')),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SegmentCell extends StatelessWidget {
  const _SegmentCell({
    required this.label,
    required this.tooltip,
    required this.selected,
    required this.taken,
    required this.holder,
    required this.onTap,
  });

  final String label;
  final String tooltip;
  final bool selected;
  final bool taken;
  final String? holder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: selected
            ? AppColors.navy
            : taken
                ? AppColors.border
                : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: selected ? AppColors.navy : AppColors.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: taken ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: selected
                        ? Colors.white
                        : taken
                            ? AppColors.textMuted
                            : AppColors.text,
                  ),
                ),
                if (holder != null)
                  Text(
                    holder!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: selected ? Colors.white70 : AppColors.textMuted),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// صف بيعرض القطعة المختارة، والضغط عليه بيفتح الجدول.
class SegmentChoiceTile extends StatelessWidget {
  const SegmentChoiceTile({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.border),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Icon(Icons.menu_book_outlined, color: AppColors.accent),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        trailing: onTap == null ? null : const Icon(Icons.edit_outlined, size: 20),
      ),
    );
  }
}
