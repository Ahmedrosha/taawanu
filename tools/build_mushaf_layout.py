"""يبني assets/mushaf/pages.json: توزيع صفحات وسطور مصحف المدينة (٦٠٤ صفحة، ١٥ سطر).

المصدر: https://github.com/zonetecde/mushaf-layout (فرع v2، مجلد mushaf/QPC2) — بيانات quran.com.
كل كلمة بنحط معاها نصها بخط حفص (من assets/quran/madinah.json، نص مجمع الملك فهد)
ورمزها في خط صفحة المجمع (QPC V2).

الشكل:
{"pages": [[سطر, ...], ...]}
سطر عنوان سورة: ["h", رقم_السورة]
سطر بسملة:      ["b"]
سطر نص:         ["t", [[سورة, آية, "نص حفص", "رمز QPC"], ...]]

التشغيل:  python3 tools/build_mushaf_layout.py <مجلد mushaf/QPC2>
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
src = Path(sys.argv[1])
hafs = json.loads((ROOT / 'assets/quran/madinah.json').read_text(encoding='utf-8'))['surahs']

DIGITS = re.compile(r'\s*[٠-٩]+$')
# كلمة فيها حرف (مش علامة وقف لوحدها زي ۛ).
LETTER = re.compile(r'[ء-يٱ-ۓ]')


def skeleton(w):
    """الحروف بس من غير تشكيل، عشان نقارن كلمات مكتوبة بإملاء مختلف شوية."""
    return ''.join(LETTER.findall(w))


def tokens(text):
    """كلمات الآية بخط حفص. علامة الربع ۞ بتتلزق في الكلمة اللي بعدها."""
    out = []
    for w in text.split():
        if out and out[-1] == '۞':
            out[-1] += ' ' + w
        else:
            out.append(w)
    return out


# نجمع كلمات كل آية بالترتيب من صفحات التوزيع.
layout_words = {}
pages_raw = []
for p in range(1, 605):
    page = json.loads((src / f'page-{p:03d}.json').read_text(encoding='utf-8'))
    pages_raw.append(page)
    for line in page['lines']:
        for w in line.get('words', []):
            s, a, i = map(int, w['location'].split(':'))
            layout_words.setdefault((s, a), []).append((i, w['word']))

# نوزّع كلمات حفص على كلمات التوزيع (كلمة التوزيع ممكن تبقى كلمتين في حفص، زي "بَعۡدَ مَا").
mapping = {}
for s, ayahs in enumerate(hafs, 1):
    for a, text in enumerate(ayahs, 1):
        toks = tokens(text)
        number = toks[-1]
        assert DIGITS.fullmatch(' ' + number), (s, a, number)
        words = toks[:-1]
        entries = sorted(layout_words[(s, a)])
        cores = [DIGITS.sub('', w).strip() for _, w in entries]
        markers = [DIGITS.sub('', w).strip() != w.strip() for _, w in entries]
        real = [n for n, c in enumerate(cores) if c]
        if len(real) == len(words):
            # الحالة الغالبة: كل كلمة توزيع = كلمة حفص.
            pieces = {n: words[k] for k, n in enumerate(real)}
        else:
            # آيات قليلة الكلمة فيها مقسومة بشكل مختلف ("لَّوْ مَا" / "لَّوۡمَا"، "بَعۡدَ مَا" / "بَعْدَمَا"):
            # بنوزّع بطول الحروف، وكل كلمة حفص بتروح لكلمة التوزيع اللي فيها نصها.
            lay_cum, acc = [], 0
            for n in real:
                acc += len(skeleton(cores[n]))
                lay_cum.append(acc)
            hafs_len = sum(len(skeleton(w)) for w in words)
            scale = acc / hafs_len
            groups = {n: [] for n in real}
            pos = 0
            for w in words:
                L = len(skeleton(w))
                mid = (pos + L / 2) * scale
                pos += L
                idx = next((k for k, c in enumerate(lay_cum) if mid <= c), len(real) - 1)
                groups[real[idx]].append(w)
            pieces = {n: ' '.join(g) for n, g in groups.items()}
            print('re-aligned', s, a, [pieces[n] for n in real])
        for n, (i, _) in enumerate(entries):
            if not cores[n]:  # رقم الآية لوحده في أول السطر اللي بعده
                mapping[(s, a, i)] = number
                continue
            mapping[(s, a, i)] = (pieces[n] + (' ' + number if markers[n] else '')).strip()

pages = []
for page in pages_raw:
    lines = []
    for line in page['lines']:
        t = line['type']
        if t == 'surah-header':
            lines.append(['h', int(line['surah'])])
        elif t == 'basmala':
            lines.append(['b'])
        else:
            ws = []
            for w in line['words']:
                s, a, i = map(int, w['location'].split(':'))
                ws.append([s, a, mapping[(s, a, i)], w['qpcV2']])
            lines.append(['t', ws])
    pages.append(lines)

out = ROOT / 'assets/mushaf/pages.json'
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps({'source': 'quran.com layout via github.com/zonetecde/mushaf-layout (QPC V2, 604 pages, 15 lines)', 'pages': pages}, ensure_ascii=False, separators=(',', ':')), encoding='utf-8')
print(out, out.stat().st_size)
