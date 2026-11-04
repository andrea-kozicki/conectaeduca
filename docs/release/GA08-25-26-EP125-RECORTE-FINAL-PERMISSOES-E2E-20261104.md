# GA08.25–26 — recuperação efetiva do PA-02 na janela pré-10/11

**04/11/2026 | ConectaEduca EP125 | preparação de corte + verificador E2E.**
**ESTADO:** nenhum segundo cutover; PA-02 permanece aberto. O plano não equivale a autorização.

## Evidência operacional confirmada pela responsável

- GA08.19R: rollback real PHP/Nginx/WAF healthy 3/3.
- GA08.19T: WAF em 192.168.6.34:443; `/healthz`, `/login.php` e `/api/public_key.php` HTTP 200 / curl RC0.
- GA08.20 (antes): imagem PHP ativa EP125, FPM não iniciou, health unhealthy, categoria permissão; descartado, produção não mudou.
- GA08.21: UID82, config read NÃO, diretório socket existe e RW SIM, exit code 78, alvo CONFIG_FPM.
- GA08.22: três arquivos candidatos (FPM, Nginx socket e dual socket) `0600`, hash Git PASS, dono UID/GID da operadora, ilegíveis pelos UIDs 82/101.
- GA08.22R: `0644` nos **três arquivos candidatos públicos somente**, hash Git PASS, sem sudo, reinício ou cutover.
- GA08.20 reteste: mesmo canário e imagem instalada EP125, `RUNNING=SIM`, `HEALTHY`, config PASS, Unix socket SIM, removido SIM; **causa do canário corrigida**.
- GA08.23: referências privadas legíveis; diretórios persistentes de FPM/HTTP PASS; `GA08_PREFLIGHT=PASS_CONFIGURACAO_E_IMAGENS`, RC0; **sem verificação de snapshot/aprovação G0**, sem mutação.
- GA08.24: CONTEXTO e ROLLBACK correspondem a blobs PR217; `DRIVER=VERSAO_DIVERGENTE`. O driver **local** ainda não inclui o gate de leitura de configuração não secreta, apesar do preflight anterior ter passado.

## Próxima ação única na EP125 — GA08.25

1. Instalar **somente** o driver versionado `scripts/ga08-change-control.py` do commit exato da PR217, exigindo blob Git `e5b6d75b7b7c4e876fc3d87abe1db7e88f1988c2`. Fazer backup local privado do arquivo anterior e verificar sintaxe/ownership antes de troca atômica; nunca `git pull` ou `git reset` no checkout institucional.
2. Reaproveitar **apenas referências de caminhos GA08** do contexto antigo em modo leitura: `~/ConectaEduca_Fase2_Evidencias/EP125/GA08/GA08-20261103-EP125/runtime-refs.json`. A ferramenta `ga08-contexto-execucao-ep125.py --mode prepare` constrói um novo contexto pelos dados dos contêineres **atuais** para o novo change ID `GA08-20261104-EP125-PERM-FIX01` e gera um **template privado não aprovado**. Não copiar certificados, conteúdo de secrets ou envfile em documento.
3. Exigir preflight `GA08_PREFLIGHT=PASS_CONFIGURACAO_E_IMAGENS` e `GA08_REFERENCIAS_PRIVADAS=18/18`, nenhum serviço alterado.
4. **Não executar cutover neste passo.** Atestação G0 para novo ID deve refletir autorização real, snapshot e cobertura/rollback, janela, operador, dependências EP126, fontes bind protegidas e estado operacional atual. Snapshot `ubuntu.33` de 03/11 foi confirmado pelo suporte e é anterior à correção de permissões; restaurar esse ponto pode recuperar também o modo `0600`. Não inventar restore ensaiado nem marcar G0 sem confirmação.

## Execução efetiva GA08 — quando gate G0 estiver aprovado

