# CE-PA05-DEP02 — Deploy controlado das correções SQL no PHP da EP125

**08/11/2026 · Responsável: Andréa Kozicki.** Implantação operacional via script Python `ops/pa05/ce_pa05_dep02.py`, **sem sudo** e sem `git pull` ou mudança nos arquivos rastreados. A PR #229 permanece DRAFT; executar o script não faz merge do patch em `main`.

## Estado real confirmado

Saída CE-PA05-DEP01 na EP125, 08/11 17:30:41 -03:00: checkout HEAD `04f88d275064a005d0ffcd4f9372a371c28c32d5`; projeto Docker `conectaeduca-dmz`; PHP imagem `conectaeduca/php-fpm:dmz`, ID **`sha256:3c8b6fe0c9905ddfe13c5b5b5fc408726bdff89290a1a99a74abb912d9a609f4`**. O contêiner PHP não possui bind de `src/`: os fontes são incorporados no build. Montagens secretas presentes em `/run/secrets/` (senha DB, CA DB TLS, chaves pública/privada) e log persistente em `/var/www/conectaeduca/storage/logs`.

**Dez arquivos Compose, ordem literal preservada** (labels atuais do PHP):

```text
/opt/conectaeduca/deploy/dmz/compose.yml
/opt/conectaeduca/deploy/dmz/compose.database.yml
/opt/conectaeduca/deploy/dmz/compose.app-secrets.yml
/opt/conectaeduca/deploy/dmz/compose.waf.yml
/opt/conectaeduca/deploy/dmz/compose.waf-tls.yml
/opt/conectaeduca/deploy/dmz/compose.waf-policy.yml
/opt/conectaeduca/deploy/dmz/compose.host.yml
/opt/conectaeduca/deploy/dmz/compose.vm.yml
/opt/conectaeduca/deploy/dmz/compose.database-tls.yml
/opt/conectaeduca/deploy/dmz/compose.audit-persistent.yml
```

## Solução — camada adicional em vez de rebuild total

Rebuild completo da aplicação arriscaria recriar dependências ou sobrescrever tag baseline e exigir segredos e variáveis do antigo pipeline. Aqui fazemos um **patch de imagem derivada**: `FROM conectaeduca/php-fpm:dmz`, fixada por verificação prévia do Image ID acima. `COPY --chown=82:82 --chmod=0644` de somente três arquivos PHP, baixados de **commit imutável** `10328ab6d67d59325c2ea3b707a5dce660c2bb8f` da PR #229 com seus Git blobs verificados:

| Arquivo | Base | Patch aprovado |
|---|---|---|
| `src/Repository/InscricaoRepository.php` | `99388b33154eb67109d866cb2d1920a85effcd37` | `538e59a2c7690cc53c5f71ff0ca54286c2a0ba5c` |
| `src/Service/InscricaoService.php` | `0c56f3b392c427d868205ab6db51361e8719c2bb` | `4d0031e97ab7daa8b4b4edff3ffddad97898c6f3` |
| `src/Controller/InscricaoController.php` | `c549acf4435fcf87036d987c94d88d31bfd7df9d` | `451d97936c8f2ae6d82ab47a932fbcb36365a496` |

A imagem nova usa tag **`conectaeduca/php-fpm:pa05-10328ab6`** sem sobrescrever `conectaeduca/php-fpm:dmz`. A construção usa `docker build --pull=false --network=none`, sem baixar base, atualizar pacotes, executando sintaxe `php -l` para somente os três arquivos, em contêiner descartável **sem rede e sem volumes/segredos**. Essa verificação é gate mínimo de segurança, não bateria de pentest.

## Compatibilização de variáveis obrigatórias sem exibir segredos

Os overlays exigem `CONECTAEDUCA_DB_HOST`, `CONECTAEDUCA_DB_PASSWORD_FILE`, chaves, CA, `APP_URL`, `STACK_SECRET_GID`, endereços de bind e certificados WAF. A configuração da EP125 já sofreu **GA-08 FAIL_CLOSED** por variável ausente; por isso a rotina **não exige nem imprime** `.env` ou qualquer conteúdo de secret:

