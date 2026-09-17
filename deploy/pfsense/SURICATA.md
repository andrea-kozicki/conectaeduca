# Suricata no CE-PFSENSE — fase 1

Instalar pelo gerenciador oficial:
1. `System > Package Manager > Available Packages`;
2. procurar `Suricata`;
3. `Install`;
4. confirmar.

Não habilite repositórios FreeBSD externos.

Primeira configuração:
1. escolha a interface real a monitorar;
2. confira pela rede/endereço, não apenas por `LAN`/`OPT`;
3. comece em IDS/alert-only;
4. habilite uma fonte gratuita de regras oferecida pelo pacote, quando disponível;
5. atualize as regras;
6. habilite alertas/logs e EVE JSON quando a versão oferecer;
7. inicie a interface Suricata;
8. rode `30-checkpoint-suricata.sh`;
9. gere tráfego de teste e rode `40-checkpoint-logging.sh`.

Somente depois considere IPS/bloqueio.

## Estado observado nas VMs acadêmicas

Além do Suricata no pfSense, a EP125 possui Suricata 8.0.6 ativo em
IDS/detect-only, produzindo `/var/log/suricata/eve.json` em tempo real.
O Wazuh Agent coleta esse arquivo por configuração centralizada do grupo DMZ.

O control-plane do Suricata na EP125 foi validado via
`/run/suricata/suricata-command.socket`, e o comando
`reopen-log-files` é anunciado pelo próprio runtime.

### Logrotate seguro — validado em 17/09/2026

A política anterior usava SIGHUP no `postrotate`. O gate foi encerrado com
migração para:

```text
/usr/sbin/runuser -u suricata -- /usr/bin/suricatasc -c reopen-log-files
```

O conteúdo de `/usr/bin/suricatasc` coincide com o MD5 registrado pelo pacote
instalado e o arquivo observado é `suricata:root 0755`, sem escrita por grupo ou
outros. Por isso o binário **não é executado como root** no `postrotate`; ele é
invocado como o próprio usuário `suricata`.

A validação live da EP125 comprovou:

```text
SURICATA_LOGROTATE_RESULT=REOPEN_LOG_FILES_PASS
WAZUH_FOLLOWS_NEW_INODE=1
SURICATASC_EXECUTED_AS_ROOT=0
SURICATA_SERVICE_RESTARTED=0
ROLLBACK_USED=0
ROTATION_EXECUTED=1
FAIL=0
```

Na rotação controlada, o inode ativo de `eve.json` mudou de `6434820` para
`6433823`, enquanto `eve.json.1` preservou o inode `6434820`. O MainPID do
Suricata permaneceu `589287`, o Suricata abriu o novo inode, o
`wazuh-logcollector` acompanhou o novo arquivo e o `eve.json` cresceu de 0 para
26952 bytes em cinco segundos. Assim, a política persistente não depende mais de
SIGHUP para reabrir logs.

A primeira tentativa do helper foi bloqueada pela política institucional porque
a opção curta `-s` do `logrotate` foi interpretada pelo wrapper como se fosse a
opção `-s` do `sudo`. O rollback restaurou a política anterior sem reiniciar o
Suricata. A versão validada passou a usar `logrotate --state`, evitando essa
ambiguidade.

Evidência consolidada em
`docs/evidencias/suricata-logrotate-safe-20260917.md`.

## Remote Logging do pfSense

O transporte do Remote Logging do pfSense para o Wazuh foi confirmado em
16/09/2026:

```text
pfSense 192.168.6.49
  -> 192.168.6.50:5514/UDP
  -> Wazuh Manager 514/UDP
```

Foram observados 10 datagramas no teste. Também houve 4 correspondências em
`alerts.json`, mas elas não foram correlacionadas por timestamp/counter aos
datagramas capturados. Por isso o estado documentado é:

```text
PFSENSE_REMOTE_SYSLOG=TRANSPORTE_CONFIRMADO
CORRELACAO_INGESTAO=PENDENTE
```

O checkpoint `40-checkpoint-logging.sh` não registra mais o forwarding como
adiado. Ele permanece somente leitura, não lê `/conf/config.xml`, e verifica o
estado runtime já renderizado do syslog para o destino configurado por
`CONECTAEDUCA_WAZUH_MANAGER_BIND_ADDRESS` e
`CONECTAEDUCA_WAZUH_SYSLOG_PORT` (ou pelos argumentos equivalentes do script).

Consulte `deploy/pfsense/LOGGING-WAZUH.md` para o estado operacional e o
procedimento de reprodução.
