# Proser studio dashboard

Painel React + Rails 8.1 para instalações, licenças, planos e versões. PostgreSQL mantém as regras transacionais; Appwrite self-hosted autentica o administrador com Google e armazena os instaladores em bucket privado.

## Comportamento inicial

- Administrador autorizado: **dwassano@gmail.com**.
- Painel: **https://app.proser.studio**. API pública: **https://api.proser.studio**. Origem Cosmos: **https://proser.wassano.com**. Appwrite: **https://appwrite.wassano.com/v1**.
- **20 instalações liberadas**, limite global editável em **Instalações → Admissão**.
- A primeira abertura do Proser registra o computador automaticamente. Havendo vaga, recebe uma licença Studio sem vencimento cadastrado. A licença pode depois receber prazo, suspensão, revogação ou outro plano pelo painel.
- Sem conexão no primeiro registro, com registro recusado ou com limite geral atingido, o aplicativo fica bloqueado. Registros excedentes ficam pendentes: libere-os no painel após aumentar o limite ou revogar outra instalação. Pausar a admissão não revoga instalações existentes.
- O limite global conta instalações com status `active`, inclusive se sua licença estiver suspensa ou vencida. Revogar a instalação libera a vaga. Reduzir o limite não remove instalações automaticamente.
- Após ativação, o aplicativo consulta o backend a cada **5 minutos**. O plano inicial permite **24 horas offline**, configuráveis de 1 a 168 horas. Uma recusa assinada é aplicada assim que recebida; em falta de rede, vale a última autorização até expirar. Dados do projeto são preservados.
- A tabela mostra computador, SO, arquitetura, versão, ativação, último contato, IP observado no servidor e localização aproximada por GeoIP. “Último uso” representa o último contato enquanto o aplicativo estava aberto, não prova de operação física.
- Para compartilhar uma licença entre computadores, crie-a em **Licenças**, configure o máximo de computadores e use **Instalações → Vincular**. A operação valida as vagas globais e da licença antes de liberar o computador.

## Execução local

Requisitos: Ruby >= 3.2 (imagem de produção: Ruby 3.3), Node >= 22.13, Bundler. SQLite é usado apenas no desenvolvimento/teste local; produção usa PostgreSQL.

```sh
cd proser-studio-dashboard
bundle config set --local path vendor/bundle
bundle install
bundle exec rails db:prepare db:seed
npm --prefix frontend ci
VITE_API_ORIGIN=http://localhost:3000 npm --prefix frontend run build
DASHBOARD_URL=http://localhost:3000 bundle exec rails server -b 127.0.0.1 -p 3000
```

Em desenvolvimento, o Rails pode servir o React com `VITE_API_ORIGIN=http://localhost:3000 npm --prefix frontend run build` e `DASHBOARD_URL=http://localhost:3000`. Para editar o frontend, execute `npm --prefix frontend run dev` em outro terminal; Vite usa a porta 5174 e encaminha `/api` e `/auth` ao Rails. Configure `DASHBOARD_URL` com a origem da qual inicia o login e adicione esse hostname à plataforma Web no Appwrite.

Não existe rota de login de teste, senha administrativa padrão nem administrador criado por cadastro público. Sem configurar Google/Appwrite, somente a tela de entrada funciona; os testes simulam esses provedores de forma isolada.

## Configurar Appwrite e Google

As chaves de serviço, o bucket e as plataformas Web dos dois hosts estão cadastrados. O provedor Google está configurado no Appwrite. O login real de `dwassano@gmail.com` foi validado em 14/09/2026, com retorno ao painel autenticado.

Siga [appwrite/README.md](appwrite/README.md) para instalar a distribuição oficial self-hosted e configurar projeto, plataforma Web, Google e API keys.

O Google Client Secret fica no Appwrite. As chaves de serviço do Appwrite ficam somente no Rails. O React recebe apenas a sessão do próprio painel por cookie HTTP-only; nunca recebe credenciais Appwrite, Google ou a chave de assinatura das licenças.

O fluxo SSR do Appwrite usa `createOAuth2Token` → `createSession`. Como esse fluxo não garante o provedor no objeto da sessão, o Rails consulta a identidade Google vinculada e valida seu token diretamente no endpoint UserInfo do Google, exigindo e-mail verificado, identidade correspondente e allowlist.

## Publicação com Cloudflare Worker

O Worker publicado serve o React em **app.proser.studio** e encaminha `/api`, `/auth` e `/up` de **api.proser.studio** ao Rails em **proser.wassano.com**. O frontend usa CORS com credenciais e o cookie administrativo permanece restrito ao host da API. Consulte [CLOUDFLARE.md](CLOUDFLARE.md) para configurar a origem, proteção do backend e publicação. Rails, PostgreSQL, Redis e Appwrite continuam no servidor externo.

## Publicar o backend self-hosted

