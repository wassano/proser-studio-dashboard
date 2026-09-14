import { test } from 'node:test';
import assert from 'node:assert/strict';
import { handle } from '../index.ts';
const origin = 'https://rails.example.test';
const env = { PUBLIC_ORIGIN: 'https://app.proser.studio', API_ORIGIN: 'https://api.proser.studio', RAILS_ORIGIN: origin, ORIGIN_TOKEN: 'a'.repeat(64), ASSETS: { fetch: async () => new Response('<html>dashboard</html>', { headers: { 'Content-Type': 'text/html' } }) } };
function request(path: string, options: RequestInit = {}) {
  const headers = new Headers(options.headers); headers.set('CF-Connecting-IP', '203.0.113.20');
  return new Request(`https://api.proser.studio${path}`, { ...options, headers });
}
test('serves frontend with security headers and rejects unknown host', async () => {
  const response = await handle(new Request(env.PUBLIC_ORIGIN + '/'), env);
  assert.equal(response.status, 200); assert.match(response.headers.get('Content-Security-Policy')!, /frame-ancestors 'none'/);
  assert.equal((await handle(new Request('https://evil.example/'), env)).status, 421);
});
test('missing backend fails closed without returning successful sessions', async () => {
  const response = await handle(request('/api/session'), { ...env, RAILS_ORIGIN: '' });
  assert.equal(response.status, 503); assert.equal(response.headers.get('Cache-Control'), 'no-store');
});
test('proxy preserves exact signed body and removes forged forwarding metadata', async t => {
  const bytes = '{ "value": 42 }';
  t.mock.method(globalThis, 'fetch', async (outgoing: Request) => {
    assert.equal(outgoing.url, `${origin}/api/v1/installations/register`);
    assert.equal(await outgoing.text(), bytes);
    assert.equal(outgoing.headers.get('X-Proser-Signature'), 'device-signature');
    assert.equal(outgoing.headers.get('X-Proser-Edge-IP'), '203.0.113.20');
    assert.equal(outgoing.headers.get('X-Proser-Edge-Token'), env.ORIGIN_TOKEN);
    assert.equal(outgoing.headers.get('Forwarded'), null);
    assert.equal(outgoing.headers.get('X-Forwarded-For'), null);
    assert.equal(outgoing.redirect, 'manual');
    return Response.json({ signed: true });
  });
  const response = await handle(request('/api/v1/installations/register', { method: 'POST', body: bytes, headers: { 'X-Proser-Signature': 'device-signature', 'X-Proser-Edge-IP': '127.0.0.1', 'X-Proser-Edge-Token': 'forged', 'X-Forwarded-For': '127.0.0.1', Forwarded: 'for=127.0.0.1' } }), env);
  assert.equal(response.status, 200);
});
test('OAuth callback remains a browser redirect and preserves secure cookies', async t => {
  t.mock.method(globalThis, 'fetch', async (outgoing: Request) => {
    assert.equal(new URL(outgoing.url).searchParams.get('state'), 'browser-state');
    assert.equal(outgoing.headers.get('Cookie'), '_proser_admin=browser-cookie');
    return new Response(null, { status: 302, headers: { Location: `${env.PUBLIC_ORIGIN}/`, 'Set-Cookie': '_proser_admin=new; Path=/; Secure; HttpOnly; SameSite=Lax' } });
  });
  const response = await handle(request('/auth/callback?state=browser-state', { headers: { Cookie: '_proser_admin=browser-cookie' } }), env);
  assert.equal(response.status, 302); assert.equal(response.headers.get('Location'), env.PUBLIC_ORIGIN + '/');
  assert.match(response.headers.get('Set-Cookie')!, /Secure; HttpOnly/);
});
test('foreign-origin mutations and oversized requests never reach Rails', async t => {
  const fetch = t.mock.method(globalThis, 'fetch', async () => { throw new Error('Must not contact backend'); });
  assert.equal((await handle(request('/api/admin/settings', { method: 'PATCH', headers: { Origin: 'https://evil.example', 'X-CSRF-Token': 'forged' }, body: '{}' }), env)).status, 403);
  assert.equal((await handle(request('/api/admin/releases/1/upload', { method: 'POST', headers: { 'Content-Length': '1000000000' } }), env)).status, 413);
  assert.equal(fetch.mock.callCount(), 0);
});
test('upload authentication happens before consuming the body', async t => {
  const fetch = t.mock.method(globalThis, 'fetch', async (outgoing: Request) => {
    assert.equal(outgoing.method, 'GET'); assert.equal(outgoing.url, `${origin}/api/session`);
    assert.equal(outgoing.body, null);
    return Response.json({ error: 'Entre com Google' }, { status: 401 });
  });
  const response = await handle(request('/api/admin/releases/1/uploads/id', { method: 'PUT', body: 'installer-chunk', headers: { Origin: env.PUBLIC_ORIGIN, 'X-CSRF-Token': 'csrf' } }), env);
  assert.equal(response.status, 401); assert.equal(fetch.mock.callCount(), 1);
});

