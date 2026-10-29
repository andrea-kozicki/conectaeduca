# ConectaEduca — Relatório técnico consolidado da GA-08 / PA-02.I — 28/10/2026

## Resumo executivo
A mitigação proposta para o caminho interno PHP→Nginx sem inspeção WAF avançou de hipótese arquitetural a **candidato Compose estaticamente validado**, com ensaio integrado efêmero Nginx→PHP-FPM por socket Unix. **Nenhum deploy foi executado; o bypass no ambiente produtivo não foi declarado corrigido.** O PR #200 permanece DRAFT e o cartão PA-02.I aberto.

## Contexto e risco
A configuração operacional da EP125 mantém WAF, Nginx e PHP na bridge Docker frontend. A comunicação direta PHP→Nginx:8080 foi observada sem atravessar WAF; GET /healthz direto retornou HTTP 404, que prova caminho de comunicação, não exploração ou bypass funcional de regra. Nginx não publica a porta 8088 no host. A solução proposta separa redes de serviços e troca FastCGI TCP por socket Unix compartilhado entre Nginx e PHP-FPM.

## Arquitetura candidata
- WAF: somente rede waf_backend; Nginx: somente rede waf_backend.
- PHP: somente rede php_egress, preservando requisito de saída TCP à EP126:3306.
- Nginx→PHP-FPM: Unix socket /run/conectaeduca-fpm/php-fpm.sock em volume compartilhado; grupo suplementar 82 no Nginx.
- Overlay: deploy/dmz/compose.ga08-socket.candidate.yml; configuração Nginx app-http.socket.candidate.conf; PHP-FPM zz-conectaeduca.socket.candidate.conf.
- Requer validação de acessos positivos e negativos em runtime, DNS/redes, permissões, TLS, aplicação e rollback.

## Evidências obtidas em 28/10
1. Ensaio de socket efêmero: PHP-FPM iniciou, socket UID82/GID82 modo 660; Nginx UID101 com grupo suplementar 82 acessou FastCGI e recebeu **pong**; contêineres sem rede e sem portas publicadas; STATUS=INTEGRACAO_OK. Arquivo GA08_NGINX_FPM_INTEGRADO_V4_20261028T215119.txt.
2. EP125→EP126: PHP em execução/healthy, conexão TCP para EP126:3306 OK; **não** foi testada autenticação SQL. Arquivo GA08_EP126_*.
3. Diagnóstico Compose: docker compose v5.5.1; docker compose version e docker info via Python PASS. Erro inicial de 37 bytes foi obscurecido pelos diagnósticos. Validação incremental localizou variáveis obrigatórias dos overlays de banco, app-secrets (CONECTAEDUCA_PRIVATE_KEY_FILE, CONECTAEDUCA_PUBLIC_KEY_FILE) e WAF-TLS (CONECTAEDUCA_WAF_TLS_CERT_FILE, CONECTAEDUCA_WAF_TLS_KEY_FILE).
4. A primeira falha em compose.host.yml ocorreu com placeholders de caminho aplicados a campos de porta/endereço; após uso de valores fictícios de tipo correto, **todos os dez arquivos base passaram**. Arquivo GA08_COMPOSE_TIPOS_20261028T224843.txt: STATUS=COMPOSE_BASE_PASS.
5. **Marco final estático:** overlay candidato agregado aos dez arquivos base; docker compose config exit 0; WAF_REDES=waf_backend; NGINX_REDES=waf_backend; PHP_REDES=php_egress; REDES_SEGREGADAS=PASS; NGINX_GRUPO_82=PASS; NGINX_SOCKET_MOUNT=PASS; PHP_SOCKET_MOUNT=PASS; STATUS=COMPOSE_CANDIDATO_PASS. Evidência GA08_COMPOSE_CANDIDATO_20261028T224951.txt.
6. Scripts e evidências armazenados em ~/ConectaEduca_Fase2_Evidencias/EP125/GA08; checkpoints e resultados anexados ao diario.md da EP125 por comandos e scripts executados. Nenhuma senha, chave ou certificado real foi utilizado na validação fictícia.

## GitHub e automação
- Branch de trabalho: docs/fase3-arquitetura-zero-trust-20261021; último script de validação versionado no commit 2cb98b2310f9bb79e22680fcbcea9bf8bd553617.
- PR #200: DRAFT, não realizar merge antes de autorização e validação de runtime.
- 8 GitHub Actions no commit 2cb98b2: **completed/success** — Gitleaks Secret Scanning, PA07 Cross PR Offline Integration, GA09 Synthetic Restore Integrity, GA08 ZT Static Contract, Repository Static Integrity, PHPUnit Security Tests, Supply Chain Build Gate e Semgrep SAST. CI não substitui testes operacionais.
- Issues abertas identificadas: #204 PA-02 bypass local, #201 PHP runtime P0, #196 Bacula Director/Catalog, #195 audit.log→Wazuh, #194 Ferret/Wazuh confidence. Nenhuma issue encerrada nesta atualização.
- Histórico da main inclui merge do PR #209 (contrato PA-05 BOLA horizontal), commit 115a3e6a de 27/10, e reconciliação Gitleaks posterior. Não inferir que branch GA08 foi mesclada.

## Limitações e próximos gates
1. Confirmar plano de implantação e rollback real (snapshot, arquivos, reversão de redes e volumes), autorização e janela; rollback ainda não testado.
2. Ensaio controlado em Compose isolado, garantindo WAF→Nginx→PHP funcional, PHP→EP126:3306 e ausência de PHP→Nginx TCP; verificar redes Docker efetivas e acesso do host.
3. Regressões HTTPS 80/443, TLS/certificados, healthchecks, autenticação, RBAC/MFA, rotas e logs Wazuh.
4. Teste negativo de acesso ao upstream a partir de origem não autorizada; evidências antes/depois, sem extrapolar alcance de pfSense/Twingate.
5. Só após gates e autorização: change control, cutover supervisionado, monitoramento e rollback testado. Manter PA-02.I e issue #204 abertos até evidência pós-implantação.

## Situação
COMPOSE_BASE=PASS
COMPOSE_CANDIDATO=PASS
SOCKET_EFEMERO=PASS
TCP_EP126=PASS
RUNTIME_ISOLAMENTO=NAO_TESTADO
ROLLBACK=NAO_TESTADO
DEPLOY=NAO_EXECUTADO
PR_200=DRAFT
PA_02_I=ABERTO
