# Evidência — Suricata logrotate seguro na EP125 — 17/09/2026

## Objetivo

Substituir o `postrotate` baseado em SIGHUP por reabertura de logs via control-plane do Suricata, sem executar `/usr/bin/suricatasc` como root e sem reiniciar o serviço.

## Baseline

Host observado: `ep125-pucpr`.

Antes do APPLY:

```text
Suricata service: active
MainPID: 589287
eve.json: suricata:suricata 0644
suricata-command.socket: suricata:suricata 0660
/usr/bin/suricatasc: suricata:root 0755
```

O MD5 de `/usr/bin/suricatasc` coincidiu com o valor registrado pelo pacote `suricata`:

```text
SURICATASC_MD5_EXPECTED=b2a60b947cf831184ff4b0a9be395ad6
SURICATASC_MD5_ACTUAL=b2a60b947cf831184ff4b0a9be395ad6
```

O comando `suricatasc` foi exercitado como usuário `suricata`; `uptime` e `command-list` retornaram `OK`, e `reopen-log-files` estava presente na lista de comandos suportados.

## Política promovida

A política anterior consultava o `MainPID` e enviava `kill -HUP`. A política persistente validada passou a usar:

```text
postrotate
    /usr/sbin/runuser -u suricata -- /usr/bin/suricatasc -c reopen-log-files >/dev/null || exit 1
endscript
```

O binário é `suricata`-owned no runtime acadêmico. Por isso o desenho evita executá-lo em contexto root: o `postrotate` força a identidade `suricata` por `runuser`.

## Tentativa v1 e rollback

A primeira tentativa de rotação controlada usou a opção curta `-s` do `logrotate` para um state isolado. A política institucional interpretou textualmente a sequência como uso da opção `-s` do `sudo` e bloqueou o comando antes da rotação.

O helper restaurou a política anterior a partir do backup root-only e executou `reopen-log-files` como `suricata`. Não houve restart do serviço.

A versão v2 substituiu a opção curta por `--state`, mantendo o state de teste isolado sem ambiguidade para o wrapper institucional.

## APPLY v2 — rotação controlada

A execução validada usou:

```text
sudo -- /usr/sbin/logrotate -v -f --state <state-isolado> /etc/logrotate.d/conectaeduca-suricata-eve
```

O `logrotate` retornou `RC=0`, renomeou `eve.json` para `eve.json.1`, criou um novo `eve.json` como `suricata:suricata 0644` e executou o `postrotate` novo.

### Inodes

```text
OLD_EVE_INODE=6434820
NEW_EVE_INODE=6433823
ROTATED_EVE_INODE=6434820
```

Isso prova que `eve.json.1` preservou o inode anterior e que o arquivo ativo passou a ser um inode novo.

### Continuidade do Suricata

```text
SURICATA_MAINPID_UNCHANGED=589287
SURICATA_SERVICE_RESTARTED=0
```

O Suricata reabriu o novo inode sem restart.

### Continuidade da coleta Wazuh

Após a rotação, `wazuh-logcollec` passou a manter descritor para o novo `eve.json`, junto com `Suricata-Main`:

```text
WAZUH_FOLLOWS_NEW_INODE=1
```

O arquivo ativo também recebeu novos dados:

```text
EVE_SIZE_T0=0
EVE_SIZE_T5=26952
```

## Resultado

```text
SURICATA_LOGROTATE_RESULT=REOPEN_LOG_FILES_PASS
CONFIG_CHANGED=1
ROTATION_EXECUTED=1
ROLLBACK_USED=0
SURICATASC_EXECUTED_AS_ROOT=0
SURICATA_SERVICE_RESTARTED=0
PASS=19
WARN=2
FAIL=0
INFO=0
FINAL=WARN
```

Os dois `WARN` pertencem ao preflight: ownership observado de `suricatasc` (`suricata:root`) e detecção inicial da política antiga ainda baseada em SIGHUP. Eles não representam falha do APPLY.

SHA-256 do relatório de evidência recebido:

```text
7ead8bc06836d00c323f976aac48b412e20dfb77e774829b78b2b4c0c15ccefd
```

## Conclusão

O gate de logrotate da EP125 está encerrado funcionalmente. A política persistente deixou de usar SIGHUP, não executa `suricatasc` como root, não reinicia o Suricata e foi validada por rotação real com continuidade do Suricata e do Wazuh no novo inode.
