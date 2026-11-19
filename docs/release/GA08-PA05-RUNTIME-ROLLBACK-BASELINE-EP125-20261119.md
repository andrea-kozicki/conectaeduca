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
3. Origem aprovada dos 10 Compose em `deploy/dmz`, overlay PA-05 em
   `$HOME/.config/conectaeduca/pa05` e 3 overlays GA08 em `deploy/dmz`.
4. Existencia de todas as fontes, rejeitando links simbolicos, arquivos
   ausentes, origem alternativa, ordem diferente e imagem PHP antiga.

O script usa apenas leituras filtradas de `docker inspect` e testes de
existencia local. Nao consulta `Config.Env`, nao despeja configuracoes,
segredos, certificados, mounts privados ou logs, nao cria arquivos e nao
chama `docker compose up/down/config`. Ele aceita ser executado no terminal
EP125 a partir da pasta de downloads, sem instalar no checkout.

## Gates para um driver realmente executavel

- [ ] Preflight de 14/11 arquivos aprovado na EP125, incluindo a origem
  exata da camada PA-05 e o overlay local de auditoria.
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
