"""Live end-to-end test: invites, joining, the roster, removing and leaving.

Everything that matters runs as real users through PostgREST with their own
JWTs (anon key + user token, RLS on) — exactly the calls the 1.0.9 app makes.
The service role is used only to create the throwaway users and to clean up.

Creates two users (og-e2e-<run tag>-{owner,member}@example.com) and checks:

  * the owner creates a household (rpc/create_household) and an invite; a
    member cannot create invites
  * the member joins with the code (rpc/accept_household_invite); the code is
    single-use; a revoked or expired code is refused with the right status
  * both see the roster with display names (rpc/household_roster); the member
    sees the owner's vehicle
  * the owner removes the member (rpc/remove_household_member): access ends;
    a plain member cannot remove anyone; direct DELETE on household_members
    changes nothing
  * leaving (rpc/leave_household): owner with a member -> 'transferred' (the
    member becomes owner), last member -> 'deleted' (household and data gone)

A cleanup step always runs. Prints ids and statuses only, never keys or tokens.

Environment and how to load it: see e2e_delete_account.py.

Run:
  python -I supabase/tests/e2e_household_invites.py --live
"""
import json
import os
import secrets
import sys
import time
import urllib.error
import urllib.request
import uuid


def _env(name):
    value = os.environ.get(name, '').strip()
    if not value:
        sys.exit(f'{name} is not set; see e2e_delete_account.py for how to load it.')
    return value


if '--live' not in sys.argv[1:]:
    sys.exit('This test creates and deletes real users and rows in the project '
             'SUPABASE_URL points at. Re-run with --live to proceed.')

URL = _env('SUPABASE_URL').rstrip('/')
ANON = _env('SUPABASE_ANON_KEY')
SERVICE = _env('SUPABASE_SERVICE_ROLE_KEY')


def call(method, path, body=None, *, token=None, apikey=None, prefer=None):
    """HTTP request; returns (status, parsed JSON or text). Never raises on HTTP errors."""
    headers = {'apikey': apikey or SERVICE, 'Authorization': f'Bearer {token or SERVICE}'}
    data = None
    if body is not None:
        headers['Content-Type'] = 'application/json'
        data = json.dumps(body).encode()
    if prefer:
        headers['Prefer'] = prefer
    req = urllib.request.Request(URL + path, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=60) as response:
            status, payload = response.status, response.read()
    except urllib.error.HTTPError as error:
        status, payload = error.code, error.read()
    try:
        return status, (json.loads(payload) if payload else None)
    except ValueError:
        return status, payload.decode(errors='replace')[:200]


def as_user(method, path, jwt, body=None, prefer=None):
    return call(method, f'/rest/v1/{path}', body, token=jwt, apikey=ANON, prefer=prefer)


def rpc(name, jwt, params):
    return as_user('POST', f'rpc/{name}', jwt, params)


def as_service(method, path, body=None):
    return call(method, f'/rest/v1/{path}', body, prefer='return=representation')


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
        'user_metadata': {'purpose': 'ourgarage household-invites e2e test'},
    })
    assert status in (200, 201), ('create user', role, status)
    users[role] = body['id']
    status, body = call('POST', '/auth/v1/token?grant_type=password',
                        {'email': email, 'password': password}, token=ANON, apikey=ANON)
    assert status == 200 and body.get('access_token'), ('sign-in', role, status)
    jwt = body['access_token']
    status, _ = as_user('POST', 'profiles', jwt,
                        {'id': users[role], 'display_name': f'E2E {role.title()}'})
    assert status == 201, ('profile', role, status)
    return users[role], jwt


def new_invite(jwt, household, *, expires_in_days=7):
    code = ''.join(secrets.choice('23456789ABCDEFGHJKMNPQRSTUVWXYZ') for _ in range(6))
    expires = time.strftime('%Y-%m-%dT%H:%M:%SZ',
                            time.gmtime(time.time() + expires_in_days * 86400))
    status, body = as_user('POST', 'household_invites?select=id', jwt, {
        'household_id': household, 'code': code,
        'created_by': users['owner'], 'expires_at': expires,
    }, prefer='return=representation')
    return status, code, (body[0]['id'] if status == 201 else None)


def roster(jwt, household):
    status, body = rpc('household_roster', jwt, {'hid': household})
    return body if status == 200 else None


