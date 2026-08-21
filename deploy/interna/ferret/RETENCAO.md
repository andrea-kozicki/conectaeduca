# Retenção dos artefatos DLP

O runtime do Ferret pode conter metadados sensíveis mesmo quando `show_match: false` está ativo. Por isso, os artefatos têm funções diferentes e não devem ser tratados como equivalentes.

## Classes

- `inbox/`: entrada controlada; retenção depende do fluxo que originou o arquivo. O pipeline não apaga automaticamente.
- `reports/raw/`: relatório técnico completo do Ferret. Não deve ser ingerido pelo Wazuh.
- `events/dlp.jsonl`: evento minimizado preparado para o SIEM.
- `state/processed.sha256`: identificadores SHA-256 para deduplicação operacional.

## Baseline desta fase

Nesta fase, a retenção automática ainda **não é habilitada**. A equipe deve primeiro validar o fluxo Ferret → evento sanitizado → Wazuh Agent e só depois ativar limpeza automática, para não apagar evidências antes da confirmação de ingestão.

Quando a integração Wazuh estiver operacional, a política de retenção local deverá ser harmonizada com `deploy/interna/wazuh/RETENCAO.md` e documentar explicitamente:

1. prazo dos relatórios brutos;
2. prazo do JSONL local após ingestão confirmada;
3. tratamento dos arquivos da inbox;
4. exceções de preservação para evidência acadêmica/incidente.

Até lá, `.runtime/` permanece fora do Git, com acesso restrito e sem inclusão em handoff/backup comum.
