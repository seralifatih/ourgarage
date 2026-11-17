"""Live end-to-end test: household premium via claim-premium and RevenueCat.

No purchase is needed: entitlements come from RevenueCat promotional grants
(REST API, secret key) on two throwaway users. The app-facing calls are made
exactly as the app makes them — claim-premium with the user's own JWT, and
households read through PostgREST with RLS on.

Users og-e2e-<run tag>-{owner,member}@example.com share one household:

  1. nobody entitled -> household not premium
  2. member gets a daily promo and claims -> premium, member is the source
  3. owner (not entitled) claims -> still premium: one member's state never
     wipes premium another member provides
  4. member's promo revoked, owner claims -> premium cleared (RevenueCat is
     the truth, whoever triggers the check)
  5. owner gets a lifetime promo and claims -> premium, no expiry; a repeat
     claim is answered from the database (no RevenueCat call)
  6. owner (the payer) leaves -> premium cleared; member gets a promo and
     claims -> premium restored
  7. claim-premium without a JWT and the webhook without its secret -> 401,
     and the household is untouched

RevenueCat may also send our webhook events for these promo grants and
revokes. Every reconcile converges on RevenueCat's truth, but one that fetched
before a grant can land just after a claim, so steps that change state
re-claim briefly until the expected state holds (see claim_until).

Cleanup removes the household and users first, then revokes the promos and
deletes the two RevenueCat customers. Prints ids and statuses only, never keys
or tokens.

Environment: as e2e_delete_account.py, plus
  REVENUECAT_SECRET_KEY   RevenueCat secret (sk_) API key — the same one set
                          in Supabase secrets. Never printed.

Run:
  python -I supabase/tests/e2e_claim_premium.py --live
"""
import json
import os
import secrets
import sys
import time
import urllib.error
import urllib.request


def _env(name):
    value = os.environ.get(name, '').strip()
    if not value:
        sys.exit(f'{name} is not set; see the docstring at the top of this file.')
    return value


if '--live' not in sys.argv[1:]:
    sys.exit('This test creates and deletes real users, rows and RevenueCat customers. '
             'Re-run with --live to proceed.')

URL = _env('SUPABASE_URL').rstrip('/')
ANON = _env('SUPABASE_ANON_KEY')
SERVICE = _env('SUPABASE_SERVICE_ROLE_KEY')
RC_KEY = _env('REVENUECAT_SECRET_KEY')
ENTITLEMENT = os.environ.get('REVENUECAT_ENTITLEMENT_ID', 'premium')
RC = 'https://api.revenuecat.com/v1'


def http(method, url, body=None, headers=None):
    """Returns (status, parsed JSON or text). Never raises on HTTP errors."""
    headers = dict(headers or {})
    data = None
    if body is not None:
        headers['Content-Type'] = 'application/json'
        data = json.dumps(body).encode()
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=60) as response:
            status, payload = response.status, response.read()
    except urllib.error.HTTPError as error:
        status, payload = error.code, error.read()
    try:
        return status, (json.loads(payload) if payload else None)
    except ValueError:
        return status, payload.decode(errors='replace')[:200]


def call(method, path, body=None, *, token=None, apikey=None, prefer=None):
    headers = {'apikey': apikey or SERVICE, 'Authorization': f'Bearer {token or SERVICE}'}
    if prefer:
        headers['Prefer'] = prefer
    return http(method, URL + path, body, headers)


def as_user(method, path, jwt, body=None):
    return call(method, f'/rest/v1/{path}', body, token=jwt, apikey=ANON)


def as_service(method, path, body=None):
    return call(method, f'/rest/v1/{path}', body, prefer='return=representation')


def revenuecat(method, path, body=None):
    return http(method, RC + path, body, {'Authorization': f'Bearer {RC_KEY}'})


def grant_promo(user_id, duration):
    status, _ = revenuecat('POST', f'/subscribers/{user_id}/entitlements/{ENTITLEMENT}/promotional',
                           {'duration': duration})
    assert status in (200, 201), ('grant promo', duration, status)


def revoke_promos(user_id):
    return revenuecat('POST', f'/subscribers/{user_id}/entitlements/{ENTITLEMENT}/revoke_promotionals')[0]


