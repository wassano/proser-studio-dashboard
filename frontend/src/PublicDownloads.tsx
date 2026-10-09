import { useEffect, useState } from 'react';
import { Download, Layers3 } from 'lucide-react';
import { api, apiUrl } from './api';

type PublicRelease = { id: number; version: string; target: string; notes: string; assets: { id: number; filename: string; size: number; sha256: string; download_path: string }[] };
const platforms: Record<string, string> = { 'win-x64': 'Windows 10/11 · x64', 'win7-x64': 'Windows 7 SP1 · x64', 'mac-arm64': 'macOS · Apple Silicon', 'mac-x64': 'macOS · Intel' };
export default function PublicDownloads() {
  const [items, setItems] = useState<PublicRelease[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  useEffect(() => {
    let disposed = false;
    api<{ items: PublicRelease[] }>('/api/v1/releases').then(data => { if (!disposed) setItems(data.items); })
      .catch(() => { if (!disposed) setError('Não foi possível carregar as versões. Recarregue a página para tentar novamente.'); })
      .finally(() => { if (!disposed) setLoading(false); });
    return () => { disposed = true; };
  }, []);
  return <main className="public-downloads"><header><a className="brand" href="/"><div className="brand-mark"><Layers3/></div><span>proser studio</span></a><a href="/">Administração</a></header>
    <p className="eyebrow">PROSER STUDIO</p><h1>Baixe o Proser studio</h1><p>Escolha a versão para o seu computador. O aplicativo solicita a liberação da instalação ao abrir.</p>
    {loading && <p role="status">Carregando versões…</p>}{error && <p role="alert" className="error">{error}</p>}
    {!loading && !error && !items.length && <p>Nenhuma versão foi liberada para download ainda.</p>}
    <div className="plan-grid">{items.map(item => <section className="panel plan" key={item.id}><h2>{platforms[item.target] || item.target}</h2><p>Versão {item.version}</p>{item.notes && <p className="release-notes">{item.notes}</p>}<ul className="public-assets">{item.assets.filter(asset => asset.filename.endsWith(item.target.startsWith('mac-') ? '.dmg' : '.exe')).map(asset => <li key={asset.id}><a className="primary login-button" href={apiUrl(asset.download_path)}><Download size={18}/>Baixar {asset.filename.endsWith('.dmg') ? 'instalador DMG' : 'instalador'}</a><small>{asset.filename} · {(asset.size / 1024 / 1024).toFixed(1)} MB</small><details><summary>Verificar integridade SHA-256</summary><code>{asset.sha256}</code></details></li>)}</ul></section>)}</div>
  </main>;
}
