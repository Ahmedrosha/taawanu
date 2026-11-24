"""مراجعة كل بيانات القرآن في التطبيق مقابل مصحف المدينة.

المراجع (بتتحمّل وقت التشغيل، مش جوه التطبيق):
  • quran.com API v4: نص مجمع الملك فهد (text_qpc_hafs)، أسماء السور، عدد الآيات، الجزء/الحزب/الربع،
    رقم الصفحة، السجدات، وكلمات كل صفحة وسطورها (code_v2 / line_number) — كلها على مصحف المدينة.
  • Tanzil metadata (quran-data.js): مرجع تاني مستقل للأجزاء والأرباع والسجدات والصفحات.
  • quran.com tafsir 16 (التفسير الميسر).

بيطبع تقرير بكل اختلاف، ومش بيعدّل أي ملف.
"""
import json, re, sys, time, urllib.request, urllib.error, unicodedata
from concurrent.futures import ThreadPoolExecutor

API = 'https://api.quran.com/api/v4'
UA = {'User-Agent': 'taawanu-audit/1.0', 'Accept': 'application/json'}
report = []


def say(s=''):
    print(s); sys.stdout.flush(); report.append(s)


def get(url, tries=6):
    for i in range(tries):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60) as r:
                return r.read().decode('utf-8')
        except Exception as e:
            if i == tries - 1:
                raise
            time.sleep(2 + i * 3)


def jget(url):
    return json.loads(get(url))


# ---------- ملفات التطبيق ----------
Q = json.load(open('assets/quran/quran.json'))
M = json.load(open('assets/quran/madinah.json'))
T = json.load(open('assets/quran/tajweed.json'))
P = json.load(open('assets/mushaf/pages.json'))
TF = json.load(open('assets/tafsir/muyassar.json'))
ADHKAR = {f: json.load(open(f'assets/adhkar/{f}.json')) for f in ('daily', 'ruqyah', 'hisn')}

# ---------- المرجع: quran.com ----------
say('# Quran data audit vs the Madinah mushaf')
chapters = jget(f'{API}/chapters?language=ar')['chapters']
assert len(chapters) == 114
FIELDS = 'text_qpc_hafs,text_uthmani,text_imlaei,juz_number,hizb_number,rub_el_hizb_number,page_number,sajdah_number,verse_key'
WFIELDS = 'code_v2,line_number,page_number,text_qpc_hafs'


def fetch_chapter(ch):
    out, page = [], 1
    while True:
        d = jget(f'{API}/verses/by_chapter/{ch}?words=true&per_page=50&page={page}'
                 f'&fields={FIELDS}&word_fields={WFIELDS}&mushaf=1')
        out += d['verses']
        nxt = d['pagination'].get('next_page')
        if not nxt:
            return out
        page = nxt


with ThreadPoolExecutor(6) as ex:
    REF = dict(zip(range(1, 115), ex.map(fetch_chapter, range(1, 115))))
total = sum(len(v) for v in REF.values())
say(f'reference verses fetched: {total}')
assert total == 6236, total


def ref(s, a):
    return REF[s][a - 1]


# ---------- أدوات المقارنة ----------
AR_DIGITS = '٠١٢٣٤٥٦٧٨٩'


def strip_num(t):
    return re.sub(r'[\s ]*[٠-٩]+\s*$', '', t).strip()


def ws(t):
    return re.sub(r'[\s ]+', ' ', t).strip()


# الهيكل: من غير تشكيل ولا علامات مصحف، وتوحيد أشكال الحروف — عشان نقارن الكلمات بين رسمين مختلفين.
MARKS = re.compile('[\u0610-\u061a\u064b-\u065f\u0670\u06d6-\u06ed\u08d3-\u08ff\u0640\u200b-\u200f\u2060-\u2064\ufeff]')


def skel(t):
    t = unicodedata.normalize('NFC', t)
    t = MARKS.sub('', t)
    t = (t.replace('ٱ', 'ا').replace('أ', 'ا').replace('إ', 'ا').replace('آ', 'ا')
         .replace('ی', 'ي').replace('ى', 'ي').replace('ک', 'ك').replace('ۀ', 'ه').replace('ة', 'ه')
         .replace('ؤ', 'و').replace('ئ', 'ي').replace('ء', ''))
    t = re.sub(r'[٠-٩0-9۞۩]', '', t)
    return re.sub(r'\s+', '', t)


def diff_words(a, b):
    """أول مكان بيختلف فيه نصّين (للعرض)."""
    for i, (x, y) in enumerate(zip(a, b)):
        if x != y:
            return f'…{a[max(0, i - 12):i + 12]}… ≠ …{b[max(0, i - 12):i + 12]}…'
    return f'length {len(a)} vs {len(b)}'


problems = 0


