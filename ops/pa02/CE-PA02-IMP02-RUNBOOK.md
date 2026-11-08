# CE-PA02-IMP02 — reconstrução OCI com Python sem Skopeo

**EP125 — 08/11/2026. Responsável: Andréa Kozicki.**

## Precedente e limitação
Em 08/11/2026 às 20:05:47 BRT, o comando IMP01 foi validado, mas abortou em:
```text
SCRIPT_IMP01_VALIDADO
FERRAMENTA_SKOPEO=NAO_INSTALADA
CE-PA02-IMP01_ABORTADO=SKOPEO_AUSENTE_NAO_INSTALAR_AUTOMATICAMENTE
```
O programa aborta no preflight, antes de converter imagens. Não instalar Skopeo nem contornar por `sudo`.

IMP02 (`ops/pa02/ce_pa02_imp02.py --materialize`) é um plano alternativo que usa **apenas a biblioteca padrão de Python 3**. Não depende de downloads, Skopeo, Podman, Buildah, Docker image load ou serviços novos. Não transforma um layout OCI em imagem carregada no daemon: **é materialização de artefatos, não prova de importação/rollback real em outro motor**.

## Operação
1. Identidade `andrea.kiew`, hostname EP125, HEAD de `/opt/conectaeduca` congelado; não usa `sudo`.
2. Confere pacote privado RC01 `CE-PA02-RC01-20261108-183146` e manifesto SHA256 em 0600/0700, 3 serviços healthy e refs, IDs e container IDs baseline. Confere imagem PHP PA05 ativa.
3. Lê `manifest.json` **interno** do `docker-images.tar.gz` e exige exatamente três refs Docker, com config/layers definidos. Verifica reserva livre de disco antes de escrever.
4. Cria uma única árvore OCI em `~/.local/share/conectaeduca/pa02-recovery/CE-PA02-IMP02-YYYYMMDD-HHMMSS/` privada (0700); ela contém um `index.json` com descritores **php, nginx, waf**, `oci-layout` e diretório de `blobs/sha256` deduplicados. Nunca escreve dentro do RC01.
5. Copia somente configs/layers referenciados para blobs endereçados por SHA256, em streaming e com arquivos `.partial` exclusivos. Rejeita nomes TAR perigosos, entradas ausentes/duplicadas e digest de blob OCI divergente. Quando layer for gzip, calcula seu `DiffID` sobre o conteúdo descomprimido com limite de tamanho e sem extrair caminhos no filesystem.
6. Compara `rootfs.diff_ids` de cada config exportado aos hashes dos layers e aos `RootFS.Layers` das imagens atualmente healthy. Gera manifests OCI locais por serviço, verifica hash/size de cada descriptor e do `index.json`.
7. Saída final `CE-PA02-IMP02_CONCLUIDO` significa: TAR Docker RC01 usado como fonte real, arquivos OCI materializados e verificáveis, imagem PHP PA05 preservada. Teste positivo e negativo no GitHub Actions (fixture de três imagens e blob adulterado rejeitado). Não exibe conteúdo de imagens, segredos ou valores de ambiente.

## Guardas e riscos
- Requer espaço livre conservador: ~1,5× o tamanho somado das imagens + reserva de 1 GiB (mínimo 2 GiB); **estimativa, não quota**, monitorar espaço disponível. O diretório resultado pode ocupar espaço considerável no **mesmo disco EP125**. Não executar se estiver em manutenção crítica de armazenamento.
- Uma falha pode deixar diretório privado parcialmente construído. **Não removê-lo automaticamente**, examinar marcador. O RC01 fica intacto.
- A operação só usa Docker para `ps` e `inspect` read-only; não tem `docker run`, `image load`, `compose up`, `image prune`, `daemon` ou reinstalação de pacotes.
- OCI layout é criado por **código próprio**, não testado com um runtime independente. Compatibilidade de leitura por Skopeo/Podman, ativação HTTP/WAF, segredos, MariaDB, certificados, volumes, snapshot e `rollback real` **não comprovados**. Não elevar G0 para aprovado automaticamente.

## Estado
IMP01 = `ABORTADO_FERRAMENTA_AUSENTE` (20:05 real);
IMP02 = `VERSIONADO_CI_PASS_NAO_EXECUTADO` até saída real EP125.
PA-02 runtime = `ABERTO`; G0 = `NAO_APROVADO`. Não repetir RC01, DRY01 ou ISO01 v3.
