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