def bad(section, msg):
    global problems
    problems += 1
    say(f'  ✗ [{section}] {msg}')


# ١) عدد الآيات وأسماء السور
say('\n## 1. Surah names and ayah counts')
for c in chapters:
    s = c['id']
    n = c['verses_count']
    for name, arr in (('quran.json', Q['surahs']), ('madinah.json', M['surahs']), ('tajweed.json', T['surahs']), ('muyassar', TF['surahs'])):
        if len(arr[s - 1]) != n:
            bad('count', f'{name} surah {s}: {len(arr[s - 1])} ayahs, reference {n}')
    app = Q['surahNamesAr'][s - 1].replace('سورة ', '')
    if skel(app) != skel(c['name_arabic']):
        bad('name', f'surah {s}: app "{app}", reference "{c["name_arabic"]}"')
say('  done')

# ٢) نص مجمع الملك فهد (madinah.json) حرف حرف
say('\n## 2. madinah.json vs KFGQPC text (quran.com text_qpc_hafs), exact')
exact = 0
for s in range(1, 115):
    for a in range(1, len(REF[s]) + 1):
        mine = ws(strip_num(M['surahs'][s - 1][a - 1]))
        theirs = ws(strip_num(ref(s, a)['text_qpc_hafs']))
        if mine == theirs:
            exact += 1
        elif unicodedata.normalize('NFC', mine) == unicodedata.normalize('NFC', theirs):
            exact += 1
        else:
            same_words = skel(mine) == skel(theirs)
            bad('madinah', f'{s}:{a} {"(marks only)" if same_words else "(LETTERS DIFFER)"} {diff_words(mine, theirs)}')
say(f'  identical ayahs: {exact} / 6236')

# ٣) نص التنزيل (quran.json للخطوط التانية، tajweed.json للتلوين) — نفس الكلمات؟
say('\n## 3. Tanzil texts vs KFGQPC: same letters/words (diacritic style differences are expected)')
for name, get_t in (('quran.json', lambda s, a: Q['surahs'][s - 1][a - 1]),
                    ('tajweed.json', lambda s, a: T['surahs'][s - 1][a - 1][0])):
    same = 0
    for s in range(1, 115):
        for a in range(1, len(REF[s]) + 1):
            mine = get_t(s, a)
            if skel(mine) == skel(ref(s, a)['text_qpc_hafs']):
                same += 1
            else:
                bad(name, f'{s}:{a} {diff_words(skel(mine), skel(ref(s, a)["text_qpc_hafs"]))}  | app: {mine}')
    say(f'  {name}: same words in {same} / 6236')

# ٤) الأرباع (والأجزاء والأحزاب المحسوبة منها)
say('\n## 4. Quarter (rub) boundaries — 240, juz = 8 quarters, hizb = 4')
starts = {}
for s in range(1, 115):
    for v in REF[s]:
        r = v['rub_el_hizb_number']
        if r not in starts:
            starts[r] = tuple(map(int, v['verse_key'].split(':')))
ref_q = [starts[i] for i in range(1, 241)]
app_q = [tuple(x) for x in Q['quarters']]
for i, (x, y) in enumerate(zip(app_q, ref_q), 1):
    if x != y:
        bad('quarter', f'quarter {i} (juz {(i - 1) // 8 + 1}, hizb {(i - 1) // 4 + 1}): app {x[0]}:{x[1]}, reference {y[0]}:{y[1]}')
# الأجزاء والأحزاب من المرجع نفسه
for s in range(1, 115):
    for v in REF[s]:
        r = v['rub_el_hizb_number']
        if v['juz_number'] != (r - 1) // 8 + 1 or v['hizb_number'] != (r - 1) // 4 + 1:
            bad('juz/hizb', f"{v['verse_key']}: reference juz {v['juz_number']} hizb {v['hizb_number']} rub {r} inconsistent")
            break
say('  done')

# ٥) السجدات
say('\n## 5. Sajdah positions (۩)')
ref_sj = sorted(tuple(map(int, v['verse_key'].split(':'))) for s in REF for v in REF[s] if v.get('sajdah_number'))
say(f'  reference sajdahs ({len(ref_sj)}): {ref_sj}')
for name, get_t in (('madinah.json', lambda s, a: M['surahs'][s - 1][a - 1]),
                    ('quran.json', lambda s, a: Q['surahs'][s - 1][a - 1]),
                    ('tajweed.json', lambda s, a: T['surahs'][s - 1][a - 1][0])):
    mine = sorted((s, a) for s in range(1, 115) for a in range(1, len(REF[s]) + 1) if '۩' in get_t(s, a))
    if mine != ref_sj:
        bad('sajdah', f'{name}: {mine}')
say('  done')

