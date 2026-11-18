# Login/WAF — contrato de origem offline antes da PR #205

**Escopo (18/11/2026):** testes estáticos de duas configurações já existentes na `main`: `compose.waf.yml` e `compose.waf-tls.yml`. Não carrega WAF, PHP, aplicação, nginx, certificados ou VMs.

A [PR #205](https://github.com/andrea-kozicki/conectaeduca/pull/205) propõe `TrustedClientIp::current()` para o login híbrido v2: a função só confia em `X-ConectaEduca-Client-IP` quando o peer aparente pertence ao serviço WAF. Essa confiança exige um contrato específico entre WAF, nginx e PHP. Os testes da fonte verificam que o Compose **declara** o header interno certo, que o upstream header usado no `real_ip` é diferente e que `SET_REAL_IP_FROM` não foi aberto a clientes arbitrários.

**Gates estáticos cobertos:** upstream confinado a `127.0.0.1`, `REAL_IP_RECURSIVE=off`, header encaminhado `X-ConectaEduca-Client-IP`, servidor de aplicação sem publicação direta de porta no overlay, publicação TLS do WAF em loopback, backend `nginx:8080`, ModSecurity ligado. Oito testes incluem mutações propositalmente perigosas que devem ser rejeitadas.

**Limite essencial:** conferir variáveis de Compose não confirma que a imagem upstream **aplique** esses valores, nem que `REMOTE_ADDR` observado no PHP seja o IP confiável do WAF. A PR #205 **permanece DRAFT** até validação real com navegador, MFA, CSRF, rate limit, identidade e fluxo TLS sob autorização institucional. A CI não pode confirmar mitigação de spoofing de IP em runtime.

Não interpretar este arquivo como ordem de implantação nem como aprovação de rollback. Os testes não utilizam segredos ou logs de sessões reais.
