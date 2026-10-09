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
  return { releases };
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
  await expect(page.getByRole('status').filter({ hasText: 'Instalador enviado e verificado' })).toBeVisible();
});


test('login download stays below the access notice at desktop and mobile widths', async ({ page }) => {
  await page.route('**/api/session', route => route.fulfill({ status: 401, json: { error: 'Entre com Google' } }));
  await page.goto('/');
  const download = page.getByRole('link', { name: 'Baixar o Proser studio', exact: true });
  await expect(download).toHaveAttribute('href', '/downloads');
  for (const width of [1440, 679, 390]) {
    await page.setViewportSize({ width, height: 844 });
    const noticeBox = await page.getByText('Acesso exclusivo aos administradores autorizados.', { exact: true }).boundingBox();
    const downloadBox = await download.boundingBox();
    expect(downloadBox!.y).toBeGreaterThanOrEqual(noticeBox!.y + noticeBox!.height + 20);
    expect(downloadBox!.height).toBeGreaterThanOrEqual(44);
    expect(await download.evaluate(element => element.getClientRects().length)).toBe(1);
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
    await page.screenshot({ path: `test-results/login-download-${width}.png`, fullPage: true });
  }
});

test('CI drafts arriving after the page opens refresh automatically and still require manual publication', async ({ page }) => {
  await page.clock.install();
  const { releases } = await fixture(page);
  const publications: string[] = [];
  page.on('request', request => { if (request.url().endsWith('/publish')) publications.push(request.url()); });
  await page.goto('/');
  await page.getByRole('button', { name: 'Versões', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'A primeira versão começa aqui' })).toBeVisible();
  const targets = ['win-x64', 'win7-x64', 'mac-arm64', 'mac-x64'];
  releases.push(...targets.map((target, index) => ({
    id: index + 10, version: '1.21.5', target, channel: 'stable', status: 'draft', published_at: null,
    ci_run_url: 'https://github.com/wassano/proser-studio-desktop/actions/runs/37952390051', ci_ready: true,
    release_assets: [{ id: index + 20, filename: `Proser-${target}.${target.startsWith('mac-') ? 'dmg' : 'exe'}`, size: 1024, sha256: 'a'.repeat(64) }],
  })));
  await page.clock.fastForward(30000);
  await expect(page.getByRole('heading', { name: '1.21.5 Rascunho', exact: true })).toHaveCount(4);
  await expect(page.getByRole('heading', { name: 'A primeira versão começa aqui' })).toHaveCount(0);
  for (const button of await page.getByRole('button', { name: 'Publicar', exact: true }).all()) await expect(button).toBeEnabled();
  releases[0].status = 'published';
  await page.evaluate(() => window.dispatchEvent(new Event('focus')));
  await expect(page.getByRole('heading', { name: '1.21.5 Publicada', exact: true })).toHaveCount(1);
  await expect(page.getByRole('heading', { name: '1.21.5 Rascunho', exact: true })).toHaveCount(3);
  expect(publications).toEqual([]);
});

test('pending release requests show loading instead of an empty catalog', async ({ page }) => {
  await fixture(page);
  let finish!: () => void;
  const pending = new Promise<void>(resolve => { finish = resolve; });
  await page.route('**/api/admin/releases?**', async route => {
    await pending;
    await route.fulfill({ json: { items: [], total: 0, page: 1 } });
  });
  await page.goto('/');
  await page.getByRole('button', { name: 'Versões', exact: true }).click();
  await expect(page.getByRole('status', { name: '' }).filter({ hasText: 'Carregando versões…' })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'A primeira versão começa aqui' })).toHaveCount(0);
  finish();
  await expect(page.getByRole('heading', { name: 'A primeira versão começa aqui' })).toBeVisible();
});


test('administrators can download draft installers and update packages before publication', async ({ page }) => {
  const { releases } = await fixture(page);
  releases.push({ id: 10, version: '1.21.5', target: 'mac-arm64', channel: 'stable', status: 'draft', published_at: null,
    ci_run_url: 'https://github.com/wassano/proser-studio-desktop/actions/runs/37952390051', ci_ready: true,
    release_assets: ['dmg', 'zip'].map((extension, index) => ({ id: index + 20, filename: `Proser studio 1.21.5.${extension}`, size: 1024, sha256: 'a'.repeat(64) })),
  });
  await page.goto('/');
  await page.getByRole('button', { name: 'Versões', exact: true }).click();
  await expect(page.getByRole('heading', { name: '1.21.5 Rascunho', exact: true })).toBeVisible();
  for (const [index, extension] of ['dmg', 'zip'].entries()) {
    const filename = `Proser studio 1.21.5.${extension}`;
    const downloadPath = `/api/admin/releases/10/files/${index + 20}/${encodeURIComponent(filename)}`;
    const downloadLink = page.getByRole('link', { name: `Baixar ${filename}`, exact: true });
    await expect(downloadLink).toHaveAttribute('href', downloadPath);
    await page.route(`**${downloadPath}`, route => route.fulfill({ body: `verified-${extension}`, contentType: 'application/octet-stream', headers: { 'Content-Disposition': `attachment; filename="Proser.${extension}"` } }));
    const downloaded = page.waitForEvent('download');
    await downloadLink.click();
    expect((await downloaded).suggestedFilename()).toBe(`Proser.${extension}`);
  }
  await expect(page.getByRole('button', { name: 'Publicar', exact: true })).toBeEnabled();
  await expect(page.getByRole('button', { name: 'Copiar link público', exact: true })).toHaveCount(0);
  await expect(page.getByRole('heading', { name: '1.21.5 Rascunho', exact: true })).toBeVisible();
  await page.screenshot({ path: 'test-results/admin-draft-downloads-desktop.png', fullPage: true });
  await page.setViewportSize({ width: 390, height: 844 });
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
  await page.screenshot({ path: 'test-results/admin-draft-downloads-mobile.png', fullPage: true });
});
