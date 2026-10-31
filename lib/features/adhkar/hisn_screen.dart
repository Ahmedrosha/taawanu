import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../theme/app_colors.dart';
import 'adhkar_data.dart';

/// حصن المسلم كله: الأبواب مع بحث.
class HisnScreen extends StatefulWidget {
  const HisnScreen({super.key});

  @override
  State<HisnScreen> createState() => _HisnScreenState();
}

class _HisnScreenState extends State<HisnScreen> {
  late final Future<List<HisnChapter>> _data = AdhkarRepository.instance.hisn();
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.hisnMuslim, style: const TextStyle(fontWeight: FontWeight.w700))),
      body: FutureBuilder<List<HisnChapter>>(
        future: _data,
        builder: (context, snap) {
          final all = snap.data;
          if (all == null) return const Center(child: CircularProgressIndicator());
          final q = normalizeArabic(_query.trim());
          // البحث في عنوان الباب ونصوصه.
          final list = q.isEmpty
              ? all
              : all.where((c) => normalizeArabic(c.title).contains(q) || c.texts.any((x) => normalizeArabic(x).contains(q))).toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: t.searchHisn),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Expanded(
                child: list.isEmpty
                    ? Center(child: Text(t.noResults, style: TextStyle(color: AppColors.textMuted)))
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: list.length,
                        separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.border),
                        itemBuilder: (context, i) {
                          final c = list[i];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                            title: Text(c.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                            trailing: Text('${c.texts.length}', style: TextStyle(color: AppColors.textMuted)),
                            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => HisnChapterScreen(chapter: c))),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class HisnChapterScreen extends StatelessWidget {
  const HisnChapterScreen({super.key, required this.chapter});

  final HisnChapter chapter;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(chapter.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          for (final text in chapter.texts)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border),
              ),
              child: SelectableText(
                text,
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.justify,
                style: GoogleFonts.amiri(fontSize: 19, height: 1.9, color: AppColors.text),
              ),
            ),
          if (chapter.footnotes.isNotEmpty)
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(t.footnotes, style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.accent)),
                children: [
                  for (final n in chapter.footnotes)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(n, textDirection: TextDirection.rtl, style: TextStyle(fontSize: 13, color: AppColors.textMuted, height: 1.6)),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Text(t.hisnSource, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
        ],
      ),
    );
  }
}
