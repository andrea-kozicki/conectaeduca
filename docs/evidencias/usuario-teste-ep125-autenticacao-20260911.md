# Evidência sanitizada — autenticação posterior do usuário `teste` / EP125

Data: 11/09/2026  
Host: `ep125-pucpr`  
Objetivo: comprovar autenticação posterior via PAM sem registrar a senha.

## Comando de prova

```bash
su - teste -c 'whoami; id; pwd'
```

O script executado produziu os mesmos dados com rótulos para facilitar auditoria.

## Resultado

```text
WHOAMI=teste
UID=1001
GID=1001
GROUPS=teste users
HOME=/home/teste
PWD=/home/teste

[PASS] Autenticação posterior do usuário teste concluída com sucesso.
AUTHENTICATION_TEST=PASS

PASS=3 WARN=0 FAIL=0 GAP=0
```

## Integridade

```text
0eac4ac894ec48145d5996df3b2203a1fa44d47e8f53a09d5ab375311903849e  conectaeduca-evidencia-autenticacao-teste-ep125-20260911-214416.txt
2b826d3d09440840299a216673c2d53f4f6e940c0e3d9d2b4bbece2a030ed16e  conectaeduca-validar-autenticacao-teste-ep125-v1.sh
```

## Sanitização

A senha não aparece nesta evidência, no script, no Git ou no relatório. Ela foi informada somente no prompt interativo do `su`.
