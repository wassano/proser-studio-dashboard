import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';
import ts from 'typescript';

class ApiError extends Error {
  constructor(message, status) { super(message); this.status = status; }
}
async function load(api) {
  const source = await readFile(new URL('../src/upload.ts', import.meta.url), 'utf8');
  const context = vm.createContext({ TypeError, Error, Promise, setTimeout: callback => callback() });
  const dependency = new vm.SyntheticModule(['api', 'ApiError'], function () {
    this.setExport('api', api); this.setExport('ApiError', ApiError);
  }, { context });
  const module = new vm.SourceTextModule(ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText, { context });
  await module.link(() => dependency); await module.evaluate();
  return module.namespace.uploadInstaller;
}
const file = () => Object.assign(new Blob(['MZ123456']), { name: 'Proser.exe' });

test('lost part and completion responses retry idempotently with the same offset', async () => {
  const offsets = []; let completions = 0; const progress = [];
  const upload = await load(async (path, method, body, headers) => {
    if (path.endsWith('/uploads')) return { id: 'upload', chunk_size: 4 };
    if (method === 'PUT') {
      offsets.push(headers['X-Upload-Offset']);
      if (offsets.length === 1) throw new TypeError('Failed to fetch');
    } else if (path.endsWith('/complete')) {
      if (++completions === 1) throw new ApiError('Temporary gateway failure', 502);
    } else assert.fail('Successful upload must not be deleted');
  });
  await upload(1, file(), n => progress.push(n));
  assert.deepEqual(offsets, ['0', '0', '4']); assert.equal(completions, 2);
  assert.deepEqual(progress, [50, 100]);
});
test('authorization failures stop immediately and clean up the incomplete upload', async () => {
  const methods = [];
  const upload = await load(async (path, method) => {
    methods.push(method);
    if (path.endsWith('/uploads')) return { id: 'upload', chunk_size: 4 };
    if (method === 'PUT') throw new ApiError('Forbidden', 403);
  });
  await assert.rejects(upload(1, file(), () => {}), /Forbidden/);
  assert.deepEqual(methods, ['POST', 'PUT', 'DELETE']);
});
test('network retries are bounded and never recreate the upload session', async () => {
  const methods = [];
  const upload = await load(async (path, method) => {
    methods.push(method);
    if (path.endsWith('/uploads')) return { id: 'upload', chunk_size: 4 };
    if (method === 'PUT') throw new TypeError('offline');
  });
  await assert.rejects(upload(1, file(), () => {}), /offline/);
  assert.deepEqual(methods, ['POST', 'PUT', 'PUT', 'PUT', 'PUT', 'DELETE']);
});
