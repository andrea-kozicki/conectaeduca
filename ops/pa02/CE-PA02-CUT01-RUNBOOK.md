# CE-PA02-CUT01 — GA08 dual Unix PA-05-safe, change control real

**Data:** 08/11/2026. **Responsável:** Andréa Kozicki. **EP125.** **Estado:** driver operacional preparado no GitHub, **NÃO executado na VM**. A rotina antiga `scripts/ga08-change-control.py --execute` da PR #217 **NÃO é compatível com o PHP PA-05 implantado**; continuar bloqueada.

## Situação técnica confirmada

- CE-PA05-DEP02 (08/11 17:40 BRT): PHP corrigido `conectaeduca/php-fpm:pa05-10328ab6` HEALTHY, segredos/auditoria preservados; utiliza 11º Compose `/home/andrea.kiew/.config/conectaeduca/pa05/compose.pa05-10328ab6.yml`.
- CE-PA02-RW01 (08/11 17:50 BRT): bind HTTP de socket UID101/GID101 modo0700 **RW e limpeza PASS**, Nginx HEALTHY, produção não alterada. GA08.33 havia comprovado FPM RW; não repetir baterias.
- GA08.31/32: `/run` canônico com Nginx saudável em sandbox; candidata `compose.ga08-runtimefix.candidate.yml` resolve tmpfs /var/run sobrepondo os sockets.
- Dois cutovers de 03 e 04/11 haviam sido revertidos (3/3 healthy). O snapshot de 03/11 **não inclui** o PA-05 de 08/11; não o tratar como plano de recuperação suficiente.

## Implementação versionada nesta PR

`ops/pa02/ce_pa02_cut01.py` possui três modos separados:

**`--mode prepare` (sem restart):** só aceita EP125 `andrea.kiew`, Git HEAD `04f88d27`, **11 Compose do PHP em produção**, imagem PA05 por tag + Image ID efetivo, três serviços healthy, diretórios socket host (HTTP 101:101/0700; FPM 82:82/0770) sem sockets raiz residuais. Em **uma única etapa**, baixa cinco artefatos candidatos da PR #217 pelo commit imutável `aa67a149ddcd14fdcbb28a66ea8785ac77579047`, valida Git blob, e reconstrói apenas o ambiente de interpolação de Compose com dados não secretos dos containers (host/porta, caminhos de mount; **não lê conteúdo das credenciais**). Exige que modelo Compose base (10+11º) e candidato (10+11º+3 GA08) mantenham **a MESMA imagem PHP PA05**, WAF/Nginx imagens constantes, sem upstream TCP, redes segregadas, /run canônico, bind de audit e secrets, read-only preservado. Cria diretório privado 0700 por change ID, `state.json` 0600 com imagens pré-corte e parâmetros não secretos (caminhos de secrets), e `approval.json` 0600 **com todos os seis gates false**. **Não criar nem marcar aprovações automaticamente.**

**`--mode apply --ack APLICAR_PA02_EP125` (MUDANÇA REAL):** só permite se o `approval.json` privado foi atestado pela responsável com nova **referência de snapshot pós-PA05**, `snapshot_created_at` timezone-aware **depois de 08/11/2026 17:40:01 -03:00**, evidência de restore, cobertura das mudanças PA05, recoverabilidade de TLS/secrets, janela aprovada e autorização de rollback; os booleans só podem ser `true` se fatos reais e verificáveis. Isso é **atestação documental da operadora**, não consulta direta ao hipervisor. Confere images/container IDs atuais sem drift, modelos Compose e hash dos artefatos; grava estado de início em disco; recria **sequencialmente** PHP→Nginx→WAF com `up -d --no-deps --no-build --pull never --force-recreate`. Aguarda healthy de cada contêiner na imagem original (PHP PA05 continua sendo imagem ativa). Confere Unix sockets FPM/HTTP, backend WAF Unix, bridge TCP 8080 e 9000 negados ao host EP125, e **uma única requisição** a `https://<bind WAF>:<porta>/api/public_key.php` com resposta HTTP200 (sem imprimir corpo; smoke sem validação CA estrita). Em sucesso grava `CUTOVER_HEALTHY` e `CE-PA02-CUT01_CONCLUIDO`.

