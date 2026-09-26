# Policies centralizadas dos agentes Wazuh

Este diretório contém as policies de grupos do Wazuh que foram validadas operacionalmente nas VMs do ConectaEduca e depois recuperadas byte a byte do Manager para canonicalização no Git.

## Grupos

| Grupo | Agente esperado | Zona | SHA-256 do `agent.conf` validado |
|---|---|---|---|
| `conectaeduca-dmz` | `001` / `ep125-pucpr` | DMZ | `2d8ef25b84b4f7a0af0faa9c3008fc3101570e7ed7c4c7abed9e5bda6dea376b` |
| `conectaeduca-interna` | `002` / `ep126-pucpr` | interna | `41f69c91175616230592ecad696a08f1b7f8241f6a8eab242f3d84e532a3971b` |

Os hashes acima se referem ao conteúdo dos arquivos, não aos metadados de permissão do filesystem. O hash do grupo `conectaeduca-dmz` foi atualizado no lote WAZ-02 de 26/09/2026, que adiciona as referências às bases Rootcheck versionadas por procedência/digest e define `check_ports=no` por ausência deliberada de `netstat`; veja `conectaeduca-dmz/ROOTCHECK-BASES.md`.

## Regra de mudança

Alterações nestes arquivos não devem ser aplicadas diretamente em produção/laboratório apenas porque foram commitadas. A sequência esperada é:

1. editar em branch;
2. validar com `verify-agent-conf`;
3. comparar colisões com o `ossec.conf` local do agente alvo;
4. aplicar em janela controlada;
5. confirmar `Active` e `synchronized`;
6. validar telemetria dos módulos afetados;
7. registrar evidência sanitizada e SHA-256.

A migração da EP125 exigiu poda prévia de módulos e `localfile` duplicados no `ossec.conf` local antes da associação a `conectaeduca-dmz`.

## Segurança

Os arquivos neste diretório são declarativos e não devem conter senhas, tokens, chaves privadas ou payloads de eventos.

A policy `conectaeduca-interna` referencia o caminho do contrato sanitizado do Ferret em `.runtime/events/dlp.jsonl`; isso não autoriza versionar o conteúdo de `.runtime/`. A policy `conectaeduca-dmz` ignora `deploy/dmz/.runtime` no FIM e coleta apenas o `eve.json` do Suricata como fonte JSON.

Consulte `docs/evidencias/wazuh-ep125-centralizacao-telemetria-20260909.md` para a validação pós-centralização.
