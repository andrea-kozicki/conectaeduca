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
| GA-08.17C | WAF/Nginx criados com **9 arquivos Compose**, PHP com **10** (overlay local de auditoria); três Image IDs disponíveis e respectivas refs/tags correspondem às imagens em execução, saúde 3/3 e restarts=0 | filesystems de 6 fontes protegidas = INDETERMINADO por permissão; não prova ext4 nem storage externo; snapshot/rollback não testados |

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

**GA-08.17C: atenção à divergência legítima dos labels Compose.** A ordem abaixo representa o **conjunto de dez arquivos disponíveis para reconstrução**. Os contêineres WAF e Nginx, porém, foram **criados com apenas os arquivos 01–09**, enquanto o PHP foi **criado com 01–10**, incluindo `compose.audit-persistent.yml`. A inclusão do 10º arquivo em um comando para WAF/Nginx não foi a composição registrada em seus labels; evitar qualificá-la como restauração exata do baseline. Verificar a sobreposição e as consequências de cada `-f` e preservar a auditoria PHP.

**Ordem dos arquivos do baseline:**
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

A implantação candidata precisa ser avaliada como **um projeto Compose resolvido** que preserve a auditoria do PHP: utilizar o conjunto de 10 arquivos efetivos e, ao final, os dois overlays de socket na ordem abaixo, após validar a diferença 9/10 e a mesclagem sem imprimir segredos:
11. `compose.ga08-socket.candidate.yml`
12. `compose.ga08-dual-socket.candidate.yml` (**último**).

O **rollback fiel ao runtime anterior** é diferente do cutover: reconstruir PHP com **01–10**, porém WAF e Nginx com **01–09**. Não alterar o 10º overlay para forçar uniformidade dos labels; o arquivo de auditoria local continua indispensável ao PHP. Ordem de operações, Compose project, Image IDs, redes, mounts e `--no-deps` devem ser revisados antes da janela, com `docker compose config --quiet` para **ambas as composições**, sem exibir variáveis.

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
2. Referenciar as cópias verificadas dos arquivos Compose baseline, preservando env, TLS/CA, certificados privados, mounts e Image IDs; **remover ambos overlays candidatos GA-08 da resolução**. Recuperar os conjuntos 01–09 (WAF/Nginx) e 01–10 (PHP), com a ordem exata da GA-08.17C.
3. Operador valida os caminhos, checksums, identificadores exatos de imagem e `docker compose config --quiet` dos **dois conjuntos baseline distintos**; se faltar arquivo, variável, mount protegido, imagem ou segredo, **não forçar recriação**.
4. Em janela aprovada, e somente com imagens anteriores preservadas e proibição de rebuild/pull acordada, reconstruir **primeiro PHP a partir de 01–10**, depois **Nginx e WAF a partir de 01–09**, em comandos separados para respeitar os labels/overlays anteriores e dependências. Usar uma operação equivalente a `compose up` **sem dependências adicionais**, após revisão de flags compatíveis com Compose v5.5.1, sem `down -v`, `pull` nem `build`. Esta descrição é **sequência lógica, não comando pronto para execução**. Confirmar redes, mounts e dependências antes de cada ação.
5. Confirmar 3/3 healthy, HTTPS CA/TLS correto, HTTP 200/403, login/MFA/RBAC, SQL EP126, audit.log persistente/Wazuh e Twingate. Provar não só start dos contêineres mas recuperação funcional.
6. Se rollback por Compose falhar ou depender de secrets/mounts indisponíveis, interromper novas tentativas e acionar **restauração do snapshot institucional** com o operador; validar o estado restaurado e eventual consistência de dados externos.
7. Registrar ocorrência, causa, evidências, tempo de retorno e decisão de manter PA-02 aberto; não classificar rollback como PASS sem execução/retorno demonstrado.

**Estado em 02/11:** rollback Docker = PROPOSTO/NÃO EXECUTADO; rollback por snapshot = PENDENTE SUPORTE. Scripts deste PR continuam com gate fechado.

## 6. Pendências específicas para amanhã (03/11)

Solicitar snapshot integral **antes** da mudança, registrar ID/tempo/operador, confirmar discos e mounts protegidos e procedimento restaurável. Confirmar revisão da PR isolada e do plano de rollback; só então elaborar o `change control` executável. No dia da janela, qualquer drift entre `main`, EP125, Compose efetivo e candidato exige nova revisão antes de cutover.

**Status final:** GA-08.10–16 PASS em seus escopos; GA-08.17/17A/17C concluídas como validações de baseline, **G0 BLOQUEADO** e GA-08.18 **NÃO EXECUTADA**. O retorno por Compose continua **proposto, sem ensaio real**. O fato de o Docker encontrar a imagem exata e sua tag não garante disponibilidade futura nem recuperação de dados ou segredos após desastre.

### Registro adicional GA-08.17C — 02/11/2026

- WAF: `running=true`, `health=healthy`, `restartCount=0`, **9** Compose efetivos em ordem 01–09; **3** binds, um `ext4`, dois `INDETERMINADO`.
- Nginx: `running=true`, `health=healthy`, `restartCount=0`, **9** Compose efetivos em ordem 01–09; **0** binds.
- PHP: `running=true`, `health=healthy`, `restartCount=0`, **10** Compose efetivos em ordem 01–10; **5** binds, um `ext4`, quatro `INDETERMINADO`.
- 3/3 Image IDs disponíveis no Docker local; referências de imagem apontam ao respectivo ID em execução. Não inferir que a cópia privada contém imagem exportada.
- `INDETERMINADO` em `findmnt -T` não estabelece armazenamento externo: a GA-08.17A demonstrou `SEM_PERMISSAO` nos seis caminhos protegidos. Seus destinos são visíveis nos contêineres. Só suporte/operador autorizado pode atestar cobertura de snapshot e restaurabilidade.
- Evidência local privada: `~/ConectaEduca_Fase2_Evidencias/EP125/GA08/GA08_17A_MOUNTS_20261102T154250.txt` e resultado GA-08.17C fornecido em chat (não foi gerado log independente nessa etapa). Não anexar dados privados ao PR.
