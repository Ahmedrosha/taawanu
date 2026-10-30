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
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.92,
      builder: (context, scroll) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t.chooseStartTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(note ?? t.chooseStartBody, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
            const SizedBox(height: 12),
            Expanded(
              child: GridView.builder(
                controller: scroll,
                padding: const EdgeInsets.only(bottom: 24),
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: holders.isEmpty ? 64 : 92,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: holders.isEmpty ? 1 : 0.95,
                ),
                itemCount: slots,
                itemBuilder: (context, seg) {
                  final isTaken = taken.contains(seg);
                  final isSelected = seg == selected;
                  final holder = holders[seg];
                  return Tooltip(
                    message: segmentLabel(t, seg, wardQuarters),
                    child: Material(
                      color: isSelected
                          ? AppColors.navy
                          : isTaken
                              ? AppColors.border
                              : AppColors.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: isSelected ? AppColors.navy : AppColors.border),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: isTaken ? null : () => Navigator.pop(context, seg),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '${seg + 1}',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: isSelected
                                      ? Colors.white
                                      : isTaken
                                          ? AppColors.textMuted
                                          : AppColors.text,
                                ),
                              ),
                              if (holder != null)
                                Text(
                                  holder,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 11, color: isSelected ? Colors.white70 : AppColors.textMuted),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
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
        side: const BorderSide(color: AppColors.border),
      ),
      child: ListTile(
        onTap: onTap,
        leading: const Icon(Icons.menu_book_outlined, color: AppColors.navy),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        trailing: onTap == null ? null : const Icon(Icons.edit_outlined, size: 20),
      ),
    );
  }
}
