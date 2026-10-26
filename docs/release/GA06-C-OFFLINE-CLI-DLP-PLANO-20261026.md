# GA-06.C — Ferret v5: revisão offline e gates de integração DLP

**Data:** 26/10/2026 (BRT)  
**Escopo:** somente repositório, análise estática e preparação de testes sintéticos. EP125/EP126 indisponíveis por manutenção até depois das 19h, segundo suporte.  
**Status:** plano preparado; testes de integração e cutover NÃO executados nesta etapa.  
**Referência:** PR #207 DRAFT; achado PA-07-DLP-01.

## 1. Evidência de partida (25/10)

- EP126, Docker 29.8.1, image store containerd; TAR e config SHA-256 conferidos; sete RootFS diff IDs compatíveis.
- Canário temporário da imagem `2.4.3+ce.pa07.v5` apresentou `CANARY_HEALTH=PASS`, `CANARY_JS=PASS`, `CANARY_SCAN_FICTICIO=PASS`.
- `CANARY_TMPFS_DOCKER_DECLARED=0700_UID1000`; **escrita efetiva no tmpfs não foi testada explicitamente**.
- Canário removido; baseline 2.4.3 permaneceu saudável. **Nenhum cutover realizado; não declarar PA-07 corrigido em produção.**
- Não tocar na conta institucional `lucy`, em seu UID/grupos/permissões/home, nem nos volumes reais `.runtime/state`, `inbox`, `reports/raw`.

## 2. Pontos da revisão estática (26/10)

### 2.1. Versão emitida pelo sanitizador

`scripts/dlp/sanitizar_ferret.py` declara `FERRET_VERSION = "2.4.3"` e usa essa constante nos eventos `dlp_scan_summary` e `dlp_finding`. A imagem candidata anuncia `2.4.3+ce.pa07.v5`.

**Risco de rastreabilidade:** um evento produzido pela candidata pode continuar exibindo `source_version=2.4.3`, sem indicar o patch da UI. **Não alterar o campo automaticamente agora.** Deliberar se `source_version` representa o contrato/esquema upstream ou a imagem executada; se necessário, acrescentar `source_build` derivado de identidade *verificada* e permitido pela política do SIEM. Regressão da regra Wazuh 110113 obrigatória.

### 2.2. Saída JSON inválida no processador Bash

Em `scripts/dlp/processar_inbox_ferret.sh`, a validação de JSON ocorre como comando `python3 ...`, seguida por `if [[ "$?" -ne 0 ]]`. Com `set -e` ativo, uma falha do Python pode encerrar o script **antes de entrar no bloco que chama `cleanup_one`**, deixando arquivos `mktemp` de saída/erro pendentes. O trap de EXIT observado trata os snapshots, mas não necessariamente `raw_tmp`/`err_tmp`. Esses temporários têm modo 0600, porém podem conter relatório bruto.

**Correção candidata a testar, não aplicada aqui:** usar `if ! python3 ...; then cleanup_one; return 1; fi`, preservando o `cleanup_active_snapshots`; preferir trap específico de temporários com garantia também em sinais/falhas. Requer teste negativo que confirme inexistência de resíduos, sem usar dados reais.

### 2.3. Execução offline de sanitizador

`resolve_input_path()` aceita apenas arquivos regulares dentro de `deploy/interna/ferret/.runtime/reports/raw`, e `resolve_output_path()` exige `.runtime/events`. **Não** apontar a CLI do sanitizador para a pasta real da EP126 durante uma simulação. Testar `load_report()`/`build_events()` em processo Python isolado, ou criar um checkout descartável com sua própria árvore `.runtime` inteiramente fictícia no computador pessoal.

## 3. Bateria offline proposta — sem Docker, sem VMs, sem dados reais

Usar apenas fixtures JSON artificiais e biblioteca padrão do Python. Não carregar credenciais, suppressions, relatórios antigos ou conteúdo real.

