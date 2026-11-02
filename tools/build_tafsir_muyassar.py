"""يبني assets/tafsir/muyassar.json من ملف تنزيل (txt-2: سورة|آية|نص).

المصدر: https://tanzil.net/trans/?transID=ar.muyassar&type=txt-2
التفسير الميسر — مجمع الملك فهد لطباعة المصحف الشريف، بدون أي تعديل في النص.
التشغيل:  python3 tools/build_tafsir_muyassar.py <ملف تنزيل>
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
surahs = [[] for _ in range(114)]
for line in Path(sys.argv[1]).read_text(encoding='utf-8').splitlines():
    if not line.strip() or line.startswith('#'):
        continue
    s, a, text = line.split('|', 2)
    s, a = int(s), int(a)
    assert len(surahs[s - 1]) == a - 1, (s, a)
    surahs[s - 1].append(text.strip())
assert sum(len(x) for x in surahs) == 6236
out = ROOT / 'assets/tafsir/muyassar.json'
out.write_text(json.dumps({
    'source': 'التفسير الميسر — مجمع الملك فهد لطباعة المصحف الشريف، عن Tanzil.net (بدون تعديل)',
    'surahs': surahs,
}, ensure_ascii=False, separators=(',', ':')), encoding='utf-8')
print(out, out.stat().st_size)
