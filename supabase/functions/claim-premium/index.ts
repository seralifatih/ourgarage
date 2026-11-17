// "My purchase should cover my household."
//
// Called by the app after it creates or joins a household, and on resume when
// the user's own RevenueCat entitlement is active but the household isn't
// premium. The caller is identified from their own JWT; whether they are
// entitled is asked of RevenueCat's REST API — nothing the client says about
// its own entitlement is trusted. See ../_shared/premium.ts.
//
// Deploy:
//   supabase functions deploy claim-premium --use-api
//   supabase secrets set REVENUECAT_SECRET_KEY=sk_...   (never echo it)

import { createClient } from 'jsr:@supabase/supabase-js@2';
import { reconcileUsers, revenueCatConfigFrom } from '../_shared/premium.ts';

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  const url = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const revenueCat = revenueCatConfigFrom((name) => Deno.env.get(name));
  if (!url || !anonKey || !serviceKey || !revenueCat) {
    console.error('claim-premium is missing configuration');
    return json({ error: 'Server misconfigured' }, 500);
  }

  const authorization = req.headers.get('Authorization');
  if (!authorization) return json({ error: 'Unauthorized' }, 401);

  const asCaller = createClient(url, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  });
  const { data: userData, error: userError } = await asCaller.auth.getUser();
  if (userError || !userData?.user) return json({ error: 'Unauthorized' }, 401);

  const admin = createClient(url, serviceKey, { auth: { persistSession: false } });

  // Throttle: the app calls this on resume, and any signed-in user could call
  // it in a loop, each call costing one RevenueCat request per member. When
  // every household the caller is in already has premium that isn't about to
  // run out, there is nothing to gain — answer from the database.
  const settled = await alreadySettled(admin, userData.user.id);
  if (settled) return json({ ok: true, households: settled, cached: true });

  try {
    const households = await reconcileUsers(admin, [userData.user.id], revenueCat);
    return json({ ok: true, households });
  } catch (error) {
    console.error('claim-premium failed:', (error as Error).message);
    return json({ error: 'Could not check premium' }, 502);
  }
});

const SETTLED_MARGIN_MS = 3 * 24 * 60 * 60 * 1000;

// deno-lint-ignore no-explicit-any
async function alreadySettled(admin: any, userId: string) {
  const { data, error } = await admin
    .from('household_members')
    .select('household_id, households(is_premium, premium_expires_at)')
    .eq('user_id', userId);
  if (error || !data?.length) return null;

  const horizon = Date.now() + SETTLED_MARGIN_MS;
  const settled = data.every((m: { households: { is_premium: boolean; premium_expires_at: string | null } | null }) =>
    m.households?.is_premium &&
    (m.households.premium_expires_at === null ||
      Date.parse(m.households.premium_expires_at) > horizon)
  );
  if (!settled) return null;
  return data.map((m: { household_id: string }) => ({
    household_id: m.household_id,
    is_premium: true,
    changed: false,
  }));
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}
