"""Sets up the App Review demo household, and mints invite codes for it.

App Review signs in with its own Apple ID (Sign in with Apple is the only
sign-in method), so it can't be handed an account. What it can be handed is an
invite code into a household that already has something in it: this creates
(or reuses) a demo owner account that never signs in on a device, its
household, a car with service history and reminders, and fresh invite codes.

Idempotent: re-running reuses the demo owner and household and only mints new
codes (and grants the promo, see below).

Premium: with REVENUECAT_SECRET_KEY set, the demo owner gets a lifetime
RevenueCat promotional entitlement; the script checks RevenueCat reports it as
lifetime, then marks the household premium through apply_household_premium
(the same function every reconcile uses), so the reviewer has Premium the
moment they join, without depending on the join-time claim succeeding.
Writing households.is_premium by hand would not stick: the next reconcile asks
RevenueCat. Without the key, everything else is still set up and the script
says premium was skipped.

Codes are single-use, so several are minted; App Review may try more than
once, or more than one reviewer may look.

Environment: as supabase/tests/e2e_delete_account.py, plus optionally
REVENUECAT_SECRET_KEY. Prints the codes and ids, never keys or tokens.

Run:
  python -I tool/create_review_household.py --live [--codes 5] [--days 45]
"""
import argparse
import json
import os
import secrets
import sys
import time
import urllib.error
import urllib.request
import uuid

DEMO_EMAIL = 'app-review-demo@ourgarage.app'
DEMO_NAME = 'OurGarage Demo'
HOUSEHOLD_NAME = 'Demo household'
ALPHABET = '23456789ABCDEFGHJKMNPQRSTUVWXYZ'  # lib/features/household/invite_code.dart

parser = argparse.ArgumentParser()
parser.add_argument('--live', action='store_true')
parser.add_argument('--codes', type=int, default=5)
parser.add_argument('--days', type=int, default=45)
args = parser.parse_args()
if args.codes < 0 or not 1 <= args.days <= 365:
    sys.exit('--codes must be >= 0 (0 mints none) and --days between 1 and 365.')
if not args.live:
    sys.exit('This writes to the project SUPABASE_URL points at. Re-run with --live.')


def _env(name, required=True):
    value = os.environ.get(name, '').strip()
    if required and not value:
        sys.exit(f'{name} is not set; see supabase/tests/e2e_delete_account.py.')
    return value


URL = _env('SUPABASE_URL').rstrip('/')
SERVICE = _env('SUPABASE_SERVICE_ROLE_KEY')
RC_KEY = _env('REVENUECAT_SECRET_KEY', required=False)
ENTITLEMENT = os.environ.get('REVENUECAT_ENTITLEMENT_ID', 'premium')


def http(method, url, body=None, headers=None):
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


def service(method, path, body=None, prefer='return=representation'):
    return http(method, URL + path, body, {
        'apikey': SERVICE, 'Authorization': f'Bearer {SERVICE}', 'Prefer': prefer})


def iso(seconds_from_now):
    return time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(time.time() + seconds_from_now))


DAY = 86400


def demo_owner():
    page = 1
    while True:
        status, body = service('GET', f'/auth/v1/admin/users?page={page}&per_page=500')
        assert status == 200, ('list users', status)
        batch = body.get('users', [])
        for user in batch:
            if user.get('email') == DEMO_EMAIL:
                return user['id'], False
        if len(batch) < 500:
            break
        page += 1
    status, body = service('POST', '/auth/v1/admin/users', {
        'email': DEMO_EMAIL,
        # Never used to sign in on a device; random and discarded.
        'password': secrets.token_urlsafe(32),
        'email_confirm': True,
        'user_metadata': {'purpose': 'App Review demo household owner'},
    })
    assert status in (200, 201), ('create demo owner', status)
    return body['id'], True


def ensure_household(owner):
    status, _ = service('POST', '/rest/v1/profiles?on_conflict=id',
                        {'id': owner, 'display_name': DEMO_NAME},
                        prefer='resolution=merge-duplicates,return=minimal')
    assert status in (200, 201, 204), ('profile', status)

    status, rows = service('GET', f'/rest/v1/households?owner_id=eq.{owner}&select=id')
    assert status == 200, ('find household', status)
    if rows:
        household, created = rows[0]['id'], False
    else:
        # The insert trigger adds the owner's membership.
        status, rows = service('POST', '/rest/v1/households',
                               {'name': HOUSEHOLD_NAME, 'owner_id': owner})
        assert status == 201, ('create household', status)
        household, created = rows[0]['id'], True

    # Seeded unless the car is already there, so a run that died half-way
    # is repaired rather than handing out codes to an empty garage.
    status, cars = service('GET', f'/rest/v1/vehicles?household_id=eq.{household}&select=id')
    assert status == 200, ('find vehicle', status)
    if not cars:
        seed_garage(owner, household)
    return household, created


