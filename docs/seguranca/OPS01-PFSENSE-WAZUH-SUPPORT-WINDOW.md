# OPS-01 — janela assistida pfSense → Wazuh

## Objetivo

Executar, com o suporte institucional, o único probe pós-reboot ainda pendente
do OPS-01: gerar um evento identificável no pfSense e comprovar sua correlação
na EP126/Wazuh sem contornar o RBAC acadêmico.

## Responsabilidades

### Suporte

- executar somente a ação necessária no pfSense para produzir um evento
  identificável;
- informar o marcador usado ou permitir que ele seja combinado previamente;
- não alterar regras, aliases, NTP, NAT ou políticas além do necessário para o
  probe acordado.

### Operadora do laboratório

Antes da janela:

- acessar a EP126;
- confirmar que o Wazuh Manager está disponível;
- executar o readiness sem marcador;
- manter o horário UTC registrado;
- não alterar runtime apenas para obter PASS.

Durante a janela:

1. combinar um marcador não sensível, por exemplo
   `CE-PF-YYYYMMDD-HHMM`;
2. solicitar ao suporte a geração do evento no pfSense;
3. imediatamente executar o correlacionador com o marcador;
4. preservar TXT + SHA-256;
5. não repetir o probe se já houver correlação inequívoca.

## Comandos na EP126

Readiness:

```bash
cd /opt/conectaeduca
python3 scripts/evidencias/pfsense_wazuh_postreboot_readonly.py
```

Fechamento com marcador já produzido externamente:

```bash
python3 scripts/evidencias/pfsense_wazuh_postreboot_readonly.py \
  --marker 'CE-PF-YYYYMMDD-HHMM'
```

## Critério de fechamento

```text
HOST_UDP5514_EXACT=PASS
DOCKER_ACCESS=PASS
MANAGER_HEALTH=PASS
DOCKER_514_TO_5514=PASS
PFSENSE_RECEIVER_CONFIG=PASS
PFSENSE_WAZUH_POSTREBOOT=CORRELATED_ALERT_PASS
RUNTIME_CONFIG_MUTATIONS=0
SERVICE_RESTARTS=0
NETWORK_TRAFFIC_INJECTION=0
RAW_SYSLOG_PERSISTED=0
FULL_LOG_PERSISTED=0
```

Se o readiness falhar antes do probe, não pedir ao suporte para repetir o
evento até o bloqueio ser entendido.

## Janela sugerida

Reservar 30 minutos. O probe em si deve ser curto; a folga existe para acesso,
alinhamento do marcador e coleta de evidência.

## Privacidade

Não persistir payload bruto de syslog na evidência. O helper registra somente
metadados sanitizados e hash do `full_log`.
