# Auditoria histórica de PRs fechados — 29/09/2026

## Objetivo

Registrar o pente-fino dos PRs fechados do ConectaEduca antes do freeze acadêmico,
com foco em encontrar achados Codex não revalidados no HEAD final, correções
superseded, checks ausentes e regressões que ainda sobrevivam na `main`.

Esta auditoria não substitui os gates live/host. Ela cobre rastreabilidade e
estado canônico de repositório.

## Corte de confiança

O PR #91 (`chore: adiciona pente fino estático do repositório`) é o corte
histórico principal para mudanças anteriores. As reconciliações #97, #100 e
#101 estão na ancestralidade do HEAD final do #91. A revisão Codex final do #91
foi bloqueada por quota, mas os três últimos findings foram verificados contra a
`main` atual:

- bootstrap Bacula contém cleanup de falha com `stop/disable/mask` antes da
  remoção do `policy-rc.d`;
- smoke do handoff executa `sha256sum -c SHA256SUMS`;
- ausência de Fish é `SKIP` na validação sintática opcional, não `FAIL`.

## PRs recentes com Codex no HEAD final

Confirmados com revisão Codex explícita no mesmo HEAD mergeado e sem finding
aberto conhecido:

- #143, #142, #141, #140, #139, #138;
- #135, #134, #133;
- #89, #87, #86, #84, #83, #82, #81, #80, #79, #78, #77;
- #76, #75, #74, #67, #66, #64, #55.

## PRs com review final ausente, mas finding corrigido/superseded

### #132 — pfSense -> Wazuh provenance

O Codex pediu que marker e proveniência pfSense pertencessem ao mesmo evento.
A implementação atual usa `marker_match && pfsense_hint` no mesmo registro e
possui self-test contra marker sem proveniência. Sem bug ativo conhecido.

### #131 — Suricata APPLY transacional

O finding pedia fail-fast dentro da transação e modo executável. O script atual
usa subshell `set -Eeuo pipefail`, captura `apply_rc`, faz rollback
controlado e o arquivo está `100755`.

### #130 — hash canônico da policy Wazuh DMZ

O README canônico atual aponta para o SHA da policy vigente, não para o hash
histórico stale.

### #129 — PgBouncer socket-only

Os checks atuais possuem probe negativo de TCP/6432 tanto no readiness quanto
no runtime pós-corte.

### #127 — formula injection na triagem Lynis

O tooling atual aplica `spreadsheet_safe()` a células exportadas.

### #126 — Suricata/WAZ-02 pós-reboot

Os pontos foram absorvidos pelos PRs #130/#131. O runbook canônico distingue a
política antiga baseada em `suricatasc` da política persistente atual e WAZ-02
está reconciliado no backlog.

### #122/#120 — CRED-01/PgBouncer

O tooling atual exige container healthy, socket Unix real, ausência do listener
TCP, conjunto exato de componentes obrigatórios e validação do
`SHA256SUMS-RAW`.

### #121/#119 — AUDIT-01

O consolidator atual normaliza os campos editáveis antes da agregação e valida
a cobertura do manifesto RAW. O checkpoint Semgrep registra HEAD/origin e
trabalha com proveniência do worktree.

### #118 — principal zero-sudo

Foi superseded pelo contrato root-owned
`/etc/conectaeduca/pentest-principal.uid`; o runtime compara o EUID ao UID
materializado.

### #117 — BAC-04 Schedule

A decisão atual separa BAC-04 (política + E2E) de BAC-05 (recorrência). O
laboratório permanece explicitamente em execução manual, sem Schedule
inventado apenas para evidência.

### #111/#112/#113/#116 e documentação adjacente

Não tiveram revisão Codex original, mas foram superseded pela linha
#129/#134/#135/#139/#140/#142/#143, que endureceu e reconciliou o pentest
zero-sudo e o freeze.

### #102/#103/#105 — GUI/OpenBao/Bacularis

Achados relevantes estão corrigidos na fonte atual:

- Bacularis usa `$uri` normalizada no firewall de mutação;
- entrypoint supervisiona Nginx e PHP-FPM;
- identidade OpenBao `teste` recebe policy mínima sem `default`;
- o campo `lockout_counter_reset` é o payload usado pelo
  `user_lockout_config` da API; não foi tratado como bug após rechecagem.

### #73/#72/#71/#70/#69/#68 — Bacula/handoff

Foram superseded pela linha posterior de hardening/handoff. A fonte atual:

- mantém `no-new-privileges:true` na composição canônica;
- inclui `FOWNER` no bootstrap Storage onde o chmod posterior ao chown exige;
- inclui o materializador do segredo Catalog no handoff;
- conecta Director ao `bacula-uplink`.

### #63/#62/#65

