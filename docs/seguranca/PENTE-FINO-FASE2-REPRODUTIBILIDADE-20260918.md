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

### 2B — Fonte de verdade

Critério:

- handoff não contém renderer Bacula de laboratório;
- identidade do Director aponta para PgBouncer/socket;
- integração SMTP cross-VM não habilitada não é apresentada como operacional;
- gaps remanescentes são declarados, não mascarados.

### 2C — Smoke test do bundle

O CI deve gerar ambos os `.tar.gz`, validar SHA-256/denylist, extrair os
pacotes e executar preflights seguros diretamente das raízes extraídas.

## Pendência que continua exigindo host

A promoção/reconciliação completa do runtime Bacula canônico
(`director-config`, TLS, PgBouncer config/socket e configuração final do
Director) continua dependente da EP126 e das evidências live. O código desta
fase não marca esse gate como concluído.