# ٦) صفحات المصحف وسطوره (pages.json) مقابل quran.com: الصفحة والسطر وشكل كل كلمة وعلامة آية
say('\n## 6. Mushaf pages (pages.json): page, line and glyph of every word and ayah marker')
ref_glyphs = {}
for s in REF:
    for v in REF[s]:
        a = int(v['verse_key'].split(':')[1])
        for w in v['words']:
            for g in w['code_v2'].split():
                ref_glyphs.setdefault((s, a), []).append((w['page_number'], w['line_number'], g, w.get('char_type_name')))
app_words = {}
app_glyphs = {}
for pi, page in enumerate(P['pages'], 1):
    li = 0
    for line in page:
        li += 1
        if line[0] != 't':
            continue
        for w in line[1]:
            s, a, hafs, code = w
            app_words.setdefault((s, a), []).append((pi, li, hafs, code))
            for g in code.split():
                app_glyphs.setdefault((s, a), []).append((pi, li, g))
gb = 0
for key, rg in ref_glyphs.items():
    ag = app_glyphs.get(key, [])
    if key == (84, 21):
        # quran.com نفسه حاطط علامة الآية على سطر ١٣ (بعد قرئ)؛ المطبوع بعد يسجدون على سطر ١٤ — اتصلحت عندنا.
        rg = [x for x in rg if x[3] != 'end'] + [(589, 14, 'ﳁ', 'end')]
    if [(x[0], x[1], x[2]) for x in rg] != ag:
        gb += 1
        if gb <= 15:
            bad('pages', f'{key[0]}:{key[1]} app {[(x[1], x[2]) for x in ag]} reference {[(x[1], x[2], x[3]) for x in rg]}')
missing = set(ref_glyphs) - set(app_glyphs)
if missing:
    bad('pages', f'{len(missing)} ayahs missing from pages: {sorted(missing)[:10]}')
say(f'  ayahs whose glyph sequence (page, line, glyph) differs: {gb}')
# نص حفص بتاع الكلمات (اللي بيظهر في وضع خط حفص) = نص المجمع؟
hb = 0
for key, aws in app_words.items():
    mine = ws(strip_num(' '.join(w[2] for w in aws)))
    theirs = ws(strip_num(ref(*key)['text_qpc_hafs']))
    if mine != theirs and unicodedata.normalize('NFC', mine) != unicodedata.normalize('NFC', theirs):
        hb += 1
        if hb <= 10:
            bad('pages-hafs', f'{key[0]}:{key[1]} {diff_words(mine, theirs)}')
say(f'  hafs word text mismatches: {hb}')
# أول آية في كل صفحة
page_start = {}
for s in REF:
    for v in REF[s]:
        page_start.setdefault(v['page_number'], tuple(map(int, v['verse_key'].split(':'))))
for pi, page in enumerate(P['pages'], 1):
    first = next(((w[0], w[1]) for line in page if line[0] == 't' for w in line[1]), None)
    if first and page_start.get(pi) and first != page_start[pi]:
        bad('pages', f'page {pi} starts at {first}, reference {page_start[pi]}')

# ٧) مرجع تاني مستقل: Tanzil metadata
say('\n## 7. Second reference: Tanzil metadata (quarters, juz, sajdah, pages)')
try:
    js = get('https://tanzil.net/res/text/metadata/quran-data.js')

    def block(name):
        m = re.search(name + r'\s*=\s*\[(.*?)\];', js, re.S)
        return [tuple(map(int, x)) for x in re.findall(r'\[\s*(\d+)\s*,\s*(\d+)', m.group(1))]
    tq = block(r'QuranData\.HizbQaurter') or block(r'QuranData\.HizbQuarter')
    tq = [x for x in tq][:240]
    for i, (x, y) in enumerate(zip(app_q, tq), 1):
        if x != y:
            bad('tanzil-quarter', f'quarter {i}: app {x}, tanzil {y}')
    tp = block(r'QuranData\.Page')[:604]
    for i, st in enumerate(tp, 1):
        if page_start.get(i) and st != page_start[i]:
            bad('tanzil-page', f'page {i}: tanzil {st}, quran.com {page_start[i]}')
    ts = sorted(block(r'QuranData\.Sajda'))
    if ts != ref_sj:
        bad('tanzil-sajdah', f'tanzil {ts} vs quran.com {ref_sj}')
    say(f'  tanzil: {len(tq)} quarters, {len(tp)} pages, {len(ts)} sajdahs compared')
except Exception as e:
    say(f'  (tanzil not reachable: {e})')

# ٨) التفسير الميسر
say('\n## 8. Tafsir al-Muyassar vs quran.com tafsir 16')


def fetch_tafsir(ch):
    out, page = {}, 1
    while True:
        d = jget(f'{API}/tafsirs/16/by_chapter/{ch}?per_page=50&page={page}')
        for x in d['tafsirs']:
            out[x['verse_key']] = x['text']
        nxt = d.get('pagination', {}).get('next_page')
        if not nxt:
            return out
        page = nxt


