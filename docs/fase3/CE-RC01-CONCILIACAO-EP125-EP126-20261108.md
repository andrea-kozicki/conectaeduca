# CE-RC01 — Reconciliação factual GitHub ↔ EP125 ↔ EP126

**Data/hora das coletas (BRT):** EP125 08/11/2026 14:34:28; EP126 08/11/2026 14:36:05.  
**Responsável:** Andréa Kozicki.  
**Proveniência:** saídas de terminal fornecidas pela responsável em 08/11/2026; não são execuções remotas pela ferramenta do GitHub.  
**Escopo:** coleta read-only CE-RC01; não equivale à validação integral dos runtimes, do Zero Trust, da integridade do OpenBao, dos PAs ou à comprovação de correções implantadas.

## Baseline do repositório

`main` observado no GitHub em 08/11/2026: `b74ea581a0814d86a99b6b455d5569f12fa967e5`. Comparação GitHub do commit EP126 `4bf7ac688b1ea738cd158f03a20b07732cdd90a3` ao baseline: **27 commits à frente, zero atrás**, dez arquivos distintos. A consulta não foi um `git fetch` nas VMs.

## EP125 — DMZ

- Host `ep125-pucpr`; branch `main`, `HEAD` e cache local `origin/main` iguais a `b74ea581a0814d86a99b6b455d5569f12fa967e5`.
- `DIRTY_TRACKED_COUNT=0`; `ALTERACOES_AREAS_TOTAL=0`; **`UNTRACKED_AREAS_TOTAL=7`** nas áreas examinadas (não inclui arquivos ignorados).
- Connector **nativo** Twingate `systemd`: `loaded/active/running/enabled`; versão `1.95.0`; `NRestarts=0`.
- Docker: WAF, Nginx e PHP-FPM `Up (healthy)` na amostra.
- **Interpretação:** checkout alinhado ao baseline GitHub; ainda NÃO foi comprovado que conteúdos de imagens Docker e configurações em execução reproduzem o código Git. Sete arquivos não rastreados merecem classificação antes de qualquer limpeza.

## EP126 — Intranet

- Host `ep126-pucpr-br`; branch `main`; `HEAD` e cache local `origin/main`: `4bf7ac688b1ea738cd158f03a20b07732cdd90a3`, **27 commits atrás do baseline GitHub** (linearidade confirmada pela API).
- `DIRTY_TRACKED_COUNT=3`; `ALTERACOES_AREAS_TOTAL=1`; alteração nomeada **na área inspecionada**: `deploy/interna/wazuh/config/rules/conectaeduca_dlp_rules.xml`. Os outros dois caminhos rastreados alterados estão fora das áreas selecionadas no CE-RC01 e ainda NÃO foram classificados.
- **`UNTRACKED_AREAS_TOTAL=3`** nas áreas examinadas, sem nomes divulgados.
- Connector **nativo** Twingate `systemd`: `loaded/active/running/enabled`; versão `1.95.0`; `NRestarts=1`.
- Docker: 12 serviços listados em execução; nove com status explicitamente `healthy`; **OpenBao 2.6.1 `Up (unhealthy)`**; Bacularis e Ferret `Up` sem indicação de `healthy` nesse inventário.
- **Interpretação:** preservar alterações locais, sobretudo regra Wazuh DLP, antes de qualquer sincronização. `unhealthy` não prova por si só indisponibilidade ou causa raiz; investigar de modo read-only, sem restart/unseal ou divulgação de credenciais.

## Comparação entre commits remotos GitHub

Arquivos diferentes entre o commit da EP126 e o baseline:
- `.github/workflows/repository-static-integrity.yml`
- `.gitleaks.toml`
- `composer.lock`
- `docs/seguranca/PA03-COMPOSE-STATIC-GATE-20261026.md`
- `docs/seguranca/PA05-RBAC-NEGATIVOS-CANDIDATURAS-20261026.md`
- `scripts/evidencias/checkpoint_compose_security_invariants.py`
- `src/Security/AuditLogger.php`
- `tests/Unit/AuditLoggerRedactionTest.php`
- `tests/Unit/Security/HorizontalOwnershipContractTest.php`
- `tests/python/test_pa03_compose_inline_lists.py`

Esses são *arquivos entre commits versionados*, NÃO o inventário de diferenças em runtime, e não incluem o delta local da regra DLP.

## Próximos gates e decisões

1. **Read-only EP126:** classificar os três arquivos rastreados alterados, sem expor caminhos ou conteúdo de segredos; distinguir mudanças de código, regras Wazuh e configurações locais. Conferir `git diff --check` sem alterar arquivos.
2. **Read-only ambas:** classificar apenas diretórios/categorias dos sete + três arquivos não rastreados, sem copiar certificados, tokens, chaves, `.env` ou configurações para o GitHub.
3. **OpenBao EP126:** conferir status técnico/healthcheck limitado e o impacto funcional com operador autorizado; não realizar unseal/restart/recreate.
4. **Mudanças candidatas:** selecionar PR isolada para cada delta seguro; CI, snapshot/rollback demonstrado, testes funcionais e evidências. Não executar `git pull`, `git reset`, `git clean`, `docker compose up` ou alterar pfSense por este registro.
5. **Pentest B 08–14/11; relatório/apresentação até 17/11:** diferenciar controles implementados e retestados, testes parciais e riscos residuais.

**Status:** CE-RC01 executado nas duas VMs; reconciliação operacional **em andamento**. Nenhum commit nas VMs, nenhum deploy, nenhuma correção de PA e nenhuma homologação declarados por este documento.
