# GA-08.17B — Pacote de mudança controlada e retorno ao baseline — EP125

**Data:** 02/11/2026 (BRT) · **Escopo:** PA-02, DMZ EP125 · **Estado:** PREPARADO PARA REVISÃO; CUTOVER **NÃO AUTORIZADO**.

> Este documento NÃO é uma ordem de execução. Nenhum arquivo deste PR deve ser aplicado na EP125 antes da aprovação da responsável, identificação do snapshot restaurável, janela autorizada, revisão do procedimento de recuperação e confirmação dos segredos/mounts pelo operador. PR permanece **DRAFT**; não habilitar auto-merge.

## 1. Fonte de verdade e separação da PR #200

- Baseline versionado: `main` **b74ea581a0814d86a99b6b455d5569f12fa967e5**; na EP125 esta era a HEAD de 02/11.
- Fonte do candidato: PR #200, commit **27361d89368eb49e09dc022d5f514de28feeb6da**.
- A PR #200 continha 87 arquivos, 147 commits à frente e 29 atrás do ancestral de comparação; GitHub indicava `mergeable=false`. Por isso a alteração GA-08 foi **extraída para branch específica sobre a main**, sem incorporar a arquitetura Twingate, Bacula, outras PRs ou ajustes do PHP.
- Os arquivos `deploy/dmz/compose.ga08-socket.candidate.yml` e `deploy/dmz/compose.ga08-dual-socket.candidate.yml` são overlays **candidatos**; o segundo deve ser o último `-f`.
- A configuração `app-http.dual-socket.candidate.conf` troca apenas `listen 8080;` por listener Unix; seis destinos FastCGI passam para socket no candidato intermediário. Scripts `ga08-implantacao-controlada-ep125.sh` e `ga08-rollback-controlado-ep125.sh` são intencionalmente **gates fechados**; não executam cutover ou rollback.

## 2. Evidências de laboratório já comprovadas (não repetir sem alteração causal)

| Gate | Resultado | Limite |
|---|---|---|
| GA-08.10 | 7/7 testes de contrato e 11/11 verificações Compose com placeholders PASS | configuração estática, não produção |
| GA-08.11 | Transporte HTTP por socket WAF→Nginx, 200 PASS | sem CRS/FPM |
| GA-08.12 | Ambos sockets integrados, FastCGI `pong`, PASS | sem CRS |
| GA-08.13–15 | WAF atual tem ModSecurity/regras, requisição benigna 200, XSS sintético 403, IDs CRS correlacionados | ainda via backend TCP atual |
| GA-08.16 v2 | WAF com entrypoint original/CRS, socket HTTP, socket FastCGI e PHP-FPM isolados: 200 legítimo, 403 XSS, correlação CRS PASS | sem dados reais, TLS institucional, SQL, login/MFA |
| GA-08.17 | 10/10 Compose baseline idênticos, manifesto SHA-256 PASS; produção healthy | rollback efetivo pendente |
| GA-08.17A | 8/8 bind mounts visíveis de dentro dos contêineres; 6 de 8 acessos às fontes no host sem permissão do usuário; três imagens base disponíveis | dados externos/recuperação de segredo NÃO comprovados |

Evidências privadas ficam em `~/ConectaEduca_Fase2_Evidencias/EP125/GA08/` e diário EP125. **Não** copiar arquivos de `secrets`, `.env`, certificados privados, dados de produção ou logs brutos para GitHub/Trello.

## 3. G0 — bloqueios obrigatórios para a janela

