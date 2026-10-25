# GA-06 / PA-07 — Ferret Scan UI v5: imagem candidata, gates e rollback para EP126

**Data:** 25/10/2026  
**Status:** PREPARAÇÃO DE CHANGE CONTROL; NÃO EXECUTAR DEPLOY SEM AUTORIZAÇÃO INSTITUCIONAL  
**Base:** Ferret Scan v2.4.3, upstream `a5156d1950df19276e6cfd8335603d73187a3841`, patch v4 e delta v5, PR ConectaEduca #207 (DRAFT).

## 1. O que comprovamos (homologação local pessoal)

- v4: 20/20 testes Node PASS; Go 1.26.10 compilou; Firefox local 127.0.0.1:18089 validou POST /scan HTTP 200 / results [], erro 403 **simulado no browser** e banner persistente.
- v5: 26/26 testes Node PASS, 0 FAIL; Go 1.26.10 compilou; binário `/home/andrea/GA06-Ferret-v5-jOvXM4fP/out/ferret-scan-v5` SHA-256 `98dcf3cdb196193faabd5f060c4722d2c4fb8f5be90ac8a5c95fed438edb37ee`.
- Firefox v5 local: `COMPLETED — 1/1` sem achados e exportação desabilitada; após HTTP 403 **sintético via window.fetch**: `Scan inconclusive`, painel `INCONCLUSIVE — 0/1` e `Export Results` desabilitado; permanência após espera confirmada verbalmente pela operadora, não por segunda captura cronometrada.
- **Nenhuma dessas evidências demonstra mudança na EP126.** Não promover o PR ou marcar achado resolvido no ambiente antes do deploy e reteste.

## 2. Baseline atual — NÃO ALTERAR POR PADRÃO

Arquivo: `deploy/interna/ferret/compose.yml`.

- Imagem: `public.ecr.aws/awslabs/ferret-scan:2.4.3@sha256:7a1b36050ae20a74632ac05b5c34e4aeb26b69836ca6703e10c1392b724b270f`.
- Publicação da Web UI no host: `127.0.0.1:18082:8080` por padrão; manter loopback.
- Root filesystem read-only, `cap_drop: ALL`, `no-new-privileges`, `pids_limit:128`, `mem_limit:1280m`, `cpus:2.00`, `tmpfs:/home/ferret/tmp` com UID/GID 1000; manter.
- Volumes locais **não versionados e potencialmente sensíveis**: `deploy/interna/ferret/.runtime/state` (supressões), `inbox`, `reports/raw`; preservar sem cópias no Git/Trello.
- Eventos sanitizados para Wazuh ficam fora do contêiner em `.runtime/events/dlp.jsonl`. Reteste do pipeline deve comprovar que conteúdo bruto não é enviado ao SIEM.
- A conta Ferret na imagem oficial tem UID/GID 1000; `TMPDIR=/home/ferret/tmp`; entrypoint `/ferret-scan` em imagem `scratch`. A candidata replica esses invariantes.
- Monitor existente `scripts/observabilidade/verificar_ferret_health.sh` exige `/health version=2.4.3` por padrão. **A candidata se identificará como `2.4.3+ce.pa07.v5` e NÃO será compatível sem ajuste explícito do monitor.**
- **CRÍTICO:** `scripts/dlp/processar_inbox_ferret.sh` deriva a imagem de `docker compose config --images` e inicia scanner CLI efêmero por `docker run`; a variante Fish usa `docker compose run`. Substituir apenas a Web UI deixa parte das operações na imagem antiga.

## 3. Artefatos preparados na branch do PR #207 (repo-only)

| Artefato | Função | Observação |
|---|---|---|
| `deploy/interna/ferret/pa07-v5/Containerfile` | imagem scratch, executável Go estático, UID1000 e diretórios de runtime | cópia de licença Apache do upstream; sem secrets |
| `scripts/evidencias/GA06_FERRET_V5_IMAGE_LOCAL.sh` | gera build Go com metadata de versão, imagem local, smoke loopback e TAR docker-archive | **somente openSUSE pessoal**; nunca publica/transfere/implanta |
| `deploy/interna/ferret/pa07-v5/compose.pa07-v5.override.yml` | troca `image` apenas mediante `FERRET_PA07_V5_IMAGE` e `-f` explícito | Compose oficial permanece inalterado |
| `scripts/dlp/processar_inbox_ferret.sh` e `.fish` | usam override **opcional** `FERRET_COMPOSE_OVERRIDE` também no pipeline de processamento | valor padrão inalterado |
| `scripts/bootstrap/subir_ferret.fish` | respeita override **opcional** na inicialização | observar que o bootstrap chama preparação de ACL e pode exigir sudo |

### Build da imagem candidata — SOMENTE no openSUSE pessoal

Não execute nas VMs. O código/fonte v5 validado permanece preservado. A candidata é recompilada com informações auditáveis em `/health`: versão `2.4.3+ce.pa07.v5`, revisão upstream mais marcador CE v5. **Este novo binário não terá obrigatoriamente o mesmo SHA-256 do binário preliminar v5 de homologação**, porque os `-ldflags` de versão são diferentes; guardar ambos.

