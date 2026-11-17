// Run: deno test supabase/functions/_shared/premium_test.ts
import { assertEquals, assertRejects } from 'jsr:@std/assert@1';
import {
  type Entitlement,
  eventUserIds,
  fetchEntitlement,
  reconcileUsers,
  type RevenueCatConfig,
  supabaseUserIds,
} from './premium.ts';

const ME = '11111111-1111-1111-1111-111111111111';
const OTHER = '22222222-2222-2222-2222-222222222222';
const THIRD = '33333333-3333-3333-3333-333333333333';
const NOW = Date.parse('2026-11-17T12:00:00Z');
const inactive: Entitlement = { active: false, expiresAt: null };

function stubFetch(status: number, body: unknown): typeof fetch {
  return (() => Promise.resolve(new Response(JSON.stringify(body), { status }))) as typeof fetch;
}

const config = (fetchFn: typeof fetch, extra: Partial<RevenueCatConfig> = {}): RevenueCatConfig => ({
  secretKey: 'sk_test',
  entitlementId: 'premium',
  fetchFn,
  now: () => NOW,
  ...extra,
});

// --- fetchEntitlement -------------------------------------------------------

Deno.test('lifetime entitlement is active with no expiry', async () => {
  const ent = await fetchEntitlement(ME, config(stubFetch(200, {
    subscriber: { entitlements: { premium: { expires_date: null } } },
  })));
  assertEquals(ent, { active: true, expiresAt: null });
});

Deno.test('expired entitlement is inactive; grace period keeps it active', async () => {
  const expired = await fetchEntitlement(ME, config(stubFetch(200, {
    subscriber: { entitlements: { premium: { expires_date: '2026-11-01T00:00:00Z' } } },
  })));
  assertEquals(expired, inactive);

  const grace = await fetchEntitlement(ME, config(stubFetch(200, {
    subscriber: {
      entitlements: {
        premium: {
          expires_date: '2026-11-01T00:00:00Z',
          grace_period_expires_date: '2026-11-20T00:00:00Z',
        },
      },
    },
  })));
  assertEquals(grace, { active: true, expiresAt: '2026-11-20T00:00:00.000Z' });
});

Deno.test('other entitlements and unknown users are inactive', async () => {
  assertEquals(
    await fetchEntitlement(ME, config(stubFetch(200, {
      subscriber: { entitlements: { other: { expires_date: null } } },
    }))),
    inactive,
  );
  assertEquals(await fetchEntitlement(ME, config(stubFetch(404, {}))), inactive);
});

Deno.test('a RevenueCat error or rate limit throws rather than reading as "not premium"', async () => {
  await assertRejects(() => fetchEntitlement(ME, config(stubFetch(500, {}))));
  await assertRejects(() => fetchEntitlement(ME, config(stubFetch(429, {}))));
});

Deno.test('a hung RevenueCat call times out', async () => {
  const hangs = ((_url: string, init?: RequestInit) =>
    new Promise<Response>((_resolve, reject) => {
      init?.signal?.addEventListener('abort', () => reject(init.signal!.reason));
    })) as typeof fetch;
  await assertRejects(() => fetchEntitlement(ME, config(hangs, { timeoutMs: 10 })));
});

Deno.test('the secret key is sent as a bearer token to the subscriber endpoint', async () => {
  let seen: { url: string; auth: string | null } | null = null;
  const capture = ((url: string, init?: RequestInit) => {
    seen = { url, auth: new Headers(init?.headers).get('Authorization') };
    return Promise.resolve(new Response('{}', { status: 200 }));
  }) as typeof fetch;
  await fetchEntitlement(ME, config(capture));
  assertEquals(seen, {
    url: `https://api.revenuecat.com/v1/subscribers/${ME}`,
    auth: 'Bearer sk_test',
  });
});

// --- ids ------------------------------------------------------------------

Deno.test('supabaseUserIds: Supabase users only, deduplicated', () => {
  assertEquals(supabaseUserIds([ME, '$RCAnonymousID:abc', ME, OTHER, 42, null]), [ME, OTHER]);
  assertEquals(supabaseUserIds(undefined), []);
});

Deno.test('eventUserIds covers every id field of an event', () => {
  assertEquals(
    eventUserIds({
      app_user_id: '$RCAnonymousID:abc',
      original_app_user_id: ME,
      aliases: ['$RCAnonymousID:abc', ME, OTHER],
      transferred_from: [OTHER],
      transferred_to: [THIRD],
    }),
    [ME, OTHER, THIRD],
  );
  assertEquals(eventUserIds({ app_user_id: '$RCAnonymousID:x' }), []);
});

