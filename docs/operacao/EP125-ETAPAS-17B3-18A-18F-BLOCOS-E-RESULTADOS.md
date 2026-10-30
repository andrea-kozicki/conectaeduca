# EP125 — Homologação 17B.3 e 18A–18F (30/10/2026)

## Objetivo e limites
Registros dos blocos executados pela operadora para diagnóstico estático RBAC/CSRF, auditoria PHP e agente Wazuh. **Nenhum bloco é autorização de deploy, restart, reinstalação ou alteração de volumes.** Os TXT locais originais permanecem como fonte primária.

## Blocos e evidências
| Etapa | Bloco/ação | Evidência e resultado |
|---|---|---|
| 17B.3 | Busca estática de rotas com `find ... -exec grep` | Mapeamento de rotas; não é teste RBAC/CSRF funcional |
| 18A | `ce_18a_audit_persistencia_preflight.sh` | `EP125_HOMOLOG_ETAPA18A_20261030T192838.txt`; bind RW + audit.log 34.128 bytes; Wazuh failed |
| 18B | `systemctl show/is-active/is-failed`, `ps`, existência de caminhos | `EP125_HOMOLOG_ETAPA18B_20261030T192940.txt`; enabled/failed/timeout; caminhos não acessíveis ao usuário |
| 18C | `systemctl show`, `dpkg-query`, `dpkg-query -L`, `docker ps` | `EP125_HOMOLOG_ETAPA18C_20261030T193034.txt`; pacote 4.14.7-1 hold; start via wazuh-control, timeout 45s |
| 18D | `dpkg --verify`, `findmnt`, `stat`, `find`, `apt-mark showhold` | `EP125_HOMOLOG_ETAPA18D_20261030T193125.txt`; /var/ossec root:wazuh 750, Permission denied |
| 18E inicial | `sudo -n true` com `exit 2` colado no shell | Abortou a sessão interativa; **bloco defeituoso, não reutilizar** |
| 18E corrigida | `bash <<'SCRIPT_18E' ... SCRIPT_18E` e sudo autenticado | `EP125_HOMOLOG_ETAPA18E_CORRIGIDA_20261030T194152.txt`; arquivos essenciais presentes; timeout journal |
| 18F | `bash <<'SCRIPT_18F' ... SCRIPT_18F`; grep restrito em ossec.log | `EP125_HOMOLOG_ETAPA18F_20261030T194256.txt`; log existe; filtro não retornou mensagens; Wazuh failed |

## Correções de interpretação
- Caminhos sob `/var/ossec` não eram necessariamente ausentes: permissões 750 impediram inspeção sem sudo. Etapa 18E confirmou os principais caminhos existentes.
- `dpkg --verify` privilegiado indica ausência de arquivos auxiliares, mas não comprova a causa do timeout.
- O filtro de 18F não encontrar mensagens **não** significa que `ossec.log` esteja vazio.
- O bind RW de `storage/logs` não substitui teste de persistência após recriação sob change control.

## Procedimento seguro para os próximos blocos
1. Autenticar explicitamente: `sudo -v` (se permitido).
2. Executar scripts sempre como processo filho: `bash /caminho/script.sh` ou heredoc `bash <<'SCRIPT' ... SCRIPT`. Não colar `exit` no shell interativo.
3. Capturar apenas metadados e erros necessários; não copiar ossec.conf, client.keys, logs brutos nem segredos.
4. Não executar `systemctl restart`, `dpkg --reinstall`, `docker compose up` ou `git clean` sem autorização e rollback.
5. Encaminhar ao suporte: timeout 45s do wazuh-agent na EP125, falha às 15:57:43 BRT; solicitar análise privilegiada dos logs e confirmação de manager/registro, sem expor chaves.
6. Após recuperação, validar se eventos do audit.log chegam à EP126 e documentar o caminho de coleta.

## Decisão sobre pentest 2
Testes RBAC/CSRF/IDOR/BOLA negativos com contas sintéticas, inclusive segunda empresa, foram adiados. Twingate limita acesso à rede; não substitui autorização da aplicação. Issue #201 e P0 permanecem abertos.
