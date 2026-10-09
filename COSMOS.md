# Deploy no Cosmos Cloud

Servidor: `deploy@157.173.111.33`. Diretório: `/home/deploy/proser-studio-dashboard`.

A stack deste projeto contém Rails/React, PostgreSQL e Redis. O Appwrite existente em `https://appwrite.wassano.com/v1`, projeto `proser`, continua separado. O Compose não contém `ports`, não instala outro proxy e não altera os serviços existentes.

## Rotas atuais no Cosmos

- `app.proser.studio`: React, login Google e API administrativa na mesma origem.
- `api.proser.studio`: registro, heartbeat e atualização dos instaladores existentes.
- Ambos usam o container `proser-studio-dashboard`, destino HTTP na porta **3000**, sem portas publicadas no host.
- DNS: registros A para `157.173.111.33`, com proxy Cloudflare desligado. Os Custom Domains do Worker são removidos.
- Não ative login adicional do Cosmos nestas rotas: o Rails valida a sessão Google/CSRF e as assinaturas dos dispositivos.
- Deixe o endurecimento de cabeçalhos por conta do Rails nestas duas rotas (`DisableHeaderHardening=true` no Cosmos). O Rails fornece CSP restrita à própria origem, HSTS, bloqueio de frames, política de permissões e `nosniff`.
- O filtro genérico de bots fica desligado nestas duas rotas para aceitar clientes desktop; os limites de requisições do Cosmos e do Rails permanecem ativos.
- Configure `DASHBOARD_URL=https://app.proser.studio`, `API_URL=https://api.proser.studio`, `TRUSTED_PROXY_CIDRS=172.30.80.1/32` e `WORKER_ORIGIN_TOKEN=` vazio. Preserve as demais credenciais existentes.
- Não configure `VITE_API_ORIGIN` no build de produção: o painel usa `/api` e `/auth` no próprio host, sem CORS entre subdomínios. Seu cookie `__Host-proser_admin` permanece Secure, HttpOnly e SameSite=Lax.

A rota antiga `proser.wassano.com` não é mais a origem pública da aplicação. O Rails aceita apenas os hosts `app` e `api`; os arquivos estáticos estão dentro da própria imagem Docker.

## Operação

```sh
cd /home/deploy/proser-studio-dashboard
docker compose build web
docker compose up -d postgres redis
docker compose run --rm web bundle exec rails db:prepare db:seed
docker compose run --rm web bundle exec rails proser:provision_storage
docker compose up -d web
docker compose ps
```

Mantenha `.env` e `secrets/` apenas no servidor e em backup seguro. Preserve os volumes em atualizações; não use `down -v`. A chave Ed25519 precisa ser preservada para manter compatibilidade com os instaladores distribuídos. Use apenas `license-public.pem` nos builds desktop.

`docker compose run --rm web bundle exec rails proser:prune` remove sessões e uploads abandonados. Execute periodicamente. Faça backup do PostgreSQL, uploads Appwrite e chaves.

## Appwrite

Configure duas chaves de serviço no projeto: autenticação com `sessions.write`; armazenamento com `buckets.read`, `buckets.write`, `files.read`, `files.write`. As chaves ficam em `APPWRITE_AUTH_KEY` e `APPWRITE_STORAGE_KEY` no `.env`. Configure as plataformas Web `app.proser.studio` e `api.proser.studio` e o provedor Google para esse projeto.

O limite global de arquivos da instância Appwrite precisa comportar os instaladores; o dashboard aceita até 2 GiB. Alterações no limite global afetam toda a instância e exigem manutenção própria do Appwrite.

O retorno OAuth do Appwrite ao Rails é `https://app.proser.studio/auth/callback`, no mesmo host em que o navegador iniciou o login. `API_URL` continua definindo as URLs de atualização dos dispositivos. O callback do Google para o Appwrite não muda.

## Histórico: implantação inicial em 14/09/2026

- Stack instalada e iniciada no diretório acima, com três containers e nenhum vínculo de porta ao host.
- Container de aplicação: `proser-studio-dashboard`, usuário `10001:10001`, filesystem somente leitura e healthcheck `/up` saudável.
- PostgreSQL preparado, plano Studio inicializado e limite global **20**, sem instalações de teste cadastradas.
- Chaves `proser-dashboard-auth` e `proser-dashboard-storage` criadas no projeto `proser`; segredos gravados somente no `.env` do servidor, com modo `0600`.
- Plataformas Web `app.proser.studio` e `api.proser.studio` cadastradas no Appwrite.
- Bucket privado `proser-releases`, sem permissões públicas, com limite de **2147483648 bytes**.
- `_APP_STORAGE_LIMIT` atualizado em `/home/appwrite/.env` após autorização. Backup anterior protegido ao lado desse arquivo; somente o serviço HTTP `appwrite` foi recriado, usando a mesma imagem.
- Validação HTTP interna: página e `/up` retornam 200; API administrativa sem sessão retorna 401; origem sem segredo do Worker retorna 403.

