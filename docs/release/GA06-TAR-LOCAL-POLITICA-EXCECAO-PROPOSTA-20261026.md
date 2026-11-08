# GA-06 — Exceção controlada para distribuição local por TAR (proposta)

**26/10/2026, PR #207 DRAFT.** Escolha da responsável pelo projeto: **manter o Ferret v5 como docker-archive local**, sem publicação em registry nesta fase. Isso é uma **decisão de proposta técnica**, NÃO constitui a autorização institucional de implantação.

## 1. Motivação e limites

A imagem aprovada em teste de homologação isolada na EP126 foi transferida via TAR e importada no Docker 29 com containerd snapshotter. Não existe digest de distribuição publicado em registry. Logo, **nenhum hash de config do TAR nem ID de descriptor Docker deve ser escrito como se fosse `registry/repo@sha256`**.

O `Supply Chain Build Gate` global exigia `@sha256:` literal para imagens externas. A antiga expressão `${FERRET_PA07_V5_IMAGE:?...}` falhava, corretamente, por não provar identidade imutável. A solução não é relaxar a exigência para todas as imagens, mas **aprovar tecnicamente um caminho especial e estrito**, verificável antes de qualquer deploy.

## 2. Contrato offline GA-06 (somente opt-in)

Arquivo `deploy/interna/ferret/pa07-v5/compose.pa07-v5.override.yml`:
- Serviço **ferret** somente;
- `image: localhost/conectaeduca/ferret-scan:2.4.3-pa07-v5-candidate` (**alias local, não digest imutável**);
- `pull_policy: never` (se a imagem faltar, deve falhar; nunca buscar na Internet);
- sem volumes, ports, networks, build, priviliged ou overrides adicionais.
- O Compose oficial `deploy/interna/ferret/compose.yml` permanece **inalterado**, com Ferret 2.4.3 por digest de registry. O override só vale quando explicitamente adicionado com `-f`.

Segundo [Docker Compose Specification](https://docs.docker.com/reference/compose-file/services/#pull_policy), `never` evita pull de registry e gera erro se não houver imagem local. O alias sozinho é mutável; a identidade precisa ser conferida **fora** do Compose em cada gate de uso.

## 3. Custódia e checagem na CI

`GA06_CANDIDATE_PROVENANCE.json` guarda três identificadores **não intercambiáveis** observados no material de 25/10:

| Objeto | SHA-256 registrado |
|---|---|
| Arquivo docker-archive TAR | `5786c56b47d7bb93604126e30cfbfb4fc549f5b1f791262fbe591555ead785a2` |
| Config JSON do TAR | `1fab3fc1c35e4e33210cfd306364dc3ce672d16cd33f0505d51214647e6033ce` |
| Docker 29 descriptor/Image ID visto na EP126 | `535ec9efb590dbaaeca41123321d773ba6d26d338686d89605492380ae9e187d` |

O script `scripts/evidencias/ga06_validar_politica_tar.py` testa SHA registrado contra o valor de custódia fixado no código, campos de versão, usuário `1000:1000`, plataforma `linux/amd64`, sete camadas e **conteúdo mínimo exato** do overlay. `tests/python/test_ga06_offline_tar_policy.py` exercita 12 cenários sintéticos, incluindo hash alterado, `latest`, mudança de `pull_policy`, porta nova e `build` indevido.

O workflow `.github/workflows/supply-chain-build.yml` só reconhece **este caminho específico** após execução bem-sucedida do validador. **Todas as demais imagens externas continuam obrigadas ao digest de registry.** O restante do workflow — build proofs de Nginx e Bacula/PgBouncer — permanece ativo.

**Limitação da CI:** o TAR real *não é armazenado no GitHub Actions*. A CI confere a integridade do **contrato e dos hashes registrados**, mas **não os bytes do TAR nem uma engine Docker da EP126**. Não interpretar `Supply Chain Build Gate=PASS` como aprovação de imagem operacional ou de mudança.

## 4. Preflight obrigatório antes de qualquer troca da imagem

Foi criado `scripts/evidencias/ga06_preflight_tar_local.sh`, somente leitura, sem `sudo`, `docker load`, `docker pull`, `docker compose up` ou restart. Ele:
1. Exige um arquivo TAR regular, local, não symlink; não o extrai.
2. Verifica SHA do TAR, `manifest.json` interno, JSON config, UID, versão, plataforma e sete camadas por `ga06_validar_proveniencia_offline.py`.
3. Lê o `docker image inspect` da referência local; confronta descriptor/Image ID e RootFS do Docker 29 com o manifesto. Guarda `inspect` completo em diretório temporário **privado 0700**, remove na saída e **não imprime ENV**.
4. Compara `docker compose config --format json` da base contra o overlay; **a única diferença autorizada é `image` e `pull_policy`**. Saída apenas PASS/FAIL, sem variáveis completas do Compose.

**Executar somente quando houver aprovação para a leitura no host destino e artefato TAR sob custódia, sem mudar o serviço:**

```bash
# EP126, host e janela autorizados; TAR privado previamente conferido.
cd /opt/conectaeduca
bash scripts/evidencias/ga06_preflight_tar_local.sh \
  --archive /CAMINHO_PRIVADO_APROVADO/ferret-pa07-v5-candidate-docker-archive.tar
```

**Não executar `docker load` nesta checagem**: ela exige imagem já importada e só a inspeciona. A candidata já foi importada em teste isolado anterior; após manutenção, verificar estado atual e autorização antes de presumir presença.

Para **futura inicialização supervisionada**, `scripts/bootstrap/subir_ferret.fish` exige `FERRET_PA07_V5_ARCHIVE` e executa esse mesmo preflight antes de preparar runtime ou subir o serviço. Os processadores Bash/Fish da inbox conferem o Image ID local contra o manifesto (Bash também usa `docker run --pull=never` para a candidata). O monitor da versão HTTP precisa de ajuste específico `FERRET_EXPECTED_VERSION=2.4.3+ce.pa07.v5`, só em change control.

## 5. Gates ainda abertos — não podem ser dispensados

- [ ] **Aprovação formal institucional** dessa exceção de TAR offline, do host, custodiante, janela, responsáveis e plano de rollback.
- [ ] Tarball original preservado na cadeia de custódia e verificado no host autorizado após manutenção (não carregar/sobrescrever sem autorização).
- [ ] Preflight `GA06_PREFLIGHT=PASS` na EP126 com imagem já importada, UID/RootFS/Compose equivalentes, sem segredos em logs.
- [ ] Escrita efetiva em `tmpfs` 0700 UID1000 e scanner CLI real com dados sintéticos.
- [ ] Integração `inbox→raw→JSONL→Wazuh` e `wazuh-logtest` de regras 110101/110113 com dados fictícios, compatibilização PR #206.
- [ ] Ajuste controlado do health monitor, reteste de UI v5 e rollback ao digest upstream 2.4.3.
- [ ] Aprovação do PR #207 e dos PRs relacionados; **nenhum merge/deploy apenas porque a CI ficou verde**.

**Status:** exceção técnica implementada e testável na branch DRAFT. A autoridade institucional ainda pode rejeitá-la; nesse caso, não contornar a política e optar por registry aprovado ou suspender implantação.

**Nota:** o preflight exige `docker compose config` disponível; este documento não comprova a instalação ou a autorização de uso do runtime na EP126 após a manutenção.
