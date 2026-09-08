# Evidência — hardening interno do MariaDB / EP126 (07/09/2026)

## Objetivo

Consolidar, sem expor segredos ou material de autenticação, os controles observados no serviço MariaDB 12.3.2 em execução na EP126 e registrar a evolução até a restrição da origem da conta de aplicação.

## Auditoria 1 — baseline do serviço

Resultado do relatório operacional:

`PASS=25 WARN=3 FAIL=0`

SHA-256 do relatório local:

`dd493ec918579790ebfc66080d01c45990886bc923f09a60e383a228ef76bd6b`

Controles confirmados:

- MariaDB `12.3.2` em estado saudável;
- `require_secure_transport=ON`;
- TLS disponível (`have_ssl=YES`);
- protocolos observados: TLS 1.2 e TLS 1.3;
- sessões TLS já concluídas pelo servidor;
- porta `3306` publicada somente em `192.168.6.50`;
- somente `root@localhost`, sem conta root remota;
- ausência de usuários anônimos;
- ausência do banco padrão `test`;
- nenhuma conta de aplicação com privilégios globais além de `USAGE`;
- `conectaeduca_app` limitada ao schema `conectaeduca` com `SELECT`, `INSERT`, `UPDATE` e `DELETE`;
- `local_infile=OFF`;
- `skip_name_resolve=ON`;
- `general_log=OFF`.

Pontos que permaneceram para análise nessa etapa:

- conta `conectaeduca_app` ainda usava `Host='%'`;
- `secure_file_priv` apareceu vazio/indisponível;
- nenhum plugin interno de política de senha foi identificado, sendo necessário avaliar o controle externo por secrets.

## Auditoria 2 — controles compensatórios e privilégios

Resultado do relatório operacional:

`PASS=16 WARN=1 FAIL=0`

SHA-256 do relatório local:

`1f43edeb168b50246880e0776bfb43dabe6a211754acdd490b32fa9943d5ca5a`

Controles adicionais confirmados:

- privilégios administrativos sensíveis globais foram observados somente para `root@localhost`;
- nenhuma conta não-root possui privilégio administrativo sensível global;
- `conectaeduca_app` não possui `FILE`;
- `conectaeduca_app` não possui `GRANT OPTION`;
- o grant efetivo permanece restrito a CRUD no schema `conectaeduca`;
- `mariadb_root_password` existe como secret externo e possui comprimento de 64 caracteres;
- `conectaeduca_db_password` existe como secret externo e possui comprimento de 64 caracteres;
- nenhuma instrução SQL mutante foi executada durante a auditoria;
- MariaDB permaneceu respondendo após os testes.

## Auditoria 3 — decisão sobre `secure_file_priv` e preparação da restrição de origem

Resultado:

`PASS=12 WARN=2 FAIL=0`

SHA-256 do relatório local:

`6fb1614bf4097d77e6c829dc368ce0d2f17356046f3245cab4f225d052e161f8`

A auditoria reconfirmou:

- `require_secure_transport=ON`;
- `local_infile=OFF`;
- `skip_name_resolve=ON`;
- `secure_file_priv=<NULL>`;
- `conectaeduca_app@'%'` sem privilégio `FILE`;
- `conectaeduca_app@'%'` sem `GRANT OPTION`.

Como `tcpdump` não estava instalado na EP126, a origem TCP não foi alterada com base apenas nessa execução.

## Auditoria 4 — origem real da aplicação

Resultado:

`PASS=19 WARN=2 FAIL=0`

SHA-256 do relatório local:

`9caa998bf44476c4b53130f5540a5c351be2c97a7bf8c2f2b8b2794ef5e08e6a`

Durante uma janela com 30 requisições HTTP válidas à aplicação, o `PROCESSLIST` do próprio MariaDB observou uma sessão autenticada como:

- usuário: `conectaeduca_app`;
- origem: `192.168.6.34` (EP125 / DMZ);
- schema: `conectaeduca`.

Essa observação forneceu evidência suficiente para substituir a origem genérica `%` pelo IP efetivamente validado da aplicação.