Na implantação inicial, a rota do Cosmos e os dois domínios do Worker foram publicados. O segredo do gateway foi transferido de forma criptografada e permanece apenas no servidor e no secret do Worker. Google OAuth está configurado e o login real de `dwassano@gmail.com` foi validado até o painel autenticado.

## HTTPS no retorno Google

O Cosmos termina TLS e encaminha o Appwrite por HTTP ao `appwrite-traefik`. O Traefik deve preservar `X-Forwarded-Proto` somente quando a requisição vem do Cosmos. No servidor atual, o Cosmos usa a rede do host e pode chegar ao Traefik pelos gateways das três redes conectadas a ele: `172.25.0.1`, `172.26.0.1` e `172.27.0.1`. Após reiniciar o Cosmos, os logs confirmaram a origem `172.27.0.1`. Em `/home/appwrite/docker-compose.yml`, o serviço `traefik` contém:

```yaml
- --entrypoints.appwrite_web.forwardedHeaders.trustedIPs=172.25.0.1/32,172.26.0.1/32,172.27.0.1/32
```

Sem isso, o Appwrite gera `http://appwrite.wassano.com/v1/account/sessions/oauth2/callback/google/proser`, causando `redirect_uri_mismatch`. O URI autorizado no Google é **https://appwrite.wassano.com/v1/account/sessions/oauth2/callback/google/proser**. Na implantação atual, o retorno seguinte ao Rails é `https://app.proser.studio/auth/callback`.

A alteração recriou apenas `appwrite-traefik`, sem publicar portas. Backup protegido desta migração: `/home/appwrite/docker-compose.yml.before-proser-direct-20260914`. Em mudanças na rede Docker, confirme o IP de origem do Cosmos antes de atualizar a regra; mantenha a confiança restrita ao proxy. A validação pública também confirmou que um cliente enviando `X-Forwarded-Proto: http` continua recebendo callback HTTPS.

