# Contrato de eventos DLP — Ferret → SIEM

## Objetivo

O Ferret produz um relatório JSON bruto para análise local. Esse relatório **não é enviado diretamente ao SIEM**. O ConectaEduca aplica uma segunda etapa de minimização com allowlist de campos e grava eventos JSONL próprios em `.runtime/events/dlp.jsonl`.

A coleta pelo Wazuh Agent da VM interna deve consumir apenas esse JSONL minimizado. A classificação desse contrato no Wazuh Manager já foi validada no baseline.

## Separação de superfícies

- `.runtime/inbox/`: material potencialmente sensível submetido ao DLP;
- `.runtime/reports/raw/`: saída JSON completa do Ferret, protegida e fora do Git;
- `.runtime/events/dlp.jsonl`: eventos minimizados destinados à observabilidade/SIEM;
- `.runtime/state/processed.sha256`: hashes de artefatos já processados para evitar duplicação acidental.

O Wazuh Manager não recebe bind mount do relatório bruto do Ferret.

## Campos explicitamente proibidos no evento SIEM

O sanitizador não propaga, mesmo que presentes no relatório bruto:

- `results[].text`;
- `results[].filename`;
- conteúdo original do arquivo;
- match detectado;
- URL, token, senha, CPF ou outro dado encontrado;
- objetos `metadata` fora dos campos aprovados abaixo.

Essa exclusão é estrutural: o sanitizador reconstrói o evento com allowlist, em vez de copiar o objeto de origem e remover alguns campos.

## Eventos

### `dlp_scan_summary`

Contém somente metadados operacionais e contagens:

- `schema_version`;
- `event_type`;
- `source`;
- `source_version`;
- `observed_at`;
- `scan_id`;
- `file_id` (SHA-256 do artefato; não contém o nome do arquivo);
- `files_processed`;
- `files_skipped`;
- `total_findings` (estatística reportada pelo Ferret);
- `emitted_findings` (quantidade efetivamente convertida em eventos `dlp_finding`);
- `high`;
- `medium`;
- `low`;
- `suppressed`;
- `duration_seconds`;
- `source_report_shape` (`object` no baseline Ferret 2.4.3);
- `stats_complete` (`true` quando o relatório 2.4.3 possui o objeto `stats` esperado);
- `sanitization_profile`.

### `dlp_finding`

Um evento por finding, limitado a:

- identificação do scan e do artefato por hash;
- `validator`;
- `finding_type`;
- `confidence_level`;
- `confidence`;
- `line_number`;
- `secret_type`;
- `detection_method`;
- `environment_type`;
- `sanitization_profile`.

O `line_number` é mantido para remediação local, mas o nome/caminho do arquivo não é enviado ao SIEM.

## Contrato JSON no Ferret 2.4.3

A imagem 2.4.3 foi validada com a mesma versão e digest observados na EP126. Em container efêmero e sem rede:

- scan limpo: `files_processed=1`, `total_findings=0`, `results=[]`;
- finding sintético: `files_processed=1`, `total_findings=1`, um objeto em `results[]`;
- ambos retornaram objeto no nível raiz com `stats{}` + `results[]`.

O relatório bruto do finding continha `text` e `filename`, mas `text` foi devolvido como `[HIDDEN]` pelo perfil usado. Mesmo assim, esses campos continuam estruturalmente proibidos no JSONL do SIEM e são descartados pela allowlist.

O sanitizador atual exige o shape objeto do Ferret 2.4.3. O antigo `legacy_empty_array` da baseline 2.2.1 não é mais aceito e shapes inesperados continuam sendo rejeitados em fail-closed.

## Modo operacional atual

O pipeline é **detect-only**. O processamento não remove, move nem quarentena automaticamente o arquivo da inbox. Isso evita que uma política DLP ainda em ajuste destrua ou altere material de trabalho.

Quarentena/bloqueio poderá ser acrescentado posteriormente como ação explícita e testada.

## Fluxo definitivo via Wazuh Agent

O fluxo de transporte planejado para a VM interna é:

```text
Ferret -> relatório bruto local -> sanitizador -> events/dlp.jsonl
                                              -> Wazuh Agent da VM interna
                                              -> Wazuh Manager
```

Não é necessário conceder ao Ferret credenciais de MariaDB, OpenBao ou Wazuh.

## Classificação preparada no Wazuh Manager

O baseline de integração do SIEM reserva regras customizadas `110100` a
`110113` para os eventos DLP. O Wazuh usa o decoder JSON nativo; não há decoder
customizado para o contrato atual.

Findings são classificados por `confidence_level` em níveis distintos, enquanto
um scan limpo é regra de nível 0. A coleta definitiva continuará sendo feita
pelo Wazuh Agent nativo da VM interna.
