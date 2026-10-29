# GA08 — Parecer de overlays e rollback (29/10/2026)

Revisão de código, sem VM e sem implantação.

## Compose: riscos e aceites
- Base: PHP e Nginx compartilham frontend; nginx publica 127.0.0.1:8088 em laboratório.
- WAF: nginx `ports: !reset []`; WAF aponta `http://nginx:8080`, e rede frontend.
- Host: WAF publica bind/80/443 parametrizados com `!override`; DB_HOST/DB_PORT na EP126.
- Candidato: WAF e Nginx `waf_backend`; PHP `php_egress`; FastCGI migra para socket Unix; diretório compartilhado RO no Nginx, RW no PHP; grupo suplementar 82.
- **Atenção:** o overlay candidato não altera explicitamente `php.expose: ["9000"]` herdado. A declaração `expose` não publica porta no host, mas fica desatualizada com FPM no socket; verificar Compose final e avaliar sua remoção na janela de mudança.
- **Atenção:** `networks: !override` substitui redes por serviço; outras sobreposições posteriores podem reintroduzir rede ou porta. Conferir ordem completa e config final com variáveis sintéticas e reais sanitizadas.
- Healthcheck PHP `php-fpm -t` e nginx `/_container_health` não substituem teste de FastCGI `/_fpm_ping` via WAF.
- Certificado/TLS, DNS/CA, Wazuh e SQL autenticado exigem evidência runtime.

## Critérios de aborto e rollback
- Abortar se HTTPS público falhar, WAF for contornado, FastCGI não responder, SQL autenticado falhar, negação lateral não for demonstrada, ou telemetria crítica desaparecer.
- Pré-mudança: autorização e operador, snapshot IDs, hash da configuração final, lista de imagens/digests, backup de arquivos sem segredos e caminho de retorno validado.
- Retorno: restaurar configurações e imagens baseline segundo procedimento aprovado, validar WAF/TLS/FPM/SQL/logs, registrar timestamps e SHA256.
- O script `ga08-rollback-controlado-ep125.sh` ainda é SOMENTE LEITURA e não executa rollback. Não promover candidato até ensaio operacional autorizado.

## Testes offline
- Teste Python atualizado no commit `65d7a898998aa99dca59d82a6d961df658757b67`: redes exatas por serviço, permissões/mount RO-RW, seis destinos FastCGI, gate fechado e mutações negativas.
- Workflow GA08 ZT Static Contract run #95 foi encontrado em fila; não declarar PASS até conclusão.
- PR #200 e issue #204 continuam dependentes de aceite e evidência de runtime; nenhum merge feito.

## PAs
- PA-02: risco de bypass local do WAF, issue #204; mitigação parcial e teste runtime pendente.
- PA-06: auditoria PHP em tmpfs não centralizada, issue #195; política de retenção/Wazuh e ensaio pendentes.
- PA-07: Bacula Director/Catalog, issue #196; confirmar causa raiz e recuperação.
- PA-01,03,04,05: rastreabilidade detalhada depende do relatório original; não inventar achados.
- Issue #201 (PHP2Shell): prioridade P0, validação de versão ativa e patch dependem de VM; revisão de Dockerfile pode ser feita offline.

**Status:** documentação e teste offline avançaram; nenhuma VM modificada; gate fechado.
