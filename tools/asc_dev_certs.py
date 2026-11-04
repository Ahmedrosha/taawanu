"""Revokes the throwaway "Created via API" development certificates that Xcode makes on CI runners.

Every TestFlight build signs on a fresh runner, so Xcode creates a new development certificate each
time, and Apple caps how many an account can have. Running this before and after each build keeps the
count at zero. Certificates made by hand (e.g. "Apple Development: Ahmed Omran") and all distribution
certificates are left alone.

Env: KEY_ID, ISSUER_ID, KEY_PATH (the .p8 App Store Connect API key).
"""
import json
import os
import sys
import time
import urllib.request

import jwt  # pyjwt[crypto]

API = 'https://api.appstoreconnect.apple.com/v1'


def token():
    key = open(os.environ['KEY_PATH']).read()
    now = int(time.time())
    return jwt.encode(
        {'iss': os.environ['ISSUER_ID'], 'iat': now, 'exp': now + 600, 'aud': 'appstoreconnect-v1'},
        key, algorithm='ES256', headers={'kid': os.environ['KEY_ID'], 'typ': 'JWT'},
    )


def call(method, path, tok):
    req = urllib.request.Request(API + path, method=method, headers={'Authorization': f'Bearer {tok}'})
    with urllib.request.urlopen(req, timeout=30) as r:
        body = r.read()
    return json.loads(body) if body else None


def main():
    tok = token()
    list_only = '--list' in sys.argv
    certs = call('GET', '/certificates?filter[certificateType]=DEVELOPMENT,IOS_DEVELOPMENT&limit=200', tok)['data']
    revoked = 0
    for c in certs:
        a = c['attributes']
        label = f"{a.get('name')} / {a.get('displayName')}"
        api = 'Created via API' in (a.get('name') or '') or 'Created via API' in (a.get('displayName') or '')
        if list_only:
            print('found:', label, a.get('expirationDate'))
            if api:
                print(f"::notice title=CI certificate exists::{label}")
            continue
        if api:
            try:
                call('DELETE', f"/certificates/{c['id']}", tok)
                revoked += 1
                print('revoked:', label)
            except Exception as e:  # noqa: BLE001 — one failure shouldn't stop the build
                print('could not revoke', label, e)
        else:
            print('kept:', label)
    print(f'revoked {revoked} of {len(certs)} development certificates' if not list_only else f'{len(certs)} development certificates')


if __name__ == '__main__':
    try:
        main()
    except Exception as e:  # noqa: BLE001 — cleanup is best-effort
        print('::warning title=Certificate cleanup::', e)
        sys.exit(0)