- Lê `Config.Env` do PHP **somente para parâmetros não secretos** (`DB_HOST`, `DB_PORT`, `APP_URL`); não imprime os valores.
- Usa `Mounts[].Source` somente para **caminhos** dos seis secrets dos contêineres PHP/WAF, nunca lê nem imprime seu conteúdo.
- Obtém `STACK_SECRET_GID` de `HostConfig.GroupAdd` do PHP/WAF, exige igualdade; portas e bind do WAF de `HostConfig.PortBindings`, exige unicidade.
- Monta ambiente de subprocesso em memória, com fontes dos arquivos secretos já montados, e valida `docker compose -f [dez arquivos] config --format json`, comparando parâmetros sensíveis à configuração efetivamente em operação.
- Cria um **11º override persistente** em `$HOME/.config/conectaeduca/pa05/compose.pa05-10328ab6.yml`, contendo apenas `services.php.image`, `pull_policy: never`, `build: !reset null`. Verifica que o modelo final é idêntico ao dos dez overlays **exceto seleção de imagem/build**. O 11º arquivo deve ser incluído em comandos futuros de manutenção enquanto o PA-05 estiver instalado: **não aplicar `docker compose up` com os dez arquivos originais**, pois isso pode restabelecer a versão de código antiga.

## Cutover limitado ao contêiner PHP

Somente se guardas passarem, executar `docker compose ... up -d --no-deps --no-build --pull never --force-recreate php` com todos os onze arquivos. O PHP pode ficar indisponível brevemente; **nenhum restart do WAF/Nginx** é solicitado. Verifica Image ID da candidata, Docker health `healthy`, integridade das fontes dos mounts, rootfs read-only, cap drop, grupo secreto e identidade dos contêineres adjacentes. Falha após início de cutover aciona rollback **best effort**: usa os dez arquivos de base para recriar apenas PHP com a imagem anterior e aguarda healthy. Se rollback falhar, não repetir cegamente: escalonar intervenção.

### Resultado esperado

```text
RUNTIME_BASELINE=CONFIRMADO
COMPOSE_ATIVO=10_ARQUIVOS
COMPOSE_E_SECRETS=RECONCILIADOS_SEM_EXPOSICAO
PATCH_3_ARQUIVOS=HASHES_CONFIRMADOS
IMAGEM_CANDIDATA=CRIADA
PHP_SINTAXE=PASS
COMPOSE_CANDIDATA=PASS
SERVICOS_AFETADOS=APENAS_PHP
DEPLOY_PHP_PA05=CONFIRMADO
PHP_HEALTH=HEALTHY
AUDIT_BIND_E_SECRETS=PRESERVADOS
WAF_NGINX_RECRIADOS=NAO
ROLLBACK_BASELINE=PREPARADO_NAO_ENSAIADO
GIT_TRACKED=NAO_MODIFICADO
CE-PA05-DEP02_CONCLUIDO
```

**NÃO executar novamente sem revisão** se surgir `CE-PA05-DEP02_ABORTADO`, falha de Compose, `ROLLBACK_PA05=...` ou qualquer mudança inesperada. Logs de comandos ficam privados sob `$HOME/.local/share/conectaeduca/pa05-deploy-10328ab6/logs` (0700/0600); **não postar logs brutos**. Não apagar backup/camada/override. O código e o próprio script ficam num PR; execução local só após usuário conferir commit/blob e aceitar o `--apply`.

### Limites e aceite

- **Esta ação implementa a imagem corrigida somente se a saída real `CE-PA05-DEP02_CONCLUIDO` aparecer.** Não confundir CI, build de candidato ou configuração preparada com deploy efetivo.
- Não declara `PA-05 PASS`. Após cutover, resta **uma prova HTTP dirigida** com contas e oportunidades fictícias (oportunidade não publicada →404 e controle publicada positiva; acesso BOLA horizontal entre contas do mesmo papel). Não repetir RBAC vertical já comprovado.
- Não cobre PA-02 WAF dual socket nem altera OpenBao, EP126, Twingate ou Ferret; evita `git reset/restore/clean` nas duas VMs. Backup da candidata por Docker image ID é preservado enquanto não houver limpeza do daemon.
- A imagem é uma **derivação local rastreada por digest do ancestral e hashes dos três arquivos**, não uma release reproduzível completa por CI de registro externo. Migração de `main` e promoção canônica para imagem de produção devem ser planejadas mais tarde.
