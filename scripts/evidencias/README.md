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


## pentest_no_sudo_readiness.py

Auditoria somente leitura para executar **antes** de o suporte retirar sudo.

Valida:

- existência do usuário host `teste`;
- ausência de `teste` em `sudo`, `wheel` e `docker`;
- inventário de clientes necessários;
- presença/ausência de `teste` no SO dos containers apenas como evidência;
- identidades nativas de MariaDB, Catalog e Bacula quando executado na EP126;
- endpoints loopback relevantes.

A ausência de um usuário Linux `teste` em containers de daemon não é, por si só, falha. O objetivo é garantir que o pentest use o mecanismo nativo de autorização de cada serviço.

Execução:

    python3 scripts/evidencias/pentest_no_sudo_readiness.py

O script não usa sudo, não altera grants, não cria contas e não imprime valores de secrets.

## gui01c_phpmyadmin_precheck.py

Precheck somente leitura da futura GUI phpMyAdmin read-only.

Execução na EP126:

    python3 scripts/evidencias/gui01c_phpmyadmin_precheck.py

O precheck descobre o MariaDB/rede real, verifica a identidade `teste` e uma porta loopback candidata, mas deliberadamente mantém `APPLY_AUTHORIZED=NO` até análise da evidência.
