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

O contrato declarativo foi versionado e o **precheck live foi executado na EP126
em 24/09/2026**.

Resultado observado:

- host esperado e repositório limpo: PASS;
- MariaDB running/healthy: PASS;
- rede descoberta: `conectaeduca-mariadb_backend`;
- identidade humana SQL `teste` presente;
- porta candidata `127.0.0.1:9098` livre;
- container criado: 0;
- rede alterada: 0;
- mutação de banco: 0;
- valor de segredo impresso: 0;
- `FINAL=PASS_PRECHECK`;
- `APPLY_AUTHORIZED=NO`.

O `APPLY_AUTHORIZED=NO` é intencional: o próximo gate é escolher a imagem
oficial, fixá-la por digest, renderizar/validar o Compose candidato e somente
então executar APPLY controlado.

Até esse gate, esta etapa:

- não instala phpMyAdmin;
- não cria container;
- não altera rede Docker;
- não altera MariaDB;
- não cria usuário SQL;
- não lê nem imprime senha.

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

O nome da rede Docker do MariaDB **não é hardcoded nesta etapa**.

O script `scripts/evidencias/gui01c_phpmyadmin_precheck.py` descobre a rede real do
container MariaDB por `docker inspect`. O Compose final deverá reutilizar apenas a
rede necessária e não deve adicionar uma bridge arbitrária ao MariaDB.

## Imagem

Esta PR não escolhe tag flutuante nem digest por antecipação.

Antes do APPLY:

1. escolher a imagem oficial phpMyAdmin;
2. inspecionar arquitetura e comportamento;
3. fixar a referência por digest;
4. validar o candidato isolado;
5. somente então versionar/promover o Compose final.

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
