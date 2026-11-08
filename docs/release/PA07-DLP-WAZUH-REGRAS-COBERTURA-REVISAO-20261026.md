# PA-07 / PR #206 — Revisão offline das regras DLP/Wazuh e cobertura mínima

**Data:** 26/10/2026 (BRT). **Ambiente de execução:** somente GitHub Actions / repositório. **Status:** proposta em branch DRAFT, não implantada no Manager/EP126.

## Contexto e problema delimitado

No Pentest A (15/10), `confidence_level=MEDIUM` foi observado na regra genérica `110110`, apesar de regra específica `110112` originalmente usar o regex sensível a maiúsculas `^medium$`. O PR #206 propôs `(?i)^low$`, `(?i)^medium$`, `(?i)^high$`. A reprodução na configuração **carregada** do Wazuh Manager permanece pendente.

A revisão cruzada com o PR #207 revelou outra ambiguidade: o sanitizador DLP permite um relatório estruturalmente válido como `{"results":[],"stats":{}}`. Seu resumo contém `files_processed=0`, `emitted_findings=0` e `stats_complete=true`. O último campo atesta apenas que `stats` é um objeto; **não comprova cobertura de arquivos**. Antes desta revisão, a regra `110101` interpretava `emitted_findings=0` como varredura concluída, sem verificar qualquer arquivo processado.

## Alterações propostas, somente em PR #206

1. Regra `110101`, nível 0, exige simultaneamente `event_type=dlp_scan_summary`, `emitted_findings=0`, `files_processed` positivo e `files_skipped=0` via `field type="pcre2"`. Sua descrição foi ajustada para indicar **achados emitidos iguais a zero com processamento registrado**, mas **não cobertura integral comprovada**. IDs, hierarquia e `no_full_log` preservados.
2. Preservadas as três regras de confiança `110111` (LOW, nível 5), `110112` (MEDIUM, nível 8) e `110113` (HIGH, nível 12) com correspondência case-insensitive; fallback `110110` (nível 6) continua para classificação desconhecida.
3. Adicionados `tests/python/test_dlp_wazuh_contract_pr206.py` (10 testes), contendo eventos **artificiais** gerados pela implementação de `sanitizar_ferret.py` da branch e um avaliador estático **limitado** dos regex e da cadeia de regras. Adicionadas guardas de invariantes em `scripts/evidencias/validar_regras_dlp_confidence.py`, incluindo `DLP_COVERAGE_STATIC=PASS`.
4. CI `Repository Static Integrity` executa as guardas e a nova suíte sem Wazuh, Docker, sudo nem dados da instituição.

## Evidência efetiva em 26/10

GitHub Actions `Repository Static Integrity`, run **40396835976**, job **121832001688**, concluiu **SUCCESS**:
- `DLP_CONFIDENCE_STATIC=PASS rules=3 cases=21 fallback=110110`.
- `DLP_COVERAGE_STATIC=PASS quiet_rule=110101 requires processed>0/skipped=0`.
- `Ran 10 tests ... OK` na suíte de contrato; nove variantes de capitalização, fallback desconhecido, schema sintético de zero processos/itens ignorados e detecção com finding.

### Resumo das classificações previstas (simulação estática)

| Fixture | Regra que deve coincidir | Limite |
|---|---|---|
| finding LOW/low/Low | `110111`, nível 5 | Match simulado; PCRE2/Wazuh real não executado |
| finding MEDIUM/medium/Medium | `110112`, nível 8 | Match simulado |
| finding HIGH/high/High | `110113`, nível 12 | Match simulado |
| finding desconhecido | `110110`, nível 6 | Fallback simulado |
| summary: 0 processados; 0 achados | **não deve corresponder à regra de ausência de achados `110101`** | NÃO gera automaticamente um alerta de "inconclusivo"; depende de regra/política posterior |
| summary: 1 processado; 0 ignorados; 0 achados | `110101`, nível 0 | Não comprova ausência de falha/incompletude real |
| summary: 1 processado; 2 ignorados; 0 achados | **não deve corresponder a `110101`** | Sem classificação afirmativa de limpeza |
| summary: 1 finding emitido | `110102`, nível 3 | Não avalia completude do lote |

## Limitações e riscos residuais

- Os testes Python **modelam** parte da avaliação de campos e `if_sid`. Não validam PCRE2 compilado pelo Wazuh, decodificadores JSON efetivos, precedência real das regras, alertas no SIEM ou ausência de falsos positivos.
- A mensagem não afirma "varredura completa". Dados ausentes no `stats` recebem defaults no sanitizador, inclusive `files_skipped=0`; portanto, zero itens ignorados **não comprova** necessariamente nenhuma perda de cobertura. A semântica efetiva do `--format json` do Ferret v5 ainda exige CLI real, incluindo falhas parciais.
- Quando `files_processed=0` a regra silenciosa `110101` deixa de coincidir, mas **isso não cria por si só um alerta de cobertura insuficiente**; decidir regra de alerta própria e contrato `coverage_status` somente após observação real e autorização.
- `source_version=2.4.3` permanece por compatibilidade no sanitizador da branch; o patch defensivo `NaN`/cleanup do PR #207 é distinto e requer reconciliação antes do merge.
- A branch não possui evidência de instalação no Manager da EP126. Nenhuma regra atual do Wazuh foi modificada.

## Gates para validação autorizada e eventual merge

1. Confirmar qual ruleset está carregado no Wazuh Manager e tirar backup da configuração ativa, sem divulgar logs brutos.
2. Verificar pelo CLI Ferret `--format json` campos reais de cobertura e `confidence_level`; comparar `files_processed`, `files_skipped`, `incomplete`/falhas, e os defaults do sanitizador; usar apenas fixtures sintéticas.
3. Executar `wazuh-logtest` autorizado com LOW/low, MEDIUM/medium, HIGH/high, valores desconhecidos, zero processados, parcial ignorado, execução positiva com 0 achados e resumo com finding; registrar rule ID e level.
4. Validar E2E agente → Manager e integridade de `no_full_log` + política de minimização, sem publicar conteúdos PII/segredos.
5. Se houver divergências, **não aplicar** a regra/merge; rever o contrato com o PR #207 e change control. Não reiniciar Manager ou editar regras em runtime nesta fase.

**Situação do Pentest A:** mitigação proposta e bateria estática aprovada; achado OBS-PA07-02 permanece **ABERTO** até implantação e reteste autorizado.