- Antes: obter prova de contexto correto/manifesto ausente do novo ID; saúde 3/3, HTTPS 3/3; capturar evidências sem segredos. Reservar console/rollback com suporte como contingência.
- Cutover sequencial usando driver fixado e interlocks oficiais: PHP-FPM, depois Nginx, depois WAF. **Não usar `docker compose down`, `-v`, `prune` nem `git reset`.** Uma falha `unhealthy` congela a fase; rollback explícito e registro de status sob o mesmo novo ID, sem seguir para serviço seguinte.
- Após: executar `python3 scripts/ga08-e2e-pa02-ep125.py --verify` (GA08.26) **somente após a implantação autorizada**, usando o arquivo de PR217 revisado/validado por hash. O verificador não altera serviços: checa Compose labels/health 3/3, redes segregadas, ausência de publicação de backends, quatro verificações de sockets (WAF→Nginx e Nginx→FPM), três GET HTTPS legítimos 200, canário GET XSS esperado 403, negação TCP host→Nginx:8080 e host→PHP:9000. Pode devolver `BLOCKED` se implantação ainda é baseline ou ambiente diverge.
- **Escopo limitado** do GA08.26: usa `curl --insecure` para prova de resposta HTTP, não prova cadeia CA; não testa login real, MFA, banco de dados, Wazuh/telemetria, host socket mount por ACL nem usuário insider `teste`. Um `PASS_RECORTE` não fecha PA-02 sozinho; validar negativo PA-02 a partir da identidade/rede aprovada e a telemetria antes de encerramento.

## Critérios de aborto e recuperação

- Driver divergente/não validado, fonte de configuração `0600`, hash incorreto, fonte protegida sem autorização, snapshot não recuperável, Health degradado, acesso remoto incerto, dependência crítica EP126 não funcional, erro de socket/CRS/HTTP → **PARAR** e não forçar segundo cutover.
- Rollback oficial já comprovado para a baseline em GA08.19R, mas cada novo change ID exige seu próprio manifesto e confirmação de autorização. Sem comando de rollback compatível com o novo ID e backups atuais **não cortar**.
- Nunca publicar o contexto privado `runtime-refs.json`, templates preenchidos, conteúdo de certificados, senhas, snapshots ou logs brutos. Só marcadores categóricos, hashes dos scripts e evidências sanitizadas.

**Status na emissão:** GA08.25 ainda não executado na EP125; GA08.26 preparado em PR217, não aplicado na VM. CI offline é complementar, não substitui a prova na EP125.

## 04/11 — GA08.25 executada e aprovada na EP125

Saída enviada pela operadora: `HOST=EP125`, `IDENTIDADE=NAO_ROOT`, `NOVO_DRIVER_INTEGRIDADE=PASS`, `REFERENCIAS_GA08=PASS`, `DRIVER_ATUALIZADO=SIM`, `BACKUP_DRIVER=CRIADO`, `DRIVER_INTEGRIDADE_FINAL=PASS`, `GA08_PREFLIGHT=PASS_CONFIGURACAO_E_IMAGENS`, `GA08_REFERENCIAS_PRIVADAS=18/18`, `GA08_CONTEXT=PASS`, `GA08_APROVACAO_TEMPLATE_CRIADO=SIM`, `PREPARACAO_RC=0`, `GA08_25=PASS`, `GA08_SERVICOS_MODIFICADOS=NAO`, `CUTOVER_EXECUTADO=NAO`. O novo change ID `GA08-20261104-EP125-PERM-FIX01` foi preparado, com referências e modelo de autorização privados; **nenhuma das declarações G0 foi atestada automaticamente** e o snapshot não foi revalidado.

**Próxima decisão única:** atestar individualmente e apenas se houver evidência os gates `snapshot_covers_all_ep125_disks`, `snapshot_restore_confirmed_by_operator`, `bind_mounts_verified_by_operator`, `secrets_and_tls_recoverable`, `operator_and_window_approved`, `cross_vm_dependencies_checked`, `socket_directories_clean`, `cutover_approved`, `rollback_approved`. Guardar o arquivo `approval.json` no diretório privado `0700` com modo `0600`, e nunca enviar seu conteúdo. O snapshot de 03/11, anteriormente confirmado pelo suporte, retorna a configuração ao momento anterior ao chmod para 0644; preferir novo ponto se autorizado e necessário. Reversão Docker normal usa manifesto do novo change ID, não a PR antiga. Se um gate não for comprovado, **não marcar true**; registrar o bloqueio em vez de tentar o corte.

## 04/11 — GA08.25G/25H: template G0 criado, 0/9 atestações

