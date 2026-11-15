"""Live end-to-end test of the `delete-account` Edge Function.

Runs against a real Supabase project (whatever SUPABASE_URL points at). It
creates three throwaway users (og-e2e-<run tag>-{olive,mia,max}@example.com)
and one household with a vehicle, service record, reminder rule, invite and
premium paid for by olive, then deletes the users one by one through the
deployed function, each with their own real JWT, and checks the database after
every step:

  1. olive — owner with members, bogus Apple code: ownership passes to mia
     (joined first), shared data survives with created_by nulled, olive's
     premium is cleared, the Apple step fails gracefully, and olive's old JWT
     is rejected afterwards.
  2. max   — plain member, no Apple code: he leaves; Apple step skipped.
  3. mia   — now the sole member, empty request body: the household and all
     its data are deleted.

A cleanup step always runs and reports any test data it had to remove. The
script prints ids and statuses only, never keys or tokens.

It does not cover a real Apple token revocation (that needs a genuine Sign in
with Apple authorization code from a device).

Requirements: Python 3.9+, standard library only, and email/password sign-in
enabled on the project (the test users sign in with a password to get a JWT).

Environment:
  SUPABASE_URL               https://<ref>.supabase.co
  SUPABASE_ANON_KEY          the project's anon key
  SUPABASE_SERVICE_ROLE_KEY  the service-role key (creates/deletes test users)

One way to load them without echoing anything, from the repo root in Git Bash
(the CLI must be logged in and the project linked):

  export SUPABASE_URL=$(python -c "import json;print(json.load(open('dart_defines.json'))['SUPABASE_URL'])")
  export SUPABASE_ANON_KEY=$(python -c "import json;print(json.load(open('dart_defines.json'))['SUPABASE_ANON_KEY'])")
  export SUPABASE_SERVICE_ROLE_KEY=$(supabase projects api-keys --project-ref <ref> -o json \\
      | python -c "import json,sys;print([k['api_key'] for k in json.load(sys.stdin) if k['name']=='service_role'][0])")

Run:
  python -I supabase/tests/e2e_delete_account.py --live

Exit status 0 when every check passes.
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
        sys.exit(f'{name} is not set; see the docstring at the top of this file.')
    return value


if '--live' not in sys.argv[1:]:
    sys.exit('This test creates and deletes real users and rows in the project '
             'SUPABASE_URL points at. Re-run with --live to proceed.')

URL = _env('SUPABASE_URL').rstrip('/')
ANON = _env('SUPABASE_ANON_KEY')
SERVICE = _env('SUPABASE_SERVICE_ROLE_KEY')


def _iso(epoch_seconds):
    return time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(epoch_seconds))


def call(method, path, body=None, *, token=None, apikey=None, prefer=None, raw_body=None):
    """HTTP request; returns (status, parsed JSON or text). Never raises on HTTP errors."""
    headers = {'apikey': apikey or SERVICE, 'Authorization': f'Bearer {token or SERVICE}'}
    data = raw_body
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


def rest(method, table_query, body=None):
    """PostgREST as the service role (bypasses RLS), returning rows."""
    return call(method, f'/rest/v1/{table_query}', body, prefer='return=representation')


def rows(table_query):
    status, result = rest('GET', table_query)
    assert status == 200, (table_query, status, result)
    return result


def user_exists(user_id):
    status, _ = call('GET', f'/auth/v1/admin/users/{user_id}')
    return status == 200


checks = []


def check(name, condition, detail=''):
    checks.append((name, bool(condition)))
    mark = 'PASS' if condition else 'FAIL'
    suffix = f' — {detail}' if detail and not condition else ''
    print(f'  [{mark}] {name}{suffix}')


tag = time.strftime('%Y%m%d%H%M%S') + '-' + secrets.token_hex(3)
users = {}
credentials = {}
created = {'households': [], 'vehicles': [], 'service_records': [], 'reminder_rules': []}


def create_user(role):
    email = f'og-e2e-{tag}-{role}@example.com'
    password = secrets.token_urlsafe(24)
    status, body = call('POST', '/auth/v1/admin/users', {
        'email': email,
        'password': password,
        'email_confirm': True,
        'user_metadata': {'purpose': 'ourgarage delete-account e2e test'},
    })
    assert status in (200, 201), (status, body)
    users[role] = body['id']
    credentials[role] = (email, password)
    return body['id']


def jwt_for(role):
    email, password = credentials[role]
    status, body = call('POST', '/auth/v1/token?grant_type=password',
                        {'email': email, 'password': password}, token=ANON, apikey=ANON)
    assert status == 200 and isinstance(body, dict) and body.get('access_token'), \
        ('password sign-in failed — is the email provider enabled?', status)
    return body['access_token']


def delete_account(jwt, body=None, raw_body=None):
    return call('POST', '/functions/v1/delete-account', body,
                token=jwt, apikey=ANON, raw_body=raw_body)


def main():
    print(f'run tag: {tag}')
    print('setup')
    olive, mia, max_ = create_user('olive'), create_user('mia'), create_user('max')
    for role, user_id in users.items():
        status, _ = rest('POST', 'profiles', {'id': user_id, 'display_name': f'E2E {role}'})
        assert status == 201, ('profile', status)

    # The insert trigger adds olive's owner membership.
    status, result = rest('POST', 'households', {'name': f'E2E household {tag}', 'owner_id': olive})
    assert status == 201, ('household', status, result)
    household = result[0]['id']
    created['households'].append(household)

    now = time.time()
    for user_id, days_ago in ((mia, 2), (max_, 1)):  # mia joined first: the heir
        status, _ = rest('POST', 'household_members', {
            'household_id': household, 'user_id': user_id,
            'role': 'member', 'joined_at': _iso(now - days_ago * 86400),
        })
        assert status == 201, ('membership', status)

    car, record, rule = str(uuid.uuid4()), str(uuid.uuid4()), str(uuid.uuid4())
    for table, row in (
        ('vehicles', {'id': car, 'household_id': household, 'created_by': olive,
                      'nickname': 'E2E car', 'odometer': 1000, 'odometer_unit': 'mi'}),
        ('service_records', {'id': record, 'vehicle_id': car, 'created_by': olive,
                             'performed_at': _iso(now), 'type': 'oilChange', 'cost': 89.4}),
        ('reminder_rules', {'id': rule, 'vehicle_id': car, 'created_by': olive,
                            'type': 'oilChange', 'interval_months': 6}),
    ):
        status, result = rest('POST', table, row)
        assert status == 201, (table, status, result)
        created[table].append(row['id'])

    status, _ = rest('POST', 'household_invites', {
        'household_id': household, 'code': f'E2E{secrets.token_hex(4).upper()}',
        'created_by': olive, 'expires_at': _iso(now + 7 * 86400),
    })
    assert status == 201, ('invite', status)

    # Premium as the RevenueCat webhook would write it (the service role passes
    # the premium guard trigger).
    status, _ = rest('PATCH', f'households?id=eq.{household}', {
        'is_premium': True, 'premium_source_user_id': olive,
        'premium_expires_at': _iso(now + 300 * 86400),
    })
    assert status == 200, ('premium', status)

    members = rows(f'household_members?household_id=eq.{household}&select=user_id,role')
    check('setup: olive is owner via the creation trigger', {'user_id': olive, 'role': 'owner'} in members)
    olive_jwt, mia_jwt, max_jwt = jwt_for('olive'), jwt_for('mia'), jwt_for('max')

    print('1. owner with members (olive), bogus Apple code')
    status, body = delete_account(olive_jwt, {'appleAuthorizationCode': 'e2e-not-a-real-code'})
    body = body if isinstance(body, dict) else {}
    check('function returned 200 ok', status == 200 and body.get('ok') is True, (status, body))
    check('Apple step failed gracefully, deletion continued', body.get('apple') == 'failed', body.get('apple'))
    transferred = (body.get('summary') or {}).get('transferred') or [{}]
    check('summary names mia as new owner', transferred[0].get('new_owner_id') == mia, body.get('summary'))
    check('olive auth user deleted', not user_exists(olive))
    check('olive profile deleted', rows(f'profiles?id=eq.{olive}') == [])
    h = rows(f'households?id=eq.{household}&select=owner_id,is_premium,premium_source_user_id,premium_expires_at')
    check('household survives with owner_id = mia', h and h[0]['owner_id'] == mia, h)
    check('premium cleared (flag, source, expiry)',
          h and h[0]['is_premium'] is False and h[0]['premium_source_user_id'] is None
          and h[0]['premium_expires_at'] is None, h)
    members = rows(f'household_members?household_id=eq.{household}&select=user_id,role')
    check('mia promoted to owner', {'user_id': mia, 'role': 'owner'} in members, members)
    check('max still a member', {'user_id': max_, 'role': 'member'} in members, members)
    check('olive membership gone', all(m['user_id'] != olive for m in members))
    check('vehicle survives, created_by nulled', rows(f'vehicles?id=eq.{car}&select=created_by') == [{'created_by': None}])
    check('service record survives, created_by nulled',
          rows(f'service_records?id=eq.{record}&select=created_by') == [{'created_by': None}])
    check('reminder rule survives', len(rows(f'reminder_rules?id=eq.{rule}&select=id')) == 1)
    check("olive's invite deleted", rows(f'household_invites?household_id=eq.{household}&select=id') == [])
    status, _ = delete_account(olive_jwt, {})
    check("replaying olive's old JWT is rejected", status == 401, status)

    print('2. plain member (max), no Apple code')
    status, body = delete_account(max_jwt, {})
    body = body if isinstance(body, dict) else {}
    check('function returned 200 ok', status == 200 and body.get('ok') is True, (status, body))
    check('Apple step skipped (no code)', body.get('apple') == 'skipped_no_code', body.get('apple'))
    check('summary: left 1 household', (body.get('summary') or {}).get('left_households') == 1, body.get('summary'))
    check('max auth user deleted', not user_exists(max_))
    members = rows(f'household_members?household_id=eq.{household}&select=user_id,role')
    check('only mia remains, still owner', members == [{'user_id': mia, 'role': 'owner'}], members)
    check('household data untouched', len(rows(f'vehicles?household_id=eq.{household}&select=id')) == 1)

    print('3. sole member (mia), empty request body')
    status, body = delete_account(mia_jwt, raw_body=b'')
    body = body if isinstance(body, dict) else {}
    check('function returned 200 ok', status == 200 and body.get('ok') is True, (status, body))
    check('summary: deleted 1 household', (body.get('summary') or {}).get('deleted_households') == 1, body)
    check('mia auth user deleted', not user_exists(mia))
    check('household deleted', rows(f'households?id=eq.{household}&select=id') == [])
    check('vehicle deleted', rows(f'vehicles?id=eq.{car}&select=id') == [])
    check('service record deleted', rows(f'service_records?id=eq.{record}&select=id') == [])
    check('reminder rule deleted', rows(f'reminder_rules?id=eq.{rule}&select=id') == [])
    check('no memberships left', rows(f'household_members?household_id=eq.{household}&select=user_id') == [])
    check('no profiles left', rows(f"profiles?id=in.({','.join(users.values())})&select=id") == [])


def cleanup():
    """Removes anything the test created that is still there. Normally nothing."""
    print('cleanup (safety net; normally nothing left)')
    removed = 0
    for table in ('reminder_rules', 'service_records', 'vehicles', 'households'):
        for row_id in created[table]:
            _, result = rest('DELETE', f'{table}?id=eq.{row_id}')
            removed += len(result) if isinstance(result, list) else 0
    for user_id in users.values():
        if user_exists(user_id):
            removed += 1
            call('DELETE', f'/auth/v1/admin/users/{user_id}')

    remaining = sum(1 for user_id in users.values() if user_exists(user_id))
    if users:
        remaining += len(rows(f"profiles?id=in.({','.join(users.values())})&select=id"))
    for household in created['households']:
        remaining += len(rows(f'households?id=eq.{household}&select=id'))
    print(f'  removed by safety net: {removed}; remaining test data: {remaining}')
    checks.append(('cleanup: no test data remains', remaining == 0))


try:
    main()
except AssertionError as error:
    print('SETUP/STEP ERROR:', str(error)[:200])
    checks.append(('script completed', False))
finally:
    cleanup()

passed = sum(1 for _, ok in checks if ok)
print(f'\nRESULT: {passed}/{len(checks)} checks passed')
sys.exit(0 if passed == len(checks) else 1)