def seed_garage(owner, household):
    car = str(uuid.uuid4())
    now = iso(0)
    status, _ = service('POST', '/rest/v1/vehicles', {
        'id': car, 'household_id': household, 'created_by': owner,
        'nickname': 'Family Civic', 'make': 'Honda', 'model': 'Civic', 'year': 2019,
        'odometer': 48200, 'odometer_unit': 'mi', 'odometer_updated_at': now,
        'created_at': now, 'updated_at': now})
    assert status == 201, ('vehicle', status)

    services = [
        ('oilChange', -150, 44100, 79.99, 'Full synthetic, new filter'),
        ('tireRotation', -150, 44100, 25.00, None),
        ('brakes', -300, 39800, 289.50, 'Front pads and rotors'),
        ('inspection', -40, 47600, 35.00, 'Annual state inspection'),
    ]
    status, _ = service('POST', '/rest/v1/service_records', [
        {'id': str(uuid.uuid4()), 'vehicle_id': car, 'created_by': owner,
         'performed_at': iso(days * DAY), 'odometer': odo, 'type': kind,
         'notes': notes, 'cost': cost, 'currency': 'USD',
         'created_at': now, 'updated_at': now}
        for kind, days, odo, cost, notes in services])
    assert status == 201, ('service records', status)

    status, _ = service('POST', '/rest/v1/reminder_rules', [
        {'id': str(uuid.uuid4()), 'vehicle_id': car, 'created_by': owner,
         'type': 'oilChange', 'interval_months': 6, 'interval_distance': 5000,
         'last_done_at': iso(-150 * DAY), 'last_done_odometer': 44100,
         'created_at': now, 'updated_at': now},
        {'id': str(uuid.uuid4()), 'vehicle_id': car, 'created_by': owner,
         'type': 'tireRotation', 'interval_months': None, 'interval_distance': 7500,
         'last_done_at': iso(-150 * DAY), 'last_done_odometer': 44100,
         'created_at': now, 'updated_at': now},
    ])
    assert status == 201, ('reminder rules', status)


def mint_codes(owner, household, count, days):
    codes = []
    while len(codes) < count:
        code = ''.join(secrets.choice(ALPHABET) for _ in range(6))
        status, _ = service('POST', '/rest/v1/household_invites', {
            'household_id': household, 'code': code, 'created_by': owner,
            'expires_at': iso(days * DAY)}, prefer='return=minimal')
        if status == 201:
            codes.append(code)
        elif status != 409:  # 409: code collision, try another
            raise AssertionError(('invite', status))
    return codes


def grant_premium(owner):
    if not RC_KEY:
        return 'skipped (REVENUECAT_SECRET_KEY not set)'
    status, _ = http(
        'POST',
        f'https://api.revenuecat.com/v1/subscribers/{owner}/entitlements/{ENTITLEMENT}/promotional',
        {'duration': 'lifetime'}, {'Authorization': f'Bearer {RC_KEY}'})
    if status not in (200, 201):
        return f'RevenueCat grant failed ({status})'

    # Confirm RevenueCat reports it as long-lived. A lifetime promo comes back
    # with an expires_date about 200 years out (seen 2026-11-17), not null;
    # fetchEntitlement treats both as entitled.
    status, body = http('GET', f'https://api.revenuecat.com/v1/subscribers/{owner}',
                        None, {'Authorization': f'Bearer {RC_KEY}'})
    entitlement = ((body or {}).get('subscriber') or {}).get('entitlements', {}).get(ENTITLEMENT)
    expires = (entitlement or {}).get('expires_date')
    long_lived = expires is None or int(expires[:4]) - int(time.strftime('%Y')) > 50
    if status != 200 or not entitlement or not long_lived:
        return f'promo granted, but RevenueCat does not report it as lifetime ({status})'
    return 'lifetime promo granted and confirmed'


def mark_premium(owner, household):
    # Same function every reconcile calls; service role only. The expiry is
    # read back from RevenueCat so this writes what a reconcile would.
    _, body = http('GET', f'https://api.revenuecat.com/v1/subscribers/{owner}',
                   None, {'Authorization': f'Bearer {RC_KEY}'})
    expires = (((body or {}).get('subscriber') or {}).get('entitlements', {})
               .get(ENTITLEMENT) or {}).get('expires_date')
    status, result = service('POST', '/rest/v1/rpc/apply_household_premium', {
        'hid': household,
        'entitlements': [{'user_id': owner, 'active': True, 'expires_at': expires}],
    })
    assert status == 200 and result and result.get('is_premium'), ('apply premium', status)
    return 'household is premium'


def main():
    owner, created_owner = demo_owner()
    household, created_household = ensure_household(owner)
    codes = mint_codes(owner, household, args.codes, args.days)
    premium = grant_premium(owner)
    if premium == 'lifetime promo granted and confirmed':
        premium += '; ' + mark_premium(owner, household)

    print(f'demo owner:  {owner} ({"created" if created_owner else "existing"})')
    print(f'household:   {household} ({"created" if created_household else "existing"})')
    print(f'premium:     {premium}')
    print(f'invite codes (single-use, expire {iso(args.days * DAY)[:10]}):')
    for code in codes:
        print(f'  {code}')


main()