Em Fish:

```fish
cd ~/Downloads
curl -fLsS --retry 2 \
  'https://raw.githubusercontent.com/andrea-kozicki/conectaeduca/fix/pa07-ferret-ui-fail-closed-review-20261025/scripts/evidencias/GA06_FERRET_V5_IMAGE_LOCAL.sh' \
  -o GA06_FERRET_V5_IMAGE_LOCAL.sh
# Antes de executar, conferir SHA Git blob informado no PR.
bash -n GA06_FERRET_V5_IMAGE_LOCAL.sh
bash GA06_FERRET_V5_IMAGE_LOCAL.sh
```

O script exige `opensuse-andrea`, rootless Podman e checkout v5 com patch v5 verificável. Usa apenas `docker.io/library/golang:1.26-bookworm` já baixada e `scratch` como imagem final. Constrói e testa contêiner **efêmero vinculado ao loopback com porta dinâmica**, limpa-o em EXIT, mantém a imagem candidata local e exporta o `docker-archive.tar` em pasta privada `~/GA06-Ferret-v5-image-XXXXXXXX`.

**Manifesto esperado:** `GA06_IMAGEM_RESULTADO.txt` com hashes SHA-256 (binário, source app.js, TAR), `IMAGEM_ID`, `HEALTH_SMOKE=PASS`, `APP_JS_V5_SERVIDO=PASS`, `EP126_ALTERADA=NAO`, `IMAGEM_PUBLICADA=NAO`. Se o script falhar, arquivar erro; **NÃO prosseguir**. Script criado mas execução pessoal dessa etapa ainda PENDENTE.

**Gate de supply chain:** a tag local é mutável; não usá-la como prova de imutabilidade. O operador deve confrontar a identidade imutável da imagem aprovada (`docker image inspect .Id`) com manifesto e hash do TAR após `docker load`, antes do `compose up`; preferir referência `@sha256` de registry institucional, se disponível. Não inventar digest de distribuição antes de push e inspeção. Arquivo TAR é artefato para posterior revisão, **não** autorização de transferência.

## 4. Preflight read-only na EP126 (apenas com operador autorizado)

Reconfirmar, sem mudar permissões, volumes nem contêiner:

```bash
BASE=deploy/interna/ferret/compose.yml
docker compose -f "$BASE" config --images
docker compose -f "$BASE" ps
docker compose -f "$BASE" ps -q ferret
docker image inspect 'public.ecr.aws/awslabs/ferret-scan:2.4.3@sha256:7a1b36050ae20a74632ac05b5c34e4aeb26b69836ca6703e10c1392b724b270f' --format '{{.Id}}'
systemctl is-active conectaeduca-ferret-healthcheck.timer
systemctl cat conectaeduca-ferret-healthcheck.service
```

Antes de qualquer corte, inventariar proprietário/ACL dos diretórios `.runtime`, o bind de loopback e a regra de rede; medir saúde pré-mudança e fazer cópia de recuperação **sob guarda institucional**, sem exportar dados de `state`, `inbox` ou `reports/raw` para chats/repositório.

**Gates de aprovação:** sudo operacional, custodiante do archive, janela, aprovação docente/suporte, digest ou image ID assinado, backup/rollback, downtime aceitável, checkpoint Wazuh 110113 e sanidade do processamento CLI.

## 5. Plano de rollout autorizado (NÃO EXECUTADO)

1. Suporte confere SHA-256 do archive aprovado no host de entrada e inspeciona `docker load`, imagem/versão/USER/entrypoint; registra `IMAGEM_ID`. Nenhum uso de tag `latest`. A imagem antiga por digest permanece disponível.
2. Definir explicitamente, em contexto **temporário e aprovado**, `FERRET_PA07_V5_IMAGE` com o nome local inspecionado; configurar `FERRET_COMPOSE_OVERRIDE` para o arquivo de override (em caminho absoluto) em todos os processadores operacionais que devam usar v5. **Não modificar permanentemente o Compose baseline.**
3. Fazer `docker compose -f BASE -f OVERRIDE config` e verificar: image v5, porta `127.0.0.1:18082`, quatro mounts originais, tmpfs, UID1000, read_only, cap_drop, no-new-privileges, CPU/mem/PIDs. Diferenças não aprovadas cancelam a operação.
4. Preparar drop-in **dedicado** para o serviço `conectaeduca-ferret-healthcheck.service` com `FERRET_EXPECTED_VERSION=2.4.3+ce.pa07.v5`. Preservar configuração anterior e preparar sua retirada no rollback; executar `systemctl daemon-reload` somente na janela autorizada.
5. Somente depois dos gates: `docker compose -f BASE -f OVERRIDE up -d --no-deps ferret`, acompanhado por operador; registrar timestamp, ID/digest da imagem efetivamente usada, health e logs **sanitizados**. Se houver falha, acionar rollback imediato; não desabilitar healthcheck para fazer parecer verde.
6. Reter caminho de retorno ao Compose baseline fixado. **Não apagar imagem antiga** nem o estado, nem remover supressões, nem ajustar ACLs por conveniência.
7. Retestes de navegador/HTTP (sucesso legítimo e HTTP 403 **sintético claramente rotulado**), regressão da aplicação e CLI (arquivo fictício, permissão, JSON compatível com `scripts/dlp/sanitizar_ferret.py`), evento minimizado Wazuh agente 002/regra 110113, ausência de dados brutos no SIEM, sem despejar valores.
8. Só fechar a issue/PA-07 se provas de todas as superfícies e registro de change control sustentarem isso.

