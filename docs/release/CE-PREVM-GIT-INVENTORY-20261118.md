# CE-PREVM — Inventário Git local, mínimo e somente leitura

**Preparado em 18/11/2026.** A revisão das PRs históricas [#215](https://github.com/andrea-kozicki/conectaeduca/pull/215) e [#221](https://github.com/andrea-kozicki/conectaeduca/pull/221) demonstrou que o kit antigo mistura verificações Git, consultas Docker/systemd, HTTP com `--insecure` e geração de artefatos. Esta implementação **nova e isolada** aproveita somente a ideia de classificar alterações locais, evitando levar os scripts de outubro/novembro para a `main`.

## O que foi preparado no GitHub

- `scripts/evidencias/ce_prevm_git_inventory.py`: Python stdlib, sem dependências, com modo padrão **PLAN_ONLY_NOT_EXECUTED**. Não executa Git no modo plano.
- Modo futuro `--execute-readonly`: somente no hostname exato EP125/EP126 e como usuário não-root; consulta a cópia Git **local** em `/opt/conectaeduca`, sem `git fetch`, `pull`, `reset`, `checkout`, `clean`, `commit` ou `push`.
- Saída em JSON restrita a SHA do HEAD, cópia local em cache de `origin/main` (marcada explicitamente como cache, **não** estado remoto), classificação genérica de branch e contagens de caminhos alterados/não rastreados por área. Não imprime nomes de arquivos nem lê conteúdos, inclusive arquivos de segredo ignorados.
- Não abre conexões HTTP/TCP, não chama Docker/systemctl, não lê `.env`, não toca em Twingate/OpenBao/Wazuh/Ferret, não cria diretórios nem arquivos de evidência. Não modifica o índice Git e define `GIT_OPTIONAL_LOCKS=0`.
- `tests/python/test_ce_prevm_git_inventory.py`: testes com repositórios Git 100% sintéticos sob diretórios temporários, bloqueio por hostname/root, paths e segredos não publicados, isolamento por VM e comandos Git proibidos.
- Workflow CI somente leitura, com runner público e **sem acesso às VMs**.

## Como consultar o plano agora, em computador/repositório autorizado

```bash
python3 scripts/evidencias/ce_prevm_git_inventory.py --role ep125
python3 scripts/evidencias/ce_prevm_git_inventory.py --role ep126
```

Isso apenas mostra o escopo proposto. **Não executa coleta nem altera a máquina.**

## Para a futura janela institucional — ainda NÃO executar

O modo `--execute-readonly` foi preparado para uma futura coleta local nas VMs **somente depois** de confirmar o commit do script e a identidade institucional. Ele é deliberadamente bloqueado fora do hostname exato ou quando executado como root. A consulta usa apenas metadados Git locais, não obtém o SHA remoto atual; essa comparação será feita separadamente no GitHub, sem modificar a cópia das VMs.

Antes dessa janela: confirmar autorização/snapshot de referência, versão real do checkout, permissões, impacto da coleta, convenções de evidência privada e caminhos ativos. Somente após revisar o resultado sintético/CI e o registro de mudança autorizado fornecer os comandos definitivos por VM.

## Limitações e critérios de aceite

1. **CI PASS não significa VM sincronizada.** HEAD local pode divergir de imagem Docker em uso, bind mounts, rulesets ativos e overlays locais.
2. **Branch/commits não provam proteção de dados.** Resultados de saída devem ser revisados antes de compartilhar com GitHub/Trello, inclusive SHAs internos.
3. **Sem inventário de arquivos ignorados.** O código não inventaria `.env`, volumes nem dados secretos; por isso, a ausência na saída não prova ausência na VM.
4. **Sem chamada remota ou runtime.** Não verifica MFA, Twingate, TLS, Wazuh 80710, Ferret v5, Bacula, OpenBao ou pfSense; esses são gates separados de homologação.
5. **Falha fechada.** Identidade inesperada, execução como root, raiz errada, Git ausente ou hash inválido abortam sem fallback que altere algo.

## Critério para a PR #215

Não mesclar o kit histórico inteiro. O `bootstrap.sh` usa PIN antigo e instala arquivos; `ce-common.sh` usa `curl --insecure`, consulta contêineres e produz evidências em HOME; os documentos retratam condições anteriores ao Pentest B concluído. Para aproveitamento futuro, separar as rotinas com TLS verificado, dados sanitizados e testes próprios em PRs pequenos, sem executar os scripts legados.