try:
    with ThreadPoolExecutor(6) as ex:
        TREF = dict(zip(range(1, 115), ex.map(fetch_tafsir, range(1, 115))))
    def tnorm(t):
        t = re.sub(r'<[^>]+>', '', t)
        return re.sub(r'[^\u0621-\u064a]', '', skel(t))
    same = differ = 0
    for s in range(1, 115):
        for a in range(1, len(REF[s]) + 1):
            mine = TF['surahs'][s - 1][a - 1]
            theirs = TREF[s].get(f'{s}:{a}')
            if theirs is None:
                continue
            if tnorm(mine) == tnorm(theirs) or tnorm(theirs) in tnorm(mine) or tnorm(mine) in tnorm(theirs):
                same += 1
            else:
                differ += 1
                if differ <= 8:
                    bad('tafsir', f'{s}:{a}\n      app: {mine[:300]}\n      ref: {re.sub(r"<[^>]+>", "", theirs)[:300]}')
    say(f'  same {same}, different {differ}')
except Exception as e:
    say(f'  (tafsir reference not reachable: {e})')

# ٩) الآيات في الأذكار والرقية: المرجع + أول وآخر كلمة (للمراجعة بالعين)
say('\n## 9. Quran references inside adhkar / ruqyah (review by eye)')


def walk(x):
    if isinstance(x, dict):
        if 'quran' in x and isinstance(x['quran'], list) and len(x['quran']) == 3:
            yield x
        for v in x.values():
            yield from walk(v)
    elif isinstance(x, list):
        for v in x:
            yield from walk(v)


for f, data in ADHKAR.items():
    for it in walk(data):
        s, a1, a2 = it['quran']
        if not (1 <= s <= 114 and 1 <= a1 <= a2 <= len(REF[s])):
            bad('adhkar', f'{f} {it.get("id")}: bad range {it["quran"]}')
            continue
        first = strip_num(ref(s, a1)['text_qpc_hafs']).split(' ')[:3]
        last = strip_num(ref(s, a2)['text_qpc_hafs']).split(' ')[-3:]
        say(f'  {f}:{it.get("id")} {s}:{a1}-{a2} [{it.get("source", "")}] «{" ".join(first)} … {" ".join(last)}»')

# ١٠) الآيات المكتوبة بإيد في حصن المسلم بين { } — مكانها في القرآن، وهل الكلام مطابق؟
say('\n## 10. Verses quoted inside Hisn al-Muslim {…}: located and checked against the imlaei text')
def iskel(t):
    t = skel(t)
    return re.sub(r'[^\u0621-\u064a]', '', t).replace('ا', '').replace('و', '').replace('ي', '')
full, index = '', []
for s_ in range(1, 115):
    for a_ in range(1, len(REF[s_]) + 1):
        k = iskel(ref(s_, a_)['text_imlaei'])
        index.append((len(full), s_, a_))
        full += k
import bisect
starts_ = [x[0] for x in index]
def where(pos):
    i = bisect.bisect_right(starts_, pos) - 1
    return index[i][1], index[i][2]
quotes = []
madq = []
def walk_txt(x):
    if isinstance(x, str):
        quotes.extend(re.findall(r'\{([^}]*)\}', x))
        madq.extend(re.findall(r'﴿([^﴾]*)﴾', x))
    elif isinstance(x, dict):
        for v in x.values():
            walk_txt(v)
    elif isinstance(x, list):
        for v in x:
            walk_txt(v)
walk_txt(ADHKAR['hisn'])
found = notfound = 0
for qt in quotes:
    k = iskel(qt)
    if len(k) < 6:
        continue
    p_ = full.find(k)
    if p_ >= 0:
        found += 1
        a1, a2 = where(p_), where(p_ + len(k) - 1)
        say(f'  ✓ {a1[0]}:{a1[1]}–{a2[0]}:{a2[1]}  {ws(qt)[:70]}')
    else:
        notfound += 1
        bad('hisn', f'not found as-is in the Quran: {ws(qt)[:160]}')
say(f'  quotes located {found}, not located {notfound}')
qfull = skel(''.join(ref(s_, a_)['text_qpc_hafs'] for s_ in range(1, 115) for a_ in range(1, len(REF[s_]) + 1)))
ok_ = 0
for qt in madq:
    if skel(qt) in qfull:
        ok_ += 1
    else:
        bad('hisn-madinah', f'not exact Madinah text: {qt[:120]}')
say(f'  ﴿…﴾ quotes in Madinah text: {ok_} / {len(madq)} match the KFGQPC text')

say(f'\n# TOTAL PROBLEMS: {problems}')
open('audit-report.md', 'w').write('\n'.join(report))
