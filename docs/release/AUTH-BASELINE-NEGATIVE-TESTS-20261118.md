# Auth — contrato do login existente na main (pré-PR #205)

**Corte:** 18/11/2026. Este documento acompanha `tests/Unit/Security/LoginBaselineBoundaryTest.php`, **somente testes sem alteração em src/public**. A [PR #205](https://github.com/andrea-kozicki/conectaeduca/pull/205) de login híbrido v2 continua **DRAFT**; seus arquivos executáveis e dependências não foram mesclados.

## O que a CI realmente testa

- Precedência do token CSRF do cabeçalho, fallback para corpo e rejeição de tipos inesperados.
- Presença dos quatro campos de envelope, ausência/null e distinção entre *shape check* e validação/descriptografia por `CryptoHybrid`; o `isEncryptedEnvelope` da main **não certifica algoritmo nem versão v2**.
- Chave de rate limit por conta: e-mail trim/lowercase/SHA-256, separação por peer e ausência de e-mail bruto no identificador.
- **Comportamento atual**: o IP vem de `REMOTE_ADDR` e não de `X-Forwarded-For` ou header customizado. Em caminho WAF, dois clientes podem compartilhar bucket; a PR #205 propõe a lógica `TrustedClientIp` que precisará validação em contexto de runtime.
- Não iniciamos sessão real, não tocamos no MariaDB, não fazemos POST, RSA, WAF ou MFA autenticado. Os testes de `PendingAuthentication`, `Csrf` e `RateLimiter` já existentes continuam na suite e **não são substituídos**.

## Gates separados para eventual #205

1. Revisão de `TrustedClientIp`: origem de confiança estrita, WAF que sobrescreve header, peer real e DNS/segmentação, com testes de header forjado.
2. HTTP negativo e body size/JSON/CSRF 419, 415, 413, 429 antes de RSA; confirmar status e não vazamento. Não recuperar testes de servidor loopback da branch antiga sem revisar lifecycle e dependências.
3. Falha fechada do JS: sem WebCrypto, sem contexto TLS seguro e sem CSRF, não transmitir credenciais em POST comum.
4. Rotas de resposta restritas a MFA e configuração; nenhuma rota direta ao dashboard antes de MFA.
5. Homologação positiva/negativa **em VM e identidade autorizada** após snapshot, CI, controle de mudança e rollback. Não presumir proteção real só por testes de unidade.

**Decisão:** testes aditivos para baseline sem promover login v2; #205 permanece DRAFT até decisão operacional. Não há alteração de login, sessão, WAF, rate limiter ou MFA em execução.
