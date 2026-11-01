# GA-08 — Plano de implantação e rollback (rascunho controlado)

## Evidência já obtida
Ensaio efêmero v4 de 28/10/2026: `RESPOSTA_FPM=pong`, `STATUS=INTEGRACAO_OK`, sem rede ou alteração da produção.

## Artefatos preparados
- `scripts/ga08-preparar-implantacao-ep125.sh`: pré-requisitos somente leitura e evidência no diário.
- `scripts/ga08-implantacao-controlada-ep125.sh`: **gate fechado**; não altera Compose ou contêineres enquanto não houver validações.
- `scripts/ga08-rollback-controlado-ep125.sh`: preflight de rollback somente leitura, sem reinícios.

## Gates antes de habilitar a implantação
1. Renderizar e validar todos os arquivos Compose efetivos e o overlay candidato; checar versão de Compose e `!override`.
2. Verificar volumes/mounts, usuários, grupo suplementar 82, diretório 82:82/0770 e ausência de portas publicadas por PHP/Nginx.
3. Verificar a comunicação WAF→Nginx→PHP-FPM por socket e bloquear PHP→Nginx HTTP, com ensaios controlados.
4. Preservar saída do PHP para banco e serviços essenciais da EP126, evitando abrir acesso desnecessário ao WAF/Nginx.
5. Capturar configuração anterior e seus arquivos Compose, variáveis **sem divulgar segredos**, hashes, imagens e plano de restauração.
6. Testar rollback e definir critérios de abortar (saúde, login, MFA, banco, WAF, logs).
7. Solicitar autorização explícita da responsável antes de qualquer aplicação.

## Segurança operacional
Os scripts nesta fase não executam `docker compose up/down`, não recriam contêineres, não criam rede, não alteram permissões de host e não tocam no banco. O gate de implantação retorna código diferente de zero intencionalmente.

## Diário
Cada execução escreve uma entrada em `~/ConectaEduca_Fase2_Evidencias/EP125/diario.md`; o arquivo remoto somente será confirmado após execução na EP125.


## Checkpoint 01/11/2026 — GA-08.4 e decisão de implantação

**Estado da EP125:** main local `b74ea581a0814d86a99b6b455d5569f12fa967e5`, Compose v5.5.1. A referência local da PR #200 está em `84d9d5a`; os três arquivos candidatos do GA-08 foram comparados e permanecem idênticos à HEAD da PR. Não fazer `git pull` ou merge para validar o candidato.

**GA-08.2 — validação estática PASS:** dez arquivos Compose efetivos, incluindo o arquivo local não rastreado `compose.audit-persistent.yml`; `docker compose config` retornou 0 com variáveis sintéticas; WAF e Nginx somente `waf_backend`, PHP somente `php_egress`; WAF com duas portas publicadas, Nginx/PHP sem publicação; mounts de socket presentes, montagem Nginx readonly. Não é prova de runtime ou recuperação.

**GA-08.3 — baseline:** WAF, Nginx e PHP `running/healthy`, restartCount=0. Foram inventariados hashes dos 10 arquivos e IDs das imagens Docker. A imagem atual não foi exportada, e o snapshot institucional ainda não foi comprovado.

**GA-08.4 — cópia privada:** dez arquivos Compose copiados com hash original=cópia para `~/ConectaEduca_Fase2_Evidencias/EP125/GA08/ROLLBACK_BASELINE_20261101T160926_teQE6K/compose/`; o `manifest.txt` tem SHA256 `e271b0e927e80371e19a01fff72d015c6370255aa2714b7c1ef4c60b5d908b23`. Contêineres WAF/Nginx/PHP mantêm imagens locais disponíveis. **A cópia não inclui necessariamente diretórios adjacentes usados como bind mounts, segredos, CA/TLS, `.env`, dados persistentes nem snapshots. Não compartilhar arquivos privados.**

**Defeito conhecido não resolvido pelo candidato:** no PA-02.1 o host EP125 obteve HTTP 200 em `172.18.0.2:8080` diretamente pelo bridge Docker, sem registro do marcador no WAF. Mesmo com redes `waf_backend` e `php_egress`, o host continua com potencial acesso à IP da bridge. A segregação candidata restringe peers da aplicação, mas **não corrige isoladamente o bypass originado no host**. UFW está ativo; leitura nftables com `sudo -n` não foi autorizada. Uma regra somente `DOCKER-USER` não resolve necessariamente tráfego originado no host. Políticas de firewall por IP interno de contêiner são frágeis após recriação; firewall pfSense interzona não observa esse trajeto local. Operadores com acesso privilegiado ao socket Docker podem contornar controles de rede locais; tratar esse privilégio como parte do modelo de ameaça.

### Gate obrigatório antes do cutover

1. Documentar **qual escopo será realmente mitigado** pelo candidato (PHP/contêineres → Nginx), e definir separadamente como lidar com a origem host → upstream, ou manter formalmente o risco residual aberto. Sem evidência negativa host→Nginx, **não encerrar PA-02**.
2. Confirmar autorização operacional, janela de intervenção e **snapshot restaurável** com identificador e responsável pelo suporte; registrar arquivos e imagens de origem e pré-requisitos de retorno. Não declarar rollback disponível apenas por cópias/hash.
3. Revisar na VM `bind mounts` e a disponibilidade local de **configurações externas necessárias** ao socket Unix e à configuração Nginx, sem copiar conteúdo de segredos para a evidência pública; a cópia de 10 overlays isoladamente não é suficiente para restaurar o serviço.
4. Validar ensaio controlado dos serviços do candidato e do caminho PHP→banco, mantendo WAF/HTTPS/Twingate, Wazuh e login/RBAC/MFA. Não executar `docker compose up/down` a partir da PR draft nem reiniciar Docker sem change control.
5. Preparar um **rollback operacional testável**, no mínimo restabelecendo Compose anterior, rede, imagens, mounts, dependências de SQL/TLS e healthchecks, com critério explícito de aborto; a implementação e o rollback atuais em `scripts/ga08-implantacao-controlada-ep125.sh` e `scripts/ga08-rollback-controlado-ep125.sh` permanecem **sem ações de deploy/rollback**.

**Status 01/11:** baseline/cópia verificados; candidato estático PASS; gate de implantação **FECHADO** por falta de rollback real, snapshot/autorização e mitigação completa para origem host. Reteste do Pentest B deverá distinguir mitigação parcial de fechamento de PA-02.
