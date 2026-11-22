# ConectaEduca — registro histórico operacional de 08/11/2026 (BRT)

> **Registro retrospectivo de 08/11, não baseline de novembro nem comprovação de implantação atual.** Os resultados abaixo vieram de transcrições e evidências de campo da data; nesta rodada, não houve acesso a VMs. A afirmação histórica de execução PA-05/DEP02 continua `PENDENTE_DE_CONCILIACAO` com as provas primárias e o procedimento versionado na [#229](https://github.com/andrea-kozicki/conectaeduca/pull/229)/[#251](https://github.com/andrea-kozicki/conectaeduca/pull/251). A matriz [pré-VM](https://github.com/andrea-kozicki/conectaeduca/blob/main/docs/operacao/CE-PREVM-GATES-20261118.md) mantém 12 gates `PENDING_VM`. Antes de publicar, aplicar o [guia de privacidade](https://github.com/andrea-kozicki/conectaeduca/blob/main/docs/portfolio/PRIVACIDADE-E-PUBLICACAO.md) e o [gate acadêmico](https://github.com/andrea-kozicki/conectaeduca/blob/main/docs/release/GATE-PREPUBLICACAO-ACADEMICA-2026-11-18.md). A edição da branch não apaga commits históricos.

**Responsável:** Andréa Kozicki · **Fase:** 3 / correções do Pentest A, preparação do Pentest B e Zero Trust · **Ambientes:** EP125 (DMZ), EP126 (Intranet), GitHub e Trello.

> Registro retrospectivo baseado em saídas efetivamente compartilhadas pela operadora em conversas de 08/11, resultados anexados à conversa e histórico dos PRs. Não é execução remota feita por esta documentação. Segredos, chaves Shamir, tokens, backups privados e logs brutos ficam fora do repositório.

## 1. Reconciliação repositório ↔ VMs — CE-RC01 a CE-RC08

- Coletas read-only CE-RC01..07: Git, alterações tracked/untracked (contagens), Compose/mounts, componentes e Connectors Twingate nativos systemd; conferência por blobs de quatro arquivos já existentes em campo. PR #221 (DRAFT) e relatório CE-RC01–08 na própria branch.
- PR #223 **MERGED**: promoveu somente deploy/dmz/compose.audit-persistent.yml da EP125, idêntico ao overlay observado no PHP; não foi novo deploy. PR #222 **MERGED**: promoveu somente sanitizar_ferret.py, validar_eventos_ferret.py e conectaeduca_dlp_rules.xml já alterados na EP126. Main resultante: 04f88d275064a005d0ffcd4f9372a371c28c32d5.
- CE-RC08 **relatado em 08/11**: EP125 e EP126 apresentaram o mesmo HEAD histórico após conciliação controlada, com arquivos locais preservados e verificação de mounts e backups no recorte. Não houve reinício de serviços nesse procedimento; arquivos não rastreados não foram removidos. Essas condições **não caracterizam o checkout ou o runtime atuais**; a #224 continua DRAFT.
- **Limite:** igualdade dos checkouts Git não prova equivalência binária do runtime. Posteriormente, a EP126 sofreu modificações tracked intencionais nos launchers PA-07; não repetir reset/pull/clean indiscriminadamente.

## 2. EP126 — OpenBao / PA-04

- CE-RC06R/07: recorrência de cofre sealed detectada; Shamir 2/3 confirmado. CE-OB01 às 16:09: unseal controlado concluído, initialized=true, sealed=false, sem compartilhar shares/tokens nem reiniciar. CE-OB02 às 16:13: running/healthy, failing streak 0, restarts 0.
- PR #228 DRAFT: proposta de KV v2 ce-app/ isolado, auth ce-approle/, política mínima read e role com TTL e SecretID. **Não implantado**, pois token administrativo válido indisponível/revogado; nenhum novo root token recuperado. PA-04 global permanece parcial.

## 3. EP126 — Ferret / PA-07

- PR #226 DRAFT: script de cutover com rollback best-effort, CI estática aprovada conforme histórico do PR. CE-GA06-CUT01 executado às 16:43: backup privado validado, Web Ferret 2.4.3+ce.pa07.v5 healthy, monitor versão v5 PASS e timer ativo. Rollback preparado, **não ensaiado**.
- PR #227 DRAFT: três launchers CLI Bash/Fish e bootstrap Fish alinhados ao override v5; CE-GA06-ALIGN01 aplicado às 17:05: três scripts rastreados atualizados no checkout EP126, backup privado verificado, Compose base preservado, sem recriar container. **Execução CLI real e teste de regressão HTTP403→INCONCLUSIVE ainda pendentes**. PA-07 global não homologado.

## 4. EP125 — PA-05 aplicação / PHP

- **Estado em 08/11:** PR #229 então DRAFT, com correções SQL para não criar inscrições em oportunidades não publicadas e restringir update empresarial à propriedade; testes estáticos/CI não substituem regressão HTTP. **Atualização documental de 18/11:** #229 foi integrada à `main` após a idempotência da #251 e testes MariaDB; essa integração de fonte **não prova implantação atual na EP125**.
- **Relato histórico sujeito à conciliação:** a consolidação de 08/11 descreve preflight PA-05/DEP01 e possível aplicação PA-05/DEP02, com imagem PHP derivada então saudável, sem recriação declarada de WAF/Nginx. O procedimento versionado na #229 **não contém confirmação operacional primária** dessa implantação, e o código precedia a correção de idempotência da #251. O relatório final Pentest B v41, de 16/11, **não fornece uma confirmação independente de DEP02**. Classificação: `PENDENTE_DE_CONCILIACAO`, sem afirmar deploy, rollback, paridade com a `main` ou correção integral de PA-05.
- **Guarda histórica, não executável:** a narrativa de 08/11 menciona um overlay PHP adicional no diretório pessoal do operador. Não há conferência atual de sua presença/uso. O instalador e runbook antigos foram isolados como [histórico — não executar](https://github.com/andrea-kozicki/conectaeduca/blob/main/docs/fase3/PA05-DEP02-HISTORICO-NAO-EXECUTAR.md). Os testes posteriores de sessão e CSRF do relatório v41 **não equivalem a validação BOLA horizontal**; o acesso entre objetos de usuários diferentes permaneceu sem comprovação.

## 5. EP125 — PA-02 WAF/Nginx / GA-08

- PR #230 DRAFT: CE-PA02-RW01 às 17:50 confirmou bind HTTP RW e limpeza, sem alterar PHP PA05/serviços; ajustes posteriores do driver para teste real de listeners /proc/net/tcp[6] e smoke HTTPS no rollback foram versionados, **não implantados**.
- Os registros RC01/IMP02 mencionam cópias e verificação local de integridade da imagem. Isso **não equivale a backup institucional, restauração independente nem snapshot atual**. Valores detalhados de dispositivo, armazenamento e artefatos permanecem no acervo privado da execução.
- **Em 08/11, G0 não estava aprovado e PA-02 permanecia em investigação.** A existência de observações posteriores no relatório v41 não homologa todo o isolamento: confirmar recorte/origem, teste negativo do backend e logs do WAF antes de qualquer aceite. Para futuras mudanças, exigir snapshot e rollback **atuais e autorizados**, sem reutilizar IDs ou horários históricos.

## 6. EP125 — PA-06 auditoria persistente / logrotate

- Compose audit-persistent no PHP confirmado por CE-RC05 e versionado por PR #223; bind host /var/log/conectaeduca/php-audit associado ao container PHP.
- PR #225 DRAFT: o procedimento CE-PA06-ROT01 foi interrompido; CE-PA06-ROT02 relatou política de rotação instalada, com arquivo e permissões conferidos em 08/11. Caminhos completos, hash exato do arquivo e metadados detalhados estão sob custódia privada e não são necessários a este resumo.
- Política laboratorial: daily, maxsize 16M, rotate 30, compress, delaycompress; **giro real, retenção institucional, revisão PII e ingestão após troca de inode ainda não comprovados**. Não repetir instalação nem forçar rotação.

## 7. EP126 — PA-06 regra Wazuh 80710: implantação e homologação funcional

### Sequência técnica, 08/11/2026

- WZ01–WZ04 e WZ05 V3/V4: Manager 4.14.7 identificado na evidência privada, três serviços saudáveis naquele corte. O preflight V4 reproduziu uma regra 80710 que também alertava em transições não pretendidas. A #231 DRAFT contém instalador anterior: **não presumir que seja o override V6 aplicado localmente**.
- WZ05 primeira implantação às 21:59: override inserido, mas validação inconclusiva do decoder; ABORT com remoção de override e Manager saudável, sem restart necessário. D1 às 22:04 confirmou decoder auditd e três falso/positivo baseline; D2 às 22:08 comprovou que fases do wazuh-logtest aparecem em stderr (stdout 2 bytes), parser PASS nos três; D3 às 22:11 confirmou volume Docker persistente em /var/ossec/etc e ausência de override após rollback.
- WZ05 V5, ensaio reversível: candidato de override identificado por SHA-256 na custódia original; validação sintática passou. Nos testes de `logtest`, a transição de ativação disparou 80710, enquanto a desativação e ausência de transição permaneceram sem alerta de nível 10. O baseline foi restaurado após o ensaio.
- WZ05 V6, segundo o registro de **08/11**: override persistente relatado como aplicado; Manager reiniciado uma vez e saudável; três casos sintéticos passaram antes e depois. A identidade exata dos arquivos permanece na evidência privada. **Não afirmar que a mesma regra continua carregada na VM hoje**.
- WZ06 às 22:31: Manager/Indexer/Dashboard running/healthy, Filebeat detectado, 6 alertas pós-V6 (5 auditd, 1 ANOM_PROMISCUOUS/80710), 0 alertas 80710 divergentes na amostra do arquivo atual; auditd e agent host ativos. Dashboard HTTPS HTTP 302 com TLS não validado no host (CA não confiada no cliente da auditoria). Zero eventos artificiais gerados pelo WZ06.
- WZ07, no recorte: um alerta pós-V6 da EP126 exibiu campos compatíveis com transição de modo promíscuo. A causa específica e a proveniência independente no audit.log **não foram estabelecidas**; detalhes de timestamp, índice, caminho e processo ficam sob custódia privada.
- O Dashboard exibiu três ocorrências para a regra 80710, sendo uma posterior ao V6. Para essa ocorrência, a presença no Indexer e no Dashboard foi **observada na data**, sem ampliar o resultado a todas as regras, alertas ou janelas futuras.
- WZ08: foi registrado um erro isolado de cópia de diretório temporário durante a inicialização do Manager. O serviço foi observado saudável; não se concluiu causa raiz ou impacto funcional. Os caminhos internos do contêiner ficam nos registros privados.

### Aceite e limites PA-06

**Regra 80710 na EP126 = CORREÇÃO IMPLANTADA / HOMOLOGAÇÃO FUNCIONAL no escopo testado.** A detecção positiva foi observada até o Dashboard; ausência de falsos positivos demonstrada por três testes sintéticos no logtest pré e pós-restart. Não afirmar prova negativa E2E para eventos 256→0/256→256, nem proveniência independente em audit.log. PA-06 **global** ainda possui pendências na EP125 (rotação/PII) e em outras integrações. O erro multigroups é incidente separado não bloqueante no recorte.

## 8. Zero Trust, segurança e pendências transversais

- Connectors Twingate nativos systemd e estado online foram constatados na reconciliação; dados de RBAC efetivo com identidade limitada, alias DNS wazuh.dashboard via cliente e isolamento negativo continuam sem aceite E2E. Não declarar Zero Trust completo.
- pfSense LAN33/LAN49 permitiu conectividade necessária em testes prévios; evidência do bloqueio de caminhos não autorizados ainda aberta. TLS EP126→EP125 apresentou verify code 20 anteriormente, sem reparo comprovado no recorte de 08/11.
- Grupo A global e liberação formal do pentest B dependem de critérios anteriores; progresso pontual em PAs não substitui aceite global, snapshot institucional comprovado nem reteste autorizado.
- Prazo acadêmico: apresentação em 17/11/2026. Congelar novas mudanças não essenciais; preservar hashes, evidências sanitizadas e registro das lacunas.

## 9. Confronto editorial com o relatório final Pentest B v41 (16/11)

- **Fontes e período:** este consolidado é o retrato de 08/11. O relatório acadêmico final v41, com corte de evidências até 15/11, foi consultado separadamente e **não é anexado a esta PR**; a leitura do relatório não substitui a verificação de suas evidências originais.
- **PA-05:** a v41 descreve controles de sessão e CSRF em testes posteriores, mas dois envios legítimos de inscrição foram bloqueados pelo WAF (CE-F06) e não houve comprovação de autorização horizontal entre contas. Não há no texto da v41 confirmação independente de `CE-PA05-DEP02`.
- **Segmentação e WAF:** a v41 registrou alcance SSH da rede interna à DMZ (CE-F01) e o bloqueio de inscrições (CE-F06). Essas observações posteriores não permitem declarar que o G0/GA-08 de 08/11 foi aprovado, nem atribuir a divergência a uma regra específica do pfSense sem correlação.
- **Wazuh/Twingate:** o alerta 80710 observado em 08/11 é evidência datada; na v41 a cadeia E2E atual do Wazuh permaneceu sem novo reteste completo, e houve intermitência no acesso remoto ao painel (CE-F05), além de problema de confiança de certificado no cliente (CE-L05). Não extrapolar a homologação da regra V6 para o ambiente inteiro.
- **Demais controles:** operações de OpenBao, Ferret, Bacula e scripts locais continuam dependentes do escopo específico de cada prova. A classificação qualitativa de risco da v41 é **alta para o recorte testado**, não um laudo de implantação nem autorização para intervenção.
- **Gates:** manter `CE-DOC-ZT=PENDING_DOC_REVIEW`, os 12 gates `PENDING_VM` e os seis gates de publicação acadêmica pendentes. Nenhuma alteração do estado operacional ocorreu com esta revisão editorial.

## 10. Referências e custódia

- Reconciliação: PRs #221, #222 MERGED, #223 MERGED, #224 DRAFT.
- **Situação histórica em 08/11:** Ferret #226/#227, OpenBao #228, PHP PA-05 #229, PA-02 #230, auditoria #225 e Wazuh 80710 #231 constavam DRAFT (o script da PR #231 não era necessariamente o V6 aplicado localmente). **Em 18/11, a #229 passou à `main` após #251/#255; as demais referências deste registro precisam ser lidas na data original.**
- Evidências de WZ05 V5/V6, WZ06–WZ08, JSON e print do Dashboard foram compartilhadas na conversa e devem permanecer arquivadas com controle de acesso. Esta consolidação **não** as apresenta como arquivos já anexados ao repositório. Não enviar backups, shares Shamir, token, .env ou logs brutos para GitHub/Trello.

**Classificação deste arquivo:** documento retrospectivo/coordenação; sem alteração de runtime ou CI por si só. **Não declarar `PA05_DEPLOY_PASS` nem reaproveitar scripts antigos.** Manter esta PR documental em DRAFT até conciliar a alegação de deploy com evidências primárias e passar pelo gate de privacidade, sem merge automático.
