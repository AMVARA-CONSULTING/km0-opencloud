import { test, expect } from '@playwright/test';

const DESKTOP_OAUTH_QUERY = {
  client_id: 'OpenCloudAndroid',
  redirect_uri: 'oc://android.opencloud.eu',
  response_type: 'code',
  scope: 'openid profile email offline_access',
  prompt: 'login',
  code_challenge: 'mOQO8SqT_ox0NxkebWyGI3a89Fb2Nkiq5LYjAB6_d08',
  code_challenge_method: 'S256',
  state: 'ykzGt6IJWMub64Dw8Sbw',
};

const REQUIRED_PARAMS = [
  'client_id',
  'redirect_uri',
  'response_type',
  'scope',
  'state',
  'code_challenge',
  'code_challenge_method',
] as const;

function extractHrefParams(html: string, connector: 'google' | 'ldap'): URLSearchParams | null {
  const pattern =
    connector === 'google'
      ? /href="([^"]*\/dex\/auth\/google[^"]*)"/
      : /href="([^"]*\/dex\/auth\/ldap[^"]*)"/;
  const match = html.match(pattern);
  if (!match) return null;
  const href = match[1].replace(/&amp;/g, '&');
  try {
    return new URL(href, 'https://cloud.km0digital.com').searchParams;
  } catch {
    return null;
  }
}

test.describe('Desktop OAuth/OIDC login flow', () => {
  test('Dex auth picker uses card layout aligned with login landing', async ({ page }) => {
    const query = new URLSearchParams(DESKTOP_OAUTH_QUERY).toString();
    await page.goto('/dex/auth?' + query);
    await expect(page.locator('.km0-card')).toBeVisible();
    await expect(page.locator('.theme-navbar')).toHaveCount(0);
    await expect(page.locator('.km0-pricing-notice, .pricing-notice')).toBeVisible();
  });

  test('connector links preserve OAuth/OIDC parameters', async ({ page }) => {
    const query = new URLSearchParams(DESKTOP_OAUTH_QUERY).toString();
    const response = await page.goto('/dex/auth?' + query);
    expect(response?.status()).toBeLessThan(400);
    const html = await page.content();

    for (const connector of ['google', 'ldap'] as const) {
      const params = extractHrefParams(html, connector);
      expect(params, `${connector} connector link`).not.toBeNull();
      for (const key of REQUIRED_PARAMS) {
        expect(params!.get(key), `${connector}.${key}`).toBe(
          DESKTOP_OAUTH_QUERY[key as keyof typeof DESKTOP_OAUTH_QUERY],
        );
      }
    }
  });

  test('web client still redirects to canonical login landing', async ({ request }) => {
    const query = new URLSearchParams({
      client_id: 'opencloud-web',
      redirect_uri: 'https://cloud.km0digital.com/oidc-callback.html',
      response_type: 'code',
      scope: 'openid profile email',
      code_challenge: 'test-challenge',
      code_challenge_method: 'S256',
      state: 'web-client-state',
    }).toString();
    const response = await request.get('/dex/auth?' + query, { maxRedirects: 0 });
    expect(response.status()).toBe(302);
    expect(response.headers()['location']).toMatch(/\/login\.html\?/);
    const location = new URL(response.headers()['location'], 'https://cloud.km0digital.com');
    for (const key of REQUIRED_PARAMS) {
      expect(location.searchParams.get(key)).toBeTruthy();
    }
  });

  test('LDAP login shows invalid credentials error state', async ({ page }) => {
    const params = new URLSearchParams({
      client_id: 'OpenCloudAndroid',
      redirect_uri: 'oc://android.opencloud.eu',
      response_type: 'code',
      scope: 'openid profile email offline_access',
      code_challenge: 'test-challenge-value',
      code_challenge_method: 'S256',
      state: 'invalid-creds-state',
    });
    await page.goto('/dex/auth/ldap/login?' + params.toString());
    await page.locator('#login').fill('invalid-user@example.com');
    await page.locator('#password').fill('wrong-password-!1');
    await page.locator('#submit-login').click();
    await expect(page.locator('#login-error, .dex-error-box')).toBeVisible();
  });
});

test.describe('dex-auth.js OIDC resume helpers', () => {
  test('login page exposes KM0DexAuth helpers', async ({ page }) => {
    await page.goto('/login.html');
    const hasHelpers = await page.evaluate(() => {
      const auth = (window as typeof window & { KM0DexAuth?: Record<string, unknown> }).KM0DexAuth;
      return !!auth &&
        typeof auth.oidcParamsFromUrl === 'function' &&
        typeof auth.startDexLogin === 'function' &&
        typeof auth.clearAllAuthState === 'function';
    });
    expect(hasHelpers).toBeTruthy();
  });

  test('oidcParamsFromUrl parses desktop OAuth query string', async ({ page }) => {
    const query = new URLSearchParams(DESKTOP_OAUTH_QUERY).toString();
    await page.goto('/login.html?' + query);
    const parsed = await page.evaluate(() => {
      const auth = (window as typeof window & {
        KM0DexAuth?: { oidcParamsFromUrl: () => Record<string, string> | null };
      }).KM0DexAuth;
      return auth?.oidcParamsFromUrl?.() || null;
    });
    expect(parsed).not.toBeNull();
    for (const key of REQUIRED_PARAMS) {
      expect(parsed![key]).toBe(DESKTOP_OAUTH_QUERY[key as keyof typeof DESKTOP_OAUTH_QUERY]);
    }
  });
});
