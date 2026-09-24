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
- publicação somente em `127.0.0.1:9098`;
- runtime Compose materializado fora do Git e protegido em modo `0600`;
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

O fechamento permanece pendente apenas para TLS/finalização. O precheck TLS
confirmou `require_secure_transport=ON`, TLS 1.2/1.3 e material PKI válido,
mas `PMA_SSL`/`PMA_SSL_VERIFY` ainda não estão explícitos. O certificado
servidor atual possui SAN `IP:192.168.6.50,DNS:ep126-pucpr`; ele não contém
`DNS:mariadb`. Assim, habilitar verificação de hostname contra
`PMA_HOST=mariadb` sem ajustar o certificado/nome produziria mismatch.

O Compose sanitizado definitivo só deve ser versionado depois da decisão TLS,
para não promover ao repositório uma configuração sabidamente intermediária.

## Contrato de segurança do container

A versão final deverá obedecer aos seguintes invariantes:

- publicação somente em loopback, preferencialmente `127.0.0.1:9098`;
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
existente. A GUI publica somente `127.0.0.1:9098`; nenhuma porta adicional do
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

Precheck live em 24/09/2026:

- phpMyAdmin: running/healthy;
- `PMA_SSL`, `PMA_SSL_VERIFY` e `PMA_SSL_CA`: ainda não definidos;
- MariaDB: `require_secure_transport=ON`;
- versões permitidas: TLS 1.2 e TLS 1.3;
- CA: `/run/secrets/mariadb_tls_ca`;
- certificado: `/run/secrets/mariadb_tls_cert`;
- chave: `/run/secrets/mariadb_tls_key`;
- origem PKI no host descoberta em `/etc/conectaeduca/pki/mariadb`;
- certificado servidor: CN `192.168.6.50`, SAN
  `IP:192.168.6.50,DNS:ep126-pucpr`.

Decisão pendente: tornar o TLS phpMyAdmin → MariaDB explícito e verificável sem
relaxar hostname/CA. Como `PMA_HOST=mariadb` não aparece no SAN atual, a
correção preferida é alinhar nome/certificado antes de ativar
`PMA_SSL_VERIFY=1`.

O acesso navegador → GUI também deve receber decisão explícita: HTTPS local ou
aceitação documentada de HTTP exclusivamente em loopback. Para a apresentação,
HTTPS é preferível.

## Critério de fechamento atualizado

GUI-01C poderá ser marcado como DONE quando:

1. TLS phpMyAdmin → MariaDB estiver explícito e sem fallback/avisos;
2. a decisão de HTTPS navegador → GUI estiver implementada ou formalmente
   documentada;
3. login + SELECT permitido + DML negado forem repetidos após a mudança TLS;
4. o Compose sanitizado final, sem senha/hash, estiver versionado;
5. a evidência final registrar MariaDB sem recreate/restart.
