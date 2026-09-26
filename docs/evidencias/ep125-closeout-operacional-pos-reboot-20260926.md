# EP125 — closeout operacional pós-reboot — 26/09/2026

> **Classificação:** EVIDÊNCIA  
> **Escopo:** OPS-01 / EP125 pós-reboot  
> **Objetivo:** registrar o estado operacional observado após o change control de kernel, recuperação do WAF, correção do logrotate do Suricata e pente-fino operacional.

## Resumo executivo

A EP125 foi submetida a validações pós-reboot com foco em hardening, integridade de runtime e comportamento operacional.

O estado consolidado é **operacionalmente saudável, sem bloqueador identificado**, com duas pendências residuais delimitadas antes do freeze:

1. sincronismo de relógio/NTP não estabelecido;
2. cobertura do rootcheck do Wazuh Agent precisa de validação direcionada.

## Change control / kernel

- kernel ativo: `6.8.0-142-generic`;
- `reboot-required`: ausente;
- `KRNL-5830`: removido da coleta Lynis pós-reboot;
- kernels realmente instalados: `6.8.0-142` e `6.8.0-138`;
- `6.8.0-138` mantido como fallback pré-freeze;
- resíduos de pacotes de kernel em estado `config-files` não foram removidos automaticamente.

## WAF / containers DMZ

- `conectaeduca-dmz-waf-1`: running/healthy, restart count 0;
- `conectaeduca-dmz-nginx-1`: running/healthy, restart count 0;
- `conectaeduca-dmz-php-1`: running/healthy, restart count 0;
- WAF `/healthz`: HTTP 200;
- aplicação HTTPS: HTTP 200;
- Git: branch `main`, working tree limpo.

A consulta corrigida `docker events --since 24h --until 0s` não encontrou eventos de lifecycle classificados como `die`, `stop`, `restart` ou `health_status: unhealthy`. O tráfego observado no arquivo de eventos era majoritariamente `exec_create`, `exec_start` e `exec_die` de healthchecks, com exit code 0.

## Suricata / logrotate

Foi encontrada uma falha operacional real após o reboot: o `logrotate.service` renomeava `eve.json`, mas o postrotate tentava executar `suricatasc -c reopen-log-files`. O unix socket esperado não existia e o Suricata continuava mantendo FD em `eve.json.1`.

A recuperação e a correção persistente foram validadas. O baseline canônico
foi reconciliado em `deploy/pfsense/SURICATA.md`: a evidência de 17/09 com
`suricatasc` permanece histórica, mas a política operacional atual da EP125
passa a usar SIGHUP via `/run/suricata.pid`.

- runtime recuperado por SIGHUP;
- MainPID preservado;
- `NRestarts` permaneceu 0;
- FD migrou para o inode atual de `eve.json`;
- nenhum FD stale permaneceu em `.1` ou arquivo deleted;
- postrotate alterado para SIGHUP via `/run/suricata.pid`;
- rotação real forçada: PASS;
- `eve.json.1` criado;
- novo `eve.json` aberto pelo processo no inode novo;
- `suricata -T` pós-change: PASS;
- `logrotate.service` deixou de permanecer em estado failed;
- rollback não foi necessário.

No Operational Readiness posterior, o drop de captura do Suricata ficou em aproximadamente 0,066%.

## Recursos / host

Operational Readiness observado:

- root filesystem: aproximadamente 14% utilizado;
- PSI memória: sem pressão relevante;
- PSI I/O: sem pressão relevante;
- processos em D-state: 0;
- zombies: 0;
- OOM / erros críticos de I/O / hung tasks: não observados;
- erros `eth0`: 0;
- drops `eth0`: 0;
- conntrack: aproximadamente 0,02% de utilização;
- Bacula FD: ativo; config-test em `/opt/bacula/etc/bacula-fd.conf`: PASS;
- auditd: ativo;
- SSH listener: presente;
- Wazuh Agent: ativo;
- conexão EP125 -> EP126:1514/TCP: ESTABLISHED.

## Pendência residual 1 — NTP

A Fase NTP dedicada confirmou que o problema não está em DNS, rota ou firewall local da EP125.

A triagem confirmou:

```text
CanNTP=yes
NTP=yes
NTPSynchronized=no
```

`systemd-timesyncd.service` está ativo, porém `timedatectl timesync-status` registrou:

```text
Server: ntp.ubuntu.com
Packet count: 0
```