def main():
    print(f'run tag: {tag}')
    owner, owner_jwt = create_user('owner')
    member, member_jwt = create_user('member')

    print('owner creates a household and invites')
    status, household = rpc('create_household', owner_jwt, {'household_name': 'E2E invites'})
    assert status == 200, ('create_household', status, household)
    households.append(household)

    car = str(uuid.uuid4())
    status, _ = as_user('POST', 'vehicles', owner_jwt, {
        'id': car, 'household_id': household, 'created_by': owner,
        'nickname': 'E2E car', 'odometer': 1000, 'odometer_unit': 'km'})
    check('owner adds a vehicle', status == 201, status)

    status, code, _ = new_invite(owner_jwt, household)
    check('owner creates an invite', status == 201, status)

    print('member joins')
    status, _ = as_user('POST', 'household_invites', member_jwt, {
        'household_id': household, 'code': 'ZZZZZZ', 'created_by': member,
        'expires_at': '2099-01-01T00:00:00Z'})
    check('a non-member cannot create an invite', status in (401, 403), status)

    status, _ = as_user('GET', f'vehicles?id=eq.{car}&select=id', member_jwt)
    _, seen = as_user('GET', f'vehicles?id=eq.{car}&select=id', member_jwt)
    check('before joining, the vehicle is invisible', seen == [], seen)

    status, joined = rpc('accept_household_invite', member_jwt, {'invite_code': code})
    check('member joins with the code', status == 200 and joined == household, (status, joined))

    status, body = rpc('accept_household_invite', member_jwt, {'invite_code': code})
    check('the code is single-use (409)', status == 409, (status, body))

    _, seen = as_user('GET', f'vehicles?id=eq.{car}&select=id', member_jwt)
    check('after joining, the member sees the vehicle', seen == [{'id': car}], seen)

    for who, jwt in (('owner', owner_jwt), ('member', member_jwt)):
        rows = roster(jwt, household) or []
        names = sorted(r.get('display_name') for r in rows)
        check(f'{who} sees the roster with names', names == ['E2E Member', 'E2E Owner'], rows)

    print('revoked and expired invites')
    status, revoked_code, invite_id = new_invite(owner_jwt, household)
    status, _ = as_user('DELETE', f'household_invites?id=eq.{invite_id}', owner_jwt,
                        prefer='return=representation')
    status, body = rpc('accept_household_invite', member_jwt, {'invite_code': revoked_code})
    # PostgREST answers P0002 with HTTP 500; the app maps the SQLSTATE code
    # (P0002 -> "doesn't match any invite"), not the status, so that's what
    # is asserted.
    check('a revoked code is not found (P0002)',
          isinstance(body, dict) and body.get('code') == 'P0002', (status, body))

    status, expired_code, _ = new_invite(owner_jwt, household, expires_in_days=-1)
    status, body = rpc('accept_household_invite', member_jwt, {'invite_code': expired_code})
    check('an expired code is refused (400)', status == 400, (status, body))

    print('removing')
    status, body = rpc('remove_household_member', member_jwt,
                       {'hid': household, 'member': owner})
    check('a plain member cannot remove the owner (403)', status == 403, (status, body))

    status, body = as_user('DELETE', f'household_members?household_id=eq.{household}'
                                     f'&user_id=eq.{member}', owner_jwt,
                           prefer='return=representation')
    check('a direct DELETE on household_members removes nothing',
          status in (200, 204) and not body, (status, body))

    status, body = rpc('remove_household_member', owner_jwt,
                       {'hid': household, 'member': member})
    check('the owner removes the member', status in (200, 204), (status, body))
    _, seen = as_user('GET', f'vehicles?id=eq.{car}&select=id', member_jwt)
    check('a removed member loses access', seen == [], seen)
    check('a removed member cannot read the roster', roster(member_jwt, household) == [])

    print('leaving')
    _, code, _ = new_invite(owner_jwt, household)
    status, _ = rpc('accept_household_invite', member_jwt, {'invite_code': code})
    check('the member rejoins with a new code', status == 200, status)

    status, outcome = rpc('leave_household', owner_jwt, {'hid': household})
    check("owner leaving -> 'transferred'", status == 200 and outcome == 'transferred',
          (status, outcome))
    rows = roster(member_jwt, household) or []
    check('the member is now the sole owner',
          [(r['user_id'], r['role']) for r in rows] == [(member, 'owner')], rows)
    _, seen = as_user('GET', f'vehicles?id=eq.{car}&select=id', owner_jwt)
    check('the old owner lost access', seen == [], seen)

    status, outcome = rpc('leave_household', member_jwt, {'hid': household})
    check("last member leaving -> 'deleted'", status == 200 and outcome == 'deleted',
          (status, outcome))
    _, left = as_service('GET', f'households?id=eq.{household}&select=id')
    _, cars = as_service('GET', f'vehicles?id=eq.{car}&select=id')
    check('household and its vehicle are gone', left == [] and cars == [], (left, cars))


def cleanup():
    print('cleanup')
    for household in households:
        _, cars = as_service('GET', f'vehicles?household_id=eq.{household}&select=id')
        for car in cars or []:
            as_service('DELETE', f'service_records?vehicle_id=eq.{car["id"]}')
            as_service('DELETE', f'reminder_rules?vehicle_id=eq.{car["id"]}')
        as_service('DELETE', f'vehicles?household_id=eq.{household}')
        as_service('DELETE', f'households?id=eq.{household}')
    for user_id in users.values():
        as_service('DELETE', f'households?owner_id=eq.{user_id}')
        call('DELETE', f'/auth/v1/admin/users/{user_id}')
    remaining = 0
    for user_id in users.values():
        status, _ = call('GET', f'/auth/v1/admin/users/{user_id}')
        remaining += status == 200
    for household in households:
        _, rows = as_service('GET', f'households?id=eq.{household}&select=id')
        remaining += len(rows or [])
    print(f'  remaining test data: {remaining}')
    checks.append(('cleanup: no test data remains', remaining == 0))


try:
    main()
except AssertionError as error:
    print('SETUP ERROR:', str(error)[:200])
    checks.append(('script completed', False))
finally:
    cleanup()

passed = sum(1 for _, ok in checks if ok)
print(f'\nRESULT: {passed}/{len(checks)} checks passed')
sys.exit(0 if passed == len(checks) else 1)
