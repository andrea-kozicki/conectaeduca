# Hardening de runtime do OpenBao

Este documento registra o hardening de container validado em ambiente isolado
antes da promoção para o OpenBao operacional da EP126.

## Controles aplicados

O serviço OpenBao passa a declarar no Compose:

- root filesystem somente leitura (`read_only: true`);
- remoção de capabilities Linux (`cap_drop: ALL`);
- `no-new-privileges`;
- limite de 256 PIDs;
- `tmpfs` somente nos caminhos que precisam permanecer graváveis;
- `nosuid`, `nodev` e `noexec` nos `tmpfs`;
- healthcheck local por `bao status`;
- publicação da API/UI preservada somente em `127.0.0.1:18200`.

O `read_only: true` já existente no bind mount de `openbao.hcl` é um controle
diferente: ele protege apenas aquele arquivo montado. O novo `read_only: true`
no nível do serviço torna o root filesystem do container somente leitura.

O volume Raft em `/openbao/data` permanece gravável.

## Evidência de compatibilidade

Antes da autoria, um container candidato isolado foi executado na EP126 com
volume Raft efêmero próprio.

Foram comprovados:

```text
Config.User=openbao
read_only=true
pids_limit=256
cap_drop=ALL
no-new-privileges=true
sem porta publicada
/tmp gravável
/openbao/file gravável
/openbao/logs gravável
/openbao/data gravável
root filesystem não gravável
OpenBao inicia com storage raft
bao status responde pela API local
```

O OpenBao operacional permaneceu com o mesmo container, zero restarts e volume
Raft live intacto durante a prova.

## Healthcheck

O healthcheck usa:

```text
BAO_ADDR=http://127.0.0.1:8200 bao status -format=json
```

No estado operacional esperado, inicializado e unsealed, o comando retorna
sucesso.

Se o cofre estiver sealed ou indisponível, o container pode aparecer
`unhealthy`. Isso é intencional: processo em execução não significa cofre pronto
para consumo de secrets.

O healthcheck não contém token.

## Interface web e listener

A UI continua habilitada no `openbao.hcl`.

A publicação Docker permanece:

```text
127.0.0.1:18200 -> 8200/tcp
```

Logo, API e UI permanecem acessíveis apenas pelo loopback da EP126.

O listener HTTP local continua sendo uma exceção documentada enquanto estiver
restrito ao loopback. Qualquer futura exposição entre VMs deverá receber TLS
real antes da abertura de rede.

## Autenticação

Este hardening não modifica AppRole, policies, tokens, secrets ou métodos de
autenticação.

Workloads continuam sendo tratados separadamente com AppRole e privilégio
mínimo quando aplicável.
