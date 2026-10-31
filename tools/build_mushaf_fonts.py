"""يحوّل خطوط صفحات المجمع (QPC V2) من woff2 لـ ttf عشان التطبيق يقدر يحمّلها.
التحويل بيغيّر شكل الملف بس (من غير أي تعديل في الخط نفسه).

التشغيل:  python3 tools/build_mushaf_fonts.py <مجلد fonts/QPC2> <مجلد الناتج>
"""
import shutil
import sys
from pathlib import Path

from fontTools.ttLib import TTFont

src, out = Path(sys.argv[1]), Path(sys.argv[2])
out.mkdir(parents=True, exist_ok=True)
for p in range(1, 605):
    font = TTFont(src / f'p{p:03d}.woff2', recalcTimestamp=False)
    font.flavor = None
    font.save(out / f'p{p:03d}.ttf')
shutil.copyfile(src / 'QPC2BSML.ttf', out / 'bsml.ttf')
print('fonts:', len(list(out.glob('*.ttf'))))
