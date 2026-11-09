# مؤقت: صورة للتجويد في الوضع الليلي (لوحة الخط التانية) وللنص المتصل الملون.
import json, struct, sys
src = open('p50.ttf', 'rb').read()
b = bytearray(src)
n = struct.unpack('>H', b[4:6])[0]
for i in range(n):
    r = 12 + i * 16
    if b[r:r+4] == b'CPAL':
        off = struct.unpack('>I', b[r+8:r+12])[0]
        np_ = struct.unpack('>H', b[off+4:off+6])[0]
        print('palettes', np_)
        b[off+12:off+14] = b[off+14:off+16]
open('p50d.ttf', 'wb').write(b)
d = json.load(open('assets/mushaf/pages.json'))
lines = d['pages'][49]
pg = '\n'.join('<div class="l">%s</div>' % ' '.join(w[3] for w in ln[1]) for ln in lines if ln[0] == 't')
tj = json.load(open('assets/quran/tajweed.json'))
light = ['#A0161B','#E0262B','#E8791A','#B8860B','#169C3B','#1E88E5','#9AA0A6']
dark = ['#FF6B6B','#FF8A80','#FFB74D','#E6C35C','#5ED68A','#64B5F6','#7D8590']
def ayahs(pal):
    out = []
    for a in range(1, 8):
        t, f = tj['surahs'][1][a-1]
        t += ' '
        h, i = '', 0
        for r in range(0, len(f), 3):
            k, s0, e0 = f[r], f[r+1], f[r+2]
            if s0 > i: h += t[i:s0]
            s0 = max(s0, i)
            h += '<span style="color:%s">%s</span>' % (pal[k], t[s0:e0]); i = e0
        h += t[i:] + '﴿%d﴾ ' % a
        out.append(h)
    return ''.join(out)
html = f'''<!doctype html><html dir="rtl"><head><meta charset="utf-8">
<link href="https://fonts.googleapis.com/css2?family=Amiri+Quran&display=block" rel="stylesheet">
<style>@font-face{{font-family:D;src:url(p50d.ttf)}}
body{{margin:0;display:flex;gap:24px;padding:24px;background:#000}}
.p{{width:520px;padding:24px;border-radius:12px}}
.l{{font-family:D;font-size:30px;line-height:1.9;text-align:justify;text-align-last:justify;white-space:nowrap;color:#E6EDF7}}
.tx{{font-family:'Amiri Quran';font-size:28px;line-height:2.1;text-align:justify}}
.t{{font:600 16px sans-serif;text-align:center;margin-bottom:10px}}</style></head><body>
<div class="p" style="background:#0B1220"><div class="t" style="color:#9AA8BD">صفحات التجويد · ليلي (بعد التعديل)</div>{pg}</div>
<div class="p" style="background:#FBF7EC"><div class="t">النص المتصل الملون</div><div class="tx" style="color:#222">{ayahs(light)}</div></div>
<div class="p" style="background:#0B1220"><div class="t" style="color:#9AA8BD">النص المتصل الملون · ليلي</div><div class="tx" style="color:#E6EDF7">{ayahs(dark)}</div></div>
</body></html>'''
open('index.html', 'w').write(html)
