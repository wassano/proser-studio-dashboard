# Dashboard e API na Cloudflare

O Worker `proser-studio-dashboard` atende dois domínios: `https://app.proser.studio` distribui o React; `https://api.proser.studio` encaminha `/api`, `/auth` e `/up` para `https://proser.wassano.com`, a rota HTTPS do Cosmos. O navegador e os instaladores usam a API pública. PostgreSQL, Redis, Appwrite e a chave privada de licenciamento permanecem no servidor externo.

## Implantado em 14/09/2026

Worker publicado com Static Assets e Custom Domains nos dois hosts. DNS e HTTPS estão ativos; `workers.dev` e previews estão desativados. A publicação inicial usou o conector Cloudflare autenticado; o CLI local continua exigindo autenticação própria. Google OAuth está configurado no Appwrite; o login administrativo completo foi validado em 14/09/2026.

## Servidor de origem

1. Use as instruções de Docker/Appwrite do [README](README.md). O hostname HTTPS da origem deve ser diferente de `app.proser.studio` e `api.proser.studio` e resolver diretamente para o servidor Rails, sem passar por este Worker. Crie essa rota no Cosmos para o container `proser-studio-dashboard`, porta interna 3000, sem publicar portas no host.
2. Configure `DASHBOARD_URL=https://app.proser.studio` e `API_URL=https://api.proser.studio` no Rails. No Appwrite, cadastre as plataformas Web `app.proser.studio` e `api.proser.studio`. O callback Google continua sendo o do Appwrite; o retorno de sucesso vai para `https://api.proser.studio/auth/callback`, que conclui a sessão e redireciona ao painel.
3. Gere o `.env` com `ruby bin/setup-secrets`. Ele também gera `WORKER_ORIGIN_TOKEN`, de 32 bytes aleatórios em hexadecimal. Em instalações já existentes, gere esse valor e armazene-o no `.env` sem imprimi-lo em logs ou incluí-lo no Git.
4. Configure esse mesmo valor como secret **ORIGIN_TOKEN** no Worker. Ele autentica o gateway antes de o Rails confiar no host público e no IP informado. Pedidos diretos sem esse segredo recebem 403. A sessão Google e o CSRF continuam obrigatórios para a administração.
5. Execute `docker compose run --rm web bundle exec rails db:migrate` antes de atualizar o frontend. A migração de 14/09/2026 adiciona as sessões de upload em partes. Depois, atualize e reinicie o container Rails.

O Worker aplica CORS com credenciais exclusivamente ao painel, valida preflights e remove cabeçalhos CORS da origem antes de responder. O Rails exige CSRF nas mutações administrativas. O cookie `__Host-proser_admin` é restrito ao host da API, Secure, HttpOnly e SameSite=Lax. O frontend usa `credentials: include`; dados de clientes não são armazenados em cache. Redirecionamentos OAuth são entregues ao navegador sem segui-los no servidor. Requisições assinadas do aplicativo mantêm os mesmos bytes, método e caminho. O IP recebido em `CF-Connecting-IP` é repassado por cabeçalho autenticado; valores de encaminhamento enviados pelo cliente são descartados.

## Publicação

Requisitos: Node >= 22.13 e acesso à conta Cloudflare configurada.

```sh
npm ci
npm --prefix frontend ci
npx wrangler login
```

O `wrangler.jsonc` contém `PUBLIC_ORIGIN=https://app.proser.studio`, `API_ORIGIN=https://api.proser.studio` e `RAILS_ORIGIN=https://proser.wassano.com`. Mantenha as três origens HTTPS distintas, sem caminho ou credenciais. Em produção, o frontend usa `https://api.proser.studio` por padrão (`VITE_API_ORIGIN` permite outro ambiente).

```sh
# Informe o valor de WORKER_ORIGIN_TOKEN pelo prompt; nunca como argumento público.
npx wrangler secret put ORIGIN_TOKEN
npm run types
npm run check
npm run deploy:dry-run
npm run deploy
```

`workers.dev` e URLs de preview ficam desativados. Os Custom Domains configuram DNS e certificados dos dois hosts; não é preciso alterar o domínio principal. O Wrangler local precisa de login próprio; a conexão do plugin Cloudflare não autentica automaticamente o CLI.

Após atualizar, valide `https://api.proser.studio/up`, sessão/CORS, login real com Google e upload/publicação. Só teste registros em produção quando quiser consumir uma vaga. O backend precisa manter o mesmo segredo do Worker, credenciais reais Appwrite/Google e banco preparado. O acesso sem sessão a `/api/admin/licenses` deve retornar 401 pelo Worker; acesso direto ao Rails deve retornar 403.

O Cosmos exige identificação de cliente: o software e o atualizador enviam `User-Agent: Proser-Studio/<versão>`. Requisições Node sem User-Agent podem receber 403 antes do Rails. Essa identificação não substitui as assinaturas nem autentica dispositivos.

## Uploads

O navegador envia partes de **5 MiB**, com verificação de ordem, repetição idempotente e vínculo à sessão administrativa. O Rails monta os arquivos no volume temporário, valida tamanho/magic bytes, calcula SHA-256/SHA-512 e publica no bucket privado Appwrite. Mantém-se o máximo de **2 GiB por arquivo** e dois uploads pendentes por sessão. O Worker consulta a sessão antes de encaminhar qualquer parte e transmite o corpo em streaming.

Uploads abandonados expiram em quatro horas. Execute `rails proser:prune` periodicamente; o encerramento da sessão remove seus uploads temporários. Um cancelamento ou falha do navegador cancela o envio incompleto. Reserve espaço no volume `temporary` para os arquivos em montagem. Vários containers Rails devem compartilhar esse volume se receberem partes do mesmo arquivo.

## Verificação local

```sh
npm run types
npm run check
bundle exec rails test
npm --prefix frontend run test:e2e
npm run deploy:dry-run
```

Os testes usam origens, credenciais e respostas isoladas. O dry run gera o pacote sem alterar a Cloudflare. Não substituem o login Google e a verificação do servidor real.

Referências: [Static Assets](https://developers.cloudflare.com/workers/static-assets/), [Custom Domains](https://developers.cloudflare.com/workers/configuration/routing/custom-domains/), [limites de requisição](https://developers.cloudflare.com/workers/platform/limits/).