| ID | Caso | Aceite |
|---|---|---|
| DLP-O01 | `results=[]`, `stats={}` válido, arquivo fictício | Um resumo `dlp_scan_summary`, zero findings; nenhum segredo |
| DLP-O02 | Um finding sintético com `text`, `filename` e metadados não aprovados | Apenas campos allowlist; `text`, `filename` e dados brutos não aparecem nos eventos |
| DLP-O03 | `results` ausente/não-array; `stats` ausente/não-objeto | Falha fechada; nenhum evento declarado como limpeza |
| DLP-O04 | `confidence` booleano/negativo ou campo inteiro inválido | Validação falha; não emitir evento parcial |
| DLP-O05 | JSON truncado ou stdout CLI inválido | Processo devolve falha; temporários brutos eliminados |
| DLP-O06 | Dois scans sintéticos independentes | IDs distintos, contagens coerentes, ledger sem falsos positivos |
| DLP-O07 | Origem versão `2.4.3+ce.pa07.v5` | Política de provenance definida e documentada, sem quebrar schema/rule 110113 |

Nenhum resultado `PASS` deve ser preenchido antes de rodar a bateria.

## 4. Gates posteriores na EP126 (após liberação e autorização)

1. Reconfirmar baseline `/health`, UID/segurança, timers e espaço, em leitura.
2. Com escopo de mudança autorizado, testar candidato em contêiner temporário **sem montagem do runtime real**, usando apenas fixture fictícia; verificar escrita efetiva dentro de `/home/ferret/tmp` como UID1000 e limpeza.
3. Testar saída **CLI** `--format json` com schema `results[]` e `stats{}`; registrar apenas campos permitidos e checksums, nunca valores de possíveis segredos.
4. Executar sanitizador em ambiente isolado, verificar allowlist/ACL/retorno e ausência de resíduos.
5. Só depois validar, com operador, envio de evento DLP sintético ao Wazuh e correspondência à regra 110113; não escrever em `.runtime/events/dlp.jsonl` real sem change control.
6. Preparar mudança reversível do monitor (`FERRET_EXPECTED_VERSION`), Compose opt-in, image ID conferido, backup e rollback; **não alterar baseline ou promover PR #207 sem gates aprovados**.

**Observação de segurança:** `lucy` é conta institucional do suporte; nenhuma alteração em suas credenciais, privilégios ou arquivos faz parte da GA-06.

## 5. Preparação do suporte / Zero Trust 28/10

Manter o handoff técnico do PR #200 separado da GA-06 e confirmar com suporte a disponibilidade da janela solicitada (28/10, 15h). Perguntas pendentes: (a) cadeia CA/SAN de EP125 vista pela EP126, verify code 20; (b) FQDN/DNS/ZeroSSL e custódia de chave; (c) host e saída permitida para Connector Twingate, MFA e recursos mínimos; (d) isolamento efetivo do endpoint administrativo — Twingate não segmenta `/admin` por path; (e) snapshot/rollback, responsáveis e escopo de mudança. **Não combinar cutover Ferret e instalação Twingate na mesma mudança sem aprovação específica.**

## 6. Estado e custódia

- **Concluído hoje:** leitura estática e preparação de gates neste documento.
- **Não concluído:** testes offline executados, correção de código, regressão CLI/Wazuh, acesso às VMs, cutover ou mudança de permissões.
- **PR:** manter #207 como DRAFT.

## 7. Avanço real do código e dos testes — 26/10/2026

**Alterações somente na branch do PR #207 (DRAFT):**
- `scripts/dlp/processar_inbox_ferret.sh`: acrescentado rastreador de caminhos de temporários brutos gerados por `mktemp`, remoção em `EXIT` e sinais HUP/INT/TERM; a validação de `results[]`/`stats{}` passou para `if ! python3 ...; then cleanup_one; return 1; fi`. Falha de `sudo install` e de `chmod` dos eventos passou a ser explicitamente tratada.
- `scripts/dlp/sanitizar_ferret.py`: `safe_float` rejeita `NaN`, infinidades e conversões com overflow; `json.dumps(..., allow_nan=False)` reforça JSONL estrito. Campos allowlist e versão upstream 2.4.3 preservados.
- `tests/python/test_ferret_sanitizer_ga06.py`: 13 testes automatizados, sem Docker/VM/dados reais.
- `.github/workflows/ga06-c-offline-dlp.yml`: CI isolada, `contents: read`, sem segredos, executa `python3 -m unittest discover -s tests/python -p 'test_ferret_sanitizer_ga06.py' -v`.

