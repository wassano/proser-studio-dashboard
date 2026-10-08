import { isIP } from 'node:net';

const securityHeaders = {
  'Content-Security-Policy': "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; font-src 'self'; object-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'",
  'Strict-Transport-Security': 'max-age=31536000; includeSubDomains',
  'X-Content-Type-Options': 'nosniff', 'X-Frame-Options': 'DENY',
  'Referrer-Policy': 'no-referrer', 'Permissions-Policy': 'geolocation=(), camera=(), microphone=()',
};
function secured(response: Response, dynamic = true, apiOrigin = "https://api.proser.studio"): Response {
  const result = new Response(response.body, response);
  for (const [name, value] of Object.entries(securityHeaders)) result.headers.set(name, value);
  result.headers.set('Content-Security-Policy', securityHeaders['Content-Security-Policy'].replace("connect-src 'self'", `connect-src 'self' ${apiOrigin}`));
  if (dynamic) result.headers.set('Cache-Control', 'no-store');
  result.headers.delete('Server'); result.headers.delete('X-Powered-By');
  return result;
}
function error(status: number, message: string): Response {
  return secured(Response.json({ error: message }, { status }));
}
function configuration(env: Env) {
  const publicOrigin = new URL(env.PUBLIC_ORIGIN);
  const apiOrigin = new URL(env.API_ORIGIN);
  const origin = new URL(env.RAILS_ORIGIN);
  for (const value of [publicOrigin, apiOrigin, origin]) {
    if (value.protocol !== 'https:' || value.username || value.password || value.pathname !== '/' || value.search || value.hash) throw new Error('Invalid origin');
  }
  if (new Set([origin.origin, publicOrigin.origin, apiOrigin.origin]).size !== 3 || !/^[a-f0-9]{64}$/.test(env.ORIGIN_TOKEN)) throw new Error('Invalid configuration');
  return { publicOrigin, apiOrigin, origin };
}
function backendRequest(request: Request, env: Env, path?: string, maxBytes = 6 * 1024 * 1024) {
  const { apiOrigin, origin } = configuration(env);
  const incoming = new URL(request.url);
  const destination = new URL(origin);
  destination.pathname = path ?? incoming.pathname;
  destination.search = path ? '' : incoming.search;
  const headers = new Headers(request.headers);
  for (const name of [...headers.keys()]) {
    if (/^(?:host|forwarded|x-forwarded-.*|x-real-ip|client-ip|x-proser-edge-.*|cf-access-.*)$/i.test(name)) headers.delete(name);
  }
  headers.set('X-Proser-Edge-Token', env.ORIGIN_TOKEN);
  const ip = request.headers.get('CF-Connecting-IP') ?? '';
  if (!isIP(ip)) throw new Error('Missing trusted client address');
  headers.set('X-Proser-Edge-IP', ip);
  headers.set('X-Forwarded-Host', apiOrigin.host);
  headers.set('X-Forwarded-Proto', 'https');
  if (path) { headers.delete('Content-Length'); headers.delete('Content-Type'); }
  let bytes = 0;
  const body = path || ['GET', 'HEAD'].includes(request.method) ? undefined : request.body?.pipeThrough(new TransformStream<Uint8Array, Uint8Array>({
    transform(chunk, controller) {
      bytes += chunk.byteLength;
      if (bytes > maxBytes) { controller.error(new Error('Request exceeds limit')); return; }
      controller.enqueue(chunk);
    },
  }));
  return new Request(destination, {
    method: path ? 'GET' : request.method, headers,
    ...{ duplex: 'half' },
    body,
    redirect: 'manual', signal: AbortSignal.timeout(path ? 15000 : 600000),
  });
}
const methods = ['GET', 'HEAD', 'POST', 'PATCH', 'PUT', 'DELETE'];
const corsHeaders = ['accept', 'content-type', 'x-csrf-token', 'x-upload-offset'];

function cors(response: Response, request: Request, publicOrigin: string): Response {
  // Cosmos headers must never broaden the browser origins allowed by this API.
  const result = new Response(response.body, response);
  for (const key of [...result.headers.keys()]) if (key.toLowerCase().startsWith('access-control-')) result.headers.delete(key);
  result.headers.append('Vary', 'Origin');
  if (request.headers.get('Origin') === publicOrigin) {
    result.headers.set('Access-Control-Allow-Origin', publicOrigin);
    result.headers.set('Access-Control-Allow-Credentials', 'true');
    if (request.method === 'OPTIONS' && response.status === 204) {
      result.headers.set('Access-Control-Allow-Methods', methods.join(', '));
      result.headers.set('Access-Control-Allow-Headers', corsHeaders.join(', '));
      result.headers.set('Access-Control-Max-Age', '600');
    }
  }
  return result;
}

