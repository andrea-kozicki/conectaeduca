# GUI-01C — phpMyAdmin read-only para demonstração

## Objetivo

Adicionar uma interface gráfica de consulta ao MariaDB da EP126 para a demonstração
acadêmica, sem transformar o phpMyAdmin em uma superfície administrativa do banco.

O objetivo principal não é apenas "abrir o phpMyAdmin". A evidência deve demonstrar
**menor privilégio** de forma visual:

1. autenticar com a identidade técnica `teste`;
2. consultar o schema `conectaeduca`;
3. demonstrar leitura permitida;
4. demonstrar que operações de escrita continuam negadas;
5. preservar o MariaDB atual sem recriação nem mudança de grants administrativos.

## Estado operacional atual

O GUI-01C avançou além do precheck e está live na EP126 em 24/09/2026.

Estado comprovado:

- imagem oficial `phpmyadmin:5.2.3-apache` fixada por digest
  `sha256:9e915766488a0f603183367a4b51f5db6309ea801f3eaa25138a83815772b14f`;
- rede Docker reutilizada: `conectaeduca-mariadb_backend`;
- IP dedicado: `172.18.255.254`;
- publicação final somente em `127.0.0.1:9443`, com HTTPS; o fallback HTTP `9098` foi removido;
- runtime Compose protegido em modo `0600`; o Compose final sanitizado foi versionado em `deploy/interna/mariadb/compose.phpmyadmin.yml`;
- `cap_drop: ALL` com somente `CHOWN`, `DAC_OVERRIDE`, `SETGID` e
  `SETUID` adicionadas;
- `no-new-privileges:true`;
- sem `privileged`, Docker socket ou host network;
- Apache master permanece root para bootstrap/bind e workers efetivamente
  executam como `www-data` com `CapEff=0` e `NoNewPrivs=1`;
- root filesystem read-only da imagem stock foi testado e demonstrado
  incompatível com o entrypoint/Apache, portanto a exceção é explícita e
  baseada em evidência;
- principal SQL `teste@172.18.255.254` criado com a mesma autenticação da
  identidade acadêmica já existente, sem registrar senha/hash;
- privilégio do novo principal limitado a `SELECT` em
  `conectaeduca.vw_pentest_oportunidades_publicas`;
- identidade fonte `teste@192.168.6.34` permaneceu inalterada;
- MariaDB preservado sem recreate/restart;
- login WebGUI + `SELECT ... LIMIT 5`: PASS;
- tentativa segura `DELETE ... WHERE 1=0`: negada pelo MariaDB com erro
  #1142, comprovando enforcement no banco.

O fechamento TLS foi concluído em 24/09/2026. A conexão phpMyAdmin → MariaDB usa
`PMA_SSL=1`, `PMA_SSL_VERIFY=1` e CA explícita, com certificado do MariaDB
contendo `DNS:mariadb`. O navegador acessa a GUI somente por
`https://localhost:9443`, com certificado local verificado. O fallback HTTP
`127.0.0.1:9098` foi removido após prova manual e finalização controlada.

O Compose final sanitizado foi promovido ao repositório em
`deploy/interna/mariadb/compose.phpmyadmin.yml`, sem senha, hash ou chave
privada versionada.

## Contrato de segurança do container

A versão final deverá obedecer aos seguintes invariantes:

- publicação somente em loopback via HTTPS em `127.0.0.1:9443`;
- sem `privileged`;
- sem Docker socket;
- sem `network_mode: host`;
- sem senha de banco versionada ou embutida no Compose;
- autenticação humana pelo login `teste` na própria WebGUI;
- imagem oficial fixada por digest antes da promoção;
- root filesystem read-only quando compatível com a imagem;
- `cap_drop: ALL` quando compatível com o bootstrap da imagem;
- `no-new-privileges:true`;
- tmpfs somente para caminhos realmente graváveis necessários à aplicação;
- conexão apenas à rede Docker mínima que permita alcançar o MariaDB;
- nenhuma publicação direta adicional do MariaDB;
- nenhum recreate do container MariaDB para instalar a GUI.

