"""يحوّل تفسير من مكتبة QUL (qul.tarteel.ai، ملف JSON) لملفات صغيرة لكل سورة على الموقع:
site/tafsir/<id>/<سورة>.json  =>  {"a": [...]}  عنصر لكل آية:
  - نص التفسير بعلامات بسيطة: <q>قرآن</q>، <b>عنوان</b>، <r>تنبيه</r>، <h>فاصل</h>، وأسطر جديدة.
  - أو رقم: الآية دي تفسيرها مع آية رقم كذا (مجموعة آيات ليها تفسير واحد).
  - أو null: مفيش تفسير منفصل (بيتعرض تفسير اللي قبلها).
الحواشي [[...]] (فروق النسخ في ابن كثير) بتتشال للقراءة، والنص نفسه زي ما هو.

التشغيل:  python3 tools/build_tafsir_qul.py <ملف QUL> <id>
"""
import html
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
src, tid = Path(sys.argv[1]), sys.argv[2]
data = json.loads(src.read_text(encoding='utf-8'))


def clean(t: str) -> str:
    t = re.sub(r'\[\[.*?\]\]', '', t, flags=re.S)
    t = re.sub(r'<h3[^>]*>(.*?)</h3>', lambda m: '\n<h>' + m.group(1).strip() + '</h>\n', t, flags=re.S)
    t = re.sub(r'<span class="[^"]*qpc-hafs[^"]*">(.*?)</span>', r'<q>\1</q>', t, flags=re.S)
    t = re.sub(r'<span class="[^"]*blue[^"]*">(.*?)</span>', r'<b>\1</b>', t, flags=re.S)
    t = re.sub(r'<span class="[^"]*red[^"]*">(.*?)</span>', r'<r>\1</r>', t, flags=re.S)
    t = re.sub(r'<br\s*/?>', '\n', t)
    t = re.sub(r'</p>\s*<p[^>]*>', '\n\n', t)
    t = re.sub(r'<(?!/?[qbrh]>)[^>]+>', '', t)
    t = html.unescape(t)
    t = re.sub(r'[ \t]+', ' ', t)
    t = re.sub(r'\n{3,}', '\n\n', t)
    return t.strip()


out_dir = ROOT / 'site/tafsir' / tid
out_dir.mkdir(parents=True, exist_ok=True)
counts = json.loads((ROOT / 'assets/quran/madinah.json').read_text(encoding='utf-8'))['surahs']
total = 0
for s, ayahs in enumerate(counts, 1):
    items = []
    for a in range(1, len(ayahs) + 1):
        v = data.get(f'{s}:{a}')
        if isinstance(v, str):
            hs, ha = map(int, v.split(':'))
            assert hs == s
            items.append(ha)
        elif isinstance(v, dict) and v.get('text'):
            items.append(clean(v['text']))
        else:
            items.append(None)
    (out_dir / f'{s}.json').write_text(json.dumps({'a': items}, ensure_ascii=False, separators=(',', ':')), encoding='utf-8')
    total += sum(len(x) for x in items if isinstance(x, str))
print(tid, 'chars', total, 'bytes', sum(f.stat().st_size for f in out_dir.glob('*.json')))