def claim(jwt):
    return call('POST', '/functions/v1/claim-premium', {}, token=jwt, apikey=ANON)


checks = []


def check(name, condition, detail=''):
    checks.append((name, bool(condition)))
    mark = 'PASS' if condition else 'FAIL'
    suffix = f' — {detail}' if detail and not condition else ''
    print(f'  [{mark}] {name}{suffix}')


tag = time.strftime('%Y%m%d%H%M%S') + '-' + secrets.token_hex(3)
users = {}
households = []


def create_user(role):
    email = f'og-e2e-{tag}-{role}@example.com'
    password = secrets.token_urlsafe(24)
    status, body = call('POST', '/auth/v1/admin/users', {
        'email': email, 'password': password, 'email_confirm': True,
        'user_metadata': {'purpose': 'ourgarage claim-premium e2e test'},
    })
    assert status in (200, 201), ('create user', role, status)
    users[role] = body['id']
    status, body = call('POST', '/auth/v1/token?grant_type=password',
                        {'email': email, 'password': password}, token=ANON, apikey=ANON)
    assert status == 200 and body.get('access_token'), ('sign-in', role, status)
    jwt = body['access_token']
    status, _ = as_user('POST', 'profiles', jwt, {'id': users[role], 'display_name': role})
    assert status == 201, ('profile', role, status)
    return users[role], jwt


def is_lifetime(expires_at):
    """A lifetime promo: RevenueCat reports it with an expiry about 200 years
    out rather than none (seen 2026-11-17), while a lifetime purchase has none.
    Either counts."""
    if expires_at is None:
        return True
    year = int(str(expires_at)[:4])
    return year - int(time.strftime('%Y')) > 50


def premium_seen_by(jwt, household):
    """The household's premium columns, as a member reads them ({} if none)."""
    _, rows = as_user('GET', f'households?id=eq.{household}'
                             '&select=is_premium,premium_source_user_id,premium_expires_at', jwt)
    return rows[0] if isinstance(rows, list) and rows else {}


def claim_until(jwt, reader_jwt, household, ok, attempts=5):
    """Claims as [jwt], then reads as [reader_jwt], until ok(row) holds."""
    p = {}
    for attempt in range(attempts):
        status, _ = claim(jwt)
        p = premium_seen_by(reader_jwt, household)
        if status == 200 and ok(p):
            return True, p
        time.sleep(1 + attempt)
    return False, p


