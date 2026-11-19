# GA08 / PA05 — baseline real e preparacao do rollback EP125 (19/11/2026)

**Estado:** inventario operacional fornecido pela responsavel; script de
reconciliacao somente leitura versionado; **nenhum novo rollback/cutover
autorizado ou executado**. PR #217 permanece DRAFT.

## Runtime observado em 19/11/2026

A leitura dos labels `com.docker.compose.project.config_files` nos tres
containers EP125 (`php`, `nginx`, `waf`) demonstrou a **mesma sequencia de 14
arquivos**. Imagens configuradas: `conectaeduca/php-fpm:pa05-10328ab6`,
`conectaeduca/nginx:dmz` e `conectaeduca/waf:dmz`. A auditoria separada do
mesmo dia reportou 22 testes OK, zero alertas e 5 informativos. Isso prova
metadados e saude Docker, mas nao um teste de restauracao.

**Correcao de proveniencia (19/11):** um preflight inicialmente exigiu que
os overlays 12–14 viessem diretamente de `/opt/conectaeduca/deploy/dmz` e
falhou em modo seguro. Diagnostico dirigido da responsavel no PHP mostrou
que os **tres arquivos existem em copias no HOME**. Isso nao e, por si, uma
divergencia funcional: uma copia externa pode ser a fonte exata do Compose
usado no cutover. O preflight foi revisado para aceitar fontes GA08 sob HOME
**somente quando os tres arquivos tiverem os SHA-256 fixados dos candidatos
revisados no GitHub**, sem links simbolicos, sem escrita por grupo/terceiros
e com propriedade do operador. A ordem e igualdade entre containers
continuam obrigatorias. Nao houve modificacao dos arquivos na EP125.

**Evidencia recebida da EP125:** o comando de reconciliacao retornou
`CE_GA08_PA05_PREFLIGHT=PASS_METADATA_E_FONTES` com `14_MATCH`,
`11_IDENTIFICADOS`, `3_HEALTHY`, `FONTES_LOCALIZADAS=14` e
`GA08_CANDIDATOS_SHA256=3_MATCH`. O proprio resultado confirma
`ROLLBACK_FUNCIONAL=NAO_ENSAIADO` e `SERVICOS_MODIFICADOS=NAO`.

**Evidencia adicional recebida da EP125:** `--check-compose` executado com
sucesso na propria VM, com `COMPOSE11_SINTAXE_SEM_INTERPOLACAO=PASS` e
`COMPOSE14_SINTAXE_SEM_INTERPOLACAO=PASS`. Os 14 arquivos e os tres hashes
GA08 continuaram correspondendo ao baseline; `SERVICOS_MODIFICADOS=NAO`.
Esta checagem valida os dois modelos estaticos, **nao** a interpolacao
efetiva de `.env`/variaveis do shell, a aplicacao ou uma restauracao.

**Inventario de proveniencia de interpolacao recebido da EP125:**
`WORKDIR_LABEL=3_IGUAIS`, `ENVFILE_LABEL=NAO_REGISTRADO`,
`DOTENV_REPO=AUSENTE`, `DOTENV_DMZ=AUSENTE`,
`SEGREDOS_EXIBIDOS=NAO` e `SERVICOS_MODIFICADOS=NAO`.
Isto confirma que os tres containers concordam quanto ao diretorio de
trabalho declarado, mas **nao** identifica as variaveis e os arquivos
usados no cutover original. Ausencia do label e destes dois `.env`
nao prova ausencia de fontes externas, de variaveis temporarias do
shell ou de um wrapper de implantacao. O gate de configuracao efetiva
continua pendente; nao executar `docker compose config --environment`
nem divulgar valores de ambiente em logs/evidencias.

| Ordem | Arquivo Compose | Papel no retorno |
|---:|---|---|
| 01 | `compose.yml` | Base |
| 02 | `compose.database.yml` | Base |
| 03 | `compose.app-secrets.yml` | Base |
| 04 | `compose.waf.yml` | Base |
| 05 | `compose.waf-tls.yml` | Base |
| 06 | `compose.waf-policy.yml` | Base |
| 07 | `compose.host.yml` | Base |
| 08 | `compose.vm.yml` | Base |
| 09 | `compose.database-tls.yml` | Base |
| 10 | `compose.audit-persistent.yml` | Base local, preservar |
| 11 | `compose.pa05-10328ab6.yml` | **PA-05, preservar** |
| 12 | `compose.ga08-socket.candidate.yml` | GA08 |
| 13 | `compose.ga08-dual-socket.candidate.yml` | GA08 |
| 14 | `compose.ga08-runtimefix.candidate.yml` | GA08 |