// --- reconcileUsers ------------------------------------------------------

/// A fake service-role client over an in-memory membership table, recording
/// rpc calls.
function fakeAdmin(
  memberships: { household_id: string; user_id: string }[],
  rpcResult: (args: { hid: string }) => unknown = (args) => ({
    household_id: args.hid,
    is_premium: true,
    changed: true,
  }),
) {
  const rpcCalls: { name: string; args: { hid: string; entitlements: unknown[] } }[] = [];
  const admin = {
    from(_table: string) {
      return {
        select(_cols: string) {
          return {
            in: (_col: string, ids: string[]) =>
              Promise.resolve({
                data: memberships.filter((m) => ids.includes(m.user_id)),
                error: null,
              }),
            eq: (_col: string, hid: string) =>
              Promise.resolve({
                data: memberships.filter((m) => m.household_id === hid),
                error: null,
              }),
          };
        },
      };
    },
    rpc(name: string, args: { hid: string; entitlements: unknown[] }) {
      rpcCalls.push({ name, args });
      return Promise.resolve({ data: rpcResult(args), error: null });
    },
  };
  return { admin, rpcCalls };
}

/// RevenueCat stub: lifetime for ME, inactive for everyone else; counts calls.
function countingRevenueCat(failFor?: string) {
  const calls: string[] = [];
  const fetchFn = ((url: string) => {
    const id = url.split('/').pop()!;
    calls.push(id);
    if (id === failFor) return Promise.resolve(new Response('{}', { status: 503 }));
    const entitlements = id === ME ? { premium: { expires_date: null } } : {};
    return Promise.resolve(
      new Response(JSON.stringify({ subscriber: { entitlements } }), { status: 200 }),
    );
  }) as typeof fetch;
  return { calls, fetchFn };
}

Deno.test('a user in no household costs no RevenueCat call and writes nothing', async () => {
  const { admin, rpcCalls } = fakeAdmin([]);
  const rc = countingRevenueCat();
  assertEquals(await reconcileUsers(admin, [ME], config(rc.fetchFn)), []);
  assertEquals(rc.calls, []);
  assertEquals(rpcCalls, []);
});

Deno.test('every member is fetched and reported, not just the triggering user', async () => {
  const { admin, rpcCalls } = fakeAdmin([
    { household_id: 'h1', user_id: ME },
    { household_id: 'h1', user_id: OTHER },
  ]);
  const rc = countingRevenueCat();
  await reconcileUsers(admin, [OTHER], config(rc.fetchFn));

  assertEquals(rc.calls.sort(), [ME, OTHER].sort());
  assertEquals(rpcCalls.length, 1);
  assertEquals(rpcCalls[0].name, 'apply_household_premium');
  assertEquals(rpcCalls[0].args.hid, 'h1');
  assertEquals(
    rpcCalls[0].args.entitlements,
    [
      { user_id: ME, active: true, expires_at: null },
      { user_id: OTHER, active: false, expires_at: null },
    ],
  );
});

Deno.test('a member shared by two households is fetched once', async () => {
  const { admin, rpcCalls } = fakeAdmin([
    { household_id: 'h1', user_id: ME },
    { household_id: 'h1', user_id: OTHER },
    { household_id: 'h2', user_id: ME },
    { household_id: 'h2', user_id: THIRD },
  ]);
  const rc = countingRevenueCat();
  await reconcileUsers(admin, [ME], config(rc.fetchFn));

  assertEquals(rpcCalls.length, 2);
  assertEquals(rc.calls.filter((id) => id === ME).length, 1);
  assertEquals(rc.calls.length, 3);
});

Deno.test('one failed fetch writes nothing', async () => {
  const { admin, rpcCalls } = fakeAdmin([
    { household_id: 'h1', user_id: ME },
    { household_id: 'h1', user_id: OTHER },
  ]);
  const rc = countingRevenueCat(OTHER);
  await assertRejects(() => reconcileUsers(admin, [ME], config(rc.fetchFn)));
  assertEquals(rpcCalls, []);
});

Deno.test('a household deleted mid-reconcile reports not premium, unchanged', async () => {
  const { admin } = fakeAdmin([{ household_id: 'h1', user_id: ME }], () => null);
  const rc = countingRevenueCat();
  assertEquals(await reconcileUsers(admin, [ME], config(rc.fetchFn)), [
    { household_id: 'h1', is_premium: false, changed: false },
  ]);
});