O journal apresenta timeouts repetidos para os servidores de `ntp.ubuntu.com` na porta UDP/123. DNS resolveu quatro IPv4; as rotas para esses endereços usam o gateway pfSense `192.168.6.33`; o firewall local mantém OUTPUT ACCEPT. Três probes SNTP diretos em UDP/123 resultaram em timeout.

**Classificação:** pendência operacional real localizada fora da EP125; caminho pfSense/upstream/institucional é o próximo domínio de investigação.

Impacto principal: correlação temporal de eventos entre EP125, EP126, pfSense e Wazuh.

## Pendência residual 2 — Wazuh rootcheck

A Fase Rootcheck dedicada confirmou **gap real de cobertura**, sem falha do runtime geral do agente.

Estado observado:

- Wazuh Agent 4.14.7 ativo e habilitado;
- `wazuh-syscheckd -t`: PASS;
- `wazuh-logcollector -t`: PASS;
- TCP `192.168.6.34 -> 192.168.6.50:1514`: ESTABLISHED;
- `netstat`: ausente;
- `ss`: presente;
- log rootcheck: `No rootcheck_files file configured`;
- log rootcheck: `No rootcheck_trojans file configured`;
- log syscheckd: `netstat not available. Skipping port check`.

A configuração central versionada em `deploy/interna/wazuh/groups/conectaeduca-dmz/agent.conf` habilita `check_files`, `check_trojans` e `check_ports`, mas não referencia `rootkit_files` nem `rootkit_trojans`. O diretório versionado do grupo também não contém essas bases.

O WARN de parse XML do coletor foi classificado como limitação do script: o arquivo efetivo do Wazuh não é um XML de raiz única para uso direto com `ElementTree`; o config-test nativo do Wazuh é a validação autoritativa e passou.

**Classificação:** gap de cobertura confirmado. A correção deve ser feita pelo baseline/grupo centralizado do Wazuh e sincronizada pelo Manager; não é recomendável aplicar hotfix local isolado na EP125. A ausência de `netstat` também reduz o check de portas e deve ser tratada como decisão de change control (instalar `net-tools` ou desabilitar/documentar especificamente esse subcheck).

O item canônico `WAZ-02` em `docs/BACKLOG-TECNICO.md` foi reaberto como
`HOST_GATE` em 26/09/2026, com fechamento condicionado à correção
manager-side das bases do Rootcheck e à decisão explícita sobre `check_ports`.

## Wazuh Agent buffer

Foi observado anteriormente um pico curto de buffer em 90%, retornando para menos de 70% em aproximadamente três segundos. Não há evidência de congestionamento persistente.

## Boundaries conhecidos

Não tratados como regressão da aplicação:

- cloud-init / DataSourceNone do ambiente institucional;
- sockets auxiliares SSSD, mantendo o serviço principal funcional;
- ICMP para EP126 não é requisito, pois TCP/1514 permanece estabelecido;
- warning de ssl_stapling do WAF por cadeia local;
- warning Docker sobre fsverity não suportado;
- sintaxe antiga de `security_opt` com `:` registrada como higiene futura.

## Evidência residual

```text
conectaeduca-operational-residual-ep125-20260926-200019Z.tar.gz
SHA256=4f6a349eb1ef006d84b471265210c7c14ad51afa0b843c407618bfdb69d68ef2
```

Manifesto interno: **20/20 arquivos validados por SHA-256**.

Resumo:

```text
PASS_COUNT=2
WARN_COUNT=1
INFO_COUNT=2

WARN CLOCK_SYNC not_synchronized
PASS DOCKER_LIFECYCLE_ANOMALIES matches=0
PASS DOCKER_PS rc=0
```

## Estado de saída

```text
EP125_RUNTIME_CRITICAL_BLOCKER=NO
EP125_DOCKER_LIFECYCLE_ANOMALY=NO
EP125_SURICATA_LOGGING=RECOVERED_AND_FIXED
EP125_NTP_SYNC=PENDING
EP125_WAZUH_ROOTCHECK_COVERAGE=GAP_CONFIRMED_MANAGER_SIDE_REMEDIATION_PENDING
NEXT=EP126_PFSENSE_SYSLOG_REVALIDATION_AND_WAF_RULE_110300_CORRELATION
```

Esta evidência é datada. As mudanças persistentes que dela decorrem foram
reconciliadas nos documentos canônicos correspondentes: o logrotate do Suricata
em `deploy/pfsense/SURICATA.md` e a pendência Rootcheck em
`docs/BACKLOG-TECNICO.md`.
