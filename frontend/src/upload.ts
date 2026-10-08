import { api, ApiError } from './api';

// Parts and completion are idempotent on the server. Creation is not retried.
async function retryUpload<T>(action: () => Promise<T>): Promise<T> {
  for (let attempt = 0; ; attempt++) {
    try { return await action(); } catch (error) {
      const temporary = error instanceof TypeError || (error instanceof ApiError && [408, 429, 502, 503, 504].includes(error.status));
      if (!temporary || attempt >= 3) throw error;
      await new Promise(resolve => setTimeout(resolve, error instanceof ApiError && error.status === 429 ? 60_000 : 1_000 * 2 ** attempt));
    }
  }
}
export async function uploadInstaller(releaseId: number, file: File, progress: (percent: number) => void) {
  if (!file.size || file.size > 2 * 1024 ** 3) throw new Error('O arquivo deve ter entre 1 byte e 2 GiB.');
  const base = `/api/admin/releases/${releaseId}/uploads`;
  const session = await api<{ id: string; chunk_size: number }>(base, 'POST', { upload: { filename: file.name, total_bytes: file.size } });
  const path = `${base}/${session.id}`;
  try {
    if (session.chunk_size < 1 || session.chunk_size > 5 * 1024 ** 2) throw new Error('Tamanho de parte inválido.');
    for (let offset = 0; offset < file.size; offset += session.chunk_size) {
      const chunk = file.slice(offset, offset + session.chunk_size);
      await retryUpload(() => api(path, 'PUT', chunk, { 'X-Upload-Offset': String(offset) }));
      progress(Math.round(Math.min(file.size, offset + chunk.size) / file.size * 100));
    }
    await retryUpload(() => api(`${path}/complete`, 'POST', {}));
  } catch (error) {
    await api(path, 'DELETE').catch(() => {});
    throw error;
  }
}
