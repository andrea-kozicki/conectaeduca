# GA-08 / PA-02.I — checkpoint técnico 28/10/2026 (22h16 BRT)

## Evidências verificadas na EP125
- Ensaio efêmero integrado Nginx→PHP-FPM por socket Unix: **PASS** (resposta `pong`, contêineres sem rede, nenhuma porta publicada, produção não alterada). Evidência: `GA08_NGINX_FPM_INTEGRADO_V4_20261028T215119.txt`.
- Contêiner PHP em produção: `running/healthy`; conexão **TCP** EP125 PHP→EP126 `192.168.6.50:3306`: **OK**. Autenticação SQL não testada; nenhuma credencial lida. Evidência: `GA08_EP126_CONECTIVIDADE_20261028T221525.txt`.
- `docker compose config --quiet` com overlay GA-08: **BLOQUEADO**. Diagnóstico inicial identificou variáveis obrigatórias `CONECTAEDUCA_DB_HOST` e `CONECTAEDUCA_DB_PASSWORD_FILE`; ensaio com 17 variáveis fictícias ainda retorna exit 1, erro `OUTRO` com 37 bytes, sem exposição do stderr. Evidências: `GA08_COMPOSE_VARIAVEIS_20261028T220759.txt`, `GA08_COMPOSE_DIAGNOSTICO_V2_20261028T221525.txt`.
- Teste mínimo da CLI Docker Compose: **3/3 PASS** (`config --quiet`, `--project-directory` antes e depois de `-f`); incompatibilidade básica da CLI descartada. Evidência: `GA08_COMPOSE_CLI_20261028T221647.txt`.

## Estado e próximos gates
**GA-08 aberta; PR #200 DRAFT.** Não houve `compose up`, migração de redes, alteração de segredos, rollback real ou merge. O teste TCP não prova autenticação SQL nem funcionamento da futura segmentação. Investigar a mensagem exata do erro Compose com sanitização adequada; validar configuração efetiva e conectividade WAF→Nginx, PHP→EP126 após segmentação, isolamento PHP→Nginx, regressão da aplicação e rollback em janela aprovada. Evitar novos inventários repetitivos.

## GitHub Actions
No commit `3f0d0ae1de7e07be536f03e1c5019475ec002a00`, oito workflows de PR consultados constavam como `completed/success`: GA08 ZT Static Contract, PHPUnit Security Tests, Repository Static Integrity, Gitleaks, GA09 Synthetic Restore Integrity, PA07 Cross PR Offline Integration, Semgrep SAST e Supply Chain Build Gate. **CI verde não valida runtime Docker Compose.**

Registro versionado no PR #200; diário local EP125 recebeu entradas dos scripts executados.