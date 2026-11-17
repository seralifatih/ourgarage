// RevenueCat webhook receiver.
//
// A trigger, not a source of truth. Every event (other than TEST) means "these
// users' entitlements may have changed": the users it names are looked up, and
// each of their households is re-reconciled from RevenueCat's REST API across
// all of its members (../_shared/premium.ts, then the SQL function
// apply_household_premium). The payload's type, expiry and source are never
// written as-is — that is what let one member's EXPIRATION wipe premium
// another member provided, and a renewal overwrite someone's lifetime. Because
// the payload is ignored and the write is idempotent, RevenueCat's
// at-least-once, out-of-order delivery doesn't matter.
//
// One member pays and the whole household becomes premium; households.
// is_premium and its companion columns are writable only server-side (column
// grants and guard triggers in the sharing-layer migration).
//
// Deploy:
//   supabase functions deploy revenuecat-webhook --no-verify-jwt --use-api
//   supabase secrets set REVENUECAT_WEBHOOK_SECRET=...
//   supabase secrets set REVENUECAT_SECRET_KEY=sk_...   (required; never echo it)
//
// `--no-verify-jwt` is required and safe: RevenueCat has no Supabase JWT to
// present. Authentication is the Authorization header checked below, which is
// why that check must never be made conditional.

import { createClient } from 'jsr:@supabase/supabase-js@2';
import { eventUserIds, reconcileUsers, revenueCatConfigFrom } from '../_shared/premium.ts';

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
  // header. Anyone who can reach this endpoint without it could trigger
  // reconciles, so this is the whole security boundary.
  if (!constantTimeEqual(req.headers.get('Authorization') ?? '', expectedSecret)) {
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

  if (event.type === 'TEST') return json({ ok: true, ignored: 'TEST' });

  const revenueCat = revenueCatConfigFrom((name) => Deno.env.get(name));
  if (!revenueCat) {
    // 500 so RevenueCat retries once the secret is set.
    console.error('REVENUECAT_SECRET_KEY is not configured');
    return json({ error: 'Server misconfigured' }, 500);
  }

  // Anonymous ids only: a purchase before sign-in. claim-premium picks it up
  // once the user has created or joined a household.
  const users = eventUserIds(event);
  if (users.length === 0) return json({ ok: true, skipped: 'no-supabase-user' });

  const admin = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { persistSession: false } },
  );

  try {
    // Users in no household yet give [] — acknowledged, nothing to do.
    const households = await reconcileUsers(admin, users, revenueCat);
    return json({ ok: true, households });
  } catch (error) {
    // RevenueCat down, timeout, 429 or a database error: 500 so it retries.
    console.error('Reconcile failed:', (error as Error).message);
    return json({ error: 'Reconcile failed' }, 500);
  }
});

interface RevenueCatEvent {
  type: string;
  app_user_id?: string;
  original_app_user_id?: string;
  aliases?: string[];
  transferred_from?: string[];
  transferred_to?: string[];
}

/// Compares without an early exit, so response timing doesn't reveal how much
/// of a guessed secret was right.
function constantTimeEqual(a: string, b: string): boolean {
  const x = new TextEncoder().encode(a);
  const y = new TextEncoder().encode(b);
  let diff = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) {
    diff |= (x[i] ?? 0) ^ (y[i] ?? 0);
  }
  return diff === 0;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}
