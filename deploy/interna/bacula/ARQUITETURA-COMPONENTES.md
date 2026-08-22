# Arquitetura dos componentes Bacula

## Modelo escolhido

### VM interna

- Bacula Director: container.
- Bacula Storage Daemon: container.
- Catalog: PostgreSQL dedicado em container.
- bconsole: uso administrativo local/efêmero; sem publicação ampla.
- Bacula File Daemon: **nativo no host Ubuntu**.

### VM DMZ

- Bacula File Daemon: **nativo no host Ubuntu**.

## Por que File Daemon nativo?

Um File Daemon containerizado precisaria receber bind mounts amplos do
filesystem do host para proteger arquivos locais. Isso aumentaria muito a
superfície de privilégio e criaria um "container que enxerga o host".

O agente nativo permite:
- FileSets explícitos;
- usuário/grupo próprio;
- permissões de leitura deliberadas;
- ausência de Docker socket;
- integração natural com systemd e logs do host.

## Por que Catalog PostgreSQL separado?

O Catalog do Bacula é metadado crítico de recuperação e não deve compartilhar
o banco/schema/credencial da aplicação. Um PostgreSQL dedicado reduz acoplamento
com o MariaDB do ConectaEduca.

## Storage

No laboratório:

```text
/srv/conectaeduca-backup/bacula/volumes
```

será o ponto lógico de armazenamento do Storage Daemon, com permissão exclusiva
do serviço. O caminho final pode mudar, mas deve ser parametrizado.

O Storage não fica na DMZ.

## Criptografia

Baseline de implementação:
1. TLS obrigatório entre Director, File Daemons e Storage Daemon;
2. verificação de peer/certificados na topologia final;
3. avaliar/ativar criptografia dos volumes do Storage na versão Bacula validada;
4. chaves privadas e chaves de recuperação nunca entram no Git ou nos relatórios.

Bacula 15 oferece criptografia de volume no Storage Daemon. A implementação
deverá validar a versão/imagem antes de habilitar a opção.

## Sem implementação antecipada

Este documento não fixa ainda:
- tag/digest da imagem;
- nome final dos containers;
- credenciais;
- certificados;
- horários;
- endereços IP das VMs.

Esses itens entram no tijolo de implementação depois do checkpoint
pré-Bacula.
