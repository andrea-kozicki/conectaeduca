# Diário operacional — EP125 — 30/10/2026 (BRT)

## Reconciliação Git controlada — concluída (código, sem deploy)

- VM: ep125-pucpr; usuário operacional: andrea.kiew; repositório: /opt/conectaeduca; branch: main.
- HEAD antes: `4bf7ac688b1ea738cd158f03a20b07732cdd90a3` (merge PR #202 PHP-FPM 8.5.12).
- Destino fixo da main remota: `b74ea581a0814d86a99b6b455d5569f12fa967e5`.
- Procedimento: precheck read-only, verificação de fast-forward, backup do overlay local, `git fetch` por SHA, `git merge --ff-only` e atualização da referência `origin/main`.
- Resultado: 27 commits aplicados por fast-forward, 10 arquivos versionados alterados (467 inserções, 16 exclusões); `HEAD...origin/main = 0 0`; árvore rastreada limpa.
- Único untracked preservado: `deploy/dmz/compose.audit-persistent.yml`; SHA-256 original e backup: `36469d6694b9eb2e802822946efd788ffb1e97c95170d0f2680731a98699998e`. Backup em `/home/andrea.kiew/ConectaEduca_Reconciliacao_EP125_20261030T164204/`.
- Overlay é o 10º arquivo Compose efetivo; montagem PHP de auditoria confirmada: `bind /var/log/conectaeduca/php-audit -> /var/www/conectaeduca/storage/logs`.
- PHP-FPM, WAF e Nginx: `healthy` após atualização Git. `StartedAt` UTC: PHP 19:06:58, WAF 19:06:56, Nginx 19:06:55 (16:06 BRT), `RestartCount=0` em todos. Causa do início recente não determinada; não atribuir ao script.
- Evidência local: `/home/andrea.kiew/ConectaEduca_Reconciliacao_EP125_20261030T164204/reconciliacao_git_20261030.txt`; `git-head-before.txt`; backup do overlay; resultados da validação pós-reconciliação apresentados pela operadora.
- **Limite do aceite:** reconciliação do Git na EP125 concluída. **Não houve deploy nem recriação de containers neste procedimento.** Não equivale a homologação operacional, testes de login/MFA/RBAC, WAF ou persistência após recriação. EP126 permanece sem reconciliação comprovada neste registro.
- Próximos gates: homologação operacional EP125, esclarecer reinício recente se necessário, reconciliação EP126, PRs draft e mudanças de runtime sob change control com rollback.
