# Ponte de secret SMTP para Docker Compose

Docker Compose, quando um `secret` tem origem em `file:`, usa o arquivo do host
como bind mount. UID/GID e modo do arquivo são preservados.

O ConectaEduca mantém o PHP-FPM como usuário não-root `www-data`. Para permitir
leitura do App Password sem tornar o arquivo world-readable e sem executar PHP
como root, o host cria um grupo de sistema dedicado sem membros humanos.

Fluxo:

OpenBao -> /dev/shm/conectaeduca-smtp-password
         owner = usuário materializador
         group = conectaeduca-smtp-secret
         mode  = 0640

Docker Compose -> `group_add` injeta somente o GID desse grupo no serviço PHP.

Dentro do container:
- PHP continua executando como `www-data`;
- o secret permanece somente leitura;
- `other` não recebe permissão;
- nenhum usuário é adicionado ao grupo no host.

Esta é a ponte do laboratório/Compose. No handoff entre VMs, a evolução preferida
é OpenBao Agent/Proxy materializando o secret diretamente para a workload.