- `getfacl` é exigido somente no ramo ACL-backed do validador Wazuh;
- o setting que motivou o finding de auto-init do security index não aparece na
  composição canônica atual;
- inconsistências documentais de Ferret/checkout foram absorvidas por
  reconciliações posteriores e pelo freeze atual.

## PRs antigos sem Codex original (#1–#56)

Grande parte dos PRs iniciais predatam o uso regular do Codex no repositório e
não possuem review automático original. Eles não foram tratados como
"automaticamente corretos": o estado atual foi confrontado com o corte global
#91 e, para findings antigos conhecidos, com a fonte canônica vigente.

Verificações adicionais desta rodada:

- #53: os `.runtime` de Bacula, Ferret, OpenBao e Wazuh estão explicitamente
  excluídos do FIM da policy interna; os arquivos de evento sanitizado continuam
  coletados via `localfile`, sem reintroduzir hashing FIM dos runtimes;
- #54: a arquitetura canônica permanece WAF/TLS na frente do Nginx HTTP interno;
  `app-https.conf` existe como artefato de overlay separado, mas não é tratado
  nesta auditoria como terminação TLS canônica da aplicação;
- #42/#41: a linha posterior de hardening/reprodutibilidade do Catalog e
  PgBouncer substituiu as primeiras versões, culminando nos overlays e
  materializadores atuais, posteriormente varridos pelo #91;
- #38/#39: a reprodutibilidade do Wazuh Dashboard/ACL foi tratada em PRs
  posteriores e entrou no tooling/handoff revisado;
- #44/#45: os controles Wazuh foram incorporados à composição canônica e ao
  inventário posterior, não permanecendo como overlay órfão;
- #46: a integração Ferret -> Wazuh e a retenção foram reconciliadas em
  versões posteriores do pipeline.

Assim, ausência de Codex nesses PRs antigos é registrada como lacuna histórica
de review, não como finding ativo por si só.

## Finding histórico que permaneceu ativo

### #59 — bridge OpenBao -> Wazuh após EOF limpo

**Status encontrado:** ATIVO na revisão de 29/09/2026.

O serviço usa `Restart=on-failure`, porém
`sanitizar_openbao_audit.py --follow` aceitava `docker logs --follow`
encerrar com `rc=0`. Após uma substituição normal do container OpenBao, a unit
podia terminar com sucesso e não reiniciar, interrompendo a auditoria.

**Correção:** PR #146 — `fix: reinicia bridge OpenBao após EOF limpo`.

O helper agora converte o EOF limpo inesperado em saída de falha para acionar
`Restart=on-failure`, preservando o cleanup local.

## Outros findings Ferret/OpenBao antigos

Os findings de #60/#61 foram confrontados com a implementação vigente:

- falha de sanitização do Ferret retorna erro antes de atualizar ledger;
- raw confirmado é rastreado também por `processed-runs.tsv`;
- retenção de raw consulta o run ledger, evitando usar apenas hash de conteúdo;
- installer do bridge OpenBao reinicia explicitamente a unit após substituí-la.

O caso de EOF limpo do bridge foi a exceção real e originou #146.

## Dependabot, duplicados e PRs fechados sem merge

PRs Dependabot com gates verdes são tratados como mudança de dependência, não
como dívida de review manual equivalente a runtime security.

PRs fechados sem merge por reconciliação/supersedência — incluindo a árvore
#90/#92/#93/#94/#95/#98/#99, #114/#115/#136 e duplicados equivalentes — não
são fonte canônica. A validação é feita sobre o PR reconciliado/mergeado que
absorveu seu conteúdo.

## Estado do freeze após #145

O PR #145 corrigiu o SHA autorreferente do pré-freeze e foi mergeado em
`88f7dd0c61a643bce9441f181d22f3dd2ab3494c`.

O contrato atual exige:

- fixar `<FREEZE_COMMIT>`;
- executar APPSEC Snyk Final Evidence com
  `expected_sha=<FREEZE_COMMIT>`;
- artifact `appsec-snyk-final-<FREEZE_COMMIT>`;
- TXT contendo `EXPECTED_SHA=<FREEZE_COMMIT>`;
- repetir o scan se a `main` avançar após a evidência.

## Conclusão

A revisão histórica encontrou várias lacunas de carimbo/re-review do Codex,
mas a maioria já estava corrigida ou superseded na fonte canônica atual.

O único finding antigo confirmado como ainda ativo nesta rodada foi o #59,
tratado no PR #146.

Enquanto #146 não for mergeado, a auditoria deve permanecer
`REPO_GATE`. Depois do merge, qualquer novo commit altera a ponta da
`main`, portanto a evidência APPSEC final deve ser executada novamente sobre
o novo `<FREEZE_COMMIT>`.