Se algum controle de hardening for incompatível com a imagem oficial, a exceção deve
ser demonstrada em candidato isolado e documentada; não deve ser relaxada no escuro.

## Identidade

A GUI deve usar a identidade técnica `teste`, já definida no projeto como principal
humano de baixo privilégio para demonstração/pentest.

A conta de aplicação `teste@pucparana.com` não deve ser reutilizada como identidade
SQL do phpMyAdmin.

A conta técnica de backup `conectaeduca_bacula_backup` também não deve ser usada
na GUI: ela existe exclusivamente para o produtor de dump do Bacula.

## Testes obrigatórios

### Positivo

Pela WebGUI:

- login com `teste`;
- seleção do schema `conectaeduca`;
- leitura de tabela permitida;
- evidência visual da consulta.

### Negativo

Pela WebGUI, usando apenas dado descartável/consulta que não modifique estado útil:

- tentativa de `INSERT`, `UPDATE` ou `DELETE`;
- operação deve ser recusada pelo MariaDB por privilégio insuficiente.

O teste negativo deve provar enforcement no banco, não apenas esconder botões da UI.

## Rede

A rede live reutilizada é `conectaeduca-mariadb_backend`. O phpMyAdmin usa o
IP dedicado `172.18.255.254`, enquanto o MariaDB permanece no runtime já
existente. A GUI publica somente `127.0.0.1:9443` via HTTPS; nenhuma porta adicional do
MariaDB foi aberta e nenhuma bridge arbitrária foi adicionada.

## Imagem

A imagem validada é:

```text
phpmyadmin@sha256:9e915766488a0f603183367a4b51f5db6309ea801f3eaa25138a83815772b14f
```

Plataforma observada: `linux/amd64`. O pin por digest deve ser preservado no
Compose final.

## Precheck

Na EP126:

```bash
cd /opt/conectaeduca
python3 scripts/evidencias/gui01c_phpmyadmin_precheck.py
```

A evidência é gravada no `$HOME`:

```text
conectaeduca-gui01c-phpmyadmin-precheck-<host>-<UTC>.txt
```

O precheck coleta apenas metadados necessários:

- estado/health do MariaDB;
- redes e IPs do container;
- bindings de porta;
- existência e privilégios observáveis da identidade `teste`;
- disponibilidade de `127.0.0.1:9098`;
- invariantes exigidos para o APPLY.

Valores de senha, hashes de autenticação e Docker secrets não são impressos.

## Critério para escrever o APPLY

O APPLY GUI-01C permanece bloqueado até existir evidência de:

- MariaDB healthy;
- rede Docker exata identificada;
- porta local candidata livre;
- identidade `teste` presente com perfil de leitura compatível;
- imagem phpMyAdmin oficial escolhida e fixada por digest;
- caminho de rollback sem recreate do MariaDB.

Só depois disso o projeto deve versionar o Compose final e executar a prova
read-only visual.


## TLS — gate final

Fechado em 24/09/2026.

- phpMyAdmin → MariaDB: TLS explícito com verificação de CA/hostname;
- certificado MariaDB alinhado ao alias `mariadb`;
- navegador → phpMyAdmin: HTTPS local em `https://localhost:9443`;
- CA local confiada no perfil Firefox dedicado para demonstração;
- fallback HTTP 9098 removido;
- MariaDB preservado sem recreate/restart;
- logs sem marcadores de transporte inseguro.

## Critério de fechamento atualizado

GUI-01C foi marcado como DONE em 24/09/2026 porque:

1. TLS phpMyAdmin → MariaDB ficou explícito e verificável;
2. HTTPS navegador → GUI foi implementado e validado;
3. login + SELECT permitido + DML negado foram repetidos após a mudança TLS;
4. o Compose sanitizado final foi versionado sem senha/hash/chave privada;
5. a evidência final registrou MariaDB sem recreate/restart;
6. o fallback HTTP 9098 foi removido e o smoke manual HTTPS-only passou.

