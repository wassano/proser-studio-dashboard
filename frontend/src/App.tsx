import { useCallback, useEffect, useRef, useState, type FormEvent, type ReactNode } from 'react';
import { Activity, ArrowUpRight, Check, ChevronLeft, ChevronRight, Download, KeyRound, Layers3, LogOut, Monitor, Plus, RefreshCw, Search, Settings2, ShieldCheck, SlidersHorizontal, X } from 'lucide-react';
import { uploadInstaller } from './upload';
import ReleaseList from './ReleaseList';
import { apiUrl, api, ApiError, setCsrf } from './api';
import { featureNames, limitNames, maximums, statusNames, type Installation, type License, type Page, type Plan, type Release, type Settings } from './types';

const date = (value?: string | null) => value ? new Intl.DateTimeFormat('pt-BR', { dateStyle: 'short', timeStyle: 'short' }).format(new Date(value)) : '—';
const emptyPage = <T,>(): Page<T> => ({ items: [], total: 0, page: 1 });
function Badge({ status }: { status: string }) { return <span className={`badge ${status}`}>{statusNames[status] || status}</span>; }
function Field({ label, children }: { label: string; children: ReactNode }) { return <label className="field"><span>{label}</span>{children}</label>; }
function Modal({ title, close, children }: { title: string; close: () => void; children: ReactNode }) {
  const dialog = useRef<HTMLDialogElement>(null);
  useEffect(() => { dialog.current?.showModal(); const node = dialog.current; return () => node?.close(); }, []);
  return <dialog ref={dialog} onCancel={close}><div className="modal-title"><h2>{title}</h2><button className="icon" aria-label="Fechar" onClick={close}><X size={20}/></button></div>{children}</dialog>;
}
function Pager({ page, total, change, labels = ['registro', 'registros'] }: { page: number; total: number; change: (page: number) => void; labels?: [string, string] }) {
  return <div className="pager"><span>{total} {labels[total === 1 ? 0 : 1]}</span><button disabled={page === 1} onClick={() => change(page - 1)} aria-label="Página anterior"><ChevronLeft size={16}/></button><span>Página {page}</span><button disabled={page * 100 >= total} onClick={() => change(page + 1)} aria-label="Próxima página"><ChevronRight size={16}/></button></div>;
}
type Tab = 'installations' | 'licenses' | 'plans' | 'releases';
export default function App() {
  const [email, setEmail] = useState<string | null | undefined>(undefined);
  const [tab, setTab] = useState<Tab>('installations');
  const [plans, setPlans] = useState<Plan[]>([]);
  const [settings, setSettings] = useState<Settings | null>(null);
  const [devices, setDevices] = useState<Page<Installation>>(emptyPage);
  const [licenses, setLicenses] = useState<Page<License>>(emptyPage);
  const [releases, setReleases] = useState<Page<Release>>(emptyPage);
  const [releasesLoaded, setReleasesLoaded] = useState(false);
  const [page, setPage] = useState(1);
  const [filter, setFilter] = useState('');
  const [query, setQuery] = useState('');
  const [search, setSearch] = useState('');
  const [loading, setLoading] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [modal, setModal] = useState<ReactNode>(null);
  const [editingPlan, setEditingPlan] = useState<Plan | null>(null);
  const [editingLicense, setEditingLicense] = useState<License | null>(null);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [newRelease, setNewRelease] = useState(false);
  const [assigning, setAssigning] = useState<Installation | null>(null);
  const fail = useCallback((reason: unknown) => {
    if (reason instanceof ApiError && reason.status === 401) { setEmail(null); setModal(null); }
    setNotice('');
    setError(reason instanceof TypeError ? 'A conexão foi interrompida. Verifique sua rede e tente enviar novamente.' : reason instanceof Error ? reason.message : 'Não foi possível completar a operação.');
  }, []);
  useEffect(() => {
    let disposed = false;
    api<{ email: string; csrf_token: string }>('/api/session').then(session => { if (!disposed) { setCsrf(session.csrf_token); setEmail(session.email); } }).catch(reason => { if (!disposed) { setEmail(null); if (!(reason instanceof ApiError && reason.status === 401)) fail(reason); } });
    return () => { disposed = true; };
  }, [fail]);
  const refresh = useCallback(async () => {
    if (!email) return;
    setLoading(true);
    try {
      const releaseRequest = tab === 'releases' ? api<Page<Release>>(`/api/admin/releases?page=${page}`).then(data => { setReleases(data); setReleasesLoaded(true); }) : Promise.resolve();
      const [planData, settingData] = await Promise.all([api<{ items: Plan[] }>('/api/admin/plans'), api<Settings>('/api/admin/settings'), releaseRequest]);
      setPlans(planData.items); setSettings(settingData);
      if (tab === 'installations') setDevices(await api<Page<Installation>>(`/api/admin/installations?page=${page}&status=${filter}&q=${encodeURIComponent(search)}`));
      if (tab === 'licenses') setLicenses(await api<Page<License>>(`/api/admin/licenses?page=${page}`));
    } catch (reason) { fail(reason); } finally { setLoading(false); }
  }, [email, tab, page, filter, search, fail]);
  useEffect(() => { void refresh(); }, [refresh]);
  useEffect(() => {
    if (!email || tab !== 'releases') return;
    let disposed = false;
    let inFlight = false;
    const updateReleases = () => {
      if (inFlight || document.visibilityState !== 'visible') return;
      inFlight = true;
      void api<Page<Release>>(`/api/admin/releases?page=${page}`).then(data => {
        if (!disposed) { setReleases(data); setReleasesLoaded(true); }
      }).catch(reason => { if (!disposed) fail(reason); }).finally(() => { inFlight = false; });
    };
    const interval = window.setInterval(updateReleases, 30000);
    window.addEventListener('focus', updateReleases);
    document.addEventListener('visibilitychange', updateReleases);
    return () => {
      disposed = true;
      window.clearInterval(interval);
      window.removeEventListener('focus', updateReleases);
      document.removeEventListener('visibilitychange', updateReleases);
    };
  }, [email, tab, page, fail]);
  async function mutate(action: () => Promise<unknown>, message: string) {
    setBusy(true); setError(''); setNotice('');
    try { await action(); setNotice(message); await refresh(); return true; } catch (reason) { fail(reason); return false; } finally { setBusy(false); }
  }
  function openTab(value: Tab) { setTab(value); setPage(1); setFilter(''); setSearch(''); setQuery(''); }
  async function approve(item: Installation) { await mutate(() => api(`/api/admin/installations/${item.id}/approve`, 'POST', {}), 'Instalação liberada. O aplicativo receberá a autorização na próxima consulta.'); }
  async function revoke(item: Installation) {
    if (window.confirm(`Revogar a instalação ${item.computer_name}? A autorização será retirada na próxima consulta ao servidor.`)) await mutate(() => api(`/api/admin/installations/${item.id}`, 'PATCH', { installation: { status: 'revoked' } }), 'Instalação revogada.');
  }
  async function upload(release: Release, file: File) {
    await mutate(() => uploadInstaller(release.id, file, percent => setNotice(percent === 100 ? 'Arquivo recebido. Verificando e armazenando…' : `Enviando instalador: ${percent}%`)), 'Instalador enviado e verificado. Publique a versão para distribuí-la.');
  }
  if (!email) return <main className="login"><div className="login-card"><div className="brand-mark"><Layers3/></div><p className="eyebrow">PROSER STUDIO</p><h1>Gestão do estúdio.</h1><p>Instalações, licenças e versões em um só lugar.</p>{email === undefined ? <p role="status">Verificando acesso…</p> : <a className="primary login-button" href={apiUrl("/auth/google")}><ShieldCheck size={19}/> Entrar com Google <ArrowUpRight size={17}/></a>}<small className="login-access-note">Acesso exclusivo aos administradores autorizados.</small><a className="login-download" href="/downloads"><Download size={18}/>Baixar o Proser studio</a>{error && <p role="alert" className="error">{error}</p>}{new URLSearchParams(location.search).has('login') && <p role="alert">O login não foi concluído. Tente novamente.</p>}</div><span className="login-footer">Proser studio · Administração</span></main>;
  const tabs: { id: Tab; label: string; icon: typeof Monitor }[] = [{ id: 'installations', label: 'Instalações', icon: Monitor }, { id: 'licenses', label: 'Licenças', icon: KeyRound }, { id: 'plans', label: 'Planos e recursos', icon: SlidersHorizontal }, { id: 'releases', label: 'Versões', icon: Download }];
  return <div className="shell"><aside><a className="brand" href="/"><div className="brand-mark"><Layers3 size={20}/></div><span>proser<span className="brand-light"> studio</span><small>PAINEL DE GESTÃO</small></span></a><nav aria-label="Gestão">{tabs.map(item => <button key={item.id} className={tab === item.id ? 'selected' : ''} onClick={() => openTab(item.id)}><item.icon size={19}/>{item.label}{tab === item.id && <span className="nav-dot"/>}</button>)}</nav><div className="sidebar-bottom"><span className="server-label"><span/> Servidor de licenças</span><span className="admin-email">{email}</span><button className="quiet" onClick={() => void mutate(async () => { await api('/api/session', 'DELETE'); setEmail(null); }, '')}><LogOut size={16}/>Sair</button></div></aside>
    <main className="workspace"><header><div><p className="eyebrow">ADMINISTRAÇÃO / PROSER STUDIO</p><h1>{tabs.find(item => item.id === tab)?.label}</h1></div><div className="actions"><button disabled={loading || busy} onClick={() => void refresh()}><RefreshCw size={16} className={loading ? 'spin' : ''}/>Atualizar</button>{tab === 'installations' && <button onClick={() => setSettingsOpen(true)}><Settings2 size={17}/>Admissão</button>}{tab === 'licenses' && <button className="primary" onClick={() => setEditingLicense({ id: 0, name: '', status: 'active', plan_id: plans[0]?.id || 0, plan_name: '', max_devices: 1, active_devices: 0, expires_at: null, minimum_version: '1.18.0', channel: 'stable', feature_overrides: {}, limit_overrides: {} })}><Plus size={17}/>Nova licença</button>}{tab === 'plans' && <button className="primary" onClick={() => setEditingPlan({ id: 0, name: '', features: Object.fromEntries(Object.keys(featureNames).map(key => [key, true])), limits: { ...maximums }, offline_hours: 24 })}><Plus size={17}/>Novo plano</button>}{tab === 'releases' && <button className="primary" onClick={() => setNewRelease(true)}><Plus size={17}/>Nova versão</button>}</div></header>
      {error && <div role="alert" className="message error">{error}<button className="icon" aria-label="Dispensar erro" onClick={() => setError('')}><X size={16}/></button></div>}{notice && <div role="status" className="message success"><Check size={17}/>{notice}</div>}
      {settings && <section className="stats" aria-label="Resumo de instalações"><div><span className="stat-label">Instalações liberadas</span><strong>{settings.active_installations}<small> / {settings.installation_limit}</small></strong><span>O limite é compartilhado por todos os planos.</span></div><div><span className="stat-label">Vagas disponíveis</span><strong>{Math.max(0, settings.installation_limit - settings.active_installations)}</strong><span>Novos registros são aprovados automaticamente.</span></div><div><span className="stat-label">Novos registros</span><strong className="stat-status"><span className={settings.registration_enabled ? 'dot-green' : 'dot-amber'}/>{settings.registration_enabled ? 'Abertos' : 'Pausados'}</strong><span>{settings.registration_enabled ? 'A admissão respeita o limite global.' : 'Instalações existentes mantêm suas licenças.'}</span></div></section>}
      {tab === 'installations' && <section className="panel"><div className="panel-toolbar"><form className="search" onSubmit={event => { event.preventDefault(); setPage(1); setSearch(query); }}><Search size={17}/><input aria-label="Buscar instalações" placeholder="Buscar por computador, IP ou identificação" value={query} onChange={event => setQuery(event.target.value)}/><button type="submit">Buscar</button></form><select aria-label="Status da instalação" value={filter} onChange={event => { setFilter(event.target.value); setPage(1); }}><option value="">Todos os status</option>{['active', 'pending', 'revoked', 'rejected'].map(status => <option key={status} value={status}>{statusNames[status]}</option>)}</select></div><div className="table-scroll"><table><thead><tr><th>Computador</th><th>Licença</th><th>Ativação</th><th>Último uso</th><th>IP e localização aproximada</th><th>Versão</th><th>Ações</th></tr></thead><tbody>{devices.items.map(item => <tr key={item.id}><td><strong className="computer"><Monitor size={16}/>{item.computer_name}</strong><small>{item.os} · {item.arch}</small><small title={item.device_id}>{item.device_id.slice(0, 12)}…</small></td><td><Badge status={item.access_status}/><small>{item.license?.plan_name || 'Sem licença'}</small></td><td>{date(item.activated_at)}</td><td>{date(item.last_seen_at)}</td><td><span className="mono">{item.last_ip || '—'}</span><small>{item.location || 'Localização indisponível'}</small></td><td><span className="version">{item.app_version}</span><small>{item.target}</small></td><td><div className="row-actions">{item.license && <button onClick={() => setEditingLicense(item.license)}>Licença</button>}<button onClick={() => setAssigning(item)}>Vincular</button>{item.status === 'active' ? <button className="danger-text" disabled={busy} onClick={() => void revoke(item)}>Revogar</button> : <button disabled={busy} onClick={() => void approve(item)}>Liberar</button>}</div></td></tr>)}</tbody></table>{!devices.items.length && <Empty icon={Monitor} title="Nenhuma instalação encontrada" text="Os computadores aparecerão aqui ao abrir o Proser conectado a este servidor."/>}</div><Pager page={page} total={devices.total} change={setPage}/></section>}
      {tab === 'licenses' && <section className="panel"><div className="table-scroll"><table><thead><tr><th>Licença</th><th>Plano</th><th>Status</th><th>Computadores</th><th>Validade</th><th>Versão mínima</th><th>Ações</th></tr></thead><tbody>{licenses.items.map(item => <tr key={item.id}><td><strong>{item.name}</strong><small>LIC-{String(item.id).padStart(5, '0')}</small></td><td>{item.plan_name}</td><td><Badge status={item.status}/></td><td>{item.active_devices} / {item.max_devices}</td><td>{item.expires_at ? date(item.expires_at) : 'Sem vencimento'}</td><td>{item.minimum_version}</td><td><button onClick={() => setEditingLicense(item)}>Editar licença</button></td></tr>)}</tbody></table>{!licenses.items.length && <Empty icon={KeyRound} title="Nenhuma licença cadastrada" text="Uma licença é criada automaticamente para cada instalação aprovada."/>}</div><Pager page={page} total={licenses.total} change={setPage}/></section>}
      {tab === 'plans' && <div className="plan-grid">{plans.map(plan => <section className="panel plan" key={plan.id}><div className="plan-heading"><div><span className="eyebrow">PLANO</span><h2>{plan.name}</h2></div><button onClick={() => setEditingPlan(plan)}>Editar</button></div><div className="plan-limits">{Object.entries(plan.limits).map(([key, value]) => <div key={key}><strong>{value}</strong><span>{limitNames[key]}</span></div>)}</div><ul className="features">{Object.entries(plan.features).map(([key, enabled]) => <li key={key} className={!enabled ? 'disabled-feature' : ''}>{enabled ? <Check size={16}/> : <X size={16}/>} {featureNames[key]}</li>)}</ul><footer><Activity size={15}/>Até {plan.offline_hours} horas sem conexão</footer></section>)}</div>}
      {tab === 'releases' && <section className="panel"><div className="panel-heading"><h2>Distribuição do aplicativo</h2><a href="/downloads" target="_blank" rel="noreferrer">Página pública de downloads</a><p>As versões enviadas pelo CI aparecem automaticamente como rascunho. Clique em Publicar para liberar o download e a atualização do aplicativo.</p></div>{!releasesLoaded && <p className="release-loading" role="status">Carregando versões…</p>}<ReleaseList items={releases.items} busy={busy} upload={upload}
        publish={item => mutate(() => api(`/api/admin/releases/${item.id}/publish`, 'POST', {}), 'Versão publicada. Os aplicativos consultarão a atualização automaticamente.')}
        withdraw={item => { if (window.confirm('Retirar esta versão de distribuição?')) void mutate(() => api(`/api/admin/releases/${item.id}/withdraw`, 'POST', {}), 'Versão retirada de distribuição.'); }}
        copyLink={path => mutate(() => navigator.clipboard.writeText(new URL(apiUrl(path), location.origin).href), 'Link público copiado.')}
      />{releasesLoaded && !releases.items.length && <Empty icon={Download} title="A primeira versão começa aqui" text="Crie uma versão para Windows, Windows 7 ou macOS e envie os arquivos gerados pelo build."/>}<Pager page={page} total={releases.total} change={setPage} labels={['versão', 'versões']}/></section>}
      <footer className="workspace-footer"><ShieldCheck size={15}/> Ações administrativas registradas em auditoria.<button className="quiet" onClick={async () => { try { const data = await api<Page<{ id: number; action: string; actor: string; created_at: string; subject: string }>>('/api/admin/audit'); setModal(<Modal title="Últimas ações" close={() => setModal(null)}><div className="audit-list">{data.items.map(item => <p key={item.id}><strong>{item.action} · {item.subject}</strong><small>{item.actor} · {date(item.created_at)}</small></p>)}</div></Modal>); } catch (reason) { fail(reason); } }}>Ver registros</button></footer>
    </main>
    {settingsOpen && settings && <SettingsEditor value={settings} plans={plans} busy={busy} close={() => setSettingsOpen(false)} save={async value => { if (await mutate(() => api('/api/admin/settings', 'PATCH', { settings: value }), 'Configuração de admissão salva.')) setSettingsOpen(false); }}/>}
    {editingPlan && <PlanEditor value={editingPlan} busy={busy} close={() => setEditingPlan(null)} save={async value => { if (await mutate(() => api(`/api/admin/plans${value.id ? `/${value.id}` : ''}`, value.id ? 'PATCH' : 'POST', { plan: value }), 'Plano salvo. As instalações receberão as regras na próxima consulta.')) setEditingPlan(null); }}/>}
    {editingLicense && <LicenseEditor value={editingLicense} plans={plans} busy={busy} close={() => setEditingLicense(null)} save={async value => { if (await mutate(() => api(`/api/admin/licenses${value.id ? `/${value.id}` : ''}`, value.id ? 'PATCH' : 'POST', { license: value }), 'Licença salva.')) setEditingLicense(null); }}/>}
    {newRelease && <ReleaseEditor busy={busy} close={() => setNewRelease(false)} save={async value => { if (await mutate(() => api('/api/admin/releases', 'POST', { release: value }), 'Rascunho criado. Envie o instalador correspondente.')) setNewRelease(false); }}/>}
    {assigning && <LicenseAssignment installation={assigning} busy={busy} close={() => setAssigning(null)} save={async licenseId => { if (await mutate(() => api(`/api/admin/installations/${assigning.id}/approve`, 'POST', { license_id: licenseId }), 'Instalação vinculada à licença e liberada.')) setAssigning(null); }}/> }{modal}{busy && <div className="working" role="status"><RefreshCw size={16} className="spin"/>Processando…</div>}
  </div>;
}
function Empty({ icon: Icon, title, text }: { icon: typeof Monitor; title: string; text: string }) { return <div className="empty"><Icon size={30}/><h3>{title}</h3><p>{text}</p></div>; }
function LicenseAssignment({ installation, busy, close, save }: { installation: Installation; busy: boolean; close: () => void; save: (id: number) => Promise<void> }) {
  const [result, setResult] = useState<Page<License>>(emptyPage);
  const [query, setQuery] = useState('');
  const [search, setSearch] = useState('');
  const [page, setPage] = useState(1);
  const [selected, setSelected] = useState('');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  useEffect(() => {
    let disposed = false;
    setLoading(true); setError(''); setSelected('');
    api<Page<License>>(`/api/admin/licenses?page=${page}&q=${encodeURIComponent(search)}`)
      .then(value => { if (!disposed) setResult(value); })
      .catch(reason => { if (!disposed) setError(reason instanceof Error ? reason.message : 'Não foi possível carregar as licenças.'); })
      .finally(() => { if (!disposed) setLoading(false); });
    return () => { disposed = true; };
  }, [page, search]);
  return <Modal title={`Vincular ${installation.computer_name}`} close={close}>
    <p>Escolha uma licença para este computador. A liberação respeita o limite global e as vagas da licença.</p>
    <form onSubmit={event => { event.preventDefault(); setPage(1); setSearch(query); }} className="search"><input aria-label="Buscar licença pelo nome" value={query} onChange={event => setQuery(event.target.value)}/><button>Buscar</button></form>
    {error && <p role="alert" className="error">{error}</p>}
    <form onSubmit={event => { event.preventDefault(); void save(Number(selected)); }}>
      <Field label="Licença de destino"><select required disabled={loading} value={selected} onChange={event => setSelected(event.target.value)}><option value="">{loading ? 'Carregando…' : 'Selecione uma licença'}</option>{result.items.map(item => <option key={item.id} value={item.id} disabled={item.status !== 'active' || Boolean(item.expires_at && Date.parse(item.expires_at) <= Date.now()) || (item.id !== installation.license?.id && item.active_devices >= item.max_devices)}>{item.name} · {item.plan_name} · {item.active_devices}/{item.max_devices}</option>)}</select></Field>
      <button className="primary" disabled={busy || loading || !selected || Boolean(error)}>Vincular e liberar</button>
    </form>
    <Pager page={page} total={result.total} change={setPage}/>
  </Modal>;
}
function Controls({ features, limits, changeFeatures, changeLimits }: { features: Record<string, boolean>; limits: Record<string, number>; changeFeatures: (v: Record<string, boolean>) => void; changeLimits: (v: Record<string, number>) => void }) {
  return <><h3>Recursos disponíveis</h3><div className="checkbox-grid">{Object.keys(featureNames).map(key => <label key={key}><input type="checkbox" checked={features[key] === true} onChange={e => changeFeatures({ ...features, [key]: e.target.checked })}/>{featureNames[key]}</label>)}</div><h3>Quantidade máxima por projeto</h3><div className="form-grid">{Object.keys(limitNames).map(key => <Field key={key} label={limitNames[key]}><input type="number" required min={0} max={maximums[key]} value={limits[key] ?? 0} onChange={e => changeLimits({ ...limits, [key]: e.target.valueAsNumber })}/></Field>)}</div></>;
}
function PlanEditor({ value, close, save, busy }: { value: Plan; close: () => void; save: (v: Plan) => Promise<void>; busy: boolean }) {
  const [draft, set] = useState(value);
  return <Modal title={value.id ? `Editar ${value.name}` : 'Novo plano'} close={close}><form onSubmit={e => { e.preventDefault(); void save(draft); }}><Field label="Nome do plano"><input required maxLength={100} value={draft.name} onChange={e => set({ ...draft, name: e.target.value })}/></Field><Controls features={draft.features} limits={draft.limits} changeFeatures={features => set({ ...draft, features })} changeLimits={limits => set({ ...draft, limits })}/><Field label="Validade offline (horas)"><input type="number" required min={1} max={168} value={draft.offline_hours} onChange={e => set({ ...draft, offline_hours: e.target.valueAsNumber })}/></Field><p className="help">Uma revogação será recebida na próxima consulta. Sem internet, a autorização anterior pode durar até esse prazo.</p><button className="primary" disabled={busy}>Salvar plano</button></form></Modal>;
}
function SettingsEditor({ value, plans, close, save, busy }: { value: Settings; plans: Plan[]; close: () => void; save: (v: Partial<Settings>) => Promise<void>; busy: boolean }) {
  const [draft, set] = useState(value);
  return <Modal title="Admissão de instalações" close={close}><form onSubmit={e => { e.preventDefault(); void save({ installation_limit: draft.installation_limit, registration_enabled: draft.registration_enabled, plan_id: draft.plan_id }); }}><Field label="Limite global de instalações"><input required type="number" min={0} max={100000} value={draft.installation_limit} onChange={e => set({ ...draft, installation_limit: e.target.valueAsNumber })}/></Field><Field label="Plano de novas instalações"><select value={draft.plan_id} onChange={e => set({ ...draft, plan_id: Number(e.target.value) })}>{plans.map(plan => <option key={plan.id} value={plan.id}>{plan.name}</option>)}</select></Field><label className="checkbox"><input type="checkbox" checked={draft.registration_enabled} onChange={e => set({ ...draft, registration_enabled: e.target.checked })}/>Liberar novos registros automaticamente</label><p className="help">Ao atingir o limite, novos computadores aguardam liberação. Reduzir o limite não revoga instalações existentes.</p><button className="primary" disabled={busy}>Salvar admissão</button></form></Modal>;
}
function LicenseEditor({ value, plans, close, save, busy }: { value: License; plans: Plan[]; close: () => void; save: (v: License) => Promise<void>; busy: boolean }) {
  const [draft, set] = useState(value);
  const [custom, setCustom] = useState(Object.keys(value.feature_overrides).length > 0 || Object.keys(value.limit_overrides).length > 0);
  const plan = plans.find(item => item.id === draft.plan_id);
  return <Modal title={value.id ? 'Editar licença' : 'Nova licença'} close={close}><form onSubmit={e => { e.preventDefault(); void save({ ...draft, feature_overrides: custom ? draft.feature_overrides : {}, limit_overrides: custom ? draft.limit_overrides : {} }); }}><Field label="Nome da licença"><input required maxLength={120} value={draft.name} onChange={e => set({ ...draft, name: e.target.value })}/></Field><div className="form-grid"><Field label="Plano"><select required value={draft.plan_id} onChange={e => set({ ...draft, plan_id: Number(e.target.value) })}>{plans.map(plan => <option key={plan.id} value={plan.id}>{plan.name}</option>)}</select></Field><Field label="Status"><select value={draft.status} onChange={e => set({ ...draft, status: e.target.value })}>{['active', 'suspended', 'revoked'].map(status => <option key={status} value={status}>{statusNames[status]}</option>)}</select></Field><Field label="Máximo de computadores"><input required type="number" min={1} max={1000} value={draft.max_devices} onChange={e => set({ ...draft, max_devices: e.target.valueAsNumber })}/></Field><Field label="Vencimento (opcional)"><input type="date" value={draft.expires_at?.slice(0, 10) || ''} onChange={e => set({ ...draft, expires_at: e.target.value ? `${e.target.value}T23:59:59-03:00` : null })}/></Field><Field label="Versão mínima"><input required pattern="[0-9]+\.[0-9]+\.[0-9]+" value={draft.minimum_version} onChange={e => set({ ...draft, minimum_version: e.target.value })}/></Field><Field label="Canal de atualizações"><select value={draft.channel} onChange={e => set({ ...draft, channel: e.target.value })}><option value="stable">Estável</option><option value="beta">Beta</option></select></Field></div><label className="checkbox"><input type="checkbox" checked={custom} onChange={e => { setCustom(e.target.checked); if (e.target.checked) set({ ...draft, feature_overrides: { ...plan?.features, ...draft.feature_overrides }, limit_overrides: { ...plan?.limits, ...draft.limit_overrides } }); }}/>Personalizar os recursos desta licença</label>{custom && <Controls features={{ ...plan?.features, ...draft.feature_overrides }} limits={{ ...plan?.limits, ...draft.limit_overrides }} changeFeatures={feature_overrides => set({ ...draft, feature_overrides })} changeLimits={limit_overrides => set({ ...draft, limit_overrides })}/>}<button className="primary" disabled={busy}>Salvar licença</button></form></Modal>;
}
function ReleaseEditor({ close, save, busy }: { close: () => void; save: (v: unknown) => Promise<void>; busy: boolean }) {
  const [draft, set] = useState({ version: '', target: 'win-x64', channel: 'stable', notes: '' });
  return <Modal title="Nova versão" close={close}><form onSubmit={(e: FormEvent) => { e.preventDefault(); void save(draft); }}><Field label="Número da versão"><input required placeholder="1.19.0" pattern="[0-9]+\.[0-9]+\.[0-9]+" value={draft.version} onChange={e => set({ ...draft, version: e.target.value })}/></Field><div className="form-grid"><Field label="Plataforma"><select value={draft.target} onChange={e => set({ ...draft, target: e.target.value })}><option value="win-x64">Windows 10/11 · x64</option><option value="win7-x64">Windows 7 · x64</option><option value="mac-arm64">macOS · Apple Silicon</option><option value="mac-x64">macOS · Intel</option></select></Field><Field label="Canal"><select value={draft.channel} onChange={e => set({ ...draft, channel: e.target.value })}><option value="stable">Estável</option><option value="beta">Beta</option></select></Field></div><Field label="Novidades desta versão"><textarea maxLength={10000} rows={5} value={draft.notes} onChange={e => set({ ...draft, notes: e.target.value })}/></Field><p className="help">Envie o .exe do NSIS para Windows ou o .zip assinado para macOS. O .dmg pode ser armazenado como arquivo adicional.</p><button className="primary" disabled={busy}>Criar rascunho</button></form></Modal>;
}
