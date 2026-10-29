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
