# GA-08 — Revisão offline de integração e critérios de homologação (29/10/2026)

**Escopo:** revisão documental dos arquivos do branch `docs/fase3-arquitetura-zero-trust-20261021`. **Não representa execução em EP125/EP126.** Nenhum deploy autorizado; gate fechado.

## Arquivos efetivamente inspecionados
- `deploy/dmz/compose.yml`, `compose.database.yml`, `compose.app-secrets.yml`, `compose.waf.yml`, `compose.waf-tls.yml`, `compose.waf-policy.yml`, `compose.host.yml`, `compose.ga08-socket.candidate.yml`.
- `deploy/dmz/nginx/Dockerfile`, `deploy/dmz/nginx/app-http.conf`, `deploy/dmz/ga08/app-http.socket.candidate.conf`.
- `deploy/dmz/php/Dockerfile`, `deploy/dmz/php/zz-conectaeduca.conf`, `deploy/dmz/ga08/zz-conectaeduca.socket.candidate.conf`.
- `scripts/ga08-implantacao-controlada-ep125.sh` e `scripts/ga08-rollback-controlado-ep125.sh`.

## Constatações verificadas no código
1. O candidato usa `networks: !override`: WAF e Nginx em `waf_backend`, PHP em `php_egress`. Exige teste runtime de isolamento; PASS estático não comprova isolamento efetivo.
2. Nginx e PHP compartilham bind mount `/run/conectaeduca-fpm`. Nginx monta somente leitura e recebe `group_add: ["82"]`; PHP monta escrita. Verificar UID/GID, diretório 0770, socket 0660, SELinux/AppArmor se aplicável, ciclo de recriação e persistência do diretório host.
3. O Nginx candidato conserva a configuração-base, trocando seis destinos `fastcgi_pass php:9000` por `fastcgi_pass unix:/run/conectaeduca-fpm/php-fpm.sock`.
4. O healthcheck da imagem PHP executa `php-fpm -t`, validando sintaxe/configuração, mas não comprova que Nginx consegue conectar ao socket. O healthcheck Nginx consulta `/_container_health` local, sem passar pelo PHP. O WAF TLS testa `/healthz` via HTTPS. Logo, os três sinais de saúde não substituem o teste integrado `/_fpm_ping` e fluxos reais.
5. O `depends_on` do Nginx espera PHP healthy e o WAF espera Nginx healthy. A condição de healthy não equivale a fluxo de ponta a ponta aprovado.
6. O overlay `compose.host.yml` preserva parâmetros de DB_HOST e DB_PORT na EP126; conectividade e autenticação SQL após mudança de redes seguem pendentes.
7. `compose.waf.yml` elimina a publicação host 8088 do Nginx; `compose.host.yml` publica WAF nas portas configuradas. Confirmar a configuração final mesclada e a ausência de bypass do WAF.
8. O script de implantação mantém `exit 3` e `APLICACAO=NAO_EXECUTADA`; a mensagem do gate foi corrigida no commit `9a7f47cc50e03d5d6f93fb4ea5b92c6d70276bb4`. O script de rollback atual faz apenas preflight: **não existe rollback operacional validado**.

## Plano de execução posterior, somente com autorização e janela
| ID | Verificação | Evidência exigida | Critério |
|---|---|---|---|
| G01 | Config final mesclada com overlays na ordem real | saída redigida de `docker compose config` | sem redes compartilhadas PHP/WAF, mounts corretos |
| G02 | Socket e permissões | `stat` do diretório/socket, UID/GID e processo | conexão Nginx→FPM sem privilégios adicionais |
| G03 | Healthchecks e rota FPM | estados de containers e `/_fpm_ping` via WAF | `pong`, app saudável |
| G04 | Isolamento lateral | tentativa controlada PHP→Nginx:8080 e PHP→WAF | conexão bloqueada conforme política |
| G05 | Comunicação com EP126 | TCP e teste SQL autenticado, sem expor credenciais | operação autorizada bem-sucedida |
| G06 | WAF/TLS e rotas | respostas HTTPS, cabeçalhos e logs de WAF | sem regressão e sem acesso direto ao Nginx |
| G07 | Logs e observabilidade | eventos WAF e trilha PHP/Wazuh | evidências coletáveis |
| G08 | Rollback | backup imutável de Compose/config/env sanitizado, procedimento e ensaio | retorno comprovado ao baseline |

## Bloqueios e critérios de não promoção
- Não efetuar merge/deploy enquanto G01–G08 não estiverem executados ou aceitos com justificativa explícita.
- Não publicar segredos nem valores reais de `.env` em issues, PRs ou evidências.
- Não afirmar que a PA-02 foi remediada apenas pelo PASS estático.
- Não executar o script de rollback como se já revertesse a implantação: ele é apenas diagnóstico.

**Situação em 29/10:** revisão de código concluída; testes runtime, autorização, rollback e evidências operacionais pendentes.
