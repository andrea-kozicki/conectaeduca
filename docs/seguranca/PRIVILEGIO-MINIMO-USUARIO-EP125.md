# Privilégio mínimo — criação e validação do usuário de sistema `teste` na EP125

## 1. Objetivo

Registrar de forma rastreável a criação do usuário de sistema `teste` na VM **EP125 / DMZ**, conforme requisito da atividade acadêmica de Experiência Criativa 8, aplicando o princípio de menor privilégio e preservando a política administrativa da VM.

A senha padrão definida para a atividade foi utilizada, mas seu valor **não é registrado neste documento, no Git, no Trello, nos relatórios ou nas evidências**.

## 2. Critérios de aceite e estado

| Critério | Estado | Evidência |
|---|---|---|
| Conta local existente | PASS | `getent passwd teste` |
| UID diferente de 0 | PASS | UID 1001 |
| Home próprio | PASS | `/home/teste`, owner `teste` |
| Sem grupos administrativos/sensíveis | PASS | `PRIVILEGED_GROUPS=none` |
| Sem autorização sudo | PASS | `SUDO_ALLOWED=no` |
| Sem leitura de `/etc/shadow` | PASS | `ETC_SHADOW_READABLE=no` |
| Sem escrita direta em `/etc` | PASS | `ETC_WRITABLE=no` |
| Senha padrão definida durante a criação | PASS | `adduser` concluiu criação interativa |
| Autenticação posterior com a senha padrão | **PASS** | `su - teste -c 'whoami; id; pwd'` + relatório sanitizado |

> Observação: o Codex Review apontou corretamente que definir a senha durante `adduser` não prova, por si só, que uma autenticação posterior via PAM terá sucesso. O teste posterior foi então executado de forma sanitizada e comprovou a autenticação com sucesso.

## 3. Fundamentos de uma conta Linux

Uma conta local é representada em `/etc/passwd` por uma linha conceitualmente semelhante a:

```text
teste:x:1001:1001:<GECOS>:/home/teste:/bin/bash
```

Os campos representam:

| Campo | Significado |
|---|---|
| `teste` | nome de login |
| `x` | indica que o hash da senha fica em `/etc/shadow`, não em `/etc/passwd` |
| `1001` | UID — identificador numérico do usuário |
| `1001` | GID — grupo primário |
| `<GECOS>` | metadados descritivos da conta |
| `/home/teste` | diretório pessoal |
| `/bin/bash` | shell de login |

### 3.1 O que é GECOS

O campo GECOS é histórico e pode armazenar dados como nome completo, sala, telefone e outros comentários descritivos.

O comando usado na criação final foi:

```bash
sudo adduser --gecos "" teste
```

O parâmetro:

```text
--gecos ""
```

instrui o `adduser` a deixar esses campos descritivos vazios e evita perguntas interativas como nome completo, sala e telefones.

**Isso não concede privilégios, não altera autenticação e não muda permissões.** Apenas evita armazenar metadados desnecessários para uma conta acadêmica de teste.

### 3.2 `adduser` x `useradd`

No ambiente da EP125, a política `sudo` bloqueava explicitamente `/usr/sbin/useradd`, mas não bloqueava `adduser`.

Para esta atividade, `adduser` foi útil porque:

- cria a entrada de usuário;
- cria o grupo primário;
- cria o home;
- copia arquivos de `/etc/skel`;
- pode solicitar a senha durante o próprio fluxo de criação.

Essa diferença foi essencial para respeitar a política administrativa da VM sem qualquer bypass.

### 3.3 O efeito de `--disabled-password`

Na primeira tentativa foi usado:

```bash
sudo adduser --disabled-password --gecos "" teste
```

Esse comando cria a identidade da conta, mas deixa a autenticação por senha desabilitada naquele momento.

Por isso a primeira estratégia dependia de uma segunda etapa:

```bash
sudo passwd teste
```

que foi justamente bloqueada pela política institucional.

## 4. Ambiente

```text
VM: EP125
Hostname: ep125-pucpr
Zona: DMZ
Sistema: Ubuntu
Usuário administrativo do laboratório: andrea.kiew
Usuário criado: teste
```

## 5. Linha do tempo e correlação comando → efeito → evidência

### 5.1 Primeira tentativa

Comando executado pelo script v1:

```bash
sudo adduser --disabled-password --gecos "" teste
```

Efeito:

- conta local criada;
- UID/GID alocados;
- home criado;
- senha ainda não configurada.

Resultado no relatório:

```text
[PASS] Usuário local teste criado.
```

Em seguida, o script tentou:

```bash
sudo passwd teste
```

Resultado:

```text
[FAIL] Não foi possível definir a senha do usuário.
PASS=3 WARN=0 FAIL=1 GAP=0
```

A execução falhou de forma segura: nenhum privilégio adicional foi concedido.

### 5.2 Reprodução manual da falha

Comando:

```bash
sudo passwd teste
```

Saída observada:

```text
Sorry, user andrea.kiew is not allowed to execute
'/usr/bin/passwd teste' as root on ep125-pucpr.
```

Isso demonstrou que a falha não era a senha em si, mas uma restrição explícita da política `sudo`.

### 5.3 Diagnóstico da política sudo

Comando principal:

```bash
sudo -l
```

O diagnóstico mostrou bloqueios explícitos para, entre outros:

```text
/usr/bin/passwd
/usr/sbin/useradd
/bin/su
/usr/sbin/visudo
shells privilegiados e edição direta de arquivos sensíveis
```

Ao mesmo tempo, `adduser` permanecia permitido.

Resultado do diagnóstico:

```text
PASS=4 WARN=0 FAIL=0 GAP=0
```

## 6. Decisão de correção

Não foi adotado qualquer bypass da política sudo.

Foram descartadas:

