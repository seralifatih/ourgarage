// Sign in with Apple token revocation.
//
// Apple requires apps that offer account deletion to revoke the user's Sign in
// with Apple tokens (TN3194 / App Store guideline 5.1.1(v)). Revoking needs a
// refresh or access token, which a native app never keeps — so the app sends a
// fresh authorization code (it shows the Apple sheet once more at deletion
// time), and this module exchanges it and revokes the result:
//
//   1. POST /auth/token   code -> refresh_token (and access_token)
//   2. POST /auth/revoke  refresh_token
//
// Both calls authenticate with a client secret: a short-lived ES256 JWT signed
// with the Sign in with Apple private key. It is minted per request rather than
// stored, so there is no six-month expiry to remember to rotate.
//
// Kept free of Deno.env and global fetch so it can be unit-tested.

export interface AppleConfig {
  teamId: string;
  keyId: string;
  /** The .p8 file contents, PEM, including the BEGIN/END lines. */
  privateKeyPem: string;
  /** For a native app, its bundle identifier. */
  clientId: string;
}

export type AppleRevokeStatus =
  | 'revoked'
  | 'skipped_no_code'
  | 'skipped_not_configured'
  | 'failed';

const APPLE = 'https://appleid.apple.com';

/** Reads the config from environment-shaped input; null when incomplete. */
export function appleConfigFrom(
  env: (name: string) => string | undefined,
): AppleConfig | null {
  const teamId = env('APPLE_TEAM_ID')?.trim();
  const keyId = env('APPLE_SIWA_KEY_ID')?.trim();
  const privateKeyPem = env('APPLE_SIWA_PRIVATE_KEY')?.trim();
  const clientId = env('APPLE_CLIENT_ID')?.trim() || 'com.ourgarage.ourgarage';
  if (!teamId || !keyId || !privateKeyPem) return null;
  return { teamId, keyId, privateKeyPem, clientId };
}

function base64url(bytes: Uint8Array): string {
  let s = '';
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function base64urlJson(value: unknown): string {
  return base64url(new TextEncoder().encode(JSON.stringify(value)));
}

async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const body = pem
    // Secrets set from a shell sometimes arrive with literal "\n" sequences.
    .replace(/\\n/g, '\n')
    .replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----/g, '')
    .replace(/\s+/g, '');
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return await crypto.subtle.importKey(
    'pkcs8',
    der,
    { name: 'ECDSA', namedCurve: 'P-256' },
    false,
    ['sign'],
  );
}

/**
 * The client secret Apple expects: an ES256 JWT, valid for [ttlSeconds].
 * WebCrypto's ECDSA signature is already the raw r||s form JWS uses.
 */
export async function makeClientSecret(
  config: AppleConfig,
  nowSeconds = Math.floor(Date.now() / 1000),
  ttlSeconds = 300,
): Promise<string> {
  const header = { alg: 'ES256', kid: config.keyId };
  const claims = {
    iss: config.teamId,
    iat: nowSeconds,
    exp: nowSeconds + ttlSeconds,
    aud: APPLE,
    sub: config.clientId,
  };
  const signingInput = `${base64urlJson(header)}.${base64urlJson(claims)}`;
  const key = await importPrivateKey(config.privateKeyPem);
  const signature = await crypto.subtle.sign(
    { name: 'ECDSA', hash: 'SHA-256' },
    key,
    new TextEncoder().encode(signingInput),
  );
  return `${signingInput}.${base64url(new Uint8Array(signature))}`;
}

/**
 * Exchanges [authorizationCode] and revokes the resulting token.
 *
 * Never throws: account deletion must not be blocked by an Apple outage, so
 * every failure becomes a status the caller logs and reports.
 */
export async function revokeAppleTokens(
  authorizationCode: string | null | undefined,
  config: AppleConfig | null,
  fetchImpl: typeof fetch = fetch,
): Promise<{ status: AppleRevokeStatus; detail?: string }> {
  if (!authorizationCode) return { status: 'skipped_no_code' };
  if (!config) return { status: 'skipped_not_configured' };

  try {
    const clientSecret = await makeClientSecret(config);

    const tokenResponse = await fetchImpl(`${APPLE}/auth/token`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        client_id: config.clientId,
        client_secret: clientSecret,
        code: authorizationCode,
        grant_type: 'authorization_code',
      }),
    });
    if (!tokenResponse.ok) {
      return {
        status: 'failed',
        detail: `token exchange ${tokenResponse.status}: ${await safeText(tokenResponse)}`,
      };
    }
    const tokens = await tokenResponse.json() as {
      refresh_token?: string;
      access_token?: string;
    };
    const token = tokens.refresh_token ?? tokens.access_token;
    const hint = tokens.refresh_token ? 'refresh_token' : 'access_token';
    if (!token) return { status: 'failed', detail: 'no token in response' };

    const revokeResponse = await fetchImpl(`${APPLE}/auth/revoke`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        client_id: config.clientId,
        client_secret: clientSecret,
        token,
        token_type_hint: hint,
      }),
    });
    if (!revokeResponse.ok) {
      return {
        status: 'failed',
        detail: `revoke ${revokeResponse.status}: ${await safeText(revokeResponse)}`,
      };
    }
    return { status: 'revoked' };
  } catch (error) {
    // Includes a malformed private key. The message never contains key material.
    return { status: 'failed', detail: String(error) };
  }
}

async function safeText(response: Response): Promise<string> {
  try {
    return (await response.text()).slice(0, 200);
  } catch {
    return '';
  }
}
