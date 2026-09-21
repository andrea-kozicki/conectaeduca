# GUI-01B — Bacularis: contrato de integração read-only

Este documento define o contrato de segurança. Esta mudança **não instala nem
inicia o Bacularis**; o APPLY permanece bloqueado até a conclusão do HOST-01.

## Não usar diretamente

- `bacularis-standalone`: duplicaria Director/Storage/PostgreSQL.
- `bacularis-api-dir` sem revisão: traz stack Bacula próprio.
- Docker socket.
- `privileged: true`.
- `network_mode: host`.
- sudo genérico para o usuário Web.
- write access às configurações Bacula na primeira versão.
- run/cancel/delete/restore na conta de demonstração.

## Contrato desejado

A futura instância deve:
- publicar somente `127.0.0.1:9097`;
- usar rede UI própria;
- alcançar Director e Catalog apenas pela rede Docker necessária;
- usar Console ACL dedicada de observação;
- usar role PostgreSQL dedicada somente leitura;
- não gravar configs Bacula;
- manter credenciais fora do Git;
- trocar credencial default imediatamente;
- preservar rollback simples sem recriar Director/Storage/Catalog.

## Gate atual

Rodar `gui01_bacularis_preflight.py` na EP126.
O relatório identifica:
- estado/restart dos containers;
- rede comum Director/Catalog;
- compose workdir/configs live;
- disponibilidade de bconsole;
- portas candidatas;
- topologia segura preferida.

O precheck final da EP126 em 21/09/2026 resultou em `PASS=14`, `WARN=0`,
`FAIL=0` e confirmou Director/Catalog saudáveis, `127.0.0.1:9101` aberto e as
portas `9097` e `15432` livres.

Somente depois do HOST-01 será escrito e revisado o APPLY final. O gate deverá
recusar instalação se o desenho exigir Docker socket, modo privilegiado, rede
do host, reutilização de console administrativo ou escrita nas configurações
do Bacula.