### Evidência da execução efetiva

Run GitHub Actions **GA06 C Offline DLP #1**, ID `40386085475`, job `121794600723` em 26/10: **13 testes executados, 13 PASS**, saída `Ran 13 tests in 0.014s / OK`. Gitleaks também PASS nessa revisão. Isso comprova **apenas a bateria de unidades e inspeções Bash offline**, não a cadeia E2E nem o comportamento do Docker/EP126 após manutenção.

**Escopo da cobertura:**
- DLP-O01 a O04: esquema válido, minimização de campos sensíveis e entradas rejeitadas cobertas offline.
- DLP-O05: JSON truncado rejeitado e função real `cleanup_active_temp_files` testada com arquivos fictícios; **falha simulada no processador Bash completo ainda pendente**.
- DLP-O06: `scan_id` único em duas análises aprovado; **ledger `processed.sha256` e concorrência não testados**.
- DLP-O07: `source_version=2.4.3` preservado deliberadamente como compatibilidade atual; **identificação separada do build v5 e regressão Wazuh 110113 pendentes**.
- Não houve teste de escrita efetiva `tmpfs`, CLI Docker real nem ingestão Wazuh nesta etapa.

### CI geral — bloqueio independente ainda ABERTO

O workflow **Supply Chain Build Gate** falhou no step `Validate supply chain invariants`: a política vigente exige que imagens externas em Compose tenham digest `@sha256:` literal, mas o override opcional `deploy/interna/ferret/pa07-v5/compose.pa07-v5.override.yml` utiliza `${FERRET_PA07_V5_IMAGE:? ...}` sem digest literal. Esse arquivo **já fazia parte do PR antes das alterações GA-06.C**. **Não inserir digest fictício nem enfraquecer o gate**. Resolver em revisão própria de identidade imutável e rollout aprovado, antes de promover/mesclar PR #207. A CI específica 13/13 PASS não elimina esse bloqueio global.

**Status:** correções + CI offline concluídas na branch; validação operacional e autorização de implantação pendentes. EP125, EP126, pfSense, conta `lucy`, `main` e serviços não foram modificados.

### Rechecagem de CI e pinning (26/10)

O primeiro workflow GA-06.C (antes do pin) passou 13/13, porém o gate global `Repository Static Integrity` recusou `actions/checkout@v4` por exigir SHA de 40 caracteres. A action foi fixada ao SHA `11d5960a326750d5838078e36cf38b85af677262` (resolvido pelo runner para checkout v4), sem afrouxar a política. No commit `0ffaba6279e0fb9f96c642b26188e65e739b4857`, **Repository Static Integrity = PASS**, **GA06 C Offline DLP = PASS**, **PHPUnit Security Tests = PASS**, **Gitleaks = PASS**. Semgrep ainda estava em andamento na verificação consultada; o **Supply Chain Build Gate = FAIL** continua devido ao override parametrizado descrito acima, a resolver independentemente da GA-06.C.

## 8. Revisão cruzada GA-06.C / PR #206 — risco de falso 'scan concluído' no Wazuh (26/10)

**Achado de análise estática — não foi reproduzido na VM.** A saída permitida por `sanitizar_ferret.py` admite relatório `{"results":[],"stats":{}}`. O sanitizador gera `dlp_scan_summary` com `files_processed=0` (default), `emitted_findings=0` e `stats_complete=true` (indicador de formato presente, NÃO de cobertura de varredura comprovada). A regra `110101` no XML de Wazuh confere apenas `event_type=dlp_scan_summary` e `emitted_findings=0`, mas descreve o evento como **"varredura concluída sem findings"**; não exige `files_processed>0`. Portanto, as regras atuais não distinguem nesse caso uma análise efetivamente concluída de um resumo válido em formato, porém sem cobertura provada.

**Relevância:** mesma família de risco semântico do PA-07 UI, porém no SIEM; não significa que o scanner v5 real gere `stats={}` após um scan concluído nem que Wazuh tenha alertado falsamente em produção. Não alterar `files_processed`/regra no escuro.

