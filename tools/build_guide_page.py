"""Builds site/guide.html from lib/features/guide/guide_content.dart, so the website guide matches the app.

Run: python3 tools/build_guide_page.py
"""
import html
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = (ROOT / 'lib/features/guide/guide_content.dart').read_text()

# Material icon name (Flutter) -> Material Symbols name.
def symbol(name):
    name = re.sub(r'_(outlined|rounded|alt_1_outlined|alt_1|outline)$', '', name)
    return {'notifications_none': 'notifications'}.get(name, name)

ICONS = dict(re.findall(r"'(\w+)': Icons\.(\w+),", SRC))

STR = r"'((?:[^'\\]|\\.)*)'"
TOKEN = re.compile(r"GuideSection\(Icons\.(\w+), " + STR + r"|(GText|GNote)\(" + STR + r"\)|(GBullets|GTable|GLegend)\(\[|\]\),?|\(" + STR + r", " + STR + r"\)|" + STR)


def unq(s):
    return s.replace("\\'", "'")


def parse(block):
    sections, cur, mode, items = [], None, None, []
    for m in TOKEN.finditer(block):
        if m.group(1):
            cur = {'icon': m.group(1), 'title': unq(m.group(2)), 'blocks': []}
            sections.append(cur)
        elif m.group(3):
            cur['blocks'].append((m.group(3), unq(m.group(4))))
        elif m.group(5):
            mode, items = m.group(5), []
        elif m.group(0).startswith(']') and mode:
            cur['blocks'].append((mode, items))
            mode = None
        elif m.group(6) is not None and mode:
            items.append((unq(m.group(6)), unq(m.group(7))))
        elif m.group(8) is not None and mode:
            items.append(unq(m.group(8)))
    return sections


def inline(text):
    t = html.escape(text, quote=False)
    t = re.sub(r'\*\*(.+?)\*\*', r'<b>\1</b>', t)
    return re.sub(r'\{i:(\w+)\}', lambda m: f'<span class="ms">{symbol(ICONS.get(m.group(1), "help"))}</span>', t)


def render(sections):
    out = []
    for i, s in enumerate(sections):
        body = []
        for kind, data in s['blocks']:
            if kind == 'GText':
                body.append(f'<p>{inline(data)}</p>')
            elif kind == 'GNote':
                body.append(f'<p class="note">{inline(data)}</p>')
            elif kind == 'GBullets':
                body.append('<ul>' + ''.join(f'<li>{inline(x)}</li>' for x in data) + '</ul>')
            elif kind == 'GTable':
                body.append('<table>' + ''.join(f'<tr><td>{inline(a)}</td><td>{inline(b)}</td></tr>' for a, b in data) + '</table>')
            elif kind == 'GLegend':
                body.append('<ul class="legend">' + ''.join(f'<li><i class="sw {st}"></i>{inline(lbl)}</li>' for st, lbl in data) + '</ul>')
        out.append(f'<details{" open" if i == 0 else ""}><summary><span class="ms">{symbol(s["icon"])}</span>{html.escape(s["title"])}</summary>'
                   + ''.join(body) + '</details>')
    return '\n'.join(out)


ar_src, en_src = SRC.split('const guideAr')[1].split('const guideEn')
AR, EN = render(parse(ar_src)), render(parse(en_src))

page = f'''<!doctype html>
<html lang="ar" dir="rtl">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>دليل الاستخدام · تعاونوا</title>
  <meta name="description" content="شرح كامل لكل شاشات تطبيق تعاونوا: المجموعات، والدعوة، والخريطة، والقراية، والتلاوة، والتفسير، والنقاط.">
  <meta name="theme-color" content="#1E3A8A">
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans+Arabic:wght@400;600;700&family=Reem+Kufi:wght@700&display=swap" rel="stylesheet">
  <link href="https://fonts.googleapis.com/css2?family=Material+Symbols+Outlined:opsz,wght,FILL,GRAD@20..24,400,0,0&display=block" rel="stylesheet">
  <link rel="stylesheet" href="/style.css">
</head>
<body class="home guide">
  <nav class="top">
    <a class="brand" href="/">
      <svg width="34" height="34" viewBox="0 0 200 200" aria-hidden="true">
        <path id="h" d="M100 84 C80 70 50 64 28 72 Q15 76 19 86 Q12 93 19 103 Q12 110 20 120 Q15 128 24 134 L32 148 C54 140 80 142 100 154 Z" fill="#FFFFFF"/>
        <use href="#h" fill="#BFDBFE" transform="translate(200 0) scale(-1 1)"/>
        <circle cx="100" cy="56" r="9" fill="#D4A537"/>
      </svg>
      <span data-ar="تعاونوا" data-en="Taawanu">تعاونوا</span>
    </a>
    <button id="lang" class="lang" type="button">English</button>
  </nav>

  <main class="section narrow">
    <h1 data-ar="دليل الاستخدام" data-en="User guide">دليل الاستخدام</h1>
    <p class="lead" data-ar="شرح كل شاشة في التطبيق. دوس على أي قسم عشان تفتحه." data-en="How every screen in the app works. Tap a section to open it.">شرح كل شاشة في التطبيق. دوس على أي قسم عشان تفتحه.</p>
    <div class="g-ar">
{AR}
    </div>
    <div class="g-en" lang="en" dir="ltr">
{EN}
    </div>
  </main>

  <footer class="foot">
    <a href="/" data-ar="الرئيسية" data-en="Home">الرئيسية</a> ·
    <a href="/privacy" data-ar="سياسة الخصوصية" data-en="Privacy policy">سياسة الخصوصية</a> ·
    <a href="mailto:support@taawanu.app">support@taawanu.app</a>
  </footer>

  <script>
    (function () {{
      var btn = document.getElementById('lang');
      function apply(lang) {{
        var en = lang === 'en';
        document.documentElement.lang = en ? 'en' : 'ar';
        document.documentElement.dir = en ? 'ltr' : 'rtl';
        document.querySelectorAll('[data-ar]').forEach(function (el) {{
          el.innerHTML = el.getAttribute(en ? 'data-en' : 'data-ar');
        }});
        document.title = en ? 'User guide · Taawanu' : 'دليل الاستخدام · تعاونوا';
        btn.textContent = en ? 'عربي' : 'English';
        try {{ localStorage.setItem('lang', lang); }} catch (e) {{}}
      }}
      var saved = null;
      try {{ saved = localStorage.getItem('lang'); }} catch (e) {{}}
      if (!saved && navigator.language && navigator.language.indexOf('ar') !== 0) saved = 'en';
      if (saved === 'en') apply('en');
      btn.addEventListener('click', function () {{ apply(document.documentElement.lang === 'en' ? 'ar' : 'en'); }});
    }})();
  </script>
</body>
</html>
'''
(ROOT / 'site/guide.html').write_text(page)
print('sections:', AR.count('<details'), EN.count('<details'))
