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


## Etapa 7 — Homologação funcional manual (30/10/2026, 17:32 BRT)

**Fonte:** `EP125_HOMOLOG_ETAPA7_20261030T173202.txt` enviado pela operadora. Host `ep125-pucpr`, modo `TESTE_FUNCIONAL_MANUAL`, sem credenciais, sem leitura de log e sem mudança de configuração.

| Controle | Resposta | Interpretação restrita |
| --- | --- | --- |
| LOGIN | S | Sucesso declarado pela operadora |
| MFA_SOLICITADO | S | Desafio apresentado |
| MFA_VALIDADO | S | Código legítimo validado; dashboard acessado conforme captura e relato anteriores |
| MFA_BLOQUEIO | S | Bloqueio declarado; falta verificação independente de bypass |
| RBAC_CANDIDATO | S | Fluxo básico declarado |
| RBAC_EMPRESA | S | Fluxo básico declarado |
| RBAC_ADMIN | S | Fluxo básico declarado |
| RBAC_NEGACAO | NA | **Não avaliado; não classificar como aprovado** |
| LOGOUT | S | Sucesso declarado |

**Limites:** o arquivo contém respostas manuais, não requisições/respostas HTTP, traces ou correlação de auditoria. Não inferir isolamento horizontal ou vertical a partir de navegação funcional.

### Roteiro reservado — pentest educacional de autorização (NÃO EXECUTADO)

**Pré-condições:** autorização e escopo definidos pelo professor; contas de teste próprias e dados sintéticos; autorização explícita para criar segunda conta candidato ou fixture; snapshots/backup e janela acordada; endpoints e identificadores reais documentados; sem alterar dados de terceiros. Manter taxa baixa, registrar horário, método, endpoint sem tokens e status HTTP, ID sintético, resultado esperado/obtido e hash de evidência.

- **PA-AUTHZ-HORIZONTAL (IDOR/BOLA):** com duas contas candidatas distintas A e B, criar recursos sintéticos separados. Autenticar A e tentar ler/editar somente o identificador do recurso sintético de B via fluxo autorizado. Esperado: 403 ou 404 e nenhuma leitura/alteração indevida. Se não houver segunda conta autorizada, marcar BLOQUEADO POR PRÉ-REQUISITO, não aprovado.
- **PA-AUTHZ-VERTICAL (BFLA/RBAC):** usar perfis candidato, empresa e administrador de teste. Mapear recursos e endpoints permitidos por papel. Para cada conta, tentar acessar uma rota/operação reservada a outro papel por navegação e requisição direta, sem ações destrutivas. Esperado: 403/404 ou redirecionamento controlado, sem execução de operação não autorizada. Não confundir ocultação de menu com autorização no servidor.
- **PA-MFA-NEGATIVO:** em conta própria, confirmar que sessão não autenticada completamente não alcança endpoint protegido; testar um único código inválido sob política de bloqueio, sem brute force. Esperado: recusa e ausência de sessão autenticada.
- **PA-SESSION:** confirmar que logout invalida sessão anterior e endpoints protegidos não aceitam reutilização de sessão encerrada; não registrar cookies/tokens nos artefatos.

**Situação:** roteiro preparado para execução posterior; nenhum desses testes de pentest foi executado nesta etapa. **Próxima homologação operacional:** Etapa 8, WAF com verificações benignas e autorizadas. Não fechar Grupo A/P0; EP126 ainda pendente.


## Homologação EP125 — Etapas 8–12 (30/10/2026, 17:48–17:53 BRT)

**Fonte:** evidências manuais enviadas pela operadora `EP125_HOMOLOG_ETAPA8_20261030T174842.txt`, `EP125_HOMOLOG_ETAPA9_20261030T174939.txt`, `EP125_HOMOLOG_ETAPA10_20261030T175041.txt`, `EP125_HOMOLOG_ETAPA11_20261030T175138.txt`, `EP125_HOMOLOG_ETAPA12_20261030T175300.txt`. Inspeções de leitura, sem reinícios ou alterações. Relatório local Daily 9 v19 consolidado, não anexado neste commit.

