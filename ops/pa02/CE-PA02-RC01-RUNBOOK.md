# CE-PA02-RC01 — Recuperação local de serviços sem suporte (EP125)

**Responsável:** Andréa Kozicki · **Data:** 08/11/2026 · **Contexto:** solicitação de avançar no PA-02 sem depender da emissão de snapshot pelo suporte.

## Objetivo e limites

Criar, **sem sudo e sem reiniciar qualquer serviço**, um pacote local de retorno dos três serviços afetados pelo futuro cutover dual Unix do PA-02: PHP **com o hardening PA-05**, Nginx e WAF.

O comando Docker oficial `docker image save` exporta as camadas das imagens, permitindo futura importação por `docker image load`, mas **não inclui alterações de volumes ou bind mounts**. O pacote é adequado como **seguro operacional de restauração de imagens + Compose**, não é snapshot do hipervisor, não preserva banco, dados persistentes ou o conteúdo das chaves e certificados; tampouco prova RTO/RPO. Arquivos de imagens podem conter código/configuração embutidos e devem ficar privados. **Não enviar arquivo de imagem, manifest, compose ou segredos ao chat ou GitHub**.

Referências: [Docker image save](https://docs.docker.com/reference/cli/docker/image/save/), [backup e restore Docker](https://docs.docker.com/desktop/settings-and-maintenance/backup-and-restore/), [volumes](https://docs.docker.com/engine/storage/volumes/).

## O que CE-PA02-RC01 salva

- Um `docker-images.tar.gz` de três imagens **efetivamente em execução** dos serviços `php`, `nginx`, `waf`, sem baixar novas versões ou reconstruí-las. Compressão gzip nível1 e prova de integridade CRC + SHA-256.
- Cópias 0600 de **todos os dez arquivos Compose-base e do 11º overlay PA-05**, com hashes SHA-256 individuais.
- `manifest.json` 0600 com identificadores de contêiner/imagem, imagens/tag, ordem de Compose, destinos e **caminhos** de bind mounts (sem seus conteúdos), hashes e cobertura do pacote.
- Diretório privado em `~/.local/share/conectaeduca/pa02-recovery/CE-PA02-RC01-<timestamp>/` modo 0700, arquivos 0600.

**Nenhum secret** presente nos bind mounts é copiado pelo script. Nenhum `docker volume` / dump MariaDB / backup de `/var/log` é incluído, evitando tocar em dados e credenciais. Por isso, esse pacote **não é recuperação de perda completa da VM**. Recomenda-se ter uma cópia **fora da EP125**, protegida de forma adequada, caso autorizado institucionalmente.

## Proteções

- Usuário normal `andrea.kiew` EP125, Git HEAD `04f88d27`, serviço `conectaeduca-dmz`, PHP `conectaeduca/php-fpm:pa05-10328ab6`.
- Runtime `php/nginx/waf` healthy, imagens por tag com Docker Image ID correspondente, labels PHP confirmam **11 Compose**, bind de auditoria presente.
- Verifica permissão de leitura dos 11 arquivos e estima espaço livre **antes de iniciar a exportação**: soma dos tamanhos das imagens únicas ×1,2 mais 1 GiB de reserva. Se não houver espaço, **aborta sem criar archive grande** e informa somente tamanhos agregados. Reserva é estimativa conservadora, não substitui quota/disk monitor.
- Exporta uma única vez, comprime, reabre gzip integralmente para verificar CRC e confere hash do manifest. Se falhar, **não declarar recuperação pronta**; arquivo parcial é removido.
- Sem `sudo`, `docker compose up/down`, restart, pull, prune, network, tar de dados, scripts DLP ou alterações no checkout.

## Execução na EP125

`python3 ce_pa02_rc01.py --save`, com download do artefato por commit imutável, verificação de Git blob e sintaxe antes de executar. Quando a operação concluir:

```text
RUNTIME_3_SERVICOS=HEALTHY
PHP_PA05_E_11_COMPOSE=CONFIRMADOS
AUDITORIA_BIND=PRESENTE
ESPACO_PARA_EXPORTAR=PASS
BACKUP_11_COMPOSE=PASS
IMAGENS_EXPORTADAS=3_SERVICOS
ARQUIVO_COMPACTADO_INTEGRIDADE=PASS
MANIFEST_INTEGRIDADE=PASS
CONTEUDO_SECRETS_COPIADO=NAO
VOLUMES_E_BANCO_COPIADOS=NAO
SNAPSHOT_HIPERVISOR=NAO
RESTARTS_E_SERVICOS_MODIFICADOS=NAO
RECUPERACAO_DE_SERVICO=PREPARADA_NAO_ENSAIADA
CE-PA02-RC01_CONCLUIDO
```

**Não repetir cegamente** após `CE-PA02-RC01_ABORTADO`, nem executar `docker load` ou um rollback só para testar; manter imagens/base intactos.

## Próximo passo que independe do suporte

Após confirmar `CE-PA02-RC01_CONCLUIDO`, reconciliar o driver `CE-PA02-CUT01` da PR #230 para dar opção **explícita e documentada** de mudança com recuperação local de serviços, preservando o 11º overlay PA-05, sem afirmar que isso equivale a snapshot. Requer aceite informado do risco residual de **perda/corrupção da VM, bind mounts, banco e segredos**, porque restauração de imagens e Compose não recupera esses dados. Caso a instituição exija formalmente snapshot G0, o pacote não substitui a aprovação.

**Status:** somente pacote local de retorno preparado no GitHub, ainda **não gerado na EP125**. Não afirmar PA-02 implantado ou rollback ensaiado. O isolamento dual socket continua pendente de change control seguro.
