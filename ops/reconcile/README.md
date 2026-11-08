# CE-RC01 — Reconciliação prática GitHub ↔ EP125/EP126 (08/11/2026)

**Objetivo:** comparar o Git local em `/opt/conectaeduca` com o SHA de `main` observado no GitHub e produzir um inventário dos serviços reais de cada VM, sem aplicar código, reiniciar serviços ou reabrir correções pendentes.

## Estado confirmado no GitHub

- Repositório: `andrea-kozicki/conectaeduca`; branch padrão `main` protegida.
- SHA de `main` observado em 08/11/2026: `b74ea581a0814d86a99b6b455d5569f12fa967e5` (**ponto de comparação histórico, não consulta remota dinâmica**).
- PR #215 já possui kit Fase 3, mas precisa de atualização: o preflight antigo verifica Connectors Twingate em Docker; agora EP125/EP126 usam serviços Linux nativos.
- PR #219 contém kit Pentest B em DRAFT; **não equivale a implantações realizadas**.

## Procedimento controlado

1. **Revisar este PR** e o arquivo `ce-rc01.sh`, incluindo origem da cópia e hash da versão.
2. Baixar `ops/reconcile/ce-rc01.sh` de **um commit fixo desta PR**, para arquivo privado em `$HOME`, nunca `curl | bash`. Verificar `git hash-object` do arquivo contra o blob SHA publicado e rodar `bash -n`.
3. Na EP125 (hostname exato `ep125-pucpr`): `bash ~/ce-rc01.sh EP125`.
4. Na EP126 (hostname exato `ep126-pucpr-br`): `bash ~/ce-rc01.sh EP126`.
5. Comparar resultados com este registro, **sem anexar arquivos de configuração, env, chaves ou segredos ao GitHub**. Os outputs são resumidos, mas ainda revisar imagens/nomes antes de publicar.

O script é **somente leitura**:
- não executa `sudo`, `sudo -s`, `git pull/fetch/reset`, `docker compose config`, `docker inspect` ou extração de env;
- não grava arquivos nem tenta trocar de branch;
- bloqueia execução em hostname diferente e não executa em openSUSE;
- imprime HEAD/branch, cache local `origin/main`, contagem de arquivos rastreados alterados e de arquivos não rastreados (sem divulgar seus nomes) nas áreas de cada VM, versão/estado do Connector nativo e lista restrita de containers;
- exclui arquivos ignorados pelo `.gitignore` da contagem de não rastreados; usa `GIT_OPTIONAL_LOCKS=0` para evitar locks opcionais;
- **não consulta o GitHub ao vivo**; o SHA de `main` é snapshot de 08/11.

## CE-RC02 — Triagem complementar (08/11)

Após as duas coletas CE-RC01, foi confirmado:
- EP125 no mesmo commit que o baseline remoto, 0 tracked alterados e 7 untracked nas áreas; Twingate systemd ativo, 3 contêineres da DMZ healthy.
- EP126 27 commits atrás do baseline remoto, 3 tracked alterados no conjunto e 3 untracked nas áreas; regra DLP Wazuh entre os tracked alterados; Twingate systemd ativo; OpenBao reportado `unhealthy`.
- Relatório factual: `docs/fase3/CE-RC01-CONCILIACAO-EP125-EP126-20261108.md`.

**Complemento disponível:** `ops/reconcile/ce-rc02.sh` classifica os 3 tracked modificados (sem imprimir seus caminhos, salvo detecção booleana da regra DLP já conhecida) e agrupa untracked por área, sem nomes; na EP126 consulta apenas estado/health/restarts do OpenBao por `docker inspect --format`, sem ENV, logs ou comandos no contêiner. Não usa `sudo`, `git fetch/pull/reset/clean`, `docker exec`, unseal ou restart.

Commit imutável do CE-RC02: `05fb622dc6d4b815592da46199c5ea7106068b9b`; blob SHA-1 Git esperado: `d7608f0efe0b82988a7e88a391bf80a2560ad05d`. Sintaxe Bash e Python compilada localmente, mas **ainda não executado nas VMs**.

Procedimento: baixar o script desse commit em `$HOME`, comparar `git hash-object` ao blob SHA, executar `bash -n`, então `bash ~/ce-rc02.sh` **em cada VM**. Revisar saída antes de publicar. Em seguida, decidir quais diferenças são correções efetivamente aplicadas no runtime, mudanças locais a preservar e pendências de PR.

## Como usar o relatório para implementar mudanças

| Evidência | Conduta |
|---|---|
| `HEAD_LOCAL` difere do SHA de `main` | Examinar commits/PRs específicos. Não fazer `git pull`/merge automático: a VM pode ter hotfix legítimo |
| `UNTRACKED_AREAS_TOTAL` maior que zero | Preservar overlays/configurações locais fora do Git. Não fazer `git clean` nem copiar esses arquivos para repositório público sem revisão de segredos. |
| `DIRTY_TRACKED_COUNT` maior que zero | Revisar *somente* caminhos de código explicitamente autorizados. Não substituir arquivos antes de preservar e comparar |
| Connector nativo ativo, Docker antigo parado | Atualizar **documentação e kit de deploy** para refletir systemd, sem reprovisionar tokens |
| Serviço Docker presente, mas checkout Git diverge | Fazer comparação de **manifestos públicos e imagens** por serviço, com backup/rollback e change control |
| Mudança depende de PR #203/#205/#206/#207/#213/#217 | Validar CI, preflight, snapshots, permissões e rollback; **não aplicar por causa deste kit** |

**Importante:** HEAD local igual a `main` **não prova** que o runtime esteja alinhado: a imagem de contêiner e as configurações efetivamente montadas podem ser diferentes das fontes Git. Essa checagem exige uma segunda reconciliação focalizada, serviço a serviço.

## Critérios de aceite

- Saída CE-RC01 de cada VM coletada sem erros nem exposição de credenciais;
- divergências classificadas como `codigo`, `configuracao`, `runtime`, `pendencia_PR` ou `permissao`;
- nenhuma mudança aplicada automaticamente;
- para qualquer delta real: PR específico + revisão + backup/snapshot + rollback + smoke/PA relevante;
- apresentação do Pentest B: 17/11/2026; não provocar cutovers de alto risco antes dos testes.
