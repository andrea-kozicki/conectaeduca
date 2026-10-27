# GA-07 / PR #203 — Reconciliação idempotente do que já foi implantado

**27/10/2026 • Estado: documento operacional para aprovação • NÃO executar sem change control.**

## Escopo e baseline confirmados

A EP125 **já opera** com o overlay `deploy/dmz/compose.audit-persistent.yml` local,
uso de **10 Compose no PHP** (9 na baseline de WAF/Nginx) e bind
`/var/log/conectaeduca/php-audit` → `/var/www/conectaeduca/storage/logs`.
O SHA-256 do arquivo local é
`36469d6694b9eb2e802822946efd788ffb1e97c95170d0f2680731a98699998e`;
seu blob Git no PR #203 é
`bfb1abca81b0a5f84e8ccda69c3c2da75294f2a1`.
A correspondência foi verificada na EP125 em 24/10 e não exige um novo inventário
para fundamentar o plano.

O `audit.log` persistente foi comprovado (modo 0600 e UID/GID 82:82,
hash host/contêiner igual nas evidências EP125-F2-0038/0039).
O pipeline PHP → Wazuh Agent 001 → Wazuh Manager → regra 110250 já teve
teste ponta a ponta sintético positivo (EP126-F2-0062, 23/10), com
revalidação parcial em EP126-F2-0064. Regras 110250–110252 já estavam
aplicadas. Não duplicar `localfile`, regras, bind nem tentar novo cutover
por mera promoção deste PR.

A correção de privacidade `AuditLogger::redact()`, originalmente repetida neste PR,
**já entrou na main** separadamente via PR #212
(commit `b74ea581a0814d86a99b6b455d5569f12fa967e5`, 4/4 CI PASS,
PHPUnit 138/482). A EP125 **não recebeu rebuild da imagem PHP**.

## Reconciliação Git: não confundir checkout, overlay e runtime

1. O `--plan` da EP125 de 27/10 às 16h56 registrou
   `PLAN_OK_READY_FOR_AUTHORIZATION`: checkout `main@4bf7ac6`,
   rastreados limpos, overlay local **não rastreado** com hash esperado,
   remoto `main@b74ea58`. Nenhum fetch/merge foi feito.
2. O script de fast-forward do checkout está **PINADO em b74ea58**.
   O PR #203 **não integra esse lote**: o overlay ainda está fora da main.
   Não dar merge no PR203 antes do fast-forward já preparado sem
   reavaliar a lista de arquivos e a colisão de arquivo local.
3. Após aprovação formal e snapshots com IDs comprovados, executar o
   procedimento `--apply` previamente preparado **se seu pin ainda
   corresponder ao HEAD remoto**, uma VM por vez, com rollback. Isso
   **não faz deploy** de código nem modifica mounts atuais.
4. Se, depois, o PR203 for integrado, haverá **colisão potencial**
   entre `compose.audit-persistent.yml` untracked e a mesma rota
   agora versionada pelo Git. O Git costuma recusar sobrescrever
   arquivos não rastreados; **não usar `reset --hard`,
   `git clean -fd`, remoção automática nem `git pull` genérico**.
5. Preparar nessa etapa posterior uma operação controlada:
   preservar cópia privada com modo 0600, conferir hashes e conteúdo
   do overlay contra o blob aprovado, garantir janela e backup;
   planejar migração do untracked ao arquivo rastreado mantendo
   os mesmos bytes. Só alterar a origem do arquivo no checkout, sem
   executar `docker compose up`, `down` ou recriar PHP.
   Se houver diferença, **BLOQUEAR** e voltar ao estado anterior,
   sem sobrescrever uma configuração viva.

## Fluxo Wazuh: versionar, não reaplicar

- A configuração `deploy/interna/wazuh/groups/conectaeduca-dmz/agent.conf`
  deve refletir a política do Manager já aplicada, incluindo **exatamente um**
  `localfile` para `/var/log/conectaeduca/php-audit/audit.log`.
  Não assumir que arquivo no Git ou no agente local espelha a configuração
  realmente carregada pelo grupo remoto.
- O arquivo `deploy/interna/wazuh/rules/zz_conectaeduca_php_audit_rules.xml`
  representa IDs 110250–110252 já implantados. Não duplicar em outra
  pasta do Manager nem recarregar o serviço automaticamente.
- Os testes offline do PR203 validam a estrutura XML/Compose, **não**
  provam identidade exata dos arquivos ativos do Manager; a comparação
  operacional deve ser pontual, quando autorizada, reaproveitando as
  evidências já produzidas.

## Pendências que não foram resolvidas com o merge de #212

- **Rotação e retenção:** aprovação da política institucional, `euid/egid`
  do `logrotate`, acesso mínimo, direitos de titulares e limites de
  retenção, comportamento do Wazuh após troca de inode e offset.
- **Continuidade:** não afirmar sobrevivência a reboot/recriação/restauração
  sem ensaio específico aprovado.
- **Privacidade de alertas:** `no_full_log` não garante eliminação de
  campos decodificados/PII em índices e encaminhamentos.
- **Rebuild PHP com AuditLogger corrigido:** depende de snapshot, plano
  de rollback e teste MFA/login quando incluído, separado do fast-forward.

## Decisão recomendada

**Fechar somente os deltas já provados**, sem novos inventários completos.
Deixar PR203 em DRAFT enquanto for necessário coordenar a promoção
de arquivos versionados com o runtime já aplicado. A revisão não autoriza
alteração nas VMs.
