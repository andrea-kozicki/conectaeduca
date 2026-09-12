# Evidência sanitizada — usuário `teste` / EP126

Data: 11/09/2026  
Host: `ep126-pucpr`  
Zona: INTERNA

## Criação

```bash
sudo adduser --gecos "" teste
```

```text
[PASS] Conta criada pelo adduser autorizado.
[PASS] Conta resolvida pelo NSS/getent.
```

## Privilégio mínimo

```text
HOST=ep126-pucpr
USER=teste
UID=1001
GID=1001
GROUPS=teste users
HOME=/home/teste
SHELL=/bin/bash
PRIVILEGED_GROUPS=none
SUDO_ALLOWED=no
ETC_SHADOW_READABLE=no
ETC_WRITABLE=no
```

## Autenticação posterior

```text
WHOAMI=teste
UID=1001
GID=1001
GROUPS=teste users
HOME=/home/teste
PWD=/home/teste
AUTHENTICATION_TEST=PASS
```

## Resultado consolidado

```text
CREATED=1
PASS=13 WARN=0 FAIL=0 GAP=0
```

## SHA-256

```text
6d3fde53cda3af9928d62d34f27a0abc9fc6a25542b43bdca669bc5ed64f45e4  conectaeduca-evidencia-usuario-teste-ep126-20260911-220806.txt
fac32a5c4ff59e56347c78840165ae249ae38cbe3d8ecddefa416f1e2d680485  conectaeduca-criar-validar-usuario-teste-ep126-v1.sh
```

Nenhuma senha ou hash de autenticação está incluído neste arquivo.
