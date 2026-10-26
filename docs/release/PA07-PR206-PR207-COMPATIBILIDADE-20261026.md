# PA-07 — Compatibilidade e plano de reconciliação dos PRs #206 e #207

**Revisão documental / estática e ensaio local posterior:** 26/10/2026 (BRT) — EP125/EP126 indisponíveis por manutenção.  
**Referências exatas conferidas:** PR #206 `02f3a4d536a3a36eb06caef234b33a7d0c5aedee`; PR #207 `b60a45cf383469edaa96860e7856996b14847ef8`; base comum `main@4bf7ac688b1ea738cd158f03a20b07732cdd90a3`.

## 1. Resultado do diff cruzado

Os PRs são *DRAFT*, não mesclados, com branches divergentes desde a mesma base comum. Comparação de arquivos alterados `list_pr_changed_filenames`:
- **PR #206:** 5 arquivos: `.github/workflows/repository-static-integrity.yml`; `deploy/interna/wazuh/config/rules/conectaeduca_dlp_rules.xml`; `scripts/evidencias/validar_regras_dlp_confidence.py`; `tests/python/test_dlp_wazuh_contract_pr206.py`; documento de regras DLP/Wazuh.
- **PR #207:** 26 arquivos: patch e rollout de interface Ferret v5, `scripts/dlp/sanitizar_ferret.py`, `scripts/dlp/processar_inbox_ferret.sh`, CI e testes da GA-06, documentação e manifestos de custódia.

**Interseção dos caminhos alterados: zero arquivos.** Portanto, não há conflito textual direto nos conjuntos atuais. Isso não demonstrava isoladamente compatibilidade funcional ou ausência de conflitos na combinação. **Atualização posterior:** o merge local sem commit ocorreu sem conflitos, e 39/39 testes passaram no mesmo tree descartável (Seção 6); não houve CI publicada da árvore combinada nem execução operacional.

## 2. Contrato compartilhado — revisão estática

| Ponto | PR #206 | PR #207 | Compatibilidade e risco |
|---|---|---|---|
| Identidade da origem | Regras 110100 exigem `source=ferret-scan`, `schema_version=1` | Sanitizador mantém os mesmos campos e valores | **Sem divergência textual identificada** |
| Níveis | Regras 110111/110112/110113 aplicam `(?i)^low/medium/high$`, com níveis 5/8/12 | Sanitizador preserva `confidence_level` sanitizado, incluindo capitalização | **Compatível em análise estática**; PCRE2/Manager pendentes |
| Fallback | 110110, nível 6, para finding desconhecido | `dlp_finding` continua emitido | **Sem quebra de esquema identificada** |
| Resumo sem achados | 110101 requer `emitted_findings=0`, `files_processed>=1`, `files_skipped=0` | 207 mantém campos, `files_processed` default 0 e `files_skipped` default 0 | **Alinhamento parcial**: ausência de skipped no JSON ainda é convertida em 0; um resumo pode ser indevidamente silenciado sem cobertura total |
| Privacidade | Ruleset mantém `no_full_log` | Sanitizador usa allowlist e rejeita NaN/infinito, JSONL `allow_nan=False` | Objetivos complementares; validar ingestão real e conteúdo antes de habilitar |
| Versão de origem | Ruleset exige `schema_version=1`, não build da UI | `source_version=2.4.3` ainda fixo na candidata v5 | Sem incompatibilidade de regra, porém **proveniência do build v5 não atestada no evento** |
| Processamento CLI | Regras não controlam produção dos logs | `processar_inbox_ferret.sh` tem cleanup fail-closed; arquivo `raw` ainda existe no caminho normal | 29/29 testes offline em PR207 (13+12+4) não substituem teste de integração com Wazuh |
| Release | Sem imagem nova | Override Ferret usa imagem parametrizada | **Bloqueio independente:** Supply Chain Build Gate em FAIL por não fixar digest real de registry |

## 3. Evidências registradas

- **PR #206** `Repository Static Integrity` run [40396835976](https://github.com/andrea-kozicki/conectaeduca/actions/runs/40396835976): 10/10 testes sintéticos de contrato PASS; `DLP_CONFIDENCE_STATIC=PASS` 21 casos e `DLP_COVERAGE_STATIC=PASS`; outros passos de integridade aprovados. Não executou a versão do sanitizador de #207.
- **PR #207** `GA06 C Offline DLP` run [40395667268](https://github.com/andrea-kozicki/conectaeduca/actions/runs/40395667268): 29/29 PASS (13 sanitização/cleanup, 12 proveniência, 4 erros do processador mockado). Nesse commit, Static Integrity, PHPUnit, Semgrep e Gitleaks PASS; Supply Chain Build Gate FAIL (restrição de política preexistente).
- **Atualização posterior — ensaio conjunto no openSUSE:** 10 fixtures de #206 executadas no mesmo checkout do `sanitizar_ferret.py` endurecido em #207, total de 39/39 testes unitários aprovados; evidência e limites na Seção 6.

## 4. Sequência segura para reconciliação e validação

