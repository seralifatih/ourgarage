// RevenueCat webhook receiver.
//
// The only thing in the system permitted to write households.is_premium,
// premium_expires_at and premium_source_user_id. Those columns are revoked
// from every client role and guarded by a trigger (see the sharing-layer
// migration), so entitlement can only ever arrive here, from RevenueCat,
// verified by the shared secret below.
//
// One member pays and the whole household becomes premium: the purchase is
// keyed to a user, and that user's household membership is what the flag is
// written against.
//
// Deploy:
//   supabase functions deploy revenuecat-webhook --no-verify-jwt
//   supabase secrets set REVENUECAT_WEBHOOK_SECRET=...
//
// `--no-verify-jwt` is required and safe: RevenueCat has no Supabase JWT to
// present. Authentication is the Authorization header checked below, which is
// why that check must never be made conditional.

import { createClient } from 'jsr:@supabase/supabase-js@2';

/// Events that mean "this user should have premium right now".
const GRANTING = new Set([
  'INITIAL_PURCHASE',
  'RENEWAL',
  'UNCANCELLATION',
  'NON_RENEWING_PURCHASE',
  'SUBSCRIPTION_EXTENDED',
  'PRODUCT_CHANGE',
]);

/// Events that mean entitlement has ended.
///
/// CANCELLATION is deliberately absent: cancelling turns off auto-renewal but
/// the user keeps what they paid for until the period ends. Revoking there
/// would take away access somebody is still entitled to, and EXPIRATION is
/// what actually marks the end.
const REVOKING = new Set(['EXPIRATION', 'REFUND']);

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== 'POST') {
    return json({ error: 'Method not allowed' }, 405);
  }

  const expectedSecret = Deno.env.get('REVENUECAT_WEBHOOK_SECRET');
  if (!expectedSecret) {
    console.error('REVENUECAT_WEBHOOK_SECRET is not configured');
    return json({ error: 'Server misconfigured' }, 500);
  }

  // RevenueCat sends the configured value verbatim in the Authorization
  // header. Anyone who can reach this endpoint without it can hand out
  // premium, so this is the whole security boundary.
  if (req.headers.get('Authorization') !== expectedSecret) {
    return json({ error: 'Unauthorized' }, 401);
  }

  let event: RevenueCatEvent;
  try {
    const body = await req.json();
    event = body?.event;
    if (!event?.type) throw new Error('missing event');
  } catch (_error) {
    return json({ error: 'Malformed payload' }, 400);
  }

  const grants = GRANTING.has(event.type);
  const revokes = REVOKING.has(event.type);

  // Anything else (TEST, BILLING_ISSUE, TRANSFER, …) is acknowledged and
  // ignored. Returning non-2xx would make RevenueCat retry an event that will
  // never be actionable.
  if (!grants && !revokes) {
    return json({ ok: true, ignored: event.type });
  }

  // app_user_id is the Supabase user id, because the client configures
  // RevenueCat with it after sign-in.
  const userId = event.app_user_id;
  if (!userId) return json({ error: 'No app_user_id' }, 400);

  const admin = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { persistSession: false } },
  );

  const { data: membership, error: membershipError } = await admin
    .from('household_members')
    .select('household_id')
    .eq('user_id', userId)
    .limit(1)
    .maybeSingle();

  if (membershipError) {
    console.error('Membership lookup failed', membershipError);
    return json({ error: 'Lookup failed' }, 500);
  }

  // A purchase from someone not yet in a household is acknowledged, not
  // retried: they bought premium before creating one, and the household they
  // create next will be flagged when RevenueCat next reports their state.
  // Failing here would have RevenueCat retrying forever.
  if (!membership) {
    console.warn(`No household for user ${userId}; nothing to flag`);
    return json({ ok: true, skipped: 'no-household' });
  }

  const expiresAt = event.expiration_at_ms
    ? new Date(event.expiration_at_ms).toISOString()
    : null;

  const { error: updateError } = await admin
    .from('households')
    .update({
      is_premium: grants,
      // Cleared on revocation so a lapsed household does not keep pointing at
      // the member who used to pay for it.
      premium_source_user_id: grants ? userId : null,
      premium_expires_at: grants ? expiresAt : null,
    })
    .eq('id', membership.household_id);

  if (updateError) {
    // Worth a 500: RevenueCat retries, and a household wrongly left un-premium
    // is a support ticket.
    console.error('Household update failed', updateError);
    return json({ error: 'Update failed' }, 500);
  }

  return json({
    ok: true,
    household_id: membership.household_id,
    is_premium: grants,
  });
});

interface RevenueCatEvent {
  type: string;
  app_user_id?: string;
  expiration_at_ms?: number;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}