- [ ] **Snapshot institucional identificado** (ID, data/hora, discos incluídos, retenção, operador responsável); comprovar que covers EP125 rootfs e todos os discos/volumes necessários. VM snapshot não garante dados de bind externos/NFS/outros hosts.
- [ ] **Restauração praticável** confirmada pelo operador institucional; documentar plano de retorno e condição para invocar o snapshot se rollback Docker falhar. Não presumir que snapshot integral implique restore ensaiado.
- [ ] Conferir proteção e recuperabilidade dos **3 bind mounts WAF** e **5 PHP**, inclusive os seis cujas origens retornam `EACCES` ao usuário comum; validação pela pessoa autorizada, sem exibir segredos.
- [ ] Diretório de origem de certificados/CA, Docker volumes e arquivos de ambiente preservados com permissões e backup apropriado. Cópia de 10 Compose em `GA08/ROLLBACK_BASELINE_20261101T160926_teQE6K/compose/` **não** equivale a backup completo.
- [ ] Manter imagem anterior de cada serviço identificada por **Image ID/digest**, acessível no daemon Docker; não fazer `image prune` durante a janela.
- [ ] Registrar operador, responsável, início/fim previstos, janela de interrupção, comunicação e autorização.
- [ ] Review cruzado do Compose atual (ordem efetiva e mounts) e do pacote; testar `docker compose config` com variáveis reais **sem imprimir o conteúdo**.
- [ ] Confirmar especificamente a disponibilidade do banco de dados EP126 e testes de regressão de TLS/CA/RBAC/MFA; dependências de services não podem ser declaradas pelo healthcheck isolado.
- [ ] Gate de implantação NÃO pode ser aberto apenas por CI, runtime saudável, ensaio efêmero ou comentário na PR.

**Ausência de qualquer item G0 = ABORTAR, sem recriar contêineres.**

## 4. Sequência planejada — ainda NÃO executável nesta PR

**Ordem dos dez arquivos de baseline**, obtidos dos labels de Compose dos contêineres e conferidos com o manifesto EP125:
1. `compose.yml`
2. `compose.database.yml`
3. `compose.app-secrets.yml`
4. `compose.waf.yml`
5. `compose.waf-tls.yml`
6. `compose.waf-policy.yml`
7. `compose.host.yml`
8. `compose.vm.yml`
9. `compose.database-tls.yml`
10. `compose.audit-persistent.yml` — **arquivo local, não rastreado na main: preservar sem substituir**.

O operador deve registrar a ordem **real** obtida em `com.docker.compose.project.config_files` e parar se divergir. Sobre os dez arquivos, acrescentar **nesta ordem**:
11. `compose.ga08-socket.candidate.yml`
12. `compose.ga08-dual-socket.candidate.yml` (último).

**Preparação dos paths:** somente na janela aprovada, em local persistente controlado e com `stat` verificado. Dois diretórios distintos: FPM (`CONECTAEDUCA_GA08_SOCKET_DIR` UID/GID 82:82 modo 0770) e HTTP (`CONECTAEDUCA_GA08_HTTP_SOCKET_DIR` UID/GID 101:101 modo 0700). Não compartilhar com segredos/logs nem criar socket por `chmod 777`. Os arquivos `CONECTAEDUCA_GA08_NGINX_CONF`, `CONECTAEDUCA_GA08_NGINX_HTTP_UNIX_CONF` e `CONECTAEDUCA_GA08_FPM_CONF` devem apontar para cópias **persistentes, legíveis e imutáveis durante o cutover**, não para arquivos em `/tmp` apagados ao fim do teste.

