# GA-07 — Plano de decisão para rotação, retenção e privacidade do audit.log PHP
**ConectaEduca • 25/10/2026 • Status: PROPOSTA DOCUMENTAL, SEM ALTERAÇÃO OPERACIONAL**

## 1. Situação comprovada e limites
- **EP125:** PHP-FPM 8.5.12 opera com `audit.log` persistido no host em `/var/log/conectaeduca/php-audit/audit.log` por bind específico; `storage/keys` e `/tmp` permanecem tmpfs. Evidências históricas EP125-F2-0038 (arquivo modo 0600, UID/GID 82:82, hash host/contêiner igual, evento sintético registrado).
- **EP126:** a trilha de auditoria PHP foi coletada pelo Wazuh Agent 001 e correlacionada no Manager pela regra 110250 em EP126-F2-0062, 23/10, marcador `CE-AUD07-20261023-E2E-02`. **Isso encerra somente a lacuna de ingestão testada**, não a integridade após rotação, proteção de dados e política de retenção.
- **Rotação:** houve obstáculo de `euid/egid` durante simulação anterior em 24/10. Não há aceitação de `logrotate` em produção nem evidência de retenção efetiva, de um ciclo completo de rotação ou de leitura pós-rotação do Wazuh.
- **Versão de código:** o PR #203 continua DRAFT e sua descrição original contém etapas históricas já superadas pelo runtime; priorizar evidências cronologicamente mais recentes.

## 2. Decisões que dependem de suporte/professor (28/10)
1. **Prazo e justificativa:** definir os períodos oficiais de retenção do log ativo e dos arquivos rotacionados conforme a política acadêmica/institucional (não inventar 7/30/90 dias). Definir eventuais exceções de preservação incident response e quem autoriza descarte.
2. **Escritor do log:** confirmar se o `AuditLogger` reabre o pathname em cada evento (ex.: `file_put_contents`/append) ou mantém descritor aberto. Isso determina a viabilidade de `rename + create` sem perder escritas; não assumir que `copytruncate` seja seguro (janela de perda/duplicidade).
3. **Leitor Wazuh:** confirmar comportamento do `wazuh-logcollector` diante da renomeação e recriação do arquivo, privilégios efetivos e se pode acompanhar corretamente o novo inode/offset; proibir duplicar entradas `localfile` remotas/locais.
4. **Privilégios:** validar diretórios, UID/GID 82:82 do escritor, modo 0600 do `audit.log`, travessia mínima e identidade efetiva do executor do `logrotate`. Diagnosticar o `euid/egid` reportado antes de escolher `su`, ACL ou execução privilegiada. Não usar `chmod 777`.
5. **Formato e privacidade:** classificar `user_id`, IP, user-agent, códigos de evento, carimbos temporais e dados de sessão; preferir minimização do esquema, controle de acesso ao arquivo bruto e alertas indexados, sem prometer que `no_full_log` remove todos os campos JSON.
6. **Destino e capacidade:** aprovar compressão/criptografia ou proteção equivalente dos arquivos rotacionados, backup, monitoração de espaço em ext4, mecanismo de acesso investigativo e descarte verificável; não publicar no Git, Trello ou anexar conteúdo bruto a PR.

## 3. Proposta de ensaio controlado (SOMENTE após autorização)
- **Pré-ensaio:** preservar estado do arquivo e configuração sem expor linhas; registrar horário, hash e tamanho; confirmar janela, backup, operador e rollback. Examinar config logrotate sem executar `--force`.
- **Simulação/dry-run:** rodar com a identidade correta em homologação e conferir sintaxe, dono/grupo dos novos arquivos e conflito de `euid/egid`; corrigir o bloqueio documentado. Dry-run aprovado não demonstra rotação real.
- **Ensaio sintético:** emitir no máximo eventos de teste autorizados, com marcadores não sensíveis antes/depois da rotação; confirmar que o escritor continua gravando, que não existem lacunas ou duplicidades e que o Wazuh recebe somente o evento esperado (agente 001, localfile correto, regra apropriada).
- **Persistência/recuperação:** avaliar continuidade após reinicialização/recriação exclusivamente na janela aprovada; conferir que o log não retorna a tmpfs, preserva histórico útil e que a coleta continua. Não provocar reinícios para fabricar evidências.
- **Rollback:** preservar configuração e arquivos anteriores; em erro de permissões/rotação, parar a mudança de controle de logs e restaurar de forma auditável sem perder registros novos; documentar responsáveis e tempo de recuperação.

## 4. Critérios objetivos de aceite
- [ ] Política de retenção assinada por responsável e compatível com proteção de dados.
- [ ] Modo de rotação escolhido **após verificar** descritores do PHP e comportamento do coletor.
- [ ] Configuração e identidade de execução validadas (incluindo bloqueio `euid/egid` sanado).
- [ ] Regras de acesso mínimo para arquivos atuais e rotacionados comprovadas, sem conteúdo sensível nas evidências.
- [ ] Teste sintético pré/pós-rotação com numeração, Wazuh e ausência de duplicações.
- [ ] Capacidade, monitoramento, backup, compressão/descartes e rollback aprovados.
- [ ] Evidência cronológica, arquivos sanitizados e SHA-256 arquivados nos diários; issue #195 atualizada com conclusão real.

