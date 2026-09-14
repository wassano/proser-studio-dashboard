import { expect, test, type Page } from '@playwright/test';

async function fixture(page: Page) {
  const plan = { id: 1, name: 'Studio', features: { lighting: true, audio: true, video: true, scenes: true, rdm: true, effects: true, video_capture: true, powerpoint: true }, limits: { fixtures: 170, audios: 256, videos: 512, scenes: 128 }, offline_hours: 24 };
  const license = { id: 1, name: 'Auditório principal', plan_id: 1, plan_name: 'Studio', status: 'active', max_devices: 1, active_devices: 1, expires_at: null, minimum_version: '1.18.0', channel: 'stable', feature_overrides: {}, limit_overrides: {} };
  const settings = { installation_limit: 20, active_installations: 1, registration_enabled: true, plan_id: 1 };
  const device = { id: 1, device_id: 'a'.repeat(64), computer_name: 'PC-PALCO', os: 'Windows 11', arch: 'x64', app_version: '1.18.0', target: 'win-x64', status: 'active', access_status: 'active', activated_at: '2026-09-12T12:00:00Z', last_seen_at: '2026-09-12T15:20:00Z', last_ip: '203.0.113.10', location: 'Sorocaba, SP, BR', license };
  const releases: Record<string, unknown>[] = [];
  await page.route('**/api/**', async route => {
    const url = new URL(route.request().url()), method = route.request().method();
    let result: unknown = {};
    if (url.pathname === '/api/session') result = { email: 'dwassano@gmail.com', csrf_token: 'test-csrf' };
    else if (url.pathname === '/api/admin/settings') { if (method === 'PATCH') Object.assign(settings, route.request().postDataJSON().settings); result = settings; }
    else if (url.pathname.startsWith('/api/admin/plans')) { if (method === 'PATCH') Object.assign(plan, route.request().postDataJSON().plan); result = { items: [plan] }; }
    else if (url.pathname === '/api/admin/installations') result = { items: [device], total: 1, page: 1 };
    else if (url.pathname === '/api/admin/installations/1') { Object.assign(device, { status: 'revoked', access_status: 'revoked' }); result = device; }
    else if (url.pathname.startsWith('/api/admin/licenses')) { if (method === 'PATCH') Object.assign(license, route.request().postDataJSON().license); result = { items: [license], total: 1, page: 1 }; }
    else if (url.pathname === '/api/admin/releases') { if (method === 'POST') releases.push({ id: 1, ...route.request().postDataJSON().release, status: 'draft', release_assets: [] }); result = { items: releases, total: releases.length, page: 1 }; }
    if (!['GET'].includes(method)) expect(route.request().headers()['x-csrf-token']).toBe('test-csrf');
    await route.fulfill({ contentType: 'application/json', body: JSON.stringify(result) });
  });
}
test('unauthenticated dashboard offers Google only', async ({ page }) => {
  await page.route('**/api/session', route => route.fulfill({ status: 401, json: { error: 'Entre com Google' } }));
  await page.goto('/');
  await expect(page.getByRole('link', { name: /Entrar com Google/ })).toHaveAttribute('href', '/auth/google');
  await expect(page.locator('input[type=password]')).toHaveCount(0);
});
test('shows installations and saves the global cap and feature controls', async ({ page }) => {
  const errors: string[] = []; page.on('pageerror', error => errors.push(error.message));
  await fixture(page); await page.goto('/');
  await expect(page.getByText('PC-PALCO', { exact: true })).toBeVisible();
  await expect(page.getByText('203.0.113.10')).toBeVisible();
  await expect(page.getByText('Sorocaba, SP, BR')).toBeVisible();
  await page.screenshot({ path: 'test-results/dashboard-desktop.png', fullPage: true });
  await page.getByRole('button', { name: 'Admissão', exact: true }).click();
  await page.getByLabel('Limite global de instalações').fill('25');
  await page.getByRole('button', { name: 'Salvar admissão' }).click();
  await expect(page.getByRole('dialog')).toHaveCount(0);
  await expect(page.getByRole('status')).toContainText('Configuração de admissão salva');
  await page.getByRole('button', { name: 'Planos e recursos', exact: true }).click();
  await page.getByRole('button', { name: 'Editar', exact: true }).click();
  await page.getByLabel('Áudio', { exact: true }).uncheck();
  await page.getByLabel('Refletores', { exact: true }).fill('12');
  await page.getByRole('button', { name: 'Salvar plano' }).click();
  await expect(page.getByRole('dialog')).toHaveCount(0);
  await expect(page.locator('.plan-limits')).toContainText('12');
  expect(errors).toEqual([]);
});
test('creates a release draft and remains usable on narrow screens', async ({ page }) => {
  await fixture(page); await page.goto('/');
  await page.getByRole('button', { name: 'Versões', exact: true }).click();
  await page.getByRole('button', { name: 'Nova versão' }).click();
  await page.getByLabel('Número da versão').fill('1.19.0');
  await page.getByLabel('Novidades desta versão').fill('Licenciamento e atualização automática.');
  await page.getByRole('button', { name: 'Criar rascunho' }).click();
  await expect(page.getByRole('heading', { name: /1.19.0/ })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Publicar', exact: true })).toBeDisabled();
  await page.setViewportSize({ width: 390, height: 844 });
  await page.screenshot({ path: 'test-results/dashboard-mobile.png', fullPage: true });
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
});
test('assigns an existing license through the authenticated approval endpoint', async ({ page }) => {
  await fixture(page); await page.goto('/');
  await page.getByRole('button', { name: 'Vincular', exact: true }).click();
  await page.getByLabel('Licença de destino').selectOption('1');
  const request = page.waitForRequest(req => req.url().endsWith('/api/admin/installations/1/approve') && req.method() === 'POST');
  await page.getByRole('button', { name: 'Vincular e liberar', exact: true }).click();
  expect((await request).postDataJSON()).toEqual({ license_id: 1 });
  await expect(page.getByRole('dialog')).toHaveCount(0);
});

test('uploads installers in bounded chunks before completion', async ({ page }) => {
  await fixture(page);
  const uploads: number[] = [];
  await page.route('**/api/admin/releases/1/uploads**', async route => {
    const request = route.request();
    expect(request.headers()['x-csrf-token']).toBe('test-csrf');
    if (request.url().endsWith('/uploads')) return route.fulfill({ json: { id: 'test-upload', chunk_size: 5 * 1024 * 1024 } });
    if (request.method() === 'PUT') {
      expect(Number(request.headers()['x-upload-offset'])).toBe(uploads.reduce((sum, size) => sum + size, 0));
      uploads.push(request.postDataBuffer()!.length);
      return route.fulfill({ json: { received_bytes: uploads.reduce((sum, size) => sum + size, 0) } });
    }
    expect(request.url()).toContain('/complete');
    expect(uploads).toEqual([5 * 1024 * 1024, 17]);
    await route.fulfill({ json: { id: 1 } });
  });
  await page.goto('/');
  await page.getByRole('button', { name: 'Versões', exact: true }).click();
  await page.getByRole('button', { name: 'Nova versão' }).click();
  await page.getByLabel('Número da versão').fill('1.19.0');
  await page.getByRole('button', { name: 'Criar rascunho' }).click();
  const buffer = Buffer.alloc(5 * 1024 * 1024 + 17, 0x41); buffer.write('MZ');
  await page.locator('input[type=file]').setInputFiles({ name: 'Proser.exe', mimeType: 'application/octet-stream', buffer });
  await expect(page.getByRole('status')).toContainText('Instalador enviado e verificado');
});
