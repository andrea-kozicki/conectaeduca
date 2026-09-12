# Retenção dos artefatos DLP

O runtime do Ferret pode conter metadados sensíveis mesmo com `show_match: false`. A política separa entrada, relatório bruto, evento minimizado e ledger para evitar retenção excessiva e, ao mesmo tempo, não apagar evidência de uma execução que falhou.

## Política operacional

- `inbox/`: após 7 dias, só é elegível para remoção se o SHA-256 completo já existir em `state/processed.sha256`.
- `reports/raw/`: após 7 dias, só é elegível se o identificador de 16 hexadecimais do nome puder ser correlacionado com uma entrada completa do ledger. Raw sem confirmação é preservado.
- `events/dlp.jsonl`: superfície minimizada coletada pelo Wazuh; rotação diária, até 30 rotações, `maxage 30`, compressão e `copytruncate`.
- `state/processed.sha256`: preservado durante a vida do projeto para deduplicação; contém hashes, não o conteúdo dos arquivos.
- `state/retention.hold`: quando presente, suspende toda a limpeza automatizada de inbox/raw.

A retenção local do JSONL acompanha a decisão do laboratório de manter `wazuh-alerts-*` por 30 dias. O relatório bruto usa prazo menor por ter maior exposição potencial.

## Automação fail-safe

`scripts/dlp/limpar_retencao_ferret.sh` executa no boundary UID 1000:

- `--dry-run`: lista candidatos sem excluir;
- `--apply`: remove apenas material vencido cuja conclusão esteja comprovada pelo ledger.

O helper aceita `FERRET_RUNTIME_ROOT` somente para testes isolados. Em operação, usa o runtime canônico em `/opt/conectaeduca`.

O timer systemd é diário e não usa `Persistent=true`, evitando uma limpeza retroativa imediata na primeira instalação após período offline.

Durante incidente ou preservação acadêmica, crie `state/retention.hold` antes da janela de limpeza. `.runtime/` continua fora do Git e de handoffs comuns.
