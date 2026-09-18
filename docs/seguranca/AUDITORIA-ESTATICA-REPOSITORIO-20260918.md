# Auditoria estática do repositório — 18/09/2026

## Objetivo

Registrar a revisão do estado versionado do ConectaEduca que pode ser feita sem
acesso às VMs EP125/EP126 e separar claramente:

1. correções puramente de repositório;
2. preparação versionável que ainda exige validação em VM;
3. gates que dependem necessariamente do runtime acadêmico.

Esta auditoria **não substitui** testes live de rede, serviços, backup/restore ou
observabilidade.

## Fotografia inicial

A árvore `main` observada no início da revisão continha:

- 516 arquivos rastreados;
- 101 scripts Python/Shell relevantes;
- 33 arquivos Compose;
- 108 documentos Markdown;
- 3 workflows GitHub Actions em `main`;
- um PR aberto (#89);
- nenhum issue aberto.

## Correções repo-only identificadas

### Auditoria estática reproduzível

Foi adicionado:

```text
scripts/ci/auditar_repositorio_estatico.py
.github/workflows/repository-static-audit.yml
```

O gate verifica, sem depender de serviços externos do laboratório:

- arquivos rastreados vazios fora de `.gitkeep`;
- runtime `.runtime`, `.env` real e chaves privadas indevidamente rastreados;
- actions externas pinadas por SHA;
- ausência de runners `*-latest`;
- `actions/checkout` com `persist-credentials: false`;
- modo executável `100755` para scripts operacionais `.sh/.py`;
- sintaxe de todos os Python por `py_compile`;
- sintaxe JavaScript por `node --check`;
- sintaxe de scripts `.sh` conforme o shebang;
- JSON, XML/fragmentos Wazuh e TOML versionados;
- links Markdown locais;
- Dockerfiles: bases externas por digest, sem `:latest`, ADD remoto ou download
  por pipe direto para shell;
- Compose: sem `privileged:true`, Docker socket ou `:latest`; imagens externas
  por digest; `network_mode: host` somente na exceção Twingate; fontes estáticas
  de bind mount relativas precisam existir no repositório;
- antipadrões `sudo -s`, `sudo su`, `chmod 777` e supressão de erro de
  `chmod/chown` com `|| true`.

O workflow usa runner fixo `ubuntu-24.04`, checkout pinado por SHA, permissões
somente de leitura e timeout explícito.

### Evidência vazia do Composer

`docs/evidencias/composer-audit-final.txt` estava rastreado com 0 bytes e não
foi encontrado como dependência/referência de outros arquivos na busca inicial.

Ele foi removido. A auditoria não inventa ou retropreenche uma evidência
histórica ausente.

A evidência não vazia existente:

```text
docs/evidencias/composer-audit.txt
```

permanece preservada.

### Inventário estático obsoleto

`estrutura_arquivos_repositorio.txt` representava uma árvore antiga do projeto:
mostrava apenas um workflow, omitia a maior parte da infraestrutura atual e ainda
referenciava o artefato Composer vazio removido nesta auditoria.

Como não havia referência interna encontrada para esse inventário e uma árvore
manual tende a voltar a divergir, o arquivo foi removido em vez de receber uma
atualização pontual que envelheceria novamente.

### Makefile — permissões de chaves

Os alvos `fix-perms` e `fix-owner` suprimiam falhas de `chmod`/`chown`
com `|| true` e imprimiam mensagem de sucesso mesmo quando o ajuste poderia
ter falhado.

A supressão foi removida. Falhas nesses ajustes agora propagam erro e impedem
um falso positivo de hardening.

### Checkpoint histórico de correções Codex

`scripts/evidencias/checkpoint_correcoes_codex.sh` estava sem bit executável e
continha asserções que já não correspondiam ao repositório — algumas delas já
eram falsas no próprio commit que criou o checkpoint em 13/09/2026.

A auditoria:

- restaurou o modo executável;
- substituiu a referência ao antigo
  `scripts/implantacao/instalar_wazuh_dashboard_acl.sh`, hoje inexistente,
  pelo gate ACL atual de `validar_wazuh_operacional.sh`;
- reconciliou os checks do Indexer com as garantias atuais:
  `internal_users.yml` runtime somente leitura + health do Security plugin;
- reconciliou o logrotate Ferret com a política real `daily` + `size 5M`;
- adicionou o checkpoint ao CI para impedir novo drift silencioso.

### Bridge OpenBao -> Wazuh

O follower usa `docker logs --follow`. Esse subprocess pode encerrar com RC 0;
nesse caso `Restart=on-failure` não relançaria o bridge e a ingestão sanitizada
poderia parar após um término limpo.

A unit gerada passou a exigir e materializar `Restart=always`. A mudança é
verificável estaticamente no Git, mas a reaplicação da unit já instalada continua
sendo um gate operacional da EP126.

### Health monitor do Ferret

O Compose permite customizar a porta web, e o health script aceita
`FERRET_HEALTH_URL`, mas a unit systemd gerada não persistia esse endpoint.

O instalador agora:

- deriva por padrão `http://127.0.0.1:<FERRET_WEB_PORT>/health`;
- aceita `FERRET_HEALTH_URL` explícita dentro de um formato restrito;
- persiste a URL na unit;
- valida no modo `--check` que a unit instalada corresponde ao valor esperado.

A reaplicação/revalidação systemd permanece dependente do host.

### Checkpoint de reprodutibilidade de imagens

`checkpoint_reprodutibilidade_imagens.sh` ainda procurava uma baseline antiga
de PHP 8.5 Bookworm e a imagem WAF upstream diretamente no Compose. O código
atual usa PHP 8.5.9 Alpine 3.24 e constrói `conectaeduca/waf:dmz` a partir de
um Dockerfile com a base CRS fixada por digest.

O checkpoint foi reconciliado com os Dockerfiles atuais e sua advertência de
pacotes dinâmicos passou de APT/Debian para APK/Alpine.

## PR #89

O workflow `.github/workflows/infra-script-tests.yml`, introduzido pelo PR #89,
foi endurecido separadamente no próprio branch do PR:

- `ubuntu-latest` -> `ubuntu-24.04`;
- `actions/checkout@v4` -> SHA fixo;
- `persist-credentials: false`;
- timeout explícito;
- rejeição de execução root do helper Bacula antes de criar lock/evidence-dir,
  com self-test específico no CI.

Essa alteração pertence ao escopo do próprio PR #89 e não é duplicada neste
branch de auditoria.

## Achados que podem ser preparados no Git, mas exigem VM para fechamento

### Bacula File Daemon nativo

O contrato atual já reconhece corretamente que:

```text
scripts/implantacao/preparar_bacula_fd_ubuntu.sh
```

é bootstrap e não um caminho completo de ativação segura.

A revisão confirmou que o script ainda:

- instala `bacula-fd` diretamente via apt;
- não executa um gate prévio obrigatório de compatibilidade de versão;
- não bloqueia de forma versionada eventual auto-start do pacote;
- não promove/valida a configuração efetiva antes da ativação;
- não fecha um gate de serviço ativo + TCP/9102.

A correção pode ser desenvolvida no repositório, mas só deve ser declarada
fechada após execução em VM limpa e repetição do fluxo cross-zone.

### Bacula restricted Console `teste`

O caminho de menor privilégio pode ser versionado, mas a autenticação, ACLs e o
E2E positivo/negativo precisam ser exercitados no Director real da EP126.

### pfSense -> Wazuh analítico

O transporte correlacionado até o receiver já possui evidência histórica. O gate
de decoder/regra/archive/alert/indexação depende do runtime Wazuh/pfSense e não
pode ser fechado por análise estática.

## Divergências intencionais que não devem ser "corrigidas" automaticamente

### Bacula `compose.yml` x `compose.vm.yml`

Os arquivos têm escopos diferentes:

- `compose.yml` preserva bancada/laboratório, inclusive `filedaemon-lab`;
- `compose.vm.yml` representa a topologia das VMs acadêmicas e integra
  `bacula-uplink`.

A auditoria deve verificar referências incorretas entre eles, mas não tratar a
diferença como drift automaticamente.

### OpenBao sem TLS interno no laboratório

O listener com `tls_disable=true` está documentado no escopo laboratorial e a
API é publicada apenas em loopback no host. O próprio arquivo registra que TLS
real é requisito antes de atravessar VMs.

### Twingate com `network_mode: host`

É uma decisão explícita da integração atual e não deve ser removida por uma regra
genérica de hardening sem análise funcional.

## Próximos gates

### Repo-only

- executar o novo workflow em PR;
- corrigir qualquer sintaxe/invariante que o gate descubra;
- preparar endurecimento do instalador Bacula FD em PR próprio;
- revisar referências entre Compose de laboratório e Compose de VM;
- revisar documentação raiz histórica sem apagar material útil.

### Requer host

- aplicar/validar restricted Console Bacula;
- validar Bacula FD package-based em VM limpa;
- concluir o gate analítico pfSense -> Wazuh;
- repetir qualquer backup/restore destrutivo somente no runtime controlado.

## Princípio de aceite

Uma correção de repositório pode ser fechada com CI estático quando sua
propriedade é inteiramente verificável no Git.

Uma propriedade operacional só é considerada fechada quando existe evidência
fresh do ambiente que efetivamente a executa.