Referência: [Traefik 2.11 — Forwarded Headers](https://doc.traefik.io/traefik/v2.11/routing/entrypoints/#forwarded-headers).

## Atualizações e uploads

### CI de deploy

O workflow `.github/workflows/deploy.yml` segue o acesso por SSH usado pelo Report7 no mesmo servidor. PRs executam Rails com PostgreSQL 16 (incluindo concorrência), testes do gateway, upload, build React/TypeScript, testes de interface Chromium e testes do script de deploy. Push na `main` e execução manual na `main` fazem deploy após esses checks. A execução manual em outras branches só testa; não publica.

Configure estes **secrets do repositório do painel** (ou do environment `production`):

| Secret | Configuração |
| --- | --- |
| `SSH_PRIVATE_KEY` | Chave do usuário de deploy autorizado no servidor, como no Report7. O GitHub não permite ler ou copiar automaticamente o valor de um secret de outro repositório. |
| `SSH_KNOWN_HOSTS` | Chave pública SSH do servidor, conferida por um canal confiável; pode usar o mesmo valor validado no Report7. O workflow exige verificação estrita do host. |
| `SSH_HOST` | Opcional; padrão `157.173.111.33`. |
| `SSH_USER` | Opcional; padrão `deploy`. |
| `PROJECT_PATH` | Opcional; padrão `/home/deploy/proser-studio-dashboard`. Não use o diretório do Report7. |

A variável `SSH_PORT` é opcional, com padrão `22`. O usuário SSH precisa escrever no diretório do painel e acessar Docker/Compose; o servidor Linux precisa de `flock` e de Compose com `--wait`/`--wait-timeout`. A stack existente, `.env`, `secrets/license-private.pem` e `geoip/` precisam estar preparados. Não há `ENV_FILE` no GitHub: o ambiente e as chaves continuam no servidor.

O runner envia um arquivo produzido por `git archive` do **SHA que passou nos testes** para `.deploy/releases/<sha>-<run>-<attempt>`. O servidor compila a imagem a partir desse snapshot isolado; arquivos locais antigos e dados de produção não entram no contexto do build. O Compose usa o diretório de produção para resolver `.env`, chaves e volumes. PostgreSQL e Redis precisam estar saudáveis e permanecem em execução.

Antes das migrations, `bin/deploy` faz um backup PostgreSQL compactado e protegido em `.deploy/backups/`. Em seguida aplica `db:migrate` com a nova imagem e recria somente `web`, aguardando o healthcheck por até 180 segundos ([opções do Compose](https://docs.docker.com/reference/cli/docker/compose/up/)). O runner do GitHub verifica HTTPS em `/up` nos dois domínios e o catálogo público `/api/v1/releases`, pois o proxy público pode bloquear requisições originadas no próprio servidor. `scripts/verify-deploy.py` retorna o resultado pelo mesmo canal SSH; o processo remoto mantém o lock e só registra a versão após receber aprovação para o SHA exato. Falha, EOF, interrupção ou ausência de resposta por 180 segundos durante essa espera restaura a imagem e o Compose anteriores e marca o job como falho. Falhas de build, backup ou migration mantêm o container anterior em execução.

O rollback automático é apenas da aplicação; não desfaz migrations nem restaura o banco. Migrations de produção precisam ser compatíveis com a versão anterior. O backup permite recuperação manual quando necessária. Não há `down`, exclusão de volumes, pruning global ou alteração de outros projetos.

Após sucesso, `.deploy/current` aponta atomicamente para o snapshot ativo e `.deploy/revision` registra o SHA. O código legado na raiz não é sobrescrito. Para operar **a versão publicada pelo CI**, use:

```sh
cd /home/deploy/proser-studio-dashboard
docker compose --project-directory "$PWD" -p proser-studio-dashboard \
  -f .deploy/current/compose.yml -f .deploy/current/compose.deploy.yml ps
```

Use os mesmos argumentos para `exec`, `run` ou `up`; não faça build da cópia antiga na raiz após adotar o CI. Snapshots, imagens e backups ficam no servidor para recuperação. Defina uma retenção operacional preservando o snapshot ativo, a última imagem saudável e os backups necessários; o CI não faz limpeza destrutiva. `.deploy/` está ignorado no Git e no contexto Docker.

O grupo de concorrência do workflow e o lock `flock` no servidor serializam deploys, sem interromper migrations em andamento. O job usa o environment [`production`](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments); configure a restrição à branch `main` nesse environment se desejar reforçá-la também nas configurações do GitHub.

### Atualização manual anterior ao CI

Para atualizar uma instalação existente, sincronize o código sem `.env`, `secrets/`, `geoip/`, bancos, backups, `node_modules`, `vendor/`, `storage/`, `tmp/` ou `.git`. Não use `--delete` sobre o diretório de produção. Depois execute no servidor:

```sh
cd /home/deploy/proser-studio-dashboard
docker compose build web
docker compose run --rm web bundle exec rails db:migrate
docker compose up -d --no-deps web
docker compose ps
```

O Dockerfile compila o React durante o build e o Rails serve os arquivos de `public/`. `npm run deploy` do antigo Worker foi bloqueado e os domínios foram retirados de `wrangler.jsonc` para evitar republicação acidental.

O painel envia partes de até 5 MiB com posição explícita e repete falhas temporárias até três vezes. Partes e conclusão são idempotentes no Rails. Falhas definitivas cancelam o upload temporário e limpam a mensagem de progresso. O envio termina quando o Rails verifica o arquivo e confirma seu armazenamento privado no Appwrite. Subir um arquivo não publica automaticamente uma versão.

Testes locais: `bundle exec rails test`, `npm --prefix frontend run test:unit` e `npm --prefix frontend run build`.

Backups desta migração: configuração do Cosmos em `/var/lib/cosmos/cosmos.config.json.before-proser-direct-20260914T184804Z`, ambiente em `.env.before-cosmos-direct-20260914`, banco em `/home/deploy/proser-backups/database-before-cosmos-direct-20260914.sql` e imagem `proser-studio-dashboard:before-cosmos-direct-20260914`. Backups do banco devem ficar fora da pasta enviada ao build; `.dockerignore` também exclui dumps SQL.

## Validação da migração em 14/09/2026

- Certificado válido emitido pelo Cosmos com SAN `*.wassano.com` e `*.proser.studio`. Os tokens DNS usados pelo Cosmos mantêm suas permissões originais e agora incluem também a zona `proser.studio`, permitindo renovação automática.
- Domínios `app` e `api` desvinculados do Worker; registros A sem proxy para `157.173.111.33`. Ambos responderam 200 com TLS validado e resolução DNS pública.
- Login Google real validado no painel hospedado pelo Rails. Nenhuma porta Docker publicada no host.
- Upload real pela interface: `Proser studio-1.18.1-arm64.dmg`, 135610859 bytes, SHA-256 `e3fed26c087ac853d0c04ca5ef0b338c73232ac8a4b4932e72d3424553c424ee`. Painel exibiu “Instalador enviado e verificado”. Release 1.18.1/mac-arm64 mantida em rascunho.
- Rails: 22 testes, 149 assertions, zero falhas/erros, 1 skip. Frontend: 3 testes de upload e build TypeScript/Vite aprovados. API administrativa sem sessão retorna 401.

## Habilitar cadastro de versões pelo GitHub Actions

Atualize o código do painel, execute `bin/rails db:migrate` e compile o frontend. Configure `RELEASE_CI_TOKEN` no `.env` do Rails com um segredo aleatório de 64 caracteres hexadecimais e o mesmo valor no secret `PROSER_RELEASE_CI_TOKEN` do repositório desktop. Recrie o serviço Rails para carregar a variável. O segredo autoriza apenas a API de ingestão de rascunhos; a liberação continua no painel. Não copie segredos para logs ou para o Git.

Confira `/downloads` na origem do painel. Essa rota é servida pelo Rails no Cosmos e pelo gateway no modo legado. No proxy, mantenha uploads de 5 MiB e o tempo de resposta necessário para a conclusão do armazenamento no Appwrite. Os instaladores permanecem em bucket privado; a API transmite apenas arquivos de versões publicadas.
