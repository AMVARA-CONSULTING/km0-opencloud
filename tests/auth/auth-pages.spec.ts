import { test, expect } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';

const PRICING_MARKERS = ['1,99', '1.99', '€1.99', '€1,99'];

test.describe('Authentication page content', () => {
  test('login page shows payment explanation', async ({ page }) => {
    await page.goto('/login.html');
    const notice = page.locator('.pricing-notice');
    await expect(notice).toBeVisible();
    const text = await notice.innerText();
    expect(PRICING_MARKERS.some((marker) => text.includes(marker))).toBeTruthy();
    await expect(page.getByRole('link', { name: /precios|pricing|preus|Preise/i })).toBeVisible();
  });

  test('register page shows payment explanation', async ({ page }) => {
    await page.goto('/register');
    const notice = page.locator('.pricing-notice');
    await expect(notice).toBeVisible();
    const text = await notice.innerText();
    expect(PRICING_MARKERS.some((marker) => text.includes(marker))).toBeTruthy();
  });

  test('payment wording is consistent between login and register', async ({ page }) => {
    await page.goto('/login.html');
    const loginText = (await page.locator('.pricing-notice').innerText()).replace(/\s+/g, ' ').trim();
    await page.goto('/register');
    const registerText = (await page.locator('.pricing-notice').innerText()).replace(/\s+/g, ' ').trim();
    expect(loginText).toBe(registerText);
  });

  test('logout page shows KM0 branding and actions', async ({ page }) => {
    await page.goto('/logout?from_dex=1');
    await expect(page.locator('.logo')).toBeVisible();
    await expect(page.getByRole('heading', { level: 1 })).toBeVisible();
    await expect(page.getByRole('link', { name: /iniciar sesión|sign in|sessió|Anmeldung/i })).toBeVisible();
    await expect(page.getByRole('link', { name: /km0digital\.com/i })).toBeVisible();
    await expect(page.locator('body')).toContainText(/Kil[oó]metr/i);
  });

  test('logout page does not expose default OpenCloud splash UI', async ({ page }) => {
    await page.goto('/logout?from_dex=1');
    await expect(page.locator('#loading')).toHaveCount(0);
    await expect(page.locator('.splash-banner')).toHaveCount(0);
  });
});

test.describe('Visual regression', () => {
  test('login page screenshot', async ({ page }) => {
    await page.goto('/login.html');
    await expect(page.locator('.card')).toHaveScreenshot('login-page.png', { fullPage: true });
  });

  test('register page screenshot', async ({ page }) => {
    await page.goto('/register');
    await expect(page.locator('.card')).toHaveScreenshot('register-page.png', { fullPage: true });
  });

  test('logout page screenshot', async ({ page }) => {
    await page.goto('/logout?from_dex=1');
    await expect(page.locator('.card')).toHaveScreenshot('logout-page.png', { fullPage: true });
  });

  test('desktop Dex auth picker screenshot', async ({ page }) => {
    const params = new URLSearchParams({
      client_id: 'OpenCloudAndroid',
      redirect_uri: 'oc://android.opencloud.eu',
      response_type: 'code',
      scope: 'openid profile email offline_access',
      prompt: 'login',
      code_challenge: 'test-challenge-value',
      code_challenge_method: 'S256',
      state: 'visual-regression-state',
    });
    await page.goto('/dex/auth?' + params.toString());
    await expect(page.locator('.km0-card, .theme-panel')).toBeVisible();
    await expect(page.locator('.km0-card, .theme-panel')).toHaveScreenshot('dex-auth-picker.png', {
      fullPage: true,
    });
  });

  test('Dex LDAP login screenshot', async ({ page }) => {
    const params = new URLSearchParams({
      client_id: 'opencloud-web',
      redirect_uri: 'https://cloud.km0digital.com/oidc-callback.html',
      response_type: 'code',
      scope: 'openid profile email',
      code_challenge: 'test-challenge-value',
      code_challenge_method: 'S256',
      state: 'visual-regression-state',
    });
    await page.goto('/dex/auth/ldap/login?' + params.toString());
    await expect(page.locator('.km0-card')).toBeVisible();
    await expect(page.locator('.km0-card')).toHaveScreenshot('dex-ldap-login.png', { fullPage: true });
  });
});

test.describe('Accessibility', () => {
  for (const path of ['/login.html', '/register', '/logout?from_dex=1']) {
    test(`a11y scan ${path}`, async ({ page }) => {
      await page.goto(path);
      const results = await new AxeBuilder({ page }).analyze();
      expect(results.violations).toEqual([]);
    });
  }
});
