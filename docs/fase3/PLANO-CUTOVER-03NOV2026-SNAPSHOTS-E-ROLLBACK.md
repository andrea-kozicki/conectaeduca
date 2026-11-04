# ConectaEduca — autorização para cortes e plano de rollback (03/11/2026)

## Adendo de atualização em 04/11 — hierarquia de evidências e prazo de sudo

O quadro abaixo foi elaborado **antes** da tentativa real GA08.19. Na EP125, houve cutover real que **falhou** no health do PHP-FPM; ocorreu rollback Docker **PASS 3/3 HEALTHY**, sem E2E HTTPS comprovado e com PA-02 ainda aberto. Ver [incidente GA08/PA-02](GA08-PA02-INCIDENTE-CUTOVER-ROLLBACK-20261103.md) para evitar interpretar a linha histórica “runtime ainda não alterado” como estado atual. A operadora informou retirada do `sudo` em **10/11/2026**; o [plano atualizado de dependências de privilégios](PLANO-ATE-09NOV-SEM-SUDO-APOS-10NOV-20261104.md) tem precedência para ordenação das próximas atividades. **Nenhum novo cutover, unseal, backup ou mudança pfSense foi executado por este adendo.**

## Fonte: confirmação textual do suporte institucional

Respostas do suporte às quatro perguntas sobre snapshots integrais:

- **EP125-PUCPR** — registro informado: `ubuntu 22 - altair.santin - ubuntu.33` — data/hora `11/3/2026 - 2:34:50 PM`.
- **EP126-PUCPR** — registro informado: `ubuntu 22 - altair.santin - ubuntu.49` — data/hora `11/3/2026 - 2:34:50 PM`.
- **Cobertura (suporte):** "Sim, os Snaps abrangem tudo o que é necessário para recuperar."
- **Armazenamento externo/volumes excluídos:** "Não."
- **Capacidade de restaurar em falha:** "Se falhar, conseguimos sim."

Interpretação de data: `11/3/2026` corresponde a **03/11/2026** em padrão EUA. Horário informado **14:34:50**; o fuso do sistema de snapshots **não foi declarado**. `ubuntu.33` e `ubuntu.49` são referências relatadas pelo suporte; não presumir que sejam UUIDs exclusivos dos objetos snapshot. O campo `ubuntu 22` pertence à identificação fornecida pelo suporte e **não prova a versão atual do sistema operacional da VM**.

**Gate de snapshot:** cobertura e possibilidade de restauração foram confirmadas. Isso libera iniciar alterações **sequenciais e verificadas**, não autoriza execução simultânea, nem substitui ensaios de rollback.

## Limites da garantia

- Restaurar um snapshot da VM retorna o disco ao estado da captura. Artefatos, logs e backups locais **criados após a captura** podem ser perdidos; preservá-los fora da VM se a retenção for necessária e autorizada. O backup privado do staging da EP126 em `/var/backups/GA09-EP126-20261103T194712Z-VCRCCT` foi criado durante trabalho posterior e não deve ser assumido presente após restauração da VM.
- Snapshots de VMs não revertem automaticamente estado do GitHub, Trello, painel Twingate, prestadores externos e dispositivos fora do escopo. Registrar divergências e plano de reconciliação.
- Verificar com o suporte o identificador único de cada snapshot e o fuso de `2:34:50 PM` para rastreabilidade; **isso não invalida a confirmação operacional já recebida**.
- A política Bacula BAC-05 permanece manual, sem Schedule; `PHYSICAL_ISOLATION=0` continua risco residual: Bacula Storage compartilha domínio físico da EP126.
- Nunca publicar unseal shares, tokens AppRole, dumps, snapshots Raft, logs confidenciais, nem diretórios privados.

## Ordem autorizada de execução — um gate por vez

