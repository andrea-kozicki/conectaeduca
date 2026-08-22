# Consistência dos dados antes do Bacula

O Bacula protege artefatos consistentes. Serviços transacionais não devem ser
copiados por leitura direta de seus diretórios internos enquanto escrevem.

## MariaDB

Fluxo obrigatório:

```text
MariaDB ativo
  -> dump consistente com identidade de backup dedicada
  -> staging 0700 / arquivo 0600
  -> Bacula File Daemon
  -> Storage Daemon
  -> validação do job
  -> limpeza controlada do staging
```

Regras:

- não copiar diretamente o volume `/var/lib/mysql`;
- não usar senha root na linha de comando;
- criar usuário de backup de privilégio mínimo na etapa de implementação;
- o dump deve ser restaurado em banco sintético durante o checkpoint;
- staging não pode ser servido pelo Nginx nem incluído em handoff.

## OpenBao Raft

O backend atual é Raft. A fonte de backup será um **snapshot Raft consistente**,
não uma cópia do diretório de dados em execução.

Fluxo:

```text
OpenBao unsealed
  -> identidade específica de snapshot
  -> snapshot Raft
  -> staging protegido
  -> Bacula
  -> confirmação
  -> limpeza do staging
```

A identidade usada para gerar snapshot não será o root token. A política deverá
conceder somente a capacidade necessária ao snapshot.

Nunca incluir no job:
- root token;
- unseal shares;
- diretório de custódia offline.

## Wazuh

Baseline:
- proteger configurações customizadas, regras e contratos;
- não copiar os volumes crus do Indexer;
- não duplicar `archives` completos;
- a retenção de eventos continua sendo responsabilidade do Wazuh.

## Ferret

Proteger somente configuração/políticas necessárias à reconstrução.
`inbox/` e `reports/raw/` ficam fora do Bacula.

## Catálogo do próprio Bacula

O Catalog deve possuir job próprio de dump após os jobs principais. A cópia do
catálogo deve permitir reconstruir metadados de volumes e jobs após falha
lógica.

O backup do catálogo no mesmo Storage continua sujeito à limitação física
documentada para o laboratório.
