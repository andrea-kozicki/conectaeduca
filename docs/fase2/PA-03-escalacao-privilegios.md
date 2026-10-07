# PA-03 — Escalação de privilégios host/container

## Objetivo

Avaliar se a identidade de baixo privilégio `teste` possui caminho plausível para root, administração de containers ou alteração de componentes privilegiados na EP125/EP126.

## Estado atual — EP126, 07/10/2026

**NIST SP 800-115:** Discovery em andamento.

Origem das evidências:

- host: `ep126-pucpr`;
- identidade: `teste` (UID/GID 1001);
- grupos: `teste, users`;
- sem `sudo`, `wheel` ou `docker`;
- execução read-only, sem elevação de privilégio;
- Discovery inicial SHA-256: `751fddebbf50b76d6b727925840f5e8ddcb81cef7a85e84f42b040465fdc3d32`;
- triagem systemd/ExecStart SHA-256: `7324c77f4d7dc72c641916ddea67940ff3c236b27276b22978e4ceb8856356ce`.

## Discovery inicial

Resultados:

- nenhum diretório do `PATH` é gravável pela identidade `teste`;
- Docker socket existe como `root:docker`, modo `srw-rw----`, sem leitura/escrita por `teste`;
- `/var/lib/docker` não é legível nem gravável por `teste`;
- cron e unidades systemd listadas não são graváveis por `teste`;
- capabilities observadas: `ping cap_net_raw=ep` e `mtr-packet cap_net_raw=ep`;
- foram enumerados 17 binários SUID/SGID comuns do sistema, sem exploração executada;
- `/dev/shm` é gravável com sticky bit `drwxrwxrwt`, comportamento esperado e não finding por si só.

## Triagem dos falsos positivos de escrita root

A primeira coleta havia reportado como "root-owned writable":

- `/etc/systemd/system-generators/systemd-gpt-auto-generator`;
- `/etc/systemd/system/sudo.service`;
- `/etc/systemd/user/pipewire-media-session.service`.

A triagem por `lstat`, `readlink` e resolução do alvo confirmou, nos três casos:

- objeto original: symlink;
- alvo: `/dev/null`;
- classificação: `SYMLINK_TO_DEV_NULL_NOT_FINDING`.

Conclusão: os três itens eram falsos positivos produzidos pelo uso anterior de `stat()`, que seguiu os symlinks até `/dev/null`.

## Triagem de serviços systemd privilegiados

Foram inspecionados cinco serviços ConectaEduca:

| Unidade | Usuário do serviço | ExecStart principal | Gravável por teste |
|---|---|---|---|
| conectaeduca-db-guard.service | root(default) | /usr/local/sbin/conectaeduca-db-guard-apply | não |
| conectaeduca-ferret-healthcheck.service | andrea.kiew | /opt/conectaeduca/scripts/observabilidade/verificar_ferret_health.sh | não |
| conectaeduca-ferret-retention.service | UID 1000 | /opt/conectaeduca/scripts/dlp/limpar_retencao_ferret.sh | não |
| conectaeduca-openbao-audit-bridge.service | andrea.kiew | /usr/bin/python3 + sanitizar_openbao_audit.py | não |
| conectaeduca-wazuh-yml-acl.service | root(default) | /usr/local/libexec/conectaeduca-wazuh-yml-acl | não |

Nenhum executável, script ou diretório-pai usado por serviço root apresentou escrita pela identidade `teste`.

Resumo automatizado:

- `ROOT_SERVICE_WRITE_CANDIDATES=0`;
- `RESULT=NO_ROOT_SERVICE_WRITE_PATH_CONFIRMED`.

## Sudoers

- `/etc/sudoers`: `-r--r----- root:root`, não legível nem gravável por `teste`;
- `/etc/sudoers.d`: diretório listável, porém não gravável por `teste`.

Até esta etapa não foi confirmado caminho de escalação via permissões de systemd, `ExecStart`, Docker socket ou escrita em diretórios críticos.

## Estado parcial

**PASS parcial para as superfícies já avaliadas.** Nenhum finding de escalação foi confirmado na EP126 até este ponto.

O PA-03 permanece em Discovery porque ainda serão triados:

1. permissões sudo efetivas sem autenticação interativa;
2. binários SUID/SGID enumerados, separando baseline comum de itens incomuns;
3. capabilities, confirmando que as duas observadas não fornecem primitive de escalação relevante;
4. posteriormente, a mesma metodologia na EP125.