O Compose é preparado para **Cosmos Cloud**, sem qualquer porta publicada no host. O container `proser-studio-dashboard` atende HTTP na porta interna **3000**. PostgreSQL e Redis ficam em uma rede Docker interna. Consulte [COSMOS.md](COSMOS.md) para os comandos de instalação e criação da rota.

1. Execute `ruby bin/setup-secrets` para criar `.env` e o par Ed25519. O comando não sobrescreve arquivos existentes nem exibe segredos.
2. Configure as chaves Appwrite em `.env`. A instância existente usa `https://appwrite.wassano.com/v1`, projeto `proser`.
3. Em Linux, deixe `secrets/license-private.pem` com proprietário `10001:10001` e modo `0400`. O `.env` deve continuar com modo `0600`, legível apenas pelo usuário de deploy.
4. Opcionalmente coloque a base licenciada **GeoLite2-City.mmdb** em `geoip/`. Sem ela, a localização aparece indisponível. Nenhum IP é enviado a serviços externos de geolocalização.
5. Construa a imagem e prepare o banco:

```sh
docker compose build web
docker compose up -d postgres redis
docker compose run --rm web bundle exec rails db:prepare db:seed
docker compose run --rm web bundle exec rails proser:provision_storage
docker compose up -d web
```

O Cosmos termina HTTPS. Quando usado com o Worker, use a rota de origem `proser.wassano.com`, diferente dos hosts públicos do Worker; o Worker autentica o encaminhamento com `WORKER_ORIGIN_TOKEN`. Pedidos diretos sem o segredo recebem 403. Rails recusa iniciar com configuração de produção incompleta. O processo roda sem root, sem capabilities e com filesystem somente leitura, exceto temporários.

Programe `docker compose run --rm web bundle exec rails proser:prune` periodicamente para remover nonces, sessões e grants expirados. Auditoria é retida por 180 dias por padrão (`AUDIT_RETENTION_DAYS`). Faça backup do PostgreSQL, uploads Appwrite e chaves; valide a restauração. Não inclua chaves privadas em imagens, Git, frontend ou instaladores.

## Configurar os instaladores do Proser

Na raiz do aplicativo, no repositório vizinho `../dmx`, configure **somente a URL e a chave pública**:

```sh
export PROSER_LICENSE_URL=https://api.proser.studio
export PROSER_LICENSE_PUBLIC_KEY_PATH=/caminho/seguro/license-public.pem
export PROSER_LICENSE_KEY_ID=primary
```

Para rotação, `PROSER_LICENSE_KEYS_PATH` aceita um JSON com pares `kid: PEM público`; distribua primeiro uma versão que confie na nova chave, depois troque a chave de assinatura do backend. Não troque a chave privada sem planejar clientes offline e versões antigas.

`npm run build` continua permitindo desenvolvimento local sem licença. **Empacotamento exige URL HTTPS, chave pública e assinatura de distribuição.** O aplicativo empacotado não aceita uma variável de ambiente para desabilitar licenciamento. A identidade fica no armazenamento seguro do sistema e fora das pastas de projeto/perfis de teste.

- Windows: configure o certificado conforme electron-builder (`CSC_LINK`/`CSC_KEY_PASSWORD` ou repositório de certificados) e `PROSER_WINDOWS_PUBLISHER` com seu nome exato. Execute `npm run dist:win`.
- macOS: configure Developer ID, hardened runtime/notarização e as credenciais Apple conforme electron-builder. Execute `npm run dist:mac`.
- Windows 7: `npm run dist:win7`. A edição continua em Electron 22; possui licença assinada e fuses compatíveis, mas **não dispõe da integridade ASAR moderna no Windows**. Isso é uma limitação da plataforma, não uma proteção equivalente à edição atual.

Não são gerados source maps no build normal; mesmo quando ativados para diagnóstico com `PROSER_DEV_SOURCEMAPS=1`, são excluídos do pacote. Os fuses desabilitam RunAsNode, NODE_OPTIONS e depuração por argumentos e restringem o carregamento ao ASAR. Integridade ASAR é habilitada nos builds atuais.

## Distribuir atualizações

1. Aumente a versão nos dois `package.json` do aplicativo (atual e Windows 7) e seus lockfiles.
2. Gere e assine o pacote da plataforma desejada.
3. No painel, abra **Versões → Nova versão**, informe versão, plataforma, canal e notas.
4. Envie **um `.exe` NSIS para Windows** ou **um `.zip` assinado para macOS**. O `.dmg` pode ser armazenado adicionalmente. O limite é 2 GiB por arquivo; o navegador envia partes de até 5 MiB ao Rails, que monta o arquivo, calcula os hashes e o encaminha ao Appwrite também em partes. Isso permite passar pelo limite de tamanho por requisição da Cloudflare.
5. Publique o rascunho. A publicação exige exatamente um artefato principal e uma versão superior às já publicadas naquele canal/plataforma. Depois de publicar, arquivos não podem ser alterados. Retirar a versão impede novas consultas e downloads autorizados; não faz downgrade de aplicativos já atualizados.

