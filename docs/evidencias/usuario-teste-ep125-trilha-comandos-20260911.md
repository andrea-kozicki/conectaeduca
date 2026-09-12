# Trilha de execução — privilégio mínimo EP125

Este documento correlaciona os comandos centrais dos scripts com os resultados observados nos relatórios operacionais.

| Etapa | Comando | Efeito | Evidência |
|---|---|---|---|
| Primeira criação | `sudo adduser --disabled-password --gecos "" teste` | cria conta sem senha utilizável | `[PASS] Usuário local teste criado` |
| Tentativa de senha | `sudo passwd teste` | bloqueada pela política sudo | `[FAIL] Não foi possível definir a senha` |
| Diagnóstico | `sudo -l` | revela bloqueio de `passwd` e `useradd` | diagnóstico PASS=4 |
| Remoção da conta incompleta | `sudo deluser --remove-home teste` | remove conta sem senha e home | `[PASS] Conta anterior removida` |
| Criação final | `sudo adduser --gecos "" teste` | cria conta final e solicita senha interativamente | `[PASS] Conta criada pelo adduser autorizado` |
| UID | `id -u teste` | prova UID comum | UID=1001 |
| Grupos | `id -nG teste` | prova grupos não privilegiados | `teste users` |
| Sudo | `sudo -l -U teste` | verifica delegação administrativa | `SUDO_ALLOWED=no` |
| Shadow | `sudo -u teste test -r /etc/shadow` | testa leitura de credenciais | `ETC_SHADOW_READABLE=no` |
| /etc | `sudo -u teste test -w /etc` | testa escrita administrativa | `ETC_WRITABLE=no` |
| Autenticação posterior | `su - teste -c 'whoami; id; pwd'` | comprovará uso real da senha via PAM | **GAP pendente** |

## Observação sobre `--gecos ""`

O parâmetro apenas deixa vazios os metadados descritivos da conta. Não altera UID, grupos, sudo, senha ou permissões.

## Observação sobre a senha curta

O PAM alertou que a senha possuía menos de 8 caracteres, mas permitiu sua confirmação. A política global da VM não foi alterada.

## Integridade

Os SHA-256 dos quatro scripts e quatro relatórios constam em:

- `docs/seguranca/PRIVILEGIO-MINIMO-USUARIO-EP125.md`;
- `docs/evidencias/usuario-teste-ep125-20260911.md`.
