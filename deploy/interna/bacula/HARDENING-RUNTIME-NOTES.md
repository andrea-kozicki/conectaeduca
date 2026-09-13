# Notas de runtime Bacula

Os arquivos `compose.director-hardening.yml` e `compose.storage-hardening.yml`
são overlays não sensíveis. A composição canônica suportada exige
`compose.vm.yml` como **base obrigatória**; é esse arquivo que fornece os
controles e recursos comuns que não devem ser duplicados nos overlays,
incluindo `security_opt: no-new-privileges:true`.

Para o runtime Bacula da EP126, os arquivos devem ser combinados nesta ordem:

1. `compose.vm.yml` — base obrigatória;
2. `compose.postgresql-hardening.yml`;
3. `compose.director-hardening.yml`;
4. `compose.storage-hardening.yml`;
5. `compose.director-pgbouncer.yml`.

Os overlays de Director/Storage e Director/PgBouncer **não são suportados
isoladamente nem como par substituto da base**. A remoção de uma diretiva
duplicada de `security_opt` nesses overlays não remove o controle do runtime:
ele é herdado da base obrigatória `compose.vm.yml`.

Para o Director, a fonte canônica de `/etc/bacula-runtime` é o volume
externo `conectaeduca-bacula-director-config`, declarado em
`compose.director-pgbouncer.yml`. O `bacula-dir.conf` promovido nesse
volume permanece `root:root 0600`: o bootstrap inicia como root apenas
para abrir a configuração e o daemon abandona privilégios para
`bacula` (UID 100/GID 101). O arquivo baseline root-only em `.runtime`
é preservado como fonte de rollback e não é uma segunda fonte de mount.
Por isso, `compose.vm.yml` não deve adicionar um bind aninhado de
`bacula-dir.conf` sobre o volume `director-config`.

Na composição canônica, `compose.director-hardening.yml` é a única
fonte de `entrypoint`/`command` do Director persistente. O overlay
`compose.director-pgbouncer.yml`, embora aplicado depois, limita-se a
imagem, volumes, rede e socket e não deve redefinir o bootstrap, pois
isso sobrescreveria o preparo dos tmpfs definido pelo hardening.

A materialização live desta validação foi promovida com containers substitutos
e rollback dos containers originais preservado até o gate final. Os arquivos
de configuração Bacula e o material TLS não foram alterados.

Tmpfs são usados somente para diretórios efêmeros necessários ao daemon. O bootstrap root ajusta mode/owner dos mountpoints e executa o Bacula com `-P`; o próprio Bacula abandona root para UID 100/GID 101. No Director, `/run/bacula` permanece `bacula:bacula 0750`, enquanto `/var/lib/bacula` usa `root:bacula 0770`. Assim, o bootstrap root sem `CAP_DAC_OVERRIDE` mantém acesso ao WorkingDirectory e o daemon `bacula` continua com R/W/X após a queda de privilégios. O processo final fica sem capabilities efetivas/permitted/inheritable/ambient, e o Docker/Compose supervisiona o PID 1.
`/backup` continua em volume persistente e o socket PgBouncer continua em
volume dedicado.

A configuração root do container existe apenas para bootstrap. Os daemons
executam efetivamente como `bacula` e terminam com CapEff zero.
