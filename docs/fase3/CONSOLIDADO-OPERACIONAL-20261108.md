# ConectaEduca — consolidação operacional de 08/11/2026 (BRT)

**Responsável:** Andréa Kozicki · **Fase:** 3 / correções do Pentest A, preparação do Pentest B e Zero Trust · **Ambientes:** EP125 (DMZ), EP126 (Intranet), GitHub e Trello.

> Registro retrospectivo baseado em saídas efetivamente compartilhadas pela operadora em conversas de 08/11, resultados anexados à conversa e histórico dos PRs. Não é execução remota feita por esta documentação. Segredos, chaves Shamir, tokens, backups privados e logs brutos ficam fora do repositório.

## 1. Reconciliação repositório ↔ VMs — CE-RC01 a CE-RC08

- Coletas read-only CE-RC01..07: Git, alterações tracked/untracked (contagens), Compose/mounts, componentes e Connectors Twingate nativos systemd; conferência por blobs de quatro arquivos já existentes em campo. PR #221 (DRAFT) e relatório CE-RC01–08 na própria branch.
- PR #223 **MERGED**: promoveu somente deploy/dmz/compose.audit-persistent.yml da EP125, idêntico ao overlay observado no PHP; não foi novo deploy. PR #222 **MERGED**: promoveu somente sanitizar_ferret.py, validar_eventos_ferret.py e conectaeduca_dlp_rules.xml já alterados na EP126. Main resultante: 04f88d275064a005d0ffcd4f9372a371c28c32d5.
- CE-RC08 **executado** EP125 às 15:50 e EP126 às 15:54: checkouts reconciliados ao mesmo HEAD 04f88d27, 1 e 3 blobs ativos preservados, 8 e 56 bind mounts examinados respectivamente, backups locais verificados e worktrees tracked limpas. Sem restart de serviços pelo procedimento; untracked não apagados. PR #224 permanece DRAFT: o merge avançaria a main além do freeze.
- **Limite:** igualdade dos checkouts Git não prova equivalência binária do runtime. Posteriormente, a EP126 sofreu modificações tracked intencionais nos launchers PA-07; não repetir reset/pull/clean indiscriminadamente.

## 2. EP126 — OpenBao / PA-04

- CE-RC06R/07: recorrência de cofre sealed detectada; Shamir 2/3 confirmado. CE-OB01 às 16:09: unseal controlado concluído, initialized=true, sealed=false, sem compartilhar shares/tokens nem reiniciar. CE-OB02 às 16:13: running/healthy, failing streak 0, restarts 0.
- PR #228 DRAFT: proposta de KV v2 ce-app/ isolado, auth ce-approle/, política mínima read e role com TTL e SecretID. **Não implantado**, pois token administrativo válido indisponível/revogado; nenhum novo root token recuperado. PA-04 global permanece parcial.

## 3. EP126 — Ferret / PA-07

- PR #226 DRAFT: script de cutover com rollback best-effort, CI estática aprovada conforme histórico do PR. CE-GA06-CUT01 executado às 16:43: backup privado validado, Web Ferret 2.4.3+ce.pa07.v5 healthy, monitor versão v5 PASS e timer ativo. Rollback preparado, **não ensaiado**.
- PR #227 DRAFT: três launchers CLI Bash/Fish e bootstrap Fish alinhados ao override v5; CE-GA06-ALIGN01 aplicado às 17:05: três scripts rastreados atualizados no checkout EP126, backup privado verificado, Compose base preservado, sem recriar container. **Execução CLI real e teste de regressão HTTP403→INCONCLUSIVE ainda pendentes**. PA-07 global não homologado.

## 4. EP125 — PA-05 aplicação / PHP

- PR #229 DRAFT: correções SQL para não criar inscrições em oportunidades não publicadas e restringir update empresarial à propriedade da oportunidade; testes estáticos/CI não substituem regressão HTTP.
- CE-PA05-DEP01 verificou imagem/labels/10 arquivos Compose; CE-PA05-DEP02 **implantado às 17:40**: imagem PHP filha conectaeduca/php-fpm:pa05-10328ab6 healthy, três arquivos PHP verificados, auditoria/secrets preservados; WAF/Nginx não recriados.
- **Guarda crítica:** overlay persistente 11º em /home/andrea.kiew/.config/conectaeduca/pa05/compose.pa05-10328ab6.yml. Executar manutenção somente com todos os overlays ativos; usar dez pode regredir ao PHP anterior. Testes dinâmicos 404 rascunho, publicada e BOLA horizontal ainda pendentes. PA-05 não homologado globalmente.

