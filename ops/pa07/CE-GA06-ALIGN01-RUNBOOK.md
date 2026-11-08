# CE-GA06-ALIGN01 — Alinhar Ferret CLI e bootstrap à Web v5 (EP126)

**Data:** 08/11/2026. **Responsável:** Andréa Kozicki. **Máquina:** EP126. **Estado:** código no GitHub; aplicação em VM ainda não comprovada.

## Conclusões já demonstradas — não repetir

CE-GA06-CUT01 executado em 08/11 16:43:56 BRT: Ferret Web v5 `2.4.3+ce.pa07.v5` healthy, monitor systemd v5 instalado, timer ativo, backup de estado atualizado em `/var/backups/GA06-CUT01-EP126-RRLgwphD`, rollback de imagem 2.4.3 preparado, mas **não ensaiado**.

A `main@04f88d275064a005d0ffcd4f9372a371c28c32d5` preserva o Compose-base Ferret 2.4.3 por digest, mas os launchers Bash/Fish e bootstrap antigos selecionam essa imagem ao processar inbox ou recriar o serviço.

## Decisão arquitetural: NÃO alterar Compose-base

O gate de Supply Chain do GitHub proíbe uma imagem local baseada só em tag como baseline de `deploy/interna/ferret/compose.yml`. **A tentativa inicial de alteração direta foi REVERTIDA NA BRANCH**, antes de qualquer comando na VM. O Compose principal mantém o blob Git `9f4e17461d2179607343780fed922153050f1e86`, com imagem oficial 2.4.3 fixada por digest. Não enfraquecer nem alterar o gate.

A candidata local v5 continua provida pelo override **opt-in, versionado na PR #207**, com hash Git blob `decf0a8b5d5b18b6122b4afcc12a17e5ee5627f2`, encontrado na EP126 porque já foi usado com sucesso pelo CE-GA06-CUT01.

## Correção mínima agora executável

Promover na EP126 somente os três launchers que a PR #207 já havia corrigido e que passaram por testes offline em outubro:

| Arquivo | Blob anterior da main | Blob aprovado desta PR |
|---|---|---|
| `scripts/dlp/processar_inbox_ferret.sh` | `777141f950a980317ccb2f3b1922c48855a49829` | `d980a038243876ad853b374d0e9895bc19e9e77e` |
| `scripts/dlp/processar_inbox_ferret.fish` | `1c417a3c7841b75995b95883e0fbc007a54d099a` | `ef71366206ae9ee655a89fffb2a2299fd898204d` |
| `scripts/bootstrap/subir_ferret.fish` | `cb74a487c93e556c19ad877d933ebd60261e09f6` | `b3535947424a143e27a3cec6009cec4ee2538b6a` |

O delta local aos scripts da PR #207 é propositalmente pequeno: **quando host = EP126 e drop-in do monitor v5 estiver instalado**, selecionar automaticamente o override `pa07-v5/compose.pa07-v5.override.yml` com hash exato `decf0a8...`. O comportamento nos demais hosts e quando não há monitor v5 permanece com opt-in por variável, sem alterar o baseline geral.

Isso evita que os launchers Bash, Fish e bootstrap escolham silenciosamente a imagem 2.4.3 enquanto o monitor indica que v5 está ativa. Os scripts verificam o candidato pela identidade Docker/Image ID e/ou preflight existente, sem pull implícito; os dados persistentes permanecem intocados. O bootstrap Fish configura automaticamente também o TAR original da custódia já validado em GA06.5/6, no caminho privado fixo da EP126, para que seu preflight obrigatório continue funcionando.

**Limitação:** outro operador ainda pode manualmente executar `docker compose -f deploy/interna/ferret/compose.yml up` sem override e reverter a imagem. O script protege os **três launchers** do projeto, não intercepta comandos Docker arbitrários. Documentar no runbook operacional que qualquer manutenção Ferret v5 exige o override.

## CE-GA06-ALIGN01 — instalador não privilegiado e de execução única

`ops/pa07/ce_ga06_align01.py`, baixado por commit imutável e validado por Git blob/AST, atua **sem sudo**:

1. Confere EP126, `andrea.kiew`, Git HEAD congelado, Compose-base hash original, override hash aprovado, drop-in systemd versão v5 e imagem candidata efetivamente em execução por Docker Image ID `sha256:535ec9ef...`.
2. Inspeciona os blobs dos três launchers antes de modificá-los. Se houver personalização diferente dos hashes conhecidos, interrompe **sem sobrescrever**.
3. Baixa apenas os três arquivos de um commit **fixo** da PR operacional; exige hashes exatos antes de qualquer gravação.
4. Faz backup privado 0700/0600 dos scripts; instala atomicamente cada nova versão preservando o modo executável original.
5. Confere hashes finais e executa rollback dos scripts substituídos se falhar. **Não executa as próprias rotinas Bash/Fish**, `docker compose up/run`, `sudo`, mudanças na inbox/relatórios, Wazuh, OpenBao, pfSense, Twingate ou Git.
6. Após a instalação, os três scripts rastreados ficarão com modificações intencionais no checkout local EP126, até conciliação futura. O HEAD permanece `04f88d27`; a EP125 não é modificada.

**Artefato de mudança:** PR #227 DRAFT. Antes de qualquer merge/fast-forward posterior, reconciliar explicitamente as alterações da EP126; não executar `git restore`, `git reset --hard` nem `git clean`.

## Critério mínimo da implantação

```text
RUNTIME_WEB_V5=CONFIRMADO
BACKUP_SCRIPTS=VERIFICADO
SCRIPTS_ATUALIZADOS=3
OVERRIDE_ATIVO_POR_MONITOR_V5=SIM
CLI_BASH_FISH=ALINHADOS
BOOTSTRAP_FISH=ALINHADO
COMPOSE_BASE_ALTERADO=NAO
WORKTREE_TRACKED=MODIFICACOES_CONTROLADAS_NA_EP126
DADOS_DLP_ALTERADOS=NAO
SERVICOS_REINICIADOS=NAO
CE-GA06-ALIGN01_CONCLUIDO
```

**Não equivale a teste funcional do CLI ou UI:** o erro HTTP403 sintético → `INCONCLUSIVE` e uma execução sintética de CLI v5 permanecem provas pontuais para o fechamento técnico do PA-07. **Não repetir baterias gerais.** Bacula e egress não são cobertos.

## Reversão

O backup privado `$HOME/.CE-GA06_ALIGN01_BACKUP_<data>/` contém os três scripts anteriores. A reversão deliberada dos launchers deve considerar o status de v5 e monitor; manter imagem v5 Web mas launchers antigos faz CLI/Bash/Fish voltarem a 2.4.3. A rotina também tenta rollback automático caso a gravação falhe antes do sucesso final.