test('API allows credentialed CORS only from the dashboard, including errors', async t => {
  t.mock.method(globalThis, 'fetch', async () => Response.json({ error: 'Login required' }, { status: 401, headers: { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': '*' } }));
  const allowed = await handle(request('/api/session', { headers: { Origin: env.PUBLIC_ORIGIN } }), env);
  assert.equal(allowed.status, 401);
  assert.equal(allowed.headers.get('Access-Control-Allow-Origin'), env.PUBLIC_ORIGIN);
  assert.equal(allowed.headers.get('Access-Control-Allow-Credentials'), 'true');
  assert.equal(allowed.headers.get('Access-Control-Allow-Headers'), null);
  assert.match(allowed.headers.get('Vary')!, /Origin/);
  const foreign = await handle(request('/api/session', { headers: { Origin: 'https://evil.proser.studio' } }), env);
  assert.equal(foreign.status, 403);
  assert.equal(foreign.headers.get('Access-Control-Allow-Origin'), null);
});
test('CORS preflight validates method and headers before contacting the backend', async t => {
  const fetch = t.mock.method(globalThis, 'fetch', async () => { throw new Error('No backend call expected'); });
  const headers = { Origin: env.PUBLIC_ORIGIN, 'Access-Control-Request-Method': 'PUT', 'Access-Control-Request-Headers': 'content-type,x-csrf-token,x-upload-offset' };
  const response = await handle(request('/api/admin/releases/1/uploads/id', { method: 'OPTIONS', headers }), env);
  assert.equal(response.status, 204);
  assert.equal(response.headers.get('Access-Control-Allow-Origin'), env.PUBLIC_ORIGIN);
  assert.equal(response.headers.get('Access-Control-Allow-Credentials'), 'true');
  assert.equal((await handle(request('/api/session', { method: 'OPTIONS', headers: { ...headers, 'Access-Control-Request-Headers': 'x-proser-edge-token' } }), env)).status, 403);
  assert.equal((await handle(request('/api/session', { method: 'OPTIONS', headers: { ...headers, Origin: 'null' } }), env)).status, 403);
  assert.equal(fetch.mock.callCount(), 0);
});
test('frontend and API hosts stay separate and CSP permits the API', async () => {
  assert.equal((await handle(request('/'), env)).status, 404);
  const response = await handle(new Request(env.PUBLIC_ORIGIN + '/'), env);
  assert.match(response.headers.get('Content-Security-Policy')!, /connect-src 'self' https:\/\/api\.proser\.studio/);
  const moved = await handle(new Request(env.PUBLIC_ORIGIN + '/auth/google'), env);
  assert.equal(moved.status, 308);
  assert.equal(moved.headers.get('Location'), env.API_ORIGIN + '/auth/google');
});
