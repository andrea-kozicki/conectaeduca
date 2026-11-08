# GA-06 / PA-07 — checklist de campo para Ferret UI v5 na EP126

**Preparado:** 02/11/2026 (BRT). **Janela-alvo condicionada:** 03/11, após snapshot EP126 e autorização.
**Estado:** CHECKLIST DOCUMENTAL; NÃO executa mudança. A PR [#207](https://github.com/andrea-kozicki/conectaeduca/pull/207) permanece DRAFT e a imagem ativa **continua Ferret 2.4.3**.
**Fontes canônicas:** `docs/release/GA06-CHANGE-CONTROL-V5-EP126-20261101.md` e `docs/release/GA06-FERRET-V5-IMAGEM-ROLLOUT-EP126-20261025.md`, **na branch da PR #207**. Não aplicar este resumo se divergir do runbook atualizado.

## 1. O que foi comprovado e NÃO precisa ser repetido antes de mudança causal
| Item | Evidência de 01–02/11 | Limite |
| --- | --- | --- |
| Imagem oficial ativa | Baseline `public.ecr.aws/awslabs/ferret-scan:2.4.3@sha256:7a1b36050ae20a74632ac05b5c34e4aeb26b69836ca6703e10c1392b724b270f` | v5 ainda não ativa |
| Candidata v5 | Alias `localhost/conectaeduca/ferret-scan:2.4.3-pa07-v5-candidate`, Docker Image ID `sha256:535ec9efb590dbaaeca41123321d773ba6d26d338686d89605492380ae9e187d`, Linux/amd64 UID1000 | tag mutável, **não** digest de registry |
| Custódia de TAR | SHA-256 previsto `5786c56b47d7bb93604126e30cfbfb4fc549f5b1f791262fbe591555ead785a2`; verificação de TAR/imagem/Compose reportada PASS em 01/11 | revalidar artefato exato na janela |
| Override PR #207 | somente `image` e `pull_policy: never` diferentes no Compose efetivo do candidato | CLI efêmera deve usar mesmo override |
| Canário v5 | 25/10: saúde, JS UI e scan sintético, tmpfs 0700 UID1000 PASS no contêiner temporário EP126 | sem cutover e sem regressão no serviço principal |
| Monitor atual | Timer systemd ativo; versão exata esperada `2.4.3`; candidato usa `2.4.3+ce.pa07.v5` | drop-in v5 não instalado |
| Backup local | Em 01/11 TAR privado `/var/backups/conectaeduca/ga06/ferret-pre-v5-20261101T173155.tar`; `tar -tf` PASS; SHA256 `24f7268fa836e5dff027ffe795f24252f1714ec5efa25000be6501ae242a0e16` | serviço estava ativo; snapshot/restauração não comprovados |
| Ruleset Wazuh PR #206 | Regra operacional SHA256 `3f00bd1adc0d81886c1867da190c96ec7bd41ff1fd980e6e5c0334929dbd7fcd`; `wazuh-logtest` 7/7, MEDIUM/HIGH E2E 2/2; regra 110101 9/9 | separa testes isolados de scan CLI real |
| Scripts PR #207 na EP126 | **Instalados em 02/11:** sanitizador SHA256 `e2e4a7e32288eaae6b4c5cf9cf7b48a0de803a852a879f53e745211e6458bf12`; validador SHA256 `35d88ddcb449f8f5e5ac506aab1eebf23fe4d19fcf1559f0f7966036f1e765c1`; GA07.7B `PASS` com backups | modificações **locais** na `main` EP126, sem merge PR #207 |
| Smoke pós-promoção | GA07.8R 6/6: summary completo→110101, quatro negativos de cobertura→NO_MATCH, MEDIUM→110112 nível 8; Manager healthy | não executou Ferret CLI real nem v5 |
| CI PR #207 | 6 workflows success no HEAD `1c7b8e12524f07cea400e83a35775dc49755807b` em 02/11 | CI não aprova change control |

**NÃO repetir a GA07.8R** e não tentar consertar script Python que já tem hash aprovado. Não fazer segundo cutover silencioso via `git pull` ou reposicionar `main` EP126 sem resolver as duas alterações locais deliberadas. Backups GA07.7B no diretório privado `~/ConectaEduca_Fase2_Evidencias/EP126/GA07/GA07_7B_cxonskrl`.

## 2. Gate GA06-G0 — requisitos da implantação de v5
| Verificação antes do cutover | Situação em 02/11 |
| --- | --- |
| Snapshot EP126 identificável, recente, cobertura de disco, .runtime e storage, operador e retorno confirmado | **AGUARDANDO SUPORTE 03/11** |
| Autorização conforme política institucional, operador, janela, aceitação de exceção TAR local / outro canal permitido | **PENDENTE** |
| Backup/rollback de dados e supressões, estado, inbox, reports/raw, configuração e permissões sem exposição no Git | **PENDENTE ACEITE DE RESTAURABILIDADE** |
| TAR verificado no host com SHA256 exato + proveniência, Docker Image ID real e alias imutável apenas por hash verificado | **REVALIDAR NO CUTOVER** |
| Compose baseline e override opt-in `pull_policy: never`, network/port/UID/mounts/tmpfs/read_only/cap_drop e Image IDs | **REVALIDAR DRIFT** |
| Versão do health monitor/serviço systemd sincronizada com v5 e plano de retorno à versão 2.4.3 | **PLANEJADO; NÃO EXECUTADO** |
| Pipeline CLI efêmero usa a mesma imagem candidata, sob `FERRET_COMPOSE_OVERRIDE`; sem fallback/pull | **PLANEJADO; RETESTE PENDENTE** |
| Preservar imagem baseline 2.4.3 e segredos/supressões; nenhuma limpeza de volumes, alias, CA ou log bruto | **OBRIGATÓRIO** |

**Interpretar corretamente quem autoriza:** permissões operacionais de Docker permitem execução técnica pela responsável, mas não suprem requisitos de aprovação institucional para o **transporte/uso do TAR e a janela de manutenção** definidos no change control #207. Obter o aceite exigido; não delegar o comando ao suporte se não for necessário.

## 3. Sequência de campo — após G0
1. **Congelar concorrência e registrar baseline**: versão `/health=2.4.3`, HTTP UI na loopback 127.0.0.1:18082, imagem/container reais, timer e logs minimizados; preservar estado DLP, segredos e backups.
2. **Custódia:** executar preflight somente leitura da PR #207 `scripts/evidencias/ga06_preflight_tar_local.sh --archive CAMINHO_PRIVADO` **apenas com TAR aprovado e presente**; registrar SHA-256 e Image ID. Não obter TAR de fonte improvisada nem fazer `docker load/pull` automático.
3. **Compose:** confrontar config real com base + `deploy/interna/ferret/pa07-v5/compose.pa07-v5.override.yml`; somente `image` e `pull_policy` mudam. Confirmar UID/GID1000, read-only, network, porta loopback, tmpfs `0700,uid=1000,gid=1000`, volumes e health no mesmo contexto.
4. **Monitor:** instalar **na janela autorizada** apenas o drop-in dedicado `90-ga06-ferret-v5-healthcheck.conf` com `FERRET_EXPECTED_VERSION=2.4.3+ce.pa07.v5`, preservar estado anterior; pausar timer apenas pelo intervalo aprovado, reativando-o após health. Não usar `systemctl revert` genérico.
5. **Cutover:** utilizar **somente** o procedimento de mudança aprovado do runbook #207 (sem reproduzir comandos privilegiados neste resumo). Manter imagem antiga e mounts; nunca `down -v`, `image prune` ou `pull`.
6. **Regressão dirigida de 6 cenários** (Tabela abaixo). Um único teste que demonstre falha/ausência de inspeção não pode aparecer como `No sensitive data found`.
7. **Decisão:** se todos os passos obrigatórios PASS, registrar estado e manter v5; se houver falha crítica, interromper e executar retorno ao baseline conforme runbook com confirmação da operadora. Sem G0 não há tentativa de cutover.

## 4. GA06 pós-cutover — matriz curta de testes (não marcar como executada)
| ID | Situação sintética | Esperado e critério |
| --- | --- | --- |
| F5-UI-01 | POST /scan HTTP403 simulado; aguardar ≥15s | UI **INCONCLUSIVE**, falha contabilizada, sem `No sensitive data found`, exportação bloqueada |
| F5-UI-02 | HTTP500/timeout ou falha de rede simulada, sessão repetida | UI INCONCLUSIVE persistente, sem estado `COMPLETED` falso e sem exportar |
| F5-UI-03 | `success:true` com `results` ausente/nulo/malformado | falha fechada, não mostra clean |
| F5-UI-04 | dois scans sucessivos: um válido e outro inválido | sem herdar resultados/estado limpo do anterior |
| F5-CLI-05 | contêiner CLI efêmero, fixture inerte, supressões/allowlist, JSONL | mesma imagem v5, `source=ferret-scan`, `schema_version=1`, flags `*_reported`, nenhuma string/arquivo bruto no evento |
| F5-SIEM-06 | fixture sintética CLI→sanitizador→validador→Wazuh Agent002/Manager | summary/finding de acordo com contadores, regra classificada e sem segredo no SIEM; não confundir `wazuh-logtest` com ingestão |

**Aceite PA-07 limitado:** reteste da UI corrigida, CLI+SIEM e integração de supressões não concluem automaticamente **egress bloqueado** nem **Bacula restore**. Estes são gates distintos do PA-07/Pentest B.

## 5. Gatilhos de aborto e rollback
Aborto imediato: TAR/Imagem/Compose divergem, snapshot não comprovado, health/monitor v5 incompatível, timer não retorna, 403 tratado como limpa, UI/CLI não sincronizados, auditoria Wazuh perdida, supressões/estados inacessíveis, acesso externo fora do loopback, mount/permissão alterados ou reconstrução inesperada de stack.

- Retornar à **imagem oficial 2.4.3 fixada por digest**, sem override v5; remover **somente** drop-in GA06 criado, restituir expectativa do monitor `2.4.3`; preservar state/inbox/reports/raw/JSONL e UID; validar `/health`, UI/CLI e Wazuh.
- O backup local TAR de 01/11 é prova de cópia, não prova de restore. Caso retorno Docker não seja possível, acionar snapshot institucional EP126 com suporte, sem inventar tempo de RTO.
- O retorno precisa de evidência positiva; nunca marcar `ROLLBACK=PASS` por executar script não testado.

## 6. Formulário simples de evidências (preencher após execução)
```text
GA06_V5_CUTOVER=NAO_EXECUTADO
SNAPSHOT_EP126_ID=
SNAPSHOT_COBERTURA_E_RESTAURABILIDADE=
AUTORIZACAO_JANELA=
OPERADOR=
TAR_SHA256_VERIFICADO=
IMAGE_ID_VERIFICADO=
COMPOSE_ONLY_IMAGE_POLICY_CHANGED=
MONITOR_VERSION_BEFORE_AFTER=
FERRET_VERSION_FINAL=
CLI_IMAGE_ID_EFETIVA=
F5_UI_01_04=
F5_CLI_05=
F5_SIEM_06=
PR207_MERGE=NAO_REALIZADO
GIT_MAIN_EP126_MODIFICADO_2_ARQUIVOS=SIM
EVENTOS_SEM_SEGREDO=
ROLLBACK_EXECUTADO=NAO
EVIDENCIA_LOCAL_SANITIZADA=
SHA256_EVIDENCIA=
STATUS_FINAL=PLANEJADO
```

**Continuidade:** [matriz A×B](../fase3/PA01-PA07-MATRIZ-PENTEST-A-B-20261102.md), [handoff 03/11](../fase3/HANDOFF-03NOV-2026-ZT-PA-GA08-GA06.md), [PR #206](https://github.com/andrea-kozicki/conectaeduca/pull/206).
