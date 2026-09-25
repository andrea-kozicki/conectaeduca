# BAC-05 — decisão de recorrência do Bacula no laboratório acadêmico

**Data da decisão:** 25/09/2026  
**Escopo:** ConectaEduca / Experiência Criativa 8  
**Estado:** risco residual aceito para o laboratório; Schedule automático não ativado

## Decisão

O baseline acadêmico final do ConectaEduca **permanece com execução manual dos
backups operacionais Bacula**. Nenhum `Schedule` automático será criado apenas
para produzir evidência de recorrência.

A decisão é deliberada. O projeto não possui uma janela operacional real
definida para as VMs acadêmicas e, portanto, atribuir um horário arbitrário a um
Schedule produziria uma configuração sem justificativa operacional.

Esta decisão **não reabre o BAC-04**. O BAC-04 já comprovou, ponta a ponta:

- materialização das fontes autoritativas;
- backup dos quatro conjuntos operacionais;
- restore isolado dos quatro conjuntos;
- igualdade SHA-256 entre origem e restaurado;
- validação de formato;
- preservação dos SmokeJobs;
- política de retenção e capacidade do pool.

O BAC-05 trata apenas da **recorrência automática**.

## Impacto sobre RPO

A política mantém **RPO alvo de até 24 horas** como objetivo de arquitetura, mas,
sem Schedule, esse RPO **não é garantido pelo runtime acadêmico**.

A idade do ponto de recuperação passa a depender da última execução manual
bem-sucedida. Portanto:

- não apresentar o laboratório como possuindo RPO automático de 24 horas;
- registrar a data/hora do último backup válido nas evidências de freeze;
- se o último ponto de recuperação estiver defasado para a demonstração ou para
  um teste planejado, executar novo backup manual antes do evento;
- tratar ausência de automação como risco residual explícito.

O RTO de laboratório de até 4 horas continua como **objetivo**, não como SLA de
produção. A capacidade técnica de restore já foi comprovada pelo BAC-04.

## Controles compensatórios no laboratório

Antes de `FREEZE-01`, o operador deve:

1. registrar o último JobId/status válido de cada workload operacional;
2. registrar a idade do ponto de recuperação mais recente;
3. executar backup manual adicional somente se necessário para obter um ponto
   suficientemente atual para a atividade acadêmica;
4. preservar a evidência sanitizada e seus hashes;
5. não alterar os recursos validados do BAC-04 apenas para simular automação.

A operação manual não altera as regras de custódia:

- root token OpenBao: nunca entra no backup;
- unseal shares: nunca entram no backup;
- segredos runtime permanecem fora do Git;
- OpenBao é protegido por Raft snapshot;
- MariaDB por dump consistente;
- Catalog por dump lógico PostgreSQL;
- Recovery State por allowlist.

## Risco residual aceito

**Risco:** ausência de recorrência automática pode produzir ponto de recuperação
mais antigo que o RPO alvo de 24 horas se o operador não executar um backup
manual em tempo hábil.

**Escopo da aceitação:** somente o laboratório acadêmico atual.

**Não coberto por esta aceitação:** ambiente produtivo. Em produção, a recorrência
deve ser automatizada em janela operacional real, monitorada e acompanhada de
alerta de falha/freshness.

Permanece separado o risco já conhecido de domínio físico de falha:

`PHYSICAL_ISOLATION=0`

pois Storage e workloads protegidos compartilham a EP126.

## Critério de fechamento BAC-05

O BAC-05 é considerado fechado quando esta decisão estiver versionada e o
`FREEZE-01` registrar explicitamente a freshness do último backup válido.

Status canônico:

```text
BAC05_SCHEDULE_ACTIVE=NO
BAC05_EXECUTION_MODE=MANUAL
BAC05_RPO_24H_GUARANTEED=NO
BAC05_RISK_ACCEPTED=YES
BAC05_SCOPE=ACADEMIC_LAB
BAC05_STATUS=DONE_WITH_ACCEPTED_RISK
```

Reabrir BAC-05 somente se for definida uma janela operacional real ou se o
projeto evoluir para um ambiente que exija recorrência automática.
