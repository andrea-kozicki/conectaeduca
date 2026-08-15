# Evidências de segurança do ConectaEduca

Esta pasta contém scripts reproduzíveis utilizados para validar os
controles de segurança da aplicação.

## gerar_seguranca.sh

Executa a validação geral do projeto, incluindo:

- lint dos arquivos PHP;
- PHPUnit;
- Composer Audit;
- busca por referências legadas ao Cognito/AWS;
- verificação de pinning das GitHub Actions;
- testes da autenticação local;
- Semgrep;
- Snyk Open Source;
- Snyk Code.

Os resultados são armazenados localmente em:

docs/evidencias/seguranca/<timestamp>/

O diretório de evidências é ignorado pelo Git por poder conter
informações específicas do ambiente de teste.

## testar_auth_local.sh

Valida o fluxo HTTP da autenticação local:

- acesso público ao login;
- bloqueio de recursos sem autenticação;
- proteção CSRF;
- rejeição de senha incorreta;
- autenticação de usuário;
- autenticação de empresa;
- autenticação de administrador;
- RBAC;
- logout;
- regeneração do identificador de sessão.

As credenciais não são armazenadas no script.

Elas devem ser configuradas localmente em:

.env.test.local

Use `.env.test.example` como modelo.

O arquivo `.env.test.local` deve permanecer ignorado pelo Git.

## Execução

Teste somente a autenticação:

    ./scripts/evidencias/testar_auth_local.sh

Validação completa:

    ./scripts/evidencias/gerar_seguranca.sh
