import { readFile } from 'node:fs/promises';
const config = JSON.parse(await readFile(new URL('../wrangler.jsonc', import.meta.url), 'utf8'));
const publicOrigin = new URL(config.vars.PUBLIC_ORIGIN);
if (!config.vars.RAILS_ORIGIN) throw new Error('Configure RAILS_ORIGIN em wrangler.jsonc com a URL HTTPS do Rails antes de publicar.');
const api = new URL(config.vars.API_ORIGIN);
if (api.protocol !== "https:" || api.username || api.password || api.pathname !== "/" || api.search || api.hash || api.origin === publicOrigin.origin) throw new Error("API_ORIGIN deve ser uma origem HTTPS distinta do painel.");
const origin = new URL(config.vars.RAILS_ORIGIN);
if (origin.protocol !== 'https:' || origin.username || origin.password || origin.pathname !== '/' || origin.search || origin.hash || [publicOrigin.origin, api.origin].includes(origin.origin)) throw new Error('RAILS_ORIGIN deve ser uma origem HTTPS externa, sem caminho ou credenciais.');
console.log('Origem Rails configurada. O Worker exige ORIGIN_TOKEN como secret da Cloudflare.');
