import { Download, Upload } from 'lucide-react';
import { apiUrl } from './api';
import { statusNames, type Release } from './types';

const platforms: Record<string, string> = {
  'win-x64': 'Windows 10/11 · x64',
  'win7-x64': 'Windows 7 SP1 · x64',
  'mac-arm64': 'macOS · Apple Silicon',
  'mac-x64': 'macOS · Intel',
};
const platformOrder = Object.keys(platforms);
const date = (value: string) => new Intl.DateTimeFormat('pt-BR', { dateStyle: 'short', timeStyle: 'short' }).format(new Date(value));
type Props = {
  items: Release[];
  busy: boolean;
  upload: (release: Release, file: File) => Promise<unknown>;
  publish: (release: Release) => Promise<unknown>;
  withdraw: (release: Release) => void;
  copyLink: (path: string) => Promise<unknown>;
};

export default function ReleaseList({ items, busy, upload, publish, withdraw, copyLink }: Props) {
  const groups = new Map<string, Release[]>();
  for (const item of items) {
    const group = groups.get(item.version) ?? [];
    group.push(item);
    groups.set(item.version, group);
  }
  const versions = [...groups.keys()].sort((a, b) => b.localeCompare(a, undefined, { numeric: true }));
  return <>{versions.map(version => {
    const releases = groups.get(version)!.sort((a, b) => platformOrder.indexOf(a.target) - platformOrder.indexOf(b.target) || a.channel.localeCompare(b.channel));
    const platformCount = new Set(releases.map(item => item.target)).size;
    const fileCount = releases.reduce((count, item) => count + item.release_assets.length, 0);
    return <section className="release-group" aria-label={`Versão ${version}`} key={version}>
      <div className="release-group-heading">
        <div className="release-icon"><Download size={20}/></div>
        <div><h3>{version}</h3><p>{platformCount} {platformCount === 1 ? 'plataforma' : 'plataformas'} · {fileCount} {fileCount === 1 ? 'arquivo' : 'arquivos'}</p></div>
      </div>
      {releases.map(item => <article className="release" aria-label={`${platforms[item.target] || item.target} · ${item.channel === 'stable' ? 'Estável' : 'Beta'}`} key={item.id}>
        <div className="release-top">
          <div>
            <h4>{platforms[item.target] || item.target} <span className={`badge ${item.status}`}>{statusNames[item.status] || item.status}</span></h4>
            <p>{item.channel === 'stable' ? 'Estável' : 'Beta'} · {item.published_at ? date(item.published_at) : 'Ainda não publicada'}</p>
          </div>
          <div className="actions">
            {item.status === 'draft' && <>
              <label className={`upload-button ${busy ? 'disabled' : ''}`}><Upload size={16}/>Enviar arquivo
                <input disabled={busy} type="file" accept=".exe,.zip,.dmg,.blockmap" aria-label={`Enviar arquivo da versão ${item.version} ${item.target}`} onChange={event => {
                  const file = event.target.files?.[0];
                  if (file) void upload(item, file);
                  event.target.value = '';
                }}/>
              </label>
              <button disabled={busy || !item.release_assets.length || Boolean(item.ci_run_url && !item.ci_ready)} className="primary" onClick={() => void publish(item)}>Publicar</button>
            </>}
            {item.status === 'published' && <button disabled={busy} className="danger-text" onClick={() => withdraw(item)}>Retirar</button>}
          </div>
        </div>
        {item.ci_run_url && <p><a href={item.ci_run_url} target="_blank" rel="noreferrer">Build no GitHub Actions</a> · {item.ci_ready ? 'Arquivos verificados. Pronta para liberação manual.' : 'Recebendo arquivos do CI…'}</p>}
        {item.notes && <p className="release-notes">{item.notes}</p>}
        <ul className="asset-list">{item.release_assets.map(asset => <li key={asset.id}>
          <span>{asset.filename}</span>
          <a className="asset-download" aria-label={`Baixar ${asset.filename}`} href={apiUrl(`/api/admin/releases/${item.id}/files/${asset.id}/${encodeURIComponent(asset.filename)}`)}><Download size={15}/>Baixar</a>
          {item.status === 'published' && <button onClick={() => void copyLink(`/api/v1/releases/${item.id}/files/${asset.id}/${encodeURIComponent(asset.filename)}`)}>Copiar link público</button>}
          <small>{(asset.size / 1024 / 1024).toFixed(1)} MB</small><code title={asset.sha256}>SHA-256 {asset.sha256.slice(0, 16)}…</code>
        </li>)}</ul>
      </article>)}
    </section>;
  })}</>;
}
