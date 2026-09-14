# Deploy no Cosmos Cloud

Servidor: `deploy@157.173.111.33`. Diretório: `/home/deploy/proser-studio-dashboard`.

A stack deste projeto contém Rails/React, PostgreSQL e Redis. O Appwrite existente em `https://appwrite.wassano.com/v1`, projeto `proser`, continua separado. O Compose não contém `ports`, não instala outro proxy e não altera os serviços existentes.

## Rota no Cosmos

- Serviço/container: `proser-studio-dashboard`.
- Protocolo do destino: **HTTP**.
- Porta do container: **3000** (somente interna).
- Ative HTTPS no domínio de origem no Cosmos.
- Rota HTTPS configurada: `https://proser.wassano.com`. Os hosts `app.proser.studio` e `api.proser.studio` são atendidos pelo Worker.
- Preserve os cabeçalhos `X-Proser-Edge-Token` e `X-Proser-Edge-IP` encaminhados pelo Worker.
- Não ative uma segunda tela de login do Cosmos nesta rota: ela impediria as APIs dos instaladores. A aplicação já valida o segredo do Worker, assinaturas de dispositivos e sessão administrativa.

O segredo é verificado antes das demais rotas. Uma visita direta à origem retorna **403**, comportamento esperado. O healthcheck interno `/up` continua disponível pelo loopback do container.

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

O Worker usa `RAILS_ORIGIN=https://proser.wassano.com`. No Rails, `DASHBOARD_URL=https://app.proser.studio` define o destino do painel e `API_URL=https://api.proser.studio` define o host público da API e do retorno OAuth. Consulte [CLOUDFLARE.md](CLOUDFLARE.md) para republicar.

## Implantação em 14/09/2026

- Stack instalada e iniciada no diretório acima, com três containers e nenhum vínculo de porta ao host.
- Container de aplicação: `proser-studio-dashboard`, usuário `10001:10001`, filesystem somente leitura e healthcheck `/up` saudável.
- PostgreSQL preparado, plano Studio inicializado e limite global **20**, sem instalações de teste cadastradas.
- Chaves `proser-dashboard-auth` e `proser-dashboard-storage` criadas no projeto `proser`; segredos gravados somente no `.env` do servidor, com modo `0600`.
- Plataformas Web `app.proser.studio` e `api.proser.studio` cadastradas no Appwrite.
- Bucket privado `proser-releases`, sem permissões públicas, com limite de **2147483648 bytes**.
- `_APP_STORAGE_LIMIT` atualizado em `/home/appwrite/.env` após autorização. Backup anterior protegido ao lado desse arquivo; somente o serviço HTTP `appwrite` foi recriado, usando a mesma imagem.
- Validação HTTP interna: página e `/up` retornam 200; API administrativa sem sessão retorna 401; origem sem segredo do Worker retorna 403.

A rota do Cosmos e os dois domínios do Worker estão publicados. O segredo do gateway foi transferido de forma criptografada e permanece apenas no servidor e no secret do Worker. Google OAuth está configurado e o login real de `dwassano@gmail.com` foi validado até o painel autenticado.

## HTTPS no retorno Google

O Cosmos termina TLS e encaminha o Appwrite por HTTP ao `appwrite-traefik`. O Traefik deve preservar `X-Forwarded-Proto` somente quando a requisição vem do Cosmos. No servidor atual, o Cosmos usa a rede do host e chega ao Traefik por `172.25.0.1` (IP confirmado nos logs). Em `/home/appwrite/docker-compose.yml`, o serviço `traefik` contém:

```yaml
- --entrypoints.appwrite_web.forwardedHeaders.trustedIPs=172.25.0.1/32
```

Sem isso, o Appwrite gera `http://appwrite.wassano.com/v1/account/sessions/oauth2/callback/google/proser`, causando `redirect_uri_mismatch`. O URI autorizado no Google é **https://appwrite.wassano.com/v1/account/sessions/oauth2/callback/google/proser**. O retorno seguinte ao Rails é `https://api.proser.studio/auth/callback`.

A alteração recriou apenas `appwrite-traefik`, sem publicar portas. Backup protegido: `/home/appwrite/docker-compose.yml.before-proser-oauth-20260914T132828Z`. Em mudanças na rede Docker, confirme o IP de origem do Cosmos antes de atualizar a regra; mantenha a confiança restrita ao proxy. A validação pública também confirmou que um cliente enviando `X-Forwarded-Proto: http` continua recebendo callback HTTPS.

Referência: [Traefik 2.11 — Forwarded Headers](https://doc.traefik.io/traefik/v2.11/routing/entrypoints/#forwarded-headers).