Saída EP125: arquivo privado `approval.json` preparado em 0600, sem cutover. Leitor read-only de atestação `GA08.25H` registrou **todos os 9 booleans = PENDENTE**, `CHANGE_ID=PASS`, `SNAPSHOT_REFERENCIA=PRESENTE`, `APROVADOR=PENDENTE`, `GATES_APROVADOS=0/9`, `G0_ESTADO=PENDENTE`. Isto reflete os valores iniciais do modelo e **não é falha de configuração do Compose**. Nenhum valor será automatizado ou falsamente aprovado.

### Matriz de decisão sem novos inventários

| Campo G0 | Evidência até agora | Lacuna para atestação |
| --- | --- | --- |
| snapshot_covers_all_ep125_disks | Suporte informou snapshot `ubuntu.33` de 03/11 com cobertura | Responsável confirmar que cobre a mudança nova, inclusive volumes externos necessários, e se ponto antigo é aceitável |
| snapshot_restore_confirmed_by_operator | Suporte informou capacidade de restauração do snapshot | Garantir alcance/contato para restauração; **não** alegar restore ensaiado |
| bind_mounts_verified_by_operator | 8/8 montagens identificadas dentro de contêineres; 6 fontes restritas no host | Proteção/recuperação de fontes externas inacessíveis ainda não demonstrada só por mounts |
| secrets_and_tls_recoverable | Referências privadas 18/18 e TLS/HTTPS pós-rollback operante | Recuperabilidade dos arquivos reais e CA/keys não foi atestada por teste de restore |
| operator_and_window_approved | Responsável detém operação Docker dentro das autorizações institucionais | Declaração consciente de janela por operadora |
| cross_vm_dependencies_checked | EP126 e Twingate já funcionaram em testes anteriores | Status atual de dependências durante a janela ainda precisa de verificação objetiva |
| socket_directories_clean | GA08.23 conferiu dono e modo de dois diretórios | Conferir ausência de sockets antigos imediatamente antes do cutover |
| cutover_approved | Código com interlock + change ID `GA08-20261104-EP125-PERM-FIX01` preparado | Aprovação explícita na janela |
| rollback_approved | Rollback real GA08.19R previamente PASS 3/3; script rollback hash verificado | Aceitar estratégia e snapshot para **novo** corte, sem assumir recuperação E2E por histórico |

**Critério decisório:** Se `bind_mounts_verified_by_operator` ou `secrets_and_tls_recoverable` permanecerem sem evidência, não prosseguir com novo cutover apenas pelo prazo. Avançar atividades não disruptivas EP126/GitHub enquanto busca confirmação autorizada. Não usar `sudo -s`, `chmod 777` ou relaxar ACLs de secrets. **Não pedir conteúdo do approval.json no chat**.

## 04/11 — GA08.27 confirmou HTTPS restaurado e diagnóstico isolado GA08.28

**Nova evidência da operadora após rollback do segundo cutover:** `healthz=200/CURL_RC=0`, `login.php=200/CURL_RC=0`, `api/public_key.php=200/CURL_RC=0`; `NGINX_RUNNING=true`, `NGINX_HEALTH=healthy`, `nginx -t` sob UID101 `RC=0/PASS`. Isto comprova **recuperação do recorte HTTPS após rollback** e saúde do Nginx da baseline. **Não prova que o candidato Unix ou seu healthcheck são válidos**, e não comprova MFA/CA estrita/DB. A segunda tentativa de corte deixou PHP healthy, Nginx sem healthy e não alcançou a recriação do WAF; rollback posterior recuperou 3/3 e HTTPS 3/3. PA-02 permanece aberto.

**Hipótese nova:** o candidato `app-http.dual-socket.candidate.conf` substitui o `listen 8080` por `listen unix:/run/conectaeduca-http/nginx.sock`, e o overlay `compose.ga08-dual-socket.candidate.yml` substitui healthcheck HTTP por `nginx -t && test -S /run/conectaeduca-http/nginx.sock`. Nginx baseline healthy e `nginx -t` PASS testam **somente config antiga**. Não alterar healthcheck para mascarar erro.

