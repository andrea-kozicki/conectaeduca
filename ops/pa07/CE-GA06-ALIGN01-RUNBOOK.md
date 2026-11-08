# CE-GA06-ALIGN01 — Alinhamento do Ferret v5 (Web / CLI / manutenção)

**Data:** 08/11/2026. **Responsável:** Andréa Kozicki. **Máquina:** EP126 somente. **Objetivo:** compatibilizar as entradas Bash, Fish e Compose com a imagem v5 **que já foi implantada** por CE-GA06-CUT01.

## Razão da mudança

O serviço Web Ferret já executa `2.4.3+ce.pa07.v5` na EP126 (CE-GA06-CUT01, 16:43:56 BRT), com monitor systemd v5 ativo. Entretanto, o `deploy/interna/ferret/compose.yml` versionado em `main@04f88d27` ainda aponta para `public.ecr.aws/...:2.4.3@sha256:7a1b...`. As rotinas abaixo obtêm a imagem desse Compose:

- `scripts/dlp/processar_inbox_ferret.sh` — `docker compose config --images`, depois `docker run` CLI.
- `scripts/dlp/processar_inbox_ferret.fish` — `docker compose -f ... run` CLI.
- `scripts/bootstrap/subir_ferret.fish` — `docker compose -f ... up` do serviço.

**Sem alinhamento,** a UI v5 e a CLI podem ficar em versões diferentes e um `compose up` baseado apenas no arquivo antigo pode recriar a versão 2.4.3, divergindo do monitor v5.

## Remediação minimalista

Na **EP126 apenas**, atualizar de maneira atômica o arquivo `deploy/interna/ferret/compose.yml`, alterando **exatamente duas entradas** e nada mais:

```yaml
services:
  ferret:
    image: localhost/conectaeduca/ferret-scan:2.4.3-pa07-v5-candidate
    pull_policy: never
```

O restante do Compose — comandos, portas, UID, permissões, bind mounts, tmpfs, `cap_drop`, `read_only`, quotas e rede — permanece idêntico. A imagem candidata tem Docker Image ID fixo `sha256:535ec9efb590dbaaeca41123321d773ba6d26d338686d89605492380ae9e187d`; não há Docker pull/load/build.

A implementação dispensa substituir os três scripts de execução: eles já consomem o Compose principal. O `pull_policy: never` impede que Docker Compose baixe outra imagem ao utilizar o arquivo.

## Proteções e limites

- A instalação ocorre pelo `ops/pa07/ce_ga06_align01.py` executado **sem sudo** como `andrea.kiew` na EP126.
- Guarda `HEAD=04f88d275064a005d0ffcd4f9372a371c28c32d5`, hash original Git blob `9f4e17461d2179607343780fed922153050f1e86`, hash aprovado final `bf87c41606d96a7547ed05bd668f6b5fc242ecc4`, owner local da configuração e ausência de symlink.
- Verifica **somente** que contêiner e tag candidatos referenciam a mesma imagem ID aprovada e que `/health` informa `healthy` na versão v5; não executa varreduras, dados de teste ou pentest.
- Faz backup privado `$HOME/.CE-GA06-ALIGN01_BACKUP_<timestamp>/compose.yml`, pasta 0700/arquivo 0600, com hash verificado. Escreve nova versão via arquivo temporário no mesmo diretório, valida sintaxe `docker compose config --quiet`, substitui atomicamente e confere imagem efetiva por `config --images`.
- **Nenhum** comando `docker compose up/run`, `docker restart`, `systemctl restart`, `sudo`, `git reset/clean/pull`, alteração em dados persistentes, scripts Bash/Fish, Wazuh, OpenBao ou pfSense.
- O HEAD Git das VMs permanece `04f88d27`; na EP126, o Compose **fica modificado em relação à main de propósito** até sua futura incorporação controlada no GitHub. Não executar CE-RC08 novamente, nem `git restore`, `git reset --hard` ou merge sobre esse caminho.
- A PR deve ficar DRAFT até a reconciliação da configuração instalada. **Não mesclar inadvertidamente** uma imagem local da EP126 como baseline genérica de outras instalações sem considerar a portabilidade/supply chain.

## Evidência para fechamento desta implementação

```text
RUNTIME_V5=CONFIRMADO
BACKUP_COMPOSE=VERIFICADO
COMPOSE_IMAGEM=FERRET_V5
PULL_POLICY=NEVER
CONFIG_COMPOSE=VALIDADA
CLI_BASH_FISH_SELECAO=V5_PELO_COMPOSE
BOOTSTRAP_FISH_SELECAO=V5_PELO_COMPOSE
GIT_TRACKED_COMPOSE=MODIFICADO_INTENCIONALMENTE
CONTEINER_RECRIADO=NAO
SERVICOS_REINICIADOS=NAO
CE-GA06-ALIGN01_CONCLUIDO
```

**Esta prova é de seleção de imagem, não processamento funcional de inbox nem fechamento do PA-07 inteiro.** O resultado comportamental da UI após HTTP 403 fictício e a execução efetiva de CLI v5 com um artefato sintético permanecem provas pontuais distintas; Bacula/egress também não estão fechados.

## Rollback manual, apenas se exigido

A cópia privada preserva **exclusivamente o Compose anterior** com hash original. Qualquer reversão de configuração deve ser coordenada com a reversão da imagem Web e do drop-in de monitor v5: restaurar somente o Compose 2.4.3 enquanto o serviço continua v5 gera novamente risco de drift. Não apagar automaticamente backup nem dados.
