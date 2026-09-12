# Privilégio mínimo — usuário de sistema `teste` na EP126

## Objetivo

Registrar a criação e a validação do usuário de sistema `teste` na VM **EP126 / INTERNA**, conforme requisito da atividade de Experiência Criativa 8.

A execução reutiliza o procedimento corrigido e validado na EP125: criação pelo `adduser` interativo, validação estrutural de menor privilégio e prova posterior de autenticação via PAM.

Nenhuma senha ou hash de senha é registrada.

## Ambiente

```text
VM: EP126
Hostname: ep126-pucpr
Zona: INTERNA
Usuário criado: teste
```

## Comando exato de criação

```bash
sudo adduser --gecos "" teste
```

O parâmetro `--gecos ""` deixa vazios os metadados descritivos da conta e não altera privilégios.

## Política administrativa observada

Antes da criação, o procedimento registrou a política `sudo` da conta administrativa.

Entre os comandos explicitamente bloqueados estavam:

```text
/bin/su
/usr/sbin/visudo
/usr/bin/passwd
/usr/sbin/useradd
shells privilegiados e edição direta de arquivos sensíveis
```

O utilitário `adduser` permaneceu utilizável no fluxo autorizado.

## Criação

A criação foi concluída pelo próprio `adduser`, que também conduziu a definição interativa da senha padrão exigida pela atividade.

Resultado:

```text
[PASS] Conta criada pelo adduser autorizado.
[PASS] Conta resolvida pelo NSS/getent.
```

## Validação estrutural

Foram validados:

```bash
getent passwd teste
id -u teste
id -g teste
id -nG teste
stat -c '%U' /home/teste
sudo -l -U teste
sudo -u teste test -r /etc/shadow
sudo -u teste test -w /etc
```

Resultado:

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

## Validação posterior de autenticação

Após a criação, a conta foi autenticada novamente via PAM por meio de `su`.

A senha foi digitada somente no prompt interativo e não foi registrada.

Resultado:

```text
WHOAMI=teste
UID=1001
GID=1001
GROUPS=teste users
HOME=/home/teste
PWD=/home/teste

[PASS] Autenticação posterior do usuário teste concluída com sucesso.
AUTHENTICATION_TEST=PASS
```

## Resultado consolidado

```text
CREATED=1
PASS=13
WARN=0
FAIL=0
GAP=0
```

Conclusão:

```text
[PASS] Critério de privilégio mínimo e autenticação atendido na EP126.
```

## Correlação comando → efeito → evidência

| Ação | Comando | Efeito comprovado |
|---|---|---|
| Criar a conta | `sudo adduser --gecos "" teste` | conta final criada pelo fluxo autorizado |
| Verificar UID | `id -u teste` | UID 1001, não root |
| Verificar grupos | `id -nG teste` | apenas `teste users` |
| Verificar sudo | `sudo -l -U teste` | nenhum comando sudo autorizado |
| Testar shadow | `sudo -u teste test -r /etc/shadow` | leitura negada |
| Testar `/etc` | `sudo -u teste test -w /etc` | escrita negada |
| Testar autenticação | `su - teste ...` | autenticação posterior concluída |

## Integridade

Relatório operacional:

```text
6d3fde53cda3af9928d62d34f27a0abc9fc6a25542b43bdca669bc5ed64f45e4  conectaeduca-evidencia-usuario-teste-ep126-20260911-220806.txt
```

Script utilizado:

```text
fac32a5c4ff59e56347c78840165ae249ae38cbe3d8ecddefa416f1e2d680485  conectaeduca-criar-validar-usuario-teste-ep126-v1.sh
```

## Estado

**EP126 / usuário de sistema `teste`: concluído e validado sem FAIL, WARN ou GAP.**

A conta de aplicação `teste@pucparana.com` é uma identidade distinta e será documentada separadamente no mesmo fluxo acadêmico.
