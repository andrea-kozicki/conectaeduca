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

A política de logrotate existente ainda usa SIGHUP no `postrotate`.
A migração para `suricatasc -c reopen-log-files` permanece pendente de um gate
de segurança porque o conteúdo de `/usr/bin/suricatasc` coincide com o MD5 do
pacote instalado, porém o ownership observado é `suricata:root`.

Não usar o binário em contexto privilegiado de logrotate enquanto esse gate não
for resolvido.

## Remote Logging do pfSense

O Remote Logging do pfSense para o Wazuh foi validado E2E em 16/09/2026:

```text
pfSense 192.168.6.49
  -> 192.168.6.50:5514/UDP
  -> Wazuh Manager 514/UDP
```

Foram observados 10 datagramas no teste e houve indício de ingestão em
`alerts.json`.

Consulte `deploy/pfsense/LOGGING-WAZUH.md` para o estado operacional e o
procedimento de reprodução.
