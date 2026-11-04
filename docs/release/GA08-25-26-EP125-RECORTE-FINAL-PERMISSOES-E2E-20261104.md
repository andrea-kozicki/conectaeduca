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
