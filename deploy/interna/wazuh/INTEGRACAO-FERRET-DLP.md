# Integração Ferret DLP → Wazuh

## Escopo desta fase

Esta fase prepara e valida a **análise no Wazuh Manager** dos eventos JSONL
sanitizados produzidos pelo pipeline DLP do ConectaEduca.

O transporte definitivo continuará sendo feito pelo **Wazuh Agent nativo da
VM interna** quando a implantação das VMs for realizada. O Manager não recebe
bind mount de `reports/raw/`, `inbox/` ou do conteúdo original analisado.

Fluxo alvo:

```text
Ferret -> reports/raw/ -> sanitizador -> events/dlp.jsonl
                                      -> Wazuh Agent nativo
                                      -> Wazuh Manager
                                      -> Indexer / Dashboard
```

## Decoder

Não há decoder customizado nesta fase. O evento é JSON simples e o Wazuh possui
decoder JSON nativo, que transforma os campos em dynamic fields para as regras.

## Regras customizadas

Arquivo:

```text
deploy/interna/wazuh/config/rules/conectaeduca_dlp_rules.xml
```

IDs reservados pelo ConectaEduca nesta fase:

| Regra | Nível | Uso |
|---|---:|---|
| 110100 | 0 | regra-base para eventos `source=ferret-scan`, schema 1 |
| 110101 | 0 | scan limpo, sem findings; não gera alerta |
| 110102 | 3 | summary com um ou mais findings |
| 110110 | 6 | fallback para finding com confiança não classificada |
| 110111 | 5 | finding `low` |
| 110112 | 8 | finding `medium` |
| 110113 | 12 | finding `high` |

As regras usam `no_full_log`. O evento já é minimizado pelo sanitizador, mas o
Wazuh também não precisa guardar uma cópia textual integral para cumprir a
função de alerta.

## Coleta pelo agente

O modelo versionado fica em:

```text
deploy/interna/wazuh/agent/conectaeduca-dlp-localfile.xml.example
```

Na VM interna, a equipe deve substituir
`__CONECTAEDUCA_DLP_EVENTS_FILE__` pelo caminho absoluto de
`events/dlp.jsonl` e inserir o bloco `<localfile>` na configuração do agente.

A política de permissões deve conceder ao processo do Wazuh Agent **somente
leitura** do JSONL sanitizado. Não conceder acesso à `inbox/`,
`reports/raw/` ou `state/`.

Essa permissão será definida no tijolo de implantação do agente, porque usuário,
grupo e caminho absoluto dependem da VM final.

## Teste antes do agente

O `checkpoint_wazuh_handoff.sh` usa `wazuh-logtest` dentro do Manager para
provar que o decoder JSON e as regras customizadas classificam eventos
sintéticos e sanitizados. Esse teste valida a camada de análise sem inventar um
bind mount temporário que não existirá na arquitetura final.

Ele não substitui o teste de transporte pelo Wazuh Agent na VM.
