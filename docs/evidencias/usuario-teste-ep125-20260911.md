# Evidência sanitizada — usuário `teste` / EP125

Data: 11/09/2026  
Host: `ep125-pucpr`  
Zona: DMZ

## Resultado estrutural final

```text
HOST=ep125-pucpr
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

PASS=9
WARN=0
FAIL=0
GAP=0
```

Esses contadores pertencem ao validador estrutural v3.

## Critério de autenticação

A autenticação posterior foi executada com sucesso por meio de `su`, usando a senha padrão apenas no prompt interativo.

```text
WHOAMI=teste
UID=1001
GID=1001
GROUPS=teste users
HOME=/home/teste
PWD=/home/teste

AUTHENTICATION_TEST=PASS
PASS=3 WARN=0 FAIL=0 GAP=0
```

Comando utilizado:

```bash
su - teste -c 'whoami; id; pwd'
```

A implementação real do script coletou os mesmos dados em linhas nomeadas, sem registrar a senha.

## Comando exato de criação final

```bash
sudo adduser --gecos "" teste
```

O parâmetro `--gecos ""` apenas deixa vazios os metadados descritivos da conta; não altera privilégios.

## SHA-256 dos relatórios locais

```text
9155db17a442bbe86fcb027aca32a558ea8556a20fbb339d00e89ca27f98f839  conectaeduca-evidencia-usuario-teste-ep125-20260911-200504.txt
d1a09def1b4e740535bcbd215e1416d9e31b22c0b056e4d526e39556a98f15cb  conectaeduca-diagnostico-sudo-usuario-teste-ep125-20260911-201335.txt
2ca91502de4b77e7084b8f12cb447837789e431888cbc57cbecc5c704f6d7e32  conectaeduca-evidencia-usuario-teste-ep125-v2-20260911-201910.txt
85b83f2d9d4f3d6239aaea2e1c8210ef9a6a4ca5a2feec033a206206318a32df  conectaeduca-evidencia-usuario-teste-ep125-v3-20260911-203147.txt
0eac4ac894ec48145d5996df3b2203a1fa44d47e8f53a09d5ab375311903849e  conectaeduca-evidencia-autenticacao-teste-ep125-20260911-214416.txt
```

## SHA-256 dos scripts utilizados

```text
1fc90968d462389b5b26d324cd3cee1766c8dd3791495def8d45319d0528c058  conectaeduca-criar-validar-usuario-teste-ep125-v1.sh
ea27aeaed5bc210a9d1d82de6052f66a17fb0a2efc3d660135947dedb2a569b8  conectaeduca-diagnostico-sudo-usuario-teste-ep125-v1.sh
6f86da615079da14efdf8c0429263e221ee82e83c60fa7bd471e3d9604cd1000  conectaeduca-recriar-validar-usuario-teste-ep125-v2.sh
0decddbe3132d9d2a84e93cb1e783b5193b0562340d06ea227ef2039e86e5acd  conectaeduca-validar-usuario-teste-ep125-v3.sh
2b826d3d09440840299a216673c2d53f4f6e940c0e3d9d2b4bbece2a030ed16e  conectaeduca-validar-autenticacao-teste-ep125-v1.sh
```

## Sanitização

Nenhuma senha, hash de senha, token, secret ou conteúdo de `/etc/shadow` é registrado nesta evidência.
