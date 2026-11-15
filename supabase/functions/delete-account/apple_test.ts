// Run: deno test supabase/functions/delete-account/apple_test.ts
import {
  assert,
  assertEquals,
} from 'jsr:@std/assert@1';
import {
  appleConfigFrom,
  type AppleConfig,
  makeClientSecret,
  revokeAppleTokens,
} from './apple.ts';

/** A throwaway P-256 key pair, exported as a .p8-style PEM. */
async function testConfig(): Promise<{ config: AppleConfig; publicKey: CryptoKey }> {
  const pair = await crypto.subtle.generateKey(
    { name: 'ECDSA', namedCurve: 'P-256' },
    true,
    ['sign', 'verify'],
  ) as CryptoKeyPair;
  const pkcs8 = new Uint8Array(await crypto.subtle.exportKey('pkcs8', pair.privateKey));
  let s = '';
  for (const b of pkcs8) s += String.fromCharCode(b);
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(s)}\n-----END PRIVATE KEY-----`;
  return {
    config: { teamId: 'TEAM123456', keyId: 'KEY1234567', privateKeyPem: pem, clientId: 'com.example.app' },
    publicKey: pair.publicKey,
  };
}

function b64urlDecode(s: string): Uint8Array<ArrayBuffer> {
  const pad = s.length % 4 === 0 ? '' : '='.repeat(4 - (s.length % 4));
  return Uint8Array.from(atob(s.replace(/-/g, '+').replace(/_/g, '/') + pad), (c) => c.charCodeAt(0));
}

Deno.test('client secret is a valid ES256 JWT with Apple claims', async () => {
  const { config, publicKey } = await testConfig();
  const jwt = await makeClientSecret(config, 1_700_000_000, 300);
  const [h, p, sig] = jwt.split('.');

  assertEquals(JSON.parse(new TextDecoder().decode(b64urlDecode(h))), { alg: 'ES256', kid: 'KEY1234567' });
  assertEquals(JSON.parse(new TextDecoder().decode(b64urlDecode(p))), {
    iss: 'TEAM123456',
    iat: 1_700_000_000,
    exp: 1_700_000_300,
    aud: 'https://appleid.apple.com',
    sub: 'com.example.app',
  });
  const valid = await crypto.subtle.verify(
    { name: 'ECDSA', hash: 'SHA-256' },
    publicKey,
    b64urlDecode(sig),
    new TextEncoder().encode(`${h}.${p}`),
  );
  assert(valid, 'signature must verify with the matching public key');
});

Deno.test('accepts a key whose newlines arrived as literal \\n', async () => {
  const { config } = await testConfig();
  const flattened = { ...config, privateKeyPem: config.privateKeyPem.replace(/\n/g, '\\n') };
  const jwt = await makeClientSecret(flattened);
  assertEquals(jwt.split('.').length, 3);
});

Deno.test('config is null until team id, key id and key are all set', () => {
  const env = (vars: Record<string, string>) => (name: string) => vars[name];
  assertEquals(appleConfigFrom(env({})), null);
  assertEquals(appleConfigFrom(env({ APPLE_TEAM_ID: 'T', APPLE_SIWA_KEY_ID: 'K' })), null);
  const config = appleConfigFrom(env({ APPLE_TEAM_ID: 'T', APPLE_SIWA_KEY_ID: 'K', APPLE_SIWA_PRIVATE_KEY: 'P' }));
  assertEquals(config?.clientId, 'com.ourgarage.ourgarage');
});

Deno.test('skips without a code or without config, and never calls Apple', async () => {
  const { config } = await testConfig();
  let calls = 0;
  const fetchSpy = (() => { calls++; return Promise.resolve(new Response('{}')); }) as typeof fetch;
  assertEquals((await revokeAppleTokens(null, config, fetchSpy)).status, 'skipped_no_code');
  assertEquals((await revokeAppleTokens('code', null, fetchSpy)).status, 'skipped_not_configured');
  assertEquals(calls, 0);
});

Deno.test('exchanges the code, then revokes the refresh token', async () => {
  const { config } = await testConfig();
  const requests: { url: string; body: URLSearchParams }[] = [];
  const fakeFetch = (async (input: string | URL | Request, init?: RequestInit) => {
    const body = new URLSearchParams(String(init?.body));
    requests.push({ url: String(input), body });
    if (String(input).endsWith('/auth/token')) {
      return new Response(JSON.stringify({ refresh_token: 'r-token', access_token: 'a-token' }));
    }
    return new Response('', { status: 200 });
  }) as typeof fetch;

  const result = await revokeAppleTokens('auth-code', config, fakeFetch);

  assertEquals(result.status, 'revoked');
  assertEquals(requests.map((r) => r.url), [
    'https://appleid.apple.com/auth/token',
    'https://appleid.apple.com/auth/revoke',
  ]);
  assertEquals(requests[0].body.get('code'), 'auth-code');
  assertEquals(requests[0].body.get('grant_type'), 'authorization_code');
  assertEquals(requests[0].body.get('client_id'), 'com.example.app');
  assertEquals(requests[1].body.get('token'), 'r-token');
  assertEquals(requests[1].body.get('token_type_hint'), 'refresh_token');
  assertEquals(requests[1].body.get('client_secret')?.split('.').length, 3);
});

Deno.test('reports failure instead of throwing when Apple rejects the code', async () => {
  const { config } = await testConfig();
  const fakeFetch = (() => Promise.resolve(new Response('{"error":"invalid_grant"}', { status: 400 }))) as typeof fetch;
  const result = await revokeAppleTokens('stale-code', config, fakeFetch);
  assertEquals(result.status, 'failed');
  assert(result.detail?.includes('400'));
});

Deno.test('reports failure for a malformed key without leaking it', async () => {
  const config: AppleConfig = { teamId: 'T', keyId: 'K', privateKeyPem: 'not-a-key', clientId: 'c' };
  const result = await revokeAppleTokens('code', config, (() => { throw new Error('should not fetch'); }) as typeof fetch);
  assertEquals(result.status, 'failed');
  assert(!result.detail?.includes('not-a-key'));
});
