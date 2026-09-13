# Evidência final — Wazuh service-layer pré-freeze — 12/09/2026

## Escopo

Fechamento da auditoria e promoção pós-merge do Wazuh central na EP126, após correções de serviço e do validador operacional.

## Estado Git

- branch final: `main`;
- HEAD final: `9bdfdfeeec306a00f6609ae21e1ca6957163a0c3`;
- worktree final: limpo;
- PR #62: hardening de serviço;
- PR #63: validador ACL-aware para `wazuh.yml`;
- PR #64: `getfacl` condicional somente no ramo ACL-backed.

## Integridade do relatório operacional

- arquivo local: `conectaeduca-wazuh-servico-posmerge-v9-python-final-ep126-pucpr-20260912-234717.txt`;
- SHA-256: `6db32e5e92ee4f2a0006f81a34151b7fb35ccdcee4f080eeaaa2759cdd7e6f49`;
- o relatório bruto permanece local; esta evidência versionada registra o resumo sanitizado.

## Resultado operacional

```text
PASS=145
WARN=0
FAIL=0
GAP=0
INDEXER_PROMOTED=SIM
DASHBOARD_PROMOTED=SIM
ROLLBACK_USED=NAO
MANAGER_RECREATE=NAO
SUDO_USED=NAO
SEGREDOS_IMPRESSOS=NAO
```

## Controles comprovados

- Manager permaneceu invariável em ID/PID/StartedAt e `healthy`;
- Indexer promovido e `healthy`, preservando exatamente o mesmo IMAGE ID;
- Dashboard promovido e `healthy`, preservando exatamente o mesmo IMAGE ID;
- `plugins.security.allow_default_init_securityindex=false`;
- `opensearch.ssl.verificationMode=full`;
- `opensearch_security.cookie.secure=true`;
- Dashboard -> Indexer validado por CA e hostname;
- cookie observado com `Secure + HttpOnly`;
- HTTP plaintext do Dashboard não funcional;
- Indexer TCP/9200 privado;
- Manager TCP/55000 privado;
- Manager TCP/1515 fechado;
- Dashboard preservado no binding administrativo em loopback;
- `no-new-privileges`, `cap_drop ALL` e limites de PID preservados no Indexer/Dashboard;
- validador operacional versionado aprovado antes e depois da promoção.

## Conclusão

A camada de serviço do Wazuh central está **CONCLUÍDA** para o baseline pré-freeze. Os riscos residuais aceitos continuam documentados em `deploy/interna/wazuh/SERVICO-PREFREEZE.md`.

Próximo gate técnico: auditoria residual read-only de MariaDB e PostgreSQL/Bacula Catalog.
