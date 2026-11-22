"""يجرّب أول وآخر آية في كل سورة لكل قارئ على everyayah (للتأكد إن تلاوته كاملة)."""
import sys, urllib.request
from concurrent.futures import ThreadPoolExecutor

AYAHS = [7,286,200,176,120,165,206,75,129,109,123,111,43,52,99,128,111,110,98,135,112,78,118,64,77,227,93,88,69,60,34,30,73,54,45,83,182,88,75,85,54,53,89,59,37,35,38,29,18,45,60,49,62,55,78,96,29,22,24,13,14,11,11,18,12,12,30,52,52,44,28,28,20,56,40,31,50,40,46,42,29,19,36,25,22,17,19,26,30,20,15,21,11,8,8,19,5,8,8,11,11,8,3,9,5,4,7,3,6,3,5,4,5,6]
assert len(AYAHS) == 114 and sum(AYAHS) == 6236

def ok(url):
    try:
        req = urllib.request.Request(url, headers={'Range': 'bytes=0-0', 'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status in (200, 206) and 'audio' in r.headers.get('Content-Type', '')
    except Exception:
        return False

def check(folder):
    base = f'https://everyayah.com/data/{folder}/'
    if not ok(base + '001001.mp3'):
        return folder, None
    urls = []
    for s, n in enumerate(AYAHS, 1):
        urls += [f'{base}{s:03d}001.mp3', f'{base}{s:03d}{n:03d}.mp3']
    with ThreadPoolExecutor(12) as ex:
        res = list(ex.map(ok, urls))
    missing = [u.rsplit('/', 1)[1][:-4] for u, r in zip(urls, res) if not r]
    return folder, missing

for folder in sys.argv[1:]:
    f, missing = check(folder)
    if missing is None:
        print(f'NOFOLDER {f}')
    elif missing:
        print(f'MISSING {f} {len(missing)}: {" ".join(missing[:20])}')
    else:
        print(f'OK {f}')
    sys.stdout.flush()
