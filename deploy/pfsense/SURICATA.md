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

Além do Suricata no pfSense, a EP125 possui Suricata 8.0.7 ativo em
IDS/detect-only, produzindo `/var/log/suricata/eve.json` em tempo real.
O Wazuh Agent coleta esse arquivo por configuração centralizada do grupo DMZ.

O control-plane do Suricata na EP125 foi validado historicamente via
`/run/suricata/suricata-command.socket`. Após o reboot de 26/09, o socket
deixou de ser criado no runtime atual; por isso o baseline operacional de
logrotate abaixo não depende mais de `suricatasc`.

### EVE JSON para Wazuh — baseline pós-reboot (27/09/2026)

O Wazuh Agent da EP125 coleta `/var/log/suricata/eve.json` como JSON. A
configuração padrão do Suricata 8.0.7 também exportava `event_type=stats`
para o EVE a cada 8 segundos.

Uma amostra controlada de 4.000 eventos mostrou:

```text
STATS_COUNT=1125
STATS_LEAF_MIN=509
STATS_LEAF_MAX=509
STATS_8SEC_RATIO=1.000
STATS_EVENTS_LEAF_GT_256=1125
```

No Wazuh Manager, `analysisd.decoder_order_size` permaneceu no valor padrão
observado de 256. Antes da correção, o Manager registrava continuamente
`Too many fields for JSON decoder.`; em uma janela de três minutos foram
5.478 ocorrências.

A política canônica passa a ser **não exportar `stats` no `eve-log` que o
Wazuh coleta**, preservando o logger global de estatísticas e o
`/var/log/suricata/stats.log`. Não aumentar globalmente
`analysisd.decoder_order_size` para contornar esse fluxo.

A alteração live removeu somente o item direto `- stats:` de
`outputs -> eve-log -> types`, preservou `alert`, passou em
`suricata -T`, reiniciou apenas o Suricata e manteve o Wazuh Agent
conectado. O `stats.log` separado continuou crescendo.

Na EP126, a validação posterior encontrou:

```text
PRE_ERROR_COUNT=5478
TRANSITION_ERROR_COUNT=747
POST_ERROR_COUNT=0
LAST_FIELDLIMIT_ERROR=2026/09/27 00:10:14
FIELDLIMIT_FIX_VALIDATION=PASS
SURICATA_EVE_STATS_ROOT_CAUSE=CONFIRMED_OPERATIONALLY
```

Para reconciliar ou verificar esse estado de forma reproduzível:

```bash
scripts/implantacao/reconciliar_suricata_eve_wazuh.sh check
scripts/implantacao/reconciliar_suricata_eve_wazuh.sh apply
```

O modo `apply` usa parser estrutural por indentação, valida o diff, executa
`suricata -T`, cria backup, aplica atomicamente, reinicia somente o Suricata,
valida ausência de novos `event_type=stats` após o processo novo estar ativo
e executa rollback automático se qualquer gate falhar.

Evidência consolidada:
`docs/evidencias/suricata-eve-stats-wazuh-field-limit-20260927.md`.

### Logrotate seguro — baseline canônico pós-reboot (26/09/2026)

A validação de 17/09/2026 comprovou que `suricatasc -c reopen-log-files`
funcionava naquele runtime quando o command socket estava disponível. Essa
evidência permanece histórica, mas **não é mais o baseline operacional
canônico**.

Após o reboot/change control de 26/09/2026, o Suricata voltou
`active/running` sem criar
`/var/run/suricata/suricata-command.socket`. A política persistente ainda
tentava executar:

```text
/usr/sbin/runuser -u suricata -- /usr/bin/suricatasc -c reopen-log-files
```

O `logrotate` renomeou `eve.json`, o `postrotate` falhou por ausência do
socket e o processo permaneceu escrevendo em `eve.json.1`. O novo
`eve.json` ficou sem receber eventos até a recuperação controlada por
SIGHUP.

Por isso, o baseline canônico da EP125 passa a usar o PID file já declarado
pelo serviço:

```text
postrotate
    /bin/kill -HUP `cat /run/suricata.pid 2>/dev/null` 2>/dev/null || true
endscript
```

