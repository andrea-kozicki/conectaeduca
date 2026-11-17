# GA-06 / PA-07 V5 — reconciliação da EP126

**Estado de referência:** 17/11/2026. **Escopo:** documentação e código-fonte; nenhuma implantação na VM.

## Arquitetura e limites

- O `deploy/interna/ferret/compose.yml` mantém a imagem oficial Ferret 2.4.3 fixada por digest.
- `pa07-v5/compose.pa07-v5.override.yml` é uma exceção **opcional**, específica do laboratório: seleciona uma imagem local e impede pull implícito. Não altera volumes, redes, portas ou privilégios do Compose-base.
- O TAR da imagem candidata **não é publicado**. Sua identidade e proveniência são registradas em `GA06_CANDIDATE_PROVENANCE.json`; o nome/tag local, isoladamente, não comprova integridade.
- `90-ga06-ferret-v5-healthcheck.conf` é um **modelo** de configuração systemd, não um instalador.

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

- **EP126 (Ubuntu):** o processamento DLP operacional é a versão `scripts/dlp/processar_inbox_ferret.sh`, com snapshot protegido, `--network none`, restrições de contêiner e checagem da imagem candidata.
- **openSUSE:** os scripts Fish existentes permanecem disponíveis. Eles seguem um caminho de processamento diferente e **não devem ser apresentados como equivalentes** aos controles específicos do processador Bash sem validação própria.
- A seleção automática da candidata por hostname/drop-in na EP126 é uma compatibilidade com o ambiente observado, **não uma regra de implantação genérica**. Sua substituição futura por uma configuração externa explícita requer ensaio e controle de mudança.

## Pendências antes de qualquer novo deploy

1. Validar o preflight no ambiente de destino e preservar evidências sem segredos.
2. Confirmar autorização institucional e plano de rollback.
3. Validar comportamento do DLP em execução, incluindo geração de eventos minimizados, sem expor relatórios brutos.
4. Revisar a paridade e a portabilidade dos scripts Fish em etapa separada.

Este registro reconcilia **código e evidências**. Ele não concede autorização de implantação nem declara o laboratório integralmente reproduzível sem o TAR sob custódia.
