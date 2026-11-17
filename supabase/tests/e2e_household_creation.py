"""Live end-to-end test: creating a household as a normal signed-in user.

Regression test for 2026-11-17: build 1.0.8+13 could sign in but not create a
household (POST /rest/v1/households?select=id -> 403, Postgres 42501). The
delete-account e2e test never saw it because it creates its household with the
service-role key, which bypasses RLS. Everything here that matters is done
with a real user's JWT and the anon key, exactly as the app does.

Creates one throwaway user (og-e2e-<run tag>-hh@example.com) and checks:

  * the build-13 request: POST households?select=id {name, owner_id} -> 201
    and an owner membership row, visible to the user
  * the RPC: POST rpc/create_household -> the id of a new household the user
    owns, with an owner membership
  * the user cannot create a household that is already premium, or one owned
    by somebody else

A cleanup step always runs and deletes the user and every row it created. The
script prints ids and statuses only, never keys or tokens.

Requires 20261117000100_household_creation.sql to be applied; before that, the
first check fails with the production error, which is the point.

Environment and how to load it: see e2e_delete_account.py.

Run:
  python -I supabase/tests/e2e_household_creation.py --live

Exit status 0 when every check passes.
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
        sys.exit(f'{name} is not set; see e2e_delete_account.py for how to load it.')
    return value


if '--live' not in sys.argv[1:]:
    sys.exit('This test creates and deletes a real user and rows in the project '
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
    """PostgREST as the signed-in user: anon key + user JWT, RLS enforced."""
    return call(method, f'/rest/v1/{path}', body, token=jwt, apikey=ANON, prefer=prefer)


def as_service(method, path, body=None):
    """PostgREST as the service role (bypasses RLS). Only for verification and cleanup."""
    return call(method, f'/rest/v1/{path}', body, prefer='return=representation')


checks = []


def check(name, condition, detail=''):
    checks.append((name, bool(condition)))
    mark = 'PASS' if condition else 'FAIL'
    suffix = f' — {detail}' if detail and not condition else ''
    print(f'  [{mark}] {name}{suffix}')


tag = time.strftime('%Y%m%d%H%M%S') + '-' + secrets.token_hex(3)
user_id = None


def owner_role(jwt, household):
    status, rows = as_user('GET', f'household_members?household_id=eq.{household}'
                                  f'&user_id=eq.{user_id}&select=role', jwt)
    return rows[0]['role'] if status == 200 and rows else None


def main():
    global user_id
    print(f'run tag: {tag}')
    email = f'og-e2e-{tag}-hh@example.com'
    password = secrets.token_urlsafe(24)
    status, body = call('POST', '/auth/v1/admin/users', {
        'email': email, 'password': password, 'email_confirm': True,
        'user_metadata': {'purpose': 'ourgarage household-creation e2e test'},
    })
    assert status in (200, 201), ('create user', status)
    user_id = body['id']

    status, body = call('POST', '/auth/v1/token?grant_type=password',
                        {'email': email, 'password': password}, token=ANON, apikey=ANON)
    assert status == 200 and body.get('access_token'), ('password sign-in', status)
    jwt = body['access_token']

    # The app creates its own profile, as the user.
    status, _ = as_user('POST', 'profiles', jwt, {'id': user_id, 'display_name': 'E2E hh'})
    check('profile created as the user', status == 201, status)

    print('build 1.0.8+13 path: insert with RETURNING')
    status, body = as_user('POST', 'households?select=id', jwt,
                           {'name': 'E2E direct', 'owner_id': user_id},
                           prefer='return=representation')
    check('POST households?select=id -> 201', status == 201, (status, body))
    if status == 201:
        direct = body[0]['id']
        check('direct: owner membership visible to the user', owner_role(jwt, direct) == 'owner')

    print('create_household RPC')
    status, body = as_user('POST', 'rpc/create_household', jwt, {'household_name': '  E2E rpc  '})
    check('rpc/create_household -> 200 with an id', status == 200 and isinstance(body, str),
          (status, body))
    if status == 200 and isinstance(body, str):
        _, rows = as_user('GET', f'households?id=eq.{body}&select=name,owner_id,is_premium', jwt)
        check('rpc: household visible, trimmed name, owned by the user, not premium',
              rows == [{'name': 'E2E rpc', 'owner_id': user_id, 'is_premium': False}], rows)
        check('rpc: owner membership visible to the user', owner_role(jwt, body) == 'owner')

    status, body = as_user('POST', 'rpc/create_household', jwt, {'household_name': '   '})
    check('rpc: blank name rejected', status == 400, (status, body))

    print('what a client must not be able to do')
    status, body = as_user('POST', 'households', jwt,
                           {'name': 'E2E premium', 'owner_id': user_id, 'is_premium': True})
    check('cannot create a premium household', status in (401, 403), (status, body))

    status, others = as_service('GET', f'profiles?id=neq.{user_id}&select=id&limit=1')
    if status == 200 and others:
        status, body = as_user('POST', 'households', jwt,
                               {'name': 'E2E spoof', 'owner_id': others[0]['id']})
        check("cannot create a household owned by someone else", status in (401, 403),
              (status, body))

    status, rows = as_service('GET', f'households?owner_id=eq.{user_id}&select=is_premium')
    check('no premium household was created', status == 200 and not any(r['is_premium'] for r in rows),
          rows)


def cleanup():
    """Deletes the test user's households, then the user (profile and memberships cascade)."""
    print('cleanup')
    if not user_id:
        return
    as_service('DELETE', f'households?owner_id=eq.{user_id}')
    call('DELETE', f'/auth/v1/admin/users/{user_id}')
    _, households = as_service('GET', f'households?owner_id=eq.{user_id}&select=id')
    status, _ = call('GET', f'/auth/v1/admin/users/{user_id}')
    remaining = (len(households) if isinstance(households, list) else 1) + (status == 200)
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
