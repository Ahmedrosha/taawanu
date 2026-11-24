"""يطلّع لكل آية مقتبسة في حصن المسلم {…} نصها من مصحف المدينة (نص مجمع الملك فهد، quran.com text_qpc_hafs).
بيطبع سطر JSON لكل اقتباس: {"quote": ..., "ref": "s:a-s:a", "madinah": ...} — مش بيعدّل ملفات."""
import json, re, sys, time, urllib.request, unicodedata
API = 'https://api.quran.com/api/v4'
MARKS = re.compile('[ؐ-ًؚ-ٰٟۖ-ۭ࣓-ࣿـ​-‏⁠-⁤﻿]')


def get(url):
    for i in range(6):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent': 'taawanu'}), timeout=60) as r:
                return json.loads(r.read().decode())
        except Exception:
            time.sleep(2 + 3 * i)
    raise SystemExit('fetch failed ' + url)


def sk(t):
    t = MARKS.sub('', unicodedata.normalize('NFC', t))
    for a, b in (('ٱ', 'ا'), ('أ', 'ا'), ('إ', 'ا'), ('آ', 'ا'), ('ى', 'ي'), ('ة', 'ه'), ('ؤ', 'و'), ('ئ', 'ي'), ('ء', '')):
        t = t.replace(a, b)
    return re.sub(r'[^ء-ي]', '', t).replace('ا', '').replace('و', '').replace('ي', '')


# كل كلمات القرآن (imlaei + qpc_hafs + علامات نهاية الآية)
words = []  # (sk_imlaei, qpc_text, is_end, s, a)
for ch in range(1, 115):
    page = 1
    while True:
        d = get(f'{API}/verses/by_chapter/{ch}?words=true&per_page=50&page={page}&word_fields=text_imlaei,text_qpc_hafs')
        for v in d['verses']:
            s, a = map(int, v['verse_key'].split(':'))
            for w in v['words']:
                end = w['char_type_name'] == 'end'
                words.append(('' if end else sk(w['text_imlaei']), w['text_qpc_hafs'], end, s, a))
        page = d['pagination'].get('next_page')
        if not page:
            break
full, starts = '', []
for i, w in enumerate(words):
    starts.append(len(full)); full += w[0]

hisn = json.load(open('assets/adhkar/hisn.json'))
quotes = []


def walk(x):
    if isinstance(x, str):
        quotes.extend(re.findall(r'\{([^}]*)\}', x))
    elif isinstance(x, dict):
        [walk(v) for v in x.values()]
    elif isinstance(x, list):
        [walk(v) for v in x]


walk(hisn)
import bisect
for q in dict.fromkeys(quotes):
    k = sk(q)
    p = full.find(k)
    if p < 0:
        print(json.dumps({'quote': q, 'error': 'not found'}, ensure_ascii=False)); continue
    i = bisect.bisect_right(starts, p) - 1
    if starts[i] != p:
        print(json.dumps({'quote': q, 'error': 'starts mid-word'}, ensure_ascii=False)); continue
    j, acc = i, ''
    out = []
    while len(acc) < len(k):
        acc += words[j][0]; out.append(words[j]); j += 1
    if acc != k:
        print(json.dumps({'quote': q, 'error': 'ends mid-word'}, ensure_ascii=False)); continue
    # لو الاقتباس بيخلص آخر الآية، نضيف رقمها
    if j < len(words) and words[j][2]:
        out.append(words[j])
    text = ' '.join(w[1] for w in out)
    print(json.dumps({'quote': q, 'ref': f'{out[0][3]}:{out[0][4]}-{out[-1][3]}:{out[-1][4]}', 'madinah': text}, ensure_ascii=False))
