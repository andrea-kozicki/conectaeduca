# Pente fino — Fase 2: handoff e reprodutibilidade — 18/09/2026

## Objetivo

Verificar se os bundles DMZ/Interna conseguem transportar e reconstruir o que a
documentação operacional promete sem depender do checkout de desenvolvimento,
de caminhos locais da autora ou de atalhos de laboratório.

Esta fase é **repo-only**. Nenhum estado das EP125/EP126 é inferido pelas
alterações abaixo.

## Achados

### 1. Handoff interno não era autossuficiente

A documentação final previa uma etapa pós-Pentest A com Twingate e operação de
Ferret/Wazuh, mas o bundle não transportava todas as dependências executáveis.

Foram incluídos, sem segredos:

- Twingate Compose, materialização efêmera, ativação e checkpoints;
- preparador Wazuh de VM + biblioteca comum;
- bridge OpenBao → Wazuh e sanitizador;
- operação/healthcheck Ferret e pipeline DLP;
- checkpoint de portabilidade target-specific.

### 2. Scripts finais pressupunham checkout Git ou caminho local

Um `git archive` não contém `.git`. Alguns scripts incluídos exigiam
`git rev-parse --show-toplevel`, `/srv/www/htdocs/conectaeduca` ou
`/opt/conectaeduca`.

O contrato passou a ser:

1. usar `PROJECT_ROOT` quando definido;
2. caso contrário, derivar a raiz pelo caminho do próprio script;
3. fora de Git, usar `RELEASE-METADATA.txt` para comprovar o freeze quando a
   verificação de origem é necessária.

O verificador do bundle reprova dependências residuais dessas raízes fixas.

### 3. Rotas antigas podiam reconstruir arquitetura errada

`materializar_bacula_core.py` ainda gerava `filedaemon-lab`, jobs sintéticos
e Catalog direto em `catalog:5432`. Isso contradiz o runtime validado atual:

`Director → Unix socket PgBouncer:6432 → TLS verify-full → PostgreSQL`.

O renderer de laboratório e seu bootstrap de segredos foram retirados do handoff
final. `preparar_bacula_director_db.fish` preserva a senha operacional, mas
normaliza host/porta para `/run/pgbouncer:6432`.

A materialização completa do volume canônico do Director ainda não possui
renderer final suficientemente comprovado no Git. Em vez de inventar um, a
metadata registra:

`bacula_final_runtime_materialization=host_gate`

### 4. Integração SMTP cross-VM não pertence ao bundle interno

Scripts OpenBao/SMTP presentes no handoff interno escreviam em
`deploy/dmz/.runtime`, embora `deploy/dmz` seja corretamente excluído do
pacote interno. Essa integração continua não habilitada na arquitetura final e
foi retirada do handoff.

### 5. Checkpoints de origem estavam misturados com ferramentas de VM

Checkpoints que exigem simultaneamente as duas zonas, `.git`,
`compose.lab.yml` ou volumes `fd-lab-*` permanecem no repositório/CI, mas não
no pacote operacional.

## Gates

### 2A — Handoff autossuficiente

Critério:

- artefatos citados pela operação existem no bundle;
- nenhuma dependência obrigatória de checkout Git/caminho local;
- Twingate entra inativo e sem tokens;
- scripts futuros/lab não entram.

### 2B — Fonte de verdade — CONCLUÍDA NO REPO

Validada no HEAD `96e1736f28a9db98be33dbd8899a695a53b3e2dc`
pelo Repository Static Integrity run `35366267797`.

Critérios comprovados:

- handoff não contém renderer Bacula de laboratório;
- `preparar_bacula_director_db.fish` fixa
  `BACULA_DB_HOST=/run/pgbouncer` e `BACULA_DB_PORT=6432`;
- metadata declara o volume externo `director-config` como fonte live;
- baseline host é explicitamente `rollback_only`;
- materialização completa do volume live continua `host_gate`;
- policy/runbook/scripts OpenBao→SMTP cross-VM ficam fora do bundle final e o
  status é `not_enabled`;
- artefatos legados preservados no repositório foram marcados como
  `LAB-ONLY`/`FUTURE/LAB-ONLY`;
- geração e verificação dos handoffs DMZ/Interna passaram no CI.

O fechamento desta mini-fase é **repo-only**. Ele não promove nem reconcilia o
volume `conectaeduca-bacula-director-config` na EP126.

### 2C — Smoke test do bundle — CONCLUÍDA NO REPO

Validada pelo Repository Static Integrity run `35366553998`.

O CI:

1. gerou os handoffs DMZ e Interna a partir do commit;
2. validou SHA-256, denylist e inventário;
3. extraiu cada tarball em diretório limpo;
4. removeu `PROJECT_ROOT` do ambiente;
5. executou `scripts/release/smoke_handoff.sh` de dentro de cada bundle.

Resultados observados:

- `HANDOFF_SMOKE=PASS`, `TARGET=dmz`;
- `HANDOFF_SMOKE=PASS`, `TARGET=interna`;
- ambos comprovaram execução fora de checkout Git;
- o bundle interno confirmou PgBouncer socket/6432, ausência de Bacula lab,
  exclusão SMTP cross-VM, superfície Twingate e self-test Wazuh ACL;
- nenhum smoke precisou de Docker, rede, systemd, sudo ou segredo.

O smoke continua sendo um gate de **portabilidade estrutural**, não um substituto
para validação live das EP125/EP126.

## Pendência que continua exigindo host

A promoção/reconciliação completa do runtime Bacula canônico
(`director-config`, TLS, PgBouncer config/socket e configuração final do
Director) continua dependente da EP126 e das evidências live. O código desta
fase não marca esse gate como concluído.

### 2D — Fechamento da Fase 2 — CONCLUÍDA NO REPO

A revisão final do diff identificou um resíduo de dependência no pipeline Ferret:
o handoff transportava o processador Bash documentado
`scripts/dlp/processar_inbox_ferret.sh`, mas não levava o bootstrap Bash que ele
executa, enquanto helpers Fish históricos também eram incluídos.

O fechamento consolidou uma única cadeia operacional no bundle:

`preparar_ferret.sh → processar_inbox_ferret.sh → sanitizar_ferret.py`

Também entram `validar_eventos_ferret.py` e `limpar_retencao_ferret.sh`.
Os helpers Ferret Fish permanecem no repositório de desenvolvimento, mas não
fazem parte do handoff final.

O smoke/verificador agora exigem explicitamente essa cadeia Bash/Python e
reprovam a reintrodução dos helpers Fish no bundle.

A revisão de acabamento também removeu do diff quatro alterações Fish que haviam
sido feitas apenas para a hipótese anterior de incluí-los no handoff. O diff
empilhado final da Fase 2 ficou em 32 arquivos com finalidade identificável.

## Estado final da Fase 2

- 2A — handoff autossuficiente: **CONCLUÍDA NO REPO**;
- 2B — fonte de verdade: **CONCLUÍDA NO REPO**;
- 2C — smoke offline do bundle: **CONCLUÍDA NO REPO**;
- 2D — revisão/consolidação: **CONCLUÍDA NO REPO**.

O PR #92 permanece draft e empilhado sobre o #91. O branch da Fase 1 avançou
dois commits de CI depois da criação da Fase 2; a reconciliação de histórico deve
ocorrer somente depois da cadeia #89 → #91 avançar. Isso não autoriza merge
isolado do #92.

Os gates que dependem de EP125/EP126 permanecem fora do escopo desta fase.
