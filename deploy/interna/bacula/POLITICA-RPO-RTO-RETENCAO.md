# Política inicial de RPO, RTO e retenção

Esta política é uma baseline acadêmica configurável pela equipe.

## Objetivos

- RPO geral inicial: até 24 horas para dados da aplicação.
- RTO de laboratório: até 4 horas para recuperação funcional dos serviços
  prioritários, sem promessa de SLA de produção.
- A restauração tem prioridade sobre a maximização de histórico.

## Agenda inicial

| Job | Frequência |
|---|---|
| MariaDB dump + backup | diário |
| arquivos/configs allowlisted | diário incremental |
| Full do conjunto principal | semanal |
| OpenBao Raft snapshot | diário e após mudança relevante |
| Bacula Catalog dump | após jobs principais |
| restore-test sintético | semanal |

A hora exata será definida pela equipe após conhecer a janela de uso. O baseline
não deve inventar horário definitivo antes da implantação.

## Retenção inicial

- Full: manter 2 ciclos semanais no laboratório.
- Incrementais: manter até o próximo conjunto Full válido e dentro da janela de
  aproximadamente 14 dias.
- Jobs/File records do Catalog: 30 dias inicialmente.
- Snapshots OpenBao: retenção compatível com o espaço, inicialmente 14 dias.
- Staging: somente até confirmação do job; não é retenção.

A política deverá ser reduzida automaticamente se o storage atingir o limiar
crítico, mas nenhuma rotina deve apagar o último Full válido.

## Regra de ouro

Retenção só é considerada válida depois que o restore-test correspondente
passar. "Backup concluído" sem teste de restauração não fecha a fase.
