# Exceções e decisões de hardening relacionadas ao Semgrep

Este documento registra achados de análise estática que exigem contexto
arquitetural no laboratório ConectaEduca.

## Diretórios com modo 0700

Regras envolvidas:

`python.lang.security.audit.insecure-file-permissions.insecure-file-permissions`

Ocorrências:

- diretório de custódia das shares de unseal do OpenBao;
- diretório operacional contendo RoleID/SecretID de AppRole.

O modo `0700` é intencional.

Em diretórios sensíveis:

- proprietário: leitura, escrita e travessia;
- grupo: nenhum acesso;
- outros: nenhum acesso.

Trocar esses diretórios para `0644`, como sugere genericamente a regra,
reduziria a proteção e seria semanticamente incorreto para diretórios,
pois removeria permissões de travessia.

As ocorrências recebem exceção `nosemgrep` localizada e documentada.
A regra não é desabilitada globalmente.

## HTTP para OpenBao no laboratório local

Enquanto a implantação permanece na estação de laboratório, a API do
OpenBao é publicada exclusivamente em:

`http://127.0.0.1:18200`

O transporte HTTP é aceito apenas porque o tráfego permanece no
loopback local.

Os clientes Python foram alterados para usar `http.client.HTTPConnection`
com host e porta fixos, evitando:

- URL arbitrária controlada por entrada;
- esquemas como `file://`;
- redirecionamento de credenciais para host externo.

O materializador de SMTP rejeita qualquer valor de
`CONECTAEDUCA_OPENBAO_ADDR` diferente de:

`http://127.0.0.1:18200`

Na topologia final entre VMs, esse contrato deve ser substituído por TLS.

## Imagens Bacula e usuário não-root

As imagens:

- conectaeduca/bacula-director
- conectaeduca/bacula-storage
- conectaeduca/bacula-filedaemon

declaram `USER bacula:bacula`.

No Compose do laboratório, alguns serviços possuem bootstrap explícito
como `0:0` porque precisam:

- ler configuração runtime bind-mounted com modo 0600;
- preparar diretórios e volumes persistentes.

Os daemons permanentes abandonam privilégios explicitamente com:

- `-u bacula`
- `-g bacula`

O requisito funcional de segurança é validado verificando que o processo
PID 1 do daemon, após inicialização, opera como UID 100 e GID 101.

`bconsole` é um serviço efêmero do profile `tools`; usa root somente para
ler seu arquivo runtime 0600 e não mantém workload persistente nem
publica porta.
