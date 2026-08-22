# ConectaEduca — contrato do Bacula File Daemon nas VMs

## Decisão

O File Daemon definitivo é **nativo no host Ubuntu**, não um container com bind
amplo do filesystem. O container `conectaeduca-bacula-filedaemon-lab` continua
sendo apenas ferramenta de laboratório/restore.

## VMs

- DMZ: `conectaeduca-dmz-fd`, TCP/9102.
- Interna: `conectaeduca-interna-fd`, TCP/9102.
- Director e Storage permanecem na VM interna.
- pfSense deve permitir 9102 somente entre Director e os File Daemons.

## Segurança

- TLS é obrigatório.
- Senhas e chaves são runtime e não entram no Git.
- Cada FD recebe segredo próprio.
- Certificados devem ser emitidos/materializados na implantação.
- Não copiar `.runtime` do host de desenvolvimento.

## Compatibilidade

Antes de instalar, consultar `apt-cache policy bacula-fd` na versão Ubuntu da
VM e confirmar compatibilidade com o Director utilizado no laboratório. O
handoff não força downgrade/upgrade do Director apenas para igualar números de
versão.

## Aula / implantação

A instalação nativa pode ser demonstrada com
`scripts/implantacao/preparar_bacula_fd_ubuntu.sh`. O script instala o pacote,
copia o template escolhido e **não inicia o daemon enquanto placeholders de
segredo estiverem presentes**.
