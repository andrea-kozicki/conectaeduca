# Evidência — Suricata EP125 → Wazuh ponta a ponta (07/09/2026)

## Objetivo
Registrar a implantação do Suricata na EP125 e a integração ponta a ponta com o Wazuh Manager/Indexer/Dashboard na EP126, sem expor segredos.

## Resultado consolidado
- Suricata 8.0.6 instalado na EP125 e executando via AF_PACKET em `eth0`.
- EP125: `192.168.6.34/28`; rede diretamente conectada: `192.168.6.32/28`.
- Regras ET Open carregadas em `/var/lib/suricata/rules/suricata.rules`.
- Conjunto observado: 68.631 linhas, 52.677 regras `alert`.
- `suricata -T -c /etc/suricata/suricata.yaml` aprovado.
- `eve.json` ativo e produzindo alertas.
- Wazuh Agent 4.14.7 na EP125 configurado para coletar `/var/log/suricata/eve.json` como JSON.
- `wazuh-logcollector -t` aprovado antes do restart.
- Wazuh Agent reiniciado com sucesso e sessão TCP para `192.168.6.50:1514` mantida.
- Manager em container na EP126 recebeu e persistiu alertas Suricata em `alerts.json`.
- Wazuh Dashboard restrito a `127.0.0.1:443` e acessível apenas localmente na EP126.
- Erro inicial `EACCES` sobre `wazuh.yml` corrigido por ACL mínima de leitura para o UID 1000 do container do Dashboard, sem tornar o arquivo público.
- Dashboard → API do Manager validado em `wazuh.manager:55000`; resposta HTTP 401 sem autenticação confirmou disponibilidade da API.
- Threat Hunting exibiu eventos do agente `ep125-pucpr`, incluindo alertas Suricata.

## Prova ponta a ponta
A evidência textual final encontrou 626 eventos do agente `ep125-pucpr` na janela analisada e 6 eventos Suricata, incluindo:

- `Suricata: Alert - ET INFO Observed Google DNS over HTTPS Domain (dns .google in TLS SNI)`
- `Suricata: Alert - SURICATA Applayer Detect protocol only one direction`

O agente `ep125-pucpr` aparece no Manager como `Active`.

Fluxo comprovado:

```text
EP125 / DMZ
  ↓
Suricata
  ↓
/var/log/suricata/eve.json
  ↓
Wazuh Agent
  ↓ TCP/1514
Wazuh Manager / EP126
  ↓
alerts.json / Indexer
  ↓
Wazuh Dashboard / Threat Hunting
```

## Evidências e integridade
Relatório final local:

`conectaeduca-evidencia-suricata-wazuh-ponta-a-ponta-20260907-204801.txt`

SHA-256 calculado para o relatório:

`cd086514ca1ba4f0553a23cc7e5c7583b836fa0028dba52f6c94f3adddef2cec`

Resumo do relatório final:

`PASS=4 WARN=0 FAIL=0`

## Riscos residuais / próximos gates
1. `HOME_NET` do Suricata ainda está genérico para redes RFC1918; avaliar restrição para `192.168.6.32/28` com validação antes/depois.
2. A ACL de leitura do `wazuh.yml` foi aplicada no runtime; deve ser tornada reprodutível no deploy para sobreviver a recriações do arquivo.
3. A stack Docker ainda usa credenciais padrão do Wazuh Dashboard/Indexer; rotacionar de forma coordenada após fechamento das validações.
4. Suricata no pfSense continua bloqueado por privilégio WebGUI institucional; não houve tentativa de contornar ACL/permissões.

## Política operacional observada
- Execução como usuário comum.
- Elevação administrativa somente por comando específico quando necessária.
- Nenhum shell root persistente.
- Nenhum conteúdo de credenciais, tokens, chaves ou `wazuh.yml` foi registrado nesta evidência.
