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

### 2C — Smoke test do bundle

O CI deve gerar ambos os `.tar.gz`, validar SHA-256/denylist, extrair os
pacotes e executar preflights seguros diretamente das raízes extraídas.

## Pendência que continua exigindo host

A promoção/reconciliação completa do runtime Bacula canônico
(`director-config`, TLS, PgBouncer config/socket e configuração final do
Director) continua dependente da EP126 e das evidências live. O código desta
fase não marca esse gate como concluído.