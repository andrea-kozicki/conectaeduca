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