1. **Congelar hashes dos dois HEADs** e calcular interseção de caminhos novamente antes do ensaio. Não operar sobre a base `main` ou nas VMs.
2. **Montar uma árvore de teste descartável e separada**, baseada no HEAD de #207 e incorporando somente as alterações de #206 (XML, validador, testes, workflow e documentação); não substituir as branches de origem nem fazer merge de PR.
3. Rodar localmente, ou em PR experimental de CI explicitamente identificado, o validador `validar_regras_dlp_confidence.py`, os 10 testes `test_dlp_wazuh_contract_pr206.py` contra o sanitizador já endurecido de #207, os 29 testes GA-06.C e regressão de shell/XML. Anotar *número de testes executados* e resultado; **não marcar PASS antes da execução conjunta**.
4. Acrescentar teste negativo explícito de `files_processed=1` com `files_skipped` ausente: a política pode ainda considerar "sem achados" sem cobertura confirmada. Decidir se é necessário `coverage_status` (ou gate equivalente) **após** confirmar o JSON verdadeiro da CLI. Não alterar silently o contrato nem classificação da regra 110101 em produção.
5. Resolver **separadamente** a política de imagem imutável no #207. Nem config digest `1fab...` nem Docker descriptor `535...` equivalem ao digest de registry; exigir registro aprovado ou exceção formal documentada para TAR offline.
6. Quando EP126 voltar e houver janela institucional: verificação read-only do ruleset realmente carregado, `wazuh-logtest` com LOW/MEDIUM/HIGH, desconhecido, zero processados e parcial; scanner CLI sintético, escrita efetiva `tmpfs`, minimização e E2E; registrar rollback.
7. Só após gates + autorização decidir ordem de merge, preferencialmente isolar primeiro regra de classificação DLP e depois rollout v5 — sem confundir resultado de CI com deployment.

## 5. Situação objetiva em 26/10

- **Conflito textual de arquivos:** NÃO detectado na comparação atual (0 interseções).
- **Compatibilidade no ensaio offline:** COMPROVADA NOS 39 CENÁRIOS SINTÉTICOS EXECUTADOS NO MESMO TREE; não comprovada no Wazuh Manager/EP126.
- **DLP-O08:** mitigação conservadora PROPOSTA em #206, sem prova real de cobertura completa nem alerta de inconclusão.
- **PA-07-DLP-01:** correção de UI v5 HOMOLOGADA EM CONTÊINER TEMPORÁRIO, sem cutover; imagem / integração e reteste pendentes.
- **OBS-PA07-02:** classificação LOW/MEDIUM/HIGH CORRIGIDA NO XML DO PR #206, **não implantada no Wazuh Manager**.
- **PRs:** ambos continuam OPEN/DRAFT, sem merge; conta `lucy`, VMs, dashboards e dados reais não alterados nesta revisão.

**Natureza do documento:** análise, plano e atualização subsequente com evidência de teste conjunto offline; não comprova homologação operacional.

## 6. Ensaio integrado efetivamente executado em 26/10/2026 (17h57 BRT)

**Fonte:** arquivo da operadora `GA06_PR206_PR207_RESULTADO.txt` (96 linhas), SHA-256 `7cc9d2c41f18a420a9ee214595030a9498c637ffb78e33abe8b007f08409f738`. Host `opensuse-andrea`, repositório `/srv/www/htdocs/conectaeduca`. Esta é uma observação posterior às revisões estáticas das Seções 1–5.

A operadora executou `GA06_ENSAIO_PR206_PR207_OFFLINE.sh`. O shell criou uma worktree de teste a partir do PR #207 (`16dd92e6de73627781ec52a04faf4a8de620b2a9`) e combinou nela, via **merge local sem commit**, as alterações do PR #206 (`02f3a4d536a3a36eb06caef234b33a7d0c5aedee`).

**Saída registrada:** `CONFLITOS_GIT=NAO`, `DLP_CONFIDENCE_STATIC=PASS rules=3 cases=21 fallback=110110`, `DLP_COVERAGE_STATIC=PASS quiet_rule=110101 requires processed>0/skipped=0`, `XML_SYNTAX=PASS`, `ENSAIO_STATUS=PASS`, `VM_ACESSADA=NAO`, `MAIN_ALTERADA=NAO`, `PR_MERGE_REALIZADO=NAO`.

| Conjunto de testes do mesmo tree | Quantidade executada | Resultado |
|---|---:|---|
| PR #206: contrato sanitizador/regras Wazuh | 10 | PASS |
| PR #207: sanitização/limpeza | 13 | PASS |
| PR #207: proveniência sintética do Docker archive | 12 | PASS |
| PR #207: fluxo negativo process_one com mocks | 4 | PASS |
| **Total da execução integrada** | **39** | **39/39 PASS** |

**Conclusão no escopo testado:** a combinação de alterações dos dois PRs ocorreu sem conflitos no ensaio local e os 39 testes aprovados foram executados **no mesmo checkout**. Isso resolve a pendência documental de teste unitário conjunto da Seção 3; não resolve os problemas semânticos de `files_skipped` ausente, proveniência da build v5, teste de `wazuh-logtest`, integração CLI/Docker/Manager ou o Supply Chain Build Gate do PR #207.

**Estado de implantação:** PRs #206 e #207 continuam DRAFT, não mesclados na `main`, regras em runtime não alteradas. O procedimento usa fixtures sintéticas, Docker/`sudo` substituídos por mocks nas partes executadas; nenhuma VM institucional foi acessada segundo o log. A ausência de evidência de restauração efetiva de serviço, regras carregadas e backup permanece. Não marcar PA-07 ou OBS-PA07-02 como corrigidos em produção.

**Pré-relatório:** inclusão na versão integrada **v10** como Seção 18, com origem/limites e SHA-256 do log. O documento .docx/.pdf encontra-se como artefato desta conversa; não inferir que tenha sido implantado ou publicado no repositório.
