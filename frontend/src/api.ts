// Cosmos serves the dashboard and its authenticated API on the same origin.
const apiOrigin = import.meta.env.VITE_API_ORIGIN ?? '';
export function apiUrl(path: string): string {
  if (!/^\/(api|auth)(\/|$)/.test(path) || path.includes('\\')) throw new Error('Rota de API inválida.');
  return `${apiOrigin}${path}`;
}
let csrf = '';
export function setCsrf(value: string) { csrf = value; }
export class ApiError extends Error { constructor(message: string, readonly status: number) { super(message); } }
export async function api<T>(path: string, method = 'GET', body?: unknown, extraHeaders: Record<string, string> = {}): Promise<T> {
  const multipart = body instanceof FormData;
  const binary = body instanceof Blob;
  const response = await fetch(apiUrl(path), {
    method, credentials: 'include', redirect: 'error',
    headers: { ...extraHeaders, Accept: 'application/json', ...(body && !multipart ? { 'Content-Type': binary ? 'application/octet-stream' : 'application/json' } : {}), ...(method !== 'GET' ? { 'X-CSRF-Token': csrf } : {}) },
    body: body ? multipart || binary ? body : JSON.stringify(body) : undefined,
  });
  if (response.status === 204) return undefined as T;
  const data = await response.json().catch(() => ({}));
  if (!response.ok) throw new ApiError(data.error || 'Não foi possível completar a operação.', response.status);
  return data;
}
