# PA-03 — Escalação de privilégios host/container

## Objetivo

Avaliar se a identidade de baixo privilégio `teste` possui caminho plausível para root, administração de containers ou alteração de componentes privilegiados na EP125/EP126.

## Estado atual — EP126, 07/10/2026

**NIST SP 800-115:** Discovery em andamento.

Origem da evidência:

- host: `ep126-pucpr`;
- identidade: `teste` (UID/GID 1001);
- grupos: `teste, users`;
- sem `sudo`, `wheel` ou `docker`;
- execução read-only, sem elevação de privilégio;
- SHA-256: `751fddebbf50b76d6b727925840f5e8ddcb81cef7a85e84f42b040465fdc3d32`.

## Resultados preliminares

- nenhum diretório do `PATH` é gravável pela identidade `teste`;
- Docker socket existe como `root:docker`, modo `srw-rw----`, sem leitura/escrita por `teste`;
- `/var/lib/docker` não é legível nem gravável por `teste`;
- superfícies cron e unidades systemd listadas não são graváveis por `teste`;
- capabilities observadas: `ping cap_net_raw=ep` e `mtr-packet cap_net_raw=ep`;
- foram enumerados 17 binários SUID/SGID comuns do sistema, sem exploração executada.

### Candidatos que exigem triagem

O script reportou três itens como "root-owned writable":

- `/etc/systemd/system-generators/systemd-gpt-auto-generator`;
- `/etc/systemd/system/sudo.service`;
- `/etc/systemd/user/pipewire-media-session.service`.

Todos apareceram como dispositivos de caractere `crw-rw-rw-`. Isso é compatível com o comportamento de `Path.stat()` ao seguir symlinks cujo destino é `/dev/null`. Portanto, **não são findings até confirmação por `lstat/readlink`**.

Também foi contabilizado `/dev/shm` como localização sensível gravável; por ser tmpfs com sticky bit `drwxrwxrwt`, isso é comportamento esperado e não constitui caminho de escalação por si só.

## Próximo passo

1. validar os três candidatos com `lstat`, `readlink` e `realpath`;
2. inspecionar unidades root e seus `ExecStart` para detectar executáveis/scripts ou diretórios-pai graváveis por `teste`;
3. somente após a triagem decidir se existe candidato real para a fase Attack.