export async function handle(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const publicOrigin = new URL(env.PUBLIC_ORIGIN);
  const apiOrigin = new URL(env.API_ORIGIN);
  const local = ['localhost', '127.0.0.1'].includes(url.hostname);
  if (![publicOrigin.host, apiOrigin.host].includes(url.host) && !local) return error(421, 'Domínio inválido.');
  if (url.protocol !== 'https:' && !local) return Response.redirect(`https://${url.host}${url.pathname}${url.search}`, 308);
  const dynamic = url.pathname === '/up' || /^\/(api|auth)(\/|$)/.test(url.pathname);
  if (url.host === publicOrigin.host || (local && !dynamic)) {
    if (!['GET', 'HEAD'].includes(request.method)) return error(405, 'Método não permitido.');
    if (dynamic) return secured(Response.redirect(`${apiOrigin.origin}${url.pathname}${url.search}`, 308));
    const assetRequest = /^\/downloads\/?$/.test(url.pathname) ? new Request(new URL('/index.html', request.url), request) : request;
    return secured(await env.ASSETS.fetch(assetRequest), false, apiOrigin.origin);
  }
  const finish = (response: Response) => cors(secured(response, true, apiOrigin.origin), request, publicOrigin.origin);
  const browserOrigin = request.headers.get('Origin');
  if (browserOrigin && ![publicOrigin.origin, apiOrigin.origin].includes(browserOrigin)) return finish(error(403, 'Origem não autorizada.'));
  if (!dynamic) return finish(error(404, 'Rota não encontrada.'));
  if (request.method === 'OPTIONS') {
    const method = request.headers.get('Access-Control-Request-Method') ?? '';
    const headers = (request.headers.get('Access-Control-Request-Headers') ?? '').toLowerCase().split(',').map(value => value.trim()).filter(Boolean);
    if (browserOrigin !== publicOrigin.origin || !methods.includes(method) || headers.some(header => !corsHeaders.includes(header))) return finish(error(403, 'Preflight não autorizado.'));
    return finish(new Response(null, { status: 204 }));
  }
  try { configuration(env); } catch { return finish(error(503, 'O servidor do painel ainda não foi conectado.')); }
  if (!methods.includes(request.method)) return finish(error(405, 'Método não permitido.'));
  const ci = /^\/api\/ci\/releases(?:\/|$)/.test(url.pathname);
  if (ci && (browserOrigin || !/^Bearer [a-f0-9]{64}$/.test(request.headers.get('Authorization') ?? ''))) return finish(error(403, 'Credencial de CI inválida.'));
  const ciUpload = /^\/api\/ci\/releases\/\d+\/uploads(?:\/[^/]+(?:\/complete)?)?$/.test(url.pathname);
  const upload = /^\/api\/admin\/releases\/\d+\/(?:upload|uploads(?:\/[^/]+(?:\/complete)?)?)$/.test(url.pathname);
  const maxBytes = upload || ciUpload ? 6 * 1024 * 1024 : url.pathname.startsWith('/api/v1/installations/') ? 16384 : 65536;
  const length = request.headers.get('Content-Length');
  if (length && (!/^\d+$/.test(length) || Number(length) > maxBytes)) return finish(error(413, 'Requisição excede o limite permitido.'));
  if (!['GET', 'HEAD'].includes(request.method) && !url.pathname.startsWith('/api/v1/') && !ci) {
    if (browserOrigin !== publicOrigin.origin || !request.headers.get('X-CSRF-Token')) return finish(error(403, 'Origem ou token CSRF inválido.'));
  }
  try {
    if (upload && request.method !== 'GET') {
      const auth = await fetch(backendRequest(request, env, '/api/session'));
      if (!auth.ok) return finish(auth);
      await auth.body?.cancel();
    }
    const response = await fetch(backendRequest(request, env, undefined, maxBytes));
    const result = finish(response);
    const location = result.headers.get('Location');
    if (location) {
      const redirect = new URL(location, env.RAILS_ORIGIN);
      if (redirect.origin === new URL(env.RAILS_ORIGIN).origin) {
        result.headers.set('Location', `${apiOrigin.origin}${redirect.pathname}${redirect.search}${redirect.hash}`);
      }
    }
    return result;
  } catch {
    // Never log request URLs, cookies, OAuth callback secrets, or request bodies.
    console.error(JSON.stringify({ event: 'origin_unavailable' }));
    return finish(error(502, 'Não foi possível acessar o servidor do painel. Tente novamente.'));
  }
}
export default { fetch: handle } satisfies ExportedHandler<Env>;
