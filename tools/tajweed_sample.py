# صفحة تجربة لمصحف التجويد الملون (خط V4) جنب الخط الحالي (V2). مؤقت.
import json, sys
page = int(sys.argv[1])
d = json.load(open('assets/mushaf/pages.json'))
lines = d['pages'][page - 1]
def html_lines(fam):
    out = []
    for ln in lines:
        if ln[0] == 't':
            out.append('<div class="l" style="font-family:%s">%s</div>' % (fam, ' '.join(w[3] for w in ln[1])))
        elif ln[0] == 'h':
            out.append('<div class="h">سورة %d</div>' % ln[1])
        elif ln[0] == 'b':
            out.append('<div class="h">﷽</div>')
    return '\n'.join(out)
html = f'''<!doctype html><html dir="rtl"><head><meta charset="utf-8"><style>
@font-face{{font-family:V4;src:url(v4.woff2)}}
@font-face{{font-family:V2;src:url(v2.woff2)}}
body{{margin:0;display:flex;gap:30px;padding:30px;background:#e9e3d3;font-family:sans-serif}}
.p{{width:520px;background:#FBF7EC;padding:30px 24px;border-radius:12px}}
.t{{text-align:center;font:600 18px sans-serif;margin-bottom:14px;color:#555}}
.l{{font-size:30px;line-height:1.9;text-align:justify;text-align-last:justify;white-space:nowrap}}
.h{{text-align:center;font-size:22px;padding:6px;color:#333}}
.dark{{background:#0B1220;color:#E6EDF7}} .dark .t{{color:#9AA8BD}} .dark .l{{font-palette:dark}}
@font-palette-values --dark{{font-family:V4;base-palette:1}}
.dark .l.v4{{font-palette:--dark}}
</style></head><body>
<div class="p"><div class="t">التجويد الملون (V4)</div>{html_lines('V4')}</div>
<div class="p"><div class="t">الحالي (V2)</div>{html_lines('V2')}</div>
<div class="p dark"><div class="t">التجويد الملون · الوضع الليلي</div>{html_lines('V4').replace('class="l"','class="l v4"')}</div>
</body></html>'''
open(sys.argv[2], 'w').write(html)