| Etapa | Evidência principal | Estado/limites |
| --- | --- | --- |
| 8 — WAF | Contêiner healthy; ModSecurity-nginx 1.0.4/libmodsecurity 3.0.16; **852 regras locais carregadas**; nginx -t OK; HTTPS 200, TLS_VERIFY=0 | **Estrutura OK**; bloqueio efetivo **não testado**; aviso ssl_stapling: issuer certificate not found |
| 9 — Auditoria | PHP/Nginx/WAF healthy; audit.log 34.128 bytes, modo 600; logs PHP em bind mount RW; mounts de segredos PHP RO | **Presença/metadata OK**; conteúdo/correlação de eventos não analisados; arquivo WAF não localizado nos caminhos amostrados |
| 10 — Retenção | bind `/var/log/conectaeduca/php-audit` → `/var/www/conectaeduca/storage/logs` RW; PHP docker log driver json-file, opções {}; WAF journald, tag conectaeduca-waf; SecAuditEngine RelevantOnly, LogType Serial, LogFormat JSON, StorageDir /var/log/modsecurity/audit/ | **Configuração identificada**; rotação e persistência após recriação **não comprovadas**; destino SecAuditLog foi mascarado pela coleta |
| 11 — TLS/headers | HTTPS 200, verificação curl 0, HTTP/2; CSP, HSTS, X-Content-Type-Options, Referrer-Policy, Permissions-Policy; certificado interno ConectaEduca Lab Root CA, CN conectaeduca.local, expira 13/10/2027 | **HTTPS funcional**; duplicados X-Content-Type-Options, Referrer-Policy e Permissions-Policy; X-Frame-Options SAMEORIGIN vs CSP frame-ancestors none; aviso ssl_stapling persiste. Script rotulou incorretamente versão HTTP como SSL_VERSION; negociação TLS 1.2/1.3 não provada individualmente |
| 12 — Hardening | PHP, Nginx, WAF running; usuários não-root (82,101,101); privileged=false; readonly rootfs=true; no-new-privileges=true; cap_drop ALL; CapEff=0; Seccomp=2 | **Controles verificados**; consulta de montagens de segredos falhou em todos os contêineres: template Docker não suporta hasPrefix. Repetir consulta sem função não suportada; não inferir ausência de segredos |

### Pendências priorizadas

1. Teste controlado, benigno e autorizado de **bloqueio real do WAF** e destino dos eventos ModSecurity.
2. Validar **rotação/retention** do audit.log PHP e do driver json-file; conferir daemon.json, logrotate, journal retention sem ler segredos ou recriar serviços.
3. Padronizar cabeçalhos duplicados e investigar se **OCSP Stapling** é aplicável ao certificado emitido pela CA interna; distinguir da futura cadeia pública ZeroSSL.
4. Repetir coleta de mounts de segredos com `docker inspect --format '{{range .Mounts}}{{println .Destination .Type .RW}}{{end}}'` e filtrar localmente, sem revelar conteúdo.
5. Correlacionar eventos de autenticação, autorização e auditoria sem dados sensíveis; comprovar persistência após recriação somente em janela aprovada.
6. Executar roteiro educacional de autorização horizontal/vertical e MFA negativo posteriormente, com duas contas sintéticas autorizadas e escopo formal.
7. EP126 indisponível em manutenção pelo suporte; não testar Wazuh/Bacula/Ferret nem declarar Grupo A/P0 concluído.

**Estado:** Etapas 8–12 concluídas como **diagnóstico**, não como homologação integral de todos os controles. Sem deploy, restart ou mudanças nas VMs pelo assistente.


## EP125 — Homologação Etapas 13 a 15B (30/10/2026)

- Etapa 13 (18:00): seis montagens de segredos em /run/secrets verificadas, quatro no PHP e duas no WAF, todas RW=false. Nginx sem montagens nesse diretório. Não houve leitura de segredos.
- Etapa 14 (18:01): WAF healthy; SecRuleEngine On, auditoria RelevantOnly em JSON, 852 regras carregadas. Sem montagens de logs em /var/log; aviso ssl_stapling continua. Bloqueio ainda não testado.
- Etapa 14B (18:02): SecAuditLog aponta para STDOUT; consulta direta ao journal inconclusiva.
- Etapa 14C (18:03): Docker journald; docker logs acessível com 83 linhas, das quais 41 com indicadores ModSecurity/transaction/messages e zero com expressão access denied. Journal do host inacessível ao usuário. Não interpretar linhas como ataques nem como transações distintas.
- Etapa 15 (18:03): sem parâmetros explícitos de retenção journald identificados; /var/log/journal e /run/log/journal presentes; consulta de ocupação inconclusiva; PHP usa json-file sem opções explícitas, WAF usa journald; logrotate instalado. Diretório de auditoria PHP não encontrado por acesso direto.
- Etapa 15B (18:05): docker inspect confirma bind mount RW do PHP com origem /var/log/conectaeduca/php-audit; teste direto no host retornou caminho inexistente ou inacessível e stat falhou. daemon.json ausente ou inacessível. Divergência permanece sem causa estabelecida.

**Conclusão:** montagens de segredos somente leitura comprovadas; auditoria WAF recuperável via docker logs; retenção, acesso ao diretório do host, bloqueio WAF, integração Wazuh e testes RBAC negativos ainda pendentes. Não houve alterações ou reinícios. EP126 sob manutenção; Grupo A/P0 não concluído.
