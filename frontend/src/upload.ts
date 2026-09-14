import { api } from './api';
export async function uploadInstaller(releaseId: number, file: File, progress: (percent: number) => void) {
  if (!file.size || file.size > 2 * 1024 ** 3) throw new Error('O arquivo deve ter entre 1 byte e 2 GiB.');
  const base = `/api/admin/releases/${releaseId}/uploads`;
  const session = await api<{ id: string; chunk_size: number }>(base, 'POST', { upload: { filename: file.name, total_bytes: file.size } });
  const path = `${base}/${session.id}`;
  try {
    if (session.chunk_size < 1 || session.chunk_size > 5 * 1024 ** 2) throw new Error('Tamanho de parte inválido.');
    for (let offset = 0; offset < file.size; offset += session.chunk_size) {
      const chunk = file.slice(offset, offset + session.chunk_size);
      await api(path, 'PUT', chunk, { 'X-Upload-Offset': String(offset) });
      progress(Math.round(Math.min(file.size, offset + chunk.size) / file.size * 100));
    }
    await api(`${path}/complete`, 'POST', {});
  } catch (error) {
    await api(path, 'DELETE').catch(() => {});
    throw error;
  }
}
