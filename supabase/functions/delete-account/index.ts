// Deletes the calling user's account (App Store guideline 5.1.1(v)).
//
// Order matters:
//   1. Verify the caller from their JWT. The user id comes from the token,
//      never from the request body, so nobody can delete someone else.
//   2. delete_account_data(): removes or hands over their households and
//      deletes their profile, in one transaction (see the migration).
//   3. Revoke their Sign in with Apple tokens, using the fresh authorization
//      code the app obtained by showing the Apple sheet at deletion time.
//      Only after step 2 succeeded, so a failed deletion never leaves a live
//      account with its Apple link cut. Best effort: a failure is logged and
//      reported, but does not stop the deletion — a user's right to delete
//      must not depend on Apple's uptime.
//   4. Delete the auth user.
//
// Steps 2 and 4 are each safe to repeat, so a deletion that fails between them
// is finished by retrying.
//
// Deploy (JWT verification stays ON, which is the default):
//   supabase functions deploy delete-account
// Secrets for step 3 (see the project notes for how to create the key):
//   APPLE_TEAM_ID, APPLE_SIWA_KEY_ID, APPLE_SIWA_PRIVATE_KEY,
//   APPLE_CLIENT_ID (optional; defaults to the app's bundle id)
// SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY are provided
// to every Edge Function automatically.

import { createClient } from 'jsr:@supabase/supabase-js@2';
import { appleConfigFrom, revokeAppleTokens } from './apple.ts';

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== 'POST') {
    return json({ error: 'Method not allowed' }, 405);
  }

  const url = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !anonKey || !serviceKey) {
    console.error('Supabase environment is not configured');
    return json({ error: 'Server misconfigured' }, 500);
  }

  const authorization = req.headers.get('Authorization');
  if (!authorization?.startsWith('Bearer ')) {
    return json({ error: 'Unauthorized' }, 401);
  }

  // Resolve the caller with their own token. getUser() asks the auth server,
  // so a forged or expired JWT fails here.
  const asCaller = createClient(url, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  });
  const { data: userData, error: userError } = await asCaller.auth.getUser();
  const userId = userData?.user?.id;
  if (userError || !userId) {
    return json({ error: 'Unauthorized' }, 401);
  }

  let body: { appleAuthorizationCode?: unknown } = {};
  try {
    body = await req.json();
  } catch {
    // An empty body is allowed: deletion proceeds without Apple revocation.
  }
  const code = typeof body.appleAuthorizationCode === 'string'
    ? body.appleAuthorizationCode
    : null;

  const admin = createClient(url, serviceKey, {
    auth: { persistSession: false },
  });

  const { data: summary, error: dataError } = await admin.rpc(
    'delete_account_data',
    { target: userId },
  );
  if (dataError) {
    console.error(`delete_account_data failed for ${userId}:`, dataError);
    return json({ error: 'Could not delete account data' }, 500);
  }

  const apple = await revokeAppleTokens(
    code,
    appleConfigFrom((name) => Deno.env.get(name)),
  );
  if (apple.status !== 'revoked') {
    console.warn(`Apple revocation for ${userId}: ${apple.status} ${apple.detail ?? ''}`);
  }

  const { error: authError } = await admin.auth.admin.deleteUser(userId);
  if (authError) {
    console.error(`auth deleteUser failed for ${userId}:`, authError);
    return json({ error: 'Could not delete account' }, 500);
  }

  return json({ ok: true, apple: apple.status, summary });
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}
