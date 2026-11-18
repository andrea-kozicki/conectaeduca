# GA-06 / PA-07 V5 — reconciliação da EP126

**Estado de referência:** 17/11/2026. **Escopo:** documentação e código-fonte; nenhuma implantação na VM.

## Arquitetura e limites

- O `deploy/interna/ferret/compose.yml` mantém a imagem oficial Ferret 2.4.3 fixada por digest.
- `pa07-v5/compose.pa07-v5.override.yml` é uma exceção **opcional**, específica do laboratório: seleciona uma imagem local e impede pull implícito. Não altera volumes, redes, portas ou privilégios do Compose-base.
- O TAR da imagem candidata **não é publicado**. Sua identidade e proveniência são registradas em `GA06_CANDIDATE_PROVENANCE.json`; o nome/tag local, isoladamente, não comprova integridade.
- `90-ga06-ferret-v5-healthcheck.conf` é um **modelo** de configuração systemd, não um instalador.

## Histórico das alterações e limites de aceite

- [PR #207](https://github.com/andrea-kozicki/conectaeduca/pull/207): origem da correção de interface do Ferret (PA-07), ainda em rascunho; por isso o template de healthcheck preserva a referência histórica `PR #207`.
- [PR #226](https://github.com/andrea-kozicki/conectaeduca/pull/226): procedimento de cutover controlado `CE-GA06-CUT01` e runbook operacional, também em rascunho. O corte executado em 08/11 foi documentado com preflight, backup e monitor saudáveis, **não** com restauração de rollback ensaiada.
- [PR #237](https://github.com/andrea-kozicki/conectaeduca/pull/237): concilia o código-fonte, o manifesto de custódia, o override opt-in e o processador CLI Bash com as observações da EP126. **Não** integra automaticamente as PRs #207/#226 e **não executa novo cutover**.
- A interface Web v5 foi observada em execução; não inferir que todos os caminhos CLI DLP utilizam a mesma imagem ou que o defeito funcional da interface teve correção integral homologada sem o teste específico correspondente.

## Verificações realizadas na EP126

Em 17/11/2026, no inventário e preflight local (CE-GIT-EP126-04 a 07):

| Controle | Resultado |
| --- | --- |
| Commit-base local/remoto | `04f88d275064a005d0ffcd4f9372a371c28c32d5` |
| Override Git blob | `decf0a8b5d5b18b6122b4afcc12a17e5ee5627f2` |
| Identidade da imagem Docker local | `sha256:535ec9efb590dbaaeca41123321d773ba6d26d338686d89605492380ae9e187d` |
| Usuário configurado na imagem | `1000:1000` |
| TAR/config/descritor/rootfs e comparação Compose | **PASS** (preflight local, saída 0) |
| Serviço Ferret | imagem candidata ativa, sem alteração pelo preflight |
| Autorização de nova implantação | **Não concedida por esses testes** |

O status `GA06_TAR_BYTES_VERIFIED_IN_CI=NAO` é esperado: o TAR não está disponível no CI. A conferência completa aconteceu **localmente**, sobre o TAR original autorizado para o laboratório.

## Como verificar sem implantar

Na máquina institucional autorizada, com Docker e acesso ao TAR custodiado, executar:

```bash
bash scripts/evidencias/ga06_preflight_tar_local.sh \
  --archive /caminho/privado/ferret-pa07-v5-candidate-docker-archive.tar \
  --override deploy/interna/ferret/pa07-v5/compose.pa07-v5.override.yml
```

O preflight valida a política do override, o hash e o conteúdo do TAR, a identidade local da imagem e a equivalência do Compose após a mudança limitada de imagem. Ele **não faz** `docker load`, `pull`, `up` ou reinício de serviço. Não publique arquivos `docker image inspect` completos: podem conter variáveis de ambiente.

## Bash e Fish

- **EP126 (Ubuntu):** o processador CLI Bash reconciliado em código-fonte é `scripts/dlp/processar_inbox_ferret.sh`, com snapshot protegido, `--network none`, restrições de contêiner e checagem da imagem candidata. Sua equivalência funcional end-to-end com o runtime Web v5 não foi demonstrada pelo CI.
- **openSUSE:** os scripts Fish existentes permanecem disponíveis. Eles seguem um caminho de processamento diferente e **não devem ser apresentados como equivalentes** aos controles específicos do processador Bash sem validação própria.
- A seleção automática da candidata por hostname/drop-in na EP126 é uma compatibilidade com o ambiente observado, **não uma regra de implantação genérica**. Sua substituição futura por uma configuração externa explícita requer ensaio e controle de mudança.

## Plano de reversão — documentação, não execução

**Estado da evidência:** o backup e o plano de rollback do corte GA-06 foram preparados e verificados em 08/11; **não houve ensaio de restauração** demonstrado. A conclusão desta PR não altera esse status. Antes de qualquer intervenção, a responsável e o suporte institucional devem aprovar janela, snapshots disponíveis, identificação da imagem baseline e procedimento de recuperação.

Sequência para um change control futuro, **somente por operador autorizado**:

1. Registrar o estado atual de imagem, Compose efetivo, healthcheck, timer, backups e indicadores mínimos de serviço, sem exportar `docker inspect` integral ou relatórios DLP brutos.
2. Suspender novos processamentos Ferret e pausar **somente** o monitor/timer do serviço durante a troca; confirmar custódia e integridade do backup prévio.
3. Recuperar a composição baseline fixada por digest, retirando da seleção operacional o override local v5; preservar volumes, configurações e dados. **Não** usar `docker compose down`, `prune` ou remoções em lote como atalho.
4. Remover/desabilitar apenas o drop-in de healthcheck específico v5, recarregar a configuração systemd e restaurar o monitor esperado da versão baseline. O Bash da EP126 seleciona automaticamente v5 pela combinação de hostname e presença desse drop-in; verificar explicitamente o retorno ao caminho baseline.
5. Validar `/health`, versão e identidade da imagem, timer, acesso esperado e um ensaio funcional mínimo do DLP, sem dados sensíveis reais. Registrar saída sintetizada, hashes e horário.
6. Em caso de falha, interromper novas mudanças e escalar ao suporte para decidir recuperação por backup ou snapshot **somente após testar sua restaurabilidade**. Não declarar rollback PASS baseado em plano ou backup isoladamente.

O script e o runbook operacionais históricos estão na PR #226, mas seus pré-requisitos de checkout/commit foram fixados para o estado de 08/11; **não reutilizar literalmente esse script após mudanças de `main` sem nova revisão e autorização**.

## Pendências antes de qualquer novo deploy

1. Validar o preflight no ambiente de destino e preservar evidências sem segredos.
2. Confirmar autorização institucional, plano atualizado e eventual ensaio autorizado de restauração/rollback.
3. Validar comportamento do DLP em execução, incluindo geração de eventos minimizados, sem expor relatórios brutos.
4. Revisar a paridade e a portabilidade dos scripts Fish em etapa separada.

Este registro reconcilia **código e evidências**. Ele não concede autorização de implantação nem declara o laboratório integralmente reproduzível sem o TAR sob custódia.
