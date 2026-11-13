"""Prepares (and optionally submits) the iOS version in App Store Connect.

Steps: find or create the version, attach the build, write "What's New" and "Promotional Text" for
each localization, and, only when SUBMIT=true, submit it for review.

Prints states and locale codes only (the repo is public: no names, emails or ids in the log).

Env: KEY_ID, ISSUER_ID, KEY_PATH, VERSION (e.g. 1.0.29), BUILD (build number, empty = newest), SUBMIT (true/false).
"""
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt  # pyjwt[crypto]

API = 'https://api.appstoreconnect.apple.com'
BUNDLE = 'com.taawanu.taawanu'


def token():
    key = open(os.environ['KEY_PATH']).read()
    now = int(time.time())
    return jwt.encode(
        {'iss': os.environ['ISSUER_ID'], 'iat': now, 'exp': now + 600, 'aud': 'appstoreconnect-v1'},
        key, algorithm='ES256', headers={'kid': os.environ['KEY_ID'], 'typ': 'JWT'},
    )


TOK = token()


def call(method, path, body=None):
    req = urllib.request.Request(
        API + path if path.startswith('/') else path, method=method,
        data=None if body is None else json.dumps(body).encode(),
        headers={'Authorization': f'Bearer {TOK}', 'Content-Type': 'application/json'},
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        msg = e.read().decode()[:700].replace('%', '%25').replace('\n', ' ')
        print(f'::error title=ASC {e.code} {method} {path.split("?")[0]}::{msg}')
        sys.exit(1)


def read(path):
    p = os.path.join(os.path.dirname(__file__), '..', path)
    return open(p, encoding='utf-8').read().strip()


version = os.environ['VERSION'].strip()
build_no = os.environ.get('BUILD', '').strip()
submit = os.environ.get('SUBMIT', 'false').strip().lower() == 'true'

app = call('GET', '/v1/apps?' + urllib.parse.urlencode({'filter[bundleId]': BUNDLE}))['data']
if not app:
    print('::error::App not found for the bundle id'); sys.exit(1)
app_id = app[0]['id']

# ١) النسخة: موجودة بالرقم ده، أو نسخة لسه قابلة للتعديل، أو نعمل واحدة جديدة.
EDITABLE = {'PREPARE_FOR_SUBMISSION', 'DEVELOPER_REJECTED', 'REJECTED', 'METADATA_REJECTED', 'INVALID_BINARY'}
vers = call('GET', f'/v1/apps/{app_id}/appStoreVersions?filter[platform]=IOS&limit=20')['data']
for v in vers:
    a = v['attributes']
    print(f"version {a['versionString']}: {a.get('appStoreState')}")
ver = next((v for v in vers if v['attributes']['versionString'] == version), None)
if ver is None:
    edit = next((v for v in vers if v['attributes'].get('appStoreState') in EDITABLE), None)
    if edit is not None:
        ver = call('PATCH', f"/v1/appStoreVersions/{edit['id']}",
                   {'data': {'type': 'appStoreVersions', 'id': edit['id'], 'attributes': {'versionString': version}}})['data']
        print(f'renamed editable version to {version}')
    else:
        ver = call('POST', '/v1/appStoreVersions', {'data': {
            'type': 'appStoreVersions', 'attributes': {'platform': 'IOS', 'versionString': version},
            'relationships': {'app': {'data': {'type': 'apps', 'id': app_id}}}}})['data']
        print(f'created version {version}')
state = ver['attributes'].get('appStoreState')
if state not in EDITABLE:
    print(f'::error::Version {version} is in state {state}: not editable, nothing changed'); sys.exit(1)
vid = ver['id']

# ٢) البناء.
q = {'filter[app]': app_id, 'filter[preReleaseVersion.version]': version, 'sort': '-version', 'limit': '10'}
if build_no:
    q['filter[version]'] = build_no
builds = call('GET', '/v1/builds?' + urllib.parse.urlencode(q))['data']
builds = [b for b in builds if not b['attributes'].get('expired')]
for b in builds:
    print(f"build {b['attributes']['version']}: {b['attributes'].get('processingState')}")
if not builds:
    print(f'::error::No build found for {version} {build_no}'); sys.exit(1)
b = builds[0]
if b['attributes'].get('processingState') != 'VALID':
    print('::error::Build is not processed yet (not VALID). Try again in a few minutes.'); sys.exit(1)
call('PATCH', f'/v1/appStoreVersions/{vid}/relationships/build', {'data': {'type': 'builds', 'id': b['id']}})
print(f"attached build {b['attributes']['version']}")

# ٣) النصوص لكل لغة.
locs = call('GET', f'/v1/appStoreVersions/{vid}/appStoreVersionLocalizations?limit=50')['data']
for l in locs:
    code = l['attributes']['locale']
    lang = code.split('-')[0].lower()
    if lang == 'ar':
        notes, promo = read('distribution/whatsnew/whatsnew-ar'), read('distribution/ios/promo-ar.txt')
    elif lang == 'en':
        notes, promo = read('distribution/whatsnew/whatsnew-en-US'), read('distribution/ios/promo-en.txt')
    else:
        print(f'skipped locale {code}')
        continue
    call('PATCH', f"/v1/appStoreVersionLocalizations/{l['id']}", {'data': {
        'type': 'appStoreVersionLocalizations', 'id': l['id'],
        'attributes': {'whatsNew': notes, 'promotionalText': promo}}})
    print(f'texts written for {code}')
if not locs:
    print('::warning::No localizations on this version')

# ٤) التقديم للمراجعة (بس لو SUBMIT=true).
if not submit:
    print('::notice title=Prepared::Version prepared, NOT submitted (SUBMIT=false)')
    sys.exit(0)
subs = call('GET', f'/v1/apps/{app_id}/reviewSubmissions?filter[platform]=IOS&filter[state]=READY_FOR_REVIEW')['data']
sub = subs[0] if subs else call('POST', '/v1/reviewSubmissions', {'data': {
    'type': 'reviewSubmissions', 'attributes': {'platform': 'IOS'},
    'relationships': {'app': {'data': {'type': 'apps', 'id': app_id}}}}})['data']
items = call('GET', f"/v1/reviewSubmissions/{sub['id']}/items?limit=20")['data']
if not items:
    call('POST', '/v1/reviewSubmissionItems', {'data': {
        'type': 'reviewSubmissionItems',
        'relationships': {
            'reviewSubmission': {'data': {'type': 'reviewSubmissions', 'id': sub['id']}},
            'appStoreVersion': {'data': {'type': 'appStoreVersions', 'id': vid}}}}})
call('PATCH', f"/v1/reviewSubmissions/{sub['id']}", {'data': {
    'type': 'reviewSubmissions', 'id': sub['id'], 'attributes': {'submitted': True}}})
print('::notice title=Submitted::Submitted for review')
