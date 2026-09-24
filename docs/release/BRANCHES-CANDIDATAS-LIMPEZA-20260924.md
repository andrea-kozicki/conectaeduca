# Branches — candidatos de limpeza pré-freeze (24/09/2026)

## Objetivo

Reduzir risco operacional de trabalhar acidentalmente em branch histórica.

Este documento **não autoriza deleção automática**. A limpeza deve ocorrer somente após confirmar que a `main` contém o resultado desejado e que não há referência externa necessária.

## Preservar

- `main` — fonte canônica atual.
- `legacy/seguranca-privacidade-web-cognito` — baseline histórico da fase Cognito.
- `feature/twingate-prep` — preservar enquanto Twingate/Pentest B continuar fase posterior.
- branch corrente de qualquer PR ainda aberto.

## Candidatos claros após merges recentes

As seguintes branches correspondem a PRs mergeados e podem ser removidas **depois** de confirmar que não há trabalho adicional nelas:

- `feat/gui01c-phpmyadmin-readonly-preflight-20260924` — PR #106 mergeado;
- `docs/atualiza-plano-testes-20260924` — PR #107 mergeado;
- `docs/prefreeze-pentest-demo-20260924` — PR #108 mergeado;
- `feat/gui01b-bacularis-readonly-final` — PR #105 mergeado;
- `fix/appsec01-project-root-20260922` — PR #104 mergeado;
- `fix/gui01-teste-menor-privilegio-20260921` — PR #103 mergeado;
- `feat/gui01-webgui-pre-freeze-20260921` — PR #102 mergeado;
- `chore/repo01-reconcile-91-94-20260921` — PR #101 mergeado;
- `chore/repo01-reconcile-91-93-20260921` — PR #100 mergeado;
- `chore/repo01-reconcile-91-92-20260921` — PR #97 mergeado;
- `chore/pente-fino-repositorio-20260918` — PR #91 mergeado;
- `docs/estado-operacional-20260916` — PR #89 mergeado.

## Superseded/fechadas sem merge

Estas branches pertencem a PRs fechados sem merge porque foram substituídos/reconciliados:

- `chore/auditoria-estatica-repo-20260918` — #90;
- `chore/pente-fino-fase2-reprodutibilidade-20260918` — #92;
- `chore/pente-fino-fase3-supply-chain-20260918` — #93;
- `chore/pente-fino-fase4-documentacao-legado-20260918` — #94;
- `chore/repo01-prep-89-91-20260918` — #95;
- `chore/repo01-reconcile-93-20260921` — #98;
- `chore/repo01-reconcile-94-20260921` — #99;
- `feat/wazuh-pentest-reprodutivel` — PRs #85/#88, substituídos pelo caminho clean mergeado em #87.

Antes de apagar uma branch superseded, comparar o commit final dela com a história da `main` apenas se houver dúvida sobre algum artefato específico. Não reabrir implementação antiga só porque a branch existe.

## Branches históricas antigas

Há muitas branches correspondentes a PRs já mergeados entre #29 e #88.

Elas podem ser limpas gradualmente depois do FREEZE-01, mas não são prioridade agora. Limpeza de branch não deve competir com BAC-04, phpMyAdmin, readiness sem sudo ou os pentests.

## Regra operacional até o freeze

Quando entrar em uma VM:

```bash
cd /opt/conectaeduca
git branch --show-current
git status --short
git rev-parse --short HEAD
```

O trabalho operacional novo deve partir da `main` sincronizada, salvo quando um runbook mencionar explicitamente outra branch.

## Critério de limpeza

Uma branch pode ser removida quando todos forem verdadeiros:

1. PR correspondente está mergeado ou formalmente superseded;
2. nenhum artefato exclusivo ainda necessário depende dela;
3. `main` contém a versão final pretendida;
4. não é baseline histórico deliberado;
5. não é branch de fase futura ainda necessária.