## 5. EP125 — PA-02 WAF/Nginx / GA-08

- PR #230 DRAFT: CE-PA02-RW01 às 17:50 confirmou bind HTTP RW e limpeza, sem alterar PHP PA05/serviços; ajustes posteriores do driver para teste real de listeners /proc/net/tcp[6] e smoke HTTPS no rollback foram versionados, **não implantados**.
- RC01 backup local e IMP02 materialização OCI local comprovam integridade em recorte, **não** restauração institucional independente; ambos ficam no mesmo host. CE-PA02-DISK01 às 20:36: /dev/sda2 176 GB total, 33 GB usados, 134 GB livres (20%); inodes 5% usados; RC01 206 MB, IMP02 208 MB. Sem limpeza/prune.
- **G0 não aprovado, PA-02 runtime aberto, nenhum cutover GA-08 autorizado**. Próximo gate externo: snapshot consistente/restaurável da EP125 **posterior a 17:40** (PA05), com ID/hora/cobertura/retenção e procedimento de retorno. Caminhos não autorizados e teste negativo de isolamento permanecem pendentes.

## 6. EP125 — PA-06 auditoria persistente / logrotate

- Compose audit-persistent no PHP confirmado por CE-RC05 e versionado por PR #223; bind host /var/log/conectaeduca/php-audit associado ao container PHP.
- PR #225 DRAFT: CE-PA06-ROT01 às 16:23 abortou na verificação posterior por detecção de argumento sudo cmp -s (não houve sudo -s). CE-PA06-ROT02 às 16:27 comprovou política INSTALADA em /etc/logrotate.d/conectaeduca-php-audit, root:root 0644, SHA256 f0d9fe60ca866f9bee435665e67b7705dcb302bcf1daa18ce71928b0959e5e2d; log original UID:GID 82:82 modo 0600, systemd timer existente.
- Política laboratorial: daily, maxsize 16M, rotate 30, compress, delaycompress; **giro real, retenção institucional, revisão PII e ingestão após troca de inode ainda não comprovados**. Não repetir instalação nem forçar rotação.

## 7. EP126 — PA-06 regra Wazuh 80710: implantação e homologação funcional

### Sequência técnica, 08/11/2026