**Checklist de ordem de execução, não script automático:**
1. Congelar alterações concorrentes, registrar `git rev-parse HEAD`, hashes de arquivos Compose e Image IDs; registrar baseline HTTPS, 403 CRS, login/MFA/RBAC, PHP→SQL, agente e Wazuh.
2. Validar `docker compose config --quiet` com os **10 arquivos reais + 2 overlays**, paths de mount reais e env do projeto sob custódia, sem mostrar `config` bruto/credenciais. Verificar WAF TCP80/443 preservado, Nginx sem TCP/expose, PHP sem TCP/expose; WAF e Nginx apenas `waf_backend`, PHP apenas `php_egress`, RO/RW e UIDs.
3. Preparar os dois diretórios do socket com permissões mínimas e verificar que os mounts/secret files estão disponíveis. **Não desmontar volumes de dados.**
4. Somente após autorização específica de cutover, definir e revisar os comandos exatos de `docker compose ... up -d --no-deps --force-recreate` para `php`, `nginx`, `waf`, com janela de interrupção prevista. Não executar na ordem suposta nem com `-f` omitidos. **Nunca `down -v`**.
5. Observar `healthy` dos três componentes e executar E2E pelo WAF: HTTP/TLS com CA, 200 benigno e 403 CRS, FPM, login/MFA/RBAC e SQL autenticado, Wazuh/telemetria, Twingate permitido/negado, sem expor dados.
6. Testar PA-02 negativo a partir do host EP125 contra o **novo IP real** da bridge e porta 8080, PHP→Nginx TCP, outro contêiner não autorizado→upstream, preservando WAF→app positivo. NÃO fixar IP antigo `172.18.0.2`: pode ter mudado. Verificar ausência de listener HTTP TCP no namespace do Nginx.
7. Registrar ID, horário, hashes, diferença antes/depois e risco residual (root/Docker admin pode contornar restrições). **PA-02 aberto até esses retestes.**

## 5. Plano de retorno ao baseline — REQUER validação do operador

**Gatilhos de aborto:** WAF/HTTPS indisponível; Nginx/PHP unhealthy; falha FastCGI/SQL; login, MFA, RBAC ou TLS regressivo; CRS deixa de bloquear; telemetria crítica desaparece; acesso lateral indevido ainda presente; perda de mount protegido.

**Rollback Docker previsto (ainda não ensaiado):**
1. Congelar novas mudanças e registrar momento da falha sem despejar segredos.
2. Referenciar as **cópias verificadas dos 10 arquivos Compose baseline**, com o overlay de auditoria local e env/certificados/mounts preservados. A configuração de rollback **NÃO inclui os dois overlays GA-08**.
3. Operador valida caminhos, Image IDs anteriores e `docker compose config --quiet` com o conjunto baseline; se faltar arquivo/mount/secret, **NÃO forçar recriação**.
4. Em janela aprovada e **com imagem anterior preservada**, restaurar a stack WAF/Nginx/PHP à definição anterior usando `docker compose -f <cada arquivo baseline na ordem registrada> up -d --no-deps --force-recreate php nginx waf`, sem `down -v` e sem `pull`; revisar a seleção dos serviços e dos arquivos com o operador antes de executar. Comando aqui é **esquemático**, não copiável literalmente.
5. Confirmar 3/3 healthy, HTTPS CA/TLS correto, HTTP 200/403, login/MFA/RBAC, SQL EP126, audit.log persistente/Wazuh e Twingate. Provar não só start dos contêineres mas recuperação funcional.
6. Se rollback por Compose falhar ou depender de secrets/mounts indisponíveis, interromper novas tentativas e acionar **restauração do snapshot institucional** com o operador; validar o estado restaurado e eventual consistência de dados externos.
7. Registrar ocorrência, causa, evidências, tempo de retorno e decisão de manter PA-02 aberto; não classificar rollback como PASS sem execução/retorno demonstrado.

**Estado em 02/11:** rollback Docker = PROPOSTO/NÃO EXECUTADO; rollback por snapshot = PENDENTE SUPORTE. Scripts deste PR continuam com gate fechado.

## 6. Pendências específicas para amanhã (03/11)

Solicitar snapshot integral **antes** da mudança, registrar ID/tempo/operador, confirmar discos e mounts protegidos e procedimento restaurável. Confirmar revisão da PR isolada e do plano de rollback; só então elaborar o `change control` executável. No dia da janela, qualquer drift entre `main`, EP125, Compose efetivo e candidato exige nova revisão antes de cutover.

**Status final:** GA-08.10–16 PASS em seus escopos; GA-08.17/17A PASS para verificação de baseline, **G0 BLOQUEADO** e GA-08.18 **NÃO EXECUTADA**.
