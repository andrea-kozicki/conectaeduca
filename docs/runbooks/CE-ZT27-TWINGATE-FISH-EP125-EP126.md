# CE-ZT27 — Diagnóstico operacional do Twingate nas três máquinas

**Estado:** script operacional de diagnóstico **somente leitura**, sem alteração de Connectors, redes, política, Docker ou pfSense. Não é um reparo automático e não comprova o isolamento final.

**Contexto observado em 04/11/2026:** os Connectors da EP125 e da EP126 estão `DEAD_HEARTBEAT_TOO_OLD` na API; os testes PubNub `/time/0` falham em dois FQDNs nas VMs (curl 35) mas passam no openSUSE; causa da interrupção não identificada. A Remote Network, grupos e políticas já existem. Não gerar tokens novos nem recriar recursos para tentar resolver um reset TCP/TLS.

## Como executar pela branch PR #213 (sem trocar a branch de trabalho)

Na **EP125**:
```bash
cd /opt/conectaeduca
git fetch --no-tags origin feat/twingate-dmz-connector-preflight-20261030
git show FETCH_HEAD:scripts/twingate/ce_zt27_operacional.py > /tmp/ce_zt27_operacional.py
python3 /tmp/ce_zt27_operacional.py --role ep125
```

Na **EP126**:
```bash
cd /opt/conectaeduca
git fetch --no-tags origin feat/twingate-dmz-connector-preflight-20261030
git show FETCH_HEAD:scripts/twingate/ce_zt27_operacional.py > /tmp/ce_zt27_operacional.py
python3 /tmp/ce_zt27_operacional.py --role ep126
```

No **openSUSE** (Fish, fora da VPN institucional, se possível):
```fish
curl -fsSL --proto '=https' --tlsv1.2 \
  'https://raw.githubusercontent.com/andrea-kozicki/conectaeduca/feat/twingate-dmz-connector-preflight-20261030/scripts/twingate/ce_zt27_operacional.py' \
  -o /tmp/ce_zt27_operacional.py
python3 /tmp/ce_zt27_operacional.py --role opensuse
```

Se o `git fetch` não tiver permissão ou a VM não conseguir alcançar GitHub, **não** mudar de branch nem forçar pull; coletar o script pelo processo de transferência aprovado pela instituição. Para execução imutável, piná-lo ao SHA de commit da revisão aprovada.

## O que o script faz
- Identifica `whoami`, timestamp e hostname; falha se o papel não combinar com a máquina.
- Nas VMs, consulta somente o Container esperado via `docker inspect`, e conta padrões de erros dos últimos 30 minutos sem imprimir os logs brutos ou valores de `.env`.
- Faz GET HTTPS `/time/0` nos três endpoints PubNub e verifica `/api/v1/public_keys` do Controller, com validação TLS e timeout. Para os dois endpoints que falham, repete com HTTP/1.1 para comparar transporte. **Não** usa `curl -k`.
- No openSUSE, lê `twingate status` e classifica a disponibilidade de recursos sem imprimir a lista.
- Produz um resumo apropriado a evidência; saída `2` indica falha HTTP/TLS em algum endpoint, `4` máquina diferente do papel e `0` significa apenas conectividade HTTPS básica observada (não Connector `ALIVE`).

Se a conexão das VMs continuar falhando enquanto o openSUSE passar, o próximo passo **não** é reinstalar ou reiniciar o Connector, mas enviar os FQDNs, horários, códigos e IPs de destino ao suporte da rede, solicitando correlação dos logs de egress/TLS upstream. O suporte deve investigar a presença de filtragem e inspeção institucionais, inclusive fora das regras personalizadas do pfSense.

### Auditoria administrativa complementar

Use `python3 scripts/twingate/ce_twingate_reconcile.py` no clone da branch quando desejar conferir redes, grupos, recursos, políticas e Connectors via API Read only. Essa consulta solicita o token local sem o expor; nunca o publique.

**Critério de sucesso final:** ambos os Connectors em `ALIVE`, heartbeats avançando, resource acessível com MFA ao perfil permitido e negativa ao não autorizado; teste do Wazuh/APP sem FortiClient e sem vazamento de credenciais. Um teste HTTPS `200` isoladamente não satisfaz o critério.
