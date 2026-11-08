# CE-PA02-IMP01 — ensaio independente de importação em layout OCI

**Contexto:** EP125, 08/11/2026; responsável Andréa Kozicki. **Estado do ensaio:** pronto no GitHub, mas ainda **não executado** na EP125.

## Motivação

A salvaguarda [RC01] preservou 3 imagens Docker (PHP PA05/Nginx/WAF) e 11 Compose; o DRY01 validou a cadeia de arquivos; o ISO01 v3 comprovou formato interno, SHA256 dos config/layers (63 camadas gzip) e executabilidade das imagens **já presentes no daemon**. A responsável pediu um ensaio **independente da fonte original**, sem arriscar produção.

A implementação `ops/pa02/ce_pa02_imp01.py` usa o **Skopeo** com `docker-archive:<RC01.tar.gz>:<imagem>` como entrada e `oci:<diretorio-privado>:<tag-temporaria>` como saída. Os transportes do Skopeo copiam entre arquivos Docker Save e **OCI layout filesystem**, sem acesso ao daemon Docker: documentação upstream [skopeo copy](https://github.com/containers/skopeo/blob/main/docs/skopeo-copy.1.md), [containers transport](https://github.com/containers/image/blob/main/docs/containers-transports.5.md) e [Ubuntu Server](https://ubuntu.com/server/docs/how-to/containers/skopeo/).

## Guardas

1. Executa somente com `andrea.kiew`, EP125, Git main HEAD congelado `04f88d27...`, `--isolated`, sem `sudo`; **não instala pacotes**.
2. Se `skopeo` não estiver instalado, retorna `SKOPEO_AUSENTE_NAO_INSTALAR_AUTOMATICAMENTE` e **não gera conversões**. Nenhuma tentativa de instalar com apt ou usar outro daemon sem planejamento.
3. Verifica antes o diretório de backup 0700 e `manifest.json`/`docker-images.tar.gz` 0600, SHA256 externo, 3 imagens exatas (tags e ImageIDs iguais ao runtime saudável, PHP PA05).
4. Calcula estimativa de disco **conservadora**, incluindo a extração temporária do arquivo compactado e saída OCI; se não há espaço, aborta **antes de criar o destino**. Reserva pelo menos 1 GiB extra; lembre que é estimativa, e não quota FS.
5. Cria `~/.local/share/conectaeduca/pa02-recovery/CE-PA02-IMP01-YYYYMMDD-HHMMSS/` privado 0700. Dentro, `oci-php`, `oci-nginx`, `oci-waf` e `tmp`; configura `TMPDIR` exclusivamente no diretório do ensaio. **Nunca** escreve no RC01, `/opt/conectaeduca`, Docker, pfSense ou certificados; não usa `docker-daemon:`, `containers-storage:`, `docker image load`, Compose nem `docker run`.
6. Para cada imagem, Skopeo `copy` somente de arquivo Docker para OCI privado; valida `oci-layout`, `index.json`, descritor do manifest e config/layers com **hash SHA256 de cada blob OCI**, campo `rootfs.diff_ids` igual ao estado do Docker anteriormente confirmado. Saída de ferramenta é capturada em memória e **não exposta**.
7. Aborta fechado com marcador específico se falhar uma das três conversões ou um hash; **não tenta apagar recursivamente diretórios parcialmente produzidos sem revisão**. Se a ferramenta estiver ausente ou o disco for insuficiente, simplesmente comunicar o bloqueio, sem contornar os gates.

## O que comprova e o que NÃO comprova

`CE-PA02-IMP01_CONCLUIDO` demonstra que uma **ferramenta independente consegue consumir as três imagens do arquivo salvo e convertê-las em layouts OCI verificáveis**, sem usar imagens do daemon como fonte. Reforça a recuperabilidade dos artefatos das imagens.

Ainda **NÃO** prova `docker image load` no daemon, restauração efetiva do stack PHP→Nginx→WAF, disponibilidade HTTPS/TLS, acesso ao MariaDB, persistência de logs/volumes, recuperação das credenciais, nem tempo de resposta de rollback. Arquivos são produzidos no **mesmo disco EP125**, não substituem snapshot institucional nem backup externo. Após PASS, não repetir RC01/DRY01/ISO01/ISO02.

## Próximo gate

Mesmo com IMP01 PASS, o PA02 continua **ABERTO EM RUNTIME** até ativação efetiva dos sockets Unix e teste funcional. O driver de corte `CE-PA02-CUT01` mantém o G0 não aprovado; uma mudança real exige aceitação expressa de riscos locais e janela de manutenção. Não editar `approval.json` automaticamente. O backup RC01 e o diretório privado do contexto de mudança devem ser preservados.