**Modelo de rollback apenas para planejamento:** o alvo sem GA08 e formado
pelos arquivos **01–11**, preservando a imagem PHP PA-05 e os overlays de
auditoria, TLS e segredos. O runtime atual utiliza **01–14**. A retirada dos
overlays GA08 nao foi testada, e a equivalencia da configuracao efetiva
`docker compose config` ainda precisa ser demonstrada com o ambiente real.

O driver historico `scripts/ga08-change-control.py` corresponde a um baseline
anterior de **9/10 arquivos**. A correcao de 19/11 adicionou uma barreira que
recusa mutacoes desse driver na presenca da PA-05. **Nao utilizar esse driver
para restaurar a EP125 atual**, nem copiar um comando `docker compose up`
simples sem o contexto e a ordem de overlays aprovados.

## Novo preflight nao mutante

`scripts/ga08-pa05-recovery-preflight-ep125.py` valida, sem sudo e sem
modificar containers:

1. Identidade exata dos tres containers e imagens, saude e reinicializacoes.
2. Sequencia completa de 14 arquivos, igual nos tres servicos.
3. Origem exata dos 10 Compose em `deploy/dmz` e da PA-05 em
   `$HOME/.config/conectaeduca/pa05`. Os 3 overlays GA08 podem vir do
   checkout ou de copias sob HOME com hashes SHA-256 aprovados fixados.
4. Existencia das fontes, integridade dos tres overlays GA08, propriedade e
   permissao segura das copias privadas, rejeicao de links simbolicos,
   ordem divergente ou imagem PHP antiga.

O script usa apenas leituras filtradas de `docker inspect`, metadados de
arquivos e leitura dos tres overlays GA08 **nao secretos** para calcular
SHA-256. Nao consulta `Config.Env`, nao despeja configuracoes,
segredos, certificados, mounts privados ou logs, nao cria arquivos e nao
chama `docker compose up/down`; no modo padrao nao chama nem `config`.
Ele aceita ser executado no terminal
EP125 a partir da pasta de downloads, sem instalar no checkout.

**Gate estrutural opcional (apos PASS de proveniencia):** executar a versao
atualizada do mesmo script com `--check-compose`. Ele invoca somente
`docker compose ... config --no-interpolate --no-env-resolution --quiet`
para os 11 arquivos de base e para os 14 ativos, utilizando os caminhos
reais dos labels. Os parametros inibem interpolacao de variaveis e
resolucao de arquivos de ambiente; stdout/stderr sao capturados e jamais
exibidos. Em caso de erro, somente o conjunto 11/14 e o motivo classificado
sao impressos. **PASS estrutural NAO prova a configuracao efetiva
interpolada nem recuperabilidade funcional**. A etapa de valores reais e
digest privado permanece em aberto.

## Gates para um driver realmente executavel

- [x] Preflight de 14/11 arquivos aprovado na EP125, incluindo a origem
  exata da camada PA-05 e o overlay local de auditoria, integridade dos
  tres candidatos GA08 e validacao estrutural sem interpolacao.
- [ ] Fonte protegida do ambiente de interpolacao Compose preservada para
  **restauracao mesmo com containers indisponiveis**; nao gerar `.env` falso.
- [ ] `docker compose config` das pilhas 14 e 11 com os mesmos valores
  aprovados; digests efetivos fixados em manifesto privado e comparados antes
  de qualquer recriacao.
- [ ] Imagem PHP PA-05 e demais IDs de imagem presentes e fixados; rollback
  nao pode substituir PHP por baseline pre-PA-05.
- [ ] Global lock por host/projeto, interlocks, snapshot recuperavel adequado
  ao estado atual, janela e aprovacao consciente da responsavel.
- [ ] Simulacao offline de drift/falha, ensaio controlado e plano de contingencia
  se a aplicacao nao responder depois da mudanca.
- [ ] Retestes dirigidos HTTPS/CRS/PHP–SQL e isolamento de backends, sem
  expor segredos ou alterar pfSense.

**Decisao:** a correspondencia de 14 labels e o preflight de arquivos sao
necessarios, mas **nao tornam o retorno executavel automaticamente**. O
driver de recuperacao v2 ainda precisa ser desenvolvido e autorizado apos
esses gates. Sem merge operacional ou alteracao de VM por esta etapa.
