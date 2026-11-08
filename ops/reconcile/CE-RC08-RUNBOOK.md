# CE-RC08 — Conciliação controlada dos checkouts EP125 e EP126

**Data:** 08/11/2026. **Responsável:** Andréa Kozicki. **Propósito:** alinhar exclusivamente o Git local das duas VMs com a `main` após os merges das PRs #223 e #222, preservando arquivos cuja identidade já foi comprovada por CE-RC04/05. O script **não faz deploy**, `docker compose`, reinicialização, unseal, atualização do Twingate ou ajuste pfSense.

## Referências fixas

- Commit GitHub de destino: `04f88d275064a005d0ffcd4f9372a371c28c32d5`.
- EP125 (DMZ): HEAD esperado `b74ea581a0814d86a99b6b455d5569f12fa967e5`, 4 caminhos versionados diferentes no destino. Preserva os **bytes** do overlay local `deploy/dmz/compose.audit-persistent.yml` que agora está rastreado na main, sem substituí-lo.
- EP126 (intranet): HEAD esperado `4bf7ac688b1ea738cd158f03a20b07732cdd90a3`, 14 caminhos versionados diferentes no destino. Preserva os **bytes** dos 2 scripts DLP e da regra Wazuh locais idênticos à main nova, sem substituí-los.
- Outros arquivos untracked/ignored continuam locais, sem `git clean`.
- `origin` deve corresponder ao repositório GitHub `andrea-kozicki/conectaeduca`; `FETCH_HEAD` deve ser exatamente o commit fixado. Se a `main` avançar, o script **aborta**.
- Os caminhos que efetivamente precisarem de escrita no working tree passam por verificação de mounts Docker; qualquer bind que os alcance **bloqueia** a execução.

## Estratégia de baixo impacto

1. Verificar host/branch/HEAD/estado Git da coleta CE-RC04, ausência de staged/conflitos, origem GitHub, target e hashes de cada arquivo já comprovado.
2. Bloquear colisões inesperadas entre arquivos locais e novos arquivos da main.
3. Copiar os arquivos existentes afetados para diretório privado `$HOME/.CE-RC08_BACKUP_<VM>_<timestamp>`, conferir os hashes das cópias.
4. Executar **`git reset --mixed <SHA_VALIDADO>`** de maneira controlada: este modo atualiza somente `HEAD` e índice Git, **não apaga nem reescreve o conteúdo dos arquivos no working tree**. Não é `--hard`.
5. Executar `git restore --worktree` **somente** para os caminhos diferentes que ainda precisam receber a versão do commit validado, protegidos pela checagem de bind. Os arquivos que já eram idênticos à nova main não são restaurados nem substituídos.
6. Conferir HEAD final, arquivos rastreados sem alterações e hashes dos arquivos preservados; conservar o backup local privado. Um erro após o reset não provoca rollback automático destrutivo: interromper e examinar estado/backup.

**Limite:** o Git pode atualizar fontes locais adicionais sem reiniciar serviços. Os controles preservam os binds Docker conhecidos; não substituem aprovação de mudança, nem garantem ausência de consumidores não-Docker dos caminhos alterados. Evitar usar em meio a operação de produção crítica; contexto é laboratório acadêmico. Se houver bloqueio ou divergência, não forçar um git pull/reset/hard ou remoção de arquivos.

## Execução

Baixar somente a versão imutável da branch/commit, conferir o blob Git e sintaxe AST antes de executar. Executar **EP125 primeiro** e examinar `CE-RC08_CONCLUIDO`; **somente depois EP126**.

Script: `ops/reconcile/ce-rc08-update-vms.py`. O parâmetro obrigatório é `--apply` (sem ele a operação é recusada). Os resultados mostram apenas contagens, hashes de commits, diretório privado do backup, códigos de status; nenhuma chave, senha, variável de ambiente ou conteúdo de arquivo é publicado.

Não executar por sudo. Se `CE-RC08_ABORTADO`, enviar somente a linha de erro e o cabeçalho, sem exibir conteúdo do backup.

## Evidências e pós-condições

- `HEAD_FINAL=04f88d275064a005d0ffcd4f9372a371c28c32d5` em cada VM.
- `WORKTREE_TRACKED=SEM_ALTERACOES`.
- Preservação de `compose.audit-persistent.yml` EP125 e arquivos DLP/Wazuh EP126 comprovada por hashes.
- Sem intervenção na arquitetura Zero Trust, OpenBao, Docker runtime ou pfSense.
- Pendências permanecem: PA-06 retenção/rotação, PA-07 E2E completo, PA-02 GA-08 cutover, OpenBao selado e arquivos untracked não classificados.
