# PA-02 / GA-08 — preservar o PA-05 antes do corte dual socket (08/11/2026)

**Responsável:** Andréa Kozicki. **EP125.** Meta: concluir isolamento HTTP WAF→Nginx e FastCGI Nginx→PHP por sockets Unix, **sem regressão do patch SQL PA-05 implantado às 17:40**.

## Fatos comprovados — não repetir baterias

A PR #217 contém os três overlays `compose.ga08-socket.candidate.yml`, `compose.ga08-dual-socket.candidate.yml`, `compose.ga08-runtimefix.candidate.yml` e configs Nginx/FPM. GA08.31 provou `/run` canônico, GA08.32 aprovou Nginx de sandbox + imagem de baseline + configs/CRS com as limitações registradas. GA08.33 comprovou FPM RW, porém **o diretório HTTP RW ficou inconclusivo** em razão de uma possível corrida entre `docker run -d` e leitura instantânea do marcador. Os dois cutovers de 03 e 04/11 falharam e exigiram rollback 3/3 healthy; não insistir com o driver antigo.

Em 08/11 às 17:40 foi implantado PHP PA-05: imagem `conectaeduca/php-fpm:pa05-10328ab6`, contêiner saudável e auditoria+secrets preservados. A seleção é feita pelo **11º overlay obrigatório**:

`/home/andrea.kiew/.config/conectaeduca/pa05/compose.pa05-10328ab6.yml`

Os scripts da GA08.17 antigos aguardavam **10** overlays PHP e imagens baseline de antes do PA-05. Assim, um novo cutover que usasse aqueles scripts poderia abortar ou, pior, recriar PHP com código vulnerável anterior. **É PROIBIDO executar `ga08-change-control.py --execute` ou `docker compose up` legado sem revisão.**

## Correção pontual desta PR

`ops/pa02/ce_pa02_rw01.py`: uma checagem controlada de escrita/remoção no bind host HTTP `/var/lib/conectaeduca-ga08/http` com a **mesma imagem Nginx ativa**, UID/GID 101:101, diretório modo 0700, em apenas **um** contêiner descartável `--network none --read-only --cap-drop ALL`, sem secrets, sem Compose, sem pub/sub sockets de produção, e com `--rm`.

Diferente da GA08.33, o `mkdir -m 0700` e `rmdir` ocorrem **sincronamente** no mesmo processo do canário. Se retornar zero, fica comprovado o gate *escrita/limpeza do diretório*, sem afirmar isolamento de bypass em produção. Se falhar, **parar sem rerun** e avaliar a hipótese de permissão/mount. Não imprimir log bruto do contêiner.

Os diretórios GA08 são preparados desde 03/11 com owner/mode FPM 82:82/0770 e HTTP 101:101/0700; não mudar os modos. Os sockets de produção HTTP/FPM (se existirem) não são tocados. Verificação limitada à única lacuna técnica ainda relevante para o cutover.

## Requisitos para implantação real do PA-02

Um roteiro novo **ainda precisa ser implementado e validado** com guardas concretos:

1. Fixar o baseline PHP implantado **por Image ID atual**, não assumir `conectaeduca/php-fpm:dmz`. Conferir também baseline WAF/Nginx e estado healthy.
2. Construir a lista Compose da EP125 a partir do inventário aprovado, sem imprimir secrets. Respeitar dez arquivos base + **11º overlay PA-05** + candidatos GA08 socket, dual socket e runtimefix **nesta ordem**. Os candidatos devem ser localmente iguais aos Git blobs aprovados da PR #217 (sem alterar `/opt/conectaeduca`).
3. Reconstituir referências de interpolação pelos metadados do runtime e caminhos de binds protegidos, como realizado no CE-PA05-DEP02. Não criar `.env` improvisado nem publicar configurações expandidas.
4. Verificar divergências entre Compose atual e candidato somente de redes/sockets/healthcheck/tmpfs, com **mesmo PHP patchado**. Jamais remover `compose.audit-persistent.yml` ou sobrepor o PHP com a tag baseline.
5. Ativar dual socket em janela autorizada com referência de snapshot e plano de recuperação compatível com o **estado de 08/11**, não com o snapshot anterior de 03/11 sem o PA-05. Manter rollback automático que restaure **PHP PA-05 + 11º overlay, Nginx e WAF**. Provar HTTPS via WAF e negação da rota TCP direta, com o mínimo de casos.
6. Apenas após `CE-PA02-CUTxx_CONCLUIDO` real classificar a remediação em runtime. Até então **PA-02 permanece ABERTO**.

### Meta de evidência CE-PA02-RW01

```text
BIND_HTTP_PERMISSOES=PASS
NGINX_BASELINE=HEALTHY
BIND_HTTP_RW=PASS
BIND_HTTP_LIMPEZA=PASS
CONTEINER_CANARIO=DESCARTADO
NGINX_PRODUCAO_ALTERADO=NAO
PHP_PA05_ALTERADO=NAO
DOCKER_COMPOSE_EXECUTADO=NAO
CE-PA02-RW01_CONCLUIDO
```

Não executar GA08.32/33 novamente nem reproduzir os dois cutovers anteriores. O procedimento completo de PA-02 é a próxima **implementação**, e CE-PA02-RW01 é exclusivamente uma guarda de integridade e permissão, não mais uma bateria de pentest.

## Atualização de 08/11 — driver PA-05-safe preparado

O driver descrito anteriormente como "a implementar" foi **versionado após a prova CE-PA02-RW01 PASS** em `ops/pa02/ce_pa02_cut01.py`, com runbook específico `ops/pa02/CE-PA02-CUT01-RUNBOOK.md`. A nova ferramenta oferece preparação privativa, cutover condicionado a snapshot **pós-PA05** e rollback à imagem PHP **PA-05**, usando 10+11º overlays como baseline. As três configurações GA08 são obtidas por Git blobs imutáveis do commit da PR #217 e usadas **adicionalmente** só no candidato. CI final 5/5 PASS + Snyk success. **Não existe prova de execução do driver na EP125**, nem aprovação G0. PA-02 segue aberto em produção. Não executar o driver antigo GA08.17/25, nem dispensar aprovação/snapshot por ter CI verde.
