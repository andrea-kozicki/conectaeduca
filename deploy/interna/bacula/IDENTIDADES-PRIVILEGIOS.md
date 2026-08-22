# Identidades, segredos e privilégio mínimo

## Identidades separadas

Serão criadas identidades distintas para:
- Director;
- Storage Daemon;
- File Daemon DMZ;
- File Daemon interna;
- Catalog PostgreSQL;
- dump MariaDB;
- snapshot OpenBao;
- operação administrativa/bconsole.

Nenhuma senha será compartilhada por conveniência entre componentes.

## MariaDB

O job de dump terá usuário dedicado, sem privilégios administrativos globais.
A senha não aparecerá em linha de comando, logs, Git ou relatório.

## OpenBao

Criar política de snapshot dedicada. O job de backup não recebe:
- root token;
- unseal shares;
- policy SMTP;
- credenciais da aplicação.

O segredo/credencial temporário do snapshot deve ter o menor TTL e escopo
práticos ou ser materializado de forma protegida em runtime.

## Bacula

- working directories: acesso apenas ao usuário/daemon necessário;
- Director não deve ter acesso irrestrito ao filesystem dos clientes;
- FileSets delimitam leitura;
- Storage Daemon escreve apenas no diretório de volumes/working;
- Catalog usa banco e usuário próprios;
- bconsole administrativo não fica aberto a redes não confiáveis.

## Docker

Nenhum componente Bacula recebe:
- `/var/run/docker.sock`;
- `privileged: true`;
- `network_mode: host`;
- bind mount `/`.

## PKI/TLS

Certificados privados ficam em runtime protegido e fora do Git/handoff.
A CA e a estratégia de confiança serão fechadas junto à implantação entre VMs.

Se for usada chave mestre de recuperação de criptografia de backup, a chave
privada mestre deve ter custódia offline separada do Storage/Director.