def main():
    print(f'run tag: {tag}')
    owner, owner_jwt = create_user('owner')
    member, member_jwt = create_user('member')

    status, household = as_user('POST', 'rpc/create_household', owner_jwt,
                                {'household_name': 'E2E premium'})
    assert status == 200, ('create_household', status)
    households.append(household)
    code = ''.join(secrets.choice('23456789ABCDEFGHJKMNPQRSTUVWXYZ') for _ in range(6))
    status, _ = as_user('POST', 'household_invites', owner_jwt, {
        'household_id': household, 'code': code, 'created_by': owner,
        'expires_at': '2099-01-01T00:00:00Z'})
    assert status == 201, ('invite', status)
    status, _ = as_user('POST', 'rpc/accept_household_invite', member_jwt, {'invite_code': code})
    assert status == 200, ('join', status)

    print('1. nobody entitled')
    status, body = claim(member_jwt)
    check('claim succeeds (200)', status == 200, (status, body))
    check('household not premium', premium_seen_by(owner_jwt, household).get('is_premium') is False)

    print('2. member entitled (daily promo)')
    grant_promo(member, 'daily')
    ok, p = claim_until(member_jwt, owner_jwt, household,
                        lambda p: p.get('is_premium') and p.get('premium_source_user_id') == member)
    check('member claim -> premium, member is the source, with an expiry',
          ok and p.get('premium_expires_at') is not None, p)

    print('3. an unentitled member triggers a check')
    status, _ = claim(owner_jwt)
    p = premium_seen_by(member_jwt, household)
    check("owner's claim keeps the member's premium",
          status == 200 and p.get('is_premium') and p.get('premium_source_user_id') == member, p)

    print('4. member promo revoked')
    check('revoke member promo', revoke_promos(member) in (200, 201))
    ok, p = claim_until(owner_jwt, owner_jwt, household, lambda p: p.get('is_premium') is False)
    check('premium cleared once nobody is entitled', ok, p)

    print('5. owner entitled (lifetime promo)')
    grant_promo(owner, 'lifetime')
    ok, p = claim_until(owner_jwt, member_jwt, household,
                        lambda p: p.get('is_premium') and p.get('premium_source_user_id') == owner
                        and is_lifetime(p.get('premium_expires_at')))
    check('owner claim -> lifetime premium, owner is the source', ok, p)
    cached, status, body = False, None, None
    for attempt in range(5):
        status, body = claim(owner_jwt)
        cached = status == 200 and isinstance(body, dict) and body.get('cached') is True
        if cached:
            break
        time.sleep(1 + attempt)
    check('a repeat claim is answered from the database', cached, (status, body))

    print('6. the payer leaves')
    status, outcome = as_user('POST', 'rpc/leave_household', owner_jwt, {'hid': household})
    check("owner leaves -> 'transferred'", status == 200 and outcome == 'transferred',
          (status, outcome))
    p = premium_seen_by(member_jwt, household)
    check("the leaver's premium went with them", p.get('is_premium') is False, p)
    grant_promo(member, 'daily')
    ok, p = claim_until(member_jwt, member_jwt, household,
                        lambda p: p.get('is_premium') and p.get('premium_source_user_id') == member)
    check('a still-entitled member restores premium', ok, p)

    print('7. authentication')
    before = premium_seen_by(member_jwt, household)
    status, _ = call('POST', '/functions/v1/claim-premium', {}, token=ANON, apikey=ANON)
    check('claim-premium without a user JWT -> 401', status == 401, status)
    status, _ = http('POST', URL + '/functions/v1/revenuecat-webhook',
                     {'event': {'type': 'EXPIRATION', 'app_user_id': member}},
                     {'Authorization': 'not-the-secret'})
    check('webhook with a wrong secret -> 401', status == 401, status)
    after = premium_seen_by(member_jwt, household)
    check('...and the household is untouched',
          after == before and after.get('is_premium'), (before, after))


def _step(action):
    """Runs one cleanup step; a network error must not stop the rest."""
    try:
        return action()
    except Exception as error:  # noqa: BLE001 — cleanup is best effort
        print(f'  cleanup step failed: {type(error).__name__}')
        return None


def cleanup():
    print('cleanup')
    # Supabase first: test users left in the live project matter more than
    # RevenueCat test customers.
    for household in households:
        _step(lambda h=household: as_service('DELETE', f'households?id=eq.{h}'))
    for user_id in users.values():
        _step(lambda u=user_id: as_service('DELETE', f'households?owner_id=eq.{u}'))
        _step(lambda u=user_id: call('DELETE', f'/auth/v1/admin/users/{u}'))
    for user_id in users.values():
        _step(lambda u=user_id: revoke_promos(u))
        _step(lambda u=user_id: revenuecat('DELETE', f'/subscribers/{u}'))

    remaining = 0
    try:
        for user_id in users.values():
            remaining += call('GET', f'/auth/v1/admin/users/{user_id}')[0] == 200
        for household in households:
            _, rows = as_service('GET', f'households?id=eq.{household}&select=id')
            remaining += len(rows) if isinstance(rows, list) else 1
    except Exception as error:  # noqa: BLE001
        print(f'  could not verify cleanup: {type(error).__name__}')
        remaining = -1
    print(f'  remaining test data: {remaining}')
    checks.append(('cleanup: no test data remains', remaining == 0))


try:
    main()
except AssertionError as error:
    print('SETUP ERROR:', str(error)[:200])
    checks.append(('script completed', False))
except Exception as error:  # noqa: BLE001 — still report a RESULT line
    print('ERROR:', type(error).__name__, str(error)[:200])
    checks.append(('script completed', False))
finally:
    cleanup()

passed = sum(1 for _, ok in checks if ok)
print(f'\nRESULT: {passed}/{len(checks)} checks passed')
sys.exit(0 if passed == len(checks) else 1)
