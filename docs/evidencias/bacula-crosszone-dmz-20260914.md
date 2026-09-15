# Evidência operacional — Bacula cross-zone DMZ

Data da validação: **14/09/2026**.

Esta evidência registra a validação ponta a ponta do fluxo Bacula entre a VM interna
(EP126) e a DMZ (EP125), com backup sintético, perda simulada da origem, restore
isolado e prova de integridade por SHA-256.

Nenhuma senha, token, AppRole, unseal share, root token, conteúdo de `.env` ou
material secreto foi incluído neste documento.

## Escopo

Topologia validada:

```text
EP126 / Bacula Director
  -> EP125 / Bacula File Daemon
  -> TCP 9102
  -> TLS confirmado

EP125 / Bacula File Daemon
  -> EP126 / Bacula Storage Daemon
  -> TCP 9103

EP126 / Bacula Director
  -> EP126 / Bacula Storage Daemon
  -> rede Docker bacula-backend / TCP 9103
```

Identidades e recursos Bacula observados no runtime:

- Client interno: `conectaeduca-interna-fd`;
- Client DMZ: `conectaeduca-dmz-fd`;
- FileSet DMZ: `DmzSmokeSet`;
- Job de backup: `DmzSmokeBackup`;
- Job de restore: `DmzSmokeRestore`;
- Storage: `ConectaEducaStorage`;
- Pool de smoke: `DmzSmokePool`;
- Volume: `DmzSmokeVol001`.

## Pré-condição — correção do caminho do Director

O source of truth já continha, após o PR #78, o `bacula-uplink` no overlay
`compose.director-pgbouncer.yml`.

A promoção live foi executada de forma mínima, conectando somente o container do
Director à rede `conectaeduca-bacula_bacula-uplink`.

Resultado:

- `PASS=25 WARN=0 FAIL=0`;
- rollback não utilizado;
- mesmo container do Director antes/depois;
- `restart_count=0`;
- Director permaneceu `healthy`;
- Director alcançou `192.168.6.34:9102` a partir do próprio namespace de rede;
- Director preservou conectividade com Storage `:9103` pela rede backend;
- Storage, Catalog e PgBouncer permaneceram invariáveis.

Essa validação elimina o defeito que havia deixado o Director sem o caminho
cross-zone para o File Daemon da DMZ.

## Preflight cross-zone

O preflight read-only confirmou:

- EP126 no commit `5190ca99ccc6e8fd6ad4456b5392c6a773305589`;
- worktree limpo;
- Director, Storage, Catalog e PgBouncer `healthy`;
- Director e Storage presentes no `bacula-uplink`;
- Director -> EP125:9102 aprovado;
- Director -> Storage:9103 aprovado;
- dois Clients presentes no Catalog;
- recursos `DmzSmokeBackup`, `DmzSmokeRestore` e `DmzSmokeSet` presentes no
  runtime;
- nenhum segredo exposto no relatório.

O primeiro helper de preflight havia tentado consultar o PostgreSQL local sem
credencial. Como o Catalog já estava hardenizado para SCRAM também no socket
local, a consulta passwordless falhou corretamente. O helper seguinte passou a
usar o secret runtime já montado no container, somente dentro do processo do
container e sem imprimi-lo ou persistir seu conteúdo.

## Prova fresh de backup e restore

### 1. Preparação na EP125

Foi criado exclusivamente para o smoke test:

```text
/var/lib/conectaeduca/bacula-smoke-dmz/input/prova-dmz.bin
```

Resultado:

- `PASS=14 WARN=0 FAIL=0`;
- Bacula FD ativo e habilitado;
- executável efetivo: `/opt/bacula/bin/bacula-fd`;
- configuração efetiva: `/opt/bacula/etc/bacula-fd.conf`;
- `bacula-fd -t` aprovado com o binário real do serviço;
- TCP/9102 em escuta;
- EP125 -> EP126:9103 aprovado;
- artefato sintético criado com **8233 bytes**;
- SHA-256 original registrado.

SHA-256 do artefato sintético desta execução:

```text
02ea65315daa777a35e19d013b1cfba534420e05a89b255d9ce9704d75919efa
```

### Divergência entre o runtime acadêmico e o handoff versionado

Esta prova valida o **runtime efetivamente disponibilizado na EP125** durante a
atividade. Nesse host, o serviço ativo foi observado em:

```text
executável: /opt/bacula/bin/bacula-fd
configuração: /opt/bacula/etc/bacula-fd.conf
```

Esse layout não é produzido pelo instalador versionado
`scripts/implantacao/preparar_bacula_fd_ubuntu.sh`. O handoff reproduzível
previsto pelo repositório instala o pacote `bacula-fd` da distribuição e
materializa o template em:

```text
/etc/bacula/bacula-fd.conf.conectaeduca
```

Portanto, esta evidência **não afirma que a instalação `/opt/bacula` é
reproduzível a partir do Git**. Ela comprova o comportamento do runtime acadêmico
existente: conectividade, TLS, backup, perda simulada, restore e integridade.

A reprodutibilidade do File Daemon permanece um gate separado do handoff. Para
fechá-lo, deve ocorrer uma destas duas ações, sem inventar procedimento que não
foi observado:

1. provisionar uma VM limpa pelo instalador package-based do repositório e
   repetir o checkpoint cross-zone; ou