## Reteste manual após TLS explícito

Após a promoção de `PMA_SSL=1`, `PMA_SSL_VERIFY=1` e da CA pública do
MariaDB, foi executado novo ciclo manual na EP126:

- login `teste`: PASS;
- ausência dos avisos vermelhos de fallback/insecure transport: PASS;
- `SELECT` na view permitida: PASS;
- `DELETE ... WHERE 1=0`: negado novamente pelo MariaDB;
- `docker logs --since 10m conectaeduca-phpmyadmin` filtrado por
  `warning|error|3159|insecure transport|ssl|tls`: nenhum alerta relevante.

Com isso, a camada phpMyAdmin → MariaDB fica encerrada com TLS explícito e
verificado por CA/hostname. Resta somente a decisão/implementação de HTTPS no
trecho navegador → phpMyAdmin e a promoção do Compose final sanitizado.


## Prova manual HTTPS navegador → phpMyAdmin

Em 24/09/2026, após o stage HTTPS v4 com entrypoint nativo preservado, foi
executada a prova manual pelo perfil Firefox dedicado:

- abertura de `https://localhost:9443/` sem aviso grave de certificado: PASS;
- login com o principal `teste`: PASS;
- `SELECT * FROM conectaeduca.vw_pentest_oportunidades_publicas LIMIT 5`: PASS;
- tentativa de `DELETE FROM conectaeduca.oportunidades WHERE 1 = 0`: DENY PASS,
  com bloqueio no MariaDB;
- logs recentes do phpMyAdmin: somente aviso informativo de startup normal do
  Apache/OpenSSL, sem `warning`, `error`, `fatal`, `3159` ou
  `insecure transport` relevantes.

Os avisos visuais do phpMyAdmin sobre configuration storage incompleto e sobre
ausência de coluna exclusiva na seleção não representam falha TLS nem concessão
de privilégio DML. A autorização efetiva permanece no banco e foi comprovada
pelo DENY do DELETE.

Com isso, a cadeia navegador → phpMyAdmin → MariaDB está funcional sob TLS
verificado, restando apenas a retirada do fallback HTTP 9098 e o versionamento
do Compose final sanitizado antes de marcar GUI-01C como DONE.


## Finalização HTTPS-only

Em 24/09/2026, o fallback HTTP em `127.0.0.1:9098` foi removido por finalizador
controlado com rollback. O runtime final ficou somente com
`127.0.0.1:9443 -> 8443/tcp`.

A validação automática confirmou:

- `docker inspect`: `80/tcp` sem publicação e `8443/tcp` publicado somente
  em loopback na porta 9443;
- resposta HTTP 200 sobre HTTPS;
- TLSv1.3 com `Verification: OK` e `Verified peername: localhost`;
- arquivos de runtime do entrypoint nativo presentes;
- configuração phpMyAdmin -> MariaDB preservada com
  `SSL=1`, `SSL_VERIFY=1` e CA explícita;
- logs sem marcadores fatais ou de transporte inseguro;
- MariaDB invariável, sem restart/recreate;
- candidato de Compose final sanitizado criado com SHA-256
  `6affbf67959ed4c4b670d29d1a6b9834e748f86eb667a7a60350649ecf845900`.

Resultado: `PASS=25 WARN=0 FAIL=0`,
`GUI01C_HTTPS_ONLY_READY=YES`.

O smoke manual pós-finalização também passou: a GUI abriu em
`https://localhost:9443` sem aviso de certificado, o login `teste` funcionou,
o SELECT permitido permaneceu funcional e o DELETE continuou negado. O Compose
final sanitizado foi versionado em
`deploy/interna/mariadb/compose.phpmyadmin.yml`.

**GUI-01C = DONE em 24/09/2026.**
