# Wazuh — auditoria de serviço pré-freeze

## Escopo

Este documento registra a auditoria final da camada de serviço do Wazuh central na EP126. Ele complementa as provas já existentes de runtime, agentes, FIM, SCA, Syscollector, YARA, DLP, WAF e Suricata, sem repetir esses testes.

A auditoria read-only de 12/09/2026 terminou com `PASS=88`, `WARN=6`, `FAIL=0`, `GAP=1`. Manager, Indexer e Dashboard permaneceram `running` e `healthy`, sem restart/recreate ou mutação de runtime.

## Controles confirmados

### Manager

- `wazuh-authd` desabilitado após enrollment;
- TCP/1515 sem publicação e sem listener;
- canal de agentes em TCP/1514 com `connection=secure`;
- único Active Response efetivo restrito ao YARA do projeto e às rules `110200,110201`;
- configuração Git, mount declarativo e runtime ativo byte-a-byte equivalentes;
- API TCP/55000 sem publicação no host e acesso sem autenticação rejeitado com HTTP 401;
- API/RBAC `rbac_mode=white` e JWT de 900 s já haviam sido comprovados na auditoria operacional anterior.

### Indexer

- configuração Git e live byte-a-byte equivalentes;
- Security plugin com anonymous auth desabilitado;
- usuários internos armazenados por hashes bcrypt-like, sem campo `password`/`passwd` em claro;
- TCP/9200 sem publicação no host;
- TLS 1.2 validado com CA e hostname `wazuh.indexer`;
- TLS <= 1.1 não negociado.

### Dashboard

- configuração Git e live byte-a-byte equivalentes;
- HTTPS habilitado e exposição somente em loopback;
- cookie/sessão com TTL de 15 minutos;
- `HttpOnly` observado;
- HTTP plaintext não funcional.

## Hardening adicional versionado após a auditoria

Três gaps com baixo risco de regressão e recomendação explícita do OpenSearch foram corrigidos:

1. `plugins.security.allow_default_init_securityindex: false`
   - após o bootstrap, impede fallback automático para configuração de segurança default caso o security index deixe de existir;
   - comportamento desejado: falhar fechado em vez de reintroduzir defaults conhecidos.

2. `opensearch.ssl.verificationMode: full`
   - valida CA e hostname entre Dashboard e Indexer;
   - a auditoria já comprovou que o certificado atual valida `wazuh.indexer`.

3. `opensearch_security.cookie.secure: true`
   - o Dashboard opera exclusivamente em HTTPS;
   - o cookie de sessão passa a exigir transporte TLS.

A aplicação live dessas três mudanças ocorre em gate pós-merge separado, com health checks e promoção sequencial.

## Riscos residuais aceitos

### Chave de cluster com cluster desabilitado

O arquivo do Manager preserva o placeholder/default do upstream Wazuh 4.14.7, mas o cluster está `disabled=yes`. O valor não é tratado como credencial operacional do laboratório e não deve ser reutilizado se clustering vier a ser habilitado.

### Hostname verification no transport do Indexer

O upstream Wazuh 4.14.7 single-node mantém `plugins.security.ssl.transport.enforce_hostname_verification: false`. Como `discovery.type=single-node` e não existem peers de transporte, o projeto aceita esse estado como risco residual de topologia. Deve ser reavaliado antes de qualquer expansão para múltiplos nós.

### Session keepalive

`opensearch_security.session.keepalive: true` é mantido. Com `session.ttl=900000`, a sessão expira após 15 minutos de inatividade; atividade legítima renova o TTL. Para o laboratório administrativo em loopback, esse comportamento é aceito.

## Referências de upstream

A baseline local deriva do `wazuh/wazuh-docker` `v4.14.7`. Algumas opções acima são defaults do single-node oficial, mas o projeto adota hardening adicional quando a documentação do OpenSearch recomenda um estado mais restritivo e o ambiente já comprovou compatibilidade.
