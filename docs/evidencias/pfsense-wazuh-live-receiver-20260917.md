# Evidência — pfSense Remote Logging → receiver Wazuh — 17/09/2026

## Objetivo

Correlacionar um estímulo sintético identificável gerado na EP125 com os datagramas de Remote Logging enviados pelo pfSense ao receiver publicado na EP126, sem persistir payload bruto de syslog.

Esta evidência comprova o **transporte correlacionado até o receiver de host `192.168.6.50:5514/UDP`**. Ela não declara, por si só, que o Wazuh Manager decodificou, arquivou, promoveu a alerta ou indexou esses eventos.

## Topologia observada

```text
EP125 192.168.6.34
  -> pfSense / regra de bloqueio LAN33
  -> Remote Logging com origem 192.168.6.49
  -> EP126 192.168.6.50:5514/UDP
  -> publicação Docker para Wazuh Manager 514/UDP
```

O listener host `192.168.6.50:5514/UDP` estava presente e a rota da EP126 para o pfSense usava `eth0` com origem `192.168.6.50`.

## Janela de captura

```text
CAPTURE_START_UTC=2026-09-17T22:17:31.196052+00:00
CAPTURE_END_UTC=2026-09-17T22:18:59.742454+00:00
CAPTURE_DURATION_SECONDS=90
CAPTURE_WRAPPER_RC=124
RAW_TCPDUMP_PERSISTED=0
```

`124` é o retorno esperado do GNU `timeout` ao encerrar a janela controlada.

Filtro BPF utilizado:

```text
src host 192.168.6.49 and dst host 192.168.6.50 and udp dst port 5514
```

## Probes correlacionados

O gerador na EP125 produziu três tentativas TCP sem payload, com source/destination ports fixos:

```text
192.168.6.34:47101 -> 192.168.6.50:62101
192.168.6.34:47102 -> 192.168.6.50:62102
192.168.6.34:47103 -> 192.168.6.50:62103
```

A captura do Remote Logging na EP126 encontrou:

```text
SYSLOG_UDP_DATAGRAM_BLOCKS=15
MATCHED_PROBE_INDICES=[1, 2, 3]
PROBE_1_MATCHES=3
PROBE_2_MATCHES=3
PROBE_3_MATCHES=3
```

Cada uma das três tuplas sintéticas apareceu três vezes dentro dos datagramas syslog recebidos do pfSense. Os blocos correlacionados foram representados apenas por hashes SHA-256 no relatório operacional; o payload bruto não foi persistido.

## Resultado

```text
PFSENSE_REMOTE_SYSLOG_LIVE=CONFIRMADO
CORRELACAO_INGESTAO_RECEIVER=CONFIRMADA
PASS=5
WARN=0
FAIL=0
FINAL=PASS
```

Portanto, o gate de **transporte correlacionado pfSense → receiver host EP126** está fechado.

O próximo gate permanece separado:

```text
WAZUH_DECODER_ALERT_ARCHIVE=PENDENTE
SIEM_E2E_COMPLETO=PENDENTE
```

O Threat Hunting não apresentou os probes como alertas indexados na verificação realizada. Como o Manager estava com `logall=no` e `logall_json=no`, ausência em `alerts.json`/`archives.json` não pode ser reinterpretada como ausência de transporte. A próxima etapa deve validar decoder/regra/archive/indexação sem confundir o transporte já comprovado com a camada analítica do SIEM.