**Novo gate DLP-O08:** obter no teste CLI autorizado os campos reais `files_processed`, `files_skipped`, `total_findings`, erro/incomplete e `results` para cenários de scan concluído e erro. Exigir definição operacional de "completo" (ex.: não basta `emitted_findings=0`); atualizar sanitizador/contrato e regras do PR #206 de forma coordenada, preservando rejeição a campos brutos e `no_full_log`. Em seguida rodar fixtures offline, `wazuh-logtest` na janela autorizada e evidência E2E. Até lá, rotular o teste 0 findings como **"sem findings emitidos; cobertura a validar"**, nunca inferir ausência de dados sensíveis.

## 9. Cadeia de custódia da imagem candidata e decisão do gate de supply chain — 26/10

A etapa offline agora inclui os seguintes artefatos **versionados em PR #207 DRAFT**:

- `deploy/interna/ferret/pa07-v5/GA06_CANDIDATE_PROVENANCE.json`: referências SHA-256 do TAR aprovado (`5786c56...`), JSON de configuração (`1fab3fc1...`), descritor identificado no Docker 29 EP126 (`535ec9ef...`), tag de custódia e invariantes UID, versão, plataforma, sete camadas. **Esses três digests identificam objetos distintos. Nenhum deles é apresentado como digest de distribuição de registry.**
- `scripts/evidencias/ga06_validar_proveniencia_offline.py`: verifica SHA do archive, `manifest.json` interno, config SHA, UID/versão/plataforma e diff IDs; opcionalmente compara metadados do Docker inspect (ID + descriptor + runtime) **sem executar Docker e sem extrair o TAR**. Output somente PASS/FAIL. Arquivo bruto `docker image inspect` pode conter `Env` sensíveis: manter em custódia e não anexar ao Git/chat.
- `tests/python/test_ga06_provenance_offline.py`: 12 cenários com archives e JSON inspect **inteiramente sintéticos**, incluindo rejeição de hash, UID, tag, versão, camadas, descriptor e ENV divergentes.

**CI executada:** GA06 C Offline DLP, run `40391056285` (26/10): suíte de sanitização **13/13 PASS** e suíte de proveniência **12/12 PASS** — total **25/25**. Isso aprova a lógica do verificador *em fixtures sintéticas*, não representa nova execução contra TAR físico nem contra Docker da EP126 nesta data.

**Por que Supply Chain Build Gate ainda FAIL:** `deploy/interna/ferret/pa07-v5/compose.pa07-v5.override.yml` permite `FERRET_PA07_V5_IMAGE` fornecido em runtime e não traz digest de registry literal no default, contrariando a política global de Compose. Não usar `1fab...` nem `535...` como substitutos especulativos de `repo@sha256:digest`, não inventar valor e não alterar a política geral para obter PASS.

**Decisão pendente de custódia / publicação:**
- **Opção A (preferencial, depende de aprovação institucional):** publicar a candidata em registry aprovado e privado, verificar o digest de distribuição retornado após push, fixar `repo@sha256:<digest real>` no override, revisar permissões/pull/segredos, rodar CI e teste de rollback. Não temos esse digest até existir publicação aprovada.
- **Opção B (somente mediante exceção institucional formal para ambiente desconectado):** manter distribuição local via TAR SHA aprovado, configurar gate específico de image store local + `pull_policy: never` + verificação da identidade imediatamente antes de Compose, registrar aceites, rollback e restrições. Uma exceção dessas exige revisão explícita da política, não apenas alterar regex do gate ou aceitar tag mutável. **Nenhuma exceção foi aprovada nem implementada.**

**Estado do Grupo A após esta revisão:** GA-06 ainda ABERTO para gate de supply chain e integração; GA-07 (plano de retenção), GA-08 (matriz bridge WAF) e GA-09 (critérios Bacula) concluídos no escopo *offline documental*, mas achados ainda aguardam operação autorizada. Não declarar quatro achados remediados. Sem mudanças na EP125/EP126, serviços, conta `lucy` ou branch `main`.
