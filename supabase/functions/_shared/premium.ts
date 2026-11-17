// Household premium, reconciled against RevenueCat.
//
// RevenueCat's REST API is the source of truth. Used by `claim-premium` (a
// member says "my purchase should cover my household") and by every
// `revenuecat-webhook` event (each one only means "these users changed,
// re-check them" — the payload's type, expiry and order are never trusted).
//
// For each affected household, every member's entitlement is fetched and the
// whole set goes to the SQL function `apply_household_premium`, the only
// writer of granted premium. It picks the best active entitlement among
// current members under a row lock (see migration 20261117000300), so there
// is no read-decide-write here to race.
//
// Why this exists at all: the paywall comes before sign-in, so a purchase is
// made under an anonymous RevenueCat id before any household exists, and a
// lifetime purchase never sends another event. Asking RevenueCat directly,
// once the user is identified and in a household, closes that gap.

const REVENUECAT_API = 'https://api.revenuecat.com/v1';

export interface Entitlement {
  active: boolean;
  /// ISO timestamp; null for a lifetime purchase (or when inactive).
  expiresAt: string | null;
}

export interface RevenueCatConfig {
  secretKey: string;
  entitlementId: string;
  timeoutMs?: number;
  fetchFn?: typeof fetch;
  now?: () => number;
}

/// Reads the RevenueCat config from the environment, or null if the secret
/// key is not set. The key is a RevenueCat *secret* (sk_) key: it can grant
/// entitlements, so it lives only in Supabase secrets and is never logged.
export function revenueCatConfigFrom(
  env: (name: string) => string | undefined,
): RevenueCatConfig | null {
  const secretKey = env('REVENUECAT_SECRET_KEY');
  if (!secretKey) return null;
  return {
    secretKey,
    entitlementId: env('REVENUECAT_ENTITLEMENT_ID') || 'premium',
  };
}

/// Whether [userId]'s entitlement is active right now, per RevenueCat.
///
/// Throws on anything but a clean answer — timeout, 429, 5xx — so callers
/// return 5xx (the webhook is retried) rather than read an outage as "not
/// premium" and revoke.
export async function fetchEntitlement(
  userId: string,
  config: RevenueCatConfig,
): Promise<Entitlement> {
  const fetchFn = config.fetchFn ?? fetch;
  const now = (config.now ?? Date.now)();

  const response = await fetchFn(
    `${REVENUECAT_API}/subscribers/${encodeURIComponent(userId)}`,
    {
      headers: {
        Authorization: `Bearer ${config.secretKey}`,
        Accept: 'application/json',
      },
      signal: AbortSignal.timeout(config.timeoutMs ?? 5000),
    },
  );
  if (response.status === 404) return { active: false, expiresAt: null };
  if (!response.ok) {
    // Status only: the body can echo request details, never worth logging.
    throw new Error(`RevenueCat lookup failed (${response.status})`);
  }

  const body = await response.json();
  const entitlement = body?.subscriber?.entitlements?.[config.entitlementId];
  if (!entitlement) return { active: false, expiresAt: null };

  // RevenueCat reports a lifetime (non-expiring) entitlement as a null
  // expires_date.
  if (entitlement.expires_date == null) return { active: true, expiresAt: null };

  // Grace period (billing retry) still counts as entitled, as it does in the
  // SDK's own `isActive`.
  const latest = [entitlement.expires_date, entitlement.grace_period_expires_date]
    .filter((d): d is string => typeof d === 'string')
    .map((d) => Date.parse(d))
    .filter((t) => !Number.isNaN(t))
    .reduce((a, b) => Math.max(a, b), -Infinity);
  if (latest > now) {
    return { active: true, expiresAt: new Date(latest).toISOString() };
  }
  return { active: false, expiresAt: null };
}

export interface ReconcileResult {
  household_id: string;
  is_premium: boolean;
  changed: boolean;
}

// The supabase-js client, kept structural so tests can pass a small fake.
// deno-lint-ignore no-explicit-any
export type AdminClient = any;

/// Every household any of [userIds] belongs to, each reconciled once.
/// [admin] must be a service-role client.
export async function reconcileUsers(
  admin: AdminClient,
  userIds: string[],
  config: RevenueCatConfig,
): Promise<ReconcileResult[]> {
  if (userIds.length === 0) return [];

  const { data, error } = await admin
    .from('household_members')
    .select('household_id')
    .in('user_id', userIds);
  if (error) throw new Error('Membership lookup failed');

  const households = [
    ...new Set((data ?? []).map((r: { household_id: string }) => r.household_id)),
  ] as string[];

  // One REST call per distinct user, however many households they share.
  const cache = new Map<string, Promise<Entitlement>>();
  const results: ReconcileResult[] = [];
  for (const householdId of households) {
    results.push(await reconcileHousehold(admin, householdId, config, cache));
  }
  return results;
}

/// Fetches every member's entitlement, then lets `apply_household_premium`
/// decide. Any fetch failure throws before anything is written.
export async function reconcileHousehold(
  admin: AdminClient,
  householdId: string,
  config: RevenueCatConfig,
  cache: Map<string, Promise<Entitlement>>,
): Promise<ReconcileResult> {
  const { data, error } = await admin
    .from('household_members')
    .select('user_id')
    .eq('household_id', householdId);
  if (error) throw new Error('Member lookup failed');

  const members = (data ?? []).map((r: { user_id: string }) => r.user_id) as string[];
  const entitlements = await Promise.all(members.map((userId) => {
    let pending = cache.get(userId);
    if (!pending) {
      pending = fetchEntitlement(userId, config);
      cache.set(userId, pending);
    }
    return pending;
  }));

  const { data: applied, error: rpcError } = await admin.rpc('apply_household_premium', {
    hid: householdId,
    entitlements: members.map((userId, i) => ({
      user_id: userId,
      active: entitlements[i].active,
      expires_at: entitlements[i].expiresAt,
    })),
  });
  if (rpcError) throw new Error('apply_household_premium failed');

  // Null: the household was deleted between the lookup and the write.
  if (!applied) return { household_id: householdId, is_premium: false, changed: false };
  return applied as ReconcileResult;
}

/// RevenueCat app user ids that are Supabase users (not `$RCAnonymousID:…`).
export function supabaseUserIds(ids: unknown): string[] {
  if (!Array.isArray(ids)) return [];
  const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  return [...new Set(ids.filter((id): id is string => typeof id === 'string' && uuid.test(id)))];
}

/// Supabase user ids a webhook event concerns.
export function eventUserIds(event: {
  app_user_id?: string;
  original_app_user_id?: string;
  aliases?: string[];
  transferred_from?: string[];
  transferred_to?: string[];
}): string[] {
  return supabaseUserIds([
    event.app_user_id,
    event.original_app_user_id,
    ...(event.aliases ?? []),
    ...(event.transferred_from ?? []),
    ...(event.transferred_to ?? []),
  ]);
}
