# CE-GA06-CUT01 — Ferret PA-07 (EP126) — cutover único e reversível

**Data:** 08/11/2026 · **Responsável:** Andréa Kozicki · **Escopo:** serviço Docker Ferret na EP126 e monitor systemd específico. **Estado:** procedimento implementado no GitHub, execução na VM aguardando operadora.

## Meta técnica

Trocar o Ferret Scan Web UI da imagem fixa v2.4.3 para a imagem candidata `2.4.3+ce.pa07.v5` da PR #207, que trata o caso PA-07-DLP-01 (interface exibir falso resultado limpo após HTTP 403). **Não equivale a fechar todo PA-07**: scripts CLI, egress e Bacula continuam escopos distintos.

## Evidências já obtidas que NÃO devem ser repetidas como bateria

- GA06.1–4: imagem v5 candidata instalada e identificada em Docker EP126, UID/GID1000, Compose do override alterando só image/pull_policy, monitor health existente 2.4.3.
- GA06.5: archive local `/home/andrea.kiew/Downloads/ferret-pa07-v5-candidate-docker-archive.tar` validado SHA-256 `5786c56b...`.
- GA06.6: preflight de proveniência TAR, identidade imagem, rootfs e Compose `PASS`.
- GA06.10B: backup isolado de 03/11 sob `/var/backups/GA06-EP126-...` comprovado com integridade/ACLs, porém **sem restore ensaiado**. O script CE-GA06-CUT01 cria um **novo** backup privado imediatamente antes de alterar o serviço.
- O snapshot integral EP126 foi informado pelo suporte, mas **ID e restaurabilidade não constam na evidência recebida**; por isso, não afirmar que houve validação de recuperação de hipervisor.

## Condições de execução e autorização

A operadora autorizada `andrea.kiew` executa `sudo ./ce_ga06_cut01.sh --apply` **sem shell root interativo**. O script verifica host `ep126-pucpr-br`, Git `main` em `04f88d275064a005d0ffcd4f9372a371c28c32d5`, conteúdo exato do Compose base, override/custódia da PR #207, imagem atual 2.4.3, imagem v5 imutável `sha256:535ec9ef...`, timer existente ativo e arquivo drop-in v5 ainda ausente. O preflight TAR não realiza `docker load`, pull ou novas instalações.

**Guarda de mudança:** `--apply` explícito e backup novo, completo e comprimido, root-only 0700/0600, com verificação gzip, listagem TAR e SHA-256 local. Não publicar a cópia; contém configuração e possíveis dados sensíveis. A responsabilidade de confirmar a janela operacional e as regras institucionais aplicáveis permanece com a operadora. Não utilizar durante manutenção externa não coordenada.

## Fluxo de implantação

1. Guardas e preflight de SHA/TAR/Compose/health original (pontuais, não pentest).
2. Backup privado de `config/ferret.yaml`, `.runtime/state`, `.runtime/inbox`, `.runtime/reports`, `.runtime/events`; se houver erro, **aborta antes do cutover**.
3. Pausar somente `conectaeduca-ferret-healthcheck.timer`.
4. `docker compose -f BASE -f OVERRIDE up -d --no-deps --pull never ferret`: **recria apenas o serviço Ferret**, sem apagar volumes, preservando porta loopback, não root, cap_drop e rootfs read-only. Saídas completas retidas em área privada temporária, não publicadas.
5. Verificar apenas `/health` (`healthy`, `service=ferret-scan-web`, `version=2.4.3+ce.pa07.v5`) e container Image ID fixo.
6. Instalar apenas o drop-in próprio `/etc/systemd/system/conectaeduca-ferret-healthcheck.service.d/90-ga06-ferret-v5.conf` (root 0644) **sem editar a unit original**, executar `daemon-reload`, reativar timer e disparar serviço de health uma vez.
7. Se qualquer etapa pós-pausa/cutover falhar, **rollback automático best-effort**: remover somente drop-in criado, restaurar Compose base e health 2.4.3, iniciar timer. Se rollback apresentar falha, escalar ao operador e recuperar via backups/snapshot; não há garantia de restauração completa sem ensaio real de restore.

**Nenhum teste redundante** é executado; health baseline/v5 e monitor v5 são gates mínimos de funcionalidade.

## Ações que o script não executa

Sem `sudo -s`, `docker load`, `docker pull`, `docker down`, `prune`, remoção de backups/arquivos de dados, modificação do Git, scripts DLP e regras Wazuh, Twingate, OpenBao ou pfSense. O processamento **CLI** pode continuar usando baseline 2.4.3 se seus scripts não forem migrados ao `FERRET_COMPOSE_OVERRIDE`; **não declarar que CLI e UI usam a mesma imagem** sem evidência.

## Critério imediato de sucesso e prova mínima dirigida

- `PREFLIGHT=PASS`, `BACKUP_NOVO_VERIFICADO=SIM`, `FERRET_V5_HEALTH=PASS`, `MONITOR_V5=PASS`, `TIMER_ATIVO=SIM`, `PA07_FERRET_V5_IMPLANTADO=SIM`, `CE-GA06-CUT01_CONCLUIDO`.
- Posteriormente, **um único teste funcional do defeito PA-07-DLP-01**: HTTP 403 sintético produz `INCONCLUSIVE` persistente em tela e exportação indisponível (não `No sensitive data found`). Não carregar arquivos reais; nenhuma rotina de pentest ampla. Sem essa evidência, classificar **IMPLANTADO / CORREÇÃO FUNCIONAL PENDENTE**, não PA-07 PASS integral.
- Caso o script reporte `CE-GA06-CUT01_ABORTADO`, manter saída resumida; não repetir cegamente, inspecionar erro/rollback e estado do serviço.

**Não mesclar esta PR operacional na `main` durante freeze `04f88d27` sem planejar atualização dos checkouts EP125/EP126.**