## Mudança controlada — restrição da conta de aplicação

Resultado:

`PASS=23 WARN=1 FAIL=0`

SHA-256 do relatório local:

`219acb645bfd8a7baa71ae42d82749af9f36f628cf61c464e13f5e8b2752043e`

Mudança aplicada no runtime:

`conectaeduca_app@'%'` → `conectaeduca_app@'192.168.6.34'`

A alteração usou `RENAME USER`, preservando a autenticação e os grants existentes sem expor hash de senha. O estado pós-mudança foi validado com:

- conta wildcard removida (`wildcard=0`);
- conta restrita presente (`restrita=1`);
- privilégios de schema preservados exatamente em `DELETE`, `INSERT`, `SELECT`, `UPDATE`;
- nenhum privilégio global adicional;
- cinco novas requisições HTTP `200` após a alteração;
- autenticação local via socket com a conta da aplicação negada, como esperado após a restrição por Host;
- gate final com `HTTP=200` e aplicação operacional;
- rollback preparado em arquivo SQL separado, sem segredos, mas não executado porque a validação foi aprovada.

O único `WARN` decorreu de o `PROCESSLIST` não capturar novamente a sessão curta durante a validação pós-mudança; isso não invalidou o gate porque a conta estava efetivamente restrita a `192.168.6.34` e a aplicação conseguiu criar novas conexões funcionais após o encerramento/renovação das sessões.

## Interpretação de `secure_file_priv`

`secure_file_priv` permanece `<NULL>` no estado observado. A conta da aplicação, contudo, não possui o privilégio global `FILE` nem `GRANT OPTION`, usa apenas CRUD no schema da aplicação, opera com `local_infile=OFF` e exige transporte seguro. Esses controles constituem defesa compensatória suficiente para o escopo atual.

A decisão desta fase é **não alterar `secure_file_priv` apenas para aumentar a quantidade de controles configurados**. O parâmetro permanece como risco residual documentado e deve ser reavaliado se a identidade da aplicação ganhar requisitos de importação/exportação de arquivos ou novos privilégios.

## Reprodutibilidade em novos volumes

O arquivo declarativo `deploy/interna/mariadb/20-minimos-privilegios.sql` foi atualizado para reproduzir a restrição de origem em novos volumes:

1. renomeia a conta inicialmente criada como `conectaeduca_app@'%'` para `conectaeduca_app@'192.168.6.34'`;
2. revoga privilégios amplos/`GRANT OPTION` da conta restrita;
3. concede apenas `SELECT`, `INSERT`, `UPDATE` e `DELETE` sobre `conectaeduca`.

Se o IP/topologia da EP125 mudar, essa allowlist deve ser revalidada antes de recriar o banco.

## Proteção da evidência

Relatórios brutos que contenham representação de autenticação não são versionados. Nenhuma senha em claro, token, chave privada ou conteúdo de secret é reproduzido neste documento. A rastreabilidade operacional é mantida pelos SHA-256 dos relatórios locais e pelo histórico Git/PR.

## Estado atual

**MariaDB — serviço: ✅ VALIDADO para o baseline atual da arquitetura.**

Controles relevantes comprovados em conjunto:

- TLS obrigatório e TLS 1.2/1.3;
- sem root remoto, sem usuário anônimo e sem banco `test`;
- `local_infile=OFF`, `skip_name_resolve=ON` e `general_log=OFF`;
- aplicação sem privilégios globais, `FILE` ou `GRANT OPTION`;
- CRUD apenas no schema `conectaeduca`;
- origem da conta da aplicação restrita à EP125 `192.168.6.34`;
- secrets externos fortes;
- porta 3306 exposta apenas no IP interno da EP126;
- aplicação permaneceu funcional após a restrição;
- rollback lógico disponível para a alteração de origem.

Risco residual principal: `secure_file_priv=<NULL>` mantido com os controles compensatórios documentados. Revalidar a allowlist de Host após qualquer mudança de endereço/topologia da EP125.