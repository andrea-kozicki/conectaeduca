# Evidência — hardening interno do MariaDB / EP126 (07/09/2026)

## Objetivo

Consolidar, sem expor segredos ou material de autenticação, os controles observados no serviço MariaDB 12.3.2 em execução na EP126.

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

Pontos que permaneceram para análise:

- conta `conectaeduca_app` usa `Host='%'`; a origem real da conexão deve ser observada antes de eventual restrição;
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

## Interpretação de `secure_file_priv`

`secure_file_priv` permaneceu vazio, porém a conta da aplicação não possui o privilégio global `FILE`. No estado observado, isso constitui um **controle compensatório relevante**, pois a identidade usada pela aplicação não pode executar as principais operações de arquivo dependentes desse privilégio. A configuração do parâmetro ainda pode ser endurecida posteriormente como defesa em profundidade, desde que validada contra requisitos funcionais.

## Origem da aplicação

Nenhuma conexão ativa de `conectaeduca_app` foi capturada na janela da segunda auditoria. Por isso, o `Host='%'` **não deve ser restringido ainda com base somente nessa observação**. A mudança ficará condicionada à captura confiável da origem real da conexão da aplicação e teste funcional posterior.

## Proteção da evidência

O relatório bruto da segunda auditoria incluiu uma representação de autenticação na saída de `SHOW GRANTS`. Por política do projeto, **esse material não é reproduzido neste documento e o relatório bruto não deve ser versionado no Git**. A rastreabilidade é mantida pelo SHA-256 do arquivo local e por esta síntese sanitizada.

Nenhuma senha em claro, token, chave privada ou conteúdo de secret foi incluído nesta evidência.

## Estado atual

**MariaDB — serviço: hardening avançado / validação parcial.**

Restam principalmente:

1. observar a origem real de `conectaeduca_app` antes de decidir eventual restrição do `Host`;
2. decidir se `secure_file_priv` será explicitamente configurado ou mantido com o controle compensatório atual;
3. após qualquer alteração, executar configtest/restart controlado, teste funcional aplicação→banco e novo relatório de evidência.