# Notas de runtime Bacula

Os arquivos `compose.director-hardening.yml` e `compose.storage-hardening.yml`
são overlays não sensíveis. Eles devem ser combinados com os Composes
declarativos existentes do Director/PgBouncer e do Storage, respectivamente.

A materialização live desta validação foi promovida com containers substitutos
e rollback dos containers originais preservado até o gate final. Os arquivos
de configuração Bacula e o material TLS não foram alterados.

Tmpfs são usados somente para diretórios efêmeros necessários ao daemon. O bootstrap root ajusta mode/owner dos mountpoints e executa o Bacula com `-P`; o próprio Bacula abandona root para UID 100/GID 101. O processo final fica sem capabilities efetivas/permitted/inheritable/ambient, e o Docker/Compose supervisiona o PID 1.
`/backup` continua em volume persistente e o socket PgBouncer continua em
volume dedicado.

A configuração root do container existe apenas para bootstrap. Os daemons
executam efetivamente como `bacula` e terminam com CapEff zero.
