# Evidência — Wazuh Dashboard com ACL reprodutível para `wazuh.yml` (07/09/2026)

## Objetivo
Registrar a correção definitiva do problema de leitura do arquivo bind-mounted `wazuh.yml` pelo Wazuh Dashboard na EP126, tornando a ACL mínima de leitura para o UID 1000 automaticamente reaplicável após mudanças/recriação do arquivo runtime.

## Contexto
O Dashboard executa com UID/GID `1000/1000` e utiliza o arquivo runtime:

`/opt/conectaeduca/deploy/interna/wazuh/.runtime/wazuh.yml`

A ACL funcional observada antes do hardening era:

```text
user::rw-
user:1000:r--
group::---
mask::r--
other::---
```

O conteúdo do `wazuh.yml` não foi exibido nem copiado para a evidência.

## Solução implantada
Foi instalada uma automação mínima baseada em `systemd.path` + serviço `oneshot`:

```text
/opt/conectaeduca/deploy/interna/wazuh/.runtime
    ↓ mudança detectada
conectaeduca-wazuh-yml-acl.path
    ↓
conectaeduca-wazuh-yml-acl.service
    ↓
/usr/local/libexec/conectaeduca-wazuh-yml-acl
    ↓
setfacl u:1000:r-- wazuh.yml
```

Artefatos instalados:

- `/usr/local/libexec/conectaeduca-wazuh-yml-acl`
- `/etc/systemd/system/conectaeduca-wazuh-yml-acl.service`
- `/etc/systemd/system/conectaeduca-wazuh-yml-acl.path`

## Validação
- EP126 confirmada em `192.168.6.50/28`.
- Container `conectaeduca-wazuh-wazuh.dashboard-1` localizado.
- UID/GID efetivos do Dashboard: `1000/1000`.
- ACL baseline confirmada antes da mudança.
- Leitura do arquivo pelo UID 1000 do container aprovada sem exibir conteúdo.
- Dashboard respondeu `HTTP 302` em `https://127.0.0.1` antes e depois do hardening.
- `systemd.path` ficou `active` e `enabled`.
- Helper reaplicado duas vezes sem erro, demonstrando idempotência operacional.
- ACL final efetiva para UID 1000.
- Nenhum `EACCES: permission denied` recente apareceu no log do Dashboard.
- `wazuh.manager` continuou resolvendo no container.
- API do Manager em `https://wazuh.manager:55000/` respondeu `HTTP 401` sem autenticação, resultado esperado para validar disponibilidade sem uso de credenciais.
- Nenhuma restauração manual foi necessária.

## Teste controlado do watcher
A entrada ACL `user:1000:r--` foi removida temporariamente para testar o autorreparo. O relatório registrou um `WARN` porque, no instante da checagem seguinte, a ACL já aparecia novamente efetiva. Isso é compatível com uma corrida favorável do watcher, que pode ter reagido antes da verificação intermediária.

Depois de um evento inofensivo no diretório runtime, a ACL foi confirmada novamente e o gate final aprovou a automação. Portanto, o aviso não representa falha funcional; ele registra apenas que a janela entre remoção e autorreparo foi curta demais para provar de forma determinística a ausência intermediária.

## Resultado final

```text
PASS=40 WARN=1 FAIL=0
Automação instalada: 1
Watch testado: 1
Restauração manual necessária: 0
```

Gate final:

```text
Watcher final: active
ACL efetiva UID 1000: 1
Leitura pelo container UID 1000: 1
```

## Integridade
SHA-256 do relatório operacional enviado:

`2a59fb3973c231a1863886e50bf0020219b99d3589148c78b779c4ef25725cbb`

SHA-256 dos artefatos instalados:

- helper: `afaf9f30c37259f5280e488e79b6cff5822cb5622a656fb4d78fd4992272d266`
- service: `32ce99aa84d3e0027ffae9e260bf66994df8a323e5481cf5d7a214feffaa30d6`
- path: `c4e55ca8b0bd8f53759f2e4ee0e6f40e0824318af4bfa6b5a20a1d1f97764e49`

## Segurança operacional
- execução como usuário comum;
- elevação administrativa apenas em comandos específicos;
- nenhum shell root persistente;
- nenhuma senha, token, chave privada ou conteúdo do `wazuh.yml` registrado nesta evidência;
- arquivo permaneceu sem permissão `other` e sem exposição pública.

## Conclusão
A correção deixa de depender de uma ACL aplicada manualmente uma única vez. A EP126 agora possui um mecanismo local, mínimo e auditável para reaplicar a leitura do `wazuh.yml` ao UID 1000 do Dashboard quando o runtime muda, preservando simultaneamente a restrição do arquivo e a operação Dashboard → Wazuh Manager.