**Atenção ao monitor:** o serviço systemd atual possui `ProtectSystem=strict` e usa versão exata; o override ambiental deve ser tratado como mudança operacional formal. Confirmar execução manual `/health` primeiro, depois timer. No rollback remover apenas o drop-in criado para GA-06; não usar `systemctl revert` genericamente se houver personalizações anteriores.

## 6. Rollback autorizado, se ocorrer regressão

1. Interromper testes e isolar evidências sanitizadas; confirmar que old image/digest continua presente no Docker.
2. Restaurar somente o Compose baseline (sem `-f` override e sem `FERRET_PA07_V5_IMAGE`) em janela autorizada: `docker compose -f BASE up -d --no-deps ferret`, preservando os mesmos volumes, portas e rede.
3. Retirar o drop-in específico GA-06 do monitor de health (com cópia anterior documentada) e recarregar systemd sob responsabilidade do suporte. Voltar a `FERRET_EXPECTED_VERSION=2.4.3`.
4. Garantir que scripts CLI/bootstraps **não** conservem `FERRET_COMPOSE_OVERRIDE` no ambiente; confirmar `config --images` do pipeline e serviço retornou ao digest baseline.
5. Validar `/health`, permissões, relatórios sintéticos, logs sanitizados e Wazuh; medir tempo de recuperação e documentar motivo do rollback.

## 7. Critérios de aceite e situação real

- [x] v4 e v5 testadas localmente (Node 20/20, Node 26/26, Go, Firefox com 403 sintético).
- [x] Preparação documental da imagem candidata + override opt-in, preservado baseline.
- [ ] Construção e smoke **reais** da imagem candidata local — **a executar no openSUSE**.
- [ ] Revisão do archive/manifesto e aprovação do operador.
- [ ] Preflight read-only EP126, planejamento de change e rollback homologado.
- [ ] Plano de versão do health timer testado e confirmado.
- [ ] Substituição autorizada do serviço Docker EP126 e conferência de imagem ID/portas/volumes/ACL.
- [ ] CLI de inbox e sanitização + Wazuh E2E retestados com dados fictícios.
- [ ] Critérios de fechamento assinados e PR #207 promovido conforme governança.

**Resultado operacional de 25/10/2026: PREPARADO PARA REVISÃO, NÃO IMPLANTADO.**


## 8. Diagnóstico Podman rootless e retomada do smoke (25/10)

**Observado no openSUSE pessoal:** `GA06_FERRET_V5_IMAGE_LOCAL.sh` avançou até `ETAPA=4_SMOKE_ISOLADO_EM_LOOPBACK`; as etapas de compilação e build de imagem foram ultrapassadas, mas o `podman run` falhou com `Error: unknown mount option "uid=1000": invalid mount option`. Portanto **NÃO houve health smoke aprovado, upload smoke, geração de manifesto ou archive nessa primeira tentativa**.

**Causa específica:** `podman run --tmpfs` nesta configuração rootless rejeita as opções de propriedade `uid=1000,gid=1000`, embora o Compose de produção use tais opções via Docker. Podman documenta o uso de `mode=1777` em tmpfs, mas isso **não equivale** à montagem Docker protegida modo 0700 e UID/GID1000 no ambiente operacional.

**Correção documental e de script:** o smoke **local** no openSUSE utiliza `--tmpfs /home/ferret/tmp:rw,nosuid,nodev,noexec,size=256m,mode=1777`, com sticky bit e restrito a um contêiner efêmero de usuário não-root; o Compose oficial permanece sem alterações. O script `scripts/evidencias/GA06_FERRET_V5_IMAGE_RESUME_LOCAL.sh` retoma a imagem **já construída** no diretório `/home/andrea/GA06-Ferret-v5-image-9oIUg369`, faz GET `/health`, verifica o JS servido, executa POST `/scan` com arquivo fictício para detectar falta de escrita temporária e exporta TAR/manifesto somente após aprovação. Nenhum novo build/VM/deploy/registry push.

**Gates remanescentes:** confirmar na EP126, durante change control, **o tmpfs real Docker 0700 UID/GID1000**, dono, modo, escrita efetiva como UID1000, ACL e rollback. Smoke com modo 1777 local não satisfaz esse gate de hardening. O PR permanece DRAFT, mudança EP126 não realizada.