- WZ01–WZ04 e WZ05 V3/V4: Manager 4.14.7 pinado pela imagem sha256:8665c9807a5765253c79e4b072a1b7462c997bd69be949118a8d82ce44dd33e9; três serviços healthy. V4 às 21:46 passou no preflight e reproduziu falha da regra original (80710 level 10 para ativação 0→256, desativação 256→0 e sem transição 256→256). PR #231 DRAFT contém instalador anterior com ajustes de guardas; **não presumir que ele seja o arquivo V6 usado pela operadora**.
- WZ05 primeira implantação às 21:59: override inserido, mas validação inconclusiva do decoder; ABORT com remoção de override e Manager saudável, sem restart necessário. D1 às 22:04 confirmou decoder auditd e três falso/positivo baseline; D2 às 22:08 comprovou que fases do wazuh-logtest aparecem em stderr (stdout 2 bytes), parser PASS nos três; D3 às 22:11 confirmou volume Docker persistente em /var/ossec/etc e ausência de override após rollback.
- WZ05 V5 ensaio reversível às 22:17: override candidato SHA256 4da3e4fe32a151f058c6d646340e8fc8a410e7bcfd41124207830cfc7e691ecf; analysisd -t RC=0; ativação 80710 level 10 alerta, desativação/sem transição 80700 level 0 sem alerta; limpeza obrigatória, baseline restaurado e original preservado.
- WZ05 V6 APPLY às 22:22: **IMPLANTACAO_PASS**; mesmo SHA256 de override; arquivo /var/ossec/etc/rules/ce_pa06_wz05_80710.xml persistente; Manager reiniciado uma vez e voltou healthy, três casos PASS antes e depois. Ruleset original SHA256 026f9aeab3c170b9154ec1bb306688d17d3059a97147d6472715fe66b28fc39f preservado.
- WZ06 às 22:31: Manager/Indexer/Dashboard running/healthy, Filebeat detectado, 6 alertas pós-V6 (5 auditd, 1 ANOM_PROMISCUOUS/80710), 0 alertas 80710 divergentes na amostra do arquivo atual; auditd e agent host ativos. Dashboard HTTPS HTTP 302 com TLS não validado no host (CA não confiada no cliente da auditoria). Zero eventos artificiais gerados pelo WZ06.
- WZ07 às 22:35: alerta UTC 2026-11-09T01:23:21.100Z (08/11 22:23:21 BRT) de agent 002 ep126-pucpr, location /var/log/audit/audit.log, dev vethc66e75b, id 50911, audit.prom=256 old_prom=0; sem assinatura do evento sintético conhecido, mas **sem comparação independente com o audit.log original**. full_log no Dashboard identifica comm=dockerd, exe=/usr/bin/dockerd, syscall sendto/Netlink; relação causal exata com restart não comprovada.
- Dashboard Threat Hunting / Events: busca rule.id=80710 mostrou **3 hits**, 2 anteriores (16:43:59, 16:44:01 BRT) e 1 pós-V6 (22:23:21 BRT). Registro pós-V6 foi localizado no índice wazuh-alerts-4.x-2026.11.09, _id ZdnnvaEBfnUr5HbyPIzE, level 10 e campos da transição corretos. **Indexer → Dashboard comprovado para esse alerta específico**; não confundir duas ocorrências históricas com falsos positivos sem examinar campos.
- WZ08 às 22:41: erro isolado do boot do Manager ao tentar cp /var/ossec/data_tmp/permanent/var/ossec/var/multigroups/. → /var/ossec/var/multigroups. Origem temporária ausente no instante do diagnóstico, destino presente e volume RW, Manager healthy. Causa histórica exata não confirmada; sem impacto funcional observado, monitorar se reaparecer.

### Aceite e limites PA-06

**Regra 80710 na EP126 = CORREÇÃO IMPLANTADA / HOMOLOGAÇÃO FUNCIONAL no escopo testado.** A detecção positiva foi observada até o Dashboard; ausência de falsos positivos demonstrada por três testes sintéticos no logtest pré e pós-restart. Não afirmar prova negativa E2E para eventos 256→0/256→256, nem proveniência independente em audit.log. PA-06 **global** ainda possui pendências na EP125 (rotação/PII) e em outras integrações. O erro multigroups é incidente separado não bloqueante no recorte.

## 8. Zero Trust, segurança e pendências transversais

- Connectors Twingate nativos systemd e estado online foram constatados na reconciliação; dados de RBAC efetivo com identidade limitada, alias DNS wazuh.dashboard via cliente e isolamento negativo continuam sem aceite E2E. Não declarar Zero Trust completo.
- pfSense LAN33/LAN49 permitiu conectividade necessária em testes prévios; evidência do bloqueio de caminhos não autorizados ainda aberta. TLS EP126→EP125 apresentou verify code 20 anteriormente, sem reparo comprovado no recorte de 08/11.
- Grupo A global e liberação formal do pentest B dependem de critérios anteriores; progresso pontual em PAs não substitui aceite global, snapshot institucional comprovado nem reteste autorizado.
- Prazo acadêmico: apresentação em 17/11/2026. Congelar novas mudanças não essenciais; preservar hashes, evidências sanitizadas e registro das lacunas.

## 9. Referências e custódia

- Reconciliação: PRs #221, #222 MERGED, #223 MERGED, #224 DRAFT.
- Ferret: PRs #226 e #227 DRAFT; OpenBao: #228 DRAFT; PHP PA-05: #229 DRAFT; PA-02: #230 DRAFT; auditoria EP125: #225 DRAFT; Wazuh 80710: #231 DRAFT (script GitHub distinto da execução V6 local).
- Evidências de WZ05 V5/V6, WZ06–WZ08, JSON e print do Dashboard foram compartilhadas na conversa e devem permanecer arquivadas com controle de acesso. Esta consolidação **não** as apresenta como arquivos já anexados ao repositório. Não enviar backups, shares Shamir, token, .env ou logs brutos para GitHub/Trello.

**Classificação deste arquivo:** documentação/coordenação; sem alteração de runtime ou CI por si só. Manter esta PR documental DRAFT até revisão e sem merge automático.