## 5. Fronteira do Grupo A em 25/10
**Podemos preparar:** proposta de política, checklist, matriz de quem lê/escreve, critérios de aceitação e revisão do PR #203.  
**Não podemos afirmar:** rotação e retenção funcionando em EP125, perda de logs corrigida sob recriação, privacidade integral dos eventos, nem fechamento completo da PA-06.  
**Não executar hoje:** `logrotate -f`, alteração de UID/ACL, substituição da regra Wazuh, cópia de logs brutos, reinicialização do PHP-FPM, Docker Compose, agente Wazuh ou testes que alterem a trilha em produção.

Links: PR #203; issue #195; cartões Trello PA-06/AUD07 e Grupo A; handoff 28/10 em PR #200.

## 6. Complemento de segurança offline — 26/10/2026 (sem VMs)

### GA07-PRIV-01 — arrays sob chaves sensíveis não eram mascarados integralmente

**Análise estática de `src/Security/AuditLogger.php` no checkout do PR #203:** o método privado `redact(array $context)` mascarava chaves `password`, `token`, `refresh_token`, `private_key`, `recovery_codes` etc.; porém, havia dois `if` sucessivos. Quando o valor da chave sensível era um **array**, o primeiro atribuía `'[REDACTED]'` e o segundo chamava `redact($value)`, **substituindo o marcador por um array derivado do conteúdo original**. Se as subchaves não fossem sensíveis, seus valores continuariam presentes no JSONL de auditoria. Trata-se de **risco de exposição por lógica identificada no código**, não de vazamento comprovado nos logs institucionais.

**Correção DRAFT:** o loop agora utiliza `continue` imediatamente após mascarar uma chave sensível, impedindo que o valor original seja processado novamente. Para chaves não sensíveis, a recursão de arrays permanece. Não foram modificados `Env::rootPath`, o formato de eventos ou os caminhos/ACL de produção.

**Verificação efetiva:** `tests/Unit/AuditLoggerRedactionTest.php` adiciona **6 testes PHPUnit**, incluindo 17 nomes de chaves sigilosas, valores escalares/array, nested arrays, capitalização diversa, preservação de contexto não sensível e não mutação do parâmetro de entrada. Nenhum teste grava `storage/logs/audit.log` ou utiliza valores reais; todas as strings são fictícias. O PHPunit Security Tests confirmou esses seis casos; a suíte geral de PHP passou na primeira execução após a correção ([PR #203](https://github.com/andrea-kozicki/conectaeduca/pull/203)).

**Limites:** a fixação não mascara automaticamente o conteúdo livre de campos como `user_agent`, `ip` ou `context` com subchaves inesperadas/objetos; essas decisões requerem contrato de privacidade e análise de dados reais **sem expor conteúdo bruto**. A correção **não foi implantada** na EP125.

### GA07-CFG-01 — regressão estática da persistência e ingestão

Criado `tests/python/test_ga07_audit_contract_offline.py` com **11 testes** que inspecionam o Compose opt-in de auditoria, a coleta única `localfile` no grupo `conectaeduca-dmz`, compatibilidade do exemplo XML, regras JSON 110250/110251/110252, níveis 3/5/7, `no_full_log` e separação de eventos de login falho/acesso proibido.

A CI `.github/workflows/ga07-offline-audit.yml` executa o contrato estaticamente com `contents: read` e checkout por SHA fixado; GitHub Actions [GA07 Audit Offline Contract — 40406904937](https://github.com/andrea-kozicki/conectaeduca/actions/runs/40406904937): **11/11 PASS**. Isso valida **estrutura de arquivos**, não configuração efetiva do Wazuh na EP125/EP126.

### Falso positivo de fixture e escopo da mitigação

Na primeira execução do novo teste PHPUnit, o Gitleaks marcou a string literal `GA07-FICTICIO-NAO-SECRETO` no `tests/Unit/AuditLoggerRedactionTest.php` como `generic-api-key`. Ela é declaradamente sintética e foi criada nesta revisão; não corresponde a uma credencial institucional. Como o Gitleaks revisa também o **histórico Git da branch**, remover o literal do HEAD não eliminaria automaticamente o alerta histórico. Foi configurada uma exceção `[[allowlists]]` em `.gitleaks.toml` **limitada à regra `generic-api-key`, ao arquivo exato de teste e ao marcador literal exato**, preservando a detecção de outros padrões e o controle negativo do scanner. Gitleaks passou na execução posterior; nenhuma credencial foi enviada ao repositório.

### Gates que continuam abertos

- Aprovação institucional da política de retenção/privacidade dos logs, incluindo campos livres, PII e tratamento do conteúdo decodificado em alertas Wazuh (`no_full_log` não elimina todos os dados).
- Resolver `euid/egid`, determinar comportamento do coletor diante da troca de inode e validar rotação **real** com identidades/permissões adequadas.
- Testar após autorização PHP em execução, Wazuh real, continuidade pós-rotação e rollback, sem copiar logs sensíveis para CI.
- PR #203 DRAFT, sem merge; **PA-06 não foi encerrado operacionalmente**.
