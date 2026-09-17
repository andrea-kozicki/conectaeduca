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
5. `compose.director-pgbouncer.yml`;
6. `compose.storage-emulado.yml` — último overlay, substitui somente o destino `/backup` pelo bind dedicado.

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

O `compose.storage-emulado.yml` deve ser aplicado **depois** dos overlays de
hardening e PgBouncer. Ele não substitui esses overlays: apenas troca a origem
do mount `/backup` para `${CONECTAEDUCA_BACULA_STORAGE_PATH:-/srv/conectaeduca-backup/bacula/volumes}`.
O named volume `conectaeduca-bacula_storage-data` pode permanecer preservado no
host como rollback, mas não é o destino ativo quando a composição canônica
inclui o overlay de Storage emulado.

Antes da primeira ativação desse overlay em um host que ainda use o named volume
legado, é obrigatório executar `preparar_storage_emulado.py check` e, após o
preflight, `preparar_storage_emulado.py apply`. O helper versionado quiesce
Director/Storage, recalcula o fingerprint da mídia com o source parado, copia
para o bind preservando metadados, exige igualdade de fingerprint e só então
recria o Storage. Target divergente, jobs ativos ou fingerprint divergente
bloqueiam a promoção; o named volume legado nunca é removido pelo helper.

A materialização live desta validação foi promovida com containers substitutos
e rollback dos containers originais preservado até o gate final. Os arquivos
de configuração Bacula e o material TLS não foram alterados.

Tmpfs são usados somente para diretórios efêmeros necessários ao daemon. O bootstrap root ajusta mode/owner dos mountpoints e executa o Bacula com `-P`; o próprio Bacula abandona root para UID 100/GID 101. No Director, `/run/bacula` permanece `bacula:bacula 0750`, enquanto `/var/lib/bacula` usa `root:bacula 0770`. Assim, o bootstrap root sem `CAP_DAC_OVERRIDE` mantém acesso ao WorkingDirectory e o daemon `bacula` continua com R/W/X após a queda de privilégios. O processo final fica sem capabilities efetivas/permitted/inheritable/ambient, e o Docker/Compose supervisiona o PID 1.
O socket PgBouncer continua em volume dedicado e o destino ativo de `/backup`
é o bind do Storage emulado quando o sexto overlay está aplicado.

A configuração root do container existe apenas para bootstrap. Os daemons
executam efetivamente como `bacula` e terminam com CapEff zero.