2. se a instalação `/opt/bacula` for definida pela infraestrutura acadêmica
   como baseline oficial, versionar o procedimento real de instalação/serviço
   antes de tratá-la como handoff reproduzível.

### 2. Backup na EP126

O Director comprovou comunicação com `conectaeduca-dmz-fd` via `bconsole` e
a sessão indicou TLS.

Novo Job:

```text
JobId=6
Name=DmzSmokeBackup
JobStatus=T
JobFiles=2
JobBytes=8233
JobErrors=0
```

Resultado do gate: `PASS=17 WARN=0 FAIL=0`.

### 3. Perda simulada da origem na EP125

Antes da remoção, o helper recalculou o hash e o tamanho da origem e exigiu
igualdade com o artefato preparado.

Resultado:

- hash pré-remoção idêntico ao original;
- tamanho pré-remoção = 8233 bytes;
- origem sintética removida;
- `PASS=12 WARN=0 FAIL=0`.

Essa etapa garante que o restore subsequente não possa ser confundido com uma
cópia ainda presente no source.

### 4. Restore na EP126

O backup JobId 6 foi revalidado no Catalog antes do restore.

Novo Job:

```text
JobId=7
Name=DmzSmokeRestore
JobStatus=T
JobFiles=2
JobBytes=8233
JobErrors=0
```

O restore foi explicitamente direcionado ao Client DMZ e a um diretório isolado,
sem cair em seleção interativa inesperada.

Resultado do gate: `PASS=17 WARN=0 FAIL=0`.

### 5. Verificação criptográfica na EP125

Antes de validar o arquivo restaurado, a origem continuava ausente.

Caminho isolado de restore:

```text
/var/lib/conectaeduca/bacula-smoke-dmz/restore/var/lib/conectaeduca/bacula-smoke-dmz/input/prova-dmz.bin
```

Comparação:

```text
SHA256 original:
02ea65315daa777a35e19d013b1cfba534420e05a89b255d9ce9704d75919efa

SHA256 restaurado:
02ea65315daa777a35e19d013b1cfba534420e05a89b255d9ce9704d75919efa

tamanho original: 8233
tamanho restaurado: 8233
```

Resultado:

- SHA-256 restaurado idêntico ao original;
- tamanho restaurado idêntico ao original;
- artefatos sintéticos removidos ao final;
- state local marcado como verificado;
- `PASS=15 WARN=0 FAIL=0`.

## Conclusão

O fluxo foi comprovado na seguinte sequência:

```text
artefato sintético na DMZ
        |
        v
backup cross-zone
        |
        v
origem removida
        |
        v
restore isolado na DMZ
        |
        v
SHA-256 restaurado == SHA-256 original
```

Portanto, o projeto demonstrou funcionalmente:

- conectividade cross-zone mínima;
- autenticação/cifra TLS entre Director e File Daemon DMZ;
- backup concluído;
- remoção real da origem de teste;
- restore concluído;
- integridade criptográfica do artefato restaurado;
- limpeza do material sintético após a prova.

Isso atende o critério central do contrato de restore sintético: **o backup só é
considerado válido após prova de recuperação e igualdade SHA-256**.

O resultado funcional cross-zone está fechado para o runtime acadêmico observado;
a reconciliação entre esse runtime e o instalador de handoff permanece registrada
como gate de reprodutibilidade separado.

## Risco residual — domínio de falha do Storage

No estado atual do laboratório, o Storage Daemon e parte dos dados protegidos
continuam na VM interna e no mesmo disco virtual.

O suporte informou que um segundo disco virtual não foi autorizado pelo professor
até esta validação. A decisão acadêmica será tratada separadamente.

Enquanto não houver destino em domínio de falha distinto, o controle comprovado
protege contra falhas lógicas e operacionais cobertas pelo fluxo de backup/restore,
mas **não elimina o risco de perda física total da VM/disco interno**.

Não deve ser usado loop device no mesmo disco como substituto cosmético de um
segundo domínio de falha.

## Cadeia de evidências locais

Os relatórios brutos permaneceram fora do Git e não contêm segredos. Seus hashes
SHA-256 nesta execução são:

| Evidência | SHA-256 |
|---|---|
| promoção do uplink do Director | `cf03e8f644f89a654156e95241e446e4c1af90bd7ebc2aef1c15ec473ed4bdf3` |
| preflight cross-zone v2 | `ec6c5474daaa5fc9d1e895430c607a69eb8f8534116da01fbf0f1991df46e607` |
| prepare EP125 v3 | `48b5c4d27e42fdd75db90eb67f42770a41adb9a6e29d72e69ee3bad6b311da60` |
| backup EP126 | `05e9ee05ffa3e918b302b200e6a57dba1fe72a64e4598ca1ffb3887a9ce4e2f3` |
| remoção controlada EP125 | `5893a6e3c1fd7de8ca60d4b9f55f2827a1261b5f2006a1a833cd11b4bdb5a8e1` |
| restore EP126 | `e79ae4f9e2491a186a225b0861482d703324a2bf527e121060e49c65d6b93063` |
| verificação final EP125 | `dea206d71cb9603d6cde354716379bd8b282b899f476e97e6fe8f03600fb8ef3` |

Arquivos brutos não são necessários para reproduzir a arquitetura; eles servem
como cadeia local de evidência da execução de 14/09/2026.
