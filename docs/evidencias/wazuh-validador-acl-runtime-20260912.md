# Wazuh — validador operacional compatível com ACL do `wazuh.yml`

## Contexto

O Dashboard executa como UID/GID `1000/1000` e precisa ler o arquivo runtime
`.runtime/wazuh.yml`, que contém configuração sensível e permanece fora do Git.

A política validada na EP126 concede somente leitura ao UID `1000` por POSIX ACL:

```text
user::rw-
user:1000:r--
group::---
mask::r--
other::---
```

Com essa ACL, `stat` apresenta modo efetivo `0640` por causa do `mask::r--`.
Isso não significa que o grupo possua leitura: `group::---` continua sem acesso.

## Falha identificada no validador

O validador operacional aceitava apenas modos `0600` ou `0400` para todos os
artefatos de `.runtime/`. Assim, reprovava o `wazuh.yml` funcional e endurecido
em `0640`, apesar de a ACL mínima ser necessária ao Dashboard.

## Evidência operacional de 12/09/2026

Diagnóstico somente leitura na EP126:

- `wazuh.yml`: modo `0640`;
- ACL exata: somente UID `1000` com `r--`, grupo e `other` sem acesso;
- automação `systemd.path` de reaplicação da ACL: `active` e `enabled`;
- helper/service/path-unit com os mesmos SHA-256 validados em 07/09;
- Dashboard efetivamente em UID/GID `1000/1000`;
- UID `1000` lê o arquivo; UID arbitrário `1001` não lê;
- self-test local comprovou `0600 -> 0640` após `setfacl u:1000:r--`;
- cópia temporária ACL-aware do validador: `WAZUH_OPERACIONAL=APROVADO`;
- diagnóstico: `PASS=33`, `WARN=0`, `FAIL=0`;
- nenhum Git/runtime/container foi alterado pelo diagnóstico.

## Correção

O validador continua aceitando `0600`/`0400` para os artefatos de runtime.
A exceção é somente `wazuh.yml`: `0640`/`0440` são aceitos apenas quando
`getfacl` comprova exatamente a ACL mínima esperada para UID `1000`, sem named
groups, sem acesso de `group`/`other` e sem ACL default.

A validação passa a verificar a semântica real da política de acesso em vez de
confundir o `mask` POSIX ACL com permissão de grupo.
