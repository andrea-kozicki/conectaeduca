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


## pentest_sem_sudo_runtime_check.py

Gate de runtime para executar **depois** da retirada de sudo, logado como o próprio usuário `teste`.

O script não chama `sudo` nem `docker`. Ele verifica:

- EUID não-root e usuário `teste`;
- ausência de `sudo`, `wheel` e `docker` nos grupos efetivos;
- ausência de Linux effective capabilities no processo;
- falta de acesso de leitura/escrita ao Docker socket;
- disponibilidade dos clientes necessários;
- alcançabilidade dos endpoints loopback relevantes na EP126;
- geração de relatório e SHA-256.

Execução:

    python3 /opt/conectaeduca/scripts/evidencias/pentest_sem_sudo_runtime_check.py

O resultado `ZERO_SUDO_RUNTIME_BASELINE=PASS` valida apenas a base de execução. Os positivos/negativos de autorização de cada serviço continuam exigindo E2E manual.


## prefreeze_repo_gate.py

Gate estático de repositório para executar antes do FREEZE-01.

Valida, sem sudo e sem Docker:

- presença dos documentos e scripts canônicos do fechamento;
- working tree limpa;
- branch corrente;
- paths sensíveis rastreados por engano;
- marcadores de conflito;
- sintaxe dos scripts Python críticos;
- presença dos gates HOST-01, BAC-04, GUI-01C, PENTEST-00 e FREEZE-01;
- presença dos cenários S01-S13;
- possíveis contradições em itens marcados DONE no backlog.

Execução:

    python3 scripts/evidencias/prefreeze_repo_gate.py

O script grava relatório e SHA-256 no HOME e não altera runtime de VM.