| Ordem | Frente | Situação no início do corte | Gate de avanço | Rollback |
|---|---|---|---|---|
| 1 | EP126 — OpenBao | **BLOCKED:** health `HTTP 503`, `initialized=true`, `sealed=true`; Shamir `n=3`, `t=2`, `progress=0` (GA09.19C/D) | Unseal **manual**, por custodiante autorizado, duas shares distintas; `sealed=false` e API health 200; confirmar AppRole de snapshot sem divulgar segredos | Não reinicializar o OpenBao nem recriar chaves; em caso de anomalia de dados ou irreversibilidade, acionar suporte conforme referência EP126 |
| 2 | EP126 — Bacula GA09 | `GA09.17 --check=PASS`; `GA09.18 backup staging=PASS`; refresh GA09.19 falhou em `openbao_snapshot()`, `HTTPError`, sem divergência de nenhum dos 8 arquivos | Após unseal, confirmar preflight e ausência de Jobs concorrentes; executar materializador uma vez; validar quatro artefatos e sidecars, depois quatro Jobs **manuais** e restore com SHA por conjunto | Backup staging privado pré-refresh; se houver falha parcial, não executar Jobs; restaurar o conjunto inteiro com validação e autorização; se recuperação maior, snapshot EP126 |
| 3 | EP125 — GA08 / PA02 WAF dual-socket | PR #217 contém **candidato**, testes pre-cutover; runtime ainda não alterado pelo PR | Capturar estado e hashes, aplicar mudança mínima em janela EP125, verificar serviços healthy, proxy, WAF/CRS e regressão PA02 | Reverter configuração promovida com backup local; se insuficiente, suporte restaura EP125 |
| 4 | EP126 — GA06 Ferret v5 / PA07 | PR #207 candidata; baseline 2.4.3; backup GA06.10B preparado; cutover ainda não realizado | Imagem/código pinados, pré-condições, smoke controlado, Wazuh DLP e rollback testável | Retornar à imagem/config 2.4.3, ou restaurar EP126 se irreversível |
| 5 | App de login / PR #205 | PR #205 draft: envelope híbrido e MFA; teste de navegador/E2E não comprovado em runtime | CI, revisão, MFA real, credenciais de teste, negativa, logs/telemetria | Reverter release específica; restauração EP125 se necessário |
| 6 | Consolidação dos PA-01…PA-07 e auditoria | Evidências de fases A/B e Zero Trust com diferentes níveis de conclusão | Comparativo antes/depois, logs Wazuh, DLP, rastreio de acesso Twingate e limites documentados | Qualquer falha remetida à frente correspondente, sem mascarar resultado |

## Estado real e PRs verificados em 03/11/2026

PRs #203, #205, #206, #207, #214, #217 e #218 **abertos em draft, não mergeados**. Snapshot não substitui CI, revisão de código, homologação local, retestes e autorização institucional. Não fazer merge cego; alterações de GitHub, VMs e console Twingate são estados independentes.

## Evidência de GA09 acumulada

- `/usr/local/sbin/conectaeduca-bacula-materializar-staging`: Python 276 linhas, root:root, 0755, SHA-256 `b655788eefad7b4d99e8f558d5a43779caa25d34b23f490ba11e4df9bd8040ac`; `--check` PASS.
- `GA09.18`: TAR privado SHA-256 `e53ea63d0e56fb76289c8563accfe76e4ce191b9dea1d28647d79a2ad22904f9`; conteúdo não anexado; confirmação estrutural TAR/gzip, **não** restore validado.
- `GA09.19`: materialização iniciada, falhou, `JOBS_BACULA=NAO_EXECUTAR`.
- `GA09.19A`: 4 conjuntos / 8 arquivos de staging sem divergências de hash ou mtime com backup anterior.
- `GA09.19B/C`: falha na função `openbao_snapshot()` por `HTTPError`; health anônimo HTTP 503, `sealed=true`.
- `GA09.19D`: Shamir `n=3`, `t=2`, `progress=0`. **Unseal ainda não confirmado nesta evidência.**

## Checklist mínimo por corte

1. Confirmar a VM correta, estado anterior e referência do snapshot; log com hora UTC e commit.
2. Garantir que não haja outro deploy/Job concorrente nem indisponibilidade institucional não planejada.
3. Aplicar apenas uma frente, mantendo backup/rollback específico do componente.
4. Exigir prova pós-corte funcional, negativa, telemetria e health; se falhar, STOP e rollback.
5. Documentar comandos, hashes, resultados, limitações e capturas/figuras sanitizadas.
6. Só então avançar à próxima frente e registrar o estado real em Trello/GitHub/Daily 9.

**Critério de encerramento:** snapshots CONFIRMADOS pelo suporte; **cortes ainda não marcados concluídos** até evidência runtime, Jobs/restores e retestes por PA.
