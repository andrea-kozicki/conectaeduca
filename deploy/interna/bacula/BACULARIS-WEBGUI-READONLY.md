# GUI-01B — Bacularis WebGUI read-only

## Estado

Implementado e validado na EP126 em 23/09/2026.

O Bacularis é usado somente como camada humana de observabilidade do Bacula. A
instância não substitui Director, Storage ou Catalog e não recebe privilégios de
administração sobre eles.

Validação final do runtime v1.8:

- `PASS=24`, `WARN=0`, `FAIL=0`, `FINAL=PASS`;
- evidência: `3889fd9e24c3bf371112d909bd89947d297660048ab91a6ee005f13e4878772f`;
- imagem validada: `conectaeduca/bacularis-webapi:6.5.2-gui01b-v31`;
- image ID validado na EP126:
  `sha256:6fa5a94dea1e07edd6fc0f21fb02c12c1228e9402aa9bb4b4d4cdb300606c3d1`.

O image ID acima identifica a imagem validada no laboratório. Um rebuild a partir
deste repositório deve ser novamente submetido aos gates antes de substituir a
imagem live.

## Modelo de segurança

### Acesso humano

- usuário Web: `teste`;
- role Web: `normal`;
- acesso padrão: `no_access`;
- senha acadêmica informada apenas em runtime e nunca versionada;
- bcrypt com custo 10;
- gerenciamento de usuários pela Web desabilitado.

### Bacula Director

O Bacularis usa o Console restrito `teste`. A ACL do Bacula permanece como
backstop e não é substituída pela GUI.

A conta não deve receber comandos de mutação como `run`, `restore`, `cancel`,
`delete`, `reload`, `update`, `label`, `relabel`, `mount`, `umount`,
`release`, `prune`, `purge`, `estimate`, `setbandwidth`, `enable` ou
`disable`.

### Catalog PostgreSQL

A API usa a role técnica `bacularis_view`:

- `LOGIN` sem privilégios administrativos;
- `default_transaction_read_only=on`;
- `CONNECT` no database `bacula`;
- `USAGE` no schema `public`;
- `SELECT` nas tabelas atuais do Catalog;
- sem `INSERT`, `UPDATE`, `DELETE`, `TRUNCATE`, DDL ou default privileges;
- conexão direta ao Catalog pela rede Docker interna com
  `PGSSLMODE=verify-full` e CA dedicada.

### API read-only

Há enforcement explícito no Nginx antes do PHP. A decisão usa a variável
normalizada `$uri`, evitando discrepância entre o alvo bruto da requisição e o
caminho efetivamente roteado pelo Nginx:

- `GET` e `HEAD` sob `/api` e `/index.php/api` são permitidos;
- qualquer outro método sob esses namespaces retorna `405`;
- POSTs da aplicação Web fora do namespace `/api` permanecem disponíveis para o
  fluxo normal de login;
- `/panel` e `/index.php/panel` retornam `403`.

A proteção de métodos HTTP é adicional às ACLs do Bacula e ao SELECT-only do
PostgreSQL.

## Hardening do container

O serviço final segue estes controles:

- bind somente em `127.0.0.1:9097`;
- usuário `www-data`;
- root filesystem read-only;
- `cap_drop: ALL`;
- `no-new-privileges:true`;
- sem Docker socket;
- sem `privileged` ou `network_mode: host`;
- sem `sudo`;
- sem Director, Storage, File Daemon ou PostgreSQL executáveis;
- `jsontools` e `actions` desabilitados;
- Config API/Web montado somente leitura;
- `assets`, `protected/runtime`, logs, sessões e diretórios operacionais em
  `tmpfs`;
- entrypoint supervisiona PHP-FPM e Nginx; a saída inesperada de qualquer um
  encerra o container para que a política de restart possa recuperá-lo.

O patch em `GeneralRequirements.php` remove somente a exigência upstream de
**escrita** no diretório `Config`. A configuração continua legível e é montada
read-only pelo runtime. As exigências de escrita em `assets`, `runtime` e `Logs`
permanecem ativas e são atendidas por `tmpfs`.

## Topologia

O container participa de duas redes:

- `conectaeduca-bacularis-ui`: bridge não-interna usada pela publicação em
  loopback;
- `conectaeduca-bacula_bacula-backend`: rede interna já existente do Bacula,
  usada para alcançar Director e Catalog.

Não há publicação do PostgreSQL ou do Director para atender o Bacularis.

## Arquivos versionados

- `bacularis/Dockerfile`: build consolidado do perfil Web+API read-only;
- `bacularis/conectaeduca-bacularis-entrypoint-v2`: inicia apenas PHP-FPM e
  Nginx;
- `bacularis/api.conf.failclosed`: defaults sem DB/bconsole/actions/json-tools
  ativos;
- `bacularis/conectaeduca-bacularis-readonly.conf`: nega o painel administrativo;
- `bacularis/00-conectaeduca-api-readonly-map.conf`: firewall de métodos da API;
- `compose.bacularis-readonly.yml`: contrato declarativo equivalente ao runtime
  validado.

Os volumes `conectaeduca-bacularis-api-runtime` e
`conectaeduca-bacularis-web-runtime` são externos e contêm material gerado em
runtime. Eles **não** devem ser exportados para o Git.

## Build e validação

Validar primeiro a configuração declarativa:

```bash
docker compose \
  -f deploy/interna/bacula/compose.bacularis-readonly.yml \
  config -q
```

O build é feito a partir do upstream Bacularis 6.5.2 fixado por digest:

```bash
docker compose \
  -f deploy/interna/bacula/compose.bacularis-readonly.yml \
  build bacularis
```

Antes de substituir a imagem live, repetir os gates do GUI-01B. O runtime só é
considerado aprovado quando, no mínimo:

- WebGUI responde em `127.0.0.1:9097`;
- Requirements API/Web passam;
- login `teste` passa;
- Catalog, Directors, Status e Jobs respondem por API v3 com JSON válido;
- tentativa de `POST /api/v3/jobs/run/` retorna `405` no Nginx;
- Director continua sem jobs iniciados pelo teste;
- snapshot do Catalog permanece inalterado;
- Director, PgBouncer e Catalog preservam health e `restart_count`.

## Evidência final de não mutação

No gate final, o snapshot de `InternaSmokeBackup` era `count=1|maxid=1` antes da
tentativa de Job Run. O POST foi bloqueado com HTTP `405`; depois do teste o
snapshot continuou `count=1|maxid=1` e o Director permaneceu sem jobs em
execução.

Esse resultado demonstra enforcement em camadas: Nginx bloqueia a mutação antes
do Bacularis, Bacula mantém ACL restrita e o Catalog é acessado por uma role
SELECT-only.