**`--mode rollback --ack ROLLBACK_PA02_EP125` (MUDANÇA REAL):** usa o `state.json` privado e as referências anteriores mesmo se os contêineres falharem; recria PHP, Nginx, WAF usando **10 Compose base + 11º PA05**, **não** os dez originais sozinhos. Exige `healthy` e **Image ID** de cada baseline. O rollback é best effort; se falhar, escalar para restauração institucional, sem repetições cegas. Erros durante o cutover também acionam esta tentativa de retorno automaticamente.

**Nenhum script é executado automaticamente pelo GitHub.** A PR fica DRAFT, não altera a `main` ou o checkout das VMs.

## Proteções específicas

- Não executa `sudo`, não altera pfSense/Twingate/OpenBao/Wazuh/Ferret, nem recria contêiner diferente de PHP/Nginx/WAF.
- Não faz `docker build`, pull/prune/down, não remove segredos, não gera `.env`, não publica `docker compose config` nem env/logs; arquivos candidatos são publicados e seus Git blobs verificados. O contexto privado **deve permanecer no host enquanto os sockets estiverem ativos**, pois as configurações Nginx/FPM e o overlay do Compose são bind mounts/arquivos de controle.
- Interrompe se existir `nginx.sock`/`php-fpm.sock` residuais nos dois binds antes de cortar; nunca apaga socket à força.
- `state.json` armazena **caminhos de arquivos secretos, não valores**; por isso é 0600 e não deve ser publicado.
- O smoke de HTTPS não substitui TLS CA estrita, MFA/RBAC ou pentest. A comprovação relevante do PA-02 é a **negação de conexões TCP diretas** e o encadeamento via WAF HTTP200 após corte, ainda limitado à origem testada.
- Depois de implantar, a operação de manutenção precisa continuar usando **todos os 14 Compose** (10 originais, 11º PA05, 3 GA08) até promoção canônica; reaplicar somente 10 ou 11 pode reabrir bypass ou retornar código antigo. O script guarda o contexto como fonte operacional da sequência.

## Dependência externa bloqueadora — snapshot pós-PA05

Solicitar ao suporte **nova imagem/snapshot EP125 posterior à implantação de 08/11 17:40 BRT**, incluindo discos/volumes/binds, com ID não ambíguo, hora/fuso, operadora autorizada e procedimento de restauração que preserve:
- a imagem PHP `conectaeduca/php-fpm:pa05-10328ab6` e o 11º overlay;
- certificados, CA, segredos/ACL e log persistente de auditoria;
- os artefatos e permissões dos sockets GA08;
- a configuração funcional WAF/Nginx e acesso institucional.

**Sem essa evidência e janela aprovada, NÃO solicitar ao usuário `--mode apply` nem criar aprovações simuladas.** `--mode prepare` é uma montagem mínima de plano e não outra bateria de testes, mas também não precisa ser executada até existir uma janela concreta.

## Critério documental

- [x] Gate HTTP RW resolvido CE-PA02-RW01 08/11 17:50 BRT.
- [x] Novo driver de corte PA05-safe e rollback versionados no GitHub.
- [ ] Snapshot pós-PA05, comprovação da recuperabilidade e janela G0 real.
- [ ] Preparação privada `CE-PA02-CUT01_PREPARACAO_CONCLUIDA` na EP125.
- [ ] Cutover real `CE-PA02-CUT01_CONCLUIDO`, WAF→app HTTP200 e bypass 8080/9000 negado.
- [ ] Avaliação dos riscos residuais (operador Docker/root e egress).
- [ ] **PA-02 ainda ABERTO em runtime.** Não confundir script preparado, gate estático ou aprovação documental com isolamento aplicado.
