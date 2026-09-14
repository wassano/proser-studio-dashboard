# Appwrite self-hosted

Use uma instância própria, separada do banco de licenças. Rails mantém as transações no PostgreSQL; Appwrite cuida do OAuth Google e dos instaladores privados.

O deploy utiliza a instância existente em **https://appwrite.wassano.com/v1**, projeto **proser**, no servidor Cosmos. Ela reporta Appwrite **1.6.0**, com imagem local `appwrite-dev`. Nenhuma atualização de versão faz parte deste deploy.

O Compose do dashboard não publica portas e não instala outra instância Appwrite. Para uma instalação nova, siga a [distribuição oficial](https://appwrite.io/docs/advanced/self-hosting/installation); para o servidor atual, preserve os serviços e volumes existentes em `/home/appwrite`.

1. Configure o domínio `appwrite.wassano.com`, HTTPS, senhas e a chave de criptografia únicos. Preserve os arquivos e volumes gerados pelo instalador; não substitua a distribuição completa por um único container Appwrite.
2. Restrinja a criação/acesso ao Console ao administrador `dwassano@gmail.com`. Desabilite os serviços de execução de código/sites que não forem utilizados, seguindo a configuração oficial da versão instalada.
3. Crie o projeto `proser`, adicione as plataformas Web `app.proser.studio` e `api.proser.studio` e habilite **somente Google** como provedor de login do projeto. Desabilite login por e-mail/senha, anônimo, telefone e demais provedores que não serão usados.
4. No Google Cloud, crie credenciais OAuth Web e configure a URL de retorno exibida pelo Appwrite (normalmente `https://appwrite.wassano.com/v1/account/sessions/oauth2/callback/google/proser`). Copie Client ID e Client Secret para a configuração Google do projeto Appwrite, nunca para o React.
5. Crie uma API key de autenticação com `sessions.write` e uma de Storage com `files.read`, `files.write`, `buckets.read`, `buckets.write`. Guarde-as respectivamente em `APPWRITE_AUTH_KEY` e `APPWRITE_STORAGE_KEY`. Depois do provisionamento pode remover `buckets.write` da chave de execução e guardar uma chave de manutenção separada.
6. Configure `_APP_STORAGE_LIMIT=2147483648` e os limites de proxy correspondentes. Não exponha o bucket à permissão `any`. Execute `bundle exec rails proser:provision_storage` no backend para criá-lo.
7. Faça backup dos volumes de uploads, do banco Appwrite e da chave de criptografia. Atualizações de Appwrite exigem seu procedimento oficial de migração.

O antivírus e a criptografia por arquivo do Appwrite têm limites por tamanho definidos pela plataforma. Não assuma que um instalador grande foi escaneado ou criptografado por ativar essas opções: use volumes criptografados e valide os artefatos assinados no build.

## Retorno OAuth atrás do Cosmos

O Client ID e Client Secret Google estão configurados no projeto `proser`, e o login administrativo foi validado em 14/09/2026. No Google Cloud, o URI de redirecionamento deve ser exatamente `https://appwrite.wassano.com/v1/account/sessions/oauth2/callback/google/proser`.

O Appwrite determina o protocolo do callback pelo cabeçalho de encaminhamento. Preserve o HTTPS recebido do Cosmos no Traefik, conforme [COSMOS.md](../COSMOS.md#https-no-retorno-google). Apenas ativar redirecionamento obrigatório para HTTPS no Appwrite não corrige um proxy que informa HTTP; pode provocar um loop. Nunca cadastre o callback HTTP como solução.
