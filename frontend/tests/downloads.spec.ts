import { expect, test } from '@playwright/test';

test('public downloads work without login and offer verified installer links on mobile', async ({ page }) => {
  const requests: string[] = [];
  page.on('request', request => { if (new URL(request.url()).pathname.startsWith('/api/')) requests.push(new URL(request.url()).pathname); });
  await page.route('**/api/v1/releases', route => route.fulfill({ json: { items: [
    { id: 1, version: '1.22.0', target: 'win-x64', notes: 'Melhorias de iluminação.', assets: [{ id: 2, filename: 'Proser Setup.exe', size: 104857600, sha256: 'a'.repeat(64), download_path: '/api/v1/releases/1/files/2/Proser%20Setup.exe' }] },
    { id: 3, version: '1.22.0', target: 'mac-arm64', notes: '', assets: [{ id: 4, filename: 'Proser.dmg', size: 104857600, sha256: 'b'.repeat(64), download_path: '/api/v1/releases/3/files/4/Proser.dmg' }] },
  ] } }));
  await page.goto('/downloads');
  await expect(page.getByRole('heading', { name: 'Baixe o Proser studio' })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Windows 10/11 · x64' })).toBeVisible();
  await expect(page.getByRole('link', { name: 'Baixar instalador', exact: true })).toHaveAttribute('href', '/api/v1/releases/1/files/2/Proser%20Setup.exe');
  await expect(page.getByRole('link', { name: 'Baixar instalador DMG' })).toHaveAttribute('href', '/api/v1/releases/3/files/4/Proser.dmg');
  expect(requests).not.toContain('/api/session');
  await page.setViewportSize({ width: 390, height: 844 });
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
});
test('public downloads show empty and failure states', async ({ page }) => {
  await page.route('**/api/v1/releases', route => route.fulfill({ json: { items: [] } }));
  await page.goto('/downloads');
  await expect(page.getByText('Nenhuma versão foi liberada para download ainda.')).toBeVisible();
  await page.route('**/api/v1/releases', route => route.fulfill({ status: 503, json: { error: 'Offline' } }));
  await page.reload();
  await expect(page.getByRole('alert')).toContainText('Não foi possível carregar as versões');
});
