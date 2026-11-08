# CE-PA06-ROT01 — Rotação automática de auditoria PHP / EP125

**Responsável:** Andréa Kozicki. **Data:** 08/11/2026. **Escopo:** EP125/DMZ `audit.log`. **Intervenção:** instalar política única em `/etc/logrotate.d/conectaeduca-php-audit`, sem girar logs imediatamente.

## Motivação e estado confirmado

- PA-06 já possui `audit.log` persistente via bind PHP `/var/log/conectaeduca/php-audit` e E2E com Wazuh Agent001→Manager rule110250 comprovado em 23/10. O arquivo original não deve ser excluído, truncado nem transportado.
- Evidências históricas EP125: arquivo UID/GID 82:82 modo 0600; diretório UID/GID 82:82 modo 0700. O UID 82 pode não ter conta nominal na EP125. O `logrotate` aceita `:82` para forçar identidade numérica, inclusive quando usuário não está em `/etc/passwd`.
- `AuditLogger::log()` abre `audit.log` a cada evento com `FILE_APPEND | LOCK_EX`; estratégia prevista é renomear e criar, **sem** `copytruncate`, que pode perder entradas.
- O modelo `deploy/dmz/logrotate/php-audit.logrotate.conf.in` na PR #203 tinha marcadores deliberadamente não preenchidos. Não instalá-lo diretamente.

## Política laboratorial provisória aplicada somente após execução

```text
daily, maxsize 16M, rotate 30,
missingok, notifempty, compress, delaycompress,
su :82 :82, create 0600 :82 :82
```

O limite `rotate 30` representa **até 30 gerações**, **não um compromisso de 30 dias corridos**; o prazo institucional de retenção e a política de PII dos alertas Wazuh ainda dependem de aceite. O agendamento é o padrão `logrotate.timer` ou cron diário existente, sem criar novo serviço.

## Guardas e limites da implementação

- Executar **na EP125, usuário não root**, com `sudo -v` e somente chamadas `sudo` restritas. Não usar `sudo -s`. Recusa host diferente de `ep125-pucpr`, branch fora do commit de freeze `04f88d275064a005d0ffcd4f9372a371c28c32d5`, log ausente/symlink, metadata UID/GID/mode inesperado, logrotate ausente, agendamento indisponível.
- Configuração nova é validada com `logrotate -d` (dry-run de parser, sem escrita de arquivo de estado e sem rotação). Aborta se detectar política existente/duplicada; não sobrescreve outras regras.
- Instala arquivo regular root:root 0644 em `/etc/logrotate.d` com `sudo install`. Verifica conteúdo e que o inode do log ativo não mudou. A instalação habilita a rotação **na próxima execução regular do logrotate**, não imediatamente.
- **Não executa**: `logrotate -f`, `copytruncate`, Docker/Compose, systemctl restart, mudança de Wazuh, PHP, Twingate, pfSense, OpenBao, limpeza de dados ou leitura de valores de `audit.log`.
- Se já existir política idêntica, a rotina retorna com êxito idempotente. Se outra política existir, aborta sem substituir.
- O script e a política ficam numa PR isolada, **DRAFT**; não mesclar na main do freeze sem atualizar referências de EP125/EP126.

## Aceite e riscos residuais

**Aceite imediato após execução:** `POLITICA_INSTALADA=SIM`, `LOG_ATIVO_ROTACIONADO=NAO`, `LOG_ATIVO_INODE_PRESERVADO=SIM`, `CE-PA06-ROT01_CONCLUIDO`.

**Ainda não comprovado:** giro automático real, permissões após o primeiro ciclo, continuidade da ingestão Wazuh após troca de inode, retenção conforme política institucional, riscos de PII já indexada, restauração de logs. Não declarar **PA-06 integralmente encerrado** somente pela instalação.

**Rollback seletivo** (apenas com autorização e registro do change): remover exclusivamente `/etc/logrotate.d/conectaeduca-php-audit` se o conteúdo for idêntico ao manifesto aprovado e nenhuma outra política estiver apontando para ele. Não apagar logs rotacionados, não forçar giro nem reiniciar serviços.

## Comando de execução

Obter `ops/pa06/ce_pa06_rot01_install.sh` de commit imutável, verificar blob `git hash-object` e `bash -n` localmente, executar com `bash` como `andrea.kiew` na EP125. Nenhum teste invasivo além da verificação de sintaxe integrada.

## Correções adicionais PA

- **PA-01:** CE-ZT47 interzona 6 fluxos allowed + SSH denied com logs; manter regras no pfSense, não introduzir mudança em lote.
- **PA-02:** GA-08 dual socket de PR #217 em hold após incidente fail-closed; não aplicar sem novo G0+rollback.
- **PA-03:** nenhuma escalação observada no recorte, monitorar.
- **PA-04:** OpenBao EP126 recuperado CE-OB01/02, healthy; AppRole/ACL faltam.
- **PA-05:** cobertura vertical favorável; BOLA horizontal exige fixture adequada.
- **PA-06:** nova política lab de logrotate será implantada pela CE-PA06-ROT01 sem alterar PHP/Wazuh.
- **PA-07:** scripts DLP+regras Wazuh já operantes; Ferret v5 ainda precisa janela e rollback.


## Incidente de compatibilidade com a política sudo — 08/11/2026

**Primeira tentativa EP125 16:23:47 BRT:** script validado por hash/sintaxe, usuário `andrea.kiew`, `PERMISSOES_AUDITORIA=82:82_0600_DIR_0700`, `AGENDA_LOGROTATE=SYSTEMD_TIMER`, `REGRA_DUPLICADA=NAO`, `CONFIGURACAO_SINTAXE=PASS`. Após a etapa de `sudo install`, a camada institucional sinalizou **"Comando 'sudo -s' detectado, uso não permitido"**; o script abortou `CE-PA06-ROT01_ABORTADO=INSTALACAO_DIVERGENTE`.

**Causa provável:** `sudo cmp -s -- ...`, usado somente para comparação silenciosa, foi interpretado equivocadamente pelo filtro de comandos como `sudo -s`. A responsável **não invocou** `sudo -s`; trata-se de opção `-s` do `cmp` após um comando sudo. A análise é inferida da ordem das linhas, sem acesso ao log de auditoria do filtro. **Risco de estado parcial:** `sudo install` pode já ter instalado `/etc/logrotate.d/conectaeduca-php-audit`; não executar novamente o instalador antes de conferir.

**Correção de código:** removidas as duas ocorrências de `sudo cmp -s`, utilizando `cmp -s` como usuário normal porque o destino é instalado root:root modo 0644 (legível), e verificando modo/proprietário na comparação. Alteração isolada nesta PR; **não executar novamente a versão antiga**.

**Verificação única, sem sudo e sem nova mudança:**
- `stat -c '%u:%g:%a' /etc/logrotate.d/conectaeduca-php-audit` deve ser `0:0:644`.
- `sha256sum /etc/logrotate.d/conectaeduca-php-audit` deve ser `f0d9fe60ca866f9bee435665e67b7705dcb302bcf1daa18ce71928b0959e5e2d`, para a política estática desta PR.
- Se ambos coincidirem e `CONFIGURACAO_SINTAXE=PASS` já foi observado, **a política foi instalada**. Nenhuma outra execução privilegiada é necessária.
- Se arquivo ausente/divergente, registrar o resultado sem sobrescrever ou ativar novos comandos privilegiados até revisão.

**Observação metodológica:** instalação de config ≠ primeira rotação ≠ garantia de Wazuh pós-inode. Não marcar PA-06 globalmente PASS.