**GA08.28 disponível em PR217:** `scripts/ga08-nginx-canario-ep125.py --run` inicia 1 container temporário de imagem exata do Nginx ativo, sem rede, secrets ou bind persistente de socket, somente a candidata versionada montada RO, UID101/GID101 (grupo suplementar 82), rootfs RO, tmpfs de cache/var-run/socket e healthcheck igual ao candidato. Retorna running/health/exit-code, `nginx -t`, escrita no diretório HTTP, presença do socket e categoria sanitizada do log, remove canário sempre. **Mesmo que passe, não prova bind persistente no host nem conectividade WAF/PHP;** isso deve ser testado antes de nova implantação. Não executar terceiro cutover antes da classificação GA08.28.

## 04/11 — GA08.28 falhou em rootfs read-only; GA08.29 isola entrypoint

Saída real EP125 da GA08.28 (contêiner descartável sem rede ou secrets): `CONFIG_INTEGRIDADE=PASS`, `NGINX_RUNNING=NAO`, `NGINX_HEALTH=UNHEALTHY`, `NGINX_EXIT_CODE=1`, `CONFIG_TEST=NAO_EXECUTADO`, `SOCKET_DIR_RW=NAO_EXECUTADO`, `SOCKET_UNIX_PRESENTE=NAO_EXECUTADO`, `LOG_CATEGORIA=ROOTFS_RO`, `GA08_28=FALHA_DIAGNOSTICADA`, `CANARIO_REMOVIDO=SIM`; produção não alterada. **A classificação original é por qualquer linha do log**, pode indicar aviso não fatal do entrypoint `10-listen-on-ipv6-by-default.sh`, não necessariamente a causa do exit 1. Portanto não recomendar remoção de `read_only:true` ou alteração do listener/host bind sem diagnóstico.

Preparado `scripts/ga08-nginx-entrypoint-isolation-ep125.py --run` (GA08.29): importa o canário GA08.28 **somente se o blob Git esperado bater**, reutiliza imagem exata, config RO, UID101, tmpfs, sem rede e segredos, mas substitui apenas entrypoint por `nginx -g 'daemon off;'`. Observa RUNNING/HEALTH/EXIT, `nginx -t`, permissão RW diretório HTTP, socket presente, categoria e alvo **preferindo erro fatal nginx [emerg] a avisos do entrypoint** sem imprimir logs. Remove sempre instância temporária. **PASS_SANDBOX** reforça hipótese de falha do entrypoint, não prova root cause ou bind persistente do host; falha classificada aponta o recurso a corrigir. Novo cutover continua proibido antes de confirmar causa, testar host bind e renovar aprovação/contexto conforme mudança futura. PA02 ABERTO.

## 04/11 — GA08.29 entrypoint descartado como causa exclusiva; GA08.30

Execução GA08.29 enviada pela operadora EP125: `IMAGE_ORIGINAL=PASS`, `CONFIG_CANDIDATA_INTEGRIDADE=PASS`, `ENTRYPOINT_BYPASS=SIM`, `NGINX_DIRETO_RUNNING=NAO`, `NGINX_DIRETO_HEALTH=UNHEALTHY`, `NGINX_DIRETO_EXIT_CODE=1`, `ERRO_FATAL_CATEGORIA=ARQUIVO_AUSENTE`, `ERRO_FATAL_ALVO=SOCKET_HTTP`, `CAUSA_ENTRYPOINT=NAO_ISOLADA`, `GA08_29=FALHA_DIAGNOSTICADA`, `CANARIO_REMOVIDO=SIM`, `SERVICOS_PRODUCAO_MODIFICADOS=NAO`. O Nginx morre mesmo quando inicializado diretamente. A categoria sanitizada sugere ENOENT no caminho do listener Unix, mas **não comprova ainda se o diretório está ausente, mascarado por mount ou inacessível**.

GA08.30 entregue em `scripts/ga08-nginx-runtime-paths-ep125.py` para reproduzir **exatamente** os flags de runtime/candidato do GA08.28/29 em contêiner temporário sem rede/segredos, mas iniciar shell unprivileged que imprime somente flags `/run`, `/var/run`, mountpoint e RW do diretório `/run/conectaeduca-http`, sintaxe do Nginx e posteriormente inicia Nginx. Classifica erro fatal sem expor Docker logs brutos. Possível conflito de sobreposição `/var/run` ↔ `/run` é **hipótese**, não comprovada. Não corrigir o código do Compose com base em inferência, e não recriar o stack antes do resultado GA08.30 e prova de mount persistente no host. PA02 permanece aberto.
