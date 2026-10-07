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


## Triagem sudo, SUID/SGID e capabilities

Evidência: SHA-256 `0fb64574f00e843c0f5b443f126d46440ff6a399f045c24f8448c8961608c0a2`.

### Sudo

A enumeração não interativa `sudo -n -l` retornou RC=1 e informou que uma senha é necessária. Nenhum grant `NOPASSWD` foi confirmado e nenhuma elevação foi executada.

Esse resultado não demonstra ausência absoluta de permissões sudo que exijam senha; demonstra apenas que a identidade `teste` não possui caminho sudo não interativo confirmado, coerente com as regras zero-sudo desta fase.

### SUID/SGID

Foram enumerados 17 binários SUID/SGID.

Resumo:

- graváveis por `teste`: 0;
- com diretório-pai gravável por `teste`: 0;
- pertencentes a usuário não-root: 0;
- item marcado como não associado a pacote: `/usr/bin/fusermount3`.

Os demais itens são binários de sistema comuns, incluindo `passwd`, `su`, `sudo`, `pkexec`, `mount`, `umount`, `crontab` e auxiliares PAM. Nenhum foi explorado nesta etapa.

O campo `UNPACKAGED_SUID_SGID=1` fez o script retornar `MANUAL_REVIEW_REQUIRED`. Esse resultado não é finding: a associação de pacote de `fusermount3` será verificada separadamente antes do fechamento da Discovery.

### Capabilities

Foram encontradas somente:

- `/usr/bin/ping cap_net_raw=ep`;
- `/usr/bin/mtr-packet cap_net_raw=ep`.

Não foram detectadas capabilities de alto impacto para escalação, arquivos com capability graváveis ou diretórios-pai graváveis.

### Estado parcial

Até esta etapa, nenhuma primitive óbvia de escalação foi confirmada.

A Discovery da EP126 permanece aberta apenas para a triagem final de `/usr/bin/fusermount3` e sua associação/integridade de pacote.


## Fechamento da Discovery na EP126

A triagem final do `/usr/bin/fusermount3` confirmou que o item marcado anteriormente como `UNPACKAGED_SUID_SGID=1` era um falso positivo de associação de caminho causado pelo layout **merged-/usr**.

Evidência: SHA-256 `7be13987d3b22412691063820dccbcf5fb1cefb5a6ebc65ac26474a2b408bdd8`.

Resultados:

- `/bin -> /usr/bin`;
- `/bin/fusermount3` e `/usr/bin/fusermount3` resolvem para o mesmo arquivo;
- modo do binário: `4755`, proprietário `root:root`;
- `fuse3` instalado na versão `3.14.0-5build1`;
- `dpkg-query -S /bin/fusermount3` confirmou ownership por `fuse3`;
- `dpkg-query -L fuse3` lista `/bin/fusermount3`;
- `dpkg -V fuse3` retornou RC 0 e nenhuma divergência;
- `fusermount3 --version` retornou `3.14.0`;
- nenhuma exploração foi executada e nenhuma modificação foi realizada.

### Conclusão do subescopo EP126

**NIST Discovery do PA-03 na EP126: CONCLUÍDA.**

Nenhum finding de escalação de privilégios foi confirmado nas superfícies avaliadas:

- grupos privilegiados;
- sudo não interativo;
- Docker socket;
- diretórios do PATH;
- cron;
- systemd e ExecStart;
- arquivos/diretórios graváveis;
- SUID/SGID;
- capabilities;
- integridade e ownership do `fusermount3`.

Classificação: **PASS para o subescopo EP126**.

O PA-03 global permanece aberto porque a mesma metodologia ainda precisa ser aplicada à EP125.
