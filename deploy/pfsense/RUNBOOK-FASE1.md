# CE-PFSENSE — Runbook fase 1

```text
00-preflight-pfsense.sh
        ↓
10-checkpoint-interfaces.sh
        ↓
configurar/verificar firewall e NAT
        ↓
20-checkpoint-firewall.sh
        ↓
instalar/configurar Suricata pela WebGUI
        ↓
30-checkpoint-suricata.sh
        ↓
40-checkpoint-logging.sh
        ↓
90-coletar-evidencias.sh
```

Instalar somente o pacote adicional Suricata.

Não instalar Git, Docker, MariaDB, Nginx, PHP ou Wazuh no firewall.
Primeiro prove rede/firewall; depois IDS/alert-only; IPS/bloqueio somente após validar.