- edição de `/etc/sudoers`;
- alteração de PAM;
- uso de `chpasswd` para escapar da restrição;
- shell root persistente;
- inclusão temporária em grupos administrativos;
- redução da política global de senha.

A correção foi usar **o fluxo administrativo já autorizado** pela VM.

## 7. Recriação pelo fluxo autorizado

Antes da recriação, a conta incompleta foi removida de forma controlada:

```bash
sudo deluser --remove-home teste
```

Depois a conta foi criada novamente com:

```bash
sudo adduser --gecos "" teste
```

Esse é o **comando exato que criou a conta final válida**.

A senha padrão da atividade foi informada no prompt interativo do próprio `adduser`.

Resultado:

```text
[PASS] Conta anterior removida de forma controlada.
[PASS] Remoção confirmada pelo NSS/getent.
[PASS] Conta criada pelo adduser autorizado.
[PASS] Conta resolvida pelo NSS/getent.
```

## 8. Aviso de comprimento da senha

A senha padrão definida para a atividade possui cinco caracteres.

Durante a criação, o PAM exibiu:

```text
BAD PASSWORD: The password is shorter than 8 characters
```

O sistema permitiu a confirmação da mesma senha.

A decisão foi **não reduzir a exigência global da VM** para acomodar uma credencial acadêmica específica. Nenhum arquivo PAM foi alterado.

## 9. Falha do coletor pós-criação

A primeira versão do coletor pós-criação encerrou antes dos testes finais porque usou a variável `GROUPS`, que é especial/read-only no Bash.

Esse defeito afetou apenas a coleta de evidência, não a conta criada.

A correção foi renomear a variável interna e executar um validador v3 somente leitura.

## 10. Validação final somente leitura

Comandos empregados:

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

Resultado final:

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

Esses `PASS=9` referem-se **somente ao escopo do validador estrutural v3**. A autenticação posterior foi validada em uma etapa separada, descrita abaixo.

## 11. Validação posterior de autenticação via PAM

Para encerrar a lacuna apontada pelo Codex Review, foi executado um teste posterior e independente da criação da conta:

```bash
su - teste -c '
  printf "WHOAMI="; whoami
  printf "UID="; id -u
  printf "GID="; id -g
  printf "GROUPS="; id -nG
  printf "HOME="; printf "%s\\n" "$HOME"
  printf "PWD="; pwd
'
```

A senha padrão foi digitada apenas no prompt interativo de `su` e não foi registrada.

Resultado observado:

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

Esse teste demonstra que a conta não apenas recebeu uma senha durante o `adduser`, mas também consegue autenticar posteriormente via PAM com a credencial exigida pela atividade.


## 12. Rastreabilidade por SHA-256

### 12.1 Relatórios operacionais

| Relatório | SHA-256 |
|---|---|
| `conectaeduca-evidencia-usuario-teste-ep125-20260911-200504.txt` | `9155db17a442bbe86fcb027aca32a558ea8556a20fbb339d00e89ca27f98f839` |
| `conectaeduca-diagnostico-sudo-usuario-teste-ep125-20260911-201335.txt` | `d1a09def1b4e740535bcbd215e1416d9e31b22c0b056e4d526e39556a98f15cb` |
| `conectaeduca-evidencia-usuario-teste-ep125-v2-20260911-201910.txt` | `2ca91502de4b77e7084b8f12cb447837789e431888cbc57cbecc5c704f6d7e32` |
| `conectaeduca-evidencia-usuario-teste-ep125-v3-20260911-203147.txt` | `85b83f2d9d4f3d6239aaea2e1c8210ef9a6a4ca5a2feec033a206206318a32df` |
| `conectaeduca-evidencia-autenticacao-teste-ep125-20260911-214416.txt` | `0eac4ac894ec48145d5996df3b2203a1fa44d47e8f53a09d5ab375311903849e` |

### 12.2 Scripts utilizados

| Script | SHA-256 |
|---|---|
| `conectaeduca-criar-validar-usuario-teste-ep125-v1.sh` | `1fc90968d462389b5b26d324cd3cee1766c8dd3791495def8d45319d0528c058` |
| `conectaeduca-diagnostico-sudo-usuario-teste-ep125-v1.sh` | `ea27aeaed5bc210a9d1d82de6052f66a17fb0a2efc3d660135947dedb2a569b8` |
| `conectaeduca-recriar-validar-usuario-teste-ep125-v2.sh` | `6f86da615079da14efdf8c0429263e221ee82e83c60fa7bd471e3d9604cd1000` |
| `conectaeduca-validar-usuario-teste-ep125-v3.sh` | `0decddbe3132d9d2a84e93cb1e783b5193b0562340d06ea227ef2039e86e5acd` |
| `conectaeduca-validar-autenticacao-teste-ep125-v1.sh` | `2b826d3d09440840299a216673c2d53f4f6e940c0e3d9d2b4bbece2a030ed16e` |

Os hashes permitem vincular os nomes dos relatórios e scripts a conteúdos imutáveis sem versionar credenciais.

## 13. Interpretação de segurança

A conta `teste` possui apenas capacidades compatíveis com um usuário local comum:

- UID não privilegiado;
- grupos comuns;
- ausência de sudo;
- sem leitura de `/etc/shadow`;
- sem escrita direta em `/etc`.

A solução preservou a política institucional da VM e demonstrou que cumprir um requisito acadêmico não exige enfraquecer o host.

## 14. Estado

**EP125 / privilégio mínimo estrutural: validado.**

**Autenticação posterior com a senha padrão: validada via PAM.**

**Estado geral da EP125: concluído sem GAPs neste requisito.**

A criação do usuário equivalente na EP126 e a conta de aplicação `teste@pucparana.com` serão tratadas em etapas próprias.