O backend calcula SHA-256 e SHA-512, gera `latest.yml`/`latest-mac.yml` e assina o descritor da versão. O aplicativo consulta a cada 30 minutos, compara os metadados com o descritor assinado e baixa usando um grant temporário ligado à instalação e à versão. O bucket nunca é público. Credenciais Appwrite não são distribuídas.

`electron-updater` verifica o download e a assinatura de distribuição. A instalação ocorre **ao encerrar**, nunca chamando `quitAndInstall` durante uma apresentação. O Proser mostra o progresso e quando a atualização estiver pronta. Para downloads que durem mais de duas horas, repita a consulta para obter um novo grant.

## Recursos e limites

Planos controlam iluminação, áudio, vídeo/documentos, cenas, RDM, efeitos, captura de tela e PowerPoint. Licenças podem sobrescrever flags e quantidades individuais. Flags novas/desconhecidas não são liberadas implicitamente.

Os limites são **por projeto** e respeitam os limites técnicos atuais: 170 refletores, 256 áudios, 512 mídias de vídeo/imagem/documento e 128 cenas. Zero impede a criação/uso daquela coleção. A interface e o processo principal validam alterações e importações; o serviço DMX verifica a licença assinada e os limites antes de executar. Cenas não permitem executar mídias ou efeitos desabilitados.

Reduzir um limite não apaga projetos. Um projeto acima do limite pode ser reduzido e exportado; saídas que dependem dele são bloqueadas até se adequar. Recusas e expirações desmontam a interface operacional e encerram as saídas. Uma perda de conexão isolada usa a janela offline; planeje seu prazo para a duração das apresentações.

## Segurança e limites reais

- Requisições dos dispositivos: Ed25519, hash do corpo, método/caminho, nonce de uso único e tolerância de relógio de 5 minutos. Índice único no PostgreSQL impede replay entre workers.
- Autorizações: assinadas, vinculadas ao dispositivo e à consulta; validade limitada; chave privada só no servidor; decisões de recusa persistidas; cache protegido por `safeStorage` sem fallback em texto puro; detecção de retrocesso de relógio.
- Administração: Google com allowlist e verificação de identidade, OAuth state de uso único, cookie seguro/HTTP-only/SameSite, CSRF e origem, sessão revogável de 8 horas com inatividade máxima de 1 hora.
- Infra/API: HTTPS, HSTS, CSP, proteção de framing, no-store, parâmetros permitidos, limites de requisição, rate limiting compartilhado em Redis, publicação atômica, downloads autenticados e registro de ações administrativas.
- Atributos como nome do PC, versão e SO são informados pelo cliente e não constituem atestação de hardware. Reinstalar após apagar a identidade cria outro pedido e consome outra vaga. Administrador/root local ainda pode modificar um binário, restaurar snapshots ou extrair dados de sua própria sessão: o código entregue ao computador não fica impossível de adulterar.
- Autorizações já emitidas offline não podem ser revogadas instantaneamente. Não há promessa de “todos os controles possíveis” ou proteção absoluta contra engenharia reversa. O backend controla suas próprias APIs; os controles locais elevam a dificuldade e reduzem bypasses triviais.

## Testes

```sh
# Backend (SQLite; teste de concorrência requer PostgreSQL)
bundle exec rails test

# Banco isolado de teste; nunca use um banco de produção nesta sequência
RAILS_ENV=test DATABASE_URL=postgresql://.../proser_test bundle exec rails db:schema:load test

# Painel (instale Chromium com npx playwright install chromium)
npm --prefix frontend run test:e2e

# Aplicativo, no repositório vizinho
cd ../dmx
npm run check
npm run build
node scripts/test-desktop.mjs
```

O painel permite definir `PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH` para usar um Chrome já instalado. Os testes React usam respostas de API isoladas; os testes Rails exercitam os endpoints reais com Google/Appwrite simulados. Os testes do cliente executam registro HTTP assinado, recusa persistida, expiração offline, falha de rede e retrocesso do relógio. A integração final com as credenciais reais de Google/Appwrite e a instalação de uma atualização assinada exigem os serviços e certificados de produção configurados.

## Referências

- [Appwrite SSR](https://appwrite.io/docs/products/auth/server-side-rendering)
- [Identidades OAuth no Appwrite](https://appwrite.io/blog/post/appwrite-oauth)
- [Storage e uploads em partes](https://appwrite.io/docs/references/cloud/server-ruby/storage)
- [Electron auto-update](https://www.electron.build/v26/docs/features/auto-update/)
- [Integridade ASAR](https://www.electronjs.org/docs/latest/tutorial/asar-integrity)
- [Serviços no Cosmos](https://cosmos-cloud.io/docs/servapps/)