Pré-condições operacionais:

- `suricata.service` deve estar `active/running`;
- `/run/suricata.pid` deve existir;
- o conteúdo do PID file deve coincidir com `MainPID` do systemd;
- `suricata -T -c /etc/suricata/suricata.yaml` deve passar antes de qualquer
  mudança persistente.

A correção de 26/09 foi validada com rotação real, não apenas por
config-test:

```text
PREAPPLY_SIGHUP_PROOF=PASS
FORCED_ROTATION_PROOF=PASS
SURICATA_MAINPID_BEFORE=1398
SURICATA_MAINPID_AFTER=1398
SURICATA_NRESTARTS_BEFORE=0
SURICATA_NRESTARTS_AFTER=0
EVE_ROTATED_FILE_PRESENT=YES
SURICATA_FD_REOPENED_NEW_EVE_INODE=YES
SURICATA_STALE_ROTATED_EVE_FD=NO
SURICATA_ACTIVE_AFTER=YES
LOGROTATE_FAILED_STATE_CLEARED=YES
ROLLBACK_EXECUTED=NO
SURICATA_LOGROTATE_FIX=PASS
```

Na prova live, o inode ativo de `eve.json` mudou de `6422843` para
`6422845`; o FD do Suricata acompanhou o novo inode, sem restart do serviço
e sem permanecer em `.1` ou arquivo deleted.

A política anterior baseada em `suricatasc` deve ser considerada
**superseded para a EP125 atual**. Não reintroduzi-la em rebuild, handoff ou
procedimento operacional sem primeiro comprovar a existência e persistência do
command socket após reboot.

Evidências:

- histórica 17/09:
  `docs/evidencias/suricata-logrotate-safe-20260917.md`;
- closeout pós-reboot 26/09:
  `docs/evidencias/ep125-closeout-operacional-pos-reboot-20260926.md`.

## Remote Logging do pfSense

O transporte do Remote Logging do pfSense para o receiver da EP126 foi
confirmado em 16/09/2026 e correlacionado com probes sintéticos em 17/09/2026:

```text
pfSense 192.168.6.49
  -> 192.168.6.50:5514/UDP
  -> Wazuh Manager 514/UDP
```

O teste live de 17/09 gerou três tuplas identificáveis na EP125 e encontrou as
três dentro dos datagramas de Remote Logging recebidos na EP126, com três
ocorrências de cada:

```text
SYSLOG_UDP_DATAGRAM_BLOCKS=15
MATCHED_PROBE_INDICES=[1, 2, 3]
PFSENSE_REMOTE_SYSLOG_LIVE=CONFIRMADO
CORRELACAO_INGESTAO_RECEIVER=CONFIRMADA
PASS=5
WARN=0
FAIL=0
FINAL=PASS
```

Por isso o estado documentado passou a ser:

```text
PFSENSE_REMOTE_SYSLOG=TRANSPORTE_CORRELACIONADO_CONFIRMADO
CORRELACAO_RECEIVER_HOST=CONFIRMADA
WAZUH_DECODER_ALERT_ARCHIVE=PENDENTE
SIEM_E2E_COMPLETO=PENDENTE
```

O gate restante é interno ao Wazuh: decoder/regra/archive/alert/indexação dos
mesmos eventos. A captura correlacionada comprova o transporte até o receiver de
host, mas não é usada para declarar E2E completo do SIEM.

O checkpoint `40-checkpoint-logging.sh` não registra mais o forwarding como
adiado. Ele permanece somente leitura, não lê `/conf/config.xml`, e verifica o
estado runtime já renderizado do syslog para o destino configurado por
`CONECTAEDUCA_WAZUH_MANAGER_BIND_ADDRESS` e
`CONECTAEDUCA_WAZUH_SYSLOG_PORT` (ou pelos argumentos equivalentes do script).

Evidência: `docs/evidencias/pfsense-wazuh-live-receiver-20260917.md`.
Consulte `deploy/pfsense/LOGGING-WAZUH.md` para o estado operacional e o
procedimento de reprodução.
