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


## Homologação operacional EP125 — Etapas 1 a 6 — 30/10/2026 (BRT)

**Fonte:** saídas de terminal da operadora e evidência TXT da Etapa 6; evidências completas permanecem na EP125, não anexadas ao GitHub. Registros automáticos no diário local confirmados nas Etapas 2–6; Etapa 1 foi incorporada ao diário local por atualização de arquivo.

| Etapa | Horário BRT | Evidência e resultado | Limite |
| --- | --- | --- | --- |
| 1 | 17:01 | PHP/WAF/Nginx running/healthy; HTTPS /, /login.php, /api/public_key.php e /assets/js/crypto-utils.js com HTTP 200 e TLS_VERIFY=0. | Sem autenticação ou prova de regra WAF. |
| 2 | 17:03 | HTTPS HTTP 200/TLS_VERIFY=0; bind PHP audit RW; audit.log presente, 28.360 bytes, modo 600. SHA256 evidência `c1985b4f228a8edf0b0f3d75baf0090426569e638697d469294c7a46df17ae83`. | Sem teste de persistência após recriação. |
| 3 | 17:07 | Somente WAF publica portas no host (192.168.6.34:80/443); Nginx/PHP sem portas publicadas. HTTPS HTTP/2 200, CSP/HSTS presentes. audit.log no contêiner 28.360 bytes, 0600, UID/GID 82; acesso pelo host inconclusivo. SHA256 `e520c8aa9afef90b461fff203e8d8902adffa6aaa463cc8988196368a32fb51d`. | Cabeçalhos X-Content-Type-Options e Referrer-Policy duplicados; regra WAF não comprovada. |
| 4 | 17:09 | Bind RW; host retorna Permission denied para stat; diretório no contêiner 0700, arquivo 0600, UID/GID 82. SHA256 `85b22fbee0a33afd5e11bc7a1670255100f4821a0c314ea5b18c09f049f0ef46`. | Restrição de acesso compatível com permissões; sem escrita ou recriação de contêiner. |
| 5 | 17:11 | WAF running/healthy, publica 80/443; / e /login.php HTTP 200, TLS_VERIFY=0. SHA256 `9f145aaeb0f4ce2ad67ac1fafecb90b233707cc6fbbdf5a9c964c5a17c865bb0`. | Sem evidência de bloqueio de regras WAF. |
| 6 | 17:11 | Login legítimo **bem-sucedido, conforme relato da operadora**; aplicação **solicitou MFA**, conforme relato. audit.log cresceu de 28.360 para 29.294 bytes (+934), resultado ARQUIVO_CRESCEU. Operadora confirmou DIARIO_ATUALIZADO=SIM. | Conteúdo do log não inspecionado: crescimento não atribuído conclusivamente ao login; solicitação de MFA não equivale à validação completa de MFA/segregação de papéis. |

**Caminhos de evidência na EP125:** `/home/andrea.kiew/ConectaEduca_Fase2_Evidencias/EP125/HOMOLOG/EP125_HOMOLOG_ETAPA{2,3,4,5,6}_20261030T*.txt`; diário local `/home/andrea.kiew/ConectaEduca_Fase2_Evidencias/EP125/diario.md`. A evidência da Etapa 6 foi compartilhada como `EP125_HOMOLOG_ETAPA6_20261030T171146.txt`; nela constam tamanho antes/depois e interpretação de escrita observada.

**Conclusão parcial:** disponibilidade e TLS das rotas testadas satisfatórios; exposição de portas consistente com ingress WAF; login positivo e apresentação de desafio MFA observados; escrita em audit.log observada. **Pendências:** completar MFA (conclusão e negação de bypass), RBAC por perfil, regra WAF em cenário benigno controlado, correlação do evento de auditoria, retenção/rotação, persistência pós-recriação sob change control, reconciliação EP126 e aceite Grupo A. Nenhum deploy/restart/alteração de firewall autorizado ou executado nestas homologações. Não fechar o P0 global.

### Adendo — MFA positivo confirmado por captura de tela (30/10/2026)

A operadora confirmou que, após login, digitou o código MFA correspondente à conta de teste e **acessou normalmente o dashboard**. Captura de tela compartilhada na conversa mostra área autenticada, dashboard, nome da conta de teste e perfil `usuario`. **Fluxo positivo login → desafio MFA → código válido → dashboard: aprovado por relato e captura de tela.** A captura não contém o código MFA nem prova por si só os controles negativos. Permanecem pendentes: rejeição de código inválido, impossibilidade de acesso antes do MFA, RBAC de candidato/empresa/admin e validação de sessão. A imagem permanece como evidência da conversa; não foi copiada ao repositório para evitar divulgar dados da conta de teste.
