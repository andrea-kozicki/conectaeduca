# Segurança — documentação e evolução

Esta área reúne documentação de segurança operacional e rastreabilidade do hardening do ConectaEduca.

## Evolução de hardening

➡️ [`hardening/README.md`](hardening/README.md) — painel vivo por container e serviço, com estado, controles comprovados, pendências, linha do tempo e vínculo com evidências.

O painel separa as camadas de:

- runtime/container;
- serviço;
- identidade e segredos;
- rede/exposição;
- validação funcional.

## Outros documentos

- [`custodia-shamir-openbao.md`](custodia-shamir-openbao.md) — custódia Shamir do OpenBao;
- [`semgrep-excecoes.md`](semgrep-excecoes.md) — exceções e decisões relacionadas ao Semgrep.

Evidências operacionais sanitizadas ficam em [`../evidencias/`](../evidencias/).

## Regra de rastreabilidade

Mudanças relevantes de hardening devem ser associadas a configuração versionada, evidência sanitizada, SHA-256 do relatório operacional quando aplicável e commit/PR correspondente. Segredos, tokens, chaves privadas e hashes de autenticação não devem ser incluídos no Git